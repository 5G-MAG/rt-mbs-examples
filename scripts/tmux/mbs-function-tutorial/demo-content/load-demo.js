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
const envPath = process.env.PORTAL_ENV || path.join(process.env.HOME, 'rt-mbs-application-provider', '.env');
const env = {};
try {
  for (const line of fs.readFileSync(envPath, 'utf8').split('\n')) {
    const m = /^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/.exec(line);
    if (m) env[m[1]] = m[2].replace(/^["']|["']$/g, '');
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

// Translates one of this template's flat, form-shaped session entries (same field names the
// portal's own "Load Template" button uses -- distSessKey/sourceIp/destIp/...) into the
// nested mbsDisSessInfos body /ingest-sessions actually expects. distSessState is always
// forced to INACTIVE regardless of what the template says.
function buildIngestSessionBody(mbsUserServId, sess) {
  const key = sess.distSessKey || 'AP_MBS_SESSION_1';
  const objDistrInfo = {
    operatingMode: sess.opMode || 'STREAMING',
    objAcqMethod: sess.acqMethod || 'PULL',
    objDistrUri: sess.distrUri || 'http://127.0.0.2/',
  };
  if ((sess.acqMethod || 'PULL') === 'PULL') {
    objDistrInfo.objIngUri = sess.ingUri || '';
    objDistrInfo.objAcqIds = String(sess.acqIds || '').split(',').map((s) => s.trim()).filter(Boolean);
  }
  return {
    mbsUserServId,
    mbsDisSessInfos: {
      [key]: {
        mbsSessionId: {
          ssm: {
            sourceIpAddr: { ipv4Addr: sess.sourceIp || '127.0.0.5' },
            destIpAddr: { ipv4Addr: sess.destIp || '232.10.0.7' },
          },
        },
        mbsDistSessState: 'INACTIVE',
        maxContBitRate: sess.maxBitrate || '10 Mbps',
        distrMethod: sess.distrMethod || 'OBJECT',
        objDistrInfo,
      },
    },
    suppFeat: '3',
  };
}

(async () => {
  console.log(`Loading "${def.description ? def.description.split('.')[0] : tmplPath}" into the portal at ${HOST}:${PORT}`);
  const svcResp = await req('POST', '/mbs-user-services', def.service || {});
  const serviceId = extractId(svcResp);
  if (!serviceId) {
    console.error('  Created the service but could not determine its id from the response Location header:');
    console.error('   ', JSON.stringify(svcResp.body));
    console.error('  Find the service id in the portal and add sessions there.');
    process.exit(1);
  }
  console.log(`  service created  id=${serviceId}`);
  for (const sess of def.sessions || []) {
    const body = buildIngestSessionBody(serviceId, sess);
    const sResp = await req('POST', '/ingest-sessions', body);
    console.log(`  ingest session created  id=${extractId(sResp) || '?'}  (${sess.acqMethod || 'PULL'}, ${sess.ingUri || sess.distrUri})`);
  }
  console.log('\nLoaded, INACTIVE. Open the portal, review the service/session, and Activate to start broadcasting.');
})().catch((e) => { console.error('FAILED:', e.message); process.exit(1); });
