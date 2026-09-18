<p align="center">
  <img src=".github/banner.svg" width="100%" alt="5G-MAG Reference Tools, 5G Multicast Broadcast Services: MBS Examples">
</p>

<p align="center">
  Runnable end-to-end demos and test tooling for the 5G MBS reference tools: a full
  Broadcast deployment from 5G Core to UE, with content flowing.
</p>

<p align="center">
  <img alt="Status: under development"
    src="https://img.shields.io/badge/Status-Under_Development-yellow">
  <a href="https://github.com/5G-MAG/rt-mbs-examples/releases"><img alt="Version"
    src="https://img.shields.io/github/v/release/5G-MAG/rt-mbs-examples?label=Version&sort=semver"></a>
  <a href="LICENSE"><img alt="5G-MAG Public License v1.0"
    src="https://img.shields.io/badge/License-5G--MAG%20PL%20v1.0-blue"></a>
</p>

<p align="center">
  <a href="https://www.5g-mag.com/reference-tools/5g-multicast-broadcast-services">Project page</a> &nbsp;&middot;&nbsp;
  <a href="https://github.com/5G-MAG/rt-mbs-examples/issues">Issues</a> &nbsp;&middot;&nbsp;
  <a href="https://www.5g-mag.com/contributing">Contributing</a>
</p>

---

## At a glance

