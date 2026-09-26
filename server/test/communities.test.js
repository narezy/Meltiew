import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { WebSocket } from 'ws';
import { startServer } from '../src/index.js';
import { LATEST_CLIENT } from '../src/version.js';
import { templatePlace } from '../src/studio/places.js';

const PORT = 17400;
const base = `http://127.0.0.1:${PORT}`;
let app;
const users = {};
const ids = {};

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
  for (const name of ['boss', 'builder', 'fan', 'kid']) {
    const r = await call('POST', '/api/register', { username: name, password: 'secret123', birthdate: '2000-01-01' });
    users[name] = r.data.token;
    ids[name] = r.data.user.id;
  }
});
after(async () => {
  await app.close();
});

test('communities: paid creation, roles, channels, members', async () => {
  // Costs 10 pieces or 100 orbs.
  let r = await call('POST', '/api/communities', { name: 'Obby Makers', currency: 'pieces' }, users.boss);
  assert.equal(r.status, 402);
  app.db.prepare('UPDATE users SET pieces = 15, orbs = 150 WHERE id = ?').run(ids.boss);
  r = await call('POST', '/api/communities', { name: 'Obby Makers', description: 'We build obbies', currency: 'orbs' }, users.boss);
  assert.equal(r.status, 200, r.raw);
  assert.equal(r.data.wallet.orbs, 50);
  assert.equal(r.data.wallet.pieces, 15);
  const c = r.data.community;
  assert.equal(c.me.rank, 255);
  assert.deepEqual(c.channels.map((ch) => ch.name), ['general', 'announcements']);
  // Names are unique (any case).
  assert.equal((await call('POST', '/api/communities', { name: 'obby makers', currency: 'pieces' }, users.boss)).data.error, 'community_name_taken');

  // Search, join.
  r = await call('GET', '/api/communities?q=obby', null, users.fan);
  assert.equal(r.data.communities[0].id, c.id);
  for (const who of ['builder', 'fan', 'kid']) assert.equal((await call('POST', `/api/communities/${c.id}/join`, null, users[who])).status, 200);
  r = await call('GET', `/api/communities/${c.id}`, null, users.fan);
  assert.equal(r.data.community.members, 4);
  assert.equal(r.data.community.me.role_name, 'Member');

  // Channels: members post in general, not in announcements (rank 200).
  const general = c.channels[0].id;
  const news = c.channels[1].id;
  r = await call('POST', `/api/communities/${c.id}/channels/${general}/messages`, { text: 'hi all' }, users.fan);
  assert.equal(r.status, 200, r.raw);
  const msgId = r.data.message.id;
  assert.equal((await call('POST', `/api/communities/${c.id}/channels/${news}/messages`, { text: 'news!' }, users.fan)).status, 403);
  assert.equal((await call('POST', `/api/communities/${c.id}/channels/${news}/messages`, { text: 'Update out' }, users.boss)).status, 200);
  r = await call('GET', `/api/communities/${c.id}/channels/${general}/messages?after=0`, null, users.kid);
  assert.deepEqual(r.data.messages.map((m) => m.body), ['hi all']);
  assert.equal(r.data.messages[0].author.username, 'fan');

  // Roles: the owner makes builder a Builder; a Member can't hand out roles.
  const builderRole = c.roles.find((x) => x.name === 'Builder');
  assert.equal((await call('PATCH', `/api/communities/${c.id}/members/${ids.builder}`, { role_id: builderRole.id }, users.fan)).status, 403);
  assert.equal((await call('PATCH', `/api/communities/${c.id}/members/${ids.builder}`, { role_id: builderRole.id }, users.boss)).status, 200);
  // A custom moderator role for fan.
  r = await call('POST', `/api/communities/${c.id}/roles`, { name: 'Mod', rank: 50, perms: ['moderate', 'post', 'nonsense'] }, users.boss);
  const mod = r.data.community.roles.find((x) => x.name === 'Mod');
  assert.deepEqual(mod.perms, ['moderate', 'post']);
  await call('PATCH', `/api/communities/${c.id}/members/${ids.fan}`, { role_id: mod.id }, users.boss);
  // The mod deletes kid's message and bans kid; can't touch the builder (ranked higher).
  r = await call('POST', `/api/communities/${c.id}/channels/${general}/messages`, { text: 'spam' }, users.kid);
  assert.equal((await call('DELETE', `/api/communities/${c.id}/messages/${r.data.message.id}`, null, users.fan)).status, 200);
  assert.equal((await call('DELETE', `/api/communities/${c.id}/members/${ids.builder}`, null, users.fan)).status, 403);
  assert.equal((await call('DELETE', `/api/communities/${c.id}/members/${ids.kid}?ban=1`, null, users.fan)).status, 200);
  assert.equal((await call('POST', `/api/communities/${c.id}/join`, null, users.kid)).status, 403);
  // Authors delete their own messages.
  assert.equal((await call('DELETE', `/api/communities/${c.id}/messages/${msgId}`, null, users.fan)).status, 200);
  // The owner can't leave (delete it instead); others can.
  assert.equal((await call('POST', `/api/communities/${c.id}/leave`, null, users.boss)).status, 400);
  r = await call('GET', '/api/communities/mine', null, users.builder);
  assert.equal(r.data.communities[0].role_name, 'Builder');
});

