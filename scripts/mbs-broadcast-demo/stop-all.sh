#!/bin/bash
# Stops every process this demo started (by pidfile), in reverse dependency order. Leaves
# the network namespace in place by default (fast to restart into); pass --netns to also
# tear it down.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source env.sh
source lib.sh

kill_pidfile() {
    local name="$1" pidfile="$PID_DIR/$1.pid"
    [[ -f "$pidfile" ]] || return 0
    local pid; pid=$(cat "$pidfile")
    if sudo -n kill -0 "$pid" 2>/dev/null; then
        log "stopping $name (pid $pid)"
        sudo -n kill -TERM "$pid" 2>/dev/null
    fi
    rm -f "$pidfile"
}

for name in provider app-relay socat app rt-mbs-client ue gnb media-server mbsf mbstf amf smf upf bsf nssf pcf udr udm ausf nrf; do
    kill_pidfile "$name"
done

# Anything left inside the netns (gNB/UE/rt-mbs-client/app leave process-group children that
# a plain TERM to the wrapper doesn't reach). Selected by namespace membership, not by name:
# "ip netns exec ... pkill -f" does not confine pkill to the namespace (it shares the host's PID
# namespace), so a pattern such as 'mbs-client' also killed any host process whose command line
# mentioned it. Everything in $NETNS is this demo's.
#
# Then wait for them to be gone: the gNB and UE hold their ZMQ RF ports until they exit, and a
# start-all.sh straight after a stop otherwise brought up a UE that could not open its RF device
# and never attached. STOP_WAIT_SECS (default 10) bounds the wait before they are killed.
if netns_exists; then
    ns_pids=$(sudo -n ip netns pids "$NETNS" 2>/dev/null | tr '\n' ' ')
    [[ -n "${ns_pids// }" ]] && sudo -n kill -TERM $ns_pids 2>/dev/null
    for _ in $(seq 1 $(( ${STOP_WAIT_SECS:-10} * 5 ))); do
        [[ -z "$(sudo -n ip netns pids "$NETNS" 2>/dev/null)" ]] && break
        sleep 0.2
    done
    ns_pids=$(sudo -n ip netns pids "$NETNS" 2>/dev/null | tr '\n' ' ')
    if [[ -n "${ns_pids// }" ]]; then
        log "still running in $NETNS after ${STOP_WAIT_SECS:-10}s, killing: $ns_pids"
        sudo -n kill -KILL $ns_pids 2>/dev/null
    fi
fi

# Match on the executable name, not the whole command line: "pkill -f open5gs-upfd" also matches
# any other process whose arguments happen to mention it, the invoking shell included, and killing
# the caller of this script is a confusing way to fail.
sudo -n pkill -x -TERM 'open5gs-upfd' 2>/dev/null || true

# The looping encoder is started detached by start-all.sh and so has no pidfile of its own. Match
# only an ffmpeg writing into this demo's own media directory, so an unrelated encode on the same
# machine is left alone.
for pid in $(pgrep -f "ffmpeg .*$MEDIA_DIR/public" 2>/dev/null || true); do
    [[ "$pid" == "$$" ]] && continue
    log "stopping live encoder (pid $pid)"
    kill -TERM "$pid" 2>/dev/null || true
done

if [[ "${1:-}" == "--netns" ]]; then
    ./00-setup-netns.sh --teardown
fi

log "stopped"
