"""
License: 5G-MAG Public License (v1.0)
Author: Borja Iñesta Hernández
Copyright: (C) 2024 iTEAM UPV
For full license terms please see the LICENSE file distributed with this
program. If this file is missing then the license can be retrieved from
https://drive.google.com/file/d/1cinCiA778IErENZ3JN52VFW-1ffHpx7Z/view
"""

import logging

def setup_logger(name, log_level):
    logger = logging.getLogger(name)
    level = logging.getLevelName(log_level)
    logger.setLevel(level)

    # log to console output
    ch = logging.StreamHandler()
    ch.setLevel(level)

    # use the format: [INFO] tests - message
    formatter = logging.Formatter("[%(levelname)s] %(name)s - %(message)s")
    ch.setFormatter(formatter)

    logger.addHandler(ch)
    return logger
