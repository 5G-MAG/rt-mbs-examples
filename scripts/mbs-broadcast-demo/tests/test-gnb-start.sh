#!/bin/bash
# Cases for start_gnb when the radio is still claimed by the session before. The gNB is stood in for by a script that
# fails as a claimed N310 makes it fail for its first starts; run_bg_netns and sudo are replaced, so nothing of a real
# run is started or signalled.
cd "$(dirname "${BASH_SOURCE[0]}")/.." \
  || { echo "cannot find the demo directory" >&2; exit 1; }
PASS=0; FAIL=0
check() { if [ "$2" = "$3" ]; then echo "  PASS  $1"; PASS=$((PASS+1)); else echo "  FAIL  $1"; echo "        expected: $3"; echo "        got:      $2"; FAIL=$((FAIL+1)); fi; }

eval "$(sed -n '/^start_gnb() {/,/^}/p' lib.sh)"
T=$(mktemp -d)
trap 'pkill -f "$T/fake-gnb" 2>/dev/null; rm -rf "$T"' EXIT
LOG_DIR="$T"; PID_DIR="$T"; GNB_CLAIM_RETRY_SECS=0
log() { :; }
sudo() { shift; "$@"; }
run_bg_netns() { shift 2; "$@" >"$LOG_DIR/gnb.log" 2>&1 & echo $! > "$PID_DIR/gnb.pid"; }

cat > "$T/fake-gnb" <<'GNB'
#!/bin/bash
n=$(( $(cat "$1" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$1"
if [ "$n" -le "$2" ]; then
    echo "Failed to open device with address 'type=n3xx': RuntimeError: Error during RPC call to \`claim'. Error message: Someone tried to claim this device again (From: 192.168.10.1)"
    exit 1
fi
echo "DU started successfully"
exec sleep 300
GNB
chmod +x "$T/fake-gnb"

echo "1. the radio is claimed for the first two starts"
GNB_READY_WAIT_SECS=20
start_gnb "$T/fake-gnb" "$T/count" 2; rc=$?
check "the DU starts" "$rc" "0"
check "the gNB was started three times" "$(cat "$T/count")" "3"

echo "2. the radio stays claimed"
pkill -f "$T/fake-gnb"; rm -f "$T/count"
GNB_READY_WAIT_SECS=3
start_gnb "$T/fake-gnb" "$T/count" 1000; rc=$?
check "start_gnb gives up within its wait" "$rc" "1"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
