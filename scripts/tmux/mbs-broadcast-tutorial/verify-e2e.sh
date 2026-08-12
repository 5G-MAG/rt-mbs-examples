#!/usr/bin/env bash
#
# verify-e2e.sh -- End-to-end MBS Broadcast proof: creates a real MBS User Service (with a
# genuine TS 26.517 Service Announcement, mode VIA_MBS_DISTRIBUTION_SESSION -- the mode that
# actually makes MBSF broadcast its own Service Announcement carousel, not VIA_MBS_5), pushes
# a small piece of real content through it, and verifies BOTH of the two things this whole
# tutorial exists to prove:
#
#   1. The Service Announcement carousel is genuinely broadcast over the air and the
#      receive-side rt-mbs-client discovers the service through it (not through any
#      out-of-band shortcut -- this is the same GET /mbs-client-api/services a real
#      MBS-Aware Application UI would call to list what's on air).
#   2. The actual pushed content is activated (again via the client's normal
#      GET /mbs-client-api/services/activate -- what a real "Play" button calls) and lands,
#      byte-identical, in the client's ReceivedContentStore.
#
# Prerequisites: ./transmit.sh and (as root) ./receive-netns.sh start already running.
#
# Usage: ./verify-e2e.sh
#
set -euo pipefail

LOG_DIR="${LOG_DIR:-$HOME/.local/state/mbs-broadcast-tutorial}"
PROVIDER_DIR="${PROVIDER_DIR:-$HOME/Repos/rt-mbs/rt-mbs-application-provider}"
PORTAL_HOST="${PORTAL_HOST:-127.0.0.1}"
PORTAL_PORT="${PORTAL_PORT:-8081}"
CLIENT_API="${CLIENT_API:-http://10.90.1.2:3031/mbs-client-api}"
MBSTF_HOST="${MBSTF_HOST:-127.0.0.61}"

die() { echo "verify-e2e.sh: $*" >&2; exit 1; }

[ -f "$LOG_DIR/MBSTF.log" ] || die "$LOG_DIR/MBSTF.log not found -- is ./transmit.sh running?"
[ -f "$PROVIDER_DIR/.env" ] || die "$PROVIDER_DIR/.env not found -- see $PROVIDER_DIR/.env.example"

AUTH_USER=$(grep -E '^AUTH_USER=' "$PROVIDER_DIR/.env" | cut -d= -f2- | tr -d '"'"'"'\r')
AUTH_TOKEN=$(grep -E '^AUTH_TOKEN=' "$PROVIDER_DIR/.env" | cut -d= -f2- | tr -d '"'"'"'\r')
[ -n "$AUTH_TOKEN" ] || die "AUTH_TOKEN not set in $PROVIDER_DIR/.env"
AUTH="${AUTH_USER:-admin}:$AUTH_TOKEN"
PORTAL="http://$PORTAL_HOST:$PORTAL_PORT"

echo "== MBS Broadcast end-to-end verification =="
echo "   Portal:     $PORTAL"
echo "   Client API: $CLIENT_API"
echo

# ---------------------------------------------------------------------------
# 1. Real demo content -- a tiny, self-describing text file. Content is checked byte-for-byte
#    at the end, so anything recognisable works; this one just states what it's proving.
# ---------------------------------------------------------------------------
WORKDIR=$(mktemp -d)
SVC_ID=""
cleanup() {
  rm -rf "$WORKDIR"
  # Delete the MBS User Service (cascades to its Ingest Session(s)) -- each run allocates real
  # MRB LCIDs at the gNB, and the whole DU only has 12 of them (LCID_MIN_MRB..LCID_MAX_MRB, TS
  # 38.331). A demo script that's meant to be run repeatedly and leaks a session every time will
  # silently exhaust that pool after a handful of runs and start failing for a completely
  # different, much more confusing reason later -- confirmed live. Runs on exit whether this
  # script succeeded or failed partway through.
  [ -n "$SVC_ID" ] && curl -sS -o /dev/null -u "$AUTH" -X DELETE "$PORTAL/mbs-user-services/$SVC_ID" 2>/dev/null || true
}
trap cleanup EXIT
DEMO_FILE="hello-mbs-broadcast.txt"
cat > "$WORKDIR/$DEMO_FILE" <<'EOF'
This file was pushed into MBSF, carried over a real NGAP Broadcast Session Setup / F1AP /
MCCH+MTCH / PDCP+RLC air interface, and received by rt-mbs-client via FLUTE -- the same path
real broadcast content takes. If you can read this after it was fetched back from the
receive side, MBS Broadcast delivery worked end-to-end.
EOF
DEMO_LEN=$(wc -c < "$WORKDIR/$DEMO_FILE")

