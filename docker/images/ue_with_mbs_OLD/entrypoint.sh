#!/bin/bash

# UE entrypoint

# source helper functions
source "helper_functions.sh"

# "${@}" contains the CMD provided by Docker

# setup config file with the UE container IP address
ue_mod_config_file_path="$(setup_config_file "${@}")"

# TODO (borieher): Make it more flexible
srsue "${ue_mod_config_file_path}"

# For testing purposes
#while :; do sleep 60; done
