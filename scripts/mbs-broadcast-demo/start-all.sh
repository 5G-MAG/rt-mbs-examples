#!/bin/bash
# The whole MBS Broadcast demo: exactly the live DASH service start-bypass-live.sh runs, plus the
# real radio path. Same encoder, same media server, same MBS User Service and Ingest Session in
# OBJECT_STREAMING, same provider and player. The only difference is what carries the FLUTE
# packets: a gNB and UE pair over ZMQ RF loopback instead of the host's own loopback interface,
# with the MBS Client running inside the gNB network namespace on the UE's own PDU session.
#
# Provisioning is shared with the RAN-free path (06-provision-live-service.sh) so the two cannot
# drift apart: if the service works without the radio, the same service is what goes over it.
#
# See README.md for the three entry points and what each is for.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source env.sh
source lib.sh
ensure_dirs

SEG_DURATION_S="${LIVE_SEG_DURATION:-5}"
PRESENTATION_PATH="${LIVE_PRESENTATION:-$LIVE_STREAM_NAME/manifest.mpd}"
SESSION_MAX_BITRATE="${BYPASS_MAX_BITRATE:-6 Mbps}"

require_file "$GNB_BIN"
require_file "$UE_BIN"
require_cmd ffmpeg
require_cmd curl

# Start from zero unless told otherwise, for the reason start-bypass-live.sh does: a run on top
# of a previous one fails far from its cause, most often as an SSM still held by a surviving MBSF.
if [[ "${DEMO_KEEP_RUNNING:-0}" != "1" ]]; then
    reset_demo
fi

log "=== 1/7 network namespace ==="
./00-setup-netns.sh

log "=== 2/7 core NFs and MBS functions ==="
./01-start-core-nfs.sh
./02-start-mbs-function.sh

log "=== 3/7 media server ==="
./03-start-media-server.sh

if [[ -n "${LIVE_PRESENTATION:-}" ]]; then
    log "=== 4/7 using the existing presentation $LIVE_PRESENTATION ==="
    [[ -f "$MEDIA_DIR/public/$PRESENTATION_PATH" ]] || \
        die "no presentation at $MEDIA_DIR/public/$PRESENTATION_PATH"
else
    log "=== 4/7 looping live encoder ==="
    if pgrep -f "live-encoder.sh|ffmpeg -re -fflags .*$LIVE_STREAM_NAME" >/dev/null 2>&1; then
        log "live encoder already running, leaving it alone"
    else
        LIVE_SEG_DURATION="$SEG_DURATION_S" nohup ./live-encoder.sh > "$LOG_DIR/live-encoder.log" 2>&1 &
        disown
    fi
    log "waiting for the encoder's first segments"
    for _ in $(seq 1 60); do
        [[ $(ls "$MEDIA_DIR/public/$LIVE_STREAM_NAME"/chunk-stream0-*.m4s 2>/dev/null | wc -l) -ge 2 ]] && break
        sleep 2
    done
    [[ $(ls "$MEDIA_DIR/public/$LIVE_STREAM_NAME"/chunk-stream0-*.m4s 2>/dev/null | wc -l) -ge 2 ]] || \
        die "the encoder produced no segments in 120s; see $LOG_DIR/live-encoder.log"
fi

# The entry point must be servable before the session is created: the MBSTF fetches it once and
# does not retry, so a session created too early comes up healthy and then delivers nothing.
log "waiting for $PRESENTATION_PATH to be servable"
manifest_ready=0
for _ in $(seq 1 60); do
    body=$(curl -s -m 5 "http://$MEDIA_HOST:$MEDIA_PORT/$PRESENTATION_PATH" 2>/dev/null || true)
    if [[ "$body" == *"<MPD"* && "$body" == *"<S "* ]]; then manifest_ready=1; break; fi
    sleep 2
done
[[ $manifest_ready -eq 1 ]] || die "the media server never served a usable manifest at
  http://$MEDIA_HOST:$MEDIA_PORT/$PRESENTATION_PATH"

log "=== 5/7 gNB and UE ==="
./04-start-ran.sh

log "=== 6/7 MBS client (in $NETNS, on the UE's PDU session), application and provider ==="
./05-start-client-and-app.sh

log "=== 7/7 service and ingest session, via the provider ==="
# The client's API lives inside the network namespace here, so reach it from there.
PRESENTATION_PATH="$PRESENTATION_PATH" SESSION_MAX_BITRATE="$SESSION_MAX_BITRATE" \
    CLIENT_API="http://127.0.0.1:$MBS_CLIENT_API_PORT/mbs-client-api" \
    CLIENT_CURL="sudo -n ip netns exec $NETNS curl" \
    ./06-provision-live-service.sh

log ""
log "=== all up (gNB + UE) ==="
log "  Application (player):  http://localhost:$APP_PORT/  (also http://$VETH_NS_ADDR:$APP_PORT/)"
log "  Application-provider:  http://127.0.0.1:$PROVIDER_PORT/  (login: $PROVIDER_AUTH_USER / $PROVIDER_AUTH_TOKEN)"
log "  Presentation manifest: http://$MEDIA_HOST:$MEDIA_PORT/$PRESENTATION_PATH"
log "  Logs:                  $LOG_DIR/"
log ""
log "  What the client holds (its API is inside $NETNS):"
log "    sudo ip netns exec $NETNS curl -s http://127.0.0.1:$MBS_CLIENT_API_PORT/mbs-client-api/content"
log "  To stop everything: ./stop-all.sh   (it stops the encoder too)"
