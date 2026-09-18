# Tutorial: the whole MBS Broadcast stack

Runs the full 5G MBS Broadcast reference stack from a cold start: network namespace, 5G core,
MBSF/MBSTF, a media server, a gNB and UE pair (ZMQ RF loopback, no SDR hardware needed),
rt-mbs-client, and both web portals.

For the service layer on its own, how an MBS User Service and its Ingest Session are defined and
what the operating mode changes, see `rt-mbs-examples/templates/README.md`, the MBS User Services
tutorial. It uses the RAN-free path below so nothing radio-related gets in the way.

## Which script

| Script | What it does | When |
|---|---|---|
| `./start-all.sh` | Everything, gNB and UE included, and provisions a demo service | The full end-to-end |
| `UE_PRE_CONFIGURATION=1 ./start-all.sh` | The same, but the client finds the Service Announcement through the TS 24.575 pre-configuration object instead of a fixed config block | Showing the specified bootstrap |
| `./start-bypass-live.sh` | Everything except the RAN, with a looping live DASH service created for you | Watching video without the radio |
| `./start-systems.sh` | The same bring-up, creating no service at all | Provisioning it yourself from the provider |

All three reset anything already running first, so they are safe to run twice. `./stop-all.sh`
stops everything, the encoder included. `./status.sh` shows what is up.

### What "it worked" looks like

After `./start-all.sh` returns, give it a minute and check the logs under `run/logs/`. These are the
numbers from a healthy run; the exact counts grow with how long it has been up.

| Check | Where | Healthy |
|---|---|---|
| The UE is receiving MCCH | `grep -c 'MCCH received' run/logs/ue_bcast.log` | grows steadily, 2 sessions advertised |
| Broadcast radio bearers wired | `grep -oE 'MRB[0-9]+' run/logs/ue_bcast.log \| sort -u` | two MRBs |
| Transport blocks decoding | `grep -ci 'crc=OK' run/logs/ue_bcast.log` | thousands, and growing |
| Objects reaching the client | `grep -c completed run/logs/rt-mbs-client.log` | grows with the carousel |
| Ingest is healthy | `grep -ciE 'fetch fail\|Not refetching' run/logs/mbstf.log` | `0` |
| The gNB is not starved | `grep -c 'No space in PDCCH' run/logs/gnb.log` | `0`, or a couple at UE attach |

Then open the player at <http://localhost:3050/>.

If the UE never attaches, that is usually machine load rather than a fault: the ZMQ virtual radio
misses its deadlines when the box is busy. `UE_TUN_WAIT_SECS` (default 180) is how long the scripts
wait for the UE's PDU session before giving up.

This is **Broadcast only**. Multicast needs a different gNB/UE test-harness configuration
(dedicated-RRC `test_only_multicast_g_rnti`/`test_only_multicast_mrb_lcid`, not the plain
NGAP Broadcast Session Setup path these scripts drive) and is not covered here.

## Prerequisites

These scripts **run** a deployment; they build nothing. Everything below has to exist before
`./demo up` will get anywhere, and `./demo doctor` checks each one and names what is missing.

### 1. System packages

You need **GCC 14 or later**, which comes from the MBSF and MBSTF: both set `cpp_std=gnu++20` in
their `meson.build`. Check with `gcc --version` rather than going by release number, because a
distribution's default is often older than its newest available compiler. If yours is older, install
a newer one alongside it and point the builds at it:

```bash
sudo apt install g++-14            # or g++-15
CC=gcc-14 CXX=g++-14 <the build command for each component>
```

The two srsRAN forks are not the constraint: `srsRAN_4G_mbs` is verified to build on GCC 13, 14 and
15. Then:

```bash
sudo apt install git ninja-build build-essential meson cmake pkg-config \
  flex bison libsctp-dev libgnutls28-dev libgcrypt-dev libssl-dev libidn11-dev \
  libmongoc-dev libbson-dev libyaml-dev libnghttp2-dev libmicrohttpd-dev \
  libcurl4-gnutls-dev libtins-dev libtalloc-dev libpcre2-dev uuid-dev \
  libcpprest-dev libfftw3-dev libmbedtls-dev libboost-program-options-dev \
  libconfig++-dev libzmq3-dev \
  default-jdk curl wget jq util-linux-extra socat iproute2 ffmpeg python3
```