# A small, valid (1-254) IPv4 last-octet derived from this run's PID, so repeated runs don't
# collide on the same SSM address as a still-torn-down-but-lingering previous session. $$ itself
# is NOT a valid octet (it regularly exceeds 255) -- confirmed live: using it directly produced
# an invalid destIpAddr that MBSF/the AF service consumer library rejected outright.
IP_SUFFIX=$(( ($$ % 200) + 50 ))

# ---------------------------------------------------------------------------
# 2. Create the MBS User Service. servAnnModes MUST be VIA_MBS_DISTRIBUTION_SESSION -- that is
#    the mode that makes MBSF stand up and broadcast its own Service Announcement carousel
#    (UserService::requiresUserServiceAnnouncement()/checkAndSetUserServiceAnnouncementChannel()
#    both gate on exactly this value). VIA_MBS_5 (a client fetching the announcement itself via
#    a direct AF connection, not implemented by this reference MBSF) will NOT do this --
#    confirmed live: a User Service created with VIA_MBS_5 alone never appears in the
#    announcement carousel at all, no matter how long you wait.
# ---------------------------------------------------------------------------
EXT_SERVICE_ID="https://example.broadcaster.com/services/e2e-verify-$$"
SVC_RESP=$(curl -sS -u "$AUTH" -X POST -H "Content-Type: application/json" -D "$WORKDIR/svc.hdrs" \
  -d "{
    \"extServiceIds\": [\"$EXT_SERVICE_ID\"],
    \"servType\": \"BROADCAST\",
    \"servClass\": \"urn:oma:bcast:oma_bsc:st:1.0\",
    \"servAnnModes\": [\"VIA_MBS_DISTRIBUTION_SESSION\"],
    \"servNameDescs\": [{\"servName\": \"MBS Broadcast E2E Verify\", \"servDescrip\": \"Automated end-to-end delivery check\", \"language\": \"eng\"}],
    \"mainServLang\": \"eng\"
  }" "$PORTAL/mbs-user-services")
SVC_ID=$( (grep -i '^Location:' "$WORKDIR/svc.hdrs" || true) | sed 's#.*/##' | tr -d '\r')
[ -n "$SVC_ID" ] || die "failed to create MBS User Service: $SVC_RESP"
echo "[1/7] Created MBS User Service $SVC_ID (ext id: $EXT_SERVICE_ID)"

# ---------------------------------------------------------------------------
# 3. Create the Ingest Session: STREAMING/PUSH, one object (the demo file). INACTIVE at
#    creation -- MBSTF stands up a real (ephemeral-port) push ingest server for it immediately,
#    logged to MBSTF.log, which is how we learn where to push the content in step 4.
# ---------------------------------------------------------------------------
LOG_MARK=$(wc -l < "$LOG_DIR/MBSTF.log")
DS_RESP=$(curl -sS -u "$AUTH" -X POST -H "Content-Type: application/json" -D "$WORKDIR/is.hdrs" \
  -d "{
    \"mbsUserServId\": \"$SVC_ID\",
    \"mbsDisSessInfos\": {
      \"AP_MBS_SESSION_1\": {
        \"mbsSessionId\": {\"ssm\": {\"sourceIpAddr\": {\"ipv4Addr\": \"127.0.0.71\"}, \"destIpAddr\": {\"ipv4Addr\": \"232.71.0.$IP_SUFFIX\"}}},
        \"mbsDistSessState\": \"INACTIVE\",
        \"maxContBitRate\": \"10 Mbps\",
        \"distrMethod\": \"OBJECT\",
        \"objDistrInfo\": {\"operatingMode\": \"STREAMING\", \"objAcqMethod\": \"PUSH\", \"objAcqIds\": [\"$DEMO_FILE\"]}
      }
    },
    \"suppFeat\": \"3\"
  }" "$PORTAL/ingest-sessions")
