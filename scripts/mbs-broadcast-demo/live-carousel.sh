#!/bin/bash
# Regenerates public/carousel-live so the MBSTF sends live DASH segments at the pace the
# encoder produces them: one segment period in, one segment period out.
#
# Why this exists alongside 07-live-carousel-regen.sh: that script advertises the encoder's
# whole window (dozens of objects) and derives a repetition interval from the window's byte
# total against a bitrate ceiling. For a live stream that makes the sender re-transmit every
# segment it still holds, over and over, so it spends its capacity repeating old segments and
# falls progressively further behind the encoder -- observed as the sender fetching segments
# that had already rotated off disk (404) while the receiver's newest segment stayed minutes
# old.
#
# A live carousel only has to do two things:
#   - carry the bootstrap objects (the MPD and the init segments) often enough that a receiver
#     joining at any time can start, and
#   - carry each media segment once, promptly, while it is still current.
# So the media window advertised here is deliberately short (LIVE_CAROUSEL_SEGMENTS newest
# segments per stream) and its repetition interval is the segment duration: a new segment is
# picked up within one segment period, and nothing is repeated more than it needs to be.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source env.sh
source lib.sh

DST_DIR="$MEDIA_DIR/public/tv_1_live"
OUT_PATH="$MEDIA_DIR/public/carousel-live"

SEG_DURATION_S="${LIVE_SEG_DURATION:-5}"
# Newest N segments per stream to advertise. Small on purpose: this is a live window, not a
# catalogue. Large enough that a receiver joining mid-stream gets a few segments to build a
# playable presentation from, small enough that the sender is never repeating stale content.
SEGMENTS="${LIVE_CAROUSEL_SEGMENTS:-4}"
# How often MBSTF re-reads this manifest. One segment period keeps it in step with the encoder
# without re-polling for no reason.
UPDATE_INTERVAL_S="$SEG_DURATION_S"
# How often each advertised object is repeated. Deliberately separate from the segment
# duration: what stops a segment being missed is how long it stays advertised (window size x
# repetition), not how fast it is repeated. Repeating less often at the same window size costs
# less bandwidth for the same exposure, which matters because the sender is the bottleneck.
REPETITION_MS="${LIVE_REPETITION_MS:-$((SEG_DURATION_S * 2000))}"

log "regenerating $OUT_PATH every ${UPDATE_INTERVAL_S}s: newest $SEGMENTS segments/stream at ${SEG_DURATION_S}s repetition"
while true; do
    if [[ -d "$DST_DIR" ]]; then
        python3 - "$DST_DIR" "$MEDIA_HOST" "$MEDIA_PORT" "$OUT_PATH" "$UPDATE_INTERVAL_S" "$REPETITION_MS" "$SEGMENTS" <<'PYEOF'
import json, os, re, sys, time

dst_dir, host, port, out_path, update_interval_s, repetition_ms, keep = sys.argv[1:8]
update_interval_s = int(update_interval_s)
seg_ms = int(repetition_ms)
keep = int(keep)
stream = os.path.basename(dst_dir)

# A segment is only advertised once it is safely finished and not about to be deleted.
# ffmpeg writes to <name>.tmp and renames, so a file appearing here is already complete, but
# leaving a small age margin also keeps the newest entry from racing the encoder's own rename.
MIN_AGE_S = 1.0
now = time.time()

def age_ok(path):
    try:
        return (now - os.path.getmtime(path)) >= MIN_AGE_S
    except OSError:
        return False

entries = []

# Bootstrap objects: the presentation manifest and one init segment per representation. These
# never rotate, and a receiver cannot decode anything without them, so they are repeated every
# cycle rather than being part of the rolling media window.
for name in sorted(os.listdir(dst_dir)):
    if name == "manifest.mpd" or re.fullmatch(r"init-stream\d+\.m4s", name):
        p = os.path.join(dst_dir, name)
        if os.path.isfile(p) and age_ok(p):
            entries.append(name)

# Rolling media window: the newest `keep` segments of each representation.
by_stream = {}
for name in os.listdir(dst_dir):
    m = re.fullmatch(r"chunk-stream(\d+)-(\d+)\.m4s", name)
    if not m:
        continue
    p = os.path.join(dst_dir, name)
    if not os.path.isfile(p) or not age_ok(p):
        continue
    by_stream.setdefault(m.group(1), []).append((int(m.group(2)), name))

for sid in sorted(by_stream):
    newest = sorted(by_stream[sid], key=lambda x: x[0])[-keep:]
    entries.extend(name for _, name in newest)

# The bootstrap objects repeat more often than the media window. MBSTF schedules by transmit
# deadline (ObjectCarouselPackager::scheduleCarousel()), so an object's repetition interval is
# what decides whether it is ever reached: with every object on the same interval the media
# segments, which are always newer, keep taking the slots and the manifest and initialisation
# segments are never sent at all -- observed directly, a receiver getting media segments and
# zero bootstrap objects, which leaves it unable to play anything. A receiver needs these
# before it needs any segment, so they are given the shortest interval here.
BOOTSTRAP_MS = max(1000, seg_ms // 4)

def is_bootstrap(name):
    return name == "manifest.mpd" or name.startswith("init-stream")

objects = [
    {
        "locator": "http://%s:%s/%s/%s" % (host, port, stream, name),
        "repetitionInterval": BOOTSTRAP_MS if is_bootstrap(name) else seg_ms,
    }
    for name in entries
]

with open(out_path, "w") as f:
    json.dump({"updateInterval": update_interval_s, "objects": objects}, f, indent=2)

total = sum(os.path.getsize(os.path.join(dst_dir, n)) for n in entries)
print("%d objects, %d bytes, repetitionInterval=%dms -> %.2f Mbps"
      % (len(objects), total, seg_ms, (total * 8.0) / (seg_ms / 1000.0) / 1e6))
PYEOF
    fi
    sleep "$UPDATE_INTERVAL_S"
done
