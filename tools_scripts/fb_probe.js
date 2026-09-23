// Measures how fast the multiplayer database answers: REST write round trip on one kept-alive
// connection, and how long a write takes to come back through the live event stream (what another
// player sees). Writes only under uad/_probe/<random> and deletes it afterwards.
//   node tools_scripts/fb_probe.js [count=30]
const https = require('https');

const DB = 'https://dream-journal-93835-default-rtdb.firebaseio.com';
const N = Math.max(1, parseInt(process.argv[2], 10) || 30);
const path = `uad/_probe/p${Date.now().toString(36)}`;
const agent = new https.Agent({ keepAlive: true, maxSockets: 1 });

function req(method, p, body) {
  return new Promise((resolve, reject) => {
    const t0 = process.hrtime.bigint();
    const r = https.request(`${DB}/${p}.json`, { method, agent, headers: { 'Content-Type': 'application/json' } }, (res) => {
      let data = '';
      res.on('data', (c) => (data += c));
      res.on('end', () => resolve({ ms: Number(process.hrtime.bigint() - t0) / 1e6, status: res.statusCode, data }));
    });
    r.on('error', reject);
    if (body !== undefined) r.write(JSON.stringify(body));
    r.end();
  });
}

// Server-sent events on `p`, following Firebase's redirect to the database shard.
function stream(p, onEvent) {
  return new Promise((resolve, reject) => {
    const open = (url, hops) => {
      https.get(url, { headers: { Accept: 'text/event-stream' } }, (res) => {
        if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location && hops < 5) {
          res.resume();
          return open(res.headers.location, hops + 1);
        }
        let buf = '';
        res.setEncoding('utf8');
        res.on('data', (c) => {
          buf += c;
          let i;
          while ((i = buf.indexOf('\n\n')) >= 0) {
            const ev = buf.slice(0, i);
            buf = buf.slice(i + 2);
            const kind = (ev.match(/^event: (.*)$/m) || [])[1];
            const data = (ev.match(/^data: (.*)$/m) || [])[1];
            onEvent(kind, data);
          }
        });
        resolve(res);
      }).on('error', reject);
    };
    open(`${DB}/${p}.json`, 0);
  });
}

const stats = (a) => {
  const s = [...a].sort((x, y) => x - y);
  const q = (f) => s[Math.min(s.length - 1, Math.floor(f * s.length))];
  return `min ${s[0].toFixed(0)} · median ${q(0.5).toFixed(0)} · p90 ${q(0.9).toFixed(0)} · max ${s[s.length - 1].toFixed(0)} ms`;
};

(async () => {
  const sent = new Map();
  const seen = [];
  let snapshot = false;
  const res = await stream(path, (kind, data) => {
    if (kind !== 'put' && kind !== 'patch') return;
    if (!snapshot) { snapshot = true; return; }
    const m = data && data.match(/"k":(\d+)/);
    if (m && sent.has(+m[1])) seen.push(Number(process.hrtime.bigint() - sent.get(+m[1])) / 1e6);
  });
  while (!snapshot) await new Promise((r) => setTimeout(r, 20));
  const first = await req('GET', 'uad/_probe/none');
  const rtt = [];
  for (let k = 0; k < N; k++) {
    sent.set(k, process.hrtime.bigint());
    const r = await req('PATCH', path, { k, t: { '.sv': 'timestamp' } });
    if (r.status !== 200) throw new Error(`write ${r.status}: ${r.data}`);
    rtt.push(r.ms);
  }
  await new Promise((r) => setTimeout(r, 1500));
  await req('DELETE', path);
  res.destroy();
  agent.destroy();
  console.log(`first request (new TLS connection): ${first.ms.toFixed(0)} ms`);
  console.log(`write round trip, kept-alive (${rtt.length}): ${stats(rtt)}`);
  console.log(`write -> live stream (${seen.length}/${N}): ${stats(seen)}`);
  console.log(`sequential writes per second on one connection: ${(1000 / (rtt.reduce((a, b) => a + b, 0) / rtt.length)).toFixed(1)}`);
})().catch((e) => { console.error('probe failed:', e.message); process.exit(1); });
