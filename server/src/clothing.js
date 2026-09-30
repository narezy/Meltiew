// Clothing: shirts anyone can make. A shirt is one picture laid out like the template
// (client/tools/clothing_template: the torso, arms and legs unfolded), worn over the
// body colours; several can be worn at once, bottom to top. Making one costs 10 pieces
// or 100 orbs; it's sold for pieces (95% to the maker, or to the community's bank) or
// given away free.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { decodeImage } from './studio/places.js';
import { CREATOR_SHARE } from './economy.js';

export const TEMPLATE_W = 1024;
export const TEMPLATE_H = 768;
export const MAX_WORN = 5;
const IMAGE_BYTES = 3 * 1024 * 1024;
const MAKE_PRICE = { pieces: 10, orbs: 100 };
const MAX_PRICE = 100_000;
const PAGE = 40;

export function createClothing({ db, economy, communities, HttpError, bad, cleanText, requireAuth, writeLimiter, mediaDir, authorCard, log = () => {} }) {
  const dir = path.join(mediaDir, 'clothing');
  fs.mkdirSync(dir, { recursive: true });
  db.exec(`CREATE TABLE IF NOT EXISTS clothing (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    kind         TEXT NOT NULL DEFAULT 'shirt',
    name         TEXT NOT NULL,
    description  TEXT NOT NULL DEFAULT '',
    creator_id   INTEGER NOT NULL,
    community_id INTEGER,
    price        INTEGER NOT NULL DEFAULT 0,
    image        TEXT NOT NULL,
    sales        INTEGER NOT NULL DEFAULT 0,
    created_at   INTEGER NOT NULL,
    updated_at   INTEGER NOT NULL,
    deleted      INTEGER NOT NULL DEFAULT 0
  )`);
  db.exec(`CREATE TABLE IF NOT EXISTS clothing_owned (
    user_id     INTEGER NOT NULL,
    clothing_id INTEGER NOT NULL,
    at          INTEGER NOT NULL,
    PRIMARY KEY (user_id, clothing_id)
  )`);
  db.exec('CREATE INDEX IF NOT EXISTS clothing_list ON clothing(deleted, created_at)');
  const cols = new Set(db.prepare('PRAGMA table_info(users)').all().map((c) => c.name));
  if (!cols.has('clothes')) db.exec("ALTER TABLE users ADD COLUMN clothes TEXT NOT NULL DEFAULT '[]'");

  const q = {
    one: db.prepare('SELECT * FROM clothing WHERE id = ? AND deleted = 0'),
    list: db.prepare(`SELECT * FROM clothing WHERE deleted = 0 AND (? = '' OR name LIKE ?) ORDER BY
      CASE WHEN ? = 'popular' THEN sales END DESC, created_at DESC LIMIT ? OFFSET ?`),
    mine: db.prepare(`SELECT * FROM clothing WHERE deleted = 0 AND (creator_id = ? OR community_id IN (SELECT value FROM json_each(?)))
      ORDER BY created_at DESC`),
    insert: db.prepare('INSERT INTO clothing (kind, name, description, creator_id, community_id, price, image, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)'),
    update: db.prepare('UPDATE clothing SET name = ?, description = ?, price = ?, image = ?, updated_at = ? WHERE id = ?'),
    remove: db.prepare('UPDATE clothing SET deleted = 1, updated_at = ? WHERE id = ?'),
    owns: db.prepare('SELECT 1 FROM clothing_owned WHERE user_id = ? AND clothing_id = ?'),
    give: db.prepare('INSERT OR IGNORE INTO clothing_owned (user_id, clothing_id, at) VALUES (?, ?, ?)'),
    owned: db.prepare(`SELECT c.* FROM clothing_owned o JOIN clothing c ON c.id = o.clothing_id
      WHERE o.user_id = ? AND c.deleted = 0 ORDER BY o.at DESC`),
    sold: db.prepare('UPDATE clothing SET sales = sales + 1 WHERE id = ?'),
    user: db.prepare('SELECT * FROM users WHERE id = ?'),
    community: db.prepare('SELECT id, name, color FROM communities WHERE id = ? AND deleted = 0'),
    bankAdd: db.prepare('UPDATE communities SET bank = bank + ? WHERE id = ?'),
    bankLog: db.prepare('INSERT INTO community_bank_log (community_id, delta, reason, ref, user_id, created_at) VALUES (?, ?, ?, ?, ?, ?)'),
    setWorn: db.prepare('UPDATE users SET clothes = ? WHERE id = ?'),
  };

  function tx(fn) {
    db.exec('BEGIN');
    try {
      const out = fn();
      db.exec('COMMIT');
      return out;
    } catch (err) {
      db.exec('ROLLBACK');
      throw err;
    }
  }

  const imageUrl = (c) => `/api/clothing/${c.id}/image?v=${c.image.slice(0, 8)}`;

  function view(c, userId = 0) {
    const creator = q.user.get(c.creator_id);
    const community = c.community_id ? q.community.get(c.community_id) : null;
    return {
      id: c.id,
      kind: c.kind,
      name: c.name,
      description: c.description,
      price: c.price,
      image: imageUrl(c),
      sales: c.sales,
      created_at: c.created_at,
      creator: creator ? authorCard(creator) : null,
      community: community ? { id: community.id, name: community.name, color: community.color } : null,
      owned: userId ? !!q.owns.get(userId, c.id) || c.creator_id === userId : false,
      mine: userId ? canEdit(c, userId) : false,
    };
  }

  /** The maker, or a manager of the community it belongs to. */
  function canEdit(c, userId) {
    if (c.creator_id === userId) return true;
    if (!c.community_id) return false;
    const mem = communities.membership(c.community_id, userId);
    return !!mem && (mem.rank >= 255 || mem.perms.has('manage'));
  }

  function saveImage(b64) {
    const img = decodeImage(b64, IMAGE_BYTES, 4096);
    if (!img || img.ext !== 'png') throw bad('clothing_png');
    if (img.width !== TEMPLATE_W || img.height !== TEMPLATE_H) throw bad('clothing_size');
    const name = crypto.createHash('sha256').update(img.buf).digest('hex').slice(0, 32) + '.png';
    fs.writeFileSync(path.join(dir, name), img.buf);
    return name;
  }

  function cleanPrice(v) {
    const n = Math.floor(Number(v ?? 0));
    if (!Number.isFinite(n) || n < 0 || n > MAX_PRICE) throw bad('bad_price');
    return n;
  }

  /** What someone wears (ids that still exist and are theirs), bottom to top. */
  function wornOf(u) {
    let ids = [];
    try {
      ids = JSON.parse(u?.clothes || '[]');
    } catch {
      // bad data: nothing
    }
    return Array.isArray(ids) ? ids.filter((id) => Number.isSafeInteger(id)).slice(0, MAX_WORN) : [];
  }

  /** Sets what a user wears; every id must be theirs and still for sale. */
  function setWorn(user, ids) {
    if (!Array.isArray(ids)) throw bad('bad_clothes');
    const clean = [...new Set(ids.map(Number))].filter(Number.isSafeInteger);
    if (clean.length > MAX_WORN) throw bad('too_many_clothes');
    for (const id of clean) {
      const c = q.one.get(id);
      if (!c || (c.creator_id !== user.id && !q.owns.get(user.id, id))) throw bad('not_owned');
    }
    q.setWorn.run(JSON.stringify(clean), user.id);
    return clean;
  }

  const routes = {
    'GET /api/clothing': (req, _b, url) => {
      let userId = 0;
      try {
        userId = requireAuth(req).user.id;
      } catch {
        // signed out: still browses
      }
      const search = String(url.searchParams.get('q') || '').trim().slice(0, 40);
      const sort = url.searchParams.get('sort') === 'popular' ? 'popular' : 'new';
      const page = Math.max(0, Math.min(200, Number(url.searchParams.get('page')) || 0));
      const rows = q.list.all(search, `%${search}%`, sort, PAGE + 1, page * PAGE);
      return { items: rows.slice(0, PAGE).map((c) => view(c, userId)), more: rows.length > PAGE };
    },

    'GET /api/clothing/:id': (req, _b, _u, params) => {
      const { user } = requireAuth(req);
      const c = q.one.get(Number(params.id));
      if (!c) throw new HttpError(404, 'not_found');
      return { item: view(c, user.id) };
    },

    'GET /api/clothing/:id/image': (_req, _b, _u, params) => {
      const c = db.prepare('SELECT image FROM clothing WHERE id = ? AND deleted = 0').get(Number(params.id));
      if (!c) throw new HttpError(404, 'not_found');
      const file = path.join(dir, path.basename(c.image));
      if (!fs.existsSync(file)) throw new HttpError(404, 'not_found');
      return { __raw: { type: 'image/png', cache: 'public, max-age=604800, immutable', body: fs.readFileSync(file) } };
    },

    'POST /api/clothing/:id/buy': (req, _b, _u, params) => {
      const { user } = requireAuth(req);
      const c = q.one.get(Number(params.id));
      if (!c) throw new HttpError(404, 'not_found');
      if (c.creator_id === user.id || q.owns.get(user.id, c.id)) return { item: view(c, user.id), wallet: economy.wallet(user.id) };
      tx(() => {
        if (c.price > 0) {
          economy.change(user.id, 'pieces', -c.price, 'clothing', String(c.id));
          const share = Math.floor(c.price * CREATOR_SHARE);
          const community = c.community_id ? q.community.get(c.community_id) : null;
          if (community) {
            q.bankAdd.run(share, community.id);
            q.bankLog.run(community.id, share, 'clothing_sale', String(c.id), user.id, Date.now());
          } else if (share > 0) economy.change(c.creator_id, 'pieces', share, 'clothing_sale', String(c.id));
        }
        q.give.run(user.id, c.id, Date.now());
        q.sold.run(c.id);
      });
      return { item: view(q.one.get(c.id), user.id), wallet: economy.wallet(user.id) };
    },

    'GET /api/me/clothing': (req) => {
      const { user } = requireAuth(req);
      const mine = q.mine.all(user.id, '[]');
      const owned = q.owned.all(user.id);
      const seen = new Set();
      const items = [...mine, ...owned].filter((c) => !seen.has(c.id) && seen.add(c.id)).map((c) => view(c, user.id));
      return { items, worn: wornOf(q.user.get(user.id)) };
    },

    'PUT /api/me/clothing': (req, body) => {
      const { user } = requireAuth(req);
      return { worn: setWorn(user, body.worn) };
    },

    // Studio: what I've made (or my communities have), and making a new one.
    'GET /api/studio/clothing': (req) => {
      const { user } = requireAuth(req);
      const managed = communities.managedBy ? communities.managedBy(user.id) : [];
      return { items: q.mine.all(user.id, JSON.stringify(managed)).map((c) => view(c, user.id)) };
    },

    'POST /api/studio/clothing': (req, body) => {
      const { user } = requireAuth(req);
      if (!writeLimiter.allow('clothing:' + user.id)) throw new HttpError(429, 'slow_down');
      const name = cleanText(body.name, 40);
      if (name.length < 2) throw bad('bad_name');
      const description = cleanText(body.description, 300);
      const price = cleanPrice(body.price);
      const currency = body.currency === 'orbs' ? 'orbs' : 'pieces';
      let communityId = null;
      if (body.community_id != null && body.community_id !== '') {
        communityId = Number(body.community_id);
        const mem = communities.membership(communityId, user.id);
        if (!q.community.get(communityId) || !mem || (mem.rank < 255 && !mem.perms.has('manage'))) throw new HttpError(403, 'forbidden');
      }
      const image = saveImage(body.image);
      const id = tx(() => {
        economy.change(user.id, currency, -MAKE_PRICE[currency], 'clothing_make', name);
        const now = Date.now();
        return Number(q.insert.run('shirt', name, description, user.id, communityId, price, image, now, now).lastInsertRowid);
      });
      log(`clothing ${id} "${name}" by ${user.username}${communityId ? ` for community ${communityId}` : ''}`);
      return { item: view(q.one.get(id), user.id), wallet: economy.wallet(user.id) };
    },

    'PATCH /api/studio/clothing/:id': (req, body, _u, params) => {
      const { user } = requireAuth(req);
      const c = q.one.get(Number(params.id));
      if (!c) throw new HttpError(404, 'not_found');
      if (!canEdit(c, user.id)) throw new HttpError(403, 'forbidden');
      const name = body.name !== undefined ? cleanText(body.name, 40) : c.name;
      if (name.length < 2) throw bad('bad_name');
      const description = body.description !== undefined ? cleanText(body.description, 300) : c.description;
      const price = body.price !== undefined ? cleanPrice(body.price) : c.price;
      const image = body.image ? saveImage(body.image) : c.image;
      q.update.run(name, description, price, image, Date.now(), c.id);
      return { item: view(q.one.get(c.id), user.id) };
    },

    // The maker takes it off sale; staff take down what breaks the rules. Whoever bought
    // it keeps nothing wearable: it's off everyone at their next look.
    'DELETE /api/studio/clothing/:id': (req, _b, _u, params) => {
      const { user } = requireAuth(req);
      const c = q.one.get(Number(params.id));
      if (!c) throw new HttpError(404, 'not_found');
      const staff = user.role === 'owner' || user.role === 'admin';
      if (!canEdit(c, user.id) && !staff) throw new HttpError(403, 'forbidden');
      q.remove.run(Date.now(), c.id);
      log(`clothing ${c.id} "${c.name}" removed by ${user.username}`);
      return { ok: true };
    },
  };

  /** Ids that are still wearable (taken-down ones drop off everyone). */
  function live(ids) {
    return ids.filter((id) => q.one.get(id));
  }

  return { routes, wornOf: (u) => live(wornOf(u)), setWorn };
}
