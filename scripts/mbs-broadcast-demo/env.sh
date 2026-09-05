#!/bin/bash
# Shared configuration for the MBS Broadcast end-to-end demo scripts (00-09 below).
# Source this file, don't execute it: `source env.sh`.
#
# All paths default to this development machine's actual checkout layout. If you clone
# these repositories somewhere else, edit REPOS_ROOT/RAN_ROOT (and RTMBS_ROOT if it moves
# out from under REPOS_ROOT) below -- everything else is derived from those two.

set -a

# ------------------------------------------------------------------------------------
# Repository locations
# ------------------------------------------------------------------------------------
REPOS_ROOT="${REPOS_ROOT:-$HOME/Repos}"
RTMBS_ROOT="${RTMBS_ROOT:-$REPOS_ROOT/rt-mbs}"
RAN_ROOT="${RAN_ROOT:-$REPOS_ROOT}"                 # parent of srsRAN_Project_mbs / srsRAN_4G_mbs

OPEN5GS_DIR="$REPOS_ROOT/open5gs"
MBSTF_DIR="$RTMBS_ROOT/rt-mbs-transport-function"
MBSF_DIR="$RTMBS_ROOT/rt-mbs-function"
CLIENT_DIR="$RTMBS_ROOT/rt-mbs-client"
APP_DIR="$RTMBS_ROOT/rt-mbs-application"
PROVIDER_DIR="$RTMBS_ROOT/rt-mbs-application-provider"
MEDIA_DIR="$RTMBS_ROOT/rt-mbs-examples/express-mock-media-server"
GNB_DIR="$RAN_ROOT/srsRAN_Project_mbs"
UE_DIR="$RAN_ROOT/srsRAN_4G_mbs"

# Binaries (built positions, not an `install/` staging tree -- matches how every one of
# these repos is actually built and run in this project today: in-tree `build/`, no `make
# install` step).
OPEN5GS_BUILD="$OPEN5GS_DIR/build"
MBSTF_BUILD="$MBSTF_DIR/build"
MBSF_BUILD="$MBSF_DIR/build"
GNB_BIN="$GNB_DIR/build/apps/gnb/gnb"
UE_BIN="$UE_DIR/build/srsue/src/srsue"
CLIENT_BIN="$CLIENT_DIR/build/mbs-client"

# ------------------------------------------------------------------------------------
# Run-time state: configs, logs, pidfiles, content -- all under this script directory's
# own `run/` subdirectory, not /tmp and not scattered across the source trees.
# ------------------------------------------------------------------------------------
DEMO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_DIR="$DEMO_ROOT/run"
CONF_DIR="$DEMO_ROOT/configs"          # static, git-tracked config templates
GEN_CONF_DIR="$RUN_DIR/configs"        # generated, per-run copies (gitignored)
LOG_DIR="$RUN_DIR/logs"
PID_DIR="$RUN_DIR/pids"
MBSF_CACHE_DIR="$RUN_DIR/mbsf-cache"
STATE_DIR="$RUN_DIR/state"             # IDs of the service/session this run created

# ------------------------------------------------------------------------------------
# Network namespace / RAN-side topology
#
# The gNB, UE, rt-mbs-client and rt-mbs-application all run inside one Linux network
# namespace (`ns-gnb`) so the UE's own PDU-session TUN device (`tun_bcastue`) and the
# ZMQ RF loopback between gNB and UE stay isolated from the host's routing table. The
# 5G core network functions (NRF..UPF, MBSF, MBSTF) run in the *root* namespace on
# 127.0.0.0/8 loopback addresses (no netns needed for them -- the whole 127.0.0.0/8
# range is usable without adding addresses). A veth pair crosses the boundary for N2/N3
# (AMF NGAP + UPF GTP-U).
# ------------------------------------------------------------------------------------
NETNS=ns-gnb
VETH_ROOT=veth-h        # root-namespace end
VETH_NS=veth-g          # ns-gnb end
VETH_ROOT_ADDR=10.99.0.1
VETH_NS_ADDR=10.99.0.2
VETH_PREFIX=30

