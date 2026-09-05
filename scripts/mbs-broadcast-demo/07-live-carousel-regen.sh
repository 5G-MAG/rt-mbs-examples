#!/bin/bash
# Regenerates public/carousel-live in a loop, reflecting whatever segments a live
# ffmpeg encoder (see the live-DASH command in the register's own "looping content" entry,
# ported from rt-mbms-examples/flute-ffmpeg/files/ffmpeg-dash.sh's proven pattern:
# `-stream_loop -1 ... -f dash -use_template 1 -use_timeline 1 -window_size N`) currently has
# on disk in $DST_DIR. MBSTF's own ObjectManifestHandler already re-fetches a carousel manifest
# on a schedule when the manifest itself declares "updateInterval" (seconds, TS 26.517 Annex
# D.1 -- confirmed code-derived, ObjectManifestHandler.cc's own
# `ingest_time = ... + std::chrono::seconds(manifest_update_interval.value())`), so this script
# only needs to keep that one JSON file honest; MBSTF does the rest of the re-polling itself.
#
# Unlike 03-start-media-server.sh's own one-shot carousel generation (a fixed, known object
# set), this content set genuinely changes shape over time (ffmpeg's own sliding window adds
# new segments and, once window_size is exceeded, deletes old ones from disk). A first version
# of this script gave every object a fixed 3s repetitionInterval regardless of how much content
# was actually in the window -- with ffmpeg's own window stabilised at ~2.2MB (43 objects),
# that demanded ~6.0 Mbps sustained (measured live, this session: total_bytes*8/3s), wildly out
# of proportion with this whole project's own bitrate conventions. Fixed the same way
# 03-start-media-server.sh already budgets its own static carousel: repetitionInterval is now
# computed fresh each cycle from the window's actual current byte total against
# LIVE_INGEST_MAX_BITRATE (env.sh), not a fixed guess.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source env.sh
source lib.sh

DST_DIR="$MEDIA_DIR/public/tv_1_live"
OUT_PATH="$MEDIA_DIR/public/carousel-live"

# 3s: fast enough to keep pace with the live encoder's own 2s segment duration (checked live,
# this session, against the actual ffmpeg -seg_duration value used) without re-fetching on
# every single new segment. Not a spec value -- see rule 12: this is an engineering choice
# tied to a stated basis (the encoder's own segment duration), not an arbitrary number. This is
# how often MBSTF re-fetches this manifest (via its own "updateInterval" field below); it is
# deliberately kept separate from repetitionInterval, which is recomputed below from the
# window's real size against LIVE_INGEST_MAX_BITRATE, not tied to this constant.
UPDATE_INTERVAL_S=3

log "regenerating $OUT_PATH from $DST_DIR every ${UPDATE_INTERVAL_S}s (Ctrl-C to stop)"
while true; do
    if [[ -d "$DST_DIR" ]]; then
        python3 - "$DST_DIR" "$MEDIA_HOST" "$MEDIA_PORT" "$OUT_PATH" "$UPDATE_INTERVAL_S" "$LIVE_INGEST_MAX_BITRATE" <<'PYEOF'
import json, os, re, sys, time

dst_dir, host, port, out_path, update_interval_s, max_bitrate_str = sys.argv[1:7]
update_interval_s = int(update_interval_s)
stream = os.path.basename(dst_dir)

# BUG FIX: listing a segment the instant it's visible on disk raced ffmpeg's own eviction
# (window_size/extra_window_size) -- a segment snapshotted here could already be deleted by
# the time MBSTF's PullObjectIngester got to fetching it a cycle or two later. Confirmed live:
# this produced a tight, unbounded retry loop (MBSTF has no backoff/cap on a single object's
# repeated fetch failures, only a consecutive-failures-across-the-session counter that a
# concurrent successful ingest resets), which exhausted MBSTF's own SBI message pool
# (ogs_pool_alloc() failed) and killed the process outright -- a real MBSTF defect, but the
# fastest, safe fix on this side is to never advertise a segment that isn't safely inside the
# window yet. init-stream*.m4s are written once at encoder startup and never rotate, so the
# age filter below only applies to the rotating chunk-stream*.m4s files.
now = time.time()
MIN_AGE_S = 3    # at least ~1.5 segment durations old: past any write-finalization race
# Tightened from 55s (window was 30+15 segments*2s=90s at the time): confirmed live this
# session that MBSTF's own PullObjectIngester is a single-threaded, sequential fetch loop
# (PullObjectIngester::doObjectIngest(), one item per call, up to a 10s timeout on a failed
# fetch) -- against ~50+ objects per cycle it can develop a real backlog, and by the time it
# gets to an object queued near the end of that backlog the object can already be evicted
# (observed: a 404 on an object still listed as valid only ~70-80s earlier). The window
# itself was also cut, from 30+15 to 10+5 segments (env.sh/the ffmpeg command), so there are
# far fewer objects to carousel per cycle and far less backlog to develop in the first place;
# this narrower age band is this script's own matching half of that same fix.
MAX_AGE_S = 15   # well inside the new ~30s window (10+5 segments * 2s), with real margin for backlog

