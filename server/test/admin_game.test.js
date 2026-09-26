import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { WebSocket } from 'ws';
import { startServer } from '../src/index.js';
import { LATEST_CLIENT } from '../src/version.js';
import { templatePlace } from '../src/studio/places.js';

const PORT = 17398;
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
  for (const name of ['nrz', 'maker', 'player']) {
    const r = await call('POST', '/api/register', { username: name, password: 'secret123', birthdate: '2000-01-01' });
    users[name] = r.data.token;
  }
});
after(async () => {
  await app.close();
});

test('the owner\'s in-game admin: mute, bring, kick; nobody else can; flying is not cheating', async () => {
  const boss = await connect(users.nrz);
  const kid = await connect(users.player);
  const other = await connect(users.maker);
  boss.send2({ t: 'join', game: 'playground', server: 'new' });
  const w = await boss.next((m) => m.t === 'welcome');
  kid.send2({ t: 'join', game: 'playground', server: w.server.id });
  const wk = await kid.next((m) => m.t === 'welcome');
  other.send2({ t: 'join', game: 'playground', server: w.server.id });
  await other.next((m) => m.t === 'welcome');
  const kidId = wk.you;

  // Not the owner: ignored.
  other.send2({ t: 'admin', cmd: 'mute', id: kidId });
  kid.send2({ t: 'chat', m: 'hello' });
  assert.equal((await other.next((m) => m.t === 'chat')).m, 'hello');

  boss.send2({ t: 'admin', cmd: 'mute', id: kidId });
  const res = await boss.next((m) => m.t === 'admin');
  assert.deepEqual(res.muted, [kidId]);
  await kid.next((m) => m.t === 'sys' && m.k === 'muted');
  kid.send2({ t: 'chat', m: 'spam' });
  await kid.next((m) => m.t === 'sys' && m.k === 'muted');
  boss.send2({ t: 'admin', cmd: 'unmute', id: kidId });
  await boss.next((m) => m.t === 'admin' && m.ok === 'unmute');
  kid.send2({ t: 'chat', m: 'back' });
  assert.equal((await other.next((m) => m.t === 'chat')).m, 'back');

  // Flying straight up far and fast: the owner is never corrected.
  for (let i = 1; i <= 10; i++) {
    boss.send2({ t: 'state', p: [0, 0.6 + i * 8, 15], r: 0, a: 'jump' });
    await new Promise((r) => setTimeout(r, 30));
  }
  boss.send2({ t: 'admin', cmd: 'bring', id: kidId });
  const corr = await kid.next((m) => m.t === 'correct');
  assert.ok(corr.p[1] > 70, 'brought up to the flying owner');
  await boss.next((m) => m.t === 'admin' && m.ok === 'bring');
  await new Promise((r) => setTimeout(r, 150));
  // (a correction for the owner would have arrived by now)
  boss.send2({ t: 'ping', c: 1 });
  const seen = [];
  await boss.next((m) => { seen.push(m.t); return m.t === 'pong'; });
  assert.ok(!seen.includes('correct'));

  boss.send2({ t: 'admin', cmd: 'kick', id: kidId });
  const k = await kid.next((m) => m.t === 'kicked');
  assert.equal(k.code, 'kicked');
  boss.close();
  other.close();
});
