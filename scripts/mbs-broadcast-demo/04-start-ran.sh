#!/bin/bash
# Starts the gNB (srsRAN_Project_mbs) and UE (srsRAN_4G_mbs) inside $NETNS, connected over
# a ZMQ RF loopback (no SDR hardware needed). Both must run inside $NETNS so the gNB's NGU
# socket and the UE's PDU-session TUN device (tun_bcastue) share that namespace's routing
# table, isolated from the host's.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source env.sh
source lib.sh

# RAN parameters written by rt-mbs-application-provider's RAN tab, if it has been used. Sourced
# before the defaults below so anything it sets wins over them, and anything already exported in the
# environment still wins over both: an operator running this script by hand with an explicit value
# should not have it silently overridden by a file the portal wrote earlier. Absent, everything falls
# back to the defaults here exactly as before.
RAN_PARAMS_FILE="${RAN_PARAMS_FILE:-$DEMO_ROOT/../../../rt-mbs-application-provider/ran-params.env}"
if [[ -f "$RAN_PARAMS_FILE" ]]; then
    log "applying RAN parameters from $RAN_PARAMS_FILE"
    while IFS='=' read -r k v; do
        [[ "$k" =~ ^[A-Z_][A-Z0-9_]*$ ]] || continue
        # Only set what the environment does not already carry, so an explicit value on the command
        # line still governs.
        [[ -n "${!k:-}" ]] || export "$k=$v"
    done < "$RAN_PARAMS_FILE"
fi

# Cell bandwidth, and the sample rate and PRB count that must agree with it. These are one set:
# changing the bandwidth without the other two produces a gNB that will not start.
#
# The ZMQ RF driver carries every I/Q sample over TCP, so the sample rate decides whether this rig
# can run the radio in real time at all. At 23.04 Msps (20 MHz) it does not: measured on the UE's
# own subframe counter, the pair advanced 128 subframes per second against 1000, about 13% of real
# time, and freeing three cores of CPU changed nothing. Everything the radio carries is scaled down
# by that factor, which is why a 464 kbps source could not get through a 20 MHz cell.
#
# 10 MHz halves the sample stream. Fewer PRBs is a smaller cell, but a cell that runs closer to
# real time delivers more than a wider one running at a fraction of it.
CELL_BW_MHZ="${CELL_BW_MHZ:-10}"
CELL_SRATE_MHZ="${CELL_SRATE_MHZ:-11.52}"

# Periodic CSI reporting on the unicast link, off by default: see the csi: block below for why it
# destroys broadcast reception on this UE. true restores the gNB's stock behaviour.
CELL_CSI_ENABLED="${CELL_CSI_ENABLED:-false}"
if [ "$CELL_CSI_ENABLED" = "true" ]; then CELL_CSI_RESOURCES=1; else CELL_CSI_RESOURCES=0; fi

# MCS index for MBS broadcast PDSCH: see the mbs: fixed_mcs_index entry below for what governs it.
CELL_MBS_MCS_INDEX="${CELL_MBS_MCS_INDEX:-20}"
CELL_NOF_PRB="${CELL_NOF_PRB:-52}"
# CORESET#0 belongs to the same set: its index selects a CORESET#0 width from TS 38.213's own
# tables, and that width has to fit inside the carrier. Index 12 gives 96 PRBs, which fits a
# 106-PRB (20 MHz) carrier but not a 52-PRB (10 MHz) one, where the gNB refuses to start with
# "Unable to derive a valid SSB pointA and k_SSB". Index 6 gives 48 PRBs, which fits.
CELL_CORESET0_IDX="${CELL_CORESET0_IDX:-6}"
ensure_dirs

require_file "$GNB_BIN"
require_file "$UE_BIN"
netns_exists || die "run 00-setup-netns.sh first"
wait_for_tcp "$AMF_ADDR" "$SBI_PORT" 5 || die "AMF is not up yet -- run 01-start-core-nfs.sh first"
sudo -n true || die "passwordless sudo (or a cached sudo timestamp) is required"

