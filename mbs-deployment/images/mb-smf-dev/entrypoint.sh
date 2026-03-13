#!/bin/bash

# SMF entrypoint

# container entrypoint receiving arguments from Docker CMD
if [[ "${ENABLE_GDB}" == "TRUE" ]]; then
    while :; do sleep 60; done
else
    /open5gs/install/bin/open5gs-smfd "${@}"
fi
