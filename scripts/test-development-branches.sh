#!/bin/bash
# Tests the development branches of the whole MBS Broadcast stack end to end, from fresh clones, on this machine.
#
#   PLAYWRIGHT_MODULE=/path/to/node_modules/playwright ./scripts/test-development-branches.sh --root /path/to/an/empty/directory
#
# In this order, each step the one the demo README describes (scripts/mbs-broadcast-demo/README.md):
#   1. clones every component at its development branch: 5mbs-development on open5gs, srsRAN_Project_mbs and srsRAN_4G_mbs, development on
#      the six rt-mbs-* components and on rt-media-origin (section 2), and records the commit of each in ROOT/test-logs/commits.txt
#   2. points the three wraps at the development branches (section 5); --release-pins leaves them as committed
#   3. builds every component with the commands of section 2
#   4. ./demo up, tests/test-e2e-chain.sh (50 checks, the last one plays the video in Chrome), and ./demo down
#   5. with --soak MINUTES: instead of ./demo down, plays the video every five minutes for that long (tests/test-soak.sh), then ./demo down
#
# This builds and runs on this machine, as a user would (network namespace, sudo, a Chrome for Playwright); the prerequisites are the README's.
# scripts/check-build-from-clean.sh is the other check: it only builds, in a stock container. Run this one on a machine that is not busy and
# is not suspended while it runs.
#
#   --root DIR         where everything is cloned and built; it has to be empty or not exist (the layout of README section 3)
#   --release-pins     do not point the wraps at the development branches (when the release branches carry the work)
#   --no-build         clone and pin only (a quick look at what would be tested)
#   --soak MINUTES     see step 5
#   --keep-demo        leave the demo up at the end
#
# Environment: PLAYWRIGHT_MODULE (required: the player check needs it; --no-player runs without), GITHUB_BASE (default git@github.com:5G-MAG;
# https://github.com/5G-MAG with a credential helper works as well), CHANNELS_FILE and the other variables of the demo as in the README.
# ccache is used when it is installed.
#
# Every step and its exit status go to ROOT/test-logs/summary.txt, the output of each to a log beside it. The exit status is 0 only when every
# step passed; the run stops at the first step that did not.
set -uo pipefail

ROOT=""; PINS=1; BUILD=1; SOAK=""; KEEP=0; PLAYER=1
GITHUB_BASE="${GITHUB_BASE:-git@github.com:5G-MAG}"
while [ $# -gt 0 ]; do
    case "$1" in
        --root)         ROOT="$2"; shift 2 ;;
        --release-pins) PINS=0; shift ;;
        --no-build)     BUILD=0; shift ;;
        --soak)         SOAK="$2"; shift 2 ;;
        --keep-demo)    KEEP=1; shift ;;
        --no-player)    PLAYER=0; shift ;;
        -h|--help)      awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done
[ -n "$ROOT" ] || { echo "--root DIR is required" >&2; exit 2; }
if [ -d "$ROOT" ] && [ -n "$(ls -A "$ROOT" 2>/dev/null)" ]; then echo "$ROOT is not empty" >&2; exit 2; fi
if [ "$PLAYER" = 1 ] && [ -z "${PLAYWRIGHT_MODULE:-}" ]; then
    echo "set PLAYWRIGHT_MODULE to a playwright install with Chrome (README, 'Checking the whole chain'), or use --no-player" >&2; exit 2
fi
for tool in git meson ninja cmake npm node python3; do command -v "$tool" >/dev/null || { echo "$tool is required" >&2; exit 2; }; done

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/development-pins.sh"
mkdir -p "$ROOT/rt-mbs" "$ROOT/test-logs" || exit 1
ROOT="$(cd "$ROOT" && pwd)"; LOGS="$ROOT/test-logs"; SUMMARY="$LOGS/summary.txt"; : > "$SUMMARY"
note() { echo "[$(date +%T)] $*" | tee -a "$SUMMARY"; }
# step NAME LOGFILE COMMAND...: runs the command, notes its status, and ends the whole run when it failed
step() {
    local name="$1" log="$LOGS/$2"; shift 2
    note "$name: started"
    "$@" > "$log" 2>&1; local rc=$?
    note "$name: rc=$rc ($log)"
    [ "$rc" = 0 ] || { note "stopped at: $name"; exit 1; }
}

if command -v ccache >/dev/null; then
    export CMAKE_C_COMPILER_LAUNCHER=ccache CMAKE_CXX_COMPILER_LAUNCHER=ccache CC="ccache gcc" CXX="ccache g++"
fi
export GIT_TERMINAL_PROMPT=0