# Optional mbs: parameters. Each is emitted only when it actually has a value: the gNB treats an
# absent key as "use my own default", but an empty one is a parse error, so writing the key
# unconditionally would turn "unset" into a failure to start.
MBS_OPTIONAL_LINES=""
mbs_opt() {  # mbs_opt <yaml key> <value>
    [[ -n "${2:-}" ]] && MBS_OPTIONAL_LINES+="  $1: $2"$'\n'
    return 0
}
mbs_opt window_duration "${MCCH_WINDOW_DURATION:-}"
mbs_opt bcast_session_mrb_lcid "${BCAST_SESSION_MRB_LCID:-}"
mbs_opt intra_fsai "${MBS_INTRA_FSAI:-}"
mbs_opt max_pdcch_alloc_attempts_per_slot "${MBS_MAX_PDCCH_ATTEMPTS_PER_SLOT:-}"
mbs_opt max_crbs_reserved_for_mcch_per_slot "${MBS_MAX_CRBS_RESERVED_FOR_MCCH:-}"

cat > "$GEN_CONF_DIR/gnb_bcast.yaml" <<EOF
gnb_id: 1

cu_cp:
  amf:
    addr: $VETH_ROOT_ADDR
    port: 38412
    bind_addr: $VETH_NS_ADDR
    supported_tracking_areas:
      - tac: $TAC
        plmn_list:
          - plmn: "${PLMN_MCC}${PLMN_MNC}"
            tai_slice_support_list:
              - sst: 1
                sd: 1
  inactivity_timer: 7200

cu_up:
  ngu:
    socket:
      - bind_addr: $VETH_NS_ADDR

cell_cfg:
  sib:
    si_sched_info:
      - si_period: 32
        sib_mapping: 20
  dl_arfcn: 368500
  band: 3
  channel_bandwidth_MHz: ${CELL_BW_MHZ}
  common_scs: 15
  plmn: "${PLMN_MCC}${PLMN_MNC}"
  tac: $TAC
  pci: 1
  slicing:
    - sst: 1
      sd: 1
  pdcch:
    common:
      ss0_index: 0
      coreset0_index: ${CELL_CORESET0_IDX}
    dedicated:
      ss2_type: common
      dci_format_0_1_and_1_1: false
  prach:
    prach_config_index: 1
  pdsch:
    mcs_table: qam64
  pusch:
    mcs_table: qam64
  # Periodic CSI reporting makes the UE transmit PUCCH format 2 on a fixed cadence. This UE loses its
  # own MBS PDSCH reception in any slot it transmits in: measured over one run, broadcast blocks in a
  # slot carrying a periodic PUCCH failed 6795 times out of 6795, against 1 failure in 127513 blocks
  # in every other slot. Broadcast has no HARQ retransmission (TS 38.212 clause 7.3.1.5.1 gives DCI
  # format 4_0 no HARQ process number and no new data indicator), so each of those blocks is lost
  # outright and any object spanning one is unrecoverable.
  #
  # A receiver of a broadcast service reports no channel state: there is no link being adapted to it.
  # Disabling it here removes the transmissions rather than working around their effect. Set
  # CELL_CSI_ENABLED=true to restore the stock behaviour; nof_cell_csi_resources must be 0 whenever it
  # is false, which the gNB's own config validator enforces.
  csi:
    csi_rs_enabled: ${CELL_CSI_ENABLED}
  pucch:
    # The gNB's own config validator requires this to be 0 when csi_rs_enabled is false and non-zero
    # when it is true, so it is derived from the same setting rather than set independently.
    f2_or_f3_or_f4_nof_cell_res_csi: ${CELL_CSI_RESOURCES}

ru_sdr:
  device_driver: zmq
  device_args: tx_port=tcp://127.0.0.1:2100,rx_port=tcp://127.0.0.1:2101,base_srate=${CELL_SRATE_MHZ}e6
  srate: ${CELL_SRATE_MHZ}
  tx_gain: 75
  rx_gain: 75

