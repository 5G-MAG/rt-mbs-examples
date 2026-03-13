#!/bin/bash

# receives the Docker CMD and setups the configuration file
# setup_config_file <docker_cmd>
function setup_config_file(){
    template_filepath="${1}"
    config_filepath="${2}"

    # global variables ending in _IP present in the config file
    variables_to_substitute=$(envsubst --variables "$(cat ${template_filepath})" | grep '_IP$')

    # each variable should be <prefix>_IP
    for variable in $variables_to_substitute; do 
        prefix=$(echo "${variable}" | awk -F'_' '{print $1}')
        prefix_ACTUAL_IP="${prefix}_ACTUAL_IP" #here we save the actual ip string (e.g. 1.2.3.4)
        prefix_FQDN="${prefix}_FQDN"

        declare "${prefix_ACTUAL_IP}="
        while [ -z "${!prefix_ACTUAL_IP}" ]; do
            declare "${prefix_ACTUAL_IP}=$(dig +short ${!prefix_FQDN})"
            sleep 0.2
        done

        # export the variable so it expands to the actual IP
        export "${variable}"="${!prefix_ACTUAL_IP}"
    done


    cat "${template_filepath}" | envsubst > "${config_filepath}"
}
