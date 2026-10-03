import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { WebSocket } from 'ws';
import { startServer } from '../src/index.js';
import { templatePlace } from '../src/studio/places.js';
import { LATEST_CLIENT } from '../src/version.js';

const PORT = 17431;
const base = `http://127.0.0.1:${PORT}`;
let app;
const users = {};

async function call(method, path, body, token) {
  const res = await fetch(base + path, {
    method,
    headers: { 'content-type': 'application/json', 'x-client': 'app', 'x-client-version': LATEST_CLIENT, ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { status: res.status, data: await res.json().catch(() => ({})) };
}

function connect(token) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`ws://127.0.0.1:${PORT}/ws?token=${token}&v=${LATEST_CLIENT}&luau=1`);
    const inbox = [];
    ws.on('message', (raw) => inbox.push(JSON.parse(raw.toString())));
    ws.next = async (pred, ms = 4000) => {
      const end = Date.now() + ms;
      for (;;) {
        const i = inbox.findIndex(pred);
        if (i >= 0) return inbox.splice(i, 1)[0];
        if (Date.now() > end) throw new Error('timed out; got ' + JSON.stringify(inbox.map((m) => m.t)));
        await new Promise((r) => setTimeout(r, 20));
      }
    };
    ws.send2 = (m) => ws.send(JSON.stringify(m));
    ws.on('open', () => resolve(ws));
    ws.on('error', reject);
  });
}

before(async () => {
  app = startServer({ port: PORT, dbFile: ':memory:' });
  for (const name of ['maker', 'friend']) {
    users[name] = (await call('POST', '/api/register', { username: name, password: 'secret123', birthdate: '2000-01-01' })).data.token;
  }
});
after(async () => {
  await app.close();
});

const withScript = (melt, source) => {
  melt.tree.k.find((n) => n.c === 'ServerScriptService').k = [{ c: 'Script', n: 'Main', p: { Source: source } }];
  return melt;
};

test('sub-places: made in a game, not listed, one game for settings; teleport takes a party along with data; DataStores are shared', async () => {
  const t = users.maker;
  const main = (await call('POST', '/api/studio/places', { name: 'Lobby' }, t)).data.place;
  const sub = (await call('POST', `/api/studio/places/${main.id}/subplaces`, { name: 'Hotel' }, t)).data.place;
  assert.equal(sub.parent_id, main.id);
  assert.deepEqual(sub.game.places.map((p) => [p.name, p.main]), [['Lobby', true], ['Hotel', false]]);
  // A sub-place of a sub-place belongs to the same game.
  const sub2 = (await call('POST', `/api/studio/places/${sub.id}/subplaces`, { name: 'Basement' }, t)).data.place;
  assert.equal(sub2.parent_id, main.id);
  const mine = (await call('GET', '/api/studio/places', null, t)).data.places.map((p) => p.id);
  assert.deepEqual(mine, [main.id], 'only the game itself in your list');
  // Someone else can't add places to it.
  assert.equal((await call('POST', `/api/studio/places/${main.id}/subplaces`, { name: 'X' }, users.friend)).status, 403);

  // The lobby saves a coin and sends whoever joins to the hotel, all together.
  const lobby = withScript(templatePlace('Lobby'), `
    local TS = game:GetService("TeleportService")
    local store = game:GetService("DataStoreService"):GetDataStore("Coins")
    game.Players.PlayerAdded:Connect(function(p)
      store:SetAsync("k" .. p.UserId, 7)
      task.wait(0.2)
      TS:TeleportPartyAsync("${sub.id}", { p }, { floor = 3, from = game.PlaceId })
    end)`);
  assert.equal((await call('PUT', `/api/studio/places/${main.id}`, { melt: lobby }, t)).status, 200);
  // The hotel reads the data, the shared coins and which game it's in, into the Workspace.
  const hotel = withScript(templatePlace('Hotel'), `
    local store = game:GetService("DataStoreService"):GetDataStore("Coins")
    game.Players.PlayerAdded:Connect(function(p)
      local d = p:GetJoinData()
      local v = Instance.new("StringValue")
      v.Name = "Got"
      v.Value = string.format("%s %s %s %s %s", tostring(d.TeleportData and d.TeleportData.floor), tostring(d.SourcePlaceId == "${main.id}"),
        tostring(store:GetAsync("k" .. p.UserId)), tostring(game.GameId == "${main.id}"), tostring(game.PlaceId == "${sub.id}"))
      v.Parent = workspace
    end)`);
  assert.equal((await call('PUT', `/api/studio/places/${sub.id}`, { melt: hotel }, t)).status, 200);
  await call('PATCH', `/api/studio/places/${main.id}`, { visibility: 'public' }, t);

  const ws = await connect(users.friend);
  ws.send2({ t: 'join', game: main.id, server: 'auto' });
  await ws.next((m) => m.t === 'welcome');
  const tp = await ws.next((m) => m.t === 'teleport', 5000);
  assert.equal(tp.game, sub.id);
  assert.notEqual(tp.server, 'auto', 'a party gets its own server');
  // That server isn't for anyone else.
  const other = await connect(users.maker);
  other.send2({ t: 'join', game: sub.id, server: tp.server });
  assert.equal((await other.next((m) => m.t === 'error')).code, 'not_found');
  other.close();

  ws.send2({ t: 'join', game: sub.id, server: tp.server });
  const w = await ws.next((m) => m.t === 'welcome');
  assert.equal(w.place.game_id, main.id);
  // (Made with its Value, then put in the Workspace: it arrives as one new object.)
  const got = await ws.next((m) => m.t === 'r' && m.o.some((o) => o.o === 'new' && o.n === 'Got'), 5000);
  const value = got.o.find((o) => o.o === 'new' && o.n === 'Got').p.Value;
  assert.equal(value, '3 true 7 true true');
  ws.close();
});

test('sub-places: only places of the same game take teleports', async () => {
  const t = users.maker;
  const a = (await call('POST', '/api/studio/places', { name: 'A' }, t)).data.place;
  const b = (await call('POST', '/api/studio/places', { name: 'B' }, t)).data.place;
  const src = withScript(templatePlace('A'), `
    local TS = game:GetService("TeleportService")
    TS.TeleportInitFailed:Connect(function(p, why)
      local v = Instance.new("StringValue") v.Name = "Failed" v.Value = "failed " .. why v.Parent = workspace
    end)
    game.Players.PlayerAdded:Connect(function(p) task.wait(0.2) TS:Teleport("${b.id}", p) end)`);
  await call('PUT', `/api/studio/places/${a.id}`, { melt: src }, t);
  const ws = await connect(t);
  ws.send2({ t: 'join', game: a.id, server: 'auto' });
  await ws.next((m) => m.t === 'welcome');
  const got = await ws.next((m) => m.t === 'r' && m.o.some((o) => o.o === 'new' && o.n === 'Failed'), 5000);
  assert.equal(got.o.find((o) => o.n === 'Failed').p.Value, 'failed InvalidPlace');
  // Deleting the main place takes its sub-places along.
  const s = (await call('POST', `/api/studio/places/${a.id}/subplaces`, { name: 'S' }, t)).data.place;
  await call('DELETE', `/api/studio/places/${a.id}`, null, t);
  assert.equal((await call('GET', `/api/studio/places/${s.id}`, null, t)).status, 404);
  ws.close();
});
