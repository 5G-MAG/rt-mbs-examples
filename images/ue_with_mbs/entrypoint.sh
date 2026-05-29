#!/bin/bash

# UE entrypoint

# source helper functions
source "helper_functions.sh"

# "${@}" contains the CMD provided by Docker

# setup config file with the UE container IP address
ue_mod_config_file_path="$(setup_config_file "${@}")"

iptables -I INPUT -i eth0 -d 239.0.0.25/32 -j DROP # Needed to avoid receiving twice the video, for the srsUE and from outside
smcrouted # Start smcroutectl service

# TODO (borieher): Make it more flexible
srsue "${ue_mod_config_file_path}"

# For testing purposes
#while :; do sleep 60; done
