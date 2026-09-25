import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import WebSocket from 'ws';
import { startServer } from '../src/index.js';

let app;
const PORT = 17350;
const base = `http://127.0.0.1:${PORT}`;

async function call(method, path, body, token) {
  const res = await fetch(base + path, {
    method,
    headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { status: res.status, data: await res.json() };
}

function connect(token) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`ws://127.0.0.1:${PORT}/ws?token=${token}`);
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
      return new Promise((resolve) => waiters.push({ pred, resolve }));
    };
    ws.send2 = (m) => ws.send(JSON.stringify(m));
    ws.on('open', () => resolve(ws));
    ws.on('error', reject);
  });
}

before(() => {
  app = startServer({ port: PORT, dbFile: ':memory:' });
});
after(async () => {
  await app.close();
});

const users = {};

test('register and login', async () => {
  for (const name of ['alice', 'bob']) {
    const r = await call('POST', '/api/register', { username: name, password: 'secret123', display_name: name.toUpperCase() });
    assert.equal(r.status, 200, JSON.stringify(r.data));
    users[name] = r.data.token;
  }
  const dup = await call('POST', '/api/register', { username: 'ALICE', password: 'secret123' });
  assert.equal(dup.status, 409);
  const badLogin = await call('POST', '/api/login', { username: 'alice', password: 'nope' });
  assert.equal(badLogin.status, 401);
  const ok = await call('POST', '/api/login', { username: 'alice', password: 'secret123' });
  assert.equal(ok.status, 200);
  assert.equal(ok.data.user.display_name, 'ALICE');
});

test('profile update validates input', async () => {
  const r = await call('PATCH', '/api/me', { bio: 'hi', colors: { torso: '#FF00aa' }, hat: 'crown' }, users.alice);
  assert.equal(r.status, 200);
  assert.equal(r.data.user.colors.torso, '#ff00aa');
  assert.equal(r.data.user.colors.head, '#f5f1ec');
  assert.equal((await call('PATCH', '/api/me', { colors: { tail: '#000000' } }, users.alice)).status, 400);
  assert.equal(r.data.user.hat, 'crown');
  assert.equal((await call('PATCH', '/api/me', { hat: 'sombrero' }, users.alice)).status, 400);
  assert.equal((await call('GET', '/api/me')).status, 401);
});

test('friend request flow', async () => {
  let r = await call('POST', '/api/friends/request', { username: 'bob' }, users.alice);
  assert.equal(r.data.relation, 'outgoing');
  r = await call('GET', '/api/friends', null, users.bob);
  assert.equal(r.data.incoming.length, 1);
  r = await call('POST', '/api/friends/accept', { user_id: r.data.incoming[0].id }, users.bob);
  assert.equal(r.data.relation, 'friends');
  r = await call('GET', '/api/friends', null, users.alice);
  assert.equal(r.data.friends[0].username, 'bob');
  r = await call('GET', '/api/users/search?q=bo', null, users.alice);
  assert.equal(r.data.users[0].relation, 'friends');
});

