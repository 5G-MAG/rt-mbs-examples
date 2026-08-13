#!/usr/bin/env bash
#
# transmit.sh -- bring up the transmit ("network") side of the 5G NR MBS Broadcast
# reference-tools stack in the background, one log file per component:
#
#   5GC (NRF, SCP, AUSF, UDM, UDR, PCF, NSSF, BSF, AMF, SMF, UPF) -> MBSF -> MBSTF
#   -> rt-mbs-application-provider (portal, provisions/pushes content) -> gNB
#
# All of this runs in the HOST (root) network namespace. Pair with
# receive-netns.sh, which runs the UE + rt-mbs-client + rt-mbs-application in a
# dedicated network namespace, connected to this side by a veth pair -- this
# split is required, not cosmetic: the gNB and UE's ZMQ RF link deadlocks if
# both processes share one namespace and talk over loopback (confirmed live,
# see gnb.yaml's comment for the full story).
#
#   ./transmit.sh            launch the transmit side (background) and report
#   ./transmit.sh --stop     stop everything this script started
#
# Config is shared with the tmux tutorial (same ./conf); override any variable
# via the environment. Every repo path below defaults to this machine's actual
# checkout layout -- adjust for yours.
#
set -u

# =============================================================================
# CONFIG -- adjust to your environment (or override via the environment)
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="${CONF:-$SCRIPT_DIR/conf}"

OPEN5GS_DIR="${OPEN5GS_DIR:-$HOME/Repos/rt-mbs/open5gs}"
MBSF_DIR="${MBSF_DIR:-$HOME/Repos/rt-mbs/rt-mbs-function}"
MBSTF_DIR="${MBSTF_DIR:-$HOME/Repos/rt-mbs/rt-mbs-transport-function}"
PROVIDER_DIR="${PROVIDER_DIR:-$HOME/Repos/rt-mbs/rt-mbs-application-provider}"
GNB_DIR="${GNB_DIR:-$HOME/Repos/srsRAN_Project_mbs}"

OPEN5GS_BIN="$OPEN5GS_DIR/install/bin"
OPEN5GS_ETC="$OPEN5GS_DIR/install/etc/open5gs"
MBSF_BIN="$MBSF_DIR/build/src/mbsf/open5gs-mbsfd"
MBSF_CONF="${MBSF_CONF:-$MBSF_DIR/build/src/mbsf/mbsf.yaml}"
MBSTF_BIN="$MBSTF_DIR/build/src/mbstf/open5gs-mbstfd"
MBSTF_CONF="${MBSTF_CONF:-$MBSTF_DIR/build/src/mbstf/mbstf.yaml}"
GNB_BIN="$GNB_DIR/build/apps/gnb/gnb"
GNB_CONF="${GNB_CONF:-$CONF/gnb.yaml}"

# The gNB gets its OWN network namespace ("mbs-gnb"), separate from both the
# root namespace (5GC/MBSF/MBSTF/Provider) and the receive side ("mbs-rx") --
# see gnb.yaml's "BUG FIX #2" comment for why: srsRAN_Project's CU-UP always
# wildcard-binds port 2152, which collides with open5gs UPF's own GTP-U sockets
# if they share a namespace. Two veth pairs connect it:
#
#   root (5GC/MBSF/MBSTF) <--10.91.0.0/24--> mbs-gnb <--10.90.0.0/24--> mbs-rx (UE)
#         AMF NGAP, UPF N3/N3mb                       gNB ZMQ RF <-> UE ZMQ RF
#
# These addresses must match amf.yaml's ngap.server, upf.yaml's gtpu.server,
# gnb.yaml's cu_cp.amf.addr/cu_up.ngu.socket.bind_addr/ru_sdr.device_args, and
# ue.conf's device_args.
GNB_NS="${GNB_NS:-mbs-gnb}"
VETH_CORE="${VETH_CORE:-veth-mbs-core}"       # root side, facing gNB
VETH_CORE_GNB="${VETH_CORE_GNB:-veth-mbs-cg}" # mbs-gnb side, facing root
VETH_CORE_IP="${VETH_CORE_IP:-10.91.0.1}"     # AMF NGAP address
VETH_CORE_IP2="${VETH_CORE_IP2:-10.91.0.3}"   # UPF N3/N3mb address (secondary on root side)
VETH_GNB_CORE_IP="${VETH_GNB_CORE_IP:-10.91.0.2}"

