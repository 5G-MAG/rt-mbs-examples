#!/bin/bash
# Build the whole MBS stack the way someone else would: fresh clones, a stock container image, and
# only the packages the demo README tells them to install.
#
# This exists because rebuilding locally cannot answer "can anyone else build this". Every dependency
# is already present on a development machine, so an incomplete package list, a hardcoded path into
# /opt, or a library version only that machine has are all invisible there. Five packages missing
# from the README's list and a component that could not build anywhere else were found this way,
# after a clean-clone build on the development machine had reported everything passing.
#
# The package list is read out of the README rather than restated here, so this checks what readers
# are actually told to install. Cloning happens on the host, so credentials stay outside the
# container and a private-repo permission failure cannot be mistaken for a missing dependency.
#
#   ./check-build-from-clean.sh                     # everything, ~45 min
#   ./check-build-from-clean.sh --quick             # skip the two srsRAN builds, ~15 min
#   ./check-build-from-clean.sh --image ubuntu:24.04
#   ./check-build-from-clean.sh --branch main
#   ./check-build-from-clean.sh --examples-checkout /path/to/rt-mbs-examples
# --examples-checkout exports the committed HEAD, excluding untracked files and local edits.
set -uo pipefail

IMAGE=ubuntu:26.04
BRANCH=feature/mbs-compliance-fixes
QUICK=0
EXAMPLES_CHECKOUT=""
WORK=${WORK:-$(mktemp -d)}
mkdir -p "$WORK" || { echo "cannot create $WORK" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --image)  IMAGE="$2"; shift 2 ;;
        --branch) BRANCH="$2"; shift 2 ;;
        --examples-checkout) EXAMPLES_CHECKOUT="$2"; shift 2 ;;
        --quick)  QUICK=1; shift ;;
        --keep)   KEEP=1; shift ;;
        -h|--help) sed -n '2,20p' "$0" | sed 's/^# \?//'; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
README="$HERE/mbs-broadcast-demo/README.md"
[ -r "$README" ] || { echo "cannot read $README" >&2; exit 1; }
command -v docker >/dev/null || { echo "docker is required" >&2; exit 1; }

# The apt line as written in the README, so a package added there is picked up here with no edit.
python3 - "$README" > "$WORK/pkgs" <<'PY'
import re, sys
s = open(sys.argv[1]).read()
m = re.search(r'```bash\nsudo apt install (git ninja-build.*?)\n```', s, re.S)
if not m:
    sys.exit("could not find the apt install block in the README")
print(' '.join(m.group(1).replace('\\\n', ' ').split()))
PY
[ -s "$WORK/pkgs" ] || exit 1
echo "package list from the README: $(wc -w < "$WORK/pkgs") packages"

SRC="$WORK/tree"
mkdir -p "$SRC/rt-mbs"
clone() {
    local repo="$1" parent="$2"; shift 2
    printf '  cloning %-30s' "$repo"
    if git clone --quiet -b "$BRANCH" "$@" "git@github.com:5G-MAG/$repo.git" "$parent/$repo" 2>/dev/null; then
        echo "$(git -C "$parent/$repo" rev-parse --short HEAD)"
    else
        echo "FAILED (no access, or no branch $BRANCH)"
        return 1
    fi
}
echo "cloning at $BRANCH"
for r in open5gs srsRAN_Project_mbs srsRAN_4G_mbs;                                do clone "$r" "$SRC" || exit 1; done
for r in rt-mbs-function rt-mbs-transport-function rt-mbs-client;                 do clone "$r" "$SRC/rt-mbs" --recurse-submodules || exit 1; done
for r in rt-mbs-application rt-mbs-application-provider;                         do clone "$r" "$SRC/rt-mbs" || exit 1; done
if [ -n "$EXAMPLES_CHECKOUT" ]; then
    # Export the exact CI checkout without carrying its credentials, build output,
    # or untracked files into the container. pipefail catches archive errors too.
    mkdir -p "$SRC/rt-mbs/rt-mbs-examples" || exit 1
    git -C "$EXAMPLES_CHECKOUT" archive HEAD | tar -x -C "$SRC/rt-mbs/rt-mbs-examples" || exit 1
    echo "rt-mbs-examples from checkout: $(git -C "$EXAMPLES_CHECKOUT" rev-parse HEAD)"
