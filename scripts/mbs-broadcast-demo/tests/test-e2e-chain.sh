#!/bin/bash
# End-to-end scenarios of the MBS Broadcast chain, driven only through the MBS Application Provider (the
# rt-mbs-application-provider portal on PROVIDER_PORT). Each scenario creates, changes or releases a User Data Ingest
# Session of a throwaway MBS User Service and checks what every hop of the chain logged for it, from the provider to the
# UE. Needs the broadcast demo up (./demo up). The demo's own services are not touched.
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$TESTS_DIR/.." || { echo "cannot find the demo directory" >&2; exit 1; }
set -a; source env.sh; set +a; source lib.sh
L="$LOG_DIR"
AP="http://127.0.0.1:${PROVIDER_PORT:-8091}"
TOKEN="${AP_TOKEN:-$(grep -E '^AUTH_TOKEN=' "$PROVIDER_DIR/.env" | cut -d= -f2-)}"
USER_="${AP_USER:-admin}"
SRC_URI="${E2E_SRC_URI:-http://127.0.0.1:3004/}"
SRC_ID="${E2E_SRC_ID:-tv_1_live/manifest.mpd}"
WAIT="${E2E_WAIT:-20}"
PASS=0; FAIL=0
LOGS="mbsf smf amf upf gnb ue_bcast"

ap() { curl -s -m 30 -u "$USER_:$TOKEN" "$@"; }
mark() { for f in $LOGS; do wc -l < "$L/$f.log" > "/tmp/.e2e_n_$f.$$"; done; }
since() { tail -n +$(( $(cat "/tmp/.e2e_n_$1.$$") + 1 )) "$L/$1.log" | sed 's/\x1b\[[0-9;]*m//g'; }
check() { if [ "$2" = "$3" ]; then echo "  PASS  $1"; PASS=$((PASS+1)); else echo "  FAIL  $1 (expected: $3, got: $2)"; FAIL=$((FAIL+1)); fi; }
# hop NAME LOG REGEX: the regex appears in what LOG wrote since mark(), within WAIT seconds
hop() {
    local i; for i in $(seq 1 "$WAIT"); do since "$2" | grep -a -q -E "$3" && { check "$1" ok ok; return; }; sleep 1; done
    check "$1" "not seen" ok
}
nohop() { sleep 1; if since "$2" | grep -a -q -E "$3"; then check "$1" "seen" "absent"; else check "$1" absent absent; fi; }

[ "$(pgrep -x gnb | wc -l)" -ge 1 ] || { echo "the demo is not up (no gnb)"; exit 2; }
[ "$(ap -o /dev/null -w '%{http_code}' "$AP/api/health")" = 200 ] || { echo "the provider does not answer on $AP"; exit 2; }

echo "setup: a throwaway MBS User Service"
SVC=$(ap -X POST -H 'Content-Type: application/json' -D - -o /dev/null "$AP/mbs-user-services" -d '{"extServiceIds":["urn:e2e:test-service"],"servType":"BROADCAST","servClass":"urn:oma:bcast:oma_bsc:st:1.0","servAnnModes":["VIA_MBS_DISTRIBUTION_SESSION"],"servNameDescs":[{"servName":"E2E test","servDescrip":"end to end scenarios","language":"eng"}],"mainServLang":"eng"}' | grep -i '^location:' | tr -d '\r' | sed 's#.*/##')
[ -n "$SVC" ] || { echo "the User Service was not created"; exit 2; }
BODY='{"mbsUserServId":"'$SVC'","mbsDisSessInfos":{"AP_MBS_SESSION_1":{"mbsDistSessState":"ACTIVE","maxContBitRate":"6 Mbps","distrMethod":"OBJECT","objDistrInfo":{"operatingMode":"STREAMING","objAcqMethod":"PULL","objIngUri":"'$SRC_URI'","objAcqIds":["'$SRC_ID'"]}}},"suppFeat":"2"}'