# 5GC control-plane addresses (loopback, root namespace)
NRF_ADDR=127.0.0.10
AUSF_ADDR=127.0.0.11
UDM_ADDR=127.0.0.12
PCF_ADDR=127.0.0.13
NSSF_ADDR=127.0.0.14
BSF_ADDR=127.0.0.15
UDR_ADDR=127.0.0.20
AMF_ADDR=127.0.0.5
SMF_ADDR=127.0.0.4
UPF_ADDR=127.0.0.7
MBSF_ADDR=127.0.0.67
MBSAF_ADDR=127.0.0.67    # MBSF's own status-announcement listener shares its host address
MBSTF_SBI_ADDR=127.0.0.59
MBSTF_DISTSESSION_ADDR=127.0.0.62
MBSTF_INGEST_ADDR=127.0.0.61
SBI_PORT=7777

PLMN_MCC=001
PLMN_MNC=01
TAC=1

# rt-mbs-client / rt-mbs-application (inside ns-gnb)
MBS_CLIENT_API_PORT=3031
APP_PORT=3050
RADIO_API_PORT=3011

# rt-mbs-application-provider (root namespace / host)
PROVIDER_PORT=8091
PROVIDER_AUTH_USER=admin
PROVIDER_AUTH_TOKEN=testtoken123

# Media server (root namespace / host -- reached by MBSTF, which also runs in the root
# namespace, over loopback; the UE/client side never talks to it directly, only via
# FLUTE carried over the veth pair once MBSTF has pulled and carouselled the content)
MEDIA_HOST=127.0.0.1
MEDIA_PORT=3004

# Content: MWC TV/Radio DASH package this demo carousels. Read-only source; scripts copy
# from here, never write into it.
MWC_CONTENT_ROOT="$HOME/MWC_TV_RADIO/dash"
# Source file the looping live encoder (live-encoder.sh) plays on repeat, and the name of the
# presentation it writes under the media server's public directory. Both are named here rather
# than inside that script so the bypass demo's ingest session and its encoder cannot disagree
# about which presentation they mean, and so a deployment holding its content elsewhere overrides
# one variable instead of editing a script.
LIVE_SOURCE_MEDIA="${LIVE_SOURCE_MEDIA:-$HOME/MWC_TV_RADIO/TV_1.mp4}"
LIVE_STREAM_NAME="${LIVE_STREAM_NAME:-tv_1_live}"
# The demo distributes the full tv_1 package: 157 objects, ~33 MB.
#
# Trimmed variants (tv_1_short, tv_1_micro) previously stood in for it because the full package
# never achieved full coverage: the FDT was invalidated before it could finish, and the carousel
# starved its own largest objects. Both causes have since been fixed in the transport function
# (FDT instances are retained across a carousel repetition, and the transmit window no longer
# inverts for the largest objects), so the reason for cutting the content down no longer applies.
DEMO_STREAM=tv_1
# maxContBitRate governs the Distribution Session's own real on-air transmission-rate
# cap, independent of CAROUSEL_REPETITION_MS (which only controls how often MBSTF
# refetches each object from origin, not the transmitter's own pacing). Found live this
# session: at 10 Mbps, MBSTF handed content to the gNB faster than this test rig's
# ZMQ RF loopback could keep up with in real time, overflowing the RLC queue (tens of
# thousands of dropped SDUs observed) and coinciding with a high PDSCH CRC failure rate.
# 500 Kbps/2 Mbps/800 Kbps were all tried under this fork's own default *adaptive* MCS
# scheduling (greedy, picks the highest MCS/code rate that fits the pending bytes) --
# that scheduling choice itself was the deeper problem: its own content-session CRC
# failure rate ran close to 50% live, independent of bitrate. Fixed properly in
# srsRAN_Project_mbs (mbs_session_fallback_scheduler.cpp: honouring
# scheduler_mbs_session_expert_config's own mbs_use_fixed_mcs, fixed at MCS 18 -- a
# deliberate middle point, not a table lookup, chosen and verified live rather than
# guessed): CRC success measured at 94% (33/35) with this fix, versus ~50% before.
# MCS 18's own real throughput ceiling was then measured live the same way as before
# (bytes granted / wall time for the content session's own G-RNTI): ~382 Kbps, not
# 800 Kbps -- confirmed by 800 Kbps overflowing the RLC queue again (641 SDUs dropped)
# even with the reliability fix in place. 300 Kbps sits with real margin under that
# measured ceiling.
# NOTE: the ~382 Kbps ceiling recorded above was measured on a build where the MBS session
# scheduler progressively starved itself of grants (per-slot mbs_session_grants list was never
# reset, so each slot became permanently unschedulable once it filled). With that fixed, the
# real ceiling needs re-measuring before this value can be treated as the rig's actual limit.
# Overridable so it can be measured without editing this file.
INGEST_MAX_BITRATE="${INGEST_MAX_BITRATE:-2 Mbps}"
# What actually paces a carousel is this interval, not the bit-rate ceiling: the whole object set
# is re-sent once per interval, so the delivered rate is (total carousel bytes / interval) and the
# ceiling only bounds it. tv_1 is ~33 MB, so 300 s asks for about 880 kbps and 150 s for about
# 1.76 Mbps; the ceiling above leaves headroom over the former without inviting the latter.
# A receiver joining at an arbitrary moment needs one full interval to reach complete coverage,
# which is the cost of carouselling a package this size. Both values are overridable so the rate
# this rig actually sustains can be measured rather than assumed.
CAROUSEL_REPETITION_MS="${CAROUSEL_REPETITION_MS:-300000}"