ING_ID=$( (grep -i '^Location:' "$WORKDIR/is.hdrs" || true) | sed 's#.*/##' | tr -d '\r')
DIST_SESS_ID=$(echo "$DS_RESP" | jq -r '.mbsDisSessInfos.AP_MBS_SESSION_1.mbsDistSessionId // ""')
MBS_SERVICE_ID=$(echo "$DS_RESP" | jq -r '.mbsDisSessInfos.AP_MBS_SESSION_1.mbsSessionId.tmgi.mbsServiceId // ""')
[ -n "$ING_ID" ] && [ -n "$DIST_SESS_ID" ] || die "failed to create Ingest Session: $DS_RESP"
echo "[2/7] Created Ingest Session $ING_ID (Distribution Session $DIST_SESS_ID)"

# Find the push port MBSTF just allocated for this session (the first "PUSH SERVER PORT" log
# line to appear after LOG_MARK). Retries for up to 10s -- this is an async log write, not an
# API response field.
PUSH_PORT=""
for _ in $(seq 1 50); do
  # -a: MBSTF.log can accumulate binary bytes across a long-lived process's many test runs
  # (e.g. raw content payloads logged verbatim elsewhere in the file), which makes grep treat
  # the whole file as binary and print "binary file matches" instead of the actual port number
  # -- confirmed live, this silently broke every retry of this check for an entire 10s window.
  # -a forces text-mode matching regardless of what the rest of the file contains.
  PUSH_PORT=$(tail -n "+$((LOG_MARK + 1))" "$LOG_DIR/MBSTF.log" | grep -aoP 'PUSH SERVER PORT: \K\d+' | head -1 || true)
  [ -n "$PUSH_PORT" ] && break
  sleep 0.2
done
[ -n "$PUSH_PORT" ] || die "MBSTF never logged a push server port for this session -- check $LOG_DIR/MBSTF.log"
echo "[3/7] MBSTF push ingest ready at $MBSTF_HOST:$PUSH_PORT"

# ---------------------------------------------------------------------------
# 4. Push the actual content.
# ---------------------------------------------------------------------------
PUSH_CODE=$(curl -sS -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: text/plain' \
  --data-binary "@$WORKDIR/$DEMO_FILE" "http://$MBSTF_HOST:$PUSH_PORT/$DEMO_FILE")
[ "$PUSH_CODE" = "200" ] || die "content push failed (HTTP $PUSH_CODE)"
echo "[4/7] Pushed $DEMO_FILE ($DEMO_LEN bytes) to MBSTF"

# ---------------------------------------------------------------------------
# 5. Activate the Distribution Session -- this is what actually starts FLUTE transmission over
#    the air, and (via configureUserServiceAnnouncementBundler()) what makes this session
#    eligible to be bundled into the next Service Announcement carousel cycle.
# ---------------------------------------------------------------------------
ACT_CODE=$(curl -sS -o /dev/null -w '%{http_code}' -u "$AUTH" -X PUT -H "Content-Type: application/json" \
  -d "{
    \"mbsUserServId\": \"$SVC_ID\",
    \"mbsDisSessInfos\": {
      \"AP_MBS_SESSION_1\": {
        \"mbsDistSessionId\": \"$DIST_SESS_ID\",
        \"mbsDistSessState\": \"ACTIVE\",
        \"mbsSessionId\": {\"tmgi\": {\"mbsServiceId\": \"$MBS_SERVICE_ID\", \"plmnId\": {\"mcc\": \"000\", \"mnc\": \"000\"}}, \"ssm\": {\"sourceIpAddr\": {\"ipv4Addr\": \"127.0.0.71\"}, \"destIpAddr\": {\"ipv4Addr\": \"232.71.0.$IP_SUFFIX\"}}},
        \"maxContBitRate\": \"10 Mbps\",
        \"distrMethod\": \"OBJECT\",
        \"objDistrInfo\": {\"operatingMode\": \"STREAMING\", \"objAcqMethod\": \"PUSH\", \"objAcqIds\": [\"$DEMO_FILE\"]}
      }
    },
    \"suppFeat\": \"3\"
  }" "$PORTAL/ingest-sessions/$ING_ID")
[ "$ACT_CODE" = "200" ] || die "activation failed (HTTP $ACT_CODE)"
echo "[5/7] Activated Distribution Session"