test('game servers cap at 10 players and sync state', async () => {
  const a = await connect(users.alice);
  a.send2({ t: 'join', server: 'auto' });
  const wa = await a.next((m) => m.t === 'welcome');
  const b = await connect(users.bob);
  b.send2({ t: 'join', server: wa.server.id });
  const wb = await b.next((m) => m.t === 'welcome');
  assert.equal(wb.server.id, wa.server.id);
  assert.equal(wb.players.length, 1);
  await a.next((m) => m.t === 'join');

  b.send2({ t: 'state', p: [1, 2, 3], r: 0.5, a: 'walk' });
  const st = await a.next((m) => m.t === 's' && m.s.some((s) => s[5] === 'walk'));
  assert.ok(st);
  a.send2({ t: 'chat', m: 'привет' });
  const chat = await b.next((m) => m.t === 'chat');
  assert.equal(chat.m, 'привет');

  const r = await call('GET', '/api/servers', null, users.alice);
  assert.equal(r.data.servers[0].players, 2);
  const fr = await call('GET', '/api/friends', null, users.alice);
  assert.equal(fr.data.friends[0].playing.server_id, wa.server.id);

  const extra = [];
  for (let i = 0; i < 9; i++) {
    const reg = await call('POST', '/api/register', { username: `p${i}x`, password: 'secret123' });
    const ws = await connect(reg.data.token);
    ws.send2({ t: 'join', server: wa.server.id });
    extra.push({ ws, msg: await ws.next((m) => m.t === 'welcome' || m.t === 'error') });
  }
  assert.equal(extra.filter((e) => e.msg.t === 'welcome').length, 8);
  assert.equal(extra.filter((e) => e.msg.t === 'error' && e.msg.code === 'full').length, 1);

  // auto-join must never land in a full server
  const last = extra.at(-1).ws;
  last.send2({ t: 'join', server: 'auto' });
  const w = await last.next((m) => m.t === 'welcome');
  assert.notEqual(w.server.id, wa.server.id);

  for (const e of extra) e.ws.close();
  a.close();
  b.close();
});

test('errors are localized by header', async () => {
  const en = await fetch(base + '/api/login', { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{"username":"alice","password":"nope"}' });
  assert.equal((await en.json()).message, 'Wrong username or password');
  const ru = await fetch(base + '/api/login', { method: 'POST', headers: { 'content-type': 'application/json', 'x-lang': 'ru' }, body: '{"username":"alice","password":"nope"}' });
  assert.equal((await ru.json()).message, 'Неверный логин или пароль');
});

test('blocking hides chat and prevents friend requests', async () => {
  const a = await connect(users.alice);
  a.send2({ t: 'join', server: 'new' });
  const wa = await a.next((m) => m.t === 'welcome');
  const b = await connect(users.bob);
  b.send2({ t: 'join', server: wa.server.id });
  await b.next((m) => m.t === 'welcome');
  let r = await call('POST', '/api/blocks/add', { username: 'bob' }, users.alice);
  assert.equal(r.data.relation, 'blocked');
  b.send2({ t: 'chat', m: 'spam' });
  a.send2({ t: 'chat', m: 'visible' });
  const got = await a.next((m) => m.t === 'chat');
  assert.equal(got.m, 'visible', 'blocked sender must be filtered');
  r = await call('POST', '/api/friends/request', { username: 'alice' }, users.bob);
  assert.equal(r.status, 403);
  r = await call('GET', '/api/blocks', null, users.alice);
  assert.equal(r.data.users[0].username, 'bob');
  await call('POST', '/api/blocks/remove', { username: 'bob' }, users.alice);
  assert.equal((await call('GET', '/api/blocks', null, users.alice)).data.users.length, 0);
  a.close();
  b.close();
});

test('launch queue is consumed once', async () => {
  let r = await call('POST', '/api/launch', { server: 'nope' }, users.alice);
  assert.equal(r.status, 404);
  r = await call('POST', '/api/launch', { server: 'new' }, users.alice);
  assert.equal(r.status, 200);
  r = await call('GET', '/api/launch', null, users.alice);
  assert.equal(r.data.launch.server, 'new');
  r = await call('GET', '/api/launch', null, users.alice);
  assert.equal(r.data.launch, null);
});

test('bust render upload is validated and served', async () => {
  const bogus = await call('POST', '/api/me/render', { hash: 'abc', png: Buffer.from('hello').toString('base64') }, users.alice);
  assert.equal(bogus.status, 400);
  const png = Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), Buffer.alloc(100)]);
  const ok = await call('POST', '/api/me/render', { hash: 'abc123', png: png.toString('base64') }, users.alice);
  assert.equal(ok.status, 200);
  const me = await call('GET', '/api/me', null, users.alice);
  assert.equal(me.data.user.render, 'abc123');
  const img = await fetch(`${base}/api/avatar/${me.data.user.id}.png`);
  assert.equal(img.headers.get('content-type'), 'image/png');
  const missing = await fetch(`${base}/api/avatar/9999.png`, { redirect: 'manual' });
  assert.equal(missing.status, 302);
});

