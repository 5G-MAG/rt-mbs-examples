#!/bin/bash

# Helper functions for gNB entrypoint

# receives the Docker CMD and returns the config file path
# get_config_file_path_from_docker_cmd <docker_cmd>
function get_config_file_path_from_docker_cmd(){
    docker_cmd="${@}"

    # parse only the -c option of the Docker CMD
    arguments=($(getopt --quiet --options c: -- ${docker_cmd}))

    # if -c is present grab argument, if not default to /etc/rt-srsRAN_Project/default/gnb_rf_b200_tdd_n78_20mhz.yml
    if [[ "${arguments[0]}" != "--" ]]; then
        # remove single quotes from config file path
        config_file_path="${arguments[1]//\'/}"
    else
        # fallback to default path
        config_file_path="/etc/rt-srsRAN_Project/default/gnb_rf_b200_tdd_n78_20mhz.yml"
    fi

    printf "${config_file_path}"
}

# receives the Docker CMD and setups the configuration file
# setup_config_file <docker_cmd>
function setup_config_file(){
    # grab the gNB container IP address, wait for container to be ready
    while [ -z "${gnb_ip_addr}" ]; do
        gnb_ip_addr=$(dig +short "${GNB_FQDN}")
        sleep 0.2
    done

    # grab the UE1 container IP address, wait for container to be ready
    while [ -z "${ue1_ip_addr}" ]; do
        ue1_ip_addr=$(dig +short "${UE1_FQDN}")
        sleep 0.2
    done

    # grab the UE2 container IP address, wait for container to be ready
    while [ -z "${ue2_ip_addr}" ]; do
        ue2_ip_addr=$(dig +short "${UE2_FQDN}")
        sleep 0.2
    done

    while [ -z "${gnuradio_ip_addr}" ]; do
        gnuradio_ip_addr=$(dig +short "${GNURADIO_FQDN}")
        sleep 0.2
    done

    # docker_cmd is "${@}"
    gnb_config_file_path="$(get_config_file_path_from_docker_cmd "${@}")"

    gnb_mod_config_file_path="/etc/rt-srsRAN_Project/custom/mod_mb-gnb.yaml"

    cp "${gnb_config_file_path}" "${gnb_mod_config_file_path}"

    # substitutes the gNB_IP in the config file with the gNB container IP address
    sed -i "s/gNB_IP/${gnb_ip_addr}/g" "${gnb_mod_config_file_path}"

    # substitutes the UE1_IP in the config file with the UE container IP address
    sed -i "s/UE1_IP/${ue1_ip_addr}/g" "${gnb_mod_config_file_path}"

    # substitutes the UE2_IP in the config file with the UE container IP address
    sed -i "s/UE2_IP/${ue2_ip_addr}/g" "${gnb_mod_config_file_path}"

    # substitutes the UE_IP in the config file with the UE container IP address
    sed -i "s/GNURADIO_IP/${gnuradio_ip_addr}/g" "${gnb_mod_config_file_path}"

    printf "${gnb_mod_config_file_path}"
}
