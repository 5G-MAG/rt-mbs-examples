#!/bin/bash
# Common helpers for the mbs-broadcast-demo scripts. Source after env.sh:
#   source env.sh; source lib.sh

log()  { echo "[$(date '+%H:%M:%S')] $*"; }
die()  { echo "[$(date '+%H:%M:%S')] ERROR: $*" >&2; exit 1; }

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "missing command: $1 (install it and re-run)"
}

# Network-namespace setup and the UPF's TUN device need root, and the scripts reach for it with
# `sudo -n` throughout so that no component start can stall on an invisible password prompt behind
# tmux. That only works once a sudo timestamp exists, so acquire one here, interactively, before any
# of it runs. A no-op where sudo is already passwordless or the timestamp is still valid.
ensure_sudo() {
    sudo -n true 2>/dev/null && return 0
    [[ -t 0 ]] || die "sudo needs a password and there is no terminal to ask on. Run 'sudo -v' first, then re-run this script."
    log "sudo is needed for the network namespace and the UPF TUN device; asking once now"
    sudo -v || die "could not acquire sudo"
}

# The UE is rejected at registration unless its SUPI is in the UDR's database, and a clean MongoDB
# has no subscribers at all. The failure surfaces three components away from its cause, as
# "Cannot find SUPI in DB" in the UDR and "PLMN not allowed" at the UE, so provision it here rather
# than leaving it as a manual step nobody reads about until the demo has already failed.
# Idempotent: an existing row is left alone, so re-running never disturbs a provisioned database.
ensure_subscriber() {
    local dbctl="$OPEN5GS_DIR/misc/db/open5gs-dbctl"
    local uri="${OPEN5GS_DB_URI:-mongodb://127.0.0.1/open5gs}"

    require_cmd mongosh
    [[ -x "$dbctl" ]] || die "open5gs-dbctl not found at $dbctl (is OPEN5GS_DIR correct?)"

    if mongosh --quiet --eval "db.subscribers.countDocuments({imsi:\"$UE_IMSI\"})" "$uri" 2>/dev/null | grep -qx "1"; then
        log "subscriber $UE_IMSI already provisioned"
        return 0
    fi

    log "provisioning subscriber $UE_IMSI in $uri"
    DB_URI="$uri" "$dbctl" add_ue_with_slice "$UE_IMSI" "$UE_KEY" "$UE_OPC" internet 1 000001 >/dev/null \
        || die "could not provision subscriber $UE_IMSI"

    mongosh --quiet --eval "db.subscribers.countDocuments({imsi:\"$UE_IMSI\"})" "$uri" 2>/dev/null | grep -qx "1" \
        || die "open5gs-dbctl reported success but $UE_IMSI is not in the database"
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

# The channel line-up, as tab-separated rows so a caller can read it with `while IFS=$'\t' read`.
# channels.json is the single definition the encoders and the provisioning step both work from,
# so an encoder and a Distribution Session cannot disagree about which presentation a channel is.
#
# DEMO_CHANNELS limits both to the ids it names (space or comma separated), for a machine
# that cannot encode the whole line-up at once. Unset, the whole line-up runs.
#
#   channel_rows   every channel:  id  stream  source  type  videoBitrate
#   onair_rows     onAir only:     id  name  stream  ssmDest
channel_rows() {
    python3 -c '
import json, os, sys
only = [x for x in os.environ.get("DEMO_CHANNELS", "").replace(",", " ").split() if x]
for c in json.load(open(sys.argv[1]))["channels"]:
    if only and c["id"] not in only: continue
    print("\t".join([c["id"], c["stream"], c["source"], c.get("type", "linear"),
                     c.get("videoBitrate", "400k")]))
' "$CHANNELS_FILE"
}

onair_rows() {
    python3 -c '
import json, os, sys
only = [x for x in os.environ.get("DEMO_CHANNELS", "").replace(",", " ").split() if x]
for c in json.load(open(sys.argv[1]))["channels"]:
    if not c.get("onAir"): continue
    if only and c["id"] not in only: continue
    if not c.get("ssmDest"):
        sys.exit("channels.json: %s is onAir but has no ssmDest" % c["id"])
    print("\t".join([c["id"], c["name"], c["stream"], c["ssmDest"]]))
' "$CHANNELS_FILE"
}
