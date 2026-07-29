"""


License: 5G-MAG Public License (v1.0)
Author: Erik Gaida
Copyright: (C) 2026 Fraunhofer  FOKUS
For full license terms please see the LICENSE file distributed with this
program. If this file is missing then the license can be retrieved from
https://drive.google.com/file/d/1cinCiA778IErENZ3JN52VFW-1ffHpx7Z/view




this file is a an end-to-end CRUD test for the MBSF APIs and refers to the Tutorial:
https://hub.5g-mag.com/Getting-Started/pages/5g-multicast-broadcast-services/tutorials/mbsf.html

Requirements:
    pytest
    python3-pycurl

1. Start all needed NFs with: bash ~/rt-mbs-examples/scripts/tmux/mbs-function-tutorial.sh
2. Set the MBSF address, protocol, and port in config.toml under [mbsf]

Run:
    pytest -v -s ~/rt-mbs-examples/test/test_mbsf_crud.py
"""

from __future__ import annotations

import copy
import io
import json
from pathlib import Path
from types import SimpleNamespace
from typing import Any
from utils import config
from uuid import uuid4

import pycurl



CONFIG = config.config_from_file(Path(__file__).with_name("config.toml"))
MBSF_BASE_URL = (f"{CONFIG['mbsf']['protocol']}://{CONFIG['mbsf']['address']}:"f"{CONFIG['mbsf']['port']}")


USER_SERVICES_URL = f"{MBSF_BASE_URL}/nmbsf-mbs-us/v1/mbs-user-services"
INGEST_SESSIONS_URL = f"{MBSF_BASE_URL}/nmbsf-mbs-ud-ingest/v1/sessions"

# https://github.com/5G-MAG/Getting-Started/blob/535f72ad57383bb0cbb17528f9c4572ce4756d0a/pages/5g-multicast-broadcast-services/tutorials/mbsf.md?plain=1#L165-L178
USER_SERVICE_JSON = {
  "extServiceIds": ["https://example.broadcaster.com/services/first-service"],
  "servType": "MULTICAST",
  "servClass": "urn:oma:bcast:oma_bsc:st:1.0",
  "servAnnModes": ["VIA_MBS_5", "VIA_MBS_DISTRIBUTION_SESSION", "PASSED_BACK"],
  "servNameDescs": [
    {
      "servName": "First Service",
      "servDescrip": "The first service, operated by Example Broadcaster, is our general entertainment channel",
      "language": "eng"
    }
  ],
  "mainServLang": "eng"
}
# ~/rt-mbs-function/tests/json/obj_distr_info.json
STREAMING_INGEST_JSON = {
    "mbsUserServId": "",
    "mbsDisSessInfos": {
        "AP_MBS_SESSION_1": {
            "mbsSessionId": {
                "ssm": {
                    "sourceIpAddr": {"ipv4Addr": "127.0.0.5"},
                    "destIpAddr": {"ipv4Addr": "232.10.0.5"},
                }
            },
            "mbsDistSessState": "INACTIVE",
            "maxContBitRate": "10 Mbps",
            "distrMethod": "OBJECT",
            "objDistrInfo": {
                "operatingMode": "STREAMING",
                "objAcqMethod": "PULL",
                "objAcqIds": ["stream.mpd"],
                "objIngUri": (
                    "https://livesim2.dashif.org/livesim2/WAVE/"
                    "vectors/cfhd_sets/12.5_25_50/t1/2022-10-17/"
                ),
            },
        }
    },
}

