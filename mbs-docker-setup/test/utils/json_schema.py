"""
License: 5G-MAG Public License (v1.0)
Author: Borja Iñesta Hernández
Copyright: (C) 2024 iTEAM UPV
For full license terms please see the LICENSE file distributed with this
program. If this file is missing then the license can be retrieved from
https://drive.google.com/file/d/1cinCiA778IErENZ3JN52VFW-1ffHpx7Z/view
"""

import json
from jsonschema import validate
import jsonschema

def json_validate(json_data, json_schema_path):
    # JSON data is received but JSON schema is a file read from path
    with open(json_schema_path) as json_schema:
        schema = json.load(json_schema)

    try:
        validate(instance=json_data, schema=schema)
    except jsonschema.exceptions.ValidationError as error:
        # JSON is not valid
        return { "result": "error", "message": error.message }
    # JSON is valid
    return { "result": "success", "message": "JSON is valid" }
