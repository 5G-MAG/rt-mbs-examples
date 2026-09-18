# Tutorial: MBS User Services

How to define and run an **MBS User Service**: what a service and its Ingest Session are, how the
operating mode decides what actually gets delivered, and how to provision both from
**rt-mbs-application-provider** rather than from a script.

For the whole stack including the gNB and UE, see
`scripts/mbs-broadcast-demo/README.md`, the end-to-end tutorial. This one stays on the service layer
and uses the RAN-free path so nothing radio-related gets in the way.

## What you are creating

Two resources, in this order:

- an **MBS User Service**, the thing announced to receivers. It carries the external service id a
  client matches on, the service class, and how it is announced.
- an **MBS User Data Ingest Session** beneath it, which says where the content comes from and how
  it is distributed: the operating mode, the acquisition method and entry point, the SSM address
  pair, and the bit rate ceiling.

The provider plays the MBS Application Provider role, so both are its to define. A template is
just a JSON file holding those two blocks, so you do not have to fill the forms by hand.

`bypass-live-dash.json` describes a live DASH service. The file is loaded twice, once per card:
the **MBS User Services** card reads its `service` block, and the **Ingest Sessions** card reads
its `sessions` array.

## 1. Start the systems

```bash
cd scripts/mbs-broadcast-demo
./start-systems.sh
```

This brings up the core network functions, the MBSF and MBSTF, the media server, a looping live
DASH encoder, the MBS Client, the application and the provider, and then stops. No service and no
session are created: that is what you are about to do yourself.

It resets anything already running first, so it is safe to run twice. It also checks every binary
and command it needs before starting anything, and names the build command for whatever is
missing.

If no source video is present it encodes a generated test pattern, so this works on a fresh
checkout. To use your own content:

```bash
LIVE_SOURCE_MEDIA=/path/to/your.mp4 ./start-systems.sh
```

## 2. Create the service

Open the provider at **http://127.0.0.1:8091/** (login `admin` / `testtoken123`).

On the **MBS User Services** card, choose **Load Template** and pick
`rt-mbs-examples/templates/bypass-live-dash.json`. The service is created immediately and opened,
and the **Ingest Sessions** card appears below it.

## 3. Create the ingest session

With that service open, choose **Load Template** on the **Ingest Sessions** card and pick the same
file. The session is created **INACTIVE** on purpose, so you can look at it before anything is
transmitted.

Read the **Operating mode** field and its note. This is the setting that most often goes wrong:

- **STREAMING** is what this template uses, and what 3GPP recommends for DASH. It follows the
  presentation manifest, so new segments are picked up as they are published and each object is
  sent once, timed against its own availability.
- **CAROUSEL** repeats a fixed object list. It is right for the User Service Announcement Channel,
  which the MBSF runs by itself, and wrong for live media: it re-sends what the receiver already
  has while never picking up what is new.
- **COLLECTION** distributes a fixed set once. **SINGLE** distributes one object.

Note also **Object IDs to pull**: for STREAMING this is the presentation manifest itself
(`tv_1_live/manifest.mpd`), not a list of segments.

## 4. Activate the session

Set the session state to **ACTIVE** and save. Saving is the activation control here, so the change
arms a confirm banner and a second click on Save applies it.

The sending side is then running:

1. the MBSF announces the service on the User Service Announcement Channel,
2. the MBSTF pulls the manifest, follows it, and sends each segment over FLUTE.

## 5. Join it on the receiving side

Open the application at **http://127.0.0.1:3050/**. The MBS Client has by now learned the service
from the announcement, so it appears in the service list; press **Activate** on it.

A client does not join an announced service by itself, which is the point of the announcement: the
service is advertised to everyone, and each receiver decides whether to join. On activation the
client learns that session's own multicast address, port and TSI from the announcement rather than
from any local configuration, joins, stores what arrives, and serves a manifest describing exactly
what it holds.

Then play it from the same application.

To see the delivery itself:

```bash
# objects the client currently holds
curl -s http://127.0.0.1:3031/mbs-client-api/content | grep -o '"location":"[^"]*"' | wc -l

# the manifest the client serves to the player
curl -s http://127.0.0.1:3031/mbs-client-api/content/tv_1_live/manifest.mpd
```

The object count settles rather than growing: the client drops each object once the availability
end time signalled for it has passed, and that time comes from the presentation's own
`@timeShiftBufferDepth`.

## Things to try

**Different content already on the media server.** Put a DASH presentation under
`express-mock-media-server/public/` and point the session's *Object IDs to pull* at its manifest.
To skip the encoder entirely:

```bash
LIVE_PRESENTATION=my_channel/manifest.mpd ./start-systems.sh
```

**A different operating mode.** Three more templates in this directory cover the other cases, and
load exactly the same way as `bypass-live-dash.json`:

| Template | Mode | What it is for |
|---|---|---|
| `bypass-live-dash.json` | OBJECT_STREAMING | A DASH or HLS presentation. The transport function follows the manifest and sends each newly published segment once. |
| `carousel-file-set.json` | OBJECT_CAROUSEL | A fixed file set, repeated on a cycle, so a receiver joining at any moment eventually gets all of it. |
| `single-file-download.json` | OBJECT_SINGLE | One object, sent once, to receivers already listening. Change `opMode` to `COLLECTION` to send several related objects once as a set. |
| `packet-forwarding.json` | PACKET distribution method | A stream already packetised at the source, carried through rather than delivered as objects. None of the object parameters apply. |

The carousel and single-file templates also set `fecConfig`. Broadcast has no retransmission, so an
object is recovered only if every one of its blocks arrives; FEC adds repair symbols to survive
residual loss, at the cost of bearer capacity. It matters most where nothing repeats. Remove the
block for no FEC.

**The reception buffer.** The backstop cap is visible and settable at
`http://127.0.0.1:3031/mbs-client-api/x-5gmag-reception-config`:

```bash
curl -s http://127.0.0.1:3031/mbs-client-api/x-5gmag-reception-config
curl -s -X PUT -H 'Content-Type: application/json' \
     -d '{"maxStoredObjects": 120}' \
     http://127.0.0.1:3031/mbs-client-api/x-5gmag-reception-config
```

That is a backstop only, for a sender that signals no availability end time; it is not the normal
retention mechanism.

## If something does not work

**"Cannot allocate TMGIs".** The MB-SMF holds a pool of 20 and only releases one when its expiry
passes, so repeated create/delete cycles exhaust it. Restart the SMF:
`pkill -x open5gs-smfd && ./01-start-core-nfs.sh`.

**"already used in another UserDataIngSession".** A previous Distribution Session still holds that
SSM. Run `./stop-all.sh` and start again, or delete the old session in the provider.

**The session is ACTIVE but nothing arrives.** Check that the media server is serving the
manifest you pointed at (`curl -s http://127.0.0.1:3004/tv_1_live/manifest.mpd | head`), then look
at `scripts/mbs-broadcast-demo/run/logs/mbstf.log`.

**Everything at once.** `./stop-all.sh` stops every process this demo started, the encoder
included.

## Other templates

`scripts/tmux/mbs-function-tutorial/demo-content/` carries two more, `dash-if-demo.json` and
`dash-if-live-demo.json`, which belong to the tmux tutorial and point at DASH-IF's public streams.
They load the same way.

## Just show me the video

`./start-bypass-live.sh` is the same bring-up with the service and session created for you.
