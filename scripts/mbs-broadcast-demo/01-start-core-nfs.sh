#!/bin/bash
# Starts the 5G core network functions this demo needs, in the root network namespace,
# on loopback addresses (see env.sh). Generates their config files from this project's
# own working values -- not the stale placeholder paths in
# scripts/tmux/mbs-function-tutorial/mbs-function-tutorial.sh.
#
# Order: NRF first (everything else registers with it), then the NF cluster, then
# UPF/SMF/AMF last (SMF's pfcp client needs UPF up; AMF's ngap server needs $NETNS -- see
# 00-setup-netns.sh -- to already exist).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source env.sh
source lib.sh
ensure_dirs

require_file "$OPEN5GS_BUILD/src/nrf/open5gs-nrfd"
require_file "$OPEN5GS_BUILD/src/upf/open5gs-upfd"
netns_exists || die "run 00-setup-netns.sh first"

if ! systemctl is-active --quiet mongod; then
    log "mongod is not active, starting it"
    sudo -n true || die "passwordless sudo (or a cached sudo timestamp) is required"
    sudo -n systemctl start mongod || die "could not start mongod (needed by NRF/UDR)"
fi

gen_nf_yaml() {
    # gen_nf_yaml <name> <addr> [extra_yaml_lines...]
    local name="$1" addr="$2"
    cat > "$GEN_CONF_DIR/${name}.yaml"
}

gen_nf_yaml nrf "$NRF_ADDR" <<EOF
logger:
  file:
    path: $LOG_DIR/nrf.log
  level: info
global:
db_uri: mongodb://127.0.0.1/open5gs
nrf:
  sbi:
    server:
      - address: $NRF_ADDR
        port: $SBI_PORT
EOF

for pair in "ausf:$AUSF_ADDR" "udm:$UDM_ADDR" "pcf:$PCF_ADDR" "nssf:$NSSF_ADDR" "bsf:$BSF_ADDR" "udr:$UDR_ADDR"; do
    nf="${pair%%:*}"; addr="${pair##*:}"
    extra=""
    if [[ "$nf" == "udm" ]]; then
        extra="  hnet:
    - id: 1
      scheme: 1
      key: $OPEN5GS_BUILD/configs/open5gs/hnet/curve25519-1.key
    - id: 2
      scheme: 2
      key: $OPEN5GS_BUILD/configs/open5gs/hnet/secp256r1-2.key
"
    fi
    if [[ "$nf" == "nssf" ]]; then
        extra_nsi="      nsi:
        - uri: http://$NRF_ADDR:$SBI_PORT
          s_nssai:
            sst: 1
            sd: 1
"
    else
        extra_nsi=""
    fi
    cat > "$GEN_CONF_DIR/${nf}.yaml" <<EOF
logger:
  file:
    path: $LOG_DIR/${nf}.log
  level: info
global:
db_uri: mongodb://127.0.0.1/open5gs
${nf}:
${extra}  sbi:
    server:
      - address: $addr
        port: $SBI_PORT
    client:
      nrf:
        - uri: http://$NRF_ADDR:$SBI_PORT
${extra_nsi}
EOF
done

cat > "$GEN_CONF_DIR/amf.yaml" <<EOF
logger:
  file:
    path: $LOG_DIR/amf.log
  level: debug
global:
amf:
  sbi:
    server:
      - address: $AMF_ADDR
        port: $SBI_PORT
    client:
      nrf:
        - uri: http://$NRF_ADDR:$SBI_PORT
  ngap:
    server:
      - address: $VETH_ROOT_ADDR
  guami:
    - plmn_id:
        mcc: $PLMN_MCC
        mnc: $PLMN_MNC
      amf_id:
        region: 2
        set: 1
  tai:
    - plmn_id:
        mcc: $PLMN_MCC
        mnc: $PLMN_MNC
      tac: $TAC
  plmn_support:
    - plmn_id:
        mcc: $PLMN_MCC
        mnc: $PLMN_MNC
      s_nssai:
        - sst: 1
          sd: 1
  security:
      integrity_order : [ NIA2, NIA1, NIA0 ]
      ciphering_order : [ NEA0, NEA1, NEA2 ]
  network_name:
    full: 5G-MAG MBS
  amf_name: 5g-mag-amf-with-mbs-0
  time:
    t3512:
      value: 540