def _request(
    method: str,
    url: str,
    payload: dict[str, Any] | None = None,
) -> SimpleNamespace:
    body = io.BytesIO()
    headers: dict[str, str] = {}

    def receive_header(raw_line: bytes) -> int:
        line = raw_line.decode("iso-8859-1").strip()
        if line.startswith("HTTP/"):
            headers.clear()
        elif ":" in line:
            name, value = line.split(":", 1)
            headers[name.strip().lower()] = value.strip()
        return len(raw_line)

    curl = pycurl.Curl()
    try:
        curl.setopt(pycurl.URL, url)
        curl.setopt(pycurl.CUSTOMREQUEST, method)
        curl.setopt(pycurl.HTTP_VERSION, pycurl.CURL_HTTP_VERSION_2_PRIOR_KNOWLEDGE)
        curl.setopt(pycurl.WRITEDATA, body)
        curl.setopt(pycurl.HEADERFUNCTION, receive_header)

        if payload is not None:
            curl.setopt(pycurl.HTTPHEADER, ["Content-Type: application/json"])
            curl.setopt(pycurl.POSTFIELDS, json.dumps(payload).encode("utf-8"))

        curl.perform()
        status = curl.getinfo(pycurl.RESPONSE_CODE)
    except pycurl.error as exc:
        raise AssertionError(
            f"HTTP request failed\nmethod: {method}\nurl: {url}\nerror: {exc}"
        ) from exc
    finally:
        curl.close()

    text = body.getvalue().decode("utf-8", errors="replace")
    try:
        json_body: Any | None = json.loads(text) if text.strip() else None
    except json.JSONDecodeError:
        json_body = None

    return SimpleNamespace(
        status=status,
        headers=headers,
        text=text,
        json_body=json_body,
    )


def test_user_service_crud() -> None:
    user_service_url: str | None = None
    random_id = uuid4().hex
    user_service = copy.deepcopy(USER_SERVICE_JSON)
    user_service["extServiceIds"] = [f"urn:uuid:{random_id}"]

    try:
        # ========================================================= #
        #       MBS User Service Operations 
        # ========================================================= #
        # 1. POST: Create the MBS User Service and capture its generated resource ID.
        create_service = _request("POST", USER_SERVICES_URL, user_service)
        assert create_service.status == 201, create_service.text
        assert "location" in create_service.headers, create_service.headers
        user_service_id = create_service.headers["location"].rstrip("/").rsplit("/", 1)[-1]
        user_service_url = f"{USER_SERVICES_URL}/{user_service_id}"

        assert isinstance(create_service.json_body, dict)
        assert create_service.json_body["servType"] == "MULTICAST"
        assert create_service.json_body["mainServLang"] == "eng"


        # 2. PUT: Update and retrieve the MBS User Service.
        
        updated_user_service = copy.deepcopy(user_service)
        updated_user_service["servNameDescs"][0][
            "servDescrip"
        ] = "The description has been changed!"

        update_service = _request("PUT", user_service_url, updated_user_service)
        assert update_service.status == 200, update_service.text
        assert isinstance(update_service.json_body, dict)
        assert (update_service.json_body["servNameDescs"][0]["servDescrip"]== "The description has been changed!")

        # 3. GET: Retrieving an MBS User Service
        get_service = _request("GET", user_service_url)
        assert get_service.status == 200, get_service.text
        assert isinstance(get_service.json_body, dict)
        assert (get_service.json_body["servNameDescs"][0]["servDescrip"] == "The description has been changed!")
        assert get_service.json_body["extServiceIds"] == user_service["extServiceIds"]
    
        # 4. DELETE: Deleting an MBS User Service 
        delete_service = _request("DELETE", user_service_url)
        assert delete_service.status == 204, delete_service.text
        assert _request("GET", user_service_url).status == 404
        user_service_url = None

    finally:
        # Remove resources left behind when an assertion fails.
        if user_service_url is not None:
            try:
                _request("DELETE", user_service_url)
            except AssertionError:
                pass