# Live-looping demo content (07-live-carousel-regen.sh plus an ffmpeg live-DASH encoder, following
# the pattern in rt-mbms-examples/flute-ffmpeg/files/ffmpeg-dash.sh). The encode is ~400 Kbps video
# plus 64 Kbps audio, ~464 Kbps native. Unlike the static content above, this path is the loopback
# bypass, so no RAN throughput ceiling constrains it and the 300 Kbps budget used there does not
# apply.
#
# This is the ceiling declared as the ingest session's maxContBitRate, and it has to hold against a
# rate that is not the native encode rate: 07-live-carousel-regen.sh derives one repetitionInterval
# per cycle from the window's byte total at that moment, while MBSTF re-reads that value only on its
# next manifest poll (ObjectCarouselPackager.cc computes total_bit_rate from whichever value it
# currently holds). Between the two, a growing live window makes the interval it holds too short for
# the bytes now present, so the implied rate can exceed what the interval was computed for.
# Exceeding the declared ceiling makes ObjectCarouselPackager reject each cycle, and the resulting
# notification rate can exhaust the SBI message pool.
#
# No spec clause governs this value (rule 12): it is an engineering choice, set far enough above any
# total this encode's window (10+5 segments at ~464 Kbps native) can imply that the drift above
# cannot reach it, rather than close enough to need re-tuning whenever the window changes shape.
LIVE_INGEST_MAX_BITRATE="12 Mbps"

# Broadcast Distribution Session SSM (source-specific multicast) source/destination.
# MBSF's own mbsf.yaml carries these same values under broadcastDistribution -- the
# ingest-session provisioning request (06-provision-broadcast-service.sh) must supply the
# same pair as the session's own mbsSessionId.ssm, together with locationDependent:true,
# so MBSF's SDP builder (UserServiceAnnBundle.cc) has a real origin/connection-info pair
# to serialise while MB-SMF still allocates a genuine TMGI for over-the-air delivery (see
# that script's own header comment for the full explanation).
BCAST_SSM_SOURCE=127.0.0.68
BCAST_SSM_DEST=232.0.0.2

# Extra gNB CLI arguments. `cu_cp` selects the CU-CP subcommand.
#
# The multicast test/dev subcommand `test_only_mbs` is deliberately NOT in this default. Every option
# under it is multicast (--test_only_multicast_g_rnti, the five --multicast_drx_*,
# --test_only_multicast_mrb_lcid and its RLC t-Reassembly) and each is translated into
# mbs.multicast_cfg.*, which nothing on the broadcast path reads. A broadcast-only gNB does not define
# the subcommand at all and refuses to start when given it ("The following argument was not expected:
# test_only_mbs"), which is what this demo runs against.
#
# For a multicast-capable gNB that expects the subcommand, override:
#   GNB_EXTRA_ARGS="cu_cp test_only_mbs" ./start-all.sh
GNB_EXTRA_ARGS="${GNB_EXTRA_ARGS:-cu_cp}"

# MBS User Service / Ingest Session identity for this demo
DEMO_SERVICE_EXT_ID="https://mwc-tv-radio.ebu.io/services/${DEMO_STREAM}"
DEMO_SERVICE_NAME="MWC TV 1"
DEMO_SERVICE_DESC="MWC demo TV channel, carouselled from rt-mbs-examples/express-mock-media-server"

set +a
