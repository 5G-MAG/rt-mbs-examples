<p align="center">
  <img src=".github/banner.svg" width="100%" alt="Reference Tools · 5G Multicast Broadcast Services (MBS): MBS Tools and Examples">
</p>

<p align="center">
  Examples and development tools for the 5G-MAG MBS implementation: an end-to-end MBS Broadcast demo
  from 5G Core to UE, a Docker Compose setup, a mock media server, REST API collections, tmux scripts
  and API tests.
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

## Introduction

This repository collects example projects that use the other 5G-MAG MBS repositories, and tools that
help to implement and test new MBS features. It builds none of the other components: it starts and
provisions what you have built. Each folder below is self-contained, and its own README or the folder
itself holds the instructions.

**Start here:** the [Broadcast demo](scripts/mbs-broadcast-demo/README.md) brings up the whole stack
from a cold start and runs content end to end over the radio interface. Its Prerequisites section is
the complete list of what to install, clone and build first.

More information is on the [project page](https://www.5g-mag.com/reference-tools/5g-mbs/).

### Tutorials

- **[The whole MBS Broadcast stack](scripts/mbs-broadcast-demo/README.md)** brings up the 5G Core,
  the MBSF and MBSTF, a gNB and UE pair, the MBS Client and both portals from a cold start, and runs
  content end to end over the radio interface. It shows what a healthy run looks like, and how to run
  the same thing with UE pre-configuration (3GPP TS 24.575), the specified way for a UE to find the
  Service Announcement. It also explains why there is no RAN-free path: the gNB and UE run over a
  ZMQ software radio, so no radio hardware is needed.
- **[MBS User Services](templates/README.md)** explains what an MBS User Service and its Ingest
  Session are and what the operating mode changes, and shows how to provision both from
  rt-mbs-application-provider with a template rather than a script.

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
meant for development, when static responses are enough to implement or test a new feature. The
Broadcast demo also uses it as its media origin.

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

## Install dependencies

This repository builds nothing of its own, but the demo it runs needs a substantial toolchain and
eight other components built first. The complete list, with the exact `apt` line and the build
command for each component, is in
[the Broadcast demo's Prerequisites](scripts/mbs-broadcast-demo/README.md#prerequisites).

In short: GCC 14 or later, which the MBSF and MBSTF need for C++20 (check with `gcc --version`
rather than by release number); Node.js 18 or later; MongoDB from MongoDB's own repository; and a
DASH package for the origin, which you can generate.

## Downloading

```bash
git clone https://github.com/5G-MAG/rt-mbs-examples.git
cd rt-mbs-examples
```

## Building

There is nothing to build. `./demo` starts components you have already built elsewhere, and fails
with the name of anything it cannot find.

The one exception is the mock media origin under `express-mock-media-server/`, a Node application:

```bash
cd express-mock-media-server
npm install
```

`./demo up` does this itself if `node_modules/` is absent.

## Installing

There is no install step. Everything is run from the working copy.

## Running a demo

Before the first run, once per machine, build the components these scripts start and install the
tools they use. The full list, including the `sudo`, `mongod` and submodule requirements, is in
[the Broadcast demo's Prerequisites](scripts/mbs-broadcast-demo/README.md#prerequisites).

After that, every run uses these commands:

```bash
./demo doctor              # will it start here? changes nothing
./demo up                  # the Broadcast demo, which is the one to show
./demo status
./demo down                # stops it and verifies nothing of it is left
./demo down --all          # stops all three demos, in every repository it can find
```

`./demo up` with no name starts the Broadcast demo.

`./demo up` runs the checks first and refuses to start on a conflict, naming what to stop. The
checks exist because three demos in this project share a machine and cannot see each other:

| | this repository | rt-mbms-examples | rt-dvb-i-examples |
|---|---|---|---|
| media origin | :3004 | :3005 | **:3004, same as this one** |
| ZMQ radio control | **2100, 2101** | **2100, 2101, same as this one** | none |
| network namespace | `ns-gnb` | `mbms-rx` | none |
| player / portal | :3050, :8091 | :3000, :8080 | :5000, :4000 |
| service list registry | none | none | :7000 |

This demo conflicts with both of the others, on the radio with MBMS and on the media origin with
DVB-I, so it runs on its own. The MBMS and DVB-I demos, which share nothing, can run together.
`./demo doctor` says which demo is in the way and how to stop it. Restarting a demo that is already
up is not treated as a conflict, because `start-all.sh` stops it first.

`./demo down` does not rely on the stop scripts alone. It runs them, then checks that this demo's
processes, ports and network namespace are gone and clears anything left, so the next run starts
clean. `--all` does the same for the other two demos, finding their checkouts beside this one; set
`MBMS_EXAMPLES_DIR` or `DVBI_EXAMPLES_DIR` if they are elsewhere.

Add `--force` to `up` to start anyway. `DEMO_MIN_FREE_MB` overrides the memory floor.

The per-demo scripts under `scripts/` can also be run directly.

### Demo content

Content starts with the demo. `./demo up` launches one looping ffmpeg encoder per channel, each
publishing a live presentation into the media server, so there is nothing extra to run.

The line-up is `scripts/mbs-broadcast-demo/channels.json`: four channels, `5G-MAG.tv 1`, `2`, `3`
and `5G-MAG.radio`, the same four names the MBMS and DVB-I demos publish. The origin encodes and
serves all four; the one with the `onAir` flag set in that file is carried over the radio.

No content is available for download. Two things are involved, and only one of them stops a run:

- **Required**: a DASH package at `$MWC_CONTENT_ROOT/$DEMO_STREAM`, default
  `~/MWC_TV_RADIO/dash/tv_1`. Without it, `./demo up` stops at `03-start-media-server.sh` with
  `content not found`.
- **Optional**: the per-channel source clips `TV_1.mp4`, `TV_2.mp4`, `TV_3.mp4` and `RADIO.mp4`
  under `CONTENT_ROOT`, default `~/MWC_TV_RADIO`. An encoder whose clip is absent falls back to a
  generated test pattern, so `./demo up` runs without them.

Any MP4 will do for either, and
[the Broadcast demo's Prerequisites](scripts/mbs-broadcast-demo/README.md#prerequisites) gives an
`ffmpeg` command for each.

```bash
# check content is actually flowing, once the demo is up
curl -s http://127.0.0.1:3004/tv_1_live/manifest.mpd | head
./demo status                       # shows the presentation and whether it is advancing
```

To play something else, edit `channels.json`, or point `CONTENT_ROOT` at a directory holding files
of those names; this changes only the live channels, not the DASH package the origin serves. Setting
`LIVE_SOURCE_MEDIA` or `LIVE_STREAM_NAME` does not change what `./demo up` plays: `start-all.sh`
sets both per channel from `channels.json` as it starts each encoder. They apply only when a script
such as `live-encoder.sh` is run directly.

On a machine that cannot encode four channels at once, `DEMO_CHANNELS` limits the run to the channel
ids it names (space or comma separated). Use it when the UE fails to attach under load:

```bash
DEMO_CHANNELS=mwc-tv-1 ./demo up
```

For a file carousel rather than a live stream, `scripts/mbs-*-demo/07-live-carousel-regen.sh`
republishes the carousel objects against the running session.

## Acknowledgements

The reference implementation of the MBS features was partially funded by the European Union through the project 6G-SANDBOX (Grant Agreement 101096328) and by the European Space Agency (ESA) through the project "Requirements consolidation and design concepts for future NTN MBS systems" (ESA Contract No. 5001042231).

## Contributing

Contributions are welcome. How to raise an issue, fork the repository and open a pull request, and
the Contributor License Agreement required before code can be merged, are described at
<https://www.5g-mag.com/contributing>.

## License

Distributed under the 5G-MAG Public License v1.0. See [LICENSE.md](LICENSE.md).
