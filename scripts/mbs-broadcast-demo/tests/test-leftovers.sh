#!/bin/bash
# Cases for the leftover check of ./demo down: the names it looks for must find the processes the demo starts. Each
# executable is stood in for by a script of that name that sleeps; nothing of a real run is signalled.
cd "$(dirname "${BASH_SOURCE[0]}")/../../.." \
  || { echo "cannot find the repository" >&2; exit 1; }
PASS=0; FAIL=0
check() { if [ "$2" = "$3" ]; then echo "  PASS  $1"; PASS=$((PASS+1)); else echo "  FAIL  $1"; echo "        expected: $3"; echo "        got:      $2"; FAIL=$((FAIL+1)); fi; }

eval "$(grep '^SELF_PROCS=' demo)"
eval "$(sed -n '/^signal_matching() {/,/^}/p' demo)"

T=$(mktemp -d)
pids=()
# A stand-in is a script, not a copy of /bin/sleep: where sleep is one applet of a multi-call binary, a renamed copy no
# longer knows which applet to run. The kernel names the process after the script.
standin() { printf '#!/bin/sh\nwhile :; do sleep 1; done\n' > "$1"; chmod +x "$1"; }
trap 'kill "${pids[@]}" 2>/dev/null; rm -rf "$T"' EXIT

found() {
    local pid="$1" p
    for p in "${SELF_PROCS[@]}"; do pgrep -x "$p" | grep -qx "$pid" && { echo found; return; }; done
    echo missed
}

echo "1. each executable the demo starts is recognised by its name"
for exe in gnb srsue open5gs-mbsfd open5gs-mbstfd mbs-client; do
    standin "$T/$exe"
    "$T/$exe" &
    pids+=($!)
    sleep 0.1
    check "$exe" "$(found $!)" "found"
done

echo "2. signal_matching stops a process of this user"
name="lefttest-$$"; name="${name:0:15}"
standin "$T/$name"
"$T/$name" &
pid=$!; pids+=("$pid")
sleep 0.1
signal_matching TERM -x "$name"
# Gone, or a zombie waiting for this shell to reap it.
state=alive
for _ in $(seq 1 30); do
    case "$(ps -o stat= -p "$pid" 2>/dev/null)" in ""|Z*) state=gone; break ;; esac
    sleep 0.1
done
check "process gone" "$state" "gone"

echo "3. signal_matching succeeds when nothing matches"
# ./demo down runs with set -e and pipefail: a signal_matching that returns 1 stops it before it removes anything.
set -o pipefail
rc=$( set -e; signal_matching TERM -x "lefttest-none-$$"; echo $? )
check "exit status" "$rc" "0"

echo "4. hard_clean succeeds when the veth pair is already gone with the namespace"
eval "$(sed -n '/^hard_clean() {/,/^}/p' demo)"
SELF_PROCS=(); SELF_PROC_PATTERNS=(); SELF_PORTS=()
SELF_NETNS="lefttest-ns-$$"; SELF_VETHS=("lefttest-v$$")
sudo() { :; }   # nothing is deleted: neither the namespace nor the veth exists
rc=$( set -e; hard_clean >/dev/null 2>&1; echo $? )
check "exit status" "$rc" "0"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
