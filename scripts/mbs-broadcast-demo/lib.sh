#!/bin/bash
# Common helpers for the mbs-broadcast-demo scripts. Source after env.sh:
#   source env.sh; source lib.sh

log()  { echo "[$(date '+%H:%M:%S')] $*"; }
die()  { echo "[$(date '+%H:%M:%S')] ERROR: $*" >&2; exit 1; }

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "missing command: $1 (install it and re-run)"
}

require_file() {
    [[ -e "$1" ]] || die "missing required file/executable: $1"
}

ensure_dirs() {
    mkdir -p "$LOG_DIR" "$PID_DIR" "$GEN_CONF_DIR" "$MBSF_CACHE_DIR" "$STATE_DIR"
}

# Start a background process, own log file, own pidfile named after $1.
#   run_bg <name> <logfile-basename> <cmd...>
# Records the real child PID (not the shell's), so stop-all.sh can kill precisely.
run_bg() {
    local name="$1" logbase="$2"; shift 2
    local logfile="$LOG_DIR/${logbase}.log"
    local pidfile="$PID_DIR/${logbase}.pid"
    if [[ -f "$pidfile" ]] && kill -0 "$(cat "$pidfile" 2>/dev/null)" 2>/dev/null; then
        log "$name already running (pid $(cat "$pidfile")), skipping"
        return 0
    fi
    log "starting $name (log: $logfile)"
    nohup "$@" >"$logfile" 2>&1 &
    echo $! > "$pidfile"
    disown
}

# Same as run_bg but the command must be executed inside the ns-gnb network namespace,
# as root (required for netns access) but the process itself keeps running as $(whoami)
# via `sudo -u`, matching how rt-mbs-client/gNB/rt-mbs-application are actually run in
# this project (root only for the netns hop, not for the process's own file ownership).
# The UE is the one exception -- see run_bg_netns_root below -- it needs to stay root to
# create its own tun_bcastue TUN device (CAP_NET_ADMIN), which a dropped-privilege process
# cannot do; without this, srsue logs "Failed to setup/configure GW interface" and never
# gets a PDU-session address (code-derived, no spec claim -- observed live in this project).
run_bg_netns() {
    local name="$1" logbase="$2"; shift 2
    local logfile="$LOG_DIR/${logbase}.log"
    local pidfile="$PID_DIR/${logbase}.pid"
    if [[ -f "$pidfile" ]] && sudo -n kill -0 "$(cat "$pidfile" 2>/dev/null)" 2>/dev/null; then
        log "$name already running (pid $(cat "$pidfile")), skipping"
        return 0
    fi
    log "starting $name in $NETNS (log: $logfile)"
    sudo -n ip netns exec "$NETNS" sudo -n -u "$(whoami)" bash -c "exec \"\$@\"" _ "$@" >"$logfile" 2>&1 &
    local shell_pid=$!
    sleep 0.3
    echo "$shell_pid" > "$pidfile"
    disown
}

# Same as run_bg_netns but keeps the process running as root inside $NETNS (no `sudo -u`
# drop) -- needed for the UE's own TUN device creation, see the comment above.
run_bg_netns_root() {
    local name="$1" logbase="$2"; shift 2
    local logfile="$LOG_DIR/${logbase}.log"
    local pidfile="$PID_DIR/${logbase}.pid"
    if [[ -f "$pidfile" ]] && sudo -n kill -0 "$(cat "$pidfile" 2>/dev/null)" 2>/dev/null; then
        log "$name already running (pid $(cat "$pidfile")), skipping"
        return 0
    fi
    log "starting $name in $NETNS as root (log: $logfile)"
    sudo -n ip netns exec "$NETNS" bash -c "exec \"\$@\"" _ "$@" >"$logfile" 2>&1 &
    local shell_pid=$!
    # The real worker PID is a grandchild (netns exec -> sudo -> bash -c exec). Give it a
    # moment to appear, then resolve it via the log-writing bash's own child so stop-all.sh
    # can signal the right process.
    sleep 0.3
    echo "$shell_pid" > "$pidfile"
    disown
}

wait_for_tcp() {
    local host="$1" port="$2" timeout="${3:-20}"
    local waited=0
    until (exec 3<>"/dev/tcp/$host/$port") 2>/dev/null; do
        exec 3>&- 2>/dev/null || true
        sleep 1
        waited=$((waited+1))
        [[ $waited -ge $timeout ]] && return 1
    done
    exec 3>&- 2>/dev/null || true
    return 0
}