VETH_ROOT_IP="${VETH_ROOT_IP:-10.90.0.1}"     # mbs-gnb side, facing UE (gNB's ZMQ tx wildcard-binds)
VETH_RX_IP="${VETH_RX_IP:-10.90.0.3}"         # mbs-rx side, facing gNB
VETH_MASK="${VETH_MASK:-24}"
VETH_ROOT="${VETH_ROOT:-veth-mbs-root}"       # mbs-gnb side
VETH_RX="${VETH_RX:-veth-mbs-rx}"             # mbs-rx side
RX_NS="${RX_NS:-mbs-rx}"

USER_NAME="${SUDO_USER:-$(logname 2>/dev/null || echo "$USER")}"

LOG_DIR="${LOG_DIR:-$HOME/.local/state/mbs-broadcast-tutorial}"
PID_FILE="$LOG_DIR/transmit.pids"
STAGE_PAUSE="${STAGE_PAUSE:-1}"

# BUG FIX (found live, 2026-08-11): this used to render GNB_CONF's @@LOG_DIR@@
# placeholder down near the launch/validation code, but the COMPONENTS array below
# expands $GNB_CONF immediately at array-definition time (bash does not re-expand
# array elements later), so that rendering ran too late to have any effect -- the
# gNB was always launched with the raw, un-rendered path still containing the
# literal "@@LOG_DIR@@" token, which of course doesn't exist, so the gNB failed to
# start at all (silently, from this script's point of view -- it just never comes
# up, and the UE spins on "Attaching UE..." forever with nothing to attach to).
# gnb.yaml's log filename is templated this way (rather than hardcoding a path
# under some specific user's home directory) since it can't reference $LOG_DIR
# itself -- YAML has no shell-style expansion. Render the copy here, before
# anything captures $GNB_CONF's value.
mkdir -p "$LOG_DIR"
if [ "$GNB_CONF" = "$CONF/gnb.yaml" ]; then
  RENDERED_GNB_CONF="$LOG_DIR/gnb.rendered.yaml"
  sed "s#@@LOG_DIR@@#$LOG_DIR#g" "$GNB_CONF" > "$RENDERED_GNB_CONF"
  GNB_CONF="$RENDERED_GNB_CONF"
fi

# "Name|WorkingDir|Command|pause|sudo"
COMPONENTS=(
  "NRF||$OPEN5GS_BIN/open5gs-nrfd -c $OPEN5GS_ETC/nrf.yaml|$STAGE_PAUSE|"
  "SCP||$OPEN5GS_BIN/open5gs-scpd -c $OPEN5GS_ETC/scp.yaml|$STAGE_PAUSE|"
  "AUSF||$OPEN5GS_BIN/open5gs-ausfd -c $OPEN5GS_ETC/ausf.yaml|0|"
  "UDM||$OPEN5GS_BIN/open5gs-udmd -c $OPEN5GS_ETC/udm.yaml|0|"
  "UDR||$OPEN5GS_BIN/open5gs-udrd -c $OPEN5GS_ETC/udr.yaml|0|"
  "PCF||$OPEN5GS_BIN/open5gs-pcfd -c $OPEN5GS_ETC/pcf.yaml|0|"
  "NSSF||$OPEN5GS_BIN/open5gs-nssfd -c $OPEN5GS_ETC/nssf.yaml|0|"
  "BSF||$OPEN5GS_BIN/open5gs-bsfd -c $OPEN5GS_ETC/bsf.yaml|$STAGE_PAUSE|"
  "UPF||$OPEN5GS_BIN/open5gs-upfd -c $OPEN5GS_ETC/upf.yaml|$STAGE_PAUSE|sudo"
  "SMF||$OPEN5GS_BIN/open5gs-smfd -c $OPEN5GS_ETC/smf.yaml|$STAGE_PAUSE|"
  "AMF||$OPEN5GS_BIN/open5gs-amfd -c $OPEN5GS_ETC/amf.yaml|$STAGE_PAUSE|"
  "MBSF|$MBSF_DIR/build/src/mbsf|$MBSF_BIN -c $MBSF_CONF|$STAGE_PAUSE|"
  "MBSTF|$MBSTF_DIR/build/src/mbstf|$MBSTF_BIN -c $MBSTF_CONF|$STAGE_PAUSE|"
  "Provider|$PROVIDER_DIR|node --env-file=.env server.js|$STAGE_PAUSE|"
  # Root is only needed for 'ip netns exec' itself -- runuser drops back to the
  # invoking user for the gNB process, same as receive-netns.sh does for the UE.
  "gNB||ip netns exec $GNB_NS runuser -u $USER_NAME -- $GNB_BIN -c $GNB_CONF|0|sudo"
)

die() { echo "ERROR: $*" >&2; exit 1; }
require_exec() { [ -x "$1" ] || die "not executable: $1 (build it, or set its path variable)"; }

