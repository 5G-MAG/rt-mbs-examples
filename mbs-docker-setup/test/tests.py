"""
License: 5G-MAG Public License (v1.0)
Author: Borja Iñesta Hernández
Copyright: (C) 2024 iTEAM UPV
For full license terms please see the LICENSE file distributed with this
program. If this file is missing then the license can be retrieved from
https://drive.google.com/file/d/1cinCiA778IErENZ3JN52VFW-1ffHpx7Z/view
"""

import unittest

import MB_SMF.TMGIServiceAPI as TMGIServiceAPI
import MB_SMF.MBSSessionServiceAPI as MBSSessionServiceAPI

# group tests in suites
tmgi_service = unittest.TestSuite()
tmgi_service.addTests(unittest.defaultTestLoader.loadTestsFromModule(TMGIServiceAPI))

# TODO (borieher): Currently the MBS Session tests are only a placeholder
mbs_session_service = unittest.TestSuite()
mbs_session_service.addTests(unittest.defaultTestLoader.loadTestsFromModule(MBSSessionServiceAPI))

if __name__ == "__main__":
    runner = unittest.TextTestRunner(verbosity=1)
    runner.run(tmgi_service)
    runner.run(mbs_session_service)
