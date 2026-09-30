import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import zlib from 'node:zlib';
import { startServer } from '../src/index.js';
import { LATEST_CLIENT } from '../src/version.js';

const PORT = 17460;
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

// A transparent PNG of the given size.
function png(w, h) {
  const crc = (buf) => {
    let c = ~0;
    for (const b of buf) {
      c ^= b;
      for (let k = 0; k < 8; k++) c = (c >>> 1) ^ (0xedb88320 & -(c & 1));
    }
    return ~c >>> 0;
  };
  const chunk = (type, data) => {
    const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
    const td = Buffer.concat([Buffer.from(type), data]);
    const c = Buffer.alloc(4); c.writeUInt32BE(crc(td));
    return Buffer.concat([len, td, c]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 6;
  const raw = Buffer.alloc((w * 4 + 1) * h);
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]).toString('base64');
}

before(async () => {
  app = startServer({ port: PORT, dbFile: ':memory:' });
  await new Promise((r) => setTimeout(r, 200));
  for (const name of ['maker', 'buyer', 'broke']) {
    const r = await call('POST', '/api/register', { username: name, password: 'secret123', birthdate: '2000-01-01' });
    users[name] = r.data.token;
    ids[name] = r.data.user.id;
  }
  app.db.prepare('UPDATE users SET pieces = 20, orbs = 0 WHERE id = ?').run(ids.maker);
  app.db.prepare('UPDATE users SET pieces = 30 WHERE id = ?').run(ids.buyer);
  app.db.prepare('UPDATE users SET pieces = 0, orbs = 0 WHERE id = ?').run(ids.broke);
});

after(() => app.close());

test('clothing: make, sell, wear, take down', async () => {
  // Only the template's size, and only PNG.
  let r = await call('POST', '/api/studio/clothing', { name: 'Stripes', price: 25, currency: 'pieces', image: png(512, 512) }, users.maker);
  assert.equal(r.data.error, 'clothing_size');
  r = await call('POST', '/api/studio/clothing', { name: 'Stripes', price: 25, currency: 'pieces', image: png(1024, 768) }, users.broke);
  assert.equal(r.status, 402);
  r = await call('POST', '/api/studio/clothing', { name: 'Stripes', price: 25, currency: 'pieces', image: png(1024, 768) }, users.maker);
  assert.equal(r.status, 200, r.raw);
  assert.equal(r.data.wallet.pieces, 10);
  const id = r.data.item.id;
  assert.equal(r.data.item.owned, true);

  // In the catalog; the picture is served.
  r = await call('GET', '/api/clothing', null, users.buyer);
  assert.equal(r.data.items[0].id, id);
  assert.equal(r.data.items[0].owned, false);
  const img = await fetch(base + `/api/clothing/${id}/image`);
  assert.equal(img.headers.get('content-type'), 'image/png');

  // Can't wear what you don't have.
  r = await call('PUT', '/api/me/clothing', { worn: [id] }, users.buyer);
  assert.equal(r.data.error, 'not_owned');
  r = await call('POST', `/api/clothing/${id}/buy`, null, users.buyer);
  assert.equal(r.data.wallet.pieces, 5);
  assert.equal(app.db.prepare('SELECT pieces FROM users WHERE id = ?').get(ids.maker).pieces, 10 + Math.floor(25 * 0.95));
  r = await call('PUT', '/api/me/clothing', { worn: [id] }, users.buyer);
  assert.deepEqual(r.data.worn, [id]);
  r = await call('GET', '/api/me', null, users.buyer);
  assert.deepEqual(r.data.user.clothes, [id]);

  // Someone else can't take it down; its maker can, and then it's gone everywhere.
  r = await call('DELETE', `/api/studio/clothing/${id}`, null, users.buyer);
  assert.equal(r.status, 403);
  r = await call('DELETE', `/api/studio/clothing/${id}`, null, users.maker);
  assert.equal(r.data.ok, true);
  assert.equal((await fetch(base + `/api/clothing/${id}/image`)).status, 404);
  r = await call('GET', '/api/clothing', null, users.buyer);
  assert.equal(r.data.items.length, 0);
});
