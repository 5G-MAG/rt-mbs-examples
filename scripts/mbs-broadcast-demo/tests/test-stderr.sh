#!/bin/bash
# Cases for lib.sh's wait_for_tcp: what a script writes to stderr after the function has run must still reach it. The
# function once ran "exec 3>&- 2>/dev/null" in the parent shell, which silenced stderr for the rest of the script, so a
# failing start-up script ended with a non-zero status and no message. Runs against a throwaway listener only.
# DEMO_DIR names another copy of the scripts to check (default: the one this test is in).
cd "${DEMO_DIR:-$(dirname "${BASH_SOURCE[0]}")/..}" \
  || { echo "cannot find the demo directory" >&2; exit 1; }
PASS=0; FAIL=0
check() { if [ "$2" = "$3" ]; then echo "  PASS  $1"; PASS=$((PASS+1)); else echo "  FAIL  $1"; echo "        expected: $3"; echo "        got:      $2"; FAIL=$((FAIL+1)); fi; }

T=$(mktemp -d)
trap 'kill $listener 2>/dev/null; rm -rf "$T"' EXIT

# A listener on a free port, so that one probe succeeds; a second port that nobody listens on.
python3 - "$T/port" <<'PY' &
import socket, sys, time
s = socket.socket(); s.bind(("127.0.0.1", 0)); s.listen(5)
open(sys.argv[1], "w").write(str(s.getsockname()[1]))
time.sleep(60)
PY
listener=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$T/port" ] && break; sleep 0.2; done
open_port=$(cat "$T/port")
closed_port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')

# stderr of a script that probes a port and then writes a line to stderr
stderr_after() {
  bash -c 'source ./env.sh; source ./lib.sh; wait_for_tcp 127.0.0.1 "$1" 1; echo "rc=$?" >&2; echo "message after wait_for_tcp" >&2' _ "$1" 2>&1 >/dev/null
}

echo "1. a probe that succeeds does not silence what follows"
out=$(stderr_after "$open_port")
check "wait_for_tcp returns 0" "$(echo "$out" | grep -c '^rc=0$')" "1"
check "the message after it reaches stderr" "$(echo "$out" | grep -c '^message after wait_for_tcp$')" "1"

echo "2. a probe that fails does not silence what follows"
out=$(stderr_after "$closed_port")
check "wait_for_tcp returns 1" "$(echo "$out" | grep -c '^rc=1$')" "1"
check "the message after it reaches stderr" "$(echo "$out" | grep -c '^message after wait_for_tcp$')" "1"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
