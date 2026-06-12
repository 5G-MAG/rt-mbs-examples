#!/bin/bash

# gNB entrypoint

# source helper functions
source "helper_functions.sh"

# "${@}" contains the CMD provided by Docker

# setup config file with the gNB container IP address
gnb_mod_config_file_path="$(setup_config_file "${@}")"

# TODO (borieher): Make it more flexible
gnb -c "${gnb_mod_config_file_path}"

# For testing purposes
#while :; do sleep 60; done
