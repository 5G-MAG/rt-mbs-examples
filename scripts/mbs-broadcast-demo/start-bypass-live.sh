#!/bin/bash
# Brings up the looping-content MBS broadcast demo without the RAN: MBSTF sends over loopback
# and rt-mbs-client receives there directly, so the whole service chain
# (rt-mbs-application-provider -> MBSF -> MBSTF -> rt-mbs-client -> rt-mbs-application) runs
# without a gNB or UE.
#
# Use this when you want to see the service, the session and the video, and the radio is not
# what you are testing. start-all.sh is the counterpart that includes the RAN.
#
# What it starts, in order:
#   1. core NFs and the MBS functions (shared with start-all.sh)
#   2. the media server
#   3. a looping live DASH encoder (live-encoder.sh), which is what makes the content loop
#      instead of ending after one pass of the source file
#   4. the MBS user service and ingest session, created THROUGH the provider so its UI lists
#      them rather than only MBSF knowing about them
#   5. rt-mbs-client bound to loopback, plus the application and the provider
#   6. activation of the service on the client
#
# The media session runs in OBJECT_STREAMING with the DASH MPD as its entry point, which is the
# mode 3GPP recommends for DASH content (TS 26.517 clause 6.2.3.5) and the one that paces objects
# against their own availability times. It is deliberately not a carousel: a carousel repeats a
# fixed object list rather than following the presentation manifest, so it re-sends segments the
# receiver already has while never picking up newly published ones. live-carousel.sh, which builds
# such a list, is therefore not started here; it remains for demonstrating OBJECT_CAROUSEL itself,
# for which the User Service Announcement Channel is the real example.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source env.sh
source lib.sh
ensure_dirs

SERVICE_ID="${BYPASS_SERVICE_ID:-https://mwc-tv-radio.ebu.io/services/tv_1_live}"
SERVICE_CLASS="${BYPASS_SERVICE_CLASS:-urn:oma:bcast:oma_bsc:st:1.0}"
SERVICE_NAME="${BYPASS_SERVICE_NAME:-MWC TV 1 live loop}"
SERVICE_DESC="${BYPASS_SERVICE_DESC:-Looping live DASH}"

# Segment duration the encoder produces, and the pace at which segments are therefore expected
# to arrive: one segment in, one segment out.
SEG_DURATION_S="${LIVE_SEG_DURATION:-5}"
# The presentation the encoder writes, and therefore the entry point the ingest session pulls,
# is named once in env.sh so this script and live-encoder.sh cannot disagree about it.
# Session maximum bit rate for the media Distribution Session. The presentation itself is about
# 0.5 Mbps (400 kbps video plus 64 kbps audio), and in OBJECT_STREAMING each object is sent once
# rather than repeatedly, so this is generous headroom rather than a figure to tune. Raise it only
# for genuinely higher-bitrate content.
SESSION_MAX_BITRATE="${BYPASS_MAX_BITRATE:-6 Mbps}"

PROVIDER_URL="http://127.0.0.1:$PROVIDER_PORT"
PROVIDER_AUTH="$PROVIDER_AUTH_USER:$PROVIDER_AUTH_TOKEN"
CLIENT_API="http://127.0.0.1:$MBS_CLIENT_API_PORT/mbs-client-api"
BYPASS_CONF="$GEN_CONF_DIR/rt-mbs-client-bypass.conf"

