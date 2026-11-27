# Media origin for the MBS examples

[rt-media-origin](https://github.com/5G-MAG/rt-media-origin) serves the objects the MBSTF pulls.
[`media-origin.yaml`](./media-origin.yaml) configures it and [`public/`](./public/) holds fixture objects for
testing the MBSTF; the demos add their own content beside them (not committed).

## Run

Set `MEDIA_ORIGIN_DIR` to your rt-media-origin checkout (`npm install` done), then, from this folder:

```
MEDIA_PUBLIC_DIR=$PWD/public RT_MEDIA_SERVER_CONFIG=$PWD/media-origin.yaml node "$MEDIA_ORIGIN_DIR/bin/www"
```

It listens on all addresses, port 3004 (`HOST` and `PORT` change that).

Docker: build the image from the rt-media-origin checkout (`docker/Dockerfile`), mount `media-origin.yaml` as
`RT_MEDIA_SERVER_CONFIG` and `public/` as `MEDIA_PUBLIC_DIR`. [`mbs-deployment`](../mbs-deployment/) does this,
with the paths from `COMPILE_PATH` in its `.env`.

## Formats

The configuration declares the Content-Type and Cache-Control of everything served; no file extension is
consulted:

- `defaultContentType` and `defaultCacheControl` apply to every object not matched below;
- `pathOverrides` name a file or a pattern (`*`, `?`), first match wins: the object manifests and `*.mpd`.

To serve other formats, copy `media-origin.yaml`, edit the copy and use it: `MEDIA_ORIGIN_CONFIG` in the demo,
`RT_MEDIA_SERVER_CONFIG` when you start the origin yourself. Use an rt-media-origin that has
`output.defaultContentType`.

## Your own videos

Section 4 of the [broadcast demo README](../scripts/mbs-broadcast-demo/README.md#4-content).

## Test

```
MEDIA_ORIGIN_DIR=<your rt-media-origin checkout> node media-origin/test/media-origin.test.js
```
