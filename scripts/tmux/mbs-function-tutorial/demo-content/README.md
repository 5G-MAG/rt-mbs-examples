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

Prerequisites: the stack is up (`../mbs-function-tutorial.sh`), the portal
(`rt-mbs-application-provider`) is reachable on its configured port (default
`:8081`), and its tab-dot connectivity indicators for MBSF/MBSTF are green.

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