|  |  |
|---|---|
| **Provides** | An end-to-end MBS Broadcast demo, a mock media origin, API tests, Insomnia collections and a Docker Compose deployment |
| **Role** | Integration: it starts and provisions the other components, and builds none of them |
| **Built with** | Bash, Node.js and Python |
| **Works with** | [rt-mbs-function](https://github.com/5G-MAG/rt-mbs-function), [rt-mbs-transport-function](https://github.com/5G-MAG/rt-mbs-transport-function), [rt-mbs-client](https://github.com/5G-MAG/rt-mbs-client), [rt-mbs-application](https://github.com/5G-MAG/rt-mbs-application), [rt-mbs-application-provider](https://github.com/5G-MAG/rt-mbs-application-provider), [open5gs](https://github.com/5G-MAG/open5gs), [srsRAN_Project_mbs](https://github.com/5G-MAG/srsRAN_Project_mbs) and [srsRAN_4G_mbs](https://github.com/5G-MAG/srsRAN_4G_mbs) |
| **Part of** | [5G Multicast Broadcast Services](https://www.5g-mag.com/reference-tools/5g-multicast-broadcast-services) |

## Introduction

Example projects that make use of other 5G-MAG repositories, or add functionality for testing and
developing MBS features.

**Start here:** the [Broadcast demo](scripts/mbs-broadcast-demo/README.md) brings up the whole
stack from a cold start and runs content end to end over the radio interface. Its Prerequisites
section is the complete list of what to install, clone and build first; this repository builds
none of those components, it runs what you have built.

## Install dependencies

This repository builds nothing of its own, but the demo it runs needs a substantial toolchain and
eight other components built first. The complete list, with the exact `apt` line and the build
command for each component, is in
[the Broadcast demo's Prerequisites](scripts/mbs-broadcast-demo/README.md#prerequisites).

In short: a distribution with GCC 14 or later, Node.js 18 or later, MongoDB from MongoDB's own
repository, and the four source clips the channel line-up names.

## Downloading

```bash
git clone https://github.com/5G-MAG/rt-mbs-examples.git
cd rt-mbs-examples
```

This repository has no build step of its own. What it needs installed and built is in the
[Broadcast demo's Prerequisites](scripts/mbs-broadcast-demo/README.md#prerequisites).

## Building

Nothing to build. `./demo` starts components you have already built elsewhere and fails with the
name of anything it cannot find.

The one exception is the mock media origin under `express-mock-media-server/`, which is a Node
application:

```bash
cd express-mock-media-server
npm install
```

`./demo up` does this itself if `node_modules/` is absent.

## Installing

There is no install step. Everything here is run from the working copy.

## Running a demo

**Before the first run**, once per machine: the components these scripts start must already be
built, and a few tools must be present. These scripts run what is built; they build nothing. The
full list, including the `sudo`, `mongod` and submodule requirements, is in
[the Broadcast demo's Prerequisites](scripts/mbs-broadcast-demo/README.md#prerequisites).

After that, every run is the four commands below.

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

So the MBS and MBMS demos cannot both hold the radio, and the MBS and DVB-I demos cannot both
hold the media origin. Whichever starts second used to fail somewhere unhelpful, in the radio or
in a bind error; `./demo doctor` now says which demo is in the way and how to stop it. Restarting
a demo that is already up is fine and is not treated as a conflict, because `start-all.sh` stops
it first.

`./demo down` does not trust the stop scripts. It runs them, then checks this demo's processes,
ports and network namespace are actually gone and clears anything left, so the next run starts
from nothing. `--all` does the same for the other two demos, finding their checkouts beside this
one; set `MBMS_EXAMPLES_DIR` or `DVBI_EXAMPLES_DIR` if they live somewhere unusual.

Add `--force` to `up` to start anyway. `DEMO_MIN_FREE_MB` overrides the memory floor.

The per-demo scripts under `scripts/` are unchanged and can still be run directly.

### Demo content

Content starts with the demo. `./demo up` launches one looping ffmpeg encoder per channel, each
publishing a live presentation into the media server, so there is nothing extra to run.

The line-up is `scripts/mbs-broadcast-demo/channels.json`: four channels, `5G-MAG.tv 1`, `2`, `3`
and `5G-MAG.radio`, the same four names the MBMS and DVB-I demos publish. All four are encoded and
served by the origin; one of them is carried over the radio, which is the `onAir` flag in that
file.

**Nothing is downloadable and nothing needs to be on the machine already.** Two different things
are involved, and only one of them stops a run:

- **Required**: a DASH package at `$MWC_CONTENT_ROOT/$DEMO_STREAM`, default
  `~/MWC_TV_RADIO/dash/tv_1`. `./demo up` stops at `03-start-media-server.sh` without it, with
  `content not found`.
- **Optional**: the per-channel source clips `TV_1.mp4`, `TV_2.mp4`, `TV_3.mp4` and `RADIO.mp4`
  under `CONTENT_ROOT`, default `~/MWC_TV_RADIO`. The encoders fall back to a generated test
  pattern when one is absent, so `./demo up` runs without them.

Any MP4 will do for either, and
[the Broadcast demo's Prerequisites](scripts/mbs-broadcast-demo/README.md#prerequisites) carries an
`ffmpeg` command for each.

```bash
# check content is actually flowing, once the demo is up
curl -s http://127.0.0.1:3004/tv_1_live/manifest.mpd | head
./demo status                       # shows the presentation and whether it is advancing
```

To play something else, edit `channels.json`, or point `CONTENT_ROOT` at a directory holding files
of those names, remembering that this changes only the live channels and not the DASH package the
origin serves. Setting `LIVE_SOURCE_MEDIA` or `LIVE_STREAM_NAME` does **not** change what `./demo
up` plays: `start-all.sh` sets both per channel from `channels.json` as it starts each encoder.
They apply only when a script such as `live-encoder.sh` is run directly.

On a machine that cannot encode four channels at once, `DEMO_CHANNELS` limits the run to the
channel ids it names (space or comma separated), which is the knob to reach for when the UE fails
to attach under load:

```bash
DEMO_CHANNELS=mwc-tv-1 ./demo up
```

For the file-carousel case rather than a live stream, `scripts/mbs-*-demo/07-live-carousel-regen.sh`
republishes the carousel objects against the running session.

## Tutorials

Two, and they are the place to start:

- **[The whole MBS Broadcast stack](scripts/mbs-broadcast-demo/README.md)** -- brings up the 5G core,
  MBSF/MBSTF, a gNB and UE pair, the MBS Client and both portals from a cold start, and runs
  content end to end over the radio interface. It also shows what a healthy run looks like, so you
  can tell whether it worked; how to run the same thing with UE pre-configuration (3GPP TS 24.575),
  which is the specified way for a UE to find the Service Announcement; and the RAN-free path for
  when the radio is not what you are testing.
- **[MBS User Services](templates/README.md)** -- what an MBS User Service and its Ingest Session
  are, what the operating mode changes, and how to provision both from rt-mbs-application-provider
  using a template rather than a script.

## 5G Multicast Broadcast Services - Docker Compose Setup

This is a docker setup to build and run MBS-related 5GC network functions, an MBS-enabled gNB, an MBS-enabled UE and a test AF/AS. In addition, it includes a Docker Compose file to deploy all these components. The configuration files included in this project can be edited on the host machine and are mounted to the respective Docker container during runtime.

Information can be found [here](./mbs-docker-setup/).

## Docker Monitor

A lightweight web-based monitor for inspecting the status of Docker containers grouped by service. It is provided as a shared tool by the [rt-common-shared](https://github.com/5G-MAG/rt-common-shared) repository.

Information on how to set it up can be found in the [mbs-docker-setup README](./mbs-docker-setup/README.md#docker-monitor).

## Express Mock AF

This folder provides a very simple HTTP server that implements a basic set of object downloads with varying redirections. This server is intended to be used for development when static responses are enough to implement or test a new feature.

Information can be found [here](./express-mock-media-server/).

## Insomnia collection

This folder contains Insomnia REST API collections for testing and exploring the 5G-MAG MBS network functions. Each collection targets a specific network function and covers the relevant 3GPP service APIs.

Information can be found [here](./insomnia/).

## TMUX Setup

This folder contains scripts for tmux an open-source terminal multiplexer that allows users to manage multiple terminal sessions, windows, and panes from a single screen or terminal window.

Information can be found [here](./scripts/tmux/).

## Tests

The `test` folder contains API tests for the MBS network functions, covering the CRUD operations of the MBSF service APIs as well as the MB-SMF TMGI and MBS Session service APIs.

Information can be found [here](./test/).

## Acknowledgements

The reference implementation of the MBS features was partially funded by the European Union through the project 6G-SANDBOX (Grant Agreement 101096328) and by the European Space Agency (ESA) through the project "Requirements consolidation and design concepts for future NTN MBS systems" (ESA Contract No. 5001042231).

## Contributing

Contributions are welcome. How to raise an issue, fork the repository and open a pull request, and
the Contributor License Agreement required before code can be merged, are described at
<https://www.5g-mag.com/contributing>.

## License

See [LICENSE](LICENSE).
