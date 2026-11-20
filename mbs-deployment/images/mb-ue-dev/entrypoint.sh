#!/bin/bash

# UE entrypoint

# source helper functions
source "helper_functions.sh"

# "${@}" contains the CMD provided by Docker. It should be the config file
template_filepath="${@}"
config_filepath="/etc/srsRAN_4G/custom/mod_mb-ue.conf"

setup_config_file "${template_filepath}" "${config_filepath}"

#iptables -I INPUT -i eth0 -d 239.0.0.25/32 -j DROP
smcrouted

if [[ "${ENABLE_GDB}" == "TRUE" ]]; then
    while :; do sleep 60; done
else
    /srsRAN_4G/build/srsue/src/srsue "${config_filepath}"
fi