wait_for_http() {
    local url="$1" timeout="${2:-20}"
    local waited=0
    until curl -s -o /dev/null -m 2 "$url"; do
        sleep 1
        waited=$((waited+1))
        [[ $waited -ge $timeout ]] && return 1
    done
    return 0
}

netns_exists() {
    # `ip netns list` prints "<name> (id: N)" per line, not just the bare name -- match
    # only the first field, not the whole line.
    sudo -n ip netns list 2>/dev/null | awk '{print $1}' | grep -qx "$NETNS"
}

# POSTs a JSON body and echoes the id from the Location header. On any other outcome it dies
# quoting the response body, because the interesting failures here are reported in the body and
# not in the header: an exhausted TMGI pool, an SSM already in use by another session, and a
# malformed body all otherwise present identically as "no Location header".
post_for_id() {
    local what="$1" url="$2" auth="$3" body="$4"
    local hdr_file resp_file code loc
    hdr_file="$(mktemp)"; resp_file="$(mktemp)"
    code=$(curl -s -m 30 -u "$auth" -X POST -H 'Content-Type: application/json' \
                -D "$hdr_file" -o "$resp_file" -w '%{http_code}' "$url" -d "$body" || echo 000)
    loc=$(grep -i '^location:' "$hdr_file" 2>/dev/null | tr -d '\r' | sed 's#.*/##')
    if [[ -n "$loc" ]]; then
        rm -f "$hdr_file" "$resp_file"
        echo "$loc"
        return 0
    fi
    local detail
    detail=$(head -c 600 "$resp_file" 2>/dev/null)
    rm -f "$hdr_file" "$resp_file"
    if [[ "$detail" == *"Cannot allocate TMGI"* ]]; then
        die "$what failed: the MB-SMF has no free TMGI.
  Its pool is OGS_MAX_NUM_OF_TMGI (20) and a TMGI is only released once its expiry passes, so
  repeated create/delete cycles exhaust it. Restart the SMF and run this again:
    pkill -f open5gs-smfd && ./01-start-core-nfs.sh"
    fi
    if [[ "$detail" == *"already used in another"* ]]; then
        die "$what failed: SSM $BCAST_SSM_DEST is already used by another Distribution Session.
  A previous session is still registered. Run ./stop-all.sh, or delete it via the provider, then
  run this again."
    fi
    die "$what failed (HTTP $code): ${detail:-no response body}"
}

# Brings the machine back to a known-empty state before a run. stop-all.sh alone is not enough:
# it works from pidfiles, so a process whose pidfile was lost (an interrupted run, a manual
# start) survives it, keeps its ports and, in MBSF's case, keeps the Distribution Session that
# then makes the next run fail with the SSM already in use. Matching is on the executable name
# (pkill -x), never the command line, so this cannot match the caller.
reset_demo() {
    log "resetting: stopping anything already running"
    ./stop-all.sh >/dev/null 2>&1 || true

    local nf
    for nf in open5gs-mbstfd open5gs-mbsfd open5gs-nrfd open5gs-amfd open5gs-smfd \
              open5gs-upfd open5gs-udmd open5gs-udrd open5gs-ausfd open5gs-pcfd \
              open5gs-nssfd open5gs-bsfd mbs-client; do
        pkill -x -TERM "$nf" 2>/dev/null || true
    done

    # Node services and the encoder have no distinct executable name, so match them by the
    # directory they run from, which is specific to this checkout.
    local pid
    for pid in $(pgrep -f "node .*$PROVIDER_DIR" 2>/dev/null || true) \
               $(pgrep -f "node .*$APP_DIR" 2>/dev/null || true) \
               $(pgrep -f "node .*$MEDIA_DIR" 2>/dev/null || true) \
               $(pgrep -f "ffmpeg .*$MEDIA_DIR/public" 2>/dev/null || true); do
        [[ "$pid" == "$$" ]] && continue
        kill -TERM "$pid" 2>/dev/null || true
    done

    sleep 3
    for nf in open5gs-mbstfd open5gs-mbsfd mbs-client; do
        pkill -x -KILL "$nf" 2>/dev/null || true
    done
    rm -f "$PID_DIR"/*.pid
    sleep 1
}
