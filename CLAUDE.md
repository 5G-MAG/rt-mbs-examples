# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

Example projects for 5G Multicast Broadcast Services (MBS) from the 5G-MAG project. This is not a single application but a collection of independent components that support developing and testing the 5G-MAG MBS network functions (MBSF, MBSTF, MB-SMF, MB-UPF). License: 5G-MAG Public License (v1.0).

The four main components:

- `mbs-docker-setup/` — Docker Compose deployment of a full end-to-end 5G MBS system: Open5GS-based 5G Core NFs (some stock, some MBS-customized like `smf_mb-smf`, `upf_mb-upf`, `amf_with_mbs`, `nrf_5gmag`), an srsRAN-based MBS gNB and UE, and a Test AF/AS. One Dockerfile per image under `images/`, built via `docker-bake.hcl`. Deployments live under `compose-files/<deployment>/` with matching configs under `configs/<deployment>/` that are mounted into the containers at runtime (currently only the `internal` deployment exists).
- `test/` — Python API tests against running network functions. All tests talk to the NFs over HTTP/2 with prior knowledge (see `utils/http2_prior_knowledge.py`). NF addresses are configured in `test/config.toml` (`[mbsf]` and `[mb_smf]` sections) and must match the running NFs' SBI addresses.
- `express-mock-media-server/` — Minimal Express server (port 3004, override with `PORT`) serving static objects with various HTTP redirect chains, used as a mock origin when developing MBS features. Routes are in `routes/index.js`.
- `scripts/tmux/` — tmux scripts that start all processes needed for the MBSF/MBSTF tutorials (Open5GS NFs, MBSTF, MBSF, mock media server) in one session. The scripts contain hardcoded paths (`OPEN5GS_BASE_DIR`, `MBSF_BASE_DIR`, etc.) that must be adjusted to the local machine before first use. They depend on sibling repos (`open5gs`, `rt-mbs-function`, `rt-mbs-transport-function`) being built locally.

`insomnia/` holds Insomnia REST collections for the MBSF, MBSTF, MB-SMF and TMGI service APIs — useful as a reference for the request/response shapes of the 3GPP service APIs.

## Commands

### API tests (test/)

Dependencies go in a venv (system Python is externally managed):

```bash
cd test
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

The network functions under test must already be running (e.g. via `bash scripts/tmux/mbs-function-tutorial/mbs-function-tutorial.sh`), and `test/config.toml` must point at them.

```bash
# MBSF CRUD tests (pytest)
pytest -v -s test_mbsf_crud.py
# single test
pytest -v -s test_mbsf_crud.py::test_user_service_crud

# MB-SMF TMGI / MBS Session tests (unittest)
python3 tests.py
```

The MBSF CRUD tests create resources with randomized identifiers and clean up even on assertion failure, so they are safe to re-run against the same MBSF instance.

### Mock media server (express-mock-media-server/)

```bash
cd express-mock-media-server
npm install
npm start          # port 3004, or PORT=... npm start
# or via docker:
cd docker && docker compose up --build
```

### Docker MBS system (mbs-docker-setup/)

```bash
cd mbs-docker-setup
# build all images (needs docker buildx; GITHUB_USER/GITHUB_TOKEN env vars with read:packages scope)
docker buildx bake

# one-time volume creation
docker volume create open5gs_db_data
docker volume create open5gs_db_config

# run / stop the internal deployment (set DOCKER_HOST_IP in .env first)
docker compose -f compose-files/internal/docker-compose-mbs.yml --env-file=.env up -d
docker compose -f compose-files/internal/docker-compose-mbs.yml --env-file=.env down
```

Image versions are pinned via variables in `mbs-docker-setup/.env`. Never hardcode `GITHUB_USER`/`GITHUB_TOKEN` in any file — pass them as environment variables only.

### tmux tutorial sessions (scripts/tmux/)

```bash
cd scripts/tmux/mbs-function-tutorial
bash ./mbs-function-tutorial.sh
# stop: tmux kill-session -t mbsf-tutorial
# leftover NFs: sudo pkill -TERM -f 'open5gs-(nrfd|scpd|smfd|upfd|amfd|udmd|mbstfd|mbsfd)'
```

## Conventions

- Source files carry a 5G-MAG Public License (v1.0) header with author and copyright — keep it when creating new files in `test/`.
- The default branch for PRs is `main`; day-to-day development happens on `development`.
