#!/bin/bash
# Cases for stop-all.sh when sudo's cached credentials have expired and there is no terminal to ask on. Runs a
# copy of the stop script in a throwaway directory, with a sudo on PATH that refuses everything, so nothing of a
# real run is touched.
cd "$(dirname "${BASH_SOURCE[0]}")/.." \
  || { echo "cannot find the demo directory" >&2; exit 1; }
PASS=0; FAIL=0
check() { if [ "$2" = "$3" ]; then echo "  PASS  $1"; PASS=$((PASS+1)); else echo "  FAIL  $1"; echo "        expected: $3"; echo "        got:      $2"; FAIL=$((FAIL+1)); fi; }

T=$(mktemp -d)
trap 'kill $own 2>/dev/null; rm -rf "$T"' EXIT
cp stop-all.sh env.sh lib.sh "$T/"
mkdir -p "$T/run/pids" "$T/bin"
printf '#!/bin/sh\nexit 1\n' > "$T/bin/sudo"; chmod +x "$T/bin/sudo"

sleep 300 &
own=$!
echo "$own" > "$T/run/pids/mbsf.pid"
echo 1 > "$T/run/pids/ue.pid"   # a process of root that this user cannot signal

out=$(cd "$T" && PATH="$T/bin:$PATH" MEDIA_DIR="$T/media" ./stop-all.sh </dev/null 2>&1); rc=$?
sleep 0.2

echo "1. a process of this user is stopped without sudo"
check "process gone" "$(kill -0 "$own" 2>/dev/null && echo alive || echo gone)" "gone"
check "its pidfile removed" "$([ -f "$T/run/pids/mbsf.pid" ] && echo kept || echo removed)" "removed"

echo "2. a process that needs sudo is reported, not forgotten"
check "its pidfile kept" "$([ -f "$T/run/pids/ue.pid" ] && echo kept || echo removed)" "kept"
check "named among those not stopped" "$(echo "$out" | grep -cx '    ue (pid 1)')" "1"
check "exit status" "$rc" "1"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
