import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { WebSocket } from 'ws';
import { startServer } from '../src/index.js';
import { LATEST_CLIENT } from '../src/version.js';
import { templatePlace } from '../src/studio/places.js';

const PORT = 17399;
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

test('physics parts: first reporter simulates, others get relays, the nearest takes over, scripts see positions', async () => {
  let r = await call('POST', '/api/studio/places', { name: 'Boxes' }, users.maker);
  const placeId = r.data.place.id;
  const melt = templatePlace('Boxes');
  melt.tree.k.find((n) => n.c === 'Workspace').k.push({ c: 'Part', n: 'Box', p: { Anchored: false, Position: { $v3: [0, 5, 0] } } });
  melt.tree.k.find((n) => n.c === 'ServerScriptService').k[0].p.Source = `
game.Players.PlayerAdded:Connect(function(p)
  p.Chatted:Connect(function() end)
end)
local remote = Instance.new("RemoteEvent")
remote.Name = "Where"
remote.Parent = game.ReplicatedStorage
remote.OnServerEvent:Connect(function(p)
  print("box at", math.floor(workspace.Box.Position.X))
end)`;
  r = await call('PUT', `/api/studio/places/${placeId}`, { melt }, users.maker);
  assert.equal(r.status, 200, r.raw);
  await call('PATCH', `/api/studio/places/${placeId}`, { visibility: 'public' }, users.maker);

  const a = await connect(users.maker);
  const b = await connect(users.player);
  a.send2({ t: 'join', game: placeId, server: 'auto' });
  const wa = await a.next((m) => m.t === 'welcome');
  b.send2({ t: 'join', game: placeId, server: wa.server.id });
  const wb = await b.next((m) => m.t === 'welcome');
  const boxId = JSON.stringify(wa.place.snapshot).match(/"id":"([^"]+)","c":"Part","n":"Box"/)?.[1]
    || wa.place.snapshot.find((op) => op.n === 'Box')?.id;
  assert.ok(boxId, 'box in snapshot');
  // Both apps are next to the box: a reports first and owns it.
  a.send2({ t: 'state', p: [0, 0.6, 1], r: 0, a: 'idle' });
  b.send2({ t: 'state', p: [0, 0.6, 3], r: 0, a: 'idle' });
  a.send2({ t: 'phys', u: [[boxId, 0, 2, 0, 0, 0, 0, 0, -3, 0]] });
  const own = await b.next((m) => m.t === 'phys_own');
  assert.equal(own.o[boxId], wa.you);
  const rel = await b.next((m) => m.t === 'phys');
  assert.equal(rel.u[0][2], 2);
  // b's report is ignored while a owns it.
  b.send2({ t: 'phys', u: [[boxId, 50, 2, 0, 0, 0, 0, 0, 0, 0]] });
  // b walks right up to it and claims it; a walks away.
  a.send2({ t: 'state', p: [0, 0.6, 5], r: 0, a: 'walk' });
  b.send2({ t: 'state', p: [0.5, 0.6, 0.5], r: 0, a: 'walk' });
  await new Promise((res) => setTimeout(res, 1100));
  b.send2({ t: 'phys_claim', id: boxId });
  const own2 = await a.next((m) => m.t === 'phys_own' && m.o[boxId] === wb.you);
  assert.ok(own2);
  b.send2({ t: 'phys', u: [[boxId, 7, 1, 0, 0, 45, 0, 0, 0, 0]] });
  await a.next((m) => m.t === 'phys' && m.u.some((u) => u[0] === boxId && u[1] === 7));
  // The server's world has the box where it went: a rejoin gets it there.
  await new Promise((res) => setTimeout(res, 400));
  a.send2({ t: 'join', game: placeId, server: wa.server.id });
  const again = await a.next((m) => m.t === 'welcome');
  const op = again.place.snapshot.find((o) => o.id === boxId);
  assert.equal(op.p.Position.$v3[0], 7);
  assert.equal(op.p.Rotation.$v3[1], 45);
  a.close();
  b.close();
});