# The gNB's own remote control server. Off in the stock configuration; needed for the provider's RAN
# tab to change anything while the gNB is running, rather than only writing what it will read next
# time it starts. Bound to loopback inside the namespace, so nothing outside it can reach the control
# surface.
remote_control:
  enabled: ${GNB_REMOTE_CONTROL_ENABLED:-true}
  bind_addr: 127.0.0.1
  port: ${GNB_REMOTE_CONTROL_PORT:-8001}

expert_execution:
  threads:
    non_rt:
      nof_non_rt_threads: 2

mbs:
  # The MCCH content is left entirely to the sessions live NGAP/F1AP Broadcast Session Setup
  # establishes, which is what this demo actually provisions: one Distribution Session for the
  # User Service Announcement Channel and one for the media.
  #
  # 0 disables the config-provisioned MCCH entry (the CLI's own documented meaning of 0). It is
  # off because a static entry and a dynamic session collide: both take a G-RNTI from the same
  # space, so MCCH ends up advertising two MBS-SessionInfo-r17 entries carrying the SAME g-RNTI,
  # which the UE cannot disambiguate. Observed with the static entry enabled: MCCH advertised
  # three sessions, two of them on 0xCACA, and the gNB then scheduled only one of the two real
  # sessions -- 4580 transmissions on one G-RNTI against 5 on the other, all of those from setup.
  # The announcement channel was the starved one, so the client never discovered the service.
  #
  # Keeping it off also removes a maintenance trap: bcast_session_tmgi_service_id below had to be
  # edited to match whatever TMGI the MB-SMF happened to allocate on the last provisioning run,
  # and the gNB restarted, or MCCH advertised a session with the wrong TMGI. Nothing needs to
  # track a live-allocated TMGI when every session comes from live signalling.
  #
  # Set BCAST_SESSION_G_RNTI to a non-zero value to re-enable the static entry, and then keep
  # BCAST_TMGI_SERVICE_ID in step with the TMGI actually allocated that run.
  bcast_session_tmgi_service_id: ${BCAST_TMGI_SERVICE_ID:-7972906}
  bcast_session_g_rnti: ${BCAST_SESSION_G_RNTI:-0}

  # MCCH scheduling (MCCH-Config-r17). Defaults match the gNB's own, so an untouched config behaves
  # exactly as before; they are named here so the provider's RAN tab has somewhere to write them.
  repetition_period: ${MCCH_REPETITION_PERIOD:-1}
  repetition_offset: ${MCCH_REPETITION_OFFSET:-0}
  window_start_slot: ${MCCH_WINDOW_START_SLOT:-0}
  mcch_modification_period: ${MCCH_MODIFICATION_PERIOD:-2}
${MBS_OPTIONAL_LINES}

  # Broadcast carries no channel-state feedback (DCI format 4_0 has no HARQ process number and no
  # PDSCH-to-HARQ_feedback timing indicator, TS 38.212 V17.13.0 clause 7.3.1.5.1), so the gNB has nothing
  # to adapt this to and it is an operator choice: a lower index reaches further and carries less. It is an
  # index into the table mcs-Table in pdsch-ConfigMTCH selects (TS 38.214 V17.5.0 clause 5.1.3.1); qam64 is
  # the default table, giving 0..28.
  #
  # This rig is a ZMQ loopback with no radio channel between the two ends, so nothing here is limited by
  # propagation and no coverage margin is being bought by a low index. The value is set high enough that the
  # transport block carries the demo's content rather than being the bottleneck; a deployment over real
  # radio must choose its own from its own coverage target, which is why this is a variable and not a
  # constant in the scheduler.
  fixed_mcs_index: ${CELL_MBS_MCS_INDEX}

