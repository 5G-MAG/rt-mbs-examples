# demo-content — loadable MBS demo templates

Templates that broadcast a video source over 5G MBS, loaded into the running
`rt-mbs-application-provider` portal. Each template creates an MBS **User
Service** and one or more **Ingest Sessions**; MBSF/MBSTF ingest the source,
FLUTE-deliver it, and (once you Activate) it goes out over the MBS
distribution session -- see the parent tutorial's `mbs-function-tutorial.sh`
for bringing up the rest of the stack (NRF/SCP/MB-SMF/MB-UPF, MBSTF, MBSF).

`dash-if-demo.json` is a ready example: a live **DASH** stream (DASH-IF's
`livesim2` WAVE test vector, "croatia" 1920x1080@25fps) via one Ingest Session
in **PULL**/**STREAMING** mode (MBSTF fetches the manifest + segments directly
and re-polls for new live segments). This exact template was verified
end-to-end: real content received by `rt-mbs-client` and played back through
`rt-mbs-application`, byte-for-byte matched against the source via MD5.

## Load a template

**From the portal (easiest):** open `rt-mbs-application-provider`'s single
tab -> open (or create) an MBS User Service -> **Load Template** -> pick a
`.json` file here (e.g. `dash-if-demo.json`). It creates one Ingest Session
under the currently open service and opens it so you can review it.

**From the CLI (headless), creating both the Service and its Session(s)
fresh:**

```bash
cd demo-content
node load-demo.js dash-if-demo.json
```

This reads the portal host/port and Basic-auth credentials from
`~/rt-mbs-application-provider/.env` (override with `PORTAL_ENV=/path`).

Either way it **only creates** the service/session, always `INACTIVE` --
it does **not** activate anything. Open the portal, review, and set the
distribution session state to `ACTIVE` (Save again to confirm) to actually
start delivery.

Prerequisites: the stack is up (`../mbs-function-tutorial.sh`, which itself needs MB-UPF's
`ogstun` interface configured -- see that script's `OPEN5GS_NETCONF_SCRIPT` setting), the portal
(`rt-mbs-application-provider`) is reachable on its configured port (default `:8081`), and its
tab-dot connectivity indicators for MBSF/MBSTF are green.

## Seeing it actually play (the parts this repo doesn't run for you)

Loading and activating a session (above) only gets content as far as MBSTF distributing it.
Two more components, from two other repos, are what actually receive and show it:

```bash
# 1. rt-mbs-client (the MBS Client -- MBSF Client + MBSTF Client subfunctions)
cd rt-mbs-client
./build/mbs-client run/rt-mbs-client.conf

# 2. rt-mbs-application (the MBS-Aware Application dashboard + player)
cd rt-mbs-application
npm start
```

Then open `rt-mbs-application` (default `:3050`) -- Client tab shows discovered services,
the received-object cache, and the last Service Announcement bundle; the Application tab is
the DASH/HLS player. If the Play button doesn't do anything, jump straight to
`http://localhost:<port>/application?p=dash&m=%2Fapi%2Fcontent%2F<manifest-path>`.

### How delivery actually reaches the client

MBSTF tunnels content to MB-UPF (`ingressTunAddrReq`, always requested); MB-UPF forwards it per
the 3GPP-standard **FSSM** PFCP Apply Action (TS 29.244, "Forward packets to lower layer SSM").
**Per spec, FSSM output is genuine GTP-U**: MB-UPF wraps the data in a GTP-U header carrying a
"GTP-U Common TEID" (C-TEID) and sends it to a "Low Layer Source Specific Multicast" (LLSSM)
address that MB-UPF itself allocates -- deliberately distinct from the multicast address the AF/
MBSF configured for the FLUTE session. In open5gs this is real code, not a paper mechanism: the
FSSM Apply Action (`lib/pfcp/handler.c`) calls the exact same GTP-U send path
(`ogs_pfcp_send_g_pdu` -> `ogs_gtp2_send_user_plane`, `lib/pfcp/path.c`) used for ordinary per-UE
GTP-U forwarding.

**Verified on the wire in this exact tutorial setup** (unfiltered capture during a live DASH-IF
session, decoded byte-for-byte): MB-UPF genuinely emits this GTP-U traffic. A packet captured
going to `239.0.0.5:2152` (source `127.0.0.7`, MB-UPF) decodes as `30 ff <len> <teid>` -- GTPv1,
message type `0xff` (G-PDU), a real TEID -- with the *entire original multicast datagram*
(source `127.0.0.50`, dest `232.50.0.1`, the AF/MBSF-configured FLUTE SSM) as its payload. That's
TS 29.244's FSSM mechanism exactly as specified, running live, not just present in the code.

**`rt-mbs-client` never touches any of that.** It subscribes directly to the FLUTE-layer address
(`232.50.0.1`, via `flute_iface`) and a plain, unencapsulated copy of the same datagram is also
observed there independently of the GTP-U/LLSSM stream -- confirmed by decoding the inner payload
of the GTP-U packet and finding it byte-identical to what arrives on `232.50.0.1` directly. Per
TS 23.247, decapsulating N3mb's GTP-U is NG-RAN's job (Shared MBS Traffic Delivery terminates at
NG-RAN, which delivers to the UE over the radio interface) -- the MBS Client (this repo) is a
UE-side, above-radio component and is never specified to see GTP-U or the LLSSM address at all.
Exactly which UPF code path re-emits the plain copy (as opposed to routing only through the
GTP-U/FAR path) wasn't traced further -- it doesn't change what the client needs to do, which is
simply to keep subscribing to the FLUTE-layer address it always has.

Note also that `flute_iface` is consumed as an **IP address**, not an interface name, despite the
parameter name (`rt-mbs-client/lib/libflute/src/Receiver.cpp`'s `join_group`/
`IP_ADD_SOURCE_MEMBERSHIP` calls both run it through `boost::asio::ip::make_address(iface)`) --
`"lo"` only "works" here because loopback's own address `127.0.0.1` is what's meant, not the
interface name itself. Across real hosts, what matters is that the network between wherever the
FLUTE-layer multicast actually originates and the receiver is genuinely multicast-capable (IGMP
allowed through firewalls, a querier present if switches do IGMP snooping, correct TTL).

### Known gotchas

- **A one-shot object (e.g. a DASH initialization segment) can get evicted from
  `rt-mbs-client`'s cache if nothing requests it for a while** (its eviction policy is
  LRU-by-last-access, not age-based, precisely so an actively-used object survives -- but an
  object nothing is asking for, e.g. because the player errored out and stopped fetching, looks
  idle and can get evicted like anything else). If playback breaks with "segment not available"
  after a gap, delete and recreate the Ingest Session (rather than just re-activating the
  existing one) so MBSTF re-fetches and re-sends everything fresh, including the init segment,
  while the client is actively listening.
- **MBSTF can crash** (`Fatal glibc error: tpp.c:83`, tracked at
  [5G-MAG/rt-mbs-transport-function#68](https://github.com/5G-MAG/rt-mbs-transport-function/issues/68),
  not yet fixed) shortly after a session activates. If it happens, restarting just MBSTF often
  isn't enough -- MBSF can hang trying to reach the now-dead MBSTF, and MB-SMF may reject
  re-creating a session with a "Duplicate MBS Session ID" error since it doesn't get cleaned up
  either. A full stack restart (`../mbs-function-tutorial.sh` again) is the reliable recovery.

## What the fields mean

`dash-if-demo.json` uses the same flat, form-shaped fields the portal's own
"New Ingest Session" form uses (not MBSF's raw nested wire format) -- both the
browser's "Load Template" button and this directory's `load-demo.js`
translate them into the real `mbsDisSessInfos`-wrapped request body.

| Field | Meaning |
| --- | --- |
| `service.*` | The MBS User Service (external service id, class, announcement modes, name/description). |
| `sessions[].distSessKey` | The `mbsDisSessInfos` map key for this distribution session, e.g. `AP_MBS_SESSION_1`. |
| `sessions[].sourceIp` / `destIp` | The SSM source/destination IP MBSF allocates the session under. MBSF rejects a repeat of a (source, destination) pair it has already seen -- even from an unrelated, already-deleted session -- so give each concurrent session a distinct pair. |
| `sessions[].acqMethod` | `PULL` (MBSTF fetches `ingUri`/`acqIds`) or `PUSH` (you push content to an MBSTF-provided URL after creating the session). |
| `sessions[].ingUri` / `acqIds` | The PULL-mode origin base URL and the object id(s) under it (e.g. a DASH/HLS manifest) to acquire and broadcast. |
| `sessions[].distSessState` | Always forced to `INACTIVE` on load regardless of what's written here -- activation is a deliberate, separate step. |

## Make your own

Copy `dash-if-demo.json`, then change `sessions[0].ingUri`/`acqIds` to your
own source, and give it a distinct `sessions[0].sourceIp`/`destIp` pair if you
run several sessions at once (see the field table above for why).

## Note on content rights

`dash-if-demo.json` points at a third-party (DASH-IF) public test stream --
fine for a closed lab test, but broadcasting third-party content beyond that
needs rights clearance. Swap in your own source for anything non-lab.