test('places list, votes and owner author', async () => {
  const reg = await call('POST', '/api/register', { username: 'nrz', password: 'secret123', display_name: 'Narez' });
  users.nrz = reg.data.token;
  assert.equal(reg.data.user.role, 'owner');
  let r = await call('GET', '/api/places', null, users.alice);
  assert.equal(r.data.places[0].id, 'playground');
  assert.equal(r.data.places[0].author.username, 'nrz');
  assert.equal(r.data.places[0].author.role, 'owner');
  r = await call('POST', '/api/places/playground/vote', { value: 1 }, users.alice);
  assert.equal(r.data.place.likes, 1);
  assert.equal(r.data.place.my_vote, 1);
  r = await call('POST', '/api/places/playground/vote', { value: -1 }, users.alice);
  assert.equal(r.data.place.likes, 0);
  assert.equal(r.data.place.dislikes, 1);
  r = await call('POST', '/api/places/playground/vote', { value: 0 }, users.alice);
  assert.equal(r.data.place.dislikes, 0);
  r = await call('GET', '/api/places/playground', null, users.alice);
  assert.ok(Array.isArray(r.data.servers));
});

test('quick play joins the server where a friend is', async () => {
  // Blocking earlier dropped their friendship; make them friends again.
  await call('POST', '/api/friends/request', { username: 'bob' }, users.alice);
  await call('POST', '/api/friends/request', { username: 'alice' }, users.bob);
  const decoy = await connect(users.p0x || (await call('POST', '/api/login', { username: 'p0x', password: 'secret123' })).data.token);
  decoy.send2({ t: 'join', server: 'new' });
  await decoy.next((m) => m.t === 'welcome');
  const b = await connect(users.bob);
  b.send2({ t: 'join', server: 'new' });
  const wb = await b.next((m) => m.t === 'welcome');
  const a = await connect(users.alice);
  a.send2({ t: 'join', server: 'auto' });
  const wa = await a.next((m) => m.t === 'welcome');
  assert.equal(wa.server.id, wb.server.id);
  a.close();
  b.close();
  decoy.close();
});

test('admin endpoints are staff-only and bans lock the account', async () => {
  assert.equal((await call('GET', '/api/admin/stats', null, users.alice)).status, 403);
  const stats = await call('GET', '/api/admin/stats', null, users.nrz);
  assert.equal(stats.status, 200);
  assert.ok(stats.data.users >= 3);
  const list = await call('GET', '/api/admin/users?q=bob', null, users.nrz);
  const bob = list.data.users.find((u) => u.username === 'bob');
  let r = await call('POST', `/api/admin/users/${bob.id}`, { role: 'admin' }, users.nrz);
  assert.equal(r.data.user.role, 'admin');
  // an admin can't touch the owner
  const owner = (await call('GET', '/api/admin/users?q=nrz', null, users.nrz)).data.users[0];
  assert.equal((await call('POST', `/api/admin/users/${owner.id}`, { banned: true }, users.bob)).status, 403);
  r = await call('POST', `/api/admin/users/${bob.id}`, { role: 'user' }, users.nrz);
  r = await call('POST', `/api/admin/users/${bob.id}`, { banned: true, reason: 'spam' }, users.nrz);
  assert.equal(r.data.user.banned, true);
  assert.equal((await call('GET', '/api/me', null, users.bob)).status, 401);
  const login = await call('POST', '/api/login', { username: 'bob', password: 'secret123' });
  assert.equal(login.status, 403);
  assert.match(login.data.message, /spam/);
  await call('POST', `/api/admin/users/${bob.id}`, { banned: false }, users.nrz);
  assert.equal((await call('POST', '/api/login', { username: 'bob', password: 'secret123' })).status, 200);
  assert.equal((await call('POST', '/api/admin/announce', { text: 'hello' }, users.nrz)).status, 200);
});
