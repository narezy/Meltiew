// Studio places on disk and in the database: .marp files, covers, access rules and stats.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { SCHEMA } from './vm.js';

export const MARP_FORMAT = 'marp';
export const MARP_VERSION = 1;
export const MAX_MARP_BYTES = 8 * 1024 * 1024;
export const MAX_NODES = 20000;
export const MAX_SOURCE = 200 * 1024;
export const VISIBILITIES = ['private', 'friends', 'public'];

// Classes that only exist while a game runs; a place file never contains them.
const RUNTIME_ONLY = new Set(Object.entries(SCHEMA.classes).filter(([, c]) => c.runtime).map(([n]) => n).concat(['DataModel']));

/** A new place: a grass baseplate, a spawn and a friendly sky. */
export function templatePlace(name) {
  const v3 = (x, y, z) => ({ $v3: [x, y, z] });
  return {
    format: MARP_FORMAT,
    version: MARP_VERSION,
    meta: { name, description: '', i18n: { name: {}, description: {} } },
    strings: {},
    tree: {
      c: 'DataModel',
      k: [
        {
          c: 'Workspace',
          n: 'Workspace',
          k: [
            { c: 'Part', n: 'Baseplate', p: { Size: v3(128, 1, 128), Position: v3(0, -0.5, 0), Color: { $c3: '#8fd18a' }, Material: 'Grass' } },
            { c: 'SpawnLocation', n: 'SpawnLocation', p: { Position: v3(0, 0.2, 0) } },
          ],
        },
        { c: 'Lighting', n: 'Lighting', k: [{ c: 'Sky', n: 'Sky' }] },
        { c: 'ReplicatedStorage', n: 'ReplicatedStorage' },
        {
          c: 'ServerScriptService',
          n: 'ServerScriptService',
          k: [{ c: 'Script', n: 'Main', p: { Source: STARTER_SCRIPT } }],
        },
        { c: 'ServerStorage', n: 'ServerStorage' },
        { c: 'StarterGui', n: 'StarterGui' },
        { c: 'StarterPlayer', n: 'StarterPlayer', k: [{ c: 'StarterPlayerScripts', n: 'StarterPlayerScripts' }] },
      ],
    },
  };
}

// What a new place's server script starts with.
const STARTER_SCRIPT = `-- Runs on the server when the place starts.
-- Docs: https://meltiew.narez.xyz/docs/studio

game.Players.PlayerAdded:Connect(function(player)
	print(player.DisplayName .. " joined")
end)
`;

function badPlace(reason) {
  const e = new Error(reason);
  e.code = 'bad_place';
  e.reason = reason;
  return e;
}

// Keeps only what the runtime understands: known classes and properties, sane sizes.
function cleanNode(node, depth, counter) {
  if (!node || typeof node !== 'object') throw badPlace('node is not an object');
  if (depth > 64) throw badPlace('tree is too deep');
  if (++counter.n > MAX_NODES) throw badPlace(`more than ${MAX_NODES} objects`);
  const cls = SCHEMA.classes[node.c];
  if (!cls || (RUNTIME_ONLY.has(node.c) && depth > 0)) throw badPlace(`unknown class ${String(node.c).slice(0, 40)}`);
  const out = { c: node.c };
  if (node.n !== undefined) out.n = String(node.n).slice(0, 100);
  const props = {};
  const known = {};
  for (let c = cls; c; c = c.base ? SCHEMA.classes[c.base] : null) Object.assign(known, c.props);
  for (const [k, v] of Object.entries(node.p || {})) {
    const p = known[k];
    if (!p) continue;
    if (typeof v === 'string' && v.length > (p.type === 'source' ? MAX_SOURCE : 4000)) throw badPlace(`${node.c}.${k} is too long`);
    props[k] = v;
  }
  if (Object.keys(props).length) out.p = props;
  if (Array.isArray(node.k) && node.k.length) out.k = node.k.map((ch) => cleanNode(ch, depth + 1, counter));
  return out;
}

export function cleanI18n(obj) {
  const out = {};
  for (const [lang, text] of Object.entries(obj || {})) {
    if (/^[a-z]{2,3}(-[A-Za-z]{2,4})?$/.test(lang) && typeof text === 'string') out[lang] = text.slice(0, 2000);
  }
  return out;
}

/** Validates an uploaded .marp and returns a cleaned copy (throws bad_place). */
export function validateMarp(marp) {
  if (!marp || typeof marp !== 'object') throw badPlace('not a place file');
  if (marp.format !== MARP_FORMAT) throw badPlace('not a .marp file');
  if (!marp.tree || marp.tree.c !== 'DataModel') throw badPlace('missing tree');
  const meta = marp.meta || {};
  const strings = {};
  let n = 0;
  for (const [key, langs] of Object.entries(marp.strings || {})) {
    if (++n > 5000) break;
    if (typeof key === 'string' && key.length <= 100) strings[key] = cleanI18n(langs);
  }
  return {
    format: MARP_FORMAT,
    version: MARP_VERSION,
    meta: {
      name: String(meta.name || 'Untitled').slice(0, 60),
      description: String(meta.description || '').slice(0, 1000),
      i18n: { name: cleanI18n(meta.i18n?.name), description: cleanI18n(meta.i18n?.description) },
    },
    strings,
    tree: cleanNode(marp.tree, 0, { n: 0 }),
  };
}

