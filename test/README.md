# Tests

## Introduction

This folder contains API tests for the 5G-MAG MBS network functions:

* `test_mbsf_crud.py` — an end-to-end CRUD test for the MBSF APIs (`pytest`). It follows the
  [MBSF tutorial](https://hub.5g-mag.com/Getting-Started/pages/5g-multicast-broadcast-services/tutorials/mbsf.html)
  and exercises the MBS User Service API (`/nmbsf-mbs-us/v1/mbs-user-services`) and the
  MBS User Data Ingest Session API (`/nmbsf-mbs-ud-ingest/v1/sessions`).
* `tests.py` — the MB-SMF test suites for the TMGI and MBS Session service APIs (`unittest`).

All tests talk to the network functions over HTTP/2 with prior knowledge.

## Installing the dependencies

Recent Python distributions mark the system interpreter as externally managed, so install the
dependencies into a virtual environment:

```bash
cd test
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

`.venv` and `venv` are already ignored by the project `.gitignore`.

## Prerequisites

The network functions under test must be running before the tests are started. The
`scripts/tmux/mbs-function-tutorial/mbs-function-tutorial.sh` script starts the Open5GS core
network functions, the MBSTF, the MBSF and the mock media server in a single tmux session:

```bash
cd scripts/tmux/mbs-function-tutorial
bash ./mbs-function-tutorial.sh
```

See [scripts/tmux/Readme.md](../scripts/tmux/Readme.md) for the paths that need to be adjusted in
that script beforehand, and for how to stop the session again.

## Configuration

The addresses of the network functions are configured in `config.toml`:

```toml
[mb_smf]
address = "smf-mb-smf.5g-mag.org"
protocol = "http"
port = 80

[mbsf]
address = "127.0.0.67"
protocol = "http"
port = 7777
```

Adjust the `[mbsf]` section so that it matches the `sbi` address of your MBSF configuration
(`local-mbsf.yaml`), and the `[mb_smf]` section for the MB-SMF tests.

## Running the tests

### MBSF CRUD tests

From the `test` folder, with the virtual environment activated:

```bash
pytest -v -s test_mbsf_crud.py
```

The tests can also be started from the project root with `pytest -v -s test/test_mbsf_crud.py`.

To run a single test, append its name:

```bash
pytest -v -s test_mbsf_crud.py::test_user_service_crud
```

Both tests create their resources with randomised identifiers and delete them again, including
when an assertion fails, so they can be run repeatedly against the same MBSF instance.

### MB-SMF tests

```bash
python3 tests.py
```