def test_ingest_session_crud() -> None:
    ingest_user_service_url: str | None = None
    ingest_url: str | None = None
    random_id = uuid4().hex

    try:
        # ========================================================= #
        #       MBS User Data Ingest Session Operations 
        # ========================================================= #
        # 0. Create a new User Service for the separate ingest-session tutorial.
        ingest_user_service = copy.deepcopy(USER_SERVICE_JSON)
        ingest_user_service["extServiceIds"] = [f"urn:uuid:{uuid4().hex}"]
        create_ingest_service = _request(
            "POST",
            USER_SERVICES_URL,
            ingest_user_service,
        )
        assert create_ingest_service.status == 201, create_ingest_service.text
        assert "location" in create_ingest_service.headers, create_ingest_service.headers
        ingest_user_service_id = create_ingest_service.headers["location"].rstrip(
            "/"
        ).rsplit("/", 1)[-1]
        ingest_user_service_url = f"{USER_SERVICES_URL}/{ingest_user_service_id}"

        # Prepare the MBS User Data Ingest Session payload with unique IP addresses.
        ingest_session = copy.deepcopy(STREAMING_INGEST_JSON)
        ingest_session["mbsUserServId"] = ingest_user_service_id
        ssm = ingest_session["mbsDisSessInfos"]["AP_MBS_SESSION_1"][
            "mbsSessionId"
        ]["ssm"]
        ssm["sourceIpAddr"]["ipv4Addr"] = (
            f"127.{int(random_id[0:2], 16)}.{int(random_id[2:4], 16)}."
            f"{int(random_id[4:6], 16)}"
        )
        ssm["destIpAddr"]["ipv4Addr"] = (
            f"232.{int(random_id[6:8], 16)}.{int(random_id[8:10], 16)}."
            f"{int(random_id[10:12], 16)}"
        )

        # 1. POST: Create the associated MBS User Data Ingest Session.
        create_ingest = _request("POST", INGEST_SESSIONS_URL, ingest_session)
        assert create_ingest.status == 201, create_ingest.text
        assert "location" in create_ingest.headers, create_ingest.headers
        ingest_id = create_ingest.headers["location"].rstrip("/").rsplit("/", 1)[-1]
        ingest_url = f"{INGEST_SESSIONS_URL}/{ingest_id}"
        assert isinstance(create_ingest.json_body, dict)
        assert create_ingest.json_body["mbsUserServId"] == ingest_user_service_id
        assert (create_ingest.json_body["mbsDisSessInfos"]["AP_MBS_SESSION_1"]["mbsDistSessState"] == "INACTIVE")

        # 2. PUT: Update an MBS User Data Ingest Session
        updated_ingest_session = copy.deepcopy(ingest_session)
        updated_ingest_session["mbsDisSessInfos"]["AP_MBS_SESSION_1"][
            "mbsDistSessState"
        ] = "ACTIVE"

        update_ingest = _request("PUT", ingest_url, updated_ingest_session)
        assert update_ingest.status == 200, update_ingest.text
        assert isinstance(update_ingest.json_body, dict)
        assert (
            update_ingest.json_body["mbsDisSessInfos"]["AP_MBS_SESSION_1"][
                "mbsDistSessState"
            ]
            == "ACTIVE"
        )
        # 3. GET: Retrieve an MBS User Data Ingest Session
        get_ingest = _request("GET", ingest_url)
        assert get_ingest.status == 200, get_ingest.text
        assert isinstance(get_ingest.json_body, dict)
        assert get_ingest.json_body["mbsUserServId"] == ingest_user_service_id
        assert (get_ingest.json_body["mbsDisSessInfos"]["AP_MBS_SESSION_1"]["mbsDistSessState"] == "ACTIVE")

        # 4. DELETE: Delete an MBS User Data Ingest Session 
        delete_ingest = _request("DELETE", ingest_url)
        assert delete_ingest.status == 204, delete_ingest.text
        assert _request("GET", ingest_url).status == 404
        ingest_url = None

        # Deleting the MBS User Service Session Created in step 0.
        delete_service = _request("DELETE", ingest_user_service_url)
        assert delete_service.status == 204, delete_service.text
        assert _request("GET", ingest_user_service_url).status == 404
        ingest_user_service_url = None

    finally:
        # Remove resources left behind when an assertion fails.
        for url in (ingest_url, ingest_user_service_url):
            if url is not None:
                try:
                    _request("DELETE", url)
                except AssertionError:
                    pass