# Full teardown of the transmit-side stack on this host, by process name -- so it
# clears leftovers regardless of how they were started. Does not touch the
# receive side or the shared veth/namespace -- tear those down separately with
# `sudo ./receive-netns.sh stop` (which also removes the veth).
stop_stack() {
  # BUG FIX (found live, 2026-08-10): the gNB is launched via sudo (see the "gNB" entry in
  # COMPONENTS -- it needs CAP_NET_ADMIN for its netns), so a plain, non-sudo pkill here can
  # never signal it (a normal user cannot signal another user's process) -- confirmed live: this
  # let a gNB process survive every "clean restart" indefinitely, including across multiple
  # ./transmit.sh runs meant to replace it, while a brand-new gNB process failed to start at all
  # (port/veth already held by the surviving old one) or, when it managed to start anyway (e.g.
  # after the old one was killed by hand), left the OLD stale process's netns/radio state mixed
  # in with the new one. Mirror the sudo already used for UPF below.
  pkill -f 'open5gs-nrfd\|open5gs-scpd\|open5gs-ausfd\|open5gs-udmd\|open5gs-udrd\|open5gs-pcfd\|open5gs-nssfd\|open5gs-bsfd\|open5gs-smfd\|open5gs-amfd\|open5gs-mbsfd\|open5gs-mbstfd' 2>/dev/null
  sudo pkill -f open5gs-upfd 2>/dev/null
  pkill -f "node --env-file=.env server.js" 2>/dev/null
  sudo pkill -f "apps/gnb/gnb -c" 2>/dev/null
  for i in 1 2 3 4 5 6; do
    pgrep -f 'open5gs-|apps/gnb/gnb -c' >/dev/null 2>&1 || break
    sleep 1
  done
  pgrep -f 'open5gs-|apps/gnb/gnb -c' >/dev/null 2>&1 && {
    pkill -9 -f 'open5gs-' 2>/dev/null
    sudo pkill -9 -f open5gs-upfd 2>/dev/null
    sudo pkill -9 -f "apps/gnb/gnb -c" 2>/dev/null
  }
  rm -f "$PID_FILE" 2>/dev/null || true
}

# The two veth pairs (root<->mbs-gnb, mbs-gnb<->mbs-rx). Idempotent: safe to call
# whether or not receive-netns.sh (or a previous run of this script) already
# created the mbs-rx side of the second pair.
setup_veth() {
  sudo ip netns add "$GNB_NS" 2>/dev/null || true
  sudo ip netns exec "$GNB_NS" ip link set lo up

  if ! ip link show "$VETH_CORE" >/dev/null 2>&1; then
    echo "Creating veth pair $VETH_CORE <-> $VETH_CORE_GNB (netns '$GNB_NS') ..."
    sudo ip link add "$VETH_CORE" type veth peer name "$VETH_CORE_GNB"
    sudo ip link set "$VETH_CORE_GNB" netns "$GNB_NS"
    sudo ip addr add "$VETH_CORE_IP/$VETH_MASK" dev "$VETH_CORE" 2>/dev/null || true
    sudo ip addr add "$VETH_CORE_IP2/$VETH_MASK" dev "$VETH_CORE" 2>/dev/null || true
    sudo ip link set "$VETH_CORE" up
    sudo ip netns exec "$GNB_NS" ip addr add "$VETH_GNB_CORE_IP/$VETH_MASK" dev "$VETH_CORE_GNB" 2>/dev/null || true
    sudo ip netns exec "$GNB_NS" ip link set "$VETH_CORE_GNB" up
  else
    echo "veth pair $VETH_CORE already exists, reusing it."
  fi

  if ! sudo ip netns exec "$GNB_NS" ip link show "$VETH_ROOT" >/dev/null 2>&1; then
    echo "Creating veth pair $VETH_ROOT (netns '$GNB_NS') <-> $VETH_RX (netns '$RX_NS') ..."
    sudo ip netns add "$RX_NS" 2>/dev/null || true
    sudo ip link add "$VETH_ROOT" netns "$GNB_NS" type veth peer name "$VETH_RX" netns "$RX_NS"
    sudo ip netns exec "$GNB_NS" ip addr add "$VETH_ROOT_IP/$VETH_MASK" dev "$VETH_ROOT" 2>/dev/null || true
    sudo ip netns exec "$GNB_NS" ip link set "$VETH_ROOT" up
    sudo ip netns exec "$RX_NS" ip addr add "$VETH_RX_IP/$VETH_MASK" dev "$VETH_RX" 2>/dev/null || true
    sudo ip netns exec "$RX_NS" ip link set "$VETH_RX" up
    sudo ip netns exec "$RX_NS" ip link set lo up
  else
    echo "veth pair $VETH_ROOT already exists, reusing it."
  fi
}

