import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import WebSocket from 'ws';
import { startServer } from '../src/index.js';
import { LATEST_CLIENT } from '../src/version.js';
import { templatePlace } from '../src/studio/places.js';

let app;
const PORT = 17352;
const base = `http://127.0.0.1:${PORT}`;
const users = {};
const ids = {};

async function call(method, path, body, token, headers = {}) {
  const res = await fetch(base + path, {
    method,
    headers: { 'content-type': 'application/json', 'x-client': 'app', 'x-client-version': LATEST_CLIENT, ...(token ? { authorization: `Bearer ${token}` } : {}), ...headers },
    body: body === null || body === undefined ? undefined : typeof body === 'string' ? body : JSON.stringify(body),
  });
  const text = await res.text();
  let data = {};
  try {
    data = JSON.parse(text);
  } catch {}
  return { status: res.status, data, raw: text };
}

before(async () => {
  app = startServer({ port: PORT, dbFile: ':memory:' });
  for (const [name, bd] of [['shopper', '2000-01-01'], ['creator', '2001-02-02']]) {
    const r = await call('POST', '/api/register', { username: name, password: 'secret123', birthdate: bd });
    users[name] = r.data.token;
    ids[name] = r.data.user.id;
  }
});
after(async () => {
  await app.close();
});

test('daily orbs once a day, shop prices, ownership', async () => {
  let r = await call('GET', '/api/me', null, users.shopper);
  assert.equal(r.data.daily_bonus, 15);
  assert.equal(r.data.user.wallet.orbs, 15);
  assert.deepEqual(r.data.user.owned.faces, [':D', ':)']);
  r = await call('GET', '/api/me', null, users.shopper);
  assert.equal(r.data.daily_bonus, 0, 'only once a day');

  r = await call('GET', '/api/shop', null, users.shopper);
  const tail = r.data.accessories.find((a) => a.id === 'cattail');
  assert.ok(tail.price.pieces > 0);
  const cap = r.data.accessories.find((a) => a.id === 'cap');
  assert.ok(cap.price.orbs > 0);

  // Can't wear or buy what you can't afford.
  assert.equal((await call('PATCH', '/api/me', { accessories: ['cap'] }, users.shopper)).status, 403);
  assert.equal((await call('PATCH', '/api/me', { face: 'uwu' }, users.shopper)).status, 403);
  r = await call('POST', '/api/shop/buy', { kind: 'accessory', id: 'cap' }, users.shopper);
  assert.equal(r.status, 402);

  app.db.prepare('UPDATE users SET orbs = 1000, pieces = 100 WHERE id = ?').run(ids.shopper);
  r = await call('POST', '/api/shop/buy', { kind: 'accessory', id: 'cap' }, users.shopper);
  assert.equal(r.status, 200, r.raw);
  assert.equal(r.data.wallet.orbs, 1000 - cap.price.orbs);
  assert.ok(r.data.owned.accessories.includes('cap'));
  // Buying twice costs nothing more.
  r = await call('POST', '/api/shop/buy', { kind: 'accessory', id: 'cap' }, users.shopper);
  assert.equal(r.data.wallet.orbs, 1000 - cap.price.orbs);
  r = await call('PATCH', '/api/me', { accessories: ['cap'] }, users.shopper);
  assert.equal(r.status, 200, r.raw);
  assert.deepEqual(r.data.user.accessories, ['cap']);
  r = await call('POST', '/api/shop/buy', { kind: 'face', id: '<3' }, users.shopper);
  assert.equal(r.data.wallet.pieces, 85);
  assert.equal((await call('PATCH', '/api/me', { face: '<3' }, users.shopper)).status, 200);
});

test('quests: three a day, claim only when done', async () => {
  let r = await call('GET', '/api/quests', null, users.shopper);
  assert.equal(r.data.quests.length, 3);
  const first = r.data.quests[0];
  r = await call('POST', `/api/quests/${first.id}/claim`, null, users.shopper);
  assert.equal(r.status, 400);
  // Finish it by hand and claim.
  const econ = app.hub.economy;
  const kinds = { playground10: ['time_playground', 600], friend: ['with_friend', 1], places3: ['places', 1], play30: ['time', 1800], like: ['like', 1], emotes5: ['emote', 5] };
  const [kind, amount] = kinds[first.id];
  if (kind === 'places') for (const p of ['a', 'b', 'c']) econ.progress(ids.shopper, 'places', 1, p);
  else econ.progress(ids.shopper, kind, amount);
  const before = (await call('GET', '/api/me/wallet', null, users.shopper)).data.wallet.orbs;
  r = await call('POST', `/api/quests/${first.id}/claim`, null, users.shopper);
  assert.equal(r.status, 200, r.raw);
  assert.equal(r.data.wallet.orbs, before + first.reward);
  r = await call('POST', `/api/quests/${first.id}/claim`, null, users.shopper);
  assert.equal(r.data.wallet.orbs, before + first.reward, 'claimed once');
});

