#!/bin/bash
#
# License: 5G-MAG Public License (v1.0)
# Authors: Borja Inesta Hernandez (iTEAM-UPV), Jaime Sanchez Roldan (iTEAM-UPV), Josep Ribes Rodriguez-Moldes (iTEAM-UPV), Jordi Joan Gimenez (5G-MAG)
# Copyright: (C) 2026 iTEAM - Universitat Politecnica de Valencia, 5G-MAG Association
#
# For full license terms please see the LICENSE file distributed with this
# program. If this file is missing then the license can be retrieved from
# https://hub.5g-mag.com/Getting-Started/OFFICIAL_5G-MAG_Public_License_v1.0.pdf
#

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
