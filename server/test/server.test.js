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