`libcpprest-dev` (with `libssl-dev`, already above) is for `srsRAN_4G_mbs`, whose `srsue` carries the radio status
API this demo's dashboard reads; it is built by default and fails to link without them. The
`libfftw3-dev`, `libmbedtls-dev`, `libboost-program-options-dev`, `libconfig++-dev` and
`libzmq3-dev` packages are the two srsRAN builds' own, `libzmq3-dev` in particular because both
the gNB and the UE run over the ZeroMQ software radio here rather than real hardware.

You also need **Node.js 18 or later** (`node --version`). The distribution package is often
older; use [NodeSource](https://github.com/nodesource/distributions) or
[nvm](https://github.com/nvm-sh/nvm) if it is.

**MongoDB** is needed separately: the NRF and UDR store their state in it. Ubuntu's own
`mongodb` package is not what Open5GS expects; install from
[MongoDB's repository](https://www.mongodb.com/docs/manual/administration/install-on-linux/),
which provides `mongod` via `mongodb-org-server`. The scripts start `mongod` if it is installed
but inactive, and fail with a clear message if it is absent.

Passwordless or cached `sudo` is required, for network-namespace management and the UPF's TUN
device. The scripts call `sudo -v` once up front.

### 2. The components

Clone and build each of these. They are independent repositories with their own READMEs; the
build command is repeated here only so you can see the whole job at once.

| Component | Repository | Build |
|---|---|---|
| 5G Core (MB-SMF, MB-UPF, AMF, NRF, …) | `open5gs` | `meson setup build && ninja -C build` |
| MBSF | `rt-mbs-function` | `meson setup build && ninja -C build` |
| MBSTF | `rt-mbs-transport-function` | `meson setup build && ninja -C build` |
| MBS Client | `rt-mbs-client` | `mkdir build && cd build && cmake -GNinja .. && ninja` |
| MBS-Aware Application | `rt-mbs-application` | `npm install` |
| Application Provider | `rt-mbs-application-provider` | `npm install` |
| gNB | `srsRAN_Project_mbs` | `cmake -S . -B build -DENABLE_ZEROMQ=ON && cmake --build build -j$(nproc)` |
| UE | `srsRAN_4G_mbs` | `cmake -S . -B build && cmake --build build -j$(nproc)` |

`ENABLE_ZEROMQ=ON` on the gNB is what lets it use the `device_driver: zmq` in this demo's
`gnb.yaml`. It defaults to **OFF** in `srsRAN_Project_mbs` (it is already ON in `srsRAN_4G_mbs`,
which is why only the gNB needs the flag), and the ZeroMQ radio is compiled only when it is on, so
having `libzmq3-dev` installed does not cover it.

`srsRAN_4G_mbs`'s own README covers its two extra dependencies, cpprestsdk and OpenSSL, in more
detail.

Clone each from its default branch. **Where you put them matters**: the scripts expect open5gs and
the two srsRAN forks directly under one root, and the six MBS components one level deeper in
`rt-mbs/`. Cloning them all side by side gives a layout the defaults do not describe, so from a
machine with nothing on it:

```bash
mkdir -p ~/Repos/rt-mbs

cd ~/Repos
git clone -b 5mbs https://github.com/5G-MAG/open5gs.git
git clone -b 5mbs https://github.com/5G-MAG/srsRAN_Project_mbs.git
git clone -b 5mbs https://github.com/5G-MAG/srsRAN_4G_mbs.git

cd ~/Repos/rt-mbs
git clone --recurse-submodules https://github.com/5G-MAG/rt-mbs-function.git
git clone --recurse-submodules https://github.com/5G-MAG/rt-mbs-transport-function.git
git clone --recurse-submodules https://github.com/5G-MAG/rt-mbs-client.git
git clone https://github.com/5G-MAG/rt-mbs-application.git
git clone https://github.com/5G-MAG/rt-mbs-application-provider.git
git clone https://github.com/5G-MAG/rt-mbs-examples.git
```

That produces exactly the tree in section 3, so no variable needs setting. Only the three repositories
shown with `--recurse-submodules` have any: MBSF, MBSTF and the MBS Client. If you already cloned one
of those without it, run `git submodule update --init --recursive` in it before building.

**The `-b 5mbs` on those three is not optional.** open5gs and the two srsRAN repositories are forks
whose `main` tracks upstream and carries no MBS work; `5mbs` is the branch that does. In
`srsRAN_Project_mbs` the difference is total, `main` containing none of the MBS sources at all, so a
plain `git clone` there produces a gNB that builds and then cannot do MBS. `srsRAN_4G_mbs` already
defaults to `5mbs`, and it is given explicitly above so that all three read the same way rather than
relying on which repository happens to default where.

The six `rt-mbs-*` components need no branch: they are MBS components throughout, and their default
branch is the one to use.

**Several of these repositories are private.** If a clone fails with a 404 rather than a permission
message, that is what it means: GitHub reports a repository you cannot see as absent, not as
forbidden. It is not a wrong URL. You need an account with access to the 5G-MAG organisation and
either an SSH key, in which case use the `git@github.com:5G-MAG/<repo>.git` form, or a credential
helper holding a token with `repo` scope.

Put them somewhere else if you prefer, and set `REPOS_ROOT`, or the individual variables, as section 3
describes.

The two Node components also need their configuration in place: `cp .env.example .env` in each,
and set `AUTH_TOKEN` in the provider's, which refuses to start without one. `05-start-client-and-app.sh`
writes both `.env` files itself when it runs, so for the demo alone `npm install` is enough.

### 3. Telling the scripts where everything is

The defaults assume the repositories are checked out under `$HOME/Repos`, with the MBS ones
grouped in a `rt-mbs/` sub-directory and the rest beside it. That grouping is the one part of the
layout that is not obvious, so the whole expected tree is below. It is one machine's habit, not a
requirement: every path here has a variable that moves it.

```
$HOME/Repos/                                REPOS_ROOT
├── open5gs/                                OPEN5GS_DIR
├── srsRAN_Project_mbs/                     GNB_DIR      (RAN_ROOT, defaults to REPOS_ROOT)
│   └── build/apps/gnb/gnb                  GNB_BIN
├── srsRAN_4G_mbs/                          UE_DIR
│   └── build/srsue/src/srsue               UE_BIN
└── rt-mbs/                                 RTMBS_ROOT   (note the extra level)
    ├── rt-mbs-function/                    MBSF_DIR
    ├── rt-mbs-transport-function/          MBSTF_DIR
    ├── rt-mbs-client/                      CLIENT_DIR
    │   └── build/mbs-client                CLIENT_BIN
    ├── rt-mbs-application/                 APP_DIR
    ├── rt-mbs-application-provider/        PROVIDER_DIR
    └── rt-mbs-examples/                    this repository
        └── express-mock-media-server/      MEDIA_DIR
```

`./demo doctor` checks exactly those nine directories and three binaries. The other components are
run from inside their own checkouts, so they need no separate binary path.

Content lives outside this tree and is covered in section 4: `$MWC_CONTENT_ROOT/$DEMO_STREAM`
(required) and `$CONTENT_ROOT` (optional), both defaulting under `$HOME/MWC_TV_RADIO`.

If yours are elsewhere:

```bash
cp local.env.example local.env     # in this directory; it is gitignored
```

and set what differs. `REPOS_ROOT` alone is enough when they are grouped; individual variables
(`MBSF_DIR`, `GNB_BIN`, and so on) cover a component that sits somewhere the roots do not
explain. Environment variables work too, and win over `local.env`:

```bash
REPOS_ROOT=/srv/code ./demo up
```

`./demo doctor` lists every checkout and binary it cannot find, and names the variable that moves
each one, so a wrong layout is caught before anything starts.

### 4. Content

**Nothing here is downloadable and nothing is assumed to be on the machine already.** The directory
name is historical, after the event the line-up was first shown at; it does not name a content pack you
are missing.

What matters is what `./demo up` does with it. `up` runs the numbered scripts in order, and content
enters at two different points: `03-start-media-server.sh` **requires** a DASH package and stops the
run without one, while the live encoders started later **do not** require anything and generate a test
pattern if their source is absent. So of the two things under this directory, only the first is a
prerequisite for `./demo up`.

**Required: a DASH package at `$MWC_CONTENT_ROOT/$DEMO_STREAM`**, which defaults to
`~/MWC_TV_RADIO/dash/tv_1`. `03-start-media-server.sh` copies it into the origin and builds the
carousel manifest from what it finds, so without it `./demo up` stops at that step with
`content not found: <path>`. Any MP4 will do as the input; the demo does not care what the picture
shows:

```bash
mkdir -p ~/MWC_TV_RADIO/dash/tv_1 && cd ~/MWC_TV_RADIO/dash/tv_1
ffmpeg -y -f lavfi -i testsrc2=size=1280x720:rate=25 \
       -f lavfi -i sine=frequency=440:sample_rate=48000 -t 30 \
       -c:v libx264 -preset veryfast -pix_fmt yuv420p -g 50 -keyint_min 50 -sc_threshold 0 \
       -c:a aac -b:a 128k -shortest \
       -f dash -seg_duration 2 -use_template 1 -use_timeline 1 manifest.mpd
```

That produces `manifest.mpd`, `init-stream*.m4s` and `chunk-stream*.m4s`, which is the shape the media
server expects. Substitute `-i your-file.mp4` for the two `lavfi` inputs to use your own media.

**Optional: source clips at `$CONTENT_ROOT`**, which defaults to `~/MWC_TV_RADIO`, named `TV_1.mp4`,
`TV_2.mp4`, `TV_3.mp4` and `RADIO.mp4` after the `source` fields in `channels.json`. These feed the
looping live encoder, and **they are genuinely optional**: `live-encoder.sh` falls back to a generated
test pattern with a tone when the file is absent, logging `source: none at <path>, generating a test
pattern instead`. `./demo up` therefore starts and runs without them. Provide them only if you want specific content on
the live channels rather than a test pattern, or point `LIVE_SOURCE_MEDIA` at your own file. A radio
channel discards the video track either way.

To provide them anyway:

```bash
mkdir -p ~/MWC_TV_RADIO && cd ~/MWC_TV_RADIO
for f in TV_1 TV_2 TV_3 RADIO; do
  ffmpeg -y -f lavfi -i testsrc2=size=1280x720:rate=25 \
         -f lavfi -i sine=frequency=440:sample_rate=48000 \
         -t 60 -c:v libx264 -preset veryfast -pix_fmt yuv420p \
         -c:a aac -b:a 128k -shortest "$f.mp4"
done
```

`channels.json` is the line-up itself: four channels, all of them encoded and served by the
origin, and the `onAir` flag decides which are carried over the radio as their own MBS User
Service. One is on air here; `channels.json`'s own comment records why, and what happens if you
set a second.

Encoding four channels at once is the demo's heaviest steady-state cost. `DEMO_CHANNELS` limits
the run to the channel ids it names, space or comma separated, which is worth doing on a machine
where the UE struggles to attach:

```bash
DEMO_CHANNELS=mwc-tv-1 ./start-all.sh      # or: DEMO_CHANNELS=mwc-tv-1 ./demo up
```

## Running it

```bash
cd rt-mbs-examples/scripts/mbs-broadcast-demo
./start-all.sh
```

This runs, in order:

| # | Script | What it does |
|---|---|---|
| 00 | `00-setup-netns.sh` | Creates the `ns-gnb` network namespace + veth pair (idempotent; `--teardown` removes it) |
| 01 | `01-start-core-nfs.sh` | NRF, AUSF, UDM, UDR, PCF, NSSF, BSF, then UPF, SMF, AMF |
| 02 | `02-start-mbs-function.sh` | MBSTF, then MBSF |
| 03 | `03-start-media-server.sh` | Copies the demo DASH content into `express-mock-media-server/public/`, (re)generates its object-manifest carousel, starts the server |
| 04 | `04-start-ran.sh` | gNB and UE, both inside `ns-gnb`, over a ZMQ RF loopback |
| 05 | `05-start-client-and-app.sh` | rt-mbs-client + rt-mbs-application (both inside `ns-gnb`) + a socat relay so the dashboard is reachable from outside the namespace, and rt-mbs-application-provider on the host |
| 06 | `06-provision-live-service.sh` | What `start-all.sh` and `start-bypass-live.sh` both call: creates the live DASH MBS User Service and its Ingest Session through the application provider (OBJECT_STREAMING, the presentation manifest as entry point), then asks the MBS Client to join it |
| 06 | `06-provision-broadcast-service.sh` | The alternative, run on its own: a `servType: BROADCAST` User Service with a CAROUSEL/PULL Ingest Session from the media server, TMGI auto-allocated, through MBSF's own API |

Each script can also be run on its own (e.g. `./04-start-ran.sh` to restart just the RAN
after editing a config) -- they're idempotent about already-running components and check
their own prerequisites (`wait_for_tcp`/`wait_for_http` on the thing they depend on) rather
than assuming a fixed startup order was followed.

When it finishes, `start-all.sh` prints the URLs. The dashboard needs a few minutes after
step 06 before the service shows up -- the announcement carousel repeats every 10s, but a
small object still needs two source symbols to complete, and on a software-radio loopback
(no real RF, no HARQ retransmission for broadcast) that can take several repetitions before
both land cleanly. Give it 3-5 minutes before concluding something's wrong, watching
`run/logs/rt-mbs-client.log` for `"ingested announcement bundle"`.

Once the service shows up under the dashboard's own Services list, it is not played
automatically -- activate it once (this is the same thing the dashboard's own "Play" button
does):

```bash
curl "http://localhost:3050/api/services/activate?external-service-id=<the service's own extServiceId, URL-encoded>"
```

This joins the actual content Distribution Session; give it several more minutes for the
carousel (157 objects at this demo's own conservative bitrate, see Troubleshooting below) to
deliver the manifest and enough segments for playback to start. Watch progress with:

```bash
watch -n5 'curl -s http://localhost:3050/api/content | python3 -m json.tool'
```

```bash
./status.sh      # health check of every component + the provisioned session's own state
./stop-all.sh    # stop everything (add --netns to also remove the network namespace)
```

## UE pre-configuration for 5MBS (TS 24.575)

By default the client learns the Service Announcement channel from a deployment-fixed block in its
generated config: the address, port and TSI are written straight into `rt-mbs-client.conf`. That
works, but it is not how a UE is meant to find out.

3GPP TS 24.575 defines a pre-configuration object for exactly this. Clause 4: *"If the UE is
pre-configured with information related to services using MBS, the UE can discover and receive data
for services by using the provisioned configuration."* Per PLMN it carries the TMGIs on which the
service announcement is available, each with its USD, the TMGIs carrying the services themselves,
NR-ARFCNs, and a default DNN and S-NSSAI pair.

To run the demo that way instead:

```bash
UE_PRE_CONFIGURATION=1 ./start-all.sh
```

That makes `05-start-client-and-app.sh` write the object to `run/configs/ue-pre-configuration.json`,
**remove** the deployment-fixed `announcement_channel` block from the client's config, and point the
client at the object. The client then acquires the announcement from the object alone. In the log:

```
rt-mbs-client: UE pre-configuration loaded from .../ue-pre-configuration.json: 1 PLMN(s)
rt-mbs-client: UE pre-configuration provisions the service announcement on TMGI ... (PLMN 00101)
DistributionSessionReceiver: announcement-channel.sdp activating FLUTE session 232.0.0.1:3000 tsi=1
rt-mbs-client: acquired the service announcement for service ... from the UE pre-configuration
```

Two things about the generated object are worth knowing:

- **The USD is a real bundle entity.** TS 26.517 clause 5.3.1A requires that *"The Content-Type
  header of the entity shall be multipart/related"*, so the object's `usd` leaf carries a
  multipart/related entity whose root part is the User Service Descriptions document and whose
  second part is the SDP for this deployment's announcement channel. That is the same channel the
  fallback block describes, written the way the specification expects to find it.
- **The TMGI is illustrative here.** A real deployment fixes the TMGI in advance, which is the whole
  point of pre-configuration. This demo's MBSF allocates TMGIs when it creates the session, so no
  fixed value can be the real one, and the client acquires the announcement from the USD beside it.
  The value is written in `05-start-client-and-app.sh`; it has the structure TS 23.003 clause 30.2
  gives for an MBS TMGI, six hexadecimal digits of MBS Service ID, a three-digit MCC, then a two- or
  three-digit MNC.

Both paths are exercised: `./start-all.sh` runs the fallback path, `UE_PRE_CONFIGURATION=1
./start-all.sh` runs the specified one, and either delivers the same content.

The object can also be read and replaced while the client runs, which is what TS 24.575 clause 6.4's
*"Access Types: Get, Replace"* on `PLMNList` allows:

```bash
sudo ip netns exec ns-gnb curl -s http://127.0.0.1:3031/mbs-client-api/x-5gmag-ue-pre-configuration
```

`rt-mbs-application` shows the same object under its **UE Pre-configuration** tab.

## Why this exists, not the older `scripts/tmux/` tutorial scripts

`scripts/tmux/mbs-function-tutorial/mbs-function-tutorial.sh` covers only the backend NFs
(NRF..AMF, MBSTF, MBSF) with hardcoded paths from a different machine's checkout, and
assumes the gNB/UE/RAN side, the network namespace, and both web portals are started some
other way. This demo needed all of that scripted and reproducible from nothing, so it's a
separate, self-contained set of scripts rather than an edit to that one -- see this
project's own commit discipline on confining a diff to what an item actually needs.

## Why `INGEST_MAX_BITRATE` defaults to 500 Kbps, not this content's own ~9 Mbps requirement

`env.sh`'s `INGEST_MAX_BITRATE` governs the Distribution Session's own real on-air
transmission rate -- independently of `CAROUSEL_REPETITION_MS`, which only controls how
often each object gets refetched from the media server, not how fast MBSTF actually hands
data to the gNB. Measured on this rig: at `10 Mbps` (this content's own naive
"repeat everything every 30s" requirement), the gNB's own RLC queue backed up by several
megabytes within seconds and PDSCH CRC failures climbed above 90% -- **not because of a
decode bug, but because this demo's own software-radio loopback (no real RF, ordinary
development hardware) cannot keep up with that much real-time MBS scheduling.** Lowering
the cap to `500 Kbps` (and `CAROUSEL_REPETITION_MS` to a matching, much slower refetch
cadence) eliminated the drops and CRC failures entirely, repeatably. If you raise this value for a beefier
host or real RF hardware, watch `run/logs/gnb.log` for `"Dropped SDU"` and back off if you
see it.

## Troubleshooting

- **The radio is fine but the client receives nothing.** The symptom is
  `run/logs/rt-mbs-client.log` staying short with no `Received new FDT` lines, while
  `run/logs/ue_bcast.log` shows MCCH receptions and thousands of CRC-OK decodes, and the
  provisioning step ends with `no cached service with external service id ...`.

  The one diagnostic that settles it is what is actually on the wire:

  ```bash
  sudo timeout 10 ip netns exec ns-gnb tcpdump -i tun_bcastue -n udp
  ```

  A healthy run carries traffic to **both** `232.0.0.1:3000`, the Service Announcement, and
  `232.0.0.2`, the content. Seeing only the content means the announcement channel is not
  transmitting, so the client has nothing to learn the service from however healthy the radio is.
  Restart from a clean state:

  ```bash
  ./stop-all.sh
  sudo rm -rf run/state run/mbsf-cache
  ./start-all.sh
  ```

  Do **not** use `run/logs/mbsf.log`'s `MBS User Data Ingest Session [USER SERVICE ANNOUNCEMENT
  CHANNEL] does not exist` as the tell. That line appears in healthy runs too, and mistaking it for
  the cause sends you after the wrong thing.

- **"SSM 232.0.0.2 is already used by another Distribution Session"** during provisioning: a
  previous run's session is still registered. Same fix as above.

- **"tun_bcastue never got an address"** (`04-start-ran.sh`/`05-start-client-and-app.sh`):
  the UE didn't attach. Check `run/logs/ue_bcast.log` for NAS/RRC failures and
  `run/logs/gnb.log` for the corresponding cell-side view. A stale gNB or UPF process left
  running from a previous, differently-configured run is the most common cause -- run
  `./stop-all.sh` first.
- **`tun_bcastue got no address within Ns`** but `run/logs/ue.log` shows `PDU Session Establishment
  successful`: the UE attached, just later than the wait allowed. Raise `UE_TUN_WAIT_SECS` in
  `env.sh` (default 180) and re-run, or continue from `./05-start-client-and-app.sh` by hand, since
  the earlier steps are still up.
- **The UE never reaches random access at all** -- `run/logs/ue_bcast.log` stays empty, the
  UE's own `run/logs/ue.log` stops at `Attaching UE...`, and `run/logs/gnb.log` shows no RACH:
  check the machine's load average before looking at anything else. The gNB and UE are joined
  by a ZMQ virtual radio and both sides must keep up with the sample rate in real time, so on
  a loaded machine the link simply never carries a preamble. Observed on an 8-core machine: at
  a load average of 16-21 (a parallel `ninja` build alongside the demo) the UE never attached
  across three consecutive attempts; with the same binaries at a load average of about 3 it
  attached first time. Do not build and run the demo at once, and give the machine a moment to
  settle after a build before starting. If the machine is simply small, cut the encoder load with
  `DEMO_CHANNELS` (see Content above) rather than retrying.
- **UPF "Maximum number of MBS Sessions[20] reached"** (`run/logs/upf.log`): the UPF was
  never restarted across many test sessions and accumulated stale MBS session contexts.
  `./stop-all.sh` followed by `./start-all.sh` gives it a clean slate; there is no live
  "forget old sessions" API for this today.
- **Ingest Session creation returns no `Location` header** (`06-provision-broadcast-service.sh`):
  read `run/logs/mbsf.log` around the request time. A TMGI collision or a stuck previous
  session (SMF doesn't restart when MBSF/MBSTF do) both show here; a full `./stop-all.sh &&
  ./start-all.sh` clears both.
- **"Carousel maximum bit rate exceeded"** (`run/logs/mbstf.log`): the content's real byte
  total no longer fits `CAROUSEL_REPETITION_MS`/`INGEST_MAX_BITRATE` in `env.sh` (e.g. you
  pointed `DEMO_STREAM` at larger content). `03-start-media-server.sh` computes and checks
  this bound itself before writing the carousel file and refuses to write one that would
  overrun it -- raise `CAROUSEL_REPETITION_MS` (slower repetition) or `INGEST_MAX_BITRATE`
  (and pass the same higher value through to `06-provision-broadcast-service.sh`) and
  re-run `03-start-media-server.sh`.
- **Dashboard shows the old/wrong service, or nothing**: give it the ~10-15s carousel
  repetition window mentioned above first. If it's still stale, the announcement carousel
  may be serving a *different*, older ingest session's announcement that never got cleaned
  up -- check `run/mbsf-cache/` for more than one entry, and prefer a full restart over
  trying to delete just one stale session live.

## Running without the RAN: looping content over loopback

`start-bypass-live.sh` brings up the same service chain with no gNB or UE. MBSTF sends to the
SSM group on loopback and rt-mbs-client joins it there, so
rt-mbs-application-provider -> MBSF -> MBSTF -> rt-mbs-client -> rt-mbs-application runs end to
end without the radio. Use it when the radio is not what you are testing.

Unlike `start-all.sh`, the content **loops**: `live-encoder.sh` runs ffmpeg with
`-stream_loop -1` over the source file, writing a rolling DASH window, so segments keep being
produced instead of the presentation ending after one pass.

`live-carousel.sh` regenerates `public/carousel-live` from that window. It differs from
`07-live-carousel-regen.sh` in two ways that matter for a live stream:

- it advertises only the newest `LIVE_CAROUSEL_SEGMENTS` segments per representation rather
  than the encoder's whole window, so the sender is not spending its capacity re-transmitting
  segments that have already been delivered, and
- it repeats the bootstrap objects (the MPD and the initialisation segments) more often than
  the media window. MBSTF schedules by transmit deadline, so with everything on one interval
  the media segments -- always newer -- take the slots and a receiver can end up with media it
  cannot play because the manifest and initialisation segments never arrived.

Useful knobs, all environment variables:

| Variable | Default | Meaning |
|---|---|---|
| `LIVE_SEG_DURATION` | 5 | Encoder segment duration, and therefore the arrival pace |
| `LIVE_CAROUSEL_SEGMENTS` | 8 | Newest segments per representation advertised |
| `LIVE_REPETITION_MS` | 10000 | How often each advertised object repeats |
| `BYPASS_MAX_BITRATE` | 6 Mbps | Session maximum bit rate |
| `BYPASS_SERVICE_ID` | `.../services/tv_1_live` | External service identifier |

The service and ingest session are created **through the provider**, so its own UI lists them
rather than only MBSF knowing about them.

Checking it is working: segments should arrive one per `LIVE_SEG_DURATION`, and what the MBS
Client serves as a manifest should only ever name segments it holds.

```
curl -s http://127.0.0.1:3031/mbs-client-api/content | grep -o '"location":"[^"]*"' | wc -l
curl -s http://127.0.0.1:3031/mbs-client-api/content/tv_1_live/manifest.mpd
```

To stop: `./stop-all.sh`, then kill `live-encoder.sh` and `live-carousel.sh`, which run
independently of it.
