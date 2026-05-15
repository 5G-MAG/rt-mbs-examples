#!/bin/bash

# UE entrypoint

# source helper functions
source "/helper_functions.sh"

template_filepath="/zmq_mux_demux.grc.template"
config_filepath="/zmq_mux_demux.grc"

setup_config_file "${template_filepath}" "${config_filepath}"

if [[ "${ENABLE_GDB}" == "TRUE" ]]; then
    while :; do sleep 60; done
else
    grcc "${config_filepath}"
    /zmq_mux_demux.py
fi