test('community places: builders edit together; saving over a newer save asks first', async () => {
  let r = await call('GET', '/api/communities/mine', null, users.boss);
  const cid = r.data.communities[0].id;
  // A plain member can't make places for it; the builder can.
  assert.equal((await call('POST', '/api/studio/places', { name: 'Team obby', community_id: cid }, users.fan)).status, 403);
  r = await call('POST', '/api/studio/places', { name: 'Team obby', community_id: cid }, users.builder);
  assert.equal(r.status, 200, r.raw);
  const place = r.data.place;
  assert.equal(place.community.id, cid);
  // The owner sees it in Studio too, and opens it.
  r = await call('GET', '/api/studio/places', null, users.boss);
  assert.ok(r.data.places.some((p) => p.id === place.id));
  assert.ok(r.data.communities.some((x) => x.id === cid));
  r = await call('GET', `/api/studio/places/${place.id}`, null, users.boss);
  assert.equal(r.status, 200);
  const melt = r.data.melt;
  const v0 = r.data.place.version;
  // The builder saves first...
  assert.equal((await call('PUT', `/api/studio/places/${place.id}`, { melt, base_version: v0 }, users.builder)).status, 200);
  // ...then the owner's save from the older version is stopped, and goes through when forced.
  r = await call('PUT', `/api/studio/places/${place.id}`, { melt, base_version: v0 }, users.boss);
  assert.equal(r.status, 409);
  assert.equal(r.data.by, 'builder');
  assert.equal((await call('PUT', `/api/studio/places/${place.id}`, { melt, base_version: v0, force: true }, users.boss)).status, 200);
  // Outsiders and members without "places" can't edit it.
  assert.equal((await call('GET', `/api/studio/places/${place.id}`, null, users.fan)).status, 403);
  // The place page shows the community as its maker.
  await call('PATCH', `/api/studio/places/${place.id}`, { visibility: 'public' }, users.builder);
  r = await call('GET', `/api/places/${place.id}`, null, users.kid);
  assert.equal(r.data.place.community.name, 'Obby Makers');
  // Deleting the community gives its places back to their makers.
  assert.equal((await call('DELETE', `/api/communities/${cid}`, null, users.builder)).status, 403);
  assert.equal((await call('DELETE', `/api/communities/${cid}`, null, users.boss)).status, 200);
  r = await call('GET', `/api/places/${place.id}`, null, users.kid);
  assert.equal(r.data.place.community, undefined);
});
