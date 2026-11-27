#!/bin/bash
# Copies the demo DASH content into $MEDIA_DIR/public, (re)generates its object-manifest carousel
# (TS 26.517 Annex D.1 shape: {"objects": [{"locator","repetitionInterval"}, ...]}), and starts
# rt-media-origin (5G-MAG/rt-media-origin, checkout in $MEDIA_ORIGIN_DIR) to serve that tree, configured
# by $MEDIA_ORIGIN_CONFIG (media-origin.yaml in $MEDIA_DIR unless you set it): mountPath "/", the formats the
# provider declares (carousel/carousel-live/collection-manifest/carousel-file-set, manifest.mpd, a default
# for everything else) and the redirect-chain test objects, so every URL this demo, MBSTF and the API
# tests expect (flat, no per-channel prefix) resolves.
#
# One server mount serves the WHOLE public/ tree, not just $DEMO_STREAM: it also has to keep serving
# whatever live-encoder.sh/live-carousel.sh write into public/*_live afterwards (start-all.sh,
# status.sh and 06-provision-live-service.sh all fetch those over this same $MEDIA_HOST:$MEDIA_PORT).
# The configuration declares manifest.mpd as application/dash+xml with no-cache, which MBSTF's
# DASHManifestHandler needs (it is registered by content-type), and every live channel writes its manifest
# under that name; a manifest with another name needs a line of its own in the configuration.
#
# The carousel's repetitionInterval is an engineering choice (no clause governs it):
# it) computed here from this stream's own real byte total against $INGEST_MAX_BITRATE
# (env.sh) with a stated safety margin -- not a fabricated constant. If the content
# changes, re-run this script and it recomputes; it does not silently clamp to whatever
# value happens to fit, it fails loudly if $CAROUSEL_REPETITION_MS (env.sh) is too
# aggressive for the content actually present, so a misconfiguration is visible rather
# than silently deployed under budget.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source env.sh
source lib.sh
ensure_dirs

require_cmd node
require_cmd npm
[[ -f "$MEDIA_ORIGIN_DIR/bin/www" ]] || die "rt-media-origin not found at $MEDIA_ORIGIN_DIR (no bin/www): clone https://github.com/5G-MAG/rt-media-origin there, or set MEDIA_ORIGIN_DIR to your checkout (environment, or local.env)"
[[ -f "$MEDIA_ORIGIN_CONFIG" ]] || die "rt-media-origin configuration not found: $MEDIA_ORIGIN_CONFIG (the default is media-origin.yaml in MEDIA_DIR, the media-origin/ folder of rt-mbs-examples; set MEDIA_ORIGIN_CONFIG to your own)"
[[ -d "$MEDIA_ORIGIN_DIR/node_modules" ]] || { log "installing rt-media-origin deps"; (cd "$MEDIA_ORIGIN_DIR" && npm install --no-audit --no-fund); }

SRC_DIR="$MWC_CONTENT_ROOT/$DEMO_STREAM"
DST_DIR="$MEDIA_DIR/public/$DEMO_STREAM"
[[ -d "$SRC_DIR" ]] || die "content not found: $SRC_DIR (set MWC_CONTENT_ROOT/DEMO_STREAM in env.sh)"

log "copying $DEMO_STREAM content into $DST_DIR"
mkdir -p "$DST_DIR"
cp -u "$SRC_DIR"/* "$DST_DIR"/

log "generating carousel manifest for $(ls "$DST_DIR" | wc -l) objects"
python3 - "$DST_DIR" "$MEDIA_HOST" "$MEDIA_PORT" "$DEMO_STREAM" "$CAROUSEL_REPETITION_MS" "$INGEST_MAX_BITRATE" "$MEDIA_DIR/public/carousel" <<'PYEOF'
import json, os, sys, re

dst_dir, host, port, stream, rep_ms, max_bitrate_str, out_path = sys.argv[1:8]
rep_ms = int(rep_ms)

files = sorted(os.listdir(dst_dir))
total_bytes = 0
objects = []
for name in files:
    path = os.path.join(dst_dir, name)
    if not os.path.isfile(path):
        continue
    size = os.path.getsize(path)
    total_bytes += size
    objects.append({
        "locator": f"http://{host}:{port}/{stream}/{name}",
        "repetitionInterval": rep_ms,
    })

# Parse "<N> Mbps"/"<N> Kbps"/"<N> bps" into bits/sec -- same units MBSF/MBSTF's own
# config/API use (e.g. mbsf.yaml userServiceAnnouncement.mbr, the ingest session's
# maxContBitRate), so this check compares like with like.
m = re.match(r'\s*([\d.]+)\s*([KMG]?)bps\s*$', max_bitrate_str, re.IGNORECASE)
if not m:
    print(f"WARNING: could not parse INGEST_MAX_BITRATE={max_bitrate_str!r}, skipping budget check")
    max_bps = None
else:
    scale = {"": 1, "K": 1e3, "M": 1e6, "G": 1e9}[m.group(2).upper()]
    max_bps = float(m.group(1)) * scale

required_bps = (total_bytes * 8) / (rep_ms / 1000.0)
print(f"{len(objects)} objects, {total_bytes} bytes total, "
      f"repetitionInterval={rep_ms}ms -> required bit rate {required_bps/1e6:.2f} Mbps")

if max_bps is not None:
    margin = 0.92  # headroom under the ingest session's own mbr, not a spec value
    if required_bps > max_bps * margin:
        print(f"ERROR: {required_bps/1e6:.2f} Mbps exceeds {margin:.0%} of the configured "
              f"INGEST_MAX_BITRATE ({max_bps/1e6:.2f} Mbps). Raise CAROUSEL_REPETITION_MS in "
              f"env.sh, or raise INGEST_MAX_BITRATE (and pass the same value when creating the "
              f"ingest session in 06-provision-broadcast-service.sh), and re-run.", file=sys.stderr)
        print("Not writing the carousel file -- refusing to deploy a manifest that would "
              "overrun MBSTF's own carousel budget and crash it (ObjectCarouselPackager.cc's "
              "\"Carousel maximum bit rate exceeded\").", file=sys.stderr)
        sys.exit(1)

with open(out_path, "w") as f:
    json.dump({"objects": objects}, f, indent=2)
print(f"wrote {out_path}")
PYEOF

log "starting media server (rt-media-origin) on $MEDIA_HOST:$MEDIA_PORT"
run_bg "MediaServer" media-server bash -c "cd '$MEDIA_ORIGIN_DIR' && HOST='$MEDIA_HOST' PORT='$MEDIA_PORT' MEDIA_PUBLIC_DIR='$MEDIA_DIR/public' RT_MEDIA_SERVER_CONFIG='$MEDIA_ORIGIN_CONFIG' node ./bin/www"
wait_for_http "http://$MEDIA_HOST:$MEDIA_PORT/carousel" 15 || die "media server did not come up"

log "media server up (rt-media-origin), carousel: http://$MEDIA_HOST:$MEDIA_PORT/carousel"
