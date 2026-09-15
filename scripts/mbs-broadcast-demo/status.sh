#!/bin/bash
# Quick health check of every component this demo starts.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source env.sh
source lib.sh

check_tcp() {
    local name="$1" host="$2" port="$3"
    if (exec 3<>"/dev/tcp/$host/$port") 2>/dev/null; then
        exec 3>&- 2>/dev/null
        echo "  [up]   $name ($host:$port)"
    else
        echo "  [down] $name ($host:$port)"
    fi
}

echo "Network namespace:"
if netns_exists; then echo "  [up]   $NETNS"; else echo "  [down] $NETNS (run 00-setup-netns.sh)"; fi

echo "5G core:"
check_tcp NRF "$NRF_ADDR" "$SBI_PORT"
check_tcp AUSF "$AUSF_ADDR" "$SBI_PORT"
check_tcp UDM "$UDM_ADDR" "$SBI_PORT"
check_tcp UDR "$UDR_ADDR" "$SBI_PORT"
check_tcp PCF "$PCF_ADDR" "$SBI_PORT"
check_tcp NSSF "$NSSF_ADDR" "$SBI_PORT"
check_tcp BSF "$BSF_ADDR" "$SBI_PORT"
check_tcp AMF "$AMF_ADDR" "$SBI_PORT"
check_tcp SMF "$SMF_ADDR" "$SBI_PORT"

echo "MBS function:"
check_tcp MBSTF "$MBSTF_SBI_ADDR" "$SBI_PORT"
check_tcp MBSF "$MBSF_ADDR" "$SBI_PORT"

echo "Media server:"
check_tcp "media server" "$MEDIA_HOST" "$MEDIA_PORT"
while IFS=$'\t' read -r ch_id ch_stream ch_source ch_type ch_vbr; do
    air=$(onair_rows | cut -f3 | grep -qx "$ch_stream" && echo "on air" || echo "origin only")
    segs=$(ls "$MEDIA_DIR/public/$ch_stream" 2>/dev/null | grep -c '\.m4s$' || echo 0)
    if pgrep -f "ffmpeg -re .*/$ch_stream" >/dev/null 2>&1 \
       && curl -s -o /dev/null -m 3 "http://$MEDIA_HOST:$MEDIA_PORT/$ch_stream/manifest.mpd"; then
        echo "  [up]   $ch_stream  ($air, $segs segments)  http://$MEDIA_HOST:$MEDIA_PORT/$ch_stream/manifest.mpd"
    else
        echo "  [down] $ch_stream  ($air)"
    fi
done < <(channel_rows)

echo "RAN (inside $NETNS):"
if netns_exists; then
    UE_IP=$(sudo -n ip netns exec "$NETNS" ip -o -4 addr show tun_bcastue 2>/dev/null | awk '{print $4}' | cut -d/ -f1)
    if [[ -n "$UE_IP" ]]; then echo "  [up]   UE PDU session ($UE_IP)"; else echo "  [down] UE PDU session (no tun_bcastue address)"; fi
fi

echo "Portals:"
check_tcp "rt-mbs-application (in $NETNS)" "$VETH_NS_ADDR" "$APP_PORT"
check_tcp "rt-mbs-application-provider" 127.0.0.1 "$PROVIDER_PORT"

# One Ingest Session per on-air channel, each in its own state file.
while IFS=$'\t' read -r ch_id ch_name ch_stream ch_ssm; do
    [[ -f "$STATE_DIR/ingest_session_id.$ch_stream" ]] || continue
    ING_ID=$(cat "$STATE_DIR/ingest_session_id.$ch_stream")
    echo "Provisioned session, $ch_name ($ch_stream): $ING_ID"
    # The SBI speaks HTTP/2 with no upgrade from HTTP/1.1, so a plain curl never gets a
    # response and this reported "(MBSF not reachable)" against a healthy, reachable MBSF.
    curl -s -m 3 --http2-prior-knowledge "http://$MBSF_ADDR:$SBI_PORT/nmbsf-mbs-ud-ingest/v1/sessions/$ING_ID" \
        | python3 -m json.tool 2>/dev/null | sed 's/^/  /' || echo "  (MBSF not reachable)"
done < <(onair_rows)
