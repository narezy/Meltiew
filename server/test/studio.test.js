import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import WebSocket from 'ws';
import { startServer } from '../src/index.js';
import { LATEST_CLIENT } from '../src/version.js';
import { templatePlace, validateMarp } from '../src/studio/places.js';

let app;
const PORT = 17351;
const base = `http://127.0.0.1:${PORT}`;
const users = {};

async function call(method, path, body, token) {
  const res = await fetch(base + path, {
    method,
    headers: { 'content-type': 'application/json', 'x-client': 'app', 'x-client-version': LATEST_CLIENT, ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let data = {};
  try {
    data = JSON.parse(text);
  } catch {}
  return { status: res.status, data, raw: text };
}

function connect(token) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`ws://127.0.0.1:${PORT}/ws?token=${token}&v=${LATEST_CLIENT}`);
    const inbox = [];
    const waiters = [];
    const ops = [];
    const opWaiters = [];
    ws.on('message', (raw) => {
      const msg = JSON.parse(raw.toString());
      if (msg.t === 'r') {
        for (const o of msg.o) {
          const j = opWaiters.findIndex((w) => w.pred(o));
          if (j >= 0) opWaiters.splice(j, 1)[0].resolve(o);
          else ops.push(o);
        }
        return;
      }
      const i = waiters.findIndex((w) => w.pred(msg));
      if (i >= 0) waiters.splice(i, 1)[0].resolve(msg);
      else inbox.push(msg);
    });
    // Waits for a message, or for a replication batch containing an op that matches.
    ws.next = (pred, ms = 4000) => {
      const i = inbox.findIndex(pred);
      if (i >= 0) return Promise.resolve(inbox.splice(i, 1)[0]);
      return new Promise((resolve, rej) => {
        const w = { pred, resolve };
        waiters.push(w);
        setTimeout(() => rej(new Error('timeout waiting for message')), ms).unref();
      });
    };
    // Waits for one replication operation (they arrive in batches of type "r").
    ws.op = (pred, ms = 4000) => {
      const i = ops.findIndex(pred);
      if (i >= 0) return Promise.resolve(ops.splice(i, 1)[0]);
      return new Promise((resolve, rej) => {
        opWaiters.push({ pred, resolve });
        setTimeout(() => rej(new Error('timeout waiting for op')), ms).unref();
      });
    };
    ws.send2 = (m) => ws.send(JSON.stringify(m));
    ws.on('open', () => resolve(ws));
    ws.on('error', reject);
  });
}

before(async () => {
  app = startServer({ port: PORT, dbFile: ':memory:' });
  for (const [name, bd] of [['maker', '2000-01-01'], ['guest', '2001-02-02'], ['stranger', '2002-03-03']]) {
    const r = await call('POST', '/api/register', { username: name, password: 'secret123', birthdate: bd });
    users[name] = r.data.token;
  }
});
after(async () => {
  await app.close();
});

const v3 = (x, y, z) => ({ $v3: [x, y, z] });

function gamePlace() {
  const marp = templatePlace('Coin Rush');
  const ws = marp.tree.k.find((n) => n.c === 'Workspace');
  ws.k.push({
    c: 'Part',
    n: 'Coin',
    p: { Position: v3(4, 1, 0), Color: { $c3: '#ffd166' }, Shape: 'Ball' },
    k: [{ c: 'Script', n: 'Pickup', p: { Source: 'script.Parent.Touched:Connect(function(hit) local p = game.Players:GetPlayerFromCharacter(hit.Parent) if p then p.leaderstats.Coins.Value += 1 end end)' } }],
  });
  const rs = marp.tree.k.find((n) => n.c === 'ReplicatedStorage');
  rs.k = [{ c: 'RemoteEvent', n: 'Hello' }, { c: 'RemoteFunction', n: 'Double' }];
  const sss = marp.tree.k.find((n) => n.c === 'ServerScriptService');
  sss.k = [
    {
      c: 'Script',
      n: 'Main',
      p: {
        Source: `
local rs = game:GetService("ReplicatedStorage")
game.Players.PlayerAdded:Connect(function(p)
  local stats = Instance.new("Folder") stats.Name = "leaderstats" stats.Parent = p
  local c = Instance.new("NumberValue") c.Name = "Coins" c.Parent = stats
end)
rs.Hello.OnServerEvent:Connect(function(p, text) rs.Hello:FireAllClients(p.Name .. " says " .. text) end)
rs.Double.OnServerInvoke = function(p, n) return n * 2 end
print("secret server code")`,
      },
    },
  ];
  marp.strings = { welcome: { en: 'Welcome!', ru: 'Добро пожаловать!' } };
  marp.meta.i18n.name = { ru: 'Монетная гонка', es: 'Carrera de monedas' };
  return marp;
}