# =============================================================================
# --stop
# =============================================================================
if [ "${1:-}" = "--stop" ] || [ "${1:-}" = "-k" ]; then
  echo "Stopping the transmit-side stack..."
  stop_stack
  echo "Tearing down the gNB namespace ('$GNB_NS') and its veth pairs..."
  sudo ip netns pids "$GNB_NS" 2>/dev/null | xargs -r sudo kill 2>/dev/null || true
  sleep 1
  sudo ip netns pids "$GNB_NS" 2>/dev/null | xargs -r sudo kill -9 2>/dev/null || true
  sudo ip netns del "$GNB_NS" 2>/dev/null || true
  sudo ip link del "$VETH_CORE" 2>/dev/null || true
  echo "Done. Receive side (if running) is separate: sudo ./receive-netns.sh stop"
  echo "(deleting '$GNB_NS' above also removes its veth pair to mbs-rx; mbs-rx itself is torn down by 'sudo ./receive-netns.sh stop')"
  exit 0
fi

# =============================================================================
# Pre-flight
# =============================================================================
command -v node >/dev/null 2>&1 || die "'node' not found (the Provider is a Node.js app)"
command -v sudo >/dev/null 2>&1 || die "'sudo' not found (UPF needs CAP_NET_ADMIN for its TUN device)"
[ -d "$CONF" ] || die "config dir not found: $CONF"
for b in nrfd scpd ausfd udmd udrd pcfd nssfd bsfd smfd amfd upfd; do
  require_exec "$OPEN5GS_BIN/open5gs-$b"
done
require_exec "$MBSF_BIN"; require_exec "$MBSTF_BIN"; require_exec "$GNB_BIN"
[ -f "$PROVIDER_DIR/server.js" ] || die "not found: $PROVIDER_DIR/server.js"
[ -f "$PROVIDER_DIR/.env" ] || echo "WARNING: $PROVIDER_DIR/.env missing -- the Provider needs AUTH_TOKEN set (see .env.example)."
[ -f "$GNB_CONF" ] || die "gNB config not found: $GNB_CONF"

mkdir -p "$LOG_DIR"
sudo mkdir -p "$OPEN5GS_DIR/install/var/log/open5gs" "$(dirname "$MBSF_CONF")" 2>/dev/null
sudo chown -R "$(id -u)":"$(id -g)" "$OPEN5GS_DIR/install/var/log/open5gs" 2>/dev/null || true

echo "Authenticating sudo once (UPF needs CAP_NET_ADMIN; the veth setup needs root)..."
sudo -n true 2>/dev/null || sudo -v || die "sudo authentication failed"
( while true; do sudo -n true 2>/dev/null || exit; sleep 50; done ) & SUDO_KEEPALIVE_PID=$!
trap '[ -n "${SUDO_KEEPALIVE_PID:-}" ] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null' EXIT

echo "Clearing any existing transmit-side stack for a clean start..."
stop_stack
sleep 1

setup_veth

# =============================================================================
# Launch: each component backgrounded (nohup), one log file per component
# =============================================================================
: > "$PID_FILE"
for entry in "${COMPONENTS[@]}"; do
  IFS='|' read -r name workdir cmd pause usesudo <<<"$entry"
  [ "$usesudo" = "sudo" ] && cmd="sudo $cmd"
  log="$LOG_DIR/${name}.log"
  echo "Starting $name  (log: $log)"
  # stdin explicitly from /dev/null, not just left disconnected: srsue (and
  # potentially other components) closes stdin at startup when it hits EOF,
  # which -- since Linux allocates the lowest free fd -- lets some unrelated
  # fd (e.g. a timerfd) land on fd 0 shortly after. Found live: this caused a
  # metrics-reporting thread's timerfd_create() to legitimately return 0,
  # which a bad "if (ret > 0)" check treated as failure, and later a bad file
  # descriptor crash when something else's close() collided with it.
  if [ -n "$workdir" ]; then
    ( cd "$workdir" && exec nohup $cmd < /dev/null >"$log" 2>&1 ) &
  else
    ( exec nohup $cmd < /dev/null >"$log" 2>&1 ) &
  fi
  echo "$name $!" >> "$PID_FILE"
  sleep "${pause:-1}"
done

echo
echo "Transmit side launched in the background. Logs: $LOG_DIR/<Name>.log"
echo "Bring up the receive side with:  sudo ./receive-netns.sh start"
echo "Stop the transmit side with:     $0 --stop"
