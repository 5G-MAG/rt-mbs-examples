#!/bin/bash
# Creates the live DASH MBS User Service and its Ingest Session through the application provider,
# then asks the MBS Client to join it. Shared by both bring-up paths so the RAN-free run and the
# full gNB/UE run provision exactly the same service: the only difference between them is what
# carries the FLUTE packets.
#
# The Distribution Session runs in OBJECT_STREAMING with the presentation manifest as its entry
# point, which is the mode 3GPP recommends for DASH (TS 26.517 clause 6.2.3.5). The User Service
# Announcement Channel is the carousel in this deployment, and the MBSF runs that itself.
#
# Inputs (all defaulted in env.sh or by the caller):
#   PRESENTATION_PATH   manifest to distribute, relative to the media server's public directory
#   SESSION_MAX_BITRATE session maximum bit rate
#   CLIENT_API          the MBS Client's local API, which differs between the two paths
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source env.sh
source lib.sh

SERVICE_ID="${BYPASS_SERVICE_ID:-https://mwc-tv-radio.ebu.io/services/tv_1_live}"
SERVICE_CLASS="${BYPASS_SERVICE_CLASS:-urn:oma:bcast:oma_bsc:st:1.0}"
SERVICE_NAME="${BYPASS_SERVICE_NAME:-MWC TV 1 live loop}"
SERVICE_DESC="${BYPASS_SERVICE_DESC:-Looping live DASH}"
PRESENTATION_PATH="${PRESENTATION_PATH:-$LIVE_STREAM_NAME/manifest.mpd}"
SESSION_MAX_BITRATE="${SESSION_MAX_BITRATE:-${BYPASS_MAX_BITRATE:-6 Mbps}}"

# Application-layer FEC for the distribution session. Broadcast has no retransmission -- DCI format 4_0
# carries no HARQ process number and no feedback timing indicator (TS 38.212 V17.13.0 clause 7.3.1.5.1) --
# so a lost transport block is lost outright, and an object is recovered only if every one of its blocks
# arrives. That makes large objects far more fragile than small ones at the same block loss rate: a video
# segment spanning ~115 blocks and an audio segment spanning ~19 do not fail at similar rates.
#
# FEC is the mechanism the MBMS Download Profile provides for exactly this, and both ends here implement
# Raptor (FEC Encoding ID 1, RFC 5053). fecOverHead is the percentage of repair symbols added; it costs
# bearer capacity in exchange for tolerating that much loss, so the operator sets it from the loss the
# deployment actually sees.
#
# Off by default (Compact No-Code) so a run costs no bearer capacity it does not need; this service's
# measured block loss is far below what 20% repair is worth paying for. Set FEC_SCHEME to
# "urn:ietf:rmt:fec:encoding:1" to request Raptor, which works end to end: an object too small to fill
# four encoding symbols at the session's symbol length is packaged with a shorter symbol, declared
# per file in the FDT, rather than being refused (RFC 5053 clause 5.7 lists systematic indices for K
# between 4 and 8192, so a block below four symbols cannot be encoded).
FEC_SCHEME="${FEC_SCHEME:-urn:ietf:rmt:fec:encoding:0}"
FEC_OVERHEAD="${FEC_OVERHEAD:-20}"
if [ "$FEC_SCHEME" = "urn:ietf:rmt:fec:encoding:0" ]; then
    FEC_CONFIG_JSON=""
else
    FEC_CONFIG_JSON="\"fecConfig\": { \"fecScheme\": \"$FEC_SCHEME\", \"fecOverHead\": $FEC_OVERHEAD },"
fi
PROVIDER_URL="http://127.0.0.1:$PROVIDER_PORT"
PROVIDER_AUTH="$PROVIDER_AUTH_USER:$PROVIDER_AUTH_TOKEN"
CLIENT_API="${CLIENT_API:-http://127.0.0.1:$MBS_CLIENT_API_PORT/mbs-client-api}"
# The MBS Client runs on loopback on the RAN-free path and inside the gNB network namespace on the
# full path, where its API is not reachable from the root namespace. The caller supplies whatever
# prefix reaches it, so this script does not need to know which path it is on.
CLIENT_CURL="${CLIENT_CURL:-curl}"

log "creating the MBS User Service and its Ingest Session via the provider"
svc_id=$(post_for_id "MBS User Service creation" "$PROVIDER_URL/mbs-user-services" "$PROVIDER_AUTH" "{
      \"extServiceIds\": [\"$SERVICE_ID\"],
      \"servType\": \"BROADCAST\",
      \"servClass\": \"$SERVICE_CLASS\",
      \"servAnnModes\": [\"VIA_MBS_DISTRIBUTION_SESSION\"],
      \"servNameDescs\": [{\"servName\": \"$SERVICE_NAME\", \"servDescrip\": \"$SERVICE_DESC\", \"language\": \"eng\"}],
      \"mainServLang\": \"eng\"
    }")
echo "$svc_id" > "$STATE_DIR/live_service_id"
log "MBS User Service: $svc_id"

ing_id=$(post_for_id "Ingest Session creation" "$PROVIDER_URL/ingest-sessions" "$PROVIDER_AUTH" "{
      \"mbsUserServId\": \"$svc_id\",
      \"mbsDisSessInfos\": { \"AP_MBS_SESSION_1\": {
          \"mbsSessionId\": { \"ssm\": { \"sourceIpAddr\": { \"ipv4Addr\": \"$BCAST_SSM_SOURCE\" },
                                         \"destIpAddr\": { \"ipv4Addr\": \"$BCAST_SSM_DEST\" } } },
          \"locationDependent\": true,
          \"mbsDistSessState\": \"ACTIVE\",
          \"maxContBitRate\": \"$SESSION_MAX_BITRATE\",
          $FEC_CONFIG_JSON
          \"distrMethod\": \"OBJECT\",
          \"objDistrInfo\": { \"operatingMode\": \"STREAMING\", \"objAcqMethod\": \"PULL\",
            \"objIngUri\": \"http://$MEDIA_HOST:$MEDIA_PORT/\", \"objAcqIds\": [\"$PRESENTATION_PATH\"] } } },
      \"suppFeat\": \"3\"
    }")
echo "$ing_id" > "$STATE_DIR/ingest_session_id"
log "Ingest Session: $ing_id"

# The client learns the service from the announcement channel by itself; this only waits for that
# to arrive before asking it to join. A client does not join an announced service on its own.
log "waiting for the client to learn the service from the announcement, then activating"
for _ in $(seq 1 45); do
    $CLIENT_CURL -s -m 10 "$CLIENT_API/services" 2>/dev/null | grep -q "$SERVICE_ID" && break
    sleep 2
done
$CLIENT_CURL -s -m 30 --get --data-urlencode "external-service-id=$SERVICE_ID" \
    "$CLIENT_API/services/activate" -o /dev/null -w '' || true
log "activation requested"