test('marp validation keeps known classes and rejects junk', () => {
  const sss = templatePlace('New').tree.k.find((n) => n.c === 'ServerScriptService');
  assert.equal(sss.k[0].c, 'Script', 'new places start with a server script');
  const clean = validateMarp(gamePlace());
  assert.equal(clean.tree.c, 'DataModel');
  assert.throws(() => validateMarp({ format: 'marp', tree: { c: 'DataModel', k: [{ c: 'Nuke' }] } }), /unknown class/);
  assert.throws(() => validateMarp({ format: 'zip' }), /not a .marp/);
  const extra = validateMarp({ format: 'marp', tree: { c: 'DataModel', k: [{ c: 'Workspace', p: { Gravity: 10, Hacks: 1 } }] } });
  assert.deepEqual(extra.tree.k[0].p, { Gravity: 10 });
});

test('create, save, publish, play, comment and stats', async () => {
  // Create and save.
  let r = await call('POST', '/api/studio/places', { name: 'Coin Rush' }, users.maker);
  assert.equal(r.status, 200, r.raw);
  const id = r.data.place.id;
  assert.equal(r.data.place.visibility, 'private');
  r = await call('PUT', `/api/studio/places/${id}`, { marp: gamePlace() }, users.maker);
  assert.equal(r.status, 200, r.raw);
  assert.equal(r.data.place.version, 3);

  // Private: invisible to others, not listed.
  assert.equal((await call('GET', `/api/places/${id}`, null, users.guest)).status, 404);
  r = await call('GET', '/api/places', null, users.guest);
  assert.ok(!r.data.places.some((p) => p.id === id));

  // Publish; the Russian name is used for Russian players.
  r = await call('PATCH', `/api/studio/places/${id}`, { visibility: 'public' }, users.maker);
  assert.equal(r.data.place.visibility, 'public');
  r = await call('GET', `/api/places/${id}`, null, users.guest);
  assert.equal(r.status, 200);
  assert.equal(r.data.place.name_ru, 'Монетная гонка');
  assert.equal(r.data.place.author.username, 'maker');
  r = await call('GET', '/api/places?q=coin', null, users.guest);
  assert.ok(r.data.places.some((p) => p.id === id));
  r = await call('GET', '/api/users/maker/places', null, users.guest);
  assert.equal(r.data.places.length, 1);

  // Play: the guest joins, gets the world without server scripts.
  const guest = await connect(users.guest);
  await guest.next((m) => m.t === 'hello');
  guest.send2({ t: 'join', game: id, server: 'auto' });
  const welcome = await guest.next((m) => m.t === 'welcome');
  assert.equal(welcome.place.id, id);

  // Any language with a translation gets it; launching someone's server opens its place.
  const es = await fetch(`${base}/api/places/${id}`, { headers: { authorization: `Bearer ${users.guest}`, 'x-lang': 'es' } }).then((x) => x.json());
  assert.equal(es.place.name, 'Carrera de monedas');
  r = await call('POST', '/api/launch', { server: welcome.server.id }, users.maker);
  assert.equal(r.data.game, id, r.raw);
  assert.equal(welcome.place.strings.welcome.ru, 'Добро пожаловать!');
  const snap = welcome.place.snapshot;
  const byName = (n) => snap.find((o) => o.n === n);
  assert.ok(byName('Coin'));
  assert.ok(!byName('Main') && !byName('Pickup'), 'server scripts must not reach clients');
  assert.ok(!JSON.stringify(snap).includes('secret server code'));
  const spawn = await guest.op((o) => o.o === 'spawn');
  assert.ok(spawn.pos.$v3);
  const coinsOp = await guest.op((o) => o.o === 'new' && o.n === 'Coins');

  // Touching the coin runs its server script.
  guest.send2({ t: 'touch', id: byName('Coin').id });
  const set = await guest.op((o) => o.o === 'set' && o.id === coinsOp.id && o.k === 'Value');
  assert.equal(set.v, 1);

  // Remotes both ways, and a RemoteFunction.
  guest.send2({ t: 'remote', id: byName('Hello').id, args: ['hi'] });
  const fired = await guest.op((o) => o.o === 'fire' && o.id === byName('Hello').id);
  assert.deepEqual(fired.args, ['guest says hi']);
  guest.send2({ t: 'invoke', id: byName('Double').id, rid: 5, args: [21] });
  const ret = await guest.op((o) => o.o === 'ret' && o.rid === 5);
  assert.deepEqual(ret.values, [42]);

  // The creator sees the server console; the guest doesn't.
  const maker = await connect(users.maker);
  await maker.next((m) => m.t === 'hello');
  maker.send2({ t: 'join', game: id, server: welcome.server.id });
  await maker.next((m) => m.t === 'welcome');
  guest.send2({ t: 'remote', id: byName('Hello').id, args: ['again'] });
  await maker.op((o) => o.o === 'fire');
  guest.close();
  maker.close();
  await new Promise((res) => setTimeout(res, 150));

  // Comments and stats.
  r = await call('POST', `/api/places/${id}/comments`, { text: 'super fun' }, users.guest);
  assert.equal(r.status, 200, r.raw);
  r = await call('GET', `/api/places/${id}/comments`, null, users.stranger);
  assert.equal(r.data.comments[0].body, 'super fun');
  assert.equal(r.data.comments[0].can_delete, false);
  r = await call('GET', `/api/studio/places/${id}/stats`, null, users.maker);
  assert.equal(r.data.stats.visits, 2);
  assert.equal(r.data.stats.unique_players, 2);
  assert.ok(r.data.stats.playtime_ms > 0);
  assert.equal(r.data.stats.comments, 1);
  assert.equal((await call('GET', `/api/studio/places/${id}/stats`, null, users.guest)).status, 403);

  // Reports can target the place.
  r = await call('POST', '/api/report', { place_id: id, reason: 'place', details: 'test' }, users.stranger);
  assert.equal(r.status, 200);

  // Friends-only: strangers can't see it anymore.
  await call('PATCH', `/api/studio/places/${id}`, { visibility: 'friends' }, users.maker);
  assert.equal((await call('GET', `/api/places/${id}`, null, users.stranger)).status, 404);

  // Delete.
  assert.equal((await call('DELETE', `/api/studio/places/${id}`, null, users.maker)).status, 200);
  assert.equal((await call('GET', `/api/studio/places/${id}`, null, users.maker)).status, 404);
});

