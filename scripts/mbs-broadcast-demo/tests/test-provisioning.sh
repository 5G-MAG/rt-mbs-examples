#!/bin/bash
# Cases for ensure_subscriber, run against a throwaway database with the same unique index on imsi
# that open5gs creates, so a duplicate insert fails here exactly as it does in a real deployment.
cd "$(dirname "${BASH_SOURCE[0]}")/.." \
  || { echo "cannot find the demo directory" >&2; exit 1; }
set -a; source env.sh; set +a; source lib.sh

U="mongodb://127.0.0.1/o5gs_prov_cases"
export OPEN5GS_DB_URI="$U"
DB="$OPEN5GS_DIR/misc/db/open5gs-dbctl"
PASS=0; FAIL=0
reset_db() {
    mongosh --quiet --eval "db.dropDatabase()" "$U" >/dev/null 2>&1
    mongosh --quiet --eval 'db.subscribers.createIndex({imsi:1},{unique:true})' "$U" >/dev/null 2>&1
}
row() { mongosh --quiet --eval 'JSON.stringify(db.subscribers.findOne({},{"slice.sst":1,"slice.sd":1,"slice.session.name":1,_id:0}))' "$U" 2>/dev/null; }
check() { if [ "$2" = "$3" ]; then echo "  PASS  $1"; PASS=$((PASS+1)); else echo "  FAIL  $1"; echo "        expected: $3"; echo "        got:      $2"; FAIL=$((FAIL+1)); fi; }

EXPECT='{"slice":[{"sst":1,"sd":"000001","session":[{"name":"internet"}]}]}'

echo "1. clean database provisions correctly"
reset_db; ensure_subscriber >/dev/null 2>&1; check "stored row" "$(row)" "$EXPECT"

echo "2. second call is idempotent and does not rewrite"
out=$(ensure_subscriber 2>&1); check "reports already provisioned" "$(echo "$out" | grep -c 'already provisioned')" "1"
check "row unchanged" "$(row)" "$EXPECT"

echo "3. the duplicate-key case: row present, probe misreports it as absent on first look"
# This is the reported failure. The probe is overridden for one call only; the real one answers the
# post-write verification, so the case tests the insert path and not the checking path.
eval "$(declare -f subscriber_state | sed '1s/subscriber_state/real_subscriber_state/')"
# The counter must live in a file: ensure_subscriber calls this through command substitution, so a
# shell variable would reset on every call and the stub would misreport every look rather than one.
CALLFILE=$(mktemp); echo 0 > "$CALLFILE"
subscriber_state() {
    local n; n=$(( $(cat "$CALLFILE") + 1 )); echo "$n" > "$CALLFILE"
    if [ "$n" -eq 1 ]; then printf 'absent'; else real_subscriber_state "$@"; fi
}
out=$(ensure_subscriber 2>&1); rc=$?
check "survives the misread (was: E11000 duplicate key)" "$rc" "0"
check "no duplicate-key error" "$(echo "$out" | grep -c 'E11000')" "0"
check "row still correct" "$(row)" "$EXPECT"
rm -f "$CALLFILE"; unset -f subscriber_state; eval "$(declare -f real_subscriber_state | sed '1s/real_subscriber_state/subscriber_state/')"

echo "4. a row written by plain 'add' (sst, no sd) is repaired"
reset_db; DB_URI="$U" "$DB" add "$UE_IMSI" "$UE_KEY" "$UE_OPC" >/dev/null 2>&1
check "starts wrong" "$(row)" '{"slice":[{"sst":1,"session":[{"name":"internet"}]}]}'
ensure_subscriber >/dev/null 2>&1; check "repaired" "$(row)" "$EXPECT"

echo "5. the same slice spelled \"1\" is recognised, not rewritten"
mongosh --quiet --eval "db.subscribers.updateOne({},{\$set:{'slice.0.sd':'1'}})" "$U" >/dev/null 2>&1
out=$(ensure_subscriber 2>&1); check "left alone" "$(row)" '{"slice":[{"sst":1,"sd":"1","session":[{"name":"internet"}]}]}'

echo "6. a genuinely different slice is repaired"
mongosh --quiet --eval "db.subscribers.updateOne({},{\$set:{'slice.0.sd':'000009'}})" "$U" >/dev/null 2>&1
ensure_subscriber >/dev/null 2>&1; check "repaired" "$(row)" "$EXPECT"

echo "7. an unreachable database fails loudly instead of inserting"
( OPEN5GS_DB_URI="mongodb://127.0.0.1:1/nope" ensure_subscriber ) >/dev/null 2>&1
check "non-zero exit" "$?" "1"

mongosh --quiet --eval "db.dropDatabase()" "$U" >/dev/null 2>&1
echo
echo "cases run: $((PASS+FAIL))   passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
