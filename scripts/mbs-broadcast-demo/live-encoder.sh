#!/bin/bash
# Looping live DASH encoder for the bypass demo: plays the configured source on repeat and
# writes a rolling DASH window. -stream_loop -1 is what makes the content loop forever, so the
# client keeps receiving new segments instead of a fixed-length presentation that ends.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source env.sh
source lib.sh

SRC="${LIVE_SRC:-$LIVE_SOURCE_MEDIA}"
DST="${LIVE_DST:-$MEDIA_DIR/public/$LIVE_STREAM_NAME}"
SEG="${LIVE_SEG_DURATION:-5}"
# Keep far more segments on disk than the presentation window advertises: the MBSTF pulls each
# object after it appears in the manifest, and a short retention lets a segment be deleted
# before that fetch happens, which shows up as a 404 storm and a sender that never catches up.
WIN="${LIVE_WINDOW:-24}"
EXTRA="${LIVE_EXTRA_WINDOW:-48}"

require_cmd ffmpeg

# Nothing in this demo depends on what the picture actually shows, so a missing source file is
# not a reason to be unable to run it. Fall back to a generated test pattern with a tone, which
# ffmpeg synthesises itself: the demo then has no content prerequisite at all, and a deployment
# that does have its own media still gets it by setting LIVE_SOURCE_MEDIA.
if [[ -f "$SRC" ]]; then
    log "source: $SRC"
    input=(-stream_loop -1 -i "$SRC")
else
    log "source: none at $SRC, generating a test pattern instead (set LIVE_SOURCE_MEDIA to use your own)"
    input=(-f lavfi -i "testsrc2=size=960x540:rate=30" -f lavfi -i "sine=frequency=440:sample_rate=48000")
fi

# Audio and video are written as two Adaptation Sets because ffmpeg's DASH muxer cannot write them
# as one: it requires every stream in an Adaptation Set to share a codec type, and rejects a mixed set
# at header-write time ("Codec type of stream ... "). Confirmed by direct test of all three spellings
# -- "streams=0,1", "streams=v,a" and two sets sharing id=0 -- of which only genuinely separate sets
# are accepted.
#
# ISO/IEC 23009-1 clause 5.3.1 admits either arrangement: it gives separate video and audio Adaptation
# Sets as its example, and also allows "a single Adaptation Set ... containing both the main audio and
# main video". So this is a tool limitation, not a specification one, and a muxed presentation needs a
# different packager (GPAC MP4Box) or a different delivery format.
#
# DASH_ADAPTATION_SETS overrides the arrangement for a deployment whose packager can do more.
mkdir -p "$DST"
rm -f "$DST"/*.m4s "$DST"/*.tmp "$DST"/manifest.mpd 2>/dev/null || true
log "encoding -> $DST (${SEG}s segments, window $WIN + $EXTRA)"
exec ffmpeg -re -fflags +genpts "${input[@]}" \
  -vf scale=960:540 -c:v libx264 -profile:v main -pix_fmt yuv420p \
  -b:v 400k -maxrate:v 400k -bufsize:v 800k -g $((SEG*30)) -keyint_min $((SEG*30)) -sc_threshold 0 -r 30 \
  -c:a aac -ar 48000 -b:a 64k \
  -seg_duration "$SEG" -use_template 1 -use_timeline 1 \
  -window_size "$WIN" -extra_window_size "$EXTRA" \
  -adaptation_sets "${DASH_ADAPTATION_SETS:-id=0,streams=v id=1,streams=a}" \
  -f dash "$DST/manifest.mpd"