# ---------------------------------------------------------------------------
# 6. Service Announcement: poll the CLIENT's own /services (the same call a real MBS-Aware
#    Application's "what's on air" list uses) until our service shows up. This only succeeds if
#    the client genuinely received and parsed a real over-the-air announcement carousel bundle
#    naming this service -- there is no other way for it to appear here.
# ---------------------------------------------------------------------------
FOUND=""
# BUG FIX (found live): a 60s wait here is right at the edge of the real announcement pipeline's
# round-trip -- the bundler's own worker thread rebuild, the announcement channel's own carousel
# push cycle, FLUTE broadcast, and client-side reception/parsing all happen async and can
# together take just over a minute the first time a brand-new session appears. 150s observed
# reliable; use 180s for margin.
for i in $(seq 1 180); do
  FOUND=$(curl -sS "$CLIENT_API/services" | jq -e --arg id "$EXT_SERVICE_ID" \
    '[.[] | select(.serviceIds[]? == $id)] | length > 0' 2>/dev/null || echo false)
  [ "$FOUND" = "true" ] && break
  sleep 1
done
[ "$FOUND" = "true" ] || die "Service Announcement for $EXT_SERVICE_ID never appeared at $CLIENT_API/services after 180s"
echo "[6/7] Service Announcement received: $EXT_SERVICE_ID is listed at $CLIENT_API/services"

# ---------------------------------------------------------------------------
# 7. Activate reception on the client (the same call a real "Play" button makes) and verify the
#    pushed content lands, byte-identical, in the client's own cache.
#
# BUG FIX (found live, 2026-08-12): the STREAMING operating mode used in step 3 has no real
# presentation manifest behind it here (just a plain file), so MBSTF's ObjectStreamingController
# falls back to the same one-shot ObjectListPackager send SINGLE mode uses -- confirmed live via
# MBSTF.log's single "Transmitted: Object with TOI" line, logged right at step 5's activation,
# with no repeat. The client can only join this session's FLUTE group *after* it discovers the
# service via the announcement carousel (step 6), which -- by design -- takes noticeably longer
# than that one-shot send. So every run missed the one and only transmission entirely: not
# packet loss, not a receiver bug, just a structural ordering gap in this test (real CAROUSEL-mode
# delivery, which repeats on a schedule, would need a manifest object and is out of scope for a
# minimal demo). Re-pushing the same content now, after the client has activated reception, gives
# it a transmission it can actually be listening for -- exactly what a real broadcaster would do
# for a receiver that might join late, and does not require a manifest.
#
# BUG FIX (found live, 2026-08-12): a single re-push still isn't reliable on its own. srsue's
# get_dl_sched_rnti_nr() checks only one PDCCH candidate per TTI (see mac_nr.h's NOTE on g_rntis)
# and round-robins across every concurrently-advertised broadcast G-RNTI -- correct behaviour, and
# confirmed live to work (a content G-RNTI alongside the announcement channel's own DID get a real
# PDCCH/PDSCH decode, CRC=OK), but with N concurrent sessions a given G-RNTI is only actually
# checked on roughly 1-in-N TTIs. A single short transmission burst can easily fall entirely within
# TTIs the round-robin spent on the OTHER G-RNTI and be missed completely -- confirmed live:
# identical back-to-back runs of this exact script, same binaries, no code changes, PASSED once
# and then MISSED step 7 the very next time. Not a bug to route around silently: it's the
# documented cost of this fork's one-candidate-per-TTI PHY model (a real fix needs genuine
# multi-candidate blind decoding). Given a manifest-driven CAROUSEL session is out of scope here,
# the practical mitigation is simply more chances to line up with an "on" round-robin slot: keep
# re-pushing periodically for the whole wait window instead of once.
# ---------------------------------------------------------------------------
curl -sS -G "$CLIENT_API/services/activate" --data-urlencode "external-service-id=$EXT_SERVICE_ID" > /dev/null || true
sleep 3

RECEIVED=""
for i in $(seq 1 90); do
  if [ $(( (i - 1) % 10 )) -eq 0 ]; then
    curl -sS -o /dev/null -X POST -H 'Content-Type: text/plain' \
      --data-binary "@$WORKDIR/$DEMO_FILE" "http://$MBSTF_HOST:$PUSH_PORT/$DEMO_FILE" 2>/dev/null || true
  fi
  RECEIVED=$(curl -sS "$CLIENT_API/content/$DEMO_FILE" 2>/dev/null || true)
  [ "$RECEIVED" = "$(cat "$WORKDIR/$DEMO_FILE")" ] && break
  sleep 1
done
[ "$RECEIVED" = "$(cat "$WORKDIR/$DEMO_FILE")" ] || die "content never arrived byte-identical at $CLIENT_API/content/$DEMO_FILE after 90s (repeated re-pushes every 10s)"
echo "[7/7] Content received, byte-identical: $CLIENT_API/content/$DEMO_FILE"

echo
echo "== PASS: Service Announcement + real content both delivered end-to-end =="
