#!/bin/bash

# Helper functions for UE entrypoint

# receives the Docker CMD and setups the configuration file
# setup_config_file <docker_cmd>
function setup_config_file(){
    # grab the UE container IP address, wait for container to be ready
    while [ -z "${ue1_ip_addr}" ]; do
        ue1_ip_addr=$(dig +short "${UE1_FQDN}")
        sleep 0.2
    done

    while [ -z "${ue2_ip_addr}" ]; do
        ue2_ip_addr=$(dig +short "${UE2_FQDN}")
        sleep 0.2
    done

    # grab the gNB container IP address, wait for container to be ready
    while [ -z "${gnb_ip_addr}" ]; do
        gnb_ip_addr=$(dig +short "${GNB_FQDN}")
        sleep 0.2
    done

    # grab the gNB container IP address, wait for container to be ready
    while [ -z "${gnuradio_ip_addr}" ]; do
        gnuradio_ip_addr=$(dig +short "${GNURADIO_FQDN}")
        sleep 0.2
    done

    # docker_cmd is "${@}"
    gnuradio_config_file_path="${@}"

    gnuradio_mod_config_file_path="/zmq_mux_demux.grc"

    cp "${gnuradio_config_file_path}" "${gnuradio_mod_config_file_path}"
    echo cp "${gnuradio_config_file_path}" "${gnuradio_mod_config_file_path}" > debug

    # substitutes the UE_IP in the config file with the UE container IP address
    sed -i "s/UE1_IP/${ue1_ip_addr}/g" "${gnuradio_mod_config_file_path}"

    # substitutes the UE_IP in the config file with the UE container IP address
    sed -i "s/UE2_IP/${ue2_ip_addr}/g" "${gnuradio_mod_config_file_path}"

    # substitutes the gNB_IP in the config file with the gNB container IP address
    sed -i "s/gNB_IP/${gnb_ip_addr}/g" "${gnuradio_mod_config_file_path}"

    # substitutes the gNB_IP in the config file with the gNB container IP address
    sed -i "s/GNURADIO_IP/${gnuradio_ip_addr}/g" "${gnuradio_mod_config_file_path}"

    printf "${gnuradio_mod_config_file_path}"
}