log:
  filename: $LOG_DIR/gnb.log
  all_level: ${GNB_LOG_LEVEL:-info}
  # The MBS scheduler explains its per-session decisions at debug level (which session it skipped
  # and why), and those are the only record of a session being suppressed rather than starved. The
  # scheduler shares its logger level with the MAC ("MAC" and "SCHED" are registered together), so
  # this is the key that reaches it. Settable so it can be captured without editing this file.
  mac_level: ${GNB_SCHED_LOG_LEVEL:-info}
  rlc_level: ${GNB_RLC_LOG_LEVEL:-info}
  phy_level: warning
  gtpu_level: warning
  pdcp_level: info
  rrc_level: info
  cu_level: info
  hex_max_size: 0

pcap:
  mac_enable: false
  ngap_enable: true
  ngap_filename: $LOG_DIR/gnb_ngap.pcap
EOF

cat > "$GEN_CONF_DIR/ue_bcast.conf" <<EOF
[rf]
freq_offset = 0
tx_gain = 50
rx_gain = 40
srate = ${CELL_SRATE_MHZ}e6
nof_antennas = 1

device_name = zmq
device_args = tx_port=tcp://127.0.0.1:2101,rx_port=tcp://127.0.0.1:2100,base_srate=${CELL_SRATE_MHZ}e6

[rat.eutra]
dl_earfcn = 2850
nof_carriers = 0

[rat.nr]
bands = 3
nof_carriers = 1
max_nof_prb = ${CELL_NOF_PRB}
nof_prb = ${CELL_NOF_PRB}

[pcap]
enable = none

[log]
all_level = info
phy_lib_level = none
all_hex_limit = 32
filename = $LOG_DIR/ue_bcast.log
file_max_size = -1

[usim]
mode = soft
algo = milenage
opc  = 00000000000000000000000000000000
k    = 00000000000000000000000000000000
imsi = 001011234567892
imei = 353490069873319

[rrc]
release = 15
ue_category = 4

[slicing]
enable = false
nssai-sst = 1
nssai-sd = 1

[nas]
apn = internet
apn_protocol = ipv4

[gw]
ip_devname = tun_bcastue
ip_netmask = 255.255.255.0

[gui]
enable = false

[general]
radio_api_enable = true
radio_api_port = $RADIO_API_PORT
EOF


log "starting gNB in $NETNS"
run_bg_netns "gNB" gnb "$GNB_BIN" -c "$GEN_CONF_DIR/gnb_bcast.yaml" $GNB_EXTRA_ARGS
sleep 3

# The gNB's remote-control socket binds loopback inside $NETNS, so nothing outside the namespace
# can reach it. This relay publishes it on the veth address, the same way the dashboard's own port
# is relayed in 05-start-client-and-app.sh, so the provider (which runs in the root namespace) can
# change MBS scheduler parameters on a running cell. The gNB itself stays bound to loopback.
if [ "${GNB_REMOTE_CONTROL_ENABLED:-true}" = "true" ]; then
    RC_PORT="${GNB_REMOTE_CONTROL_PORT:-8001}"
    log "starting socat relay: $VETH_NS_ADDR:$RC_PORT (in $NETNS) -> loopback:$RC_PORT (in $NETNS)"
    if ! pgrep -f "socat.*TCP-LISTEN:$RC_PORT,bind=$VETH_NS_ADDR" >/dev/null 2>&1; then
        sudo -n ip netns exec "$NETNS" bash -c \
            "nohup socat TCP-LISTEN:$RC_PORT,bind=$VETH_NS_ADDR,fork,reuseaddr TCP:127.0.0.1:$RC_PORT >'$LOG_DIR/socat-rc.log' 2>&1 & echo \$! > '$PID_DIR/socat-rc.pid'; disown"
    fi
fi

log "starting UE in $NETNS"
run_bg_netns_root "UE" ue "$UE_BIN" "$GEN_CONF_DIR/ue_bcast.conf"

log "gNB/UE started -- check $LOG_DIR/gnb.log and $LOG_DIR/ue_bcast.log for RRC_CONNECTED / PDU session establishment"
log "(the UE typically needs 10-30s to attach; 05-start-client-and-app.sh waits for its TUN interface)"