create_session() {
    mark
    ING=$(ap -X POST -H 'Content-Type: application/json' -D - -o /dev/null "$AP/ingest-sessions" -d "$BODY" | tee /tmp/.e2e_h.$$ | grep -i '^location:' | tr -d '\r' | sed 's#.*/##')
    check "provider: Ingest Session created (201)" "$(head -1 /tmp/.e2e_h.$$ | cut -d' ' -f2)" 201
    hop "MB-SMF: TMGI and MBS session added" smf 'Added\] Number of MBS Sessions in SMF'
    hop "AMF: Broadcast ContextCreate received" amf 'MBS Broadcast ContextCreate request received'
    hop "AMF: Broadcast Session Setup Response from the gNB" amf 'BROADCAST SESSION SETUP RESPONSE'
    hop "MB-UPF: MBS session added" upf 'Added\] Number of MBS Sessions in UPF'
    hop "gNB CU-CP: Broadcast Session Setup Request" gnb 'Received Broadcast Session Setup Request'
    hop "gNB: BC Bearer Context Setup on the CU-UP (E1AP)" gnb 'Received BC Bearer Context Setup Request on the CU-UP'
    hop "UE: MBS channel set up" ue_bcast 'MBS Channel Setup'
    hop "UE: PDSCH of the new G-RNTI received" ue_bcast 'PDCCH: cc=0, g-rnti='
    STATE=$(ap "$AP/ingest-sessions/$ING" | python3 -c 'import json,sys; d=json.load(sys.stdin)["mbsDisSessInfos"]["AP_MBS_SESSION_1"]; print(d["mbsDistSessState"], bool(d.get("mbsSessionId",{}).get("tmgi")))')
    check "provider: session ACTIVE with a TMGI" "$STATE" "ACTIVE True"
}
release_session() {
    mark
    check "provider: Ingest Session deleted (204)" "$(ap -X DELETE -o /dev/null -w '%{http_code}' "$AP/ingest-sessions/$ING")" 204
    hop "MB-SMF: MBS session removed" smf 'Removed\] Number of MBS Sessions in SMF'
    hop "AMF: Broadcast Session Release Request to the gNB" amf 'BROADCAST SESSION RELEASE REQUEST'
    hop "AMF: Broadcast Session Release Response" amf 'BROADCAST SESSION RELEASE RESPONSE'
    hop "AMF: MBS context removed" amf 'Removed\] Number of MBS Contexts in AMF'
    hop "MB-UPF: MBS session removed" upf 'Removed\] Number of MBS Sessions in UPF'
    hop "gNB: Broadcast Context Release Command to the DU" gnb 'Received BroadcastContextReleaseCommand on the DU'
    hop "UE: MBS channel torn down" ue_bcast 'MBS Channel Teardown'
}

