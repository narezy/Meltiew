import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { WebSocket } from 'ws';
import { startServer } from '../src/index.js';
import { LATEST_CLIENT } from '../src/version.js';
import { templatePlace } from '../src/studio/places.js';

const PORT = 17397;
const base = `http://127.0.0.1:${PORT}`;
let app;
const users = {};

async function call(method, path, body, token) {
  const res = await fetch(base + path, {
    method,
    headers: { 'content-type': 'application/json', 'x-client': 'app', 'x-client-version': LATEST_CLIENT, ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const raw = await res.text();
  let data = {};
  try { data = JSON.parse(raw); } catch {}
  return { status: res.status, data, raw };
}

function connect(token) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`ws://127.0.0.1:${PORT}/ws?token=${token}&v=${LATEST_CLIENT}&luau=1`);
    const inbox = [];
    const waiters = [];
    ws.on('message', (raw) => {
      const msg = JSON.parse(raw.toString());
      const i = waiters.findIndex((w) => w.pred(msg));
      if (i >= 0) waiters.splice(i, 1)[0].resolve(msg);
      else inbox.push(msg);
    });
    ws.next = (pred) => {
      const i = inbox.findIndex(pred);
      if (i >= 0) return Promise.resolve(inbox.splice(i, 1)[0]);
      return new Promise((res) => waiters.push({ pred, resolve: res }));
    };
    ws.send2 = (m) => ws.send(JSON.stringify(m));
    ws.on('open', () => resolve(ws));
    ws.on('error', reject);
  });
}

before(async () => {
  app = startServer({ port: PORT, dbFile: ':memory:' });
  for (const name of ['maker', 'player']) {
    const r = await call('POST', '/api/register', { username: name, password: 'secret123', birthdate: '2000-01-01' });
    users[name] = r.data.token;
  }
});
after(async () => {
  await app.close();
});

test('saving a new version moves live players to a fresh server with it', async () => {
  let r = await call('POST', '/api/studio/places', { name: 'Live' }, users.maker);
  const placeId = r.data.place.id;
  const melt = templatePlace('Live');
  r = await call('PUT', `/api/studio/places/${placeId}`, { melt }, users.maker);
  assert.equal(r.status, 200, r.raw);
  await call('PATCH', `/api/studio/places/${placeId}`, { visibility: 'public' }, users.maker);

  const a = await connect(users.maker);
  const b = await connect(users.player);
  a.send2({ t: 'join', game: placeId, server: 'auto' });
  const wa = await a.next((m) => m.t === 'welcome');
  b.send2({ t: 'join', game: placeId, server: wa.server.id });
  await b.next((m) => m.t === 'welcome');

  // Saving the same content again changes nothing.
  await call('PUT', `/api/studio/places/${placeId}`, { melt }, users.maker);
  // A real change: a new part.
  melt.tree.k.find((n) => n.c === 'Workspace').k.push({ c: 'Part', n: 'NewThing', p: {} });
  r = await call('PUT', `/api/studio/places/${placeId}`, { melt }, users.maker);
  assert.equal(r.status, 200, r.raw);
  const [ra, rb] = await Promise.all([a.next((m) => m.t === 'rejoin'), b.next((m) => m.t === 'rejoin')]);
  assert.equal(ra.server, rb.server, 'everyone goes to the same new server');
  assert.notEqual(ra.server, wa.server.id);
  assert.ok(ra.m);
  // The old server is no longer offered; the new one runs the new version.
  const list = await call('GET', `/api/places/${placeId}/servers`, null, users.player);
  if (list.status === 200) assert.ok(!(list.data.servers || []).some((s) => s.id === wa.server.id));
  a.send2({ t: 'join', game: placeId, server: ra.server });
  const w2 = await a.next((m) => m.t === 'welcome');
  assert.equal(w2.server.id, ra.server);
  assert.ok(JSON.stringify(w2.place.snapshot).includes('NewThing'));
  // Joining the retired server by id lands on a current one.
  b.send2({ t: 'join', game: placeId, server: wa.server.id });
  const w3 = await b.next((m) => m.t === 'welcome');
  assert.equal(w3.server.id, ra.server);
  a.close();
  b.close();
});
