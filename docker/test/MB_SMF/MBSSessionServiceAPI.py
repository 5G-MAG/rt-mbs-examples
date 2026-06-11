"""
License: 5G-MAG Public License (v1.0)
Author: Borja Iñesta Hernández
Copyright: (C) 2024 iTEAM UPV
For full license terms please see the LICENSE file distributed with this
program. If this file is missing then the license can be retrieved from
https://drive.google.com/file/d/1cinCiA778IErENZ3JN52VFW-1ffHpx7Z/view
"""

import unittest
import httpcore

from utils.config import config_from_file
from utils.logger import setup_logger
from utils.json_schema import json_validate
from utils.http2_prior_knowledge import setup_http2_pool

global config, logger
config = config_from_file("config.toml")
logger = setup_logger(__name__, config["DEFAULT"]["log_level"])
http2 = setup_http2_pool()

class MBSSessionCreateServiceOperation(unittest.TestCase):

    def test_create_mbs_session(self):
        api_resource_uri = "/post"

        # avoid the ugly output when tests are run in verbose mode
        print("\n")

        logger.info("test_create_mbs_session")

        url = "https://www.google.es"
        response = http2.request("GET", url)

        self.assertEqual(response.status, 200)
