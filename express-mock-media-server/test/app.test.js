// Minimal smoke test: plain `assert`, no test framework dependency -- matches the convention
// already established for rt-mbs-application-provider's and rt-mbs-application's own test files.
const assert = require('assert');
const http = require('http');
const app = require('../app');

// isNotModifiedSince() unit tests: exercised directly, not only through the live server, since
// express.static's own built-in lastModified/etag handling (both enabled in app.js) already
// produces a correct 304/200 decision on its own and would mask a broken comparison here
// entirely -- confirmed directly while fixing this: the live server's own observable response
// was unaffected by the bug either way, because of that independent, already-correct mechanism.
// A pair of dates was needed whose lexicographic string order (the original, buggy comparison
// mechanism) genuinely disagrees with their chronological order (weekday abbreviations dominate
// Date.prototype.toString()'s own format ahead of the year, so "earlier" and "later" don't sort
// the way a calendar would).
const genuinelyOlder = new Date('2020-12-01T00:00:00Z');   // "Tue Dec 01 2020..."
const genuinelyNewer = new Date('2026-08-21T00:00:00Z');   // "Fri Aug 21 2026..."
assert.ok(genuinelyOlder.toString() > genuinelyNewer.toString(),
  'this test fixture pair must lexicographically disagree with chronological order, or it would ' +
  'not have caught the original defect -- see this file\'s own header comment');

assert.strictEqual(app.isNotModifiedSince(genuinelyOlder, genuinelyNewer.toUTCString()), true,
  'a file genuinely last modified before the requested time must be reported not-modified -- ' +
  'the original Date(x)-without-new expression reported this as false (200, not 304)');
assert.strictEqual(app.isNotModifiedSince(genuinelyNewer, genuinelyOlder.toUTCString()), false,
  'a file genuinely last modified after the requested time must not be reported not-modified');
assert.strictEqual(app.isNotModifiedSince(genuinelyOlder, undefined), false,
  'no If-Modified-Since header at all must not be reported not-modified');
console.log('OK: isNotModifiedSince() compares chronologically, not lexicographically');

// Live-server smoke tests: start on an ephemeral local port, no external network. Confirms the
// content-type header logic and the (separately correct, express.static's own) ETag mechanism
// this file's fix sits alongside -- not a re-test of the fixed comparison itself, per the note
// above.
function get(server, urlPath, headers) {
  const port = server.address().port;
  return new Promise((resolve, reject) => {
    const req = http.request({ host: '127.0.0.1', port, path: urlPath, headers: headers || {} }, (res) => {
      let data = '';
      res.on('data', (c) => { data += c; });
      res.on('end', () => resolve({ statusCode: res.statusCode, headers: res.headers, body: data }));
    });
    req.on('error', reject);
    req.end();
  });
}

async function main() {
  const server = app.listen(0, '127.0.0.1');
  await new Promise((resolve) => server.once('listening', resolve));

  try {
    const manifest = await get(server, '/collection-manifest');
    assert.strictEqual(manifest.statusCode, 200);
    assert.strictEqual(manifest.headers['content-type'], 'application/3gpp-mbs-object-manifest+json;version="Rel17"');

    const plainObject = await get(server, '/object1');
    assert.strictEqual(plainObject.statusCode, 200);
    assert.strictEqual(plainObject.headers['content-type'], 'text/plain');
    console.log('OK: content-type headers correct for manifest and plain object paths');

    const first = await get(server, '/object1');
    const etag = first.headers['etag'];
    assert.ok(etag, 'a response for a real static file must carry an ETag');
    const conditionalByEtag = await get(server, '/object1', { 'If-None-Match': etag });
    assert.strictEqual(conditionalByEtag.statusCode, 304, 'a matching If-None-Match must produce 304');
    console.log('OK: If-None-Match conditional GET produces 304');

    console.log('app.test.js: OK');
  } finally {
    server.close();
  }
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
