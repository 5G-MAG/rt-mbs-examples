#!/bin/bash
# Copies the demo DASH content into $MEDIA_DIR/public, (re)generates its object-manifest carousel
# (TS 26.517 Annex D.1 shape: {"objects": [{"locator","repetitionInterval"}, ...]}), and starts
# whichever server MEDIA_ORIGIN_BACKEND (env.sh) names to serve that tree:
#
#   rt-media-origin -- 5G-MAG/rt-media-origin, configured with its own `mbs-static-vod`
#     template (mountPath "/", the carousel/carousel-live/collection-manifest/carousel-file-set content-type
#     overrides, this demo's redirect-chain test objects) so every URL this demo, MBSTF and the
#     API tests already expect (flat, no per-channel prefix) keeps resolving unchanged.
#   legacy (default) -- this repository's own express-mock-media-server, exactly as before rt-media-origin
#     was wired in. No MEDIA_ORIGIN_DIR checkout needed in this mode.
#
# Either way, one server mount serves the WHOLE public/ tree, not just $DEMO_STREAM: it also has to
# keep serving whatever live-encoder.sh/live-carousel.sh write into public/*_live afterwards
# (start-all.sh, status.sh and 06-provision-live-service.sh all fetch those over this same
# $MEDIA_HOST:$MEDIA_PORT, regardless of backend). rt-media-origin's own built-in Content-Type/
# Cache-Control rules (src/static/contentTypes.js) already set .mpd -> application/dash+xml,
# no-cache -- the same rule express-mock-media-server's app.js hand-implements and documents as
# load-bearing (MBSTF's DASHManifestHandler is registered by content-type) -- so the live channels
# need no override of their own in either mode.
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
case "$MEDIA_ORIGIN_BACKEND" in
    rt-media-origin)
        require_file "$MEDIA_ORIGIN_DIR/bin/www"
        [[ -d "$MEDIA_ORIGIN_DIR/node_modules" ]] || { log "installing rt-media-origin deps"; (cd "$MEDIA_ORIGIN_DIR" && npm install --no-audit --no-fund); }
        ;;
    legacy)
        [[ -d "$MEDIA_DIR/node_modules" ]] || { log "installing media server deps"; (cd "$MEDIA_DIR" && npm install --no-audit --no-fund); }
        ;;
    *)
        die "MEDIA_ORIGIN_BACKEND must be 'rt-media-origin' or 'legacy', not '$MEDIA_ORIGIN_BACKEND'"
        ;;
esac

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

case "$MEDIA_ORIGIN_BACKEND" in
    rt-media-origin)
        # One static channel, mountPath "/", serving the whole $MEDIA_DIR/public tree -- see this
        # script's header for why one mount has to cover both the carousel content and whatever
        # live-encoder.sh/live-carousel.sh write elsewhere under the same tree. Content-type/
        # cache-control for carousel/carousel-live/collection-manifest matches
        # express-mock-media-server's app.js exactly (read directly from it, not guessed); the
        # five redirects are its own /object2../object4 relocation test chain, used by
        # test/app.test.js.
        cat > "$GEN_CONF_DIR/media-origin.yaml" <<EOF
server:
  host: $MEDIA_HOST
  port: $MEDIA_PORT
channels:
  - id: mbs-demo-origin
    mode: static
    mountPath: "/"
    output:
      dir: $MEDIA_DIR/public
      defaultCacheControl: "max-age=30"
      pathOverrides:
        - { match: "carousel", contentType: 'application/3gpp-mbs-object-manifest+json;version="Rel17"' }
        - { match: "carousel-live", contentType: 'application/3gpp-mbs-object-manifest+json;version="Rel17"' }
        - { match: "collection-manifest", contentType: 'application/3gpp-mbs-object-manifest+json;version="Rel17"' }
        - { match: "carousel-file-set", contentType: 'application/3gpp-mbs-object-manifest+json;version="Rel17"' }
    redirects:
      - { from: "/object2", to: "/real-object2", status: 302 }
      - { from: "/object3", to: "/perm-object3", status: 301 }
      - { from: "/perm-object3", to: "/real-object3", status: 302 }
      - { from: "/object4", to: "/temp-object4", status: 302 }
      - { from: "/temp-object4", to: "/real-object4", status: 301 }
    transport: http
EOF
        log "starting media server (rt-media-origin) on $MEDIA_HOST:$MEDIA_PORT"
        run_bg "MediaServer" media-server bash -c "cd '$MEDIA_ORIGIN_DIR' && RT_MEDIA_SERVER_CONFIG='$GEN_CONF_DIR/media-origin.yaml' node ./bin/www"
        ;;
    legacy)
        log "starting media server (express-mock-media-server) on $MEDIA_HOST:$MEDIA_PORT"
        run_bg "MediaServer" media-server bash -c "cd '$MEDIA_DIR' && HOST='$MEDIA_HOST' PORT='$MEDIA_PORT' node ./bin/www"
        ;;
esac
wait_for_http "http://$MEDIA_HOST:$MEDIA_PORT/carousel" 15 || die "media server did not come up"

log "media server up ($MEDIA_ORIGIN_BACKEND), carousel: http://$MEDIA_HOST:$MEDIA_PORT/carousel"
