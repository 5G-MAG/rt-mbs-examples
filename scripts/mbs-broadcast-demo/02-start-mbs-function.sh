#!/bin/bash
# Starts MBSTF (rt-mbs-transport-function) then MBSF (rt-mbs-function), in that order --
# MBSF's own Nmb8 client needs MBSTF's distSessionAPI already registered with the NRF.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source env.sh
source lib.sh
ensure_dirs

require_file "$MBSTF_BUILD/src/mbstf/open5gs-mbstfd"
require_file "$MBSF_BUILD/src/mbsf/open5gs-mbsfd"
wait_for_tcp "$NRF_ADDR" "$SBI_PORT" 5 || die "NRF is not up yet -- run 01-start-core-nfs.sh first"

cat > "$GEN_CONF_DIR/mbstf.yaml" <<EOF
logger:
  level: debug

global:

sbi:
  server:
    no_tls: true
  client:
    no_tls: true

mbstf:
    sbi:
      - addr: $MBSTF_SBI_ADDR
        port: $SBI_PORT
    distSessionAPI:
      - addr: $MBSTF_DISTSESSION_ADDR
        port: $SBI_PORT
    rtpIngest:
      - addr: $MBSTF_INGEST_ADDR
        port: 0
    httpPushIngest:
      - addr: $MBSTF_INGEST_ADDR
        port: 0
    totalMaxBitRateSoftLimit: 1000
    consecutiveIngestFailuresBeforeDeactivate: 5
    packetModeSchedulingQueueSize: 131072
    serverResponseCacheControl:
      - distMaxAge: 60
        ObjectMaxAge: 60

nrf:
    sbi:
      - addr:
          - $NRF_ADDR
        port: $SBI_PORT
EOF

cat > "$GEN_CONF_DIR/mbsf.yaml" <<EOF
logger:
  file:
    path: $LOG_DIR/mbsf.log
  level: debug

global:
  max:
    ue: 128

mbsf:
  sbi:
    server:
      - address: $MBSF_ADDR
        port: $SBI_PORT
    client:
      nrf:
        - uri: http://$NRF_ADDR:$SBI_PORT

  mbsUserServices:
    - addr: $MBSF_ADDR
      port: $SBI_PORT

  mbsUserDataIngestSession:
    - addr: $MBSF_ADDR
      port: $SBI_PORT

  serverResponseCacheControl:
    - defaultMaxAge: 60
      mbsUserServiceMaxAge: 60
      mbsUserDataIngestSessionMaxAge: 60

  userServiceAnnouncement:
    # How often the User Service Announcement Channel repeats its bundle, in milliseconds. This is
    # the per-object repetitionInterval of the announcement channel's own object manifest
    # (TS 26.517 clause 6.1.2, and clause 5.3.1A for why that channel is a carousel at all), which
    # the MBSF authors itself.
    #
    # 10 s is enough for a receiver to acquire the bundle over the radio path. A shorter interval
    # was tried while the announcement session was being starved of PDCCH candidates by a
    # continuously-loaded content session, on the theory that repeating more often would compensate;
    # it did not, because the constraint was the scheduling order rather than the offered rate.
    # With that fixed in the gNB scheduler the announcement drains normally and this can stay where
    # it was. Overridable if a deployment wants faster acquisition.
    announcementRepetitionTime: ${ANNOUNCEMENT_REPETITION_MS:-10000}
    ssmPort: 3000
    ssmSourceAddress: $MBSF_ADDR
    ssmDestinationAddress: 232.0.0.1
    # mbr governs this carousel's own real on-air pacing (same effect as the content
    # Distribution Session's own maxContBitRate, see env.sh's own INGEST_MAX_BITRATE
    # comment) -- the announcement bundle only needs a few hundred bps even at this
    # repetition rate, so 10 Mbps here was just an oversized, effectively-unlimited
    # ceiling. Found live: with no real pacing, the announcement's two ALC packets went
    # out ~1-2ms apart (confirmed via MBSTF's own "sending TOI" debug log), too tight
    # for the gNB's RLC/scheduler to reliably service both -- the same real-time-headroom
    # issue already found and fixed for content at 500 Kbps, just never applied here.
    mbr: 500 Kbps
    docRoot: $MBSF_CACHE_DIR

  broadcastDistribution:
    sourceAddress: $BCAST_SSM_SOURCE
    destinationAddress: $BCAST_SSM_DEST

  activeDistributionSessionsSoftLimit: 1000
  activeUserServicesSoftLimit: 50
  actPeriodGoToEstablishedState: 60

mbsaf:
  server:
    - addr: $MBSAF_ADDR
      port: 8888
    # Second listener on the root-namespace end of the veth pair. This server carries the
    # User Service Description retrieval API -- TS 26.517 V18.6.0 clause 9.2.2: "The User
    # Service Description retrieval API is accessible from the MBS AF at reference point MBS5
    # and from the MBSTF Client at reference point MBS7' through the following URL base path:"
    # -- and MBS5 is a unicast reference point the MBS Client reaches over its PDU session.
    # \$MBSAF_ADDR is a 127.0.0.0/8 address: fine for the other core NFs, which share the root
    # namespace, but from the UE's namespace 127/8 is that namespace's own loopback, so the
    # MBS5 half of TS 26.502 V18.6.0 clause 4.5.31's Service announcement modes was
    # unreachable. The real MBS AF serves the real API on both addresses; nothing is proxied.
    - addr: $VETH_ROOT_ADDR
      port: 8888
EOF

log "starting MBSTF"
run_bg "MBSTF" mbstf "$MBSTF_BUILD/src/mbstf/open5gs-mbstfd" -c "$GEN_CONF_DIR/mbstf.yaml"
wait_for_tcp "$MBSTF_SBI_ADDR" "$SBI_PORT" 15 || die "MBSTF did not come up"

log "starting MBSF"
run_bg "MBSF" mbsf "$MBSF_BUILD/src/mbsf/open5gs-mbsfd" -c "$GEN_CONF_DIR/mbsf.yaml"
wait_for_tcp "$MBSF_ADDR" "$SBI_PORT" 15 || die "MBSF did not come up"

log "MBSTF/MBSF up"
