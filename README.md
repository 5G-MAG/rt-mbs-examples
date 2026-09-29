<p align="center">
  <img src=".github/banner.svg" width="100%" alt="Reference Tools · 5G Multicast Broadcast Services (MBS): MBS Tools and Examples">
</p>

<p align="center">
  Examples and development tools for the 5G-MAG MBS implementation: a Docker Compose setup of the
  5G Core, gNB, UE and a test AF/AS, a mock media server, REST API collections, tmux scripts and API
  tests.
</p>

<p align="center">
  <img alt="Status: Under Development"
    src="https://img.shields.io/badge/Status-Under%20Development-e67e22">
  <a href="https://github.com/5G-MAG/rt-mbs-examples/releases"><img alt="Version"
    src="https://img.shields.io/github/v/release/5G-MAG/rt-mbs-examples?label=Version"></a>
  <a href="LICENSE.md"><img alt="License: 5G-MAG Public License v1.0"
    src="https://img.shields.io/badge/License-5G--MAG%20PL%20v1.0-blue"></a>
</p>

<p align="center">
  <a href="https://www.5g-mag.com/reference-tools/5g-mbs/">Project page</a> &nbsp;&middot;&nbsp;
  <a href="https://github.com/5G-MAG/rt-mbs-examples/issues">Issues</a> &nbsp;&middot;&nbsp;
  <a href="https://www.5g-mag.com/contributing">Contributing</a>
</p>

---

## At a glance

|  |  |
|---|---|
| **Part of** | [5G Multicast Broadcast Services (MBS)](https://www.5g-mag.com/reference-tools/5g-mbs/), alongside [open5gs](https://github.com/5G-MAG/open5gs), [rt-5gc-service-consumers](https://github.com/5G-MAG/rt-5gc-service-consumers), [rt-libflute](https://github.com/5G-MAG/rt-libflute), [rt-mbs-application](https://github.com/5G-MAG/rt-mbs-application), [rt-mbs-application-provider](https://github.com/5G-MAG/rt-mbs-application-provider), [rt-mbs-client](https://github.com/5G-MAG/rt-mbs-client), [rt-mbs-function](https://github.com/5G-MAG/rt-mbs-function), [rt-mbs-transport-function](https://github.com/5G-MAG/rt-mbs-transport-function), [rt-media-origin](https://github.com/5G-MAG/rt-media-origin), [rt-srsRAN_Project](https://github.com/5G-MAG/rt-srsRAN_Project), [srsRAN_4G](https://github.com/5G-MAG/srsRAN_4G), [srsRAN_4G_mbs](https://github.com/5G-MAG/srsRAN_4G_mbs) and [srsRAN_Project_mbs](https://github.com/5G-MAG/srsRAN_Project_mbs) |

## Introduction

This repository collects example projects that use the other 5G-MAG MBS repositories, and tools that
help to implement and test new MBS features. Each folder below is self-contained, and its own README
or the folder itself holds the instructions.

More information is on the [project page](https://www.5g-mag.com/reference-tools/5g-mbs/).

### Docker Compose setup

A Docker setup that builds and runs the MBS-related 5G Core network functions, an MBS-enabled gNB, an
MBS-enabled UE and a test AF/AS, with a Docker Compose file that deploys them all. The configuration
files can be edited on the host; they are mounted into the containers at runtime.

See [mbs-docker-setup](./mbs-docker-setup/).

### Docker Monitor

A lightweight web-based monitor that shows the status of the Docker containers, grouped by service.
It is a shared tool from the [rt-common-shared](https://github.com/5G-MAG/rt-common-shared)
repository.

How to set it up is described in the
[mbs-docker-setup README](./mbs-docker-setup/README.md#docker-monitor).

### Express mock AF

A simple HTTP server that serves a basic set of object downloads with varying redirections. It is
meant for development, when static responses are enough to implement or test a new feature.

See [express-mock-media-server](./express-mock-media-server/).

### Insomnia collections

Insomnia REST API collections for testing and exploring the 5G-MAG MBS network functions. Each
collection targets one network function and covers its 3GPP service APIs.

See [insomnia](./insomnia/).

### tmux scripts

Scripts for tmux, the open-source terminal multiplexer, which manages several terminal sessions,
windows and panes from one terminal window.

See [scripts/tmux](./scripts/tmux/).

### API tests

The `test` folder holds API tests for the MBS network functions: the CRUD operations of the MBSF
service APIs, and the MB-SMF TMGI and MBS Session service APIs.

See [test](./test/).

## Acknowledgements

The reference implementation of the MBS features was partially funded by the European Union through the project 6G-SANDBOX (Grant Agreement 101096328) and by the European Space Agency (ESA) through the project "Requirements consolidation and design concepts for future NTN MBS systems" (ESA Contract No. 5001042231).

## Contributing

Contributions are welcome. How to raise an issue, fork the repository and open a pull request, and
the Contributor License Agreement required before code can be merged, are described at
<https://www.5g-mag.com/contributing>.

## License

Distributed under the 5G-MAG Public License v1.0. See [LICENSE.md](LICENSE.md).
