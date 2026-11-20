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
ensure_sudo

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

# veth pair: $VETH_ROOT stays in the root namespace, $VETH_NS moves into $NETNS.
#
# Both ends are checked, not just $VETH_ROOT. Deleting $NETNS takes $VETH_NS with it and leaves
# $VETH_ROOT behind, so a run after an interrupted teardown finds the root end present, skips
# creating the pair, and then fails on the next line with "Cannot find device". A root end whose
# peer is gone is not a pair; delete it and make a real one.
if ip link show "$VETH_ROOT" >/dev/null 2>&1 && \
   ! sudo -n ip netns exec "$NETNS" ip link show "$VETH_NS" >/dev/null 2>&1; then
    log "$VETH_ROOT survived without its peer $VETH_NS; recreating the pair"
    sudo -n ip link delete "$VETH_ROOT"
fi

if ! ip link show "$VETH_ROOT" >/dev/null 2>&1; then
    log "creating veth pair $VETH_ROOT <-> $VETH_NS"
    sudo -n ip link add "$VETH_ROOT" type veth peer name "$VETH_NS"
    sudo -n ip link set "$VETH_NS" netns "$NETNS"
    # NetworkManager takes a new ethernet device for its own, applies a wired profile (DHCP or a static
    # address) and removes the address set below, which leaves the AMF unable to bind $VETH_ROOT_ADDR.
    # Leave the host end to this script.
    if command -v nmcli >/dev/null 2>&1 && nmcli -t -f RUNNING general 2>/dev/null | grep -q '^running$'; then
        sudo -n nmcli device set "$VETH_ROOT" managed no || log "could not mark $VETH_ROOT unmanaged for NetworkManager"
    fi
else
    log "veth pair $VETH_ROOT already exists"
fi

sudo -n ip addr replace "$VETH_ROOT_ADDR/$VETH_PREFIX" dev "$VETH_ROOT"
if [[ "${AMF2:-0}" == 1 ]]; then
    # a second AMF listens on its own address, on the registered NGAP port (TS 38.412 refers to the IANA registry)
    sudo -n ip addr replace "$AMF2_NGAP_ADDR/$VETH_PREFIX" dev "$VETH_ROOT"
fi
sudo -n ip link set "$VETH_ROOT" up
sudo -n ip netns exec "$NETNS" ip addr replace "$VETH_NS_ADDR/$VETH_PREFIX" dev "$VETH_NS"
if [[ "${AMF2:-0}" == 1 ]]; then
    sudo -n ip netns exec "$NETNS" ip addr replace "$AMF2_NGAP_NS_ADDR/$VETH_PREFIX" dev "$VETH_NS"
fi
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
