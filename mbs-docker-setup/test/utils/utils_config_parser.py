"""
License: 5G-MAG Public License (v1.0)
Author: Borja Iñesta Hernández
Copyright: (C) 2024 iTEAM UPV
For full license terms please see the LICENSE file distributed with this
program. If this file is missing then the license can be retrieved from
https://hub.5g-mag.com/Getting-Started/OFFICIAL_5G-MAG_Public_License_v1.0.pdf
"""

import configparser

class UtilsConfigParser(configparser.ConfigParser):
    """
    Patched ConfigParser class that removes double quotes from values
    """

    def get(self, section, option, *, raw=False, vars=None, fallback=configparser._UNSET):
        """Overriden get() method to remove the double quotes from values"""
        value = super().get(section, option, raw=raw, vars=vars, fallback=fallback)
        if value.startswith('"') and value.endswith('"'):
            value = value[1:-1]
        return value