files = []
total_bytes = 0
for name in sorted(os.listdir(dst_dir)):
    path = os.path.join(dst_dir, name)
    # Skip ffmpeg's own in-progress ".tmp" files -- listing one here would have MBSTF try to
    # fetch a file ffmpeg hasn't finished writing (or renamed into place) yet.
    if not os.path.isfile(path) or name.endswith('.tmp'):
        continue
    if name.startswith('chunk-stream'):
        age = now - os.path.getmtime(path)
        if age < MIN_AGE_S or age > MAX_AGE_S:
            continue
    files.append(name)
    total_bytes += os.path.getsize(path)

# Same parse/budget pattern as 03-start-media-server.sh's own carousel generator (rule 12: a
# bound needs a real source, here the window's own actual current byte total, not a guess).
m = re.match(r'\s*([\d.]+)\s*([KMG]?)bps\s*$', max_bitrate_str, re.IGNORECASE)
scale = {"": 1, "K": 1e3, "M": 1e6, "G": 1e9}[m.group(2).upper()]
max_bps = float(m.group(1)) * scale
margin = 0.80  # Headroom under the ingest session's declared maxContBitRate. No spec value
               # governs it (rule 12): this script and MBSTF's PullObjectIngester run on
               # independent timers against the same growing ffmpeg output, so a window
               # measured here has already grown by the time MBSTF fetches it, and the interval
               # computed from the smaller total then implies a higher rate than intended. The
               # margin absorbs that drift; see LIVE_INGEST_MAX_BITRATE in env.sh, which the
               # same drift also sizes.
# Minimum 1s floor: with an empty or near-empty window (startup transient) the division would
# otherwise produce an implausibly small interval.
rep_s = max(1.0, (total_bytes * 8) / (max_bps * margin)) if total_bytes else float(update_interval_s)
rep_ms = int(rep_s * 1000)

# BUG FIX, code-derived: every object in this list -- including manifest.mpd itself -- was
# getting the same repetitionInterval, sized for the bulk media segments' own byte budget
# (several MB every 5-20s at this window size), and no keepUpdatedInterval at all. Confirmed
# live, this session: the served manifest's own window kept trailing the actual delivered
# content by a growing margin (up to 24s and climbing) even after fixing repetitionInterval
# alone -- because repetitionInterval governs how often MBSTF *retransmits an already-fetched
# object* over FLUTE (ObjectCarouselPackager::scheduleCarousel()'s own use of it), not how often
# MBSTF re-pulls a fresh copy from origin. That second, actually-relevant schedule is
# keepUpdatedInterval (ObjectManifestHandler::finishRequest(), ObjectManifestHandler.cc:328-345):
# for an object whose locator is unchanged between manifest updates (a live manifest.mpd,
# carouselled at the same URL every cycle, unlike the chunk-stream files which get a genuinely
# new URL each time), MBSTF only re-pulls it from origin once that field's own next-fetch-time
# arrives -- with no keepUpdatedInterval set at all, it fell back to the object's own cache
# expiry (a much longer, generic default), explaining the slow, irregular refresh actually
# observed. manifest.mpd is a couple of KB; there is no bitrate-budget reason to tie either of
# its own schedules to the bulk segments' shared interval. This script's own update_interval_s is
# the fastest MBSTF can usefully get a newer copy anyway (nothing regenerates the descriptor more
# often than that), so use it directly for both fields, for manifest.mpd only.
MANIFEST_INTERVAL_MS = update_interval_s * 1000
objects = [
    {
        "locator": f"http://{host}:{port}/{stream}/{name}",
        "repetitionInterval": MANIFEST_INTERVAL_MS if name.endswith('.mpd') else rep_ms,
        **({"keepUpdatedInterval": update_interval_s} if name.endswith('.mpd') else {}),
    }
    for name in files
]

tmp_path = out_path + ".tmp"
with open(tmp_path, "w") as f:
    json.dump({"objects": objects, "updateInterval": update_interval_s}, f, indent=2)
os.replace(tmp_path, out_path)  # atomic -- never leaves MBSTF reading a half-written file
PYEOF
    fi
    sleep "$UPDATE_INTERVAL_S"
done
