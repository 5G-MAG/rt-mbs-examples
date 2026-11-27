// Starts rt-media-origin on an ephemeral local port with media-origin.yaml and checks what the MBSTF
// relies on the media origin for: the media type of the object manifests and of a DASH manifest, the
// caching headers, conditional requests, and the chain of redirects. It needs an rt-media-origin that has
// the channel option output.defaultContentType. No dependency beyond Node itself.
//
//   MEDIA_ORIGIN_DIR=<rt-media-origin checkout, npm install done> node media-origin/test/media-origin.test.js
const assert = require('assert');
const fs = require('fs');
const http = require('http');
const net = require('net');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');

const originDir = process.env.MEDIA_ORIGIN_DIR;
if (!originDir || !fs.existsSync(path.join(originDir, 'bin', 'www'))) {
  console.error('set MEDIA_ORIGIN_DIR to an rt-media-origin checkout (bin/www not found there)');
  process.exit(2);
}
const here = path.join(__dirname, '..');
const MANIFEST_TYPE = 'application/3gpp-mbs-object-manifest+json;version="Rel17"';

function freePort() {
  return new Promise((resolve, reject) => {
    const s = net.createServer();
    s.once('error', reject);
    s.listen(0, '127.0.0.1', () => { const { port } = s.address(); s.close(() => resolve(port)); });
  });
}

function get(port, urlPath, headers) {
  return new Promise((resolve, reject) => {
    const req = http.request({ host: '127.0.0.1', port, path: urlPath, headers: headers || {} }, (res) => {
      res.resume();
      res.on('end', () => resolve({ status: res.statusCode, headers: res.headers }));
    });
    req.on('error', reject);
    req.end();
  });
}

async function waitUntilServing(port) {
  for (let i = 0; i < 100; i++) {
    try { if ((await get(port, '/object1')).status === 200) return; } catch (e) { /* not listening yet */ }
    await new Promise((r) => setTimeout(r, 100));
  }
  throw new Error('rt-media-origin did not start serving /object1 within 10 s');
}

let passed = 0;
async function check(name, fn) { await fn(); passed += 1; console.log('ok   ' + name); }

async function main() {
  // The fixtures plus one DASH manifest, in a scratch copy so the repository stays untouched.
  const publicDir = fs.mkdtempSync(path.join(os.tmpdir(), 'media-origin-test-'));
  fs.cpSync(path.join(here, 'public'), publicDir, { recursive: true });
  fs.mkdirSync(path.join(publicDir, 'tv'));
  fs.writeFileSync(path.join(publicDir, 'tv', 'manifest.mpd'), '<?xml version="1.0"?><MPD/>');
  fs.writeFileSync(path.join(publicDir, 'tv', 'chunk-stream0-00001.m4s'), 'segment');
  fs.writeFileSync(path.join(publicDir, 'tv', 'other.mpd'), '<?xml version="1.0"?><MPD/>');

  const port = await freePort();
  const server = spawn('node', ['bin/www'], {
    cwd: originDir,
    env: { ...process.env, PORT: String(port), HOST: '127.0.0.1', MEDIA_PUBLIC_DIR: publicDir,
           RT_MEDIA_SERVER_CONFIG: path.join(here, 'media-origin.yaml') },
    stdio: 'ignore',
  });
  try {
    await waitUntilServing(port);

    for (const name of ['collection-manifest', 'carousel-file-set']) {
      await check(`/${name}: 200 with the object manifest media type`, async () => {
        const r = await get(port, '/' + name);
        assert.strictEqual(r.status, 200);
        assert.strictEqual(r.headers['content-type'], MANIFEST_TYPE);
      });
    }

    await check('/tv/manifest.mpd: declared application/dash+xml, Cache-Control: no-cache', async () => {
      const r = await get(port, '/tv/manifest.mpd');
      assert.strictEqual(r.headers['content-type'], 'application/dash+xml');
      assert.strictEqual(r.headers['cache-control'], 'no-cache');
    });
    await check('/tv/other.mpd: the *.mpd pattern declares it too', async () => {
      const r = await get(port, '/tv/other.mpd');
      assert.strictEqual(r.headers['content-type'], 'application/dash+xml');
      assert.strictEqual(r.headers['cache-control'], 'no-cache');
    });
    await check('/tv/chunk-stream0-00001.m4s: the declared default, not the extension', async () => {
      const r = await get(port, '/tv/chunk-stream0-00001.m4s');
      assert.strictEqual(r.headers['content-type'], 'text/plain');
      assert.strictEqual(r.headers['cache-control'], 'max-age=30');
    });

    const obj = await get(port, '/object1');
    await check('/object1: text/plain, Cache-Control max-age=30, with an ETag and a Last-Modified', async () => {
      assert.strictEqual(obj.headers['content-type'], 'text/plain');
      assert.strictEqual(obj.headers['cache-control'], 'max-age=30');
      assert.ok(obj.headers.etag, 'no ETag');
      assert.ok(obj.headers['last-modified'], 'no Last-Modified');
    });
    await check('/object1: If-None-Match with its ETag gives 304', async () => {
      assert.strictEqual((await get(port, '/object1', { 'If-None-Match': obj.headers.etag })).status, 304);
    });
    await check('/object1: If-Modified-Since with its Last-Modified gives 304', async () => {
      assert.strictEqual((await get(port, '/object1', { 'If-Modified-Since': obj.headers['last-modified'] })).status, 304);
    });
    await check('/object1: a different If-None-Match gives 200', async () => {
      assert.strictEqual((await get(port, '/object1', { 'If-None-Match': 'W/"other"' })).status, 200);
    });

    for (const [from, status, to] of [['/object2', 302, '/real-object2'], ['/object3', 301, '/perm-object3'],
      ['/perm-object3', 302, '/real-object3'], ['/object4', 302, '/temp-object4'], ['/temp-object4', 301, '/real-object4']]) {
      await check(`${from}: ${status} to ${to}`, async () => {
        const r = await get(port, from);
        assert.strictEqual(r.status, status);
        assert.strictEqual(new URL(r.headers.location, 'http://x').pathname, to);
      });
    }
    for (const name of ['real-object2', 'real-object3', 'real-object4']) {
      await check(`/${name}: 200 (the end of the chain)`, async () => {
        assert.strictEqual((await get(port, '/' + name)).status, 200);
      });
    }
    console.log(`media-origin.test.js: ${passed} cases checked`);
  } finally {
    server.kill();
    fs.rmSync(publicDir, { recursive: true, force: true });
  }
}

main().catch((err) => { console.error(err); process.exitCode = 1; });
