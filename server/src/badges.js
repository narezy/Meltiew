// Place badges: each studio place can make up to 15 badges (name, description,
// picture) and its server scripts award them (BadgeService:AwardBadge). A place
// can only award its own badges. Players collect them on their profile.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { decodeImage } from './studio/places.js';

export const MAX_BADGES_PER_PLACE = 15;
const BADGE_IMAGE_BYTES = 512 * 1024;

export function migrateBadges(db) {
  db.exec(`
    CREATE TABLE IF NOT EXISTS place_badges (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      place_id    TEXT NOT NULL,
      name        TEXT NOT NULL,
      description TEXT NOT NULL DEFAULT '',
      image       TEXT NOT NULL DEFAULT '',
      awarded     INTEGER NOT NULL DEFAULT 0,
      deleted     INTEGER NOT NULL DEFAULT 0,
      created_at  INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS place_badges_place ON place_badges(place_id);
    CREATE TABLE IF NOT EXISTS user_badges (
      user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      badge_id   INTEGER NOT NULL REFERENCES place_badges(id) ON DELETE CASCADE,
      awarded_at INTEGER NOT NULL,
      PRIMARY KEY (user_id, badge_id)
    );
  `);
}

export function createBadges({ db, hub, mediaDir, HttpError, bad, cleanText, requireAuth, authenticate }) {
  fs.mkdirSync(path.join(mediaDir, 'badges'), { recursive: true });
  const q = {
    place: db.prepare('SELECT id, owner_id, kind, name FROM places WHERE id = ?'),
    badges: db.prepare('SELECT * FROM place_badges WHERE place_id = ? AND deleted = 0 ORDER BY id'),
    badge: db.prepare('SELECT * FROM place_badges WHERE id = ? AND deleted = 0'),
    count: db.prepare('SELECT COUNT(*) AS n FROM place_badges WHERE place_id = ? AND deleted = 0'),
    insert: db.prepare('INSERT INTO place_badges (place_id, name, description, image, created_at) VALUES (?, ?, ?, ?, ?)'),
    update: db.prepare('UPDATE place_badges SET name = ?, description = ?, image = ? WHERE id = ?'),
    remove: db.prepare('UPDATE place_badges SET deleted = 1 WHERE id = ?'),
    has: db.prepare('SELECT 1 FROM user_badges WHERE user_id = ? AND badge_id = ?'),
    give: db.prepare('INSERT OR IGNORE INTO user_badges (user_id, badge_id, awarded_at) VALUES (?, ?, ?)'),
    awarded: db.prepare('UPDATE place_badges SET awarded = awarded + 1 WHERE id = ?'),
    ownedIn: db.prepare(`SELECT ub.badge_id AS id FROM user_badges ub JOIN place_badges b ON b.id = ub.badge_id
      WHERE ub.user_id = ? AND b.place_id = ? AND b.deleted = 0`),
    ofUser: db.prepare(`SELECT b.*, ub.awarded_at, p.name AS place_name FROM user_badges ub
      JOIN place_badges b ON b.id = ub.badge_id JOIN places p ON p.id = b.place_id
      WHERE ub.user_id = ? AND b.deleted = 0 ORDER BY ub.awarded_at DESC LIMIT 300`),
    userByName: db.prepare('SELECT id FROM users WHERE username = ?'),
  };

  const imageUrl = (b) => (b.image ? `/api/badges/${b.id}/image?v=${encodeURIComponent(b.image)}` : '');
  const view = (b, userId) => ({
    id: b.id,
    place_id: b.place_id,
    name: b.name,
    description: b.description,
    image: imageUrl(b),
    awarded: b.awarded,
    owned: userId ? !!q.has.get(userId, b.id) : false,
  });

  function ownPlace(req, placeId) {
    const auth = requireAuth(req);
    const row = q.place.get(placeId);
    if (!row || row.kind !== 'studio') throw new HttpError(404, 'no_place');
    if (!hub.canEditPlace?.(auth.user, row) && row.owner_id !== auth.user.id && auth.user.role !== 'owner' && auth.user.role !== 'admin') {
      throw new HttpError(403, 'forbidden');
    }
    return { ...auth, row };
  }

  function saveImage(b64) {
    const img = decodeImage(b64, BADGE_IMAGE_BYTES, 512);
    if (!img) throw bad('bad_image');
    const name = crypto.randomBytes(8).toString('hex') + '.' + img.ext;
    fs.writeFileSync(path.join(mediaDir, 'badges', name), img.buf);
    return name;
  }

  /**
   * A place's script awards a badge. Only that place's own badges count; returns
   * the badge when it's newly given, null otherwise (already had it, not this place's).
   */
  function award(placeId, userId, badgeId) {
    const b = q.badge.get(Number(badgeId));
    if (!b || b.place_id !== placeId) return { ok: false, err: 'that badge is not from this place' };
    if (q.give.run(userId, b.id, Date.now()).changes !== 1) return { ok: true, fresh: false, badge: b };
    q.awarded.run(b.id);
    return { ok: true, fresh: true, badge: b };
  }

  const routes = {
    'GET /api/places/:id/badges': (req, _b, _u, params) => {
      const uid = authenticate(req)?.user.id;
      return { badges: q.badges.all(params.id).map((b) => view(b, uid)), max: MAX_BADGES_PER_PLACE };
    },

    'POST /api/studio/places/:id/badges': (req, body, _u, params) => {
      const { row } = ownPlace(req, params.id);
      if (q.count.get(row.id).n >= MAX_BADGES_PER_PLACE) throw bad('too_many_badges');
      const name = cleanText(body.name, 50);
      if (name.length < 2) throw bad('bad_name');
      const image = body.image ? saveImage(body.image) : '';
      const info = q.insert.run(row.id, name, cleanText(body.description, 300), image, Date.now());
      return { badge: view(q.badge.get(Number(info.lastInsertRowid)), null) };
    },

    'PATCH /api/studio/places/:id/badges/:bid': (req, body, _u, params) => {
      const { row } = ownPlace(req, params.id);
      const b = q.badge.get(Number(params.bid));
      if (!b || b.place_id !== row.id) throw new HttpError(404, 'no_badge');
      const name = body.name !== undefined ? cleanText(body.name, 50) : b.name;
      if (name.length < 2) throw bad('bad_name');
      q.update.run(name, body.description !== undefined ? cleanText(body.description, 300) : b.description, body.image ? saveImage(body.image) : b.image, b.id);
      return { badge: view(q.badge.get(b.id), null) };
    },

    'DELETE /api/studio/places/:id/badges/:bid': (req, _b, _u, params) => {
      const { row } = ownPlace(req, params.id);
      const b = q.badge.get(Number(params.bid));
      if (!b || b.place_id !== row.id) throw new HttpError(404, 'no_badge');
      q.remove.run(b.id);
      return { ok: true };
    },

    'GET /api/badges/:bid/image': (_req, _b, _u, params) => {
      const b = db.prepare('SELECT image FROM place_badges WHERE id = ?').get(Number(params.bid));
      if (!b?.image || !/^[0-9a-f]{16}\.(png|jpg)$/.test(b.image)) throw new HttpError(404, 'not_found');
      const file = path.join(mediaDir, 'badges', b.image);
      if (!fs.existsSync(file)) throw new HttpError(404, 'not_found');
      return { __raw: { type: b.image.endsWith('.png') ? 'image/png' : 'image/jpeg', cache: 'public, max-age=86400', body: fs.readFileSync(file) } };
    },

    'GET /api/users/:name/badges': (_req, _b, _u, params) => {
      const u = q.userByName.get(params.name);
      if (!u) throw new HttpError(404, 'no_user');
      return {
        badges: q.ofUser.all(u.id).map((b) => ({ ...view(b, null), owned: true, place_name: b.place_name, awarded_at: b.awarded_at })),
      };
    },
  };

  return {
    routes,
    award,
    /** For the game: the badges a player has in this place, and what they are. */
    ownedIn: (userId, placeId) => q.ownedIn.all(userId, placeId).map((r) => r.id),
    info: (placeId) => q.badges.all(placeId).map((b) => ({ id: b.id, name: b.name, description: b.description })),
    imageUrl,
  };
}