# restart_gnb / restart_amf: stop the process and start it again as the demo does. The demo truncates the log of a
# process it starts, so the line count of that log restarts at zero.
restart_gnb() {
    sudo -n pkill -x srsue; pkill -x gnb
    # run_bg_netns starts nothing while the pid file names a live process: wait for the sudo wrapper to be gone too.
    for i in $(seq 1 30); do pgrep -x gnb >/dev/null || sudo -n kill -0 "$(cat "$PID_DIR/gnb.pid")" 2>/dev/null || break; sleep 1; done
    echo 0 > "/tmp/.e2e_n_gnb.$$"
    # With the ZeroMQ radio the UE has to start after the gNB's DU, and restart with it (see 04-start-ran.sh): it stops
    # before the gNB and starts once the DU is up.
    sudo -n pkill -x srsue; for i in $(seq 1 30); do pgrep -x srsue >/dev/null || sudo -n kill -0 "$(cat "$PID_DIR/ue.pid")" 2>/dev/null || break; sleep 1; done
    echo 0 > "/tmp/.e2e_n_ue_bcast.$$"
    run_bg_netns "gNB" gnb "$GNB_BIN" -c "$GEN_CONF_DIR/gnb_bcast.yaml" ${GNB_EXTRA_ARGS:-} >/dev/null
    for i in $(seq 1 60); do grep -aq 'DU started successfully' "$L/gnb.log" 2>/dev/null && break; sleep 1; done
    run_bg_netns_root "UE" ue "$UE_BIN" "$GEN_CONF_DIR/ue_bcast.conf" >/dev/null
    # The client is bound to the UE's tun_bcastue, which the new UE creates again: it restarts once the UE has its address,
    # as 05-start-client-and-app.sh does, and the service that was active has to be activated again, as the application's
    # page does with /api/services/activate (the client keeps no activation across a restart).
    for i in $(seq 1 120); do sudo -n ip netns exec "$NETNS" ip -o -4 addr show tun_bcastue 2>/dev/null | grep -q inet && break; sleep 1; done
    for pid in $(ps -eo pid,comm | awk '$2=="mbs-client"{print $1}'); do sudo -n kill "$pid" 2>/dev/null; done
    sleep 3
    bash "$TESTS_DIR/../05-start-client-and-app.sh" >/dev/null 2>&1
    for ext in $(ap "$AP/mbs-user-services" | python3 -c 'import json,sys
for x in json.load(sys.stdin):
    for e in x.get("extServiceIds", []):
        if e != "urn:e2e:test-service": print(e)'); do
        curl -s -m 20 -o /dev/null "http://localhost:3050/api/services/activate?external-service-id=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "$ext")"
    done
}
restart_amf() {
    kill "$(cat "$PID_DIR/amf.pid")"; for i in $(seq 1 30); do kill -0 "$(cat "$PID_DIR/amf.pid")" 2>/dev/null || break; sleep 1; done
    echo 0 > "/tmp/.e2e_n_amf.$$"
    run_bg "AMF" amf "$OPEN5GS_BUILD/src/amf/open5gs-amfd" -c "$GEN_CONF_DIR/amf.yaml" >/dev/null
}

echo "1. create the Ingest Session and follow it to the UE"; create_session
if [ "${E2E_RESTART:-1}" = 1 ]; then
echo "restore: the gNB restarts while the session is active (TS 23.527 cl. 8.3.2.2)"
mark; restart_gnb; WAIT=60
hop "AMF: NG Setup from the gNB again" amf 'NGSetupRequest|NG Setup'
hop "AMF: Broadcast Session Setup Request to the gNB again" amf 'BROADCAST SESSION SETUP REQUEST'
hop "AMF: Broadcast Session Setup Response from the gNB again (session restored)" amf 'BROADCAST SESSION SETUP RESPONSE'
hop "UE: MBS channel set up again" ue_bcast 'MBS Channel Setup'
WAIT=20
if [ "${E2E_RESTART_AMF:-1}" = 1 ]; then
# The restarted AMF holds no MBS context: the MB-SMF creates it again and the gNB, which kept the session, releases it and
# sets it up again. TS 23.527 cl. 8.3.2.4 covers an AMF that failed without restart; none read covers this exact case.
echo "restore: the AMF restarts while the session is active"
mark; restart_amf; WAIT=90
hop "AMF: Broadcast ContextCreate received again" amf 'MBS Broadcast ContextCreate request received'
hop "AMF: Broadcast Session Setup Response from the gNB again" amf 'BROADCAST SESSION SETUP RESPONSE'
WAIT=20
fi
fi
echo "2. deactivate and reactivate the distribution session (Nmb10 state change)"
for st in INACTIVE ACTIVE; do
    code=$(ap -X PATCH -H 'Content-Type: application/merge-patch+json' -o /dev/null -w '%{http_code}' "$AP/ingest-sessions/$ING" -d '{"mbsDisSessInfos":{"AP_MBS_SESSION_1":{"mbsDistSessState":"'$st'","distrMethod":"OBJECT","maxContBitRate":"6 Mbps"}}}')
    check "provider: state $st accepted (200)" "$code" 200
done
echo "3. release the Ingest Session and follow the teardown to the UE"; release_session
echo "4. create it again: the chain sets up again"; create_session
echo "5. release it again"; release_session
echo "6. a request the chain cannot serve is refused and reaches no hop"
mark
code=$(ap -X POST -H 'Content-Type: application/json' -o /dev/null -w '%{http_code}' "$AP/ingest-sessions" -d '{"mbsUserServId":"00000000-0000-0000-0000-000000000000","mbsDisSessInfos":{"AP_MBS_SESSION_1":{"mbsDistSessState":"ACTIVE","maxContBitRate":"6 Mbps","distrMethod":"OBJECT","objDistrInfo":{"operatingMode":"STREAMING","objAcqMethod":"PULL","objIngUri":"'$SRC_URI'","objAcqIds":["'$SRC_ID'"]}}},"suppFeat":"2"}')
case "$code" in 4??) check "provider: an unknown User Service is refused (4xx)" ok ok;; *) check "provider: an unknown User Service is refused (4xx)" "$code" 4xx;; esac
nohop "MB-SMF: no MBS session was added" smf 'Added\] Number of MBS Sessions in SMF'
nohop "AMF: no ContextCreate" amf 'MBS Broadcast ContextCreate request received'
nohop "gNB: no Broadcast Session Setup Request" gnb 'Received Broadcast Session Setup Request'
if [ -n "${PLAYWRIGHT_MODULE:-}" ] && command -v node >/dev/null; then
    echo "7. the demo's own service still plays after all of this"
    # The video may take a while to recover after the restarts above: up to six looks, 30 s apart.
    for attempt in 1 2 3 4 5 6; do
        SAMPLES=$(PLAYWRIGHT_MODULE="$PLAYWRIGHT_MODULE" node "$TESTS_DIR/e2e-player.js" 2>/dev/null | head -1)
        VERDICT=$(python3 -c 'import json,sys
s=[x for x in json.loads(sys.argv[1]) if x]
print("playing" if len(s)>=4 and s[-1]["t"]-s[-4]["t"]>=5 and s[-1]["rs"]>=3 else "not playing")' "$SAMPLES" 2>/dev/null)
        [ "$VERDICT" = playing ] && break
        sleep 30
    done
    check "player: video advances with readyState >= 3" "${VERDICT:-no samples}" playing
else
    echo "7. (skipped: set PLAYWRIGHT_MODULE to a playwright install to check playback)"
fi
echo "cleanup"
ap -X DELETE -o /dev/null "$AP/mbs-user-services/$SVC"
rm -f /tmp/.e2e_n_*.$$ /tmp/.e2e_h.$$
echo; echo "passed $PASS, failed $FAIL"; [ "$FAIL" = 0 ]
