import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { WebSocket } from 'ws';
import { startServer } from '../src/index.js';
import { LATEST_CLIENT } from '../src/version.js';
import { templatePlace } from '../src/studio/places.js';

const PORT = 17395;
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

test('places award their own badges; profiles list them', async () => {
  let r = await call('POST', '/api/studio/places', { name: 'Parkour' }, users.maker);
  const placeId = r.data.place.id;
  r = await call('POST', '/api/studio/places', { name: 'Other' }, users.maker);
  const otherId = r.data.place.id;
  r = await call('POST', `/api/studio/places/${placeId}/badges`, { name: 'Finished parkour', description: 'Got to the top' }, users.maker);
  assert.equal(r.status, 200, r.raw);
  const badgeId = r.data.badge.id;
  r = await call('POST', `/api/studio/places/${otherId}/badges`, { name: 'Other badge' }, users.maker);
  const foreignId = r.data.badge.id;
  // Only the place's owner makes badges; at most 15.
  assert.equal((await call('POST', `/api/studio/places/${placeId}/badges`, { name: 'Nope' }, users.player)).status, 403);
  for (let i = 0; i < 14; i++) await call('POST', `/api/studio/places/${otherId}/badges`, { name: `B${i}` }, users.maker);
  assert.equal((await call('POST', `/api/studio/places/${otherId}/badges`, { name: 'Too many' }, users.maker)).status, 400);

  const melt = templatePlace('Parkour');
  melt.tree.k.find((n) => n.c === 'ServerScriptService').k[0].p.Source = `
local BS = game:GetService("BadgeService")
game.Players.PlayerAdded:Connect(function(p)
  print("had", BS:UserHasBadgeAsync(p.UserId, ${badgeId}), BS:GetBadgeInfo(${badgeId}).Name)
  BS:AwardBadge(p.UserId, ${badgeId})
  print("has", BS:UserHasBadgeAsync(p.UserId, ${badgeId}))
  local ok, err = pcall(function() BS:AwardBadge(p.UserId, ${foreignId}) end)
  print("foreign", ok)
end)`;
  r = await call('PUT', `/api/studio/places/${placeId}`, { melt }, users.maker);
  assert.equal(r.status, 200, r.raw);
  r = await call('PATCH', `/api/studio/places/${placeId}`, { visibility: 'public' }, users.maker);
  assert.equal(r.status, 200, r.raw);

  const ws = await connect(users.player);
  await ws.next((m) => m.t === 'hello');
  ws.send2({ t: 'join', game: placeId, server: 'auto' });
  const welcome = await ws.next((m) => m.t === 'welcome');
  assert.deepEqual(welcome.place.badge_info.map((b) => b.name), ['Finished parkour']);
  const got = await ws.next((m) => m.t === 'badge');
  assert.equal(got.badge.name, 'Finished parkour');
  ws.close();

  r = await call('GET', '/api/users/player/badges');
  assert.deepEqual(r.data.badges.map((b) => [b.id, b.place_name]), [[badgeId, 'Parkour']]);
  r = await call('GET', `/api/places/${placeId}/badges`, null, users.player);
  assert.equal(r.data.badges[0].owned, true);
  assert.equal(r.data.badges[0].awarded, 1);
  // The other place's badge was not given out by this place.
  const foreign = app.db.prepare('SELECT COUNT(*) AS n FROM user_badges WHERE badge_id = ?').get(foreignId);
  assert.equal(foreign.n, 0);
});
