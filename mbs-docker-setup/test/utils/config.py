"""
License: 5G-MAG Public License (v1.0)
Author: Borja Iñesta Hernández
Copyright: (C) 2024 iTEAM UPV
For full license terms please see the LICENSE file distributed with this
program. If this file is missing then the license can be retrieved from
https://hub.5g-mag.com/Getting-Started/OFFICIAL_5G-MAG_Public_License_v1.0.pdf
"""

from utils.utils_config_parser import UtilsConfigParser

def config_from_file(file_path):
    config = UtilsConfigParser()
    config.read(file_path)
    return config
