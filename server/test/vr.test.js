import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { WebSocket } from 'ws';
import { startServer } from '../src/index.js';
import { vrHands } from '../src/game.js';
import { LATEST_CLIENT } from '../src/version.js';

const PORT = 17411;
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
    ws.all = (pred) => inbox.filter(pred);
    ws.next = async (pred, ms = 3000) => {
      const end = Date.now() + ms;
      for (;;) {
        const i = inbox.findIndex(pred);
        if (i >= 0) return inbox.splice(i, 1)[0];
        if (Date.now() > end) throw new Error('timed out');
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
  const year = new Date().getFullYear();
  for (const [name, born] of [['headset', '2000-01-01'], ['teen', `${year - 15}-01-01`], ['kid', `${year - 10}-01-01`]]) {
    users[name] = (await call('POST', '/api/register', { username: name, password: 'secret123', birthdate: born })).data.token;
  }
});
after(async () => {
  await app.close();
});

test('vr: hands are pulled back within reach, broken ones are dropped', () => {
  assert.deepEqual(vrHands([0.3, 1.2, -0.5, -0.3, 1.5, -0.4]), [0.3, 1.2, -0.5, -0.3, 1.5, -0.4]);
  // A hand 30 studs away (a "long arm" cheat) comes back to an arm's reach.
  const far = vrHands([0, 1.32, -30, null, null, null]);
  assert.ok(Math.abs(far[2] + 1.6) < 0.01, JSON.stringify(far));
  assert.deepEqual(far.slice(3), [null, null, null]);
  assert.equal(vrHands([null, null, null, null, null, null]), null);
  assert.equal(vrHands('nope'), null);
  assert.equal(vrHands([1, 2, 3]), null);
});

test('vr: a headset player\'s hands reach players 13 and older, not younger ones', async () => {
  const vr = await connect(users.headset);
  const teen = await connect(users.teen);
  const kid = await connect(users.kid);
  vr.send2({ t: 'join', game: 'playground', server: 'new', vr: true });
  const w = await vr.next((m) => m.t === 'welcome');
  for (const ws of [teen, kid]) {
    ws.send2({ t: 'join', game: 'playground', server: w.server.id });
    await ws.next((m) => m.t === 'welcome');
  }
  const me = w.you;
  for (let i = 0; i < 4; i++) {
    vr.send2({ t: 'state', p: [0, 0.6, 15.5 + i * 0.05], r: 0, a: 'idle', h: [0.3, 1.2, -0.5, -0.3, 1.6, -0.3] });
    await new Promise((r) => setTimeout(r, 80));
  }
  const mine = (ws) => ws.all((m) => m.t === 's').flatMap((m) => m.s).filter((s) => s[0] === me);
  await new Promise((r) => setTimeout(r, 200));
  assert.ok(mine(teen).some((s) => Array.isArray(s[6]) && s[6][1] === 1.2), JSON.stringify(mine(teen)));
  assert.ok(mine(kid).length > 0 && mine(kid).every((s) => s.length === 6), JSON.stringify(mine(kid)));
  // Someone who isn't in VR can't send hands at all.
  teen.send2({ t: 'state', p: [1, 0.6, 15.5], r: 0, a: 'idle', h: [0.3, 1.2, -0.5, -0.3, 1.6, -0.3] });
  await new Promise((r) => setTimeout(r, 200));
  const teenStates = vr.all((m) => m.t === 's').flatMap((m) => m.s).filter((s) => s[0] !== me);
  assert.ok(teenStates.length > 0 && teenStates.every((s) => s.length === 6), JSON.stringify(teenStates));
  for (const ws of [vr, teen, kid]) ws.close();
});
