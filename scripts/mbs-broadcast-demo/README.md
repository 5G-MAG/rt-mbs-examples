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

- `tmux` is **not** required (unlike `scripts/tmux/mbs-function-tutorial/`) -- everything
  here runs as background processes with per-component log files, so you can watch any one
  of them with `tail -f run/logs/<name>.log`.
- Passwordless (or cached) `sudo` -- needed for network-namespace management and the UPF's
  TUN device. The scripts call `sudo -v` up front so you're prompted once if needed.
- Built binaries for every component listed in `env.sh` (`open5gs`, `rt-mbs-transport-function`,
  `rt-mbs-function`, `rt-mbs-client`, `srsRAN_Project_mbs`, `srsRAN_4G_mbs`) -- these scripts
  run what's already built, they don't build anything.
- `node`/`npm`, `python3`, `curl`, `mongod` running (checked/started automatically for
  `mongod` if inactive; NRF/UDR need it).
- Content is **optional**. `start-all.sh` carousels the DASH package at
  `~/MWC_TV_RADIO/dash/<stream>/` (change `MWC_CONTENT_ROOT`/`DEMO_STREAM` in `env.sh`). The
  live paths encode a looping stream instead, and if no source file is present they generate a
  test pattern, so a fresh checkout runs with no content at all. Point `LIVE_SOURCE_MEDIA` at
  your own file, or `LIVE_PRESENTATION` at a DASH presentation already under the media server.

If your checkout layout differs from `$HOME/Repos/...`, edit `REPOS_ROOT`/`RAN_ROOT` at the
top of `env.sh` -- every other path is derived from those two.

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
  settle after a build before starting.
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