# Preflight. Everything this run needs is checked before anything is started, so a missing build
# fails in seconds with the command that fixes it, rather than part-way through bringing up eight
# network functions and leaving them running.
preflight() {
    local missing=0
    check_built() {
        [[ -x "$1" ]] && return 0
        echo "  missing: $1" >&2
        echo "      build it with: $2" >&2
        missing=1
    }
    check_built "$OPEN5GS_BUILD/src/nrf/open5gs-nrfd"    "cd $OPEN5GS_DIR && meson setup build && ninja -C build"
    check_built "$OPEN5GS_BUILD/src/smf/open5gs-smfd"    "cd $OPEN5GS_DIR && ninja -C build"
    check_built "$MBSTF_BUILD/src/mbstf/open5gs-mbstfd"  "cd $MBSTF_DIR && meson setup build && ninja -C build"
    check_built "$MBSF_BUILD/src/mbsf/open5gs-mbsfd"     "cd $MBSF_DIR && meson setup build && ninja -C build"
    check_built "$CLIENT_BIN"                            "cd $CLIENT_DIR && cmake -B build && make -C build"
    for c in ffmpeg curl node npm; do
        command -v "$c" >/dev/null 2>&1 || { echo "  missing command: $c" >&2; missing=1; }
    done
    [[ $missing -eq 0 ]] || die "preflight failed, see above. Nothing was started."
}
preflight

# Always start from zero unless told not to. A demo that half-starts on top of a previous run is
# the single most common way this fails, and the failure surfaces far from its cause (an SSM still
# held by a surviving MBSF, a port still bound, a client still joined to a dead session).
if [[ "${BYPASS_KEEP_RUNNING:-0}" != "1" ]]; then
    reset_demo
fi

log "=== 1/6 core NFs and MBS functions ==="
./01-start-core-nfs.sh
./02-start-mbs-function.sh

log "=== 2/6 media server ==="
./03-start-media-server.sh

# Where the presentation comes from. Either this demo produces one by encoding a looping live
# stream, or it distributes a presentation that already exists under the media server's public
# directory. Anything the MBSTF can pull and parse as a DASH MPD works, so a deployment with its
# own content does not need the encoder at all:
#   LIVE_PRESENTATION=my_channel/manifest.mpd ./start-bypass-live.sh
if [[ -n "${LIVE_PRESENTATION:-}" ]]; then
    log "=== 3/6 using the existing presentation $LIVE_PRESENTATION ==="
    PRESENTATION_PATH="$LIVE_PRESENTATION"
    [[ -f "$MEDIA_DIR/public/$PRESENTATION_PATH" ]] || \
        die "no presentation at $MEDIA_DIR/public/$PRESENTATION_PATH
  LIVE_PRESENTATION names a manifest relative to the media server's public directory."
else
    PRESENTATION_PATH="$LIVE_STREAM_NAME/manifest.mpd"
    log "=== 3/6 looping live encoder ==="
    if pgrep -f "live-encoder.sh|ffmpeg -re -fflags .*$LIVE_STREAM_NAME" >/dev/null 2>&1; then
        log "live encoder already running, leaving it alone"
    else
        LIVE_SEG_DURATION="$SEG_DURATION_S" nohup ./live-encoder.sh > "$LOG_DIR/live-encoder.log" 2>&1 &
        disown
    fi
    # Nothing can be distributed until the encoder has written its first segments.
    log "waiting for the encoder's first segments"
    for _ in $(seq 1 60); do
        [[ $(ls "$MEDIA_DIR/public/$LIVE_STREAM_NAME"/chunk-stream0-*.m4s 2>/dev/null | wc -l) -ge 2 ]] && break
        sleep 2
    done
    [[ $(ls "$MEDIA_DIR/public/$LIVE_STREAM_NAME"/chunk-stream0-*.m4s 2>/dev/null | wc -l) -ge 2 ]] || \
        die "the encoder produced no segments in 120s; see $LOG_DIR/live-encoder.log"
    sleep "$SEG_DURATION_S"
fi

# The Distribution Session's entry point must be fetchable and parseable before the session is
# created. MBSTF fetches it once when the session starts and, if that fetch fails, falls back to a
# non-DASH handler for the life of the session: the symptom is a session that comes up cleanly and
# then delivers nothing, with only "Object ingest failed ... reason = 3" in its log. Waiting here
# for the media server to actually serve a manifest that names segments removes that race.
log "waiting for $PRESENTATION_PATH to be servable"
manifest_ready=0
for _ in $(seq 1 60); do
    body=$(curl -s -m 5 "http://$MEDIA_HOST:$MEDIA_PORT/$PRESENTATION_PATH" 2>/dev/null || true)
    if [[ "$body" == *"<MPD"* && "$body" == *"<S "* ]]; then manifest_ready=1; break; fi
    sleep 2
