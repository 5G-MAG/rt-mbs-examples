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

echo "RAN (inside $NETNS):"
if netns_exists; then
    UE_IP=$(sudo -n ip netns exec "$NETNS" ip -o -4 addr show tun_bcastue 2>/dev/null | awk '{print $4}' | cut -d/ -f1)
    if [[ -n "$UE_IP" ]]; then echo "  [up]   UE PDU session ($UE_IP)"; else echo "  [down] UE PDU session (no tun_bcastue address)"; fi
fi

echo "Portals:"
check_tcp "rt-mbs-application (in $NETNS)" "$VETH_NS_ADDR" "$APP_PORT"
check_tcp "rt-mbs-application-provider" 127.0.0.1 "$PROVIDER_PORT"

if [[ -f "$STATE_DIR/ingest_session_id" ]]; then
    ING_ID=$(cat "$STATE_DIR/ingest_session_id")
    echo "Provisioned demo session: $ING_ID"
    curl -s -m 3 "http://$MBSF_ADDR:$SBI_PORT/nmbsf-mbs-ud-ingest/v1/sessions/$ING_ID" \
        | python3 -m json.tool 2>/dev/null | sed 's/^/  /' || echo "  (MBSF not reachable)"
fi