test('assets: upload, serve, quota, delete', async () => {
  // A 1x1 PNG.
  const png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
  let r = await call('POST', '/api/assets', { name: 'dot', image: png }, users.maker);
  assert.equal(r.status, 200, r.raw);
  const a = r.data.asset;
  assert.equal(a.width, 1);
  assert.match(a.ref, /^asset:\/\//);
  const img = await fetch(base + a.url);
  assert.equal(img.headers.get('content-type'), 'image/png');
  assert.equal((await call('POST', '/api/assets', { name: 'x', image: 'bm90IGFuIGltYWdl' }, users.maker)).status, 400);
  r = await call('GET', '/api/assets', null, users.maker);
  assert.equal(r.data.usage.count, 1);
  assert.equal((await call('DELETE', `/api/assets/${a.id}`, null, users.guest)).status, 403);
  assert.equal((await call('DELETE', `/api/assets/${a.id}`, null, users.maker)).status, 200);
});

test('the app ships the same runtime and schema as the server', async () => {
  const fs = await import('node:fs');
  const read = (p) => fs.readFileSync(new URL(p, import.meta.url), 'utf8');
  assert.equal(read('../../client/studio/runtime/runtime.luau'), read('../src/studio/runtime/runtime.luau'), 'run tools/sync_runtime.sh');
  assert.equal(read('../../client/studio/runtime/classes.json'), read('../src/studio/runtime/classes.json'), 'run tools/sync_runtime.sh');
});
