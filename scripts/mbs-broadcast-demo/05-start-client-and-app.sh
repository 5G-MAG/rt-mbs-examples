#!/bin/bash
# Starts rt-mbs-client (MBSF Client + MBSTF Client) and rt-mbs-application inside $NETNS
# (both need loopback access to each other and to the UE's own tun_bcastue interface),
# plus a socat relay so the dashboard is reachable from outside $NETNS at
# $VETH_NS_ADDR:$APP_PORT, and rt-mbs-application-provider on the host.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source env.sh
source lib.sh
ensure_dirs

require_file "$CLIENT_BIN"
require_cmd socat
netns_exists || die "run 00-setup-netns.sh first"
sudo -n true || die "passwordless sudo (or a cached sudo timestamp) is required"

log "waiting for the UE's tun_bcastue interface to get an address (PDU session establishment)"
UE_IP=""
for _ in $(seq 1 "$UE_TUN_WAIT_SECS"); do
    UE_IP=$(sudo -n ip netns exec "$NETNS" ip -o -4 addr show tun_bcastue 2>/dev/null \
        | awk '{print $4}' | cut -d/ -f1)
    [[ -n "$UE_IP" ]] && break
    sleep 1
done
[[ -n "$UE_IP" ]] || die "tun_bcastue got no address within ${UE_TUN_WAIT_SECS}s -- check $LOG_DIR/ue_bcast.log for the attach, and raise UE_TUN_WAIT_SECS in env.sh if the UE is simply slow on this machine"
log "UE PDU session address: $UE_IP"

# rt-mbs-client.conf: field names/values per rt-mbs-client/run/rt-mbs-client.conf, adapted
# for this deployment's addresses. flute_iface points at the UE's own real PDU-session
# address (changes across UE restarts, hence discovered live above, not hardcoded).
# raw_capture_relay is required because tun_bcastue is a TUN device and OS-level local IP
# multicast delivery does not work on a TUN-type interface in this whole test topology
# (https://github.com/5G-MAG/rt-libflute/issues/66).
cat > "$GEN_CONF_DIR/rt-mbs-client.conf" <<EOF
log_level: "trace";

mbsf_client: {
  # Reference point MBS5, the unicast half of TS 26.502 V18.6.0 clause 4.5.31's Service
  # announcement modes. Two things this has to get right, both of which the previous
  # "\$MBSF_ADDR:\$SBI_PORT" got wrong for a UE that is not in the root namespace:
  #  - Port: the User Service Description retrieval API is served by the co-located MBS AF
  #    server (8888), not the SBI port. TS 26.517 V18.6.0 clause 9.2.2: "The User Service
  #    Description retrieval API is accessible from the MBS AF at reference point MBS5 and from
  #    the MBSTF Client at reference point MBS7' through the following URL base path:".
  #  - Address: MBS5 is reached by the MBS Client over its own PDU session, so it must be a
  #    routable address. \$MBSAF_ADDR is in 127.0.0.0/8, which inside \$NETNS resolves to that
  #    namespace's own loopback and never reaches the MBS AF at all. \$VETH_ROOT_ADDR is the
  #    root-namespace end of the veth pair and is reachable from \$NETNS; 02-start-mbs-function.sh
  #    binds the MBS AF server there as well as on \$MBSAF_ADDR.
  api_root: "http://$VETH_ROOT_ADDR:8888";
  announcement_channel: {
    multicast_address: "232.0.0.1";
    port: 3000;
    tsi: 1;
    source_address: "$MBSF_ADDR";
  }
}

mbstf_client: {
  flute_iface: "$UE_IP";
  raw_capture_relay: true;
}

mbs_aware_api: {
  listen_uri: "http://127.0.0.1:$MBS_CLIENT_API_PORT/mbs-client-api";
}


EOF