test('payments: signed callback credits pieces once; bad signatures are refused', async () => {
  const secret = 'test-secret';
  app.db.prepare("INSERT OR REPLACE INTO config (key, value) VALUES ('rollypay_secret', ?), ('rollypay_api_key', 'k')").run(secret);
  // Payments are created against RollyPay; here we add the row the way createPayment does.
  app.db.prepare("INSERT INTO payments (id, user_id, pack_id, pieces, amount, status, created_at) VALUES ('mptest', ?, 'p110', 110, '99.00', 'created', ?)").run(ids.creator, Date.now());
  const body = JSON.stringify({ event_type: 'payment.paid', payment_id: 'pay_1', order_id: 'mptest', status: 'paid', amount: '99.00', currency: 'RUB' });
  const ts = String(Math.floor(Date.now() / 1000));
  const sig = crypto.createHmac('sha256', secret).update(`${ts}.${body}`).digest('hex');
  let r = await call('POST', '/api/payments/rollypay/callback', body, null, { 'x-timestamp': ts, 'x-signature': 'bad' + sig.slice(3) });
  assert.equal(r.status, 401);
  r = await call('POST', '/api/payments/rollypay/callback', body, null, { 'x-timestamp': ts, 'x-signature': sig });
  assert.equal(r.status, 200, r.raw);
  r = await call('POST', '/api/payments/rollypay/callback', body, null, { 'x-timestamp': ts, 'x-signature': sig });
  assert.equal(r.status, 200);
  r = await call('GET', '/api/me/wallet', null, users.creator);
  assert.equal(r.data.wallet.pieces, 110);
  r = await call('GET', '/api/pay/mptest', null, users.creator);
  assert.equal(r.data.status, 'paid');
});

function connect(token) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`ws://127.0.0.1:${PORT}/ws?token=${token}&v=${LATEST_CLIENT}&luau=1`);
    const msgs = [];
    const waiters = [];
    ws.on('message', (raw) => {
      const m = JSON.parse(raw.toString());
      const items = m.t === 'r' ? m.o.map((o) => ({ ...o, r: true })) : [m];
      for (const it of items) {
        const i = waiters.findIndex((w) => w.pred(it));
        if (i >= 0) waiters.splice(i, 1)[0].resolve(it);
        else msgs.push(it);
      }
    });
    ws.next = (pred, ms = 5000) => {
      const i = msgs.findIndex(pred);
      if (i >= 0) return Promise.resolve(msgs.splice(i, 1)[0]);
      return new Promise((res, rej) => {
        waiters.push({ pred, resolve: res });
        setTimeout(() => rej(new Error('timeout')), ms).unref();
      });
    };
    ws.send2 = (m) => ws.send(JSON.stringify(m));
    ws.on('open', () => resolve(ws));
    ws.on('error', reject);
  });
}

test('gamepasses and DataStore in a place', async () => {
  let r = await call('POST', '/api/studio/places', { name: 'Shop test' }, users.creator);
  const placeId = r.data.place.id;
  r = await call('POST', `/api/studio/places/${placeId}/passes`, { name: 'VIP', price: 50 }, users.creator);
  assert.equal(r.status, 200, r.raw);
  const passId = r.data.pass.id;
  assert.equal((await call('POST', `/api/studio/places/${placeId}/passes`, { name: 'x', price: 5 }, users.shopper)).status, 403);

  const melt = templatePlace('Shop test');
  melt.tree.k.find((n) => n.c === 'ServerScriptService').k[0].p.Source = `
local MS = game:GetService("MarketplaceService")
local ds = game:GetService("DataStoreService"):GetDataStore("stats")
game.Players.PlayerAdded:Connect(function(p)
  local n = ds:IncrementAsync("visits_" .. p.UserId, 1)
  ds:SetAsync("last", { name = p.Name, pos = Vector3.new(1, 2, 3) })
  local last = ds:GetAsync("last")
  print("ds", n, last.name, last.pos.Y, MS:UserOwnsGamePassAsync(p.UserId, ${passId}), MS:GetGamePassInfo(${passId}).Name)
end)
MS.PromptGamePassPurchaseFinished:Connect(function(p, id, ok) print("bought", p.Name, id, ok, MS:UserOwnsGamePassAsync(p.UserId, id)) end)`;
  r = await call('PUT', `/api/studio/places/${placeId}`, { melt }, users.creator);
  assert.equal(r.status, 200, r.raw);

  // The creator plays (and sees the server console); someone buys the pass meanwhile.
  const ws = await connect(users.creator);
  await ws.next((m) => m.t === 'hello');
  ws.send2({ t: 'join', game: placeId, server: 'auto' });
  const welcome = await ws.next((m) => m.t === 'welcome');
  assert.deepEqual(welcome.place.pass_info.map((p) => p.name), ['VIP']);
  let line = await ws.next((m) => m.o === 'print' && (m.msg.startsWith('ds') || m.level === 'error'));
  assert.equal(line.msg, 'ds 1 creator 2 false VIP');

  const creatorBefore = (await call('GET', '/api/me/wallet', null, users.creator)).data.wallet.pieces;
  r = await call('POST', `/api/passes/${passId}/buy`, null, users.shopper);
  assert.equal(r.status, 200, r.raw);
  assert.equal(r.data.pass.owned, true);
  const creatorAfter = (await call('GET', '/api/me/wallet', null, users.creator)).data.wallet.pieces;
  assert.equal(creatorAfter - creatorBefore, 47, 'creator gets 95%');

  // The creator buys their own pass while playing: the script hears about it.
  app.db.prepare('UPDATE users SET pieces = pieces + 100 WHERE id = ?').run(ids.creator);
  r = await call('POST', `/api/passes/${passId}/buy`, null, users.creator);
  assert.equal(r.status, 200, r.raw);
  line = await ws.next((m) => m.o === 'print' && m.msg.startsWith('bought'));
  assert.equal(line.msg, `bought creator ${passId} true true`);
  ws.close();

  // Saved data outlives the server.
  const row = app.db.prepare("SELECT value FROM datastore WHERE place_id = ? AND key = 'last'").get(placeId);
  assert.deepEqual(JSON.parse(row.value), { name: 'creator', pos: { $v3: [1, 2, 3] } });
});
