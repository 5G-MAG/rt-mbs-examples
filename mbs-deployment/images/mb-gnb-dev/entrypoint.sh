#!/bin/bash

# gNB entrypoint

# source helper functions
source "helper_functions.sh"

# "${@}" contains the CMD provided by Docker. It should be the config file
template_filepath="${@}"
config_filepath="/etc/rt-srsRAN_Project/custom/mod_mb-gnb.yaml"

setup_config_file "${template_filepath}" "${config_filepath}"

if [[ "${ENABLE_GDB}" == "TRUE" ]]; then
    while :; do sleep 60; done
else
    /rt-srsRAN_Project/build/apps/gnb/gnb -c "${config_filepath}"
fi