# UE pre-configuration for 5MBS (3GPP TS 24.575), when UE_PRE_CONFIGURATION=1.
#
# The specified way for a UE to learn which TMGI carries the Service Announcement, and with what
# USD, is this object. TS 24.575 clause 4: "If the UE is pre-configured with information related
# to services using MBS, the UE can discover and receive data for services by using the
# provisioned configuration." The announcement_channel block above is the deployment-fixed
# fallback for when no object is provisioned, so the two are alternatives and this removes it.
#
# The USD is a User Service Descriptions Bundle Entity: TS 26.517 clause 5.3.1A requires that
# "The Content-Type header of the entity shall be multipart/related", and the entity carries its
# own header here so the client can read the type and boundary from it. Its second body part is
# the SDP for this deployment's own announcement channel -- the same parameters the fallback
# block uses, expressed the way the specification expects to find them.
if [ "${UE_PRE_CONFIGURATION:-0}" = "1" ]; then
  UPC_FILE="$GEN_CONF_DIR/ue-pre-configuration.json"
  UPC_BOUNDARY="5gmag-demo-ue-pre-config"

  # Written with python3 so the JSON string escaping of a MIME entity (CRLFs, quotes, the
  # boundary) is done by a JSON encoder rather than by hand in shell.
  ANN_SRC="$MBSF_ADDR" ANN_ADDR="232.0.0.1" ANN_PORT="3000" ANN_TSI="1" \
  UPC_BOUNDARY="$UPC_BOUNDARY" UPC_FILE="$UPC_FILE" \
  python3 - <<'PYEOF'
import json, os
src, addr = os.environ["ANN_SRC"], os.environ["ANN_ADDR"]
port, tsi = os.environ["ANN_PORT"], os.environ["ANN_TSI"]
b = os.environ["UPC_BOUNDARY"]

# The TMGI recorded in TMGIListForSA. A real deployment fixes this in advance, which is the point
# of pre-configuration; this demo's MBSF allocates TMGIs when it creates the session, so no fixed
# value can be the real one and the client acquires the announcement from the USD beside it. It
# still has the structure TS 23.003 clause 30.2 gives: six hexadecimal digits of MBS Service ID,
# a three-digit MCC, then a two- or three-digit MNC.
tmgi = "00000100101"

sdp = ("v=0\r\n"
       f"o=- 1 1 IN IP4 {src}\r\n"
       "s=Announcement Channel\r\n"
       "t=0 0\r\n"
       f"a=source-filter:incl IN IP4 * {src}\r\n"
       f"a=flute-tsi:{tsi}\r\n"
       f"m=application {port} FLUTE/UDP 0\r\n"
       f"c=IN IP4 {addr}\r\n"
       "b=10000\r\n")

root = {"version": 1,
        "userServiceDescriptions": [{
            "serviceIds": ["urn:5gmag:demo:service-announcement"],
            "class": "urn:oma:bcast:oma_bsc:st:1.0",
            "names": [{"lang": "en", "name": "Service Announcement Channel"}],
            "distributionSessionDescriptions": [
                {"distributionMethod": "OBJECT",
                 "sessionDescriptionLocator": "announcement-channel.sdp"}]}]}

entity = (
  f'Content-Type: multipart/related; type="application/3gpp-mbs-user-service-descriptions+json"; boundary="{b}"\r\n'
  "\r\n"
  f"--{b}\r\n"
  "Content-Type: application/3gpp-mbs-user-service-descriptions+json\r\n"
  "\r\n"
  f"{json.dumps(root)}\r\n"
  f"--{b}\r\n"
  "Content-Type: application/sdp\r\n"
  "Content-Location: announcement-channel.sdp\r\n"
  "\r\n"
  f"{sdp}\r\n"
  f"--{b}--\r\n")

obj = {"name": "rt-mbs-examples broadcast demo",
       "plmnList": [{"plmnId": "00101",
                     "tmgiListForSA": [{"tmgi": tmgi, "usd": entity}]}]}
with open(os.environ["UPC_FILE"], "w") as fh:
    json.dump(obj, fh, indent=2)
PYEOF

  # Drop the fallback and point the client at the object instead.
  python3 - "$GEN_CONF_DIR/rt-mbs-client.conf" "$UPC_FILE" <<'PYEOF'
import re, sys
conf, upc = sys.argv[1], sys.argv[2]
s = open(conf).read()
s = re.sub(r"\n  announcement_channel: \{[^}]*\}\n", "\n", s)
s += '\nue_pre_configuration: {\n  file: "%s";\n}\n' % upc
open(conf, "w").write(s)
PYEOF

  log "UE pre-configuration (TS 24.575) provisioned: $UPC_FILE"
  log "  the announcement_channel fallback is removed; the client acquires the announcement from the object"
fi

