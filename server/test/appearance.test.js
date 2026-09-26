import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { WebSocket } from 'ws';
import { startServer } from '../src/index.js';
import { LATEST_CLIENT } from '../src/version.js';
import { templatePlace } from '../src/studio/places.js';

const PORT = 17401;
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

test('Appearance: a place dresses players for this place only', async () => {
  let r = await call('POST', '/api/studio/places', { name: 'Costume party' }, users.maker);
  const placeId = r.data.place.id;
  const melt = templatePlace('Costume party');
  const sp = melt.tree.k.find((n) => n.c === 'StarterPlayer');
  sp.k = sp.k || [];
  sp.k.push({ c: 'Appearance', n: 'Everyone', p: { TorsoColor: { $c3: '#ff0000' }, Face: ':3', Accessories: 'crown,nonsense', KeepFace: false } });
  melt.tree.k.find((n) => n.c === 'ServerScriptService').k[0].p.Source = `
local ok, err = pcall(function() game.Players.LocalPlayer:ApplyAppearance(nil) end)
game.Players.PlayerAdded:Connect(function(p)
  if p.Name == "player" then
    task.wait(0.2)
    local app = game.Players:GetAppearanceAsync(p.UserId)
    print("current", app.Face, app.Accessories, app.TorsoColor:ToHex())
    app.Accessories = "halo"
    app.KeepColors = true
    p:ApplyAppearance(app)
    task.wait(0.2)
    p:ResetAppearance()
  end
end)`;
  r = await call('PUT', `/api/studio/places/${placeId}`, { melt }, users.maker);
  assert.equal(r.status, 200, r.raw);
  await call('PATCH', `/api/studio/places/${placeId}`, { visibility: 'public' }, users.maker);

  const a = await connect(users.maker);
  a.send2({ t: 'join', game: placeId, server: 'auto' });
  const wa = await a.next((m) => m.t === 'welcome');
  // StarterPlayer's Appearance: red torso, :3, a crown (unknown items are dropped).
  let look = await a.next((m) => m.t === 'look' && m.player.id === wa.you);
  assert.equal(look.player.colors.torso, '#ff0000');
  assert.equal(look.player.face, ':3');
  assert.deepEqual(look.player.accessories, ['crown']);
  const b = await connect(users.player);
  b.send2({ t: 'join', game: placeId, server: wa.server.id });
  const wb = await b.next((m) => m.t === 'welcome');
  // The other player sees b dressed by the place, then re-dressed by the script, then back.
  look = await a.next((m) => m.t === 'look' && m.player.id === wb.you);
  assert.deepEqual(look.player.accessories, ['crown']);
  look = await a.next((m) => m.t === 'look' && m.player.id === wb.you);
  assert.deepEqual(look.player.accessories, ['halo']);
  assert.equal(look.player.colors.torso, '#baa4e2', 'KeepColors: their own torso');
  look = await a.next((m) => m.t === 'look' && m.player.id === wb.you);
  assert.deepEqual(look.player.accessories, []);
  // Their real profile never changed.
  r = await call('GET', '/api/users/player', null, users.maker);
  assert.deepEqual(r.data.user.accessories, []);
  assert.notEqual(r.data.user.face, ':3');
  a.close();
  b.close();
});

test('GetUserAppearanceAsync and the public look endpoint', async () => {
  const anon = await fetch(base + '/api/users/maker/look').then((r) => r.json());
  assert.ok(anon.colors && anon.face, 'public look');
  assert.equal((await fetch(base + '/api/users/nobody_here/look')).status, 404);
  let r = await call('POST', '/api/studio/places', { name: 'Twins' }, users.maker);
  const placeId = r.data.place.id;
  const melt = templatePlace('Twins');
  melt.tree.k.find((n) => n.c === 'ServerScriptService').k[0].p.Source = `
game.Players.PlayerAdded:Connect(function(p)
  if p.Name == "player" then
    local look = game.Players:GetUserAppearanceAsync("maker")
    look.Accessories = "crown"
    p:ApplyAppearance(look)
    local ok = pcall(function() return game.Players:GetUserAppearanceAsync("nobody_here") end)
    if not ok then look.Face = "T_T"; p:ApplyAppearance(look) end
  end
end)`;
  await call('PUT', `/api/studio/places/${placeId}`, { melt }, users.maker);
  await call('PATCH', `/api/studio/places/${placeId}`, { visibility: 'public' }, users.maker);
  const b = await connect(users.player);
  b.send2({ t: 'join', game: placeId, server: 'auto' });
  const wb = await b.next((m) => m.t === 'welcome');
  let look = await b.next((m) => m.t === 'look' && m.player.id === wb.you);
  assert.deepEqual(look.player.accessories, ['crown']);
  assert.equal(look.player.face, anon.face);
  look = await b.next((m) => m.t === 'look' && m.player.id === wb.you);
  assert.equal(look.player.face, 'T_T');
  b.close();
});
