#!/bin/bash
#
# License: 5G-MAG Public License (v1.0)
# Authors: Borja Inesta Hernandez (iTEAM-UPV), Jaime Sanchez Roldan (iTEAM-UPV), Josep Ribes Rodriguez-Moldes (iTEAM-UPV), Jordi Joan Gimenez (5G-MAG)
# Copyright: (C) 2026 iTEAM - Universitat Politecnica de Valencia, 5G-MAG Association
#
# For full license terms please see the LICENSE file distributed with this
# program. If this file is missing then the license can be retrieved from
# https://hub.5g-mag.com/Getting-Started/OFFICIAL_5G-MAG_Public_License_v1.0.pdf
#

# Helper functions for UE entrypoint

# receives the Docker CMD and setups the configuration file
# setup_config_file <docker_cmd>
function setup_config_file(){
    # grab the UE container IP address, wait for container to be ready
    while [ -z "${ue_ip_addr}" ]; do
        ue_ip_addr=$(dig +short "${UE_FQDN}")
        sleep 0.2
    done

    # grab the gNB container IP address, wait for container to be ready
    while [ -z "${gnb_ip_addr}" ]; do
        gnb_ip_addr=$(dig +short "${GNB_FQDN}")
        sleep 0.2
    done

    # docker_cmd is "${@}"
    ue_config_file_path="${@}"

    ue_mod_config_file_path="/etc/srsRAN_4G_mbs/custom/mod_ue_with_mbs.conf"

    cp "${ue_config_file_path}" "${ue_mod_config_file_path}"

    # substitutes the UE_IP in the config file with the UE container IP address
    sed -i "s/UE_IP/${ue_ip_addr}/g" "${ue_mod_config_file_path}"

    # substitutes the gNB_IP in the config file with the gNB container IP address
    sed -i "s/gNB_IP/${gnb_ip_addr}/g" "${ue_mod_config_file_path}"

    printf "${ue_mod_config_file_path}"
}