# Both rt-mbs-client and rt-mbs-application run as root inside $NETNS (run_bg_netns_root),
# not privilege-dropped -- rt-mbs-client's own raw_capture_relay opens an AF_PACKET raw
# socket on tun_bcastue (CAP_NET_RAW, root-only); observed live in this project ("socket
# (AF_PACKET) failed: Operation not permitted" otherwise). rt-mbs-application has no such
# requirement itself but is kept root too, matching this project's own already-working
# configuration rather than introducing an untested divergence.
log "starting rt-mbs-client in $NETNS"
run_bg_netns_root "rt-mbs-client" rt-mbs-client "$CLIENT_BIN" "$GEN_CONF_DIR/rt-mbs-client.conf"
sleep 1

cat > "$APP_DIR/.env" <<EOF
PORT=$APP_PORT
MBS_CLIENT_HOST=localhost
MBS_CLIENT_PORT=$MBS_CLIENT_API_PORT
RADIO_HOST=localhost
RADIO_PORT=$RADIO_API_PORT
EOF

[[ -d "$APP_DIR/node_modules" ]] || { log "installing rt-mbs-application deps"; (cd "$APP_DIR" && npm install --no-audit --no-fund); }
log "starting rt-mbs-application in $NETNS"
run_bg_netns_root "rt-mbs-application" app "bash" "-c" "cd '$APP_DIR' && node app.js"
sleep 1

log "starting socat relay: $VETH_NS_ADDR:$APP_PORT (in $NETNS) -> loopback:$APP_PORT (in $NETNS)"
if ! pgrep -f "socat.*TCP-LISTEN:$APP_PORT,bind=$VETH_NS_ADDR" >/dev/null 2>&1; then
    sudo -n ip netns exec "$NETNS" bash -c \
        "nohup socat TCP-LISTEN:$APP_PORT,bind=$VETH_NS_ADDR,fork,reuseaddr TCP:127.0.0.1:$APP_PORT >'$LOG_DIR/socat.log' 2>&1 & echo \$! > '$PID_DIR/socat.pid'; disown"
fi

# Same relay again, the other direction: root-namespace loopback:$APP_PORT -> $NETNS's
# $VETH_NS_ADDR:$APP_PORT, purely so the dashboard is reachable at the conventional
# http://localhost:$APP_PORT/ from the host, not just at the veth address.
if ! pgrep -f "socat.*TCP-LISTEN:$APP_PORT,bind=127.0.0.1" >/dev/null 2>&1; then
    run_bg "app-relay" app-relay socat "TCP-LISTEN:$APP_PORT,bind=127.0.0.1,fork,reuseaddr" "TCP:$VETH_NS_ADDR:$APP_PORT"
fi

cat > "$PROVIDER_DIR/.env" <<EOF
MBSF_HOST=$MBSF_ADDR
MBSF_PORT=$SBI_PORT
MBSTF_HOST=$MBSTF_DISTSESSION_ADDR
MBSTF_PORT=$SBI_PORT
PORT=$PROVIDER_PORT
HOST=127.0.0.1
NOTIF_PATH=/notifications
AUTH_USER=$PROVIDER_AUTH_USER
AUTH_TOKEN=$PROVIDER_AUTH_TOKEN
LOG_DIR=./logs
MBSTF_PUSH_AUTH_TOKEN=
EOF

[[ -d "$PROVIDER_DIR/node_modules" ]] || { log "installing rt-mbs-application-provider deps"; (cd "$PROVIDER_DIR" && npm install --no-audit --no-fund); }
log "starting rt-mbs-application-provider on the host"
run_bg "rt-mbs-application-provider" provider bash -c "cd '$PROVIDER_DIR' && node server.js"

wait_for_http "http://$VETH_NS_ADDR:$APP_PORT/" 15 || log "WARNING: rt-mbs-application not reachable yet at http://$VETH_NS_ADDR:$APP_PORT/ -- check $LOG_DIR/app.log"
wait_for_http "http://127.0.0.1:$PROVIDER_PORT/" 15 || log "WARNING: rt-mbs-application-provider not reachable yet -- check $LOG_DIR/provider.log"

log "rt-mbs-client / rt-mbs-application / rt-mbs-application-provider started"
log "  Dashboard: http://localhost:$APP_PORT/  (also reachable at http://$VETH_NS_ADDR:$APP_PORT/)"
log "  Provider:  http://127.0.0.1:$PROVIDER_PORT/  (login: $PROVIDER_AUTH_USER / $PROVIDER_AUTH_TOKEN)"
