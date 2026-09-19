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
ensure_sudo

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
    log "=== 4/7 looping live encoders, one per channel ==="
    # Every channel in channels.json is encoded and served by the origin, whether or not it is
    # carried over the radio, so this demo offers the same four channels under the same names as
    # the MBMS and DVB-I ones. Which of them go on air is decided in step 7.
    while IFS=$'\t' read -r ch_id ch_stream ch_source ch_type ch_vbr; do
        if pgrep -f "ffmpeg -re .*/$ch_stream" >/dev/null 2>&1; then
            log "  $ch_id: encoder already running, leaving it alone"
            continue
        fi
        log "  $ch_id -> $ch_stream"
        LIVE_SOURCE_MEDIA="$CONTENT_ROOT/$ch_source" LIVE_STREAM_NAME="$ch_stream" \
            LIVE_TYPE="$ch_type" LIVE_VIDEO_BITRATE="$ch_vbr" \
            LIVE_SEG_DURATION="$SEG_DURATION_S" \
            nohup ./live-encoder.sh > "$LOG_DIR/live-encoder-$ch_id.log" 2>&1 &
        disown
    done < <(channel_rows)

    log "waiting for each encoder's first segments"
    while IFS=$'\t' read -r ch_id ch_stream ch_source ch_type ch_vbr; do
        for _ in $(seq 1 90); do
            [[ $(ls "$MEDIA_DIR/public/$ch_stream"/chunk-stream0-*.m4s 2>/dev/null | wc -l) -ge 2 ]] && break
            sleep 2
        done
        [[ $(ls "$MEDIA_DIR/public/$ch_stream"/chunk-stream0-*.m4s 2>/dev/null | wc -l) -ge 2 ]] || \
            die "no segments for $ch_id in 180s; see $LOG_DIR/live-encoder-$ch_id.log"
    done < <(channel_rows)
fi

# The entry point must be servable before the session is created: the MBSTF fetches it once and
# does not retry, so a session created too early comes up healthy and then delivers nothing.
while IFS=$'\t' read -r ch_id ch_name ch_stream ch_ssm; do
    log "waiting for $ch_stream/manifest.mpd to be servable"
    manifest_ready=0
    for _ in $(seq 1 60); do
        body=$(curl -s -m 5 "http://$MEDIA_HOST:$MEDIA_PORT/$ch_stream/manifest.mpd" 2>/dev/null || true)
        if [[ "$body" == *"<MPD"* && "$body" == *"<S "* ]]; then manifest_ready=1; break; fi
        sleep 2
    done
    [[ $manifest_ready -eq 1 ]] || die "the media server never served a usable manifest at
  http://$MEDIA_HOST:$MEDIA_PORT/$ch_stream/manifest.mpd"
done < <(onair_rows)

log "=== 5/7 gNB and UE ==="
./04-start-ran.sh

log "=== 6/7 MBS client (in $NETNS, on the UE's PDU session), application and provider ==="
./05-start-client-and-app.sh

log "=== 7/7 MBS User Services for the on-air channels, via the provider ==="
# One MBS User Service and one Distribution Session per on-air channel, each on its own SSM.
# The client's API lives inside the network namespace here, so reach it from there.
while IFS=$'\t' read -r ch_id ch_name ch_stream ch_ssm; do
    log "  $ch_name ($ch_stream) on $ch_ssm"
    BYPASS_SERVICE_ID="https://mwc-tv-radio.ebu.io/services/$ch_stream" \
        BYPASS_SERVICE_NAME="$ch_name" \
        BYPASS_SERVICE_DESC="Looping live DASH" \
        BCAST_SSM_DEST="$ch_ssm" \
        PRESENTATION_PATH="$ch_stream/manifest.mpd" \
        SESSION_MAX_BITRATE="$SESSION_MAX_BITRATE" \
        CLIENT_API="http://127.0.0.1:$MBS_CLIENT_API_PORT/mbs-client-api" \
        CLIENT_CURL="sudo -n ip netns exec $NETNS curl" \
        ./06-provision-live-service.sh
done < <(onair_rows)

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
