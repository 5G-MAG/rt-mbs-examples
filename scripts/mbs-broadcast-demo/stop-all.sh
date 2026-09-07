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
# a plain TERM to the wrapper doesn't reach) -- clean up by binary name as a backstop.
if netns_exists; then
    sudo -n ip netns exec "$NETNS" pkill -TERM -f 'apps/gnb/gnb ' 2>/dev/null || true
    sudo -n ip netns exec "$NETNS" pkill -TERM -f 'srsue/src/srsue ' 2>/dev/null || true
    sudo -n ip netns exec "$NETNS" pkill -TERM -f 'mbs-client' 2>/dev/null || true
    sudo -n ip netns exec "$NETNS" pkill -TERM -f 'node app.js' 2>/dev/null || true
    sudo -n ip netns exec "$NETNS" pkill -TERM -f socat 2>/dev/null || true
fi

# Match on the executable name, not the whole command line: "pkill -f open5gs-upfd" also matches
# any other process whose arguments happen to mention it, the invoking shell included, and killing
# the caller of this script is a confusing way to fail.
sudo -n pkill -x -TERM 'open5gs-upfd' 2>/dev/null || true

# The looping encoder is started detached by start-bypass-live.sh and so has no pidfile of its own.
# Match only an ffmpeg writing into this demo's own media directory, so an unrelated encode on the
# same machine is left alone.
for pid in $(pgrep -f "ffmpeg .*$MEDIA_DIR/public" 2>/dev/null || true); do
    [[ "$pid" == "$$" ]] && continue
    log "stopping live encoder (pid $pid)"
    kill -TERM "$pid" 2>/dev/null || true
done

if [[ "${1:-}" == "--netns" ]]; then
    ./00-setup-netns.sh --teardown
fi

log "stopped"