else
    clone rt-mbs-examples "$SRC/rt-mbs" || exit 1
fi

SKIP=""
[ "$QUICK" = 1 ] && SKIP="ue gnb"

echo "building in $IMAGE"
docker run --rm -v "$SRC:/src" -v "$WORK:/out" "$IMAGE" bash -c '
set -u
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null 2>&1
if apt-get install -y -qq $(cat /out/pkgs) nodejs npm >/out/apt.log 2>&1; then
    echo "PASS  apt install"
else
    echo "FAIL  apt install"
    grep -iE "unable to locate|no installation candidate" /out/apt.log | head -5
    exit 1
fi

# Install a newer Meson only when the stock image is too old.
if dpkg --compare-versions "$(meson --version)" lt 1.4.0; then
    apt-get install -y -qq pipx || exit 1
    PIPX_HOME=/opt/mbs-pipx PIPX_BIN_DIR=/usr/local/bin pipx install meson || exit 1
fi
dpkg --compare-versions "$(meson --version)" ge 1.4.0 || { echo "Meson >= 1.4 required"; exit 1; }
echo "using Meson $(meson --version)"

# Failures are recorded, not only printed, so this can exit non-zero. A check that always succeeds
# is worse than no check: it reads as evidence while proving nothing.
: > /out/failures
skip="'"$SKIP"'"
b() {
    n="$1"; d="$2"; shift 2
    case " $skip " in *" $n "*) echo "SKIP  $n"; return ;; esac
    [ -d "$d" ] || { echo "FAIL  $n (source directory missing)"; echo "$n" >> /out/failures; return; }
    if ( cd "$d" && eval "$@" ) > /out/$n.log 2>&1; then
        echo "PASS  $n"
    else
        echo "FAIL  $n"
        echo "$n" >> /out/failures
        grep -E "ERROR:|error:|undefined reference to" /out/$n.log | head -3 | sed "s/^/        /"
    fi
}

b open5gs   /src/open5gs                            "meson setup build && ninja -C build"
b mbsf      /src/rt-mbs/rt-mbs-function             "meson setup build && ninja -C build"
b mbstf     /src/rt-mbs/rt-mbs-transport-function   "meson setup build && ninja -C build"
b mbsclient /src/rt-mbs/rt-mbs-client               "mkdir -p build && cd build && cmake -GNinja .. && ninja && ctest"
b app       /src/rt-mbs/rt-mbs-application          "npm install"
b provider  /src/rt-mbs/rt-mbs-application-provider "npm install"
b mediasrv  /src/rt-mbs/rt-mbs-examples/express-mock-media-server "npm install"
b ue        /src/srsRAN_4G_mbs                      "cmake -S . -B build && cmake --build build -j$(nproc)"
b gnb       /src/srsRAN_Project_mbs                 "cmake -S . -B build -DENABLE_ZEROMQ=ON && cmake --build build -j$(nproc)"

n=$(wc -l < /out/failures)
# No single quotes below: this whole block is inside a single-quoted bash -c, and one would close it.
if [ "$n" -eq 0 ]; then echo "--- everything attempted built"; else echo "--- $n failed:" $(cat /out/failures); fi
exit "$n"
'
rc=$?

if [ "${KEEP:-0}" = 1 ]; then
    echo "logs and sources kept in $WORK"
else
    # The container writes its build trees as root, so removal needs the same.
    sudo -n rm -rf "$WORK" 2>/dev/null || rm -rf "$WORK" 2>/dev/null || echo "could not remove $WORK"
fi
exit $rc