EOF

cat > "$GEN_CONF_DIR/smf.yaml" <<EOF
logger:
  file:
    path: $LOG_DIR/smf.log
  level: info
global:
db_uri: mongodb://127.0.0.1/open5gs
smf:
  sbi:
    server:
      - address: $SMF_ADDR
        port: $SBI_PORT
    client:
      nrf:
        - uri: http://$NRF_ADDR:$SBI_PORT
  pfcp:
    server:
      - address: $SMF_ADDR
    client:
      upf:
        - address: $UPF_ADDR
  gtpc:
    server:
      - address: $SMF_ADDR
  gtpu:
    server:
      - address: $SMF_ADDR
  session:
    - subnet: 10.45.0.0/16
      gateway: 10.45.0.1
  dns:
    - 8.8.8.8
    - 8.8.4.4
  mtu: 1400
  info:
    - s_nssai:
        - sst: 1
          sd: 1
          dnn:
            - internet
      tai:
        - plmn_id:
            mcc: $PLMN_MCC
            mnc: $PLMN_MNC
          tac: $TAC
EOF

cat > "$GEN_CONF_DIR/upf.yaml" <<EOF
logger:
  file:
    path: $LOG_DIR/upf.log
  level: info
global:
upf:
  pfcp:
    server:
      - address: $UPF_ADDR
  gtpu:
    server:
      - address: $VETH_ROOT_ADDR
  session:
    - subnet: 10.45.0.0/16
      gateway: 10.45.0.1
  mbs:
    udptunnel:
      address: $VETH_ROOT_ADDR
      port: 0
    multicast_router:
      activate: true
      input_interface: lo
      output_interface: ogstun
EOF

log "starting NRF"
run_bg "NRF" nrf "$OPEN5GS_BUILD/src/nrf/open5gs-nrfd" -c "$GEN_CONF_DIR/nrf.yaml"
cd "$OPEN5GS_BUILD"
wait_for_tcp "$NRF_ADDR" "$SBI_PORT" 15 || die "NRF did not come up"

for nf in ausf udm udr pcf nssf bsf; do
    run_bg "${nf^^}" "$nf" "$OPEN5GS_BUILD/src/$nf/open5gs-${nf}d" -c "$GEN_CONF_DIR/${nf}.yaml"
done
sleep 2

log "starting UPF (needs root for its TUN device)"
sudo -n true || die "passwordless sudo (or a cached sudo timestamp) is required"
sudo -n bash -c "cd '$OPEN5GS_BUILD' && nohup ./src/upf/open5gs-upfd -c '$GEN_CONF_DIR/upf.yaml' >'$LOG_DIR/upf.log' 2>&1 & echo \$! > '$PID_DIR/upf.pid'; disown"
sleep 1

run_bg "SMF" smf "$OPEN5GS_BUILD/src/smf/open5gs-smfd" -c "$GEN_CONF_DIR/smf.yaml"
sleep 1
run_bg "AMF" amf "$OPEN5GS_BUILD/src/amf/open5gs-amfd" -c "$GEN_CONF_DIR/amf.yaml"

wait_for_tcp "$SMF_ADDR" "$SBI_PORT" 15 || die "SMF did not come up"
wait_for_tcp "$AMF_ADDR" "$SBI_PORT" 15 || die "AMF did not come up"

log "core NFs up: NRF/AUSF/UDM/UDR/PCF/NSSF/BSF/SMF/AMF/UPF"
