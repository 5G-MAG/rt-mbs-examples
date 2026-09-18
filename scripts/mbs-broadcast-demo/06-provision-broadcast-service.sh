#!/bin/bash
# Provisions the demo MBS User Service and its Broadcast Ingest Session, driven entirely
# through rt-mbs-function's (MBSF) own Nmb10 REST API -- no direct MBSTF or SMF calls.
# This is the one control point the user asked for: "all needs to be managed from
# rt-mbs-function so all APIs should work from there properly".
#
# API shapes below are code-derived/verified against rt-mbs-application-provider's own
# lib/mbsUserService.js, lib/mbsIngestSession.js and rt-mbs-examples/insomnia/
# 5G-MAG_MBSF-insomnia_collection.yaml's "Create Carousel MBS User Data Ingest Session"
# example, cross-checked live against rt-mbs-function/src/mbsf/UserDataIngSession.cc:
#   - servType ("BROADCAST" vs "MULTICAST") lives on the User Service, not the ingest
#     session -- UserDataIngSession.cc:2090 reads it from the parent User Service's own
#     servType, not from anything in the ingest-session body itself.
#   - a brand new TMGI is allocated by MB-SMF precisely when 'mbsSessionId' is entirely
#     ABSENT from the per-session object (UserDataIngSession.cc:
#     "if no MBS session identifier is provided ... MBSF shall include a "tmgiAllocReq"
#     attribute set to "true""), which is the form this script uses.
#
#     A BROADCAST service must use that form. TS 23.247 V18.8.0 clause 6.5.1 gives the
#     MBS Session ID types as "-TMGI (for broadcast and multicast MBS sessions);" and
#     "-source specific IP multicast address (for multicast MBS sessions)", so an SSM
#     identifies a multicast session only. This script used to send one anyway, together
#     with "locationDependent": true, because MBSF's SDP builder could then find an
#     origin line and connection info; without it the announcement bundle was never
#     written. MBSF now takes those addresses from its own mbsf.broadcastDistribution
#     configuration, the same pair it gives the MBSTF for the Nmb9 flow, so the SSM is no
#     longer needed and is refused for a BROADCAST service.
#
#     The address on the wire is therefore mbsf.broadcastDistribution.destinationAddress,
#     which the demo sets from the on-air channel's ssmDest. One on-air channel at a time
#     is fine; a second would need 5G-MAG/rt-mbs-function#59, because that configuration is
#     one pair per MBSF while the specification makes the Nmb9 label per Distribution
#     Session.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source env.sh
source lib.sh
ensure_dirs

require_cmd curl
require_cmd python3
wait_for_tcp "$MBSF_ADDR" "$SBI_PORT" 5 || die "MBSF is not up yet -- run 02-start-mbs-function.sh first"
wait_for_http "http://$MEDIA_HOST:$MEDIA_PORT/carousel" 5 || die "media server/carousel not up yet -- run 03-start-media-server.sh first"

MBSF_BASE="http://$MBSF_ADDR:$SBI_PORT"

log "creating MBS User Service ($DEMO_SERVICE_NAME, servType BROADCAST)"
SVC_BODY=$(cat <<EOF
{
  "extServiceIds": ["$DEMO_SERVICE_EXT_ID"],
  "servType": "BROADCAST",
  "servClass": "urn:oma:bcast:oma_bsc:st:1.0",
  "servAnnModes": ["VIA_MBS_DISTRIBUTION_SESSION"],
  "servNameDescs": [
    { "servName": "$DEMO_SERVICE_NAME", "servDescrip": "$DEMO_SERVICE_DESC", "language": "eng" }
  ],
  "mainServLang": "eng"
}
EOF
)
SVC_HEADERS=$(mktemp)
curl -s -m 10 --http2-prior-knowledge -X POST -H 'Content-Type: application/json' -D "$SVC_HEADERS" -o /tmp/.svc_resp.$$ \
    "$MBSF_BASE/nmbsf-mbs-us/v1/mbs-user-services" -d "$SVC_BODY"
SVC_ID=$(grep -i '^location:' "$SVC_HEADERS" | tail -1 | tr -d '\r' | sed 's#.*/##')
rm -f "$SVC_HEADERS" /tmp/.svc_resp.$$
[[ -n "$SVC_ID" ]] || die "MBS User Service creation did not return a Location header -- check MBSF's own log ($LOG_DIR/mbsf.log)"
echo "$SVC_ID" > "$STATE_DIR/service_id"
log "User Service created: $SVC_ID"

log "creating Broadcast Ingest Session (CAROUSEL/PULL from http://$MEDIA_HOST:$MEDIA_PORT/, TMGI auto-allocated)"
ING_BODY=$(cat <<EOF
{
  "mbsUserServId": "$SVC_ID",
  "mbsDisSessInfos": {
    "AP_MBS_SESSION_1": {
      "mbsDistSessState": "ACTIVE",
      "maxContBitRate": "$INGEST_MAX_BITRATE",
      "distrMethod": "OBJECT",
      "objDistrInfo": {
        "operatingMode": "CAROUSEL",
        "objAcqMethod": "PULL",
        "objIngUri": "http://$MEDIA_HOST:$MEDIA_PORT/",
        "objAcqIds": ["carousel"]
      }
    }
  },
  "suppFeat": "3"
}
EOF
)
ING_HEADERS=$(mktemp)
curl -s -m 30 --http2-prior-knowledge -X POST -H 'Content-Type: application/json' -D "$ING_HEADERS" -o /tmp/.ing_resp.$$ \
    "$MBSF_BASE/nmbsf-mbs-ud-ingest/v1/sessions" -d "$ING_BODY"
ING_ID=$(grep -i '^location:' "$ING_HEADERS" | tail -1 | tr -d '\r' | sed 's#.*/##')
ING_RESP=$(cat /tmp/.ing_resp.$$)
rm -f "$ING_HEADERS" /tmp/.ing_resp.$$
if [[ -z "$ING_ID" ]]; then
    log "Ingest Session creation response: $ING_RESP"
    die "Ingest Session creation did not return a Location header -- check MBSF's own log ($LOG_DIR/mbsf.log) and the response above"
fi
echo "$ING_ID" > "$STATE_DIR/ingest_session_id"
log "Ingest Session created: $ING_ID"

log "waiting for the distribution session to reach ACTIVE (MB-SMF/NGAP setup can take a few seconds)"
for _ in $(seq 1 20); do
    STATE=$(curl -s -m 5 --http2-prior-knowledge "$MBSF_BASE/nmbsf-mbs-ud-ingest/v1/sessions/$ING_ID" \
        | python3 -c "import json,sys; d=json.load(sys.stdin); print(list(d.get('mbsDisSessInfos',{}).values())[0].get('mbsDistSessState','?'))" 2>/dev/null || echo "?")
    [[ "$STATE" == "ACTIVE" ]] && break
    sleep 1
done
log "distribution session state: ${STATE:-unknown}"

log "provisioned. Give the announcement carousel ~10-15s to repeat, then check the dashboard."
log "  Service:  $SVC_ID"
log "  Ingest:   $ING_ID"
