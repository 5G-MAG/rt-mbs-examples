/*
License: 5G-MAG Public License (v1.0)
Authors: Borja Inesta Hernandez (iTEAM-UPV), Jaime Sanchez Roldan (iTEAM-UPV), Josep Ribes Rodriguez-Moldes (iTEAM-UPV), Jordi Joan Gimenez (5G-MAG)
Copyright: (C) 2026 iTEAM - Universitat Politecnica de Valencia, 5G-MAG Association

For full license terms please see the LICENSE file distributed with this
program. If this file is missing then the license can be retrieved from
https://hub.5g-mag.com/Getting-Started/OFFICIAL_5G-MAG_Public_License_v1.0.pdf
*/

const express = require('express');
const http = require('http');
const path = require('path');

const app = express();
app.use(express.static(path.join(__dirname, 'public')));

function dockerRequest(path) {
  return new Promise((resolve, reject) => {
    const options = {
      socketPath: '/var/run/docker.sock',
      path: path,
      method: 'GET',
      headers: { 'Content-Type': 'application/json' }
    };
    const req = http.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try { resolve(JSON.parse(data)); }
        catch (e) { reject(e); }
      });
    });
    req.on('error', reject);
    req.end();
  });
}

app.get('/api/versions', (req, res) => {
  res.json({
    open5gs: process.env.OPEN5GS_VERSION || 'unknown',
    mbs: process.env.FIVEG_MAG_MBS_VERSION || 'unknown',
    mongodb: process.env.MONGODB_VERSION || 'unknown'
  });
});

app.get('/api/containers', async (req, res) => {
  try {
    const containers = await dockerRequest('/containers/json?all=true');
    const result = containers.map(c => ({
      id: c.Id.substring(0, 12),
      name: c.Names[0].replace('/', '').replace(/^\//,''),
      image: c.Image,
      status: c.Status,
      state: c.State,
      created: c.Created,
      ports: c.Ports,
      group: (c.Labels && c.Labels['monitor.group']) || null
    }));
    const filtered = result.filter(c => !c.image.startsWith('sha256:'));
    res.json(filtered);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/debug', async (req, res) => {
  try {
    const containers = await dockerRequest('/containers/json?all=true');
    res.json(containers.slice(0, 2));
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/containers/:id/lastlog', async (req, res) => {
  try {
    const options = {
      socketPath: '/var/run/docker.sock',
      path: `/containers/${req.params.id}/logs?stdout=true&stderr=true&tail=20`,
      method: 'GET'
    };
    const raw = await new Promise((resolve, reject) => {
      const req2 = http.request(options, (r) => {
        let data = Buffer.alloc(0);
        r.on('data', chunk => data = Buffer.concat([data, chunk]));
        r.on('end', () => resolve(data));
      });
      req2.on('error', reject);
      req2.end();
    });
    const lines = [];
    let i = 0;
    while (i < raw.length) {
      if (i + 8 > raw.length) break;
      const size = raw.readUInt32BE(i + 4);
      const line = raw.slice(i + 8, i + 8 + size).toString('utf8').replace(/\[[0-9;]*m/g, '').trim();
      if (line) lines.push(line);
      i += 8 + size;
    }
    // Find last meaningful line and its level
    let level = 'info';
    let message = '';
    for (let j = lines.length - 1; j >= 0; j--) {
      const line = lines[j];
      if (!line.trim()) continue;
      if (/FATAL|ERROR|Aborted|core dumped/i.test(line)) level = 'error';
      else if (/WARNING|WARN/i.test(line)) level = 'warn';
      else if (/INFO/i.test(line)) level = 'info';
      else level = 'info';
      // Open5GS format: [module] LEVEL: message
      const lvlMatch = line.match(/\[\w+\]\s+(FATAL|ERROR|WARNING|WARN|INFO):\s*(.+)/i);
      if (lvlMatch) {
        const lvl = lvlMatch[1].toUpperCase();
        if (lvl === 'FATAL' || lvl === 'ERROR') level = 'error';
        else if (lvl === 'WARNING' || lvl === 'WARN') level = 'warn';
        else level = 'info';
        message = lvlMatch[2].trim();
      } else {
        message = line.trim();
      }
      if (message.length > 60) message = message.substring(0, 60) + '…';
      break;
    }
    res.json({ level, message });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/containers/:id/logs', async (req, res) => {
  try {
    const options = {
      socketPath: '/var/run/docker.sock',
      path: `/containers/${req.params.id}/logs?stdout=true&stderr=true&tail=50`,
      method: 'GET'
    };
    const raw = await new Promise((resolve, reject) => {
      const req2 = http.request(options, (r) => {
        let data = Buffer.alloc(0);
        r.on('data', chunk => data = Buffer.concat([data, chunk]));
        r.on('end', () => resolve(data));
      });
      req2.on('error', reject);
      req2.end();
    });
    const lines = [];
    let i = 0;
    while (i < raw.length) {
      if (i + 8 > raw.length) break;
      const size = raw.readUInt32BE(i + 4);
      const line = raw.slice(i + 8, i + 8 + size).toString('utf8');
      lines.push(line);
      i += 8 + size;
    }
    const cleanLogs = lines.join('').replace(/\x1b\[[0-9;]*m/g, '');
    res.json({ logs: cleanLogs });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.listen(9000, () => console.log('5G-MAG Monitor running on port 9000'));
