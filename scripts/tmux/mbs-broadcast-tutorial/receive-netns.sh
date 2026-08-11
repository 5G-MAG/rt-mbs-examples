#!/usr/bin/env bash
#
# receive-netns.sh -- run the 5G NR MBS Broadcast RECEIVE chain (UE + rt-mbs-client
# + rt-mbs-application) in a dedicated network namespace ("mbs-rx"), connected to
# the transmit side (gNB, in the root namespace) by a veth pair.
#
# This split is NOT cosmetic -- confirmed live: putting the gNB and UE in the same
# namespace and pointing their ZMQ RF device_args at 127.0.0.1 deadlocks (the UE
# retransmits PRACH forever, the gNB never detects a single preamble), even on an
# otherwise-unmodified, previously live-verified commit, and even using the
# pre-built reference Docker images (ghcr.io/5g-mag/gnb_with_mbs / ue_with_mbs) --
# so it isn't a code regression either. srsRAN_Project's ZMQ TX/RX channels are
# hardcoded ZMQ_REP/ZMQ_REQ (a strict alternating request-reply pattern), which
# is far more scheduling-latency-sensitive than a fire-and-forget PUB/SUB link
# would be; separate namespaces + a veth is the pattern both the rt-mbs-examples
# Docker deployment and rt-mbms-examples' own tmux tutorial use for exactly this
# reason. See conf/gnb.yaml's matching comment.
#
#   sudo ./receive-netns.sh start     # launch UE/client/application in the netns
#   sudo ./receive-netns.sh stop      # tear the whole netns + veth down
#
# Pair with transmit.sh, which brings up everything on the network side (5GC,
# MBSF, MBSTF, rt-mbs-application-provider, gNB).
#
# BUG FIX (found live, 2026-08-11): this script used to assume it shared ONE veth
# pair (veth-mbs-root/veth-mbs-rx, 10.90.0.1/10.90.0.3) with transmit.sh, created
# idempotently by whichever script ran first -- true back when the gNB ran directly
# in the root namespace. transmit.sh now runs the gNB in its own 'mbs-gnb' netns and
# creates a veth pair with THESE SAME NAMES entirely *inside* mbs-gnb, paired to
# mbs-rx, for the gNB<->UE ZMQ RF-simulation link -- a different, unrelated pair
# serving a different purpose. Since this script's own idempotency check
# (`ip link show "$VETH_ROOT"`) only ever looks in the HOST namespace, it never
# sees transmit.sh's mbs-gnb-side pair and always creates a second, redundant one
# -- whose mbs-rx end then fails to move into mbs-rx at all ("Error: An interface
# with the same name exists in the target netns", since transmit.sh's real
# veth-mbs-rx already occupies that name there), leaving a broken, host-stranded
# pair and NO actual route from the host into mbs-rx. Confirmed live: this made
# rt-mbs-client and rt-mbs-application completely unreachable from the host every
# single run. Fixed by giving this script's host<->mbs-rx pair its own, distinct
# names (below) so it never collides with transmit.sh's internal mbs-gnb<->mbs-rx
# pair -- the two pairs are genuinely independent and both need to exist.
#
# Topology:
#   root netns : 5GC, MBSF, MBSTF, rt-mbs-application-provider, gNB (ZMQ tx on
#                tcp://*:2000)                                -> via ./transmit.sh
#   mbs-gnb    : gNB -- connected to mbs-rx by transmit.sh's OWN veth-mbs-root/
#                veth-mbs-rx pair (10.90.0.1/10.90.0.3), for the ZMQ RF-simulation
#                link only. Not touched by this script.
#   mbs-rx     : UE (ZMQ tx on tcp://*:2001), rt-mbs-client, rt-mbs-application --
#                reachable from the HOST via THIS script's own, separate veth pair.
#
# Reach the receive side from the host at 10.90.1.2 (a distinct subnet from the
# gNB<->UE 10.90.0.x pair above, on purpose -- see the veth pair naming below):
#   rt-mbs-application UI : http://10.90.1.2:3050
#   rt-mbs-client local API : http://10.90.1.2:3031/mbs-client-api
#
set -u
[ "$(id -u)" = 0 ] || { echo "Run with sudo: sudo $0 ${1:-start}"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="${CONF:-$SCRIPT_DIR/conf}"

NS="${RX_NS:-mbs-rx}"
# Distinct names/subnet from transmit.sh's own veth-mbs-root/veth-mbs-rx pair (which
# lives entirely inside mbs-gnb<->mbs-rx, for the ZMQ RF-simulation link) -- see the
# BUG FIX note above. This pair is host<->mbs-rx only, for reaching the local APIs.
ROOT_IP="${VETH_HOST_IP:-10.90.1.1}"
RX_IP="${VETH_HOSTRX_IP:-10.90.1.2}"
MASK="${VETH_MASK:-24}"
VETH_ROOT="${VETH_HOST:-veth-mbs-h2rx}"
VETH_RX="${VETH_HOSTRX:-veth-mbs-rx2h}"

USER_NAME="${SUDO_USER:-$(logname 2>/dev/null || echo "$USER")}"
UH="$(getent passwd "$USER_NAME" | cut -d: -f6)"

UE_DIR="${UE_DIR:-$UH/Repos/srsRAN_4G_mbs}"
CLIENT_DIR="${CLIENT_DIR:-$UH/Repos/rt-mbs/rt-mbs-client}"
APP_DIR="${APP_DIR:-$UH/Repos/rt-mbs/rt-mbs-application}"

UE_BIN="$UE_DIR/build/srsue/src/srsue"
UE_CONF="${UE_CONF:-$CONF/ue.conf}"
CLIENT_BIN="$CLIENT_DIR/build/mbs-client"
CLIENT_CONF="${CLIENT_CONF:-$CLIENT_DIR/run/rt-mbs-client.conf}"

LOG="${LOG_DIR:-$UH/.local/state/mbs-broadcast-tutorial}"

nsrun() { # nsrun <Name> <workdir> <command string> -- run as the unprivileged user
  local name="$1" workdir="$2"; shift 2
  ip netns exec "$NS" runuser -u "$USER_NAME" -- \
    env HOME="$UH" PATH="/usr/local/bin:/usr/bin:/bin" \
    nohup bash -c "cd '$workdir' && exec $*" < /dev/null > "$LOG/$name.log" 2>&1 &
  disown
  echo "  $name launched in netns '$NS'  (log: $LOG/$name.log)"
}

nsrun_root() { # nsrun_root <Name> <workdir> <command string> -- run as ROOT
  # The UE needs CAP_NET_ADMIN to create/configure its MBS TUN device
  # (tun_srsue, srsue's gw::add_mbs_port()) -- under runuser (unprivileged) that
  # fails outright. The log is chowned back to the user after.
  local name="$1" workdir="$2"; shift 2
  ip netns exec "$NS" \
    env HOME="$UH" PATH="/usr/local/bin:/usr/bin:/bin" \
    nohup bash -c "cd '$workdir' && exec $*" < /dev/null > "$LOG/$name.log" 2>&1 &
  disown
  chown "$USER_NAME": "$LOG/$name.log" 2>/dev/null || true
  echo "  $name launched in netns '$NS' (root, for the MBS TUN device)  (log: $LOG/$name.log)"
}

start() {
  command -v ip >/dev/null || { echo "iproute2 ('ip') required"; exit 1; }
  [ -x "$UE_BIN" ]     || { echo "UE binary not found/executable: $UE_BIN (build srsRAN_4G_mbs)"; exit 1; }
  [ -x "$CLIENT_BIN" ] || { echo "rt-mbs-client binary not found/executable: $CLIENT_BIN (build rt-mbs-client)"; exit 1; }
  [ -f "$APP_DIR/app.js" ] || { echo "not found: $APP_DIR/app.js"; exit 1; }
  [ -f "$UE_CONF" ]     || { echo "UE config not found: $UE_CONF"; exit 1; }
  [ -f "$CLIENT_CONF" ] || { echo "rt-mbs-client config not found: $CLIENT_CONF"; exit 1; }
  mkdir -p "$LOG"; chown "$USER_NAME": "$LOG" 2>/dev/null || true

  # ue.conf's log filenames are templated with @@LOG_DIR@@ (libconfig has no shell-style
  # expansion), since a committed config file can't hardcode a path under any particular
  # user's home directory. Render a runtime copy with the placeholder substituted, and
  # point UE_CONF at that instead of the checked-in template, so a fresh checkout works
  # on any machine/username unmodified.
  if [ "$UE_CONF" = "$CONF/ue.conf" ]; then
    RENDERED_UE_CONF="$LOG/ue.rendered.conf"
    sed "s#@@LOG_DIR@@#$LOG#g" "$UE_CONF" > "$RENDERED_UE_CONF"
    chown "$USER_NAME": "$RENDERED_UE_CONF" 2>/dev/null || true
    UE_CONF="$RENDERED_UE_CONF"
  fi

  # 1) namespace + this script's own host<->mbs-rx veth pair -- idempotent, safe to
  #    call repeatedly. This is independent of transmit.sh's own veth-mbs-root/rx
  #    pair (see the BUG FIX note at the top of this file).
  ip netns add "$NS" 2>/dev/null || true
  ip netns exec "$NS" ip link set lo up
  if ! ip link show "$VETH_ROOT" >/dev/null 2>&1; then
    ip link add "$VETH_ROOT" type veth peer name "$VETH_RX"
    ip link set "$VETH_RX" netns "$NS"
  fi
  ip addr add "$ROOT_IP/$MASK" dev "$VETH_ROOT" 2>/dev/null || true
  ip link set "$VETH_ROOT" up
  ip netns exec "$NS" ip addr add "$RX_IP/$MASK" dev "$VETH_RX" 2>/dev/null || true
  ip netns exec "$NS" ip link set "$VETH_RX" up

  echo "Starting receive chain in netns '$NS' (gNB TX expected at ${ROOT_IP}:2000) ..."
  nsrun_root UE "$(dirname "$UE_CONF")" "'$UE_BIN' '$UE_CONF'"

  # The UE creates tun_srsue on successful registration/PDU session establishment
  # with a hardcoded 172.16.0.2 address (srsue's gw::add_mbs_port()) -- wait for
  # it before starting rt-mbs-client, which binds its FLUTE receiver there.
  echo "Waiting for tun_srsue (the UE creates it once attach/PDU session completes) ..."
  tun_ok=0
  for _ in $(seq 1 60); do
    if ip netns exec "$NS" ip link show tun_srsue >/dev/null 2>&1; then tun_ok=1; break; fi
    sleep 1
  done
  if [ "$tun_ok" = 1 ]; then
    echo "  tun_srsue is up."
  else
    echo "  WARNING: tun_srsue never appeared -- check UE.log for attach failures before rt-mbs-client starts."
  fi

  nsrun rt-mbs-client "$(dirname "$CLIENT_BIN")" "'$CLIENT_BIN' '$CLIENT_CONF'"
  sleep 2
  nsrun rt-mbs-application "$APP_DIR" "node app.js"

  echo
  echo "Receive chain is in netns '$NS'. From the host:"
  echo "  rt-mbs-application UI  : http://${RX_IP}:3050"
  echo "  rt-mbs-client local API: http://${RX_IP}:3031/mbs-client-api"
  echo "Tear down with: sudo $0 stop"
}

stop() {
  ip netns pids "$NS" 2>/dev/null | xargs -r kill 2>/dev/null || true
  sleep 1
  ip netns pids "$NS" 2>/dev/null | xargs -r kill -9 2>/dev/null || true
  ip netns del "$NS" 2>/dev/null || true
  ip link del "$VETH_ROOT" 2>/dev/null || true
  echo "Receive netns '$NS' and veth torn down."
}

case "${1:-start}" in
  start) start ;;
  stop)  stop ;;
  *) echo "usage: sudo $0 [start|stop]"; exit 1 ;;
esac
