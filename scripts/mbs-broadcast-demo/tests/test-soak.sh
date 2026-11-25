#!/bin/bash
# Plays the demo's video again and again for a while, to catch a stream that stops after some time.
#
#   PLAYWRIGHT_MODULE=/path/to/node_modules/playwright ./test-soak.sh [MINUTES [INTERVAL]]
#
# The demo has to be up (`./demo up`). Every INTERVAL minutes (default 5) the video is played in Chrome as tests/e2e-player.js does for the
# last check of test-e2e-chain.sh, and it has to advance at least 5 s with readyState >= 3. It ends after MINUTES (default 110).
#
# A machine that was suspended is reported and ends the run with status 2, not as a failed stream: while it sleeps the encoders stop and the
# live edge moves away from them, so the video does not recover until the demo is restarted (README, Troubleshooting). The run is void then.
#
# Prints PASS or FAIL per look and `passed N, failed M` at the end; status 0 when nothing failed.
set -uo pipefail

MINUTES="${1:-110}"
INTERVAL="${2:-5}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -n "${PLAYWRIGHT_MODULE:-}" ] || { echo "set PLAYWRIGHT_MODULE to a playwright install with Chrome (see the README, 'Checking the whole chain')" >&2; exit 1; }
command -v node >/dev/null || { echo "node is required" >&2; exit 1; }

PASS=0; FAIL=0
look() { # one look: up to three tries, 30 s apart, as the last check of the chain test waits for the video to recover
    local attempt samples verdict=""
    for attempt in 1 2 3; do
        samples=$(PLAYWRIGHT_MODULE="$PLAYWRIGHT_MODULE" node "$HERE/e2e-player.js" 2>/dev/null | head -1)
        verdict=$(python3 -c 'import json,sys
s=[x for x in json.loads(sys.argv[1]) if x]
print("playing" if len(s)>=4 and s[-1]["t"]-s[-4]["t"]>=5 and s[-1]["rs"]>=3 else "not playing")' "$samples" 2>/dev/null)
        [ "$verdict" = playing ] && break
        sleep 30
    done
    if [ "$verdict" = playing ]; then PASS=$((PASS+1)); echo "  PASS  $1 video advances with readyState >= 3"
    else FAIL=$((FAIL+1)); echo "  FAIL  $1 video does not advance (${verdict:-no samples}): ${samples:-no output}"; fi
}

start=$(date +%s); last=$start
echo "playing the video every $INTERVAL min for $MINUTES min"
while :; do
    now=$(date +%s)
    if [ $((now - last)) -gt $((INTERVAL * 60 * 2 + 120)) ]; then
        echo "  VOID  $(( (now - last) / 60 )) min passed between two looks: the machine was suspended; restart the demo and run again"
        echo; echo "passed $PASS, failed $FAIL (void)"; exit 2
    fi
    last=$now
    look "t=$(( (now - start) / 60 )) min:"
    [ $((now - start + INTERVAL * 60)) -gt $((MINUTES * 60)) ] && break
    sleep $((INTERVAL * 60))
done
echo; echo "passed $PASS, failed $FAIL"; [ "$FAIL" = 0 ]