/** Reads width/height from PNG/JPEG headers; null if it isn't one of those. */
export function imageInfo(buf) {
  if (buf.length > 24 && buf.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) {
    return { mime: 'image/png', ext: 'png', width: buf.readUInt32BE(16), height: buf.readUInt32BE(20) };
  }
  if (buf.length > 4 && buf[0] === 0xff && buf[1] === 0xd8) {
    let i = 2;
    while (i + 9 < buf.length) {
      if (buf[i] !== 0xff) return null;
      const marker = buf[i + 1];
      const len = buf.readUInt16BE(i + 2);
      if (marker >= 0xc0 && marker <= 0xcf && ![0xc4, 0xc8, 0xcc].includes(marker)) {
        return { mime: 'image/jpeg', ext: 'jpg', width: buf.readUInt16BE(i + 7), height: buf.readUInt16BE(i + 5) };
      }
      i += 2 + len;
    }
  }
  return null;
}

export function decodeImage(b64, maxBytes, maxSide = 4096) {
  let buf;
  try {
    buf = Buffer.from(String(b64 || ''), 'base64');
  } catch {
    return null;
  }
  if (!buf.length || buf.length > maxBytes) return null;
  const info = imageInfo(buf);
  if (!info || !info.width || !info.height || info.width > maxSide || info.height > maxSide) return null;
  return { buf, ...info };
}

export class PlaceStore {
  constructor(db, dataDir) {
    this.db = db;
    this.dir = path.join(dataDir, 'places');
    this.mediaDir = path.join(dataDir, 'place_media');
    this.assetDir = path.join(dataDir, 'assets');
    for (const d of [this.dir, this.mediaDir, this.assetDir]) fs.mkdirSync(d, { recursive: true });
    this.cache = new Map(); // id -> { version, marp }
    this.q = {
      one: db.prepare('SELECT * FROM places WHERE id = ? AND deleted = 0'),
      touchPlayer: db.prepare(`INSERT INTO place_players (place_id, user_id, visits, playtime_ms, first_at, last_at) VALUES (?, ?, 1, 0, ?, ?)
        ON CONFLICT(place_id, user_id) DO UPDATE SET visits = visits + 1, last_at = excluded.last_at`),
      addPlayerTime: db.prepare('UPDATE place_players SET playtime_ms = playtime_ms + ? WHERE place_id = ? AND user_id = ?'),
      daily: db.prepare(`INSERT INTO place_daily (place_id, day, visits, playtime_ms) VALUES (?, ?, ?, ?)
        ON CONFLICT(place_id, day) DO UPDATE SET visits = visits + excluded.visits, playtime_ms = playtime_ms + excluded.playtime_ms`),
      addTime: db.prepare('UPDATE places SET playtime_ms = playtime_ms + ? WHERE id = ?'),
    };
  }

  newId() {
    return 'p' + crypto.randomBytes(5).toString('hex');
  }

  file(id) {
    if (!/^p[0-9a-f]{10}$/.test(id)) throw new Error('bad place id');
    return path.join(this.dir, id + '.marp');
  }

  write(id, marp) {
    const f = this.file(id);
    fs.writeFileSync(f + '.tmp', JSON.stringify(marp));
    fs.renameSync(f + '.tmp', f);
    this.cache.delete(id);
  }

  /** The place file (cached by version). Null for the built-in playground. */
  load(id) {
    const row = this.q.one.get(id);
    if (!row || row.kind !== 'studio') return null;
    const hit = this.cache.get(id);
    if (hit && hit.version === row.version) return hit.marp;
    let marp;
    try {
      marp = JSON.parse(fs.readFileSync(this.file(id), 'utf8'));
    } catch {
      return null;
    }
    this.cache.set(id, { version: row.version, marp });
    return marp;
  }

  remove(id) {
    try {
      fs.unlinkSync(this.file(id));
    } catch {}
    this.cache.delete(id);
  }

  /** Who may open or join a place. */
  canSee(row, user, isFriend) {
    if (!row || row.deleted) return false;
    if (row.kind !== 'studio' || row.visibility === 'public') return true;
    if (!user) return false;
    if (row.owner_id === user.id || user.role === 'owner' || user.role === 'admin') return true;
    return row.visibility === 'friends' && isFriend(row.owner_id, user.id);
  }

  recordVisit(placeId, userId) {
    const now = Date.now();
    this.q.touchPlayer.run(placeId, userId, now, now);
    this.q.daily.run(placeId, new Date(now).toISOString().slice(0, 10), 1, 0);
  }

  recordPlaytime(placeId, userId, ms) {
    if (!(ms > 0)) return;
    ms = Math.min(Math.round(ms), 24 * 3600 * 1000);
    this.q.addTime.run(ms, placeId);
    this.q.addPlayerTime.run(ms, placeId, userId);
    this.q.daily.run(placeId, new Date().toISOString().slice(0, 10), 0, ms);
  }
}