# 1. clones, the layout of README section 3: open5gs, the two srsRAN forks and rt-media-origin directly under ROOT, the six rt-mbs-* components in ROOT/rt-mbs
clone() { # repo parent branch [git clone options]
    local repo="$1" parent="$2" branch="$3"; shift 3
    git clone --quiet -b "$branch" "$@" "$GITHUB_BASE/$repo.git" "$parent/$repo" || return 1
    echo "$repo $branch $(git -C "$parent/$repo" rev-parse --short=10 HEAD)" >> "$LOGS/commits.txt"
}
clone_all() {
    : > "$LOGS/commits.txt"
    for r in open5gs srsRAN_Project_mbs srsRAN_4G_mbs; do clone "$r" "$ROOT" 5mbs-development || return 1; done
    clone rt-media-origin "$ROOT" development || return 1
    for r in rt-mbs-function rt-mbs-transport-function rt-mbs-client; do clone "$r" "$ROOT/rt-mbs" development --recurse-submodules || return 1; done
    for r in rt-mbs-application rt-mbs-application-provider rt-mbs-examples; do clone "$r" "$ROOT/rt-mbs" development || return 1; done
}
step "clone every component at its development branch" clone.log clone_all
note "commits:"; sed 's/^/    /' "$LOGS/commits.txt" | tee -a "$SUMMARY" > /dev/null

# 2. the three wraps
if [ "$PINS" = 1 ]; then step "point the three wraps at the development branches" pins.log apply_development_pins "$ROOT"; fi
[ "$BUILD" = 1 ] || { note "stopped after the clones (--no-build)"; exit 0; }

# 3. builds, the commands of README section 2
build() { # name dir command
    local name="$1" dir="$2" cmd="$3"
    step "build $name" "build-$name.log" bash -c "cd '$dir' && $cmd"
}
JOBS="$(nproc)"
build open5gs   "$ROOT/open5gs"                              "meson setup build && ninja -C build"
build gnb       "$ROOT/srsRAN_Project_mbs"                   "cmake -S . -B build -DENABLE_ZEROMQ=ON && cmake --build build -j$JOBS"
build ue        "$ROOT/srsRAN_4G_mbs"                        "cmake -S . -B build && cmake --build build -j$JOBS"
build mbsf      "$ROOT/rt-mbs/rt-mbs-function"               "git submodule update --init --recursive && meson subprojects update && meson setup build && ninja -C build"
build mbstf     "$ROOT/rt-mbs/rt-mbs-transport-function"     "git submodule update --init --recursive && meson subprojects update && meson setup build && ninja -C build"
build client    "$ROOT/rt-mbs/rt-mbs-client"                 "git submodule update --init --recursive && mkdir -p build && cd build && cmake -GNinja .. && ninja"
build app       "$ROOT/rt-mbs/rt-mbs-application"            "npm install"
build provider  "$ROOT/rt-mbs/rt-mbs-application-provider"   "npm install"
build origin    "$ROOT/rt-media-origin"                     "npm install"

# 4. the demo and the chain test, from the checkout of rt-mbs-examples that was just cloned
export REPOS_ROOT="$ROOT" RAN_ROOT="$ROOT"
unset GNB_BIN UE_BIN GNB_FLAVOR GNB_DIR
EX="$ROOT/rt-mbs/rt-mbs-examples"
# a failed `demo up` can leave part of the demo running: `./demo down` with the same REPOS_ROOT and RAN_ROOT stops it
step "demo up" demo-up.log bash -c "cd '$EX' && timeout 900 ./demo up"
# the chain test plays the video only when PLAYWRIGHT_MODULE is set; --no-player takes it away
if [ "$PLAYER" = 1 ]; then CHAIN_ENV=(env); else CHAIN_ENV=(env -u PLAYWRIGHT_MODULE); fi
note "chain test: started"
( cd "$EX" && "${CHAIN_ENV[@]}" timeout 1500 ./scripts/mbs-broadcast-demo/tests/test-e2e-chain.sh ) > "$LOGS/chain-test.log" 2>&1; chain_rc=$?
note "chain test: rc=$chain_rc, $(grep -a '^passed ' "$LOGS/chain-test.log" | tail -1) ($LOGS/chain-test.log)"

# 5. the soak, when asked for
soak_rc=0
if [ "$chain_rc" = 0 ] && [ -n "$SOAK" ]; then
    note "soak: started ($SOAK min)"
    ( cd "$EX" && "$HERE/mbs-broadcast-demo/tests/test-soak.sh" "$SOAK" ) > "$LOGS/soak.log" 2>&1; soak_rc=$?
    note "soak: rc=$soak_rc, $(grep -a '^passed ' "$LOGS/soak.log" | tail -1) ($LOGS/soak.log)"
fi

if [ "$KEEP" = 1 ]; then note "the demo is left up (--keep-demo)"
else step "demo down" demo-down.log bash -c "cd '$EX' && ./demo down"; fi

if [ "$chain_rc" = 0 ] && [ "$soak_rc" = 0 ]; then note "PASSED"; exit 0; fi
note "FAILED (chain test rc=$chain_rc, soak rc=$soak_rc)"; exit 1
