#!/bin/bash
# Creates the ns-gnb network namespace and the veth pair carrying N2 (NGAP)/N3 (GTP-U)
# between the 5GC (root namespace, loopback addresses) and the gNB/UE/rt-mbs-client/
# rt-mbs-application (ns-gnb). Idempotent: safe to re-run.
#
# code-derived, no spec claim -- this is deployment topology, not 3GPP-governed behaviour.
#
# Usage: ./00-setup-netns.sh            # create (default)
#        ./00-setup-netns.sh --teardown # remove the namespace and veth pair
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source env.sh
source lib.sh

require_cmd ip
require_cmd sudo
sudo -n true || die "passwordless sudo (or a cached sudo timestamp) is required"

teardown() {
    log "tearing down $NETNS"
    sudo -n ip netns del "$NETNS" 2>/dev/null || true
    sudo -n ip link del "$VETH_ROOT" 2>/dev/null || true
    log "done"
}

if [[ "${1:-}" == "--teardown" ]]; then
    teardown
    exit 0
fi

if netns_exists; then
    log "$NETNS already exists, checking it looks right"
else
    log "creating $NETNS"
    sudo -n ip netns add "$NETNS"
fi

# veth pair: $VETH_ROOT stays in the root namespace, $VETH_NS moves into $NETNS
if ! ip link show "$VETH_ROOT" >/dev/null 2>&1; then
    log "creating veth pair $VETH_ROOT <-> $VETH_NS"
    sudo -n ip link add "$VETH_ROOT" type veth peer name "$VETH_NS"
    sudo -n ip link set "$VETH_NS" netns "$NETNS"
else
    log "veth pair $VETH_ROOT already exists"
fi

sudo -n ip addr replace "$VETH_ROOT_ADDR/$VETH_PREFIX" dev "$VETH_ROOT"
sudo -n ip link set "$VETH_ROOT" up
sudo -n ip netns exec "$NETNS" ip addr replace "$VETH_NS_ADDR/$VETH_PREFIX" dev "$VETH_NS"
sudo -n ip netns exec "$NETNS" ip link set "$VETH_NS" up
sudo -n ip netns exec "$NETNS" ip link set lo up

# Multicast route: FLUTE/announcement traffic (232.0.0.0/8-ish destinations, per mbsf.yaml's
# ssmDestinationAddress/broadcastDistribution.destinationAddress) is originated by MBSF/
# MBSTF in the root namespace and must be sent out over the veth pair to actually reach the
# UE side -- the kernel does not route class-D multicast via unicast routes by default, this
# static route is what makes it happen. code-derived, no spec claim: this is host networking,
# not 3GPP behaviour.
sudo -n ip route replace 239.0.0.0/8 dev "$VETH_ROOT" 2>/dev/null || true

log "$NETNS ready:"
sudo -n ip netns exec "$NETNS" ip -o addr show | sed 's/^/  /'