done
[[ $manifest_ready -eq 1 ]] || die "the media server never served a usable manifest at
  http://$MEDIA_HOST:$MEDIA_PORT/$PRESENTATION_PATH
  Check $LOG_DIR/live-encoder.log and $LOG_DIR/media-server.log."

log "=== 4/6 application, provider and MBS client ==="
# The client joins the SSM group on loopback, where MBSTF actually sends it. raw_capture_relay
# is deliberately off: that exists only because a TUN device cannot do OS-level multicast
# delivery, which is a RAN-path concern and does not apply here.
cat > "$BYPASS_CONF" <<EOF
log_level: "debug";

mbsf_client: {
  api_root: "http://$MBSF_ADDR:8888";
  announcement_channel: {
    multicast_address: "232.0.0.1";
    port: 3000;
    tsi: 1;
    source_address: "$MBSF_ADDR";
  }
}

mbstf_client: {
  flute_iface: "127.0.0.1";
  raw_capture_relay: false;
}

mbs_aware_api: {
  listen_uri: "http://127.0.0.1:$MBS_CLIENT_API_PORT/mbs-client-api";
}
EOF

# Port 3050 may still be held by start-all.sh's netns relay; the application binds it directly here.
for p in $(pgrep -f "socat.*TCP-LISTEN:$APP_PORT" 2>/dev/null || true); do kill "$p" 2>/dev/null || true; done

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
[[ -d "$PROVIDER_DIR/node_modules" ]] || (cd "$PROVIDER_DIR" && npm install --no-audit --no-fund)
run_bg "rt-mbs-application-provider" provider bash -c "cd '$PROVIDER_DIR' && node server.js"

cat > "$APP_DIR/.env" <<EOF
PORT=$APP_PORT
MBS_CLIENT_HOST=127.0.0.1
MBS_CLIENT_PORT=$MBS_CLIENT_API_PORT
RADIO_HOST=localhost
RADIO_PORT=$RADIO_API_PORT
EOF
[[ -d "$APP_DIR/node_modules" ]] || (cd "$APP_DIR" && npm install --no-audit --no-fund)
run_bg "rt-mbs-application" app bash -c "cd '$APP_DIR' && node app.js"

run_bg "rt-mbs-client" rt-mbs-client "$CLIENT_BIN" "$BYPASS_CONF"
wait_for_http "$PROVIDER_URL/" 20 || true

if [[ "${BYPASS_PROVISION:-1}" == "1" ]]; then
    log "=== 5/6 service and ingest session, via the provider ==="
    PRESENTATION_PATH="$PRESENTATION_PATH" SESSION_MAX_BITRATE="$SESSION_MAX_BITRATE" \
        CLIENT_API="$CLIENT_API" ./06-provision-live-service.sh
else
    log "=== 5/6 skipping provisioning (BYPASS_PROVISION=0) ==="
    log "    create the service and ingest session in the provider UI; see templates/README.md"
fi

log ""
log "=== bypass demo up (no gNB/UE) ==="
log "  Application (player):  http://127.0.0.1:$APP_PORT/"
log "  Application-provider:  $PROVIDER_URL/  (login: $PROVIDER_AUTH_USER / $PROVIDER_AUTH_TOKEN)"
log "  MBS client API:        $CLIENT_API/content"
log "  Presentation manifest: http://$MEDIA_HOST:$MEDIA_PORT/$PRESENTATION_PATH"
log ""
log "  Segments should now arrive one per ${SEG_DURATION_S}s. To check:"
log "    curl -s $CLIENT_API/content | grep -o '\"location\":\"[^\"]*\"' | wc -l"
log "  To stop everything: ./stop-all.sh   (it stops the encoder too)"
