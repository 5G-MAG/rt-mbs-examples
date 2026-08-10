#!/usr/bin/env node
//
// load-demo.js -- load an MBS demo template into the running rt-mbs-application-provider
// portal. Creates the MBS User Service, then each of its Ingest Sessions, via the portal's
// own /mbs-user-services and /ingest-sessions API (Nmb10, proxied to rt-mbs-function). It
// does NOT activate anything -- every session is created with distSessState INACTIVE
// regardless of what the template says, same as the portal's own "Load Template" button.
//
//   node load-demo.js [template.json]        (default: ./dash-if-demo.json)
//
// Portal host/port and Basic-auth credentials are read from the portal's .env (default
// ~/rt-mbs-application-provider/.env; override with PORTAL_ENV=/path). Mirrors
// rt-mbms-examples' scripts/tmux/mbms-broadcast-tutorial/demo-content/load-demo.js --
// same shape of script, adapted to the Nmb10 API instead of xMB (TS 26.348).
//
'use strict';
const fs = require('fs');
const http = require('http');
const path = require('path');

const tmplPath = process.argv[2] || path.join(__dirname, 'dash-if-demo.json');
const def = JSON.parse(fs.readFileSync(tmplPath, 'utf8'));

// --- portal connection info from its .env ---
if (!process.env.PORTAL_ENV && !process.env.HOME) {
  console.error('Neither PORTAL_ENV nor HOME is set; cannot locate the portal .env file. Set PORTAL_ENV=/path/to/.env explicitly.');
  process.exit(1);
}
const envPath = process.env.PORTAL_ENV || path.join(process.env.HOME, 'rt-mbs-application-provider', '.env');
const env = {};
try {
  for (const rawLine of fs.readFileSync(envPath, 'utf8').split('\n')) {
    // Strip a trailing \r explicitly (CRLF-saved .env) before matching: JS's
    // "." already excludes \r, so a bare trailing \r wouldn't stop (.*)$
    // from matching at all -- and .trim() the captured value afterwards so
    // a plain trailing space (not \r) doesn't end up inside it either,
    // which would otherwise defeat the quote-stripping below.
    const line = rawLine.replace(/\r$/, '');
    const m = /^\s*([A-Z0-9_]+)\s*=\s*(.*)$/.exec(line);
    if (m) env[m[1]] = m[2].trim().replace(/^["']|["']$/g, '');
  }
} catch (e) {
  console.error(`Could not read portal .env at ${envPath}: ${e.message}`);
  process.exit(1);
}
const HOST = env.HOST || '127.0.0.1';
const PORT = Number(env.PORT) || 8081;
const AUTH = 'Basic ' + Buffer.from(`${env.AUTH_USER || 'admin'}:${env.AUTH_TOKEN || ''}`).toString('base64');

function req(method, p, body) {
  return new Promise((resolve, reject) => {
    const data = body ? JSON.stringify(body) : null;
    const r = http.request(
      { host: HOST, port: PORT, path: p, method, timeout: 15000,
        headers: { Authorization: AUTH, 'Content-Type': 'application/json',
          ...(data ? { 'Content-Length': Buffer.byteLength(data) } : {}) } },
      (res) => {
        let s = '';
        res.on('data', (c) => (s += c));
        res.on('end', () => {
          let j; try { j = JSON.parse(s); } catch { j = s; }
          if (res.statusCode >= 200 && res.statusCode < 300) resolve({ headers: res.headers, body: j });
          else reject(new Error(`HTTP ${res.statusCode}: ${typeof j === 'string' ? j : JSON.stringify(j)}`));
        });
      }
    );
    r.on('error', reject);
    r.on('timeout', () => { r.destroy(new Error('request timed out')); });
    if (data) r.write(data);
    r.end();
  });
}

// Pull a resource id out of a create response's Location header (both /mbs-user-services and
// /ingest-sessions forward MBSF's Location header on 201, see server.js).
function extractId(resp) {
  const loc = resp.headers && resp.headers.location;
  return loc ? loc.split('/').filter(Boolean).pop() : undefined;
}

// Fields buildIngestSessionBody actually reads from a template session entry. Anything else
// present on the object is almost certainly a typo (wrong case, underscore instead of
// camelCase, ...) that would otherwise silently fall back to a hardcoded default below.
const KNOWN_SESSION_FIELDS = new Set([
  'distSessKey', 'sourceIp', 'destIp', 'distSessState', 'maxBitrate', 'distrMethod',
  'opMode', 'acqMethod', 'ingUri', 'acqIds', 'distrUri',
]);

const usedDistSessKeys = new Set();

// Translates one of this template's flat, form-shaped session entries (same field names the
// portal's own "Load Template" button uses -- distSessKey/sourceIp/destIp/...) into the
// nested mbsDisSessInfos body /ingest-sessions actually expects (minus mbsUserServId, filled
// in by the caller once the service has been created). distSessState is always forced to
// INACTIVE regardless of what the template says.
function buildIngestSessionBody(sess) {
  for (const k of Object.keys(sess)) {
    if (!KNOWN_SESSION_FIELDS.has(k)) {
      console.error(`FAILED: session has unrecognised field "${k}" -- check for a typo. Known fields: ${[...KNOWN_SESSION_FIELDS].join(', ')}`);
      process.exit(1);
    }
  }

  const key = sess.distSessKey || 'AP_MBS_SESSION_1';
  if (usedDistSessKeys.has(key)) {
    console.error(`FAILED: distSessKey "${key}" is used by more than one session in this template (set a distinct distSessKey on each).`);
    process.exit(1);
  }
  usedDistSessKeys.add(key);

  const acqMethod = sess.acqMethod || 'PULL';
  const objDistrInfo = {
    operatingMode: sess.opMode || 'STREAMING',
    objAcqMethod: acqMethod,
    objDistrUri: sess.distrUri || 'http://127.0.0.2/',
  };
  if (acqMethod === 'PULL') {
    // MBSF treats these as mandatory for PULL sessions and, per validate.js, crashes the
    // entire process (taking every other active session down with it) on a missing
    // mandatory field that the client didn't catch first -- so refuse to send this at all
    // rather than silently defaulting to an empty/absent value.
    if (!sess.ingUri) {
      console.error('FAILED: session has acqMethod PULL but no ingUri.');
      process.exit(1);
    }
    const acqIds = String(sess.acqIds || '').split(/[,;\s]+/).map((s) => s.trim()).filter(Boolean);
    if (acqIds.length === 0) {
      console.error('FAILED: session has acqMethod PULL but no acqIds (comma/space-separated list).');
      process.exit(1);
    }
    objDistrInfo.objIngUri = sess.ingUri;
    objDistrInfo.objAcqIds = acqIds;
  }
  return {
    // mbsUserServId filled in by the caller once the service has been created.
    mbsDisSessInfos: {
      [key]: {
        mbsSessionId: {
          ssm: {
            sourceIpAddr: { ipv4Addr: sess.sourceIp || '127.0.0.5' },
            destIpAddr: { ipv4Addr: sess.destIp || '232.10.0.7' },
          },
        },
        mbsDistSessState: 'INACTIVE',
        maxContBitRate: sess.maxBitrate ?? '10 Mbps',
        distrMethod: sess.distrMethod || 'OBJECT',
        objDistrInfo,
      },
    },
    suppFeat: '3',
  };
}

(async () => {
  console.log(`Loading "${def.description ? def.description.split('.')[0] : tmplPath}" into the portal at ${HOST}:${PORT}`);

  if (!Array.isArray(def.sessions) || def.sessions.length === 0) {
    console.error(`FAILED: template has no "sessions" array (or it's empty) -- nothing to ingest. Check the template for a typo'd key.`);
    process.exit(1);
  }
  // Build (and so validate) every session body up front, before creating anything on the
  // portal -- a bad session further down the template shouldn't leave an orphaned service
  // (or a partial set of sessions) behind on a real, possibly-shared portal.
  const bodies = def.sessions.map(buildIngestSessionBody);

  const svcResp = await req('POST', '/mbs-user-services', def.service || {});
  const serviceId = extractId(svcResp);
  if (!serviceId) {
    console.error('  Created the service but could not determine its id from the response Location header:');
    console.error('   ', JSON.stringify(svcResp.body));
    console.error('  Find the service id in the portal and add sessions there.');
    process.exit(1);
  }
  console.log(`  service created  id=${serviceId}`);
  let missingLocation = false;
  for (let i = 0; i < bodies.length; i++) {
    const sess = def.sessions[i];
    bodies[i].mbsUserServId = serviceId;
    const sResp = await req('POST', '/ingest-sessions', bodies[i]);
    const sessionId = extractId(sResp);
    if (!sessionId) missingLocation = true;
    console.log(`  ingest session created  id=${sessionId || '?'}  (${sess.acqMethod || 'PULL'}, ${sess.ingUri || sess.distrUri})`);
  }
  if (missingLocation) {
    console.error('\nWARNING: at least one session response had no Location header -- its id is unknown, find it manually in the portal.');
  }
  console.log('\nLoaded, INACTIVE. Open the portal, review the service/session, and Activate to start broadcasting.');
})().catch((e) => { console.error('FAILED:', e.message); process.exit(1); });
