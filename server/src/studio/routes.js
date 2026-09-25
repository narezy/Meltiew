// HTTP routes for Meltiew Studio: your places, publishing, covers, stats, assets and comments.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { chatRules } from '../age.js';
import { filterText } from '../filter.js';
import { VISIBILITIES, decodeImage, templatePlace, validateMarp } from './places.js';

export const ASSET_LIMIT_COUNT = 100;
export const ASSET_LIMIT_BYTES = 25 * 1024 * 1024;
const ASSET_MAX_BYTES = 2 * 1024 * 1024;
const COVER_MAX_BYTES = 3 * 1024 * 1024;
const MAX_PLACES_PER_USER = 50;

export function createStudioRoutes(ctx) {
  const { db, hub, store, requireAuth, requireStaff, HttpError, bad, cleanText, writeLimiter, publicProfile, authorCard, isFriend, placeView, pickLang } = ctx;
  const q = {
    mine: db.prepare("SELECT * FROM places WHERE owner_id = ? AND kind = 'studio' AND deleted = 0 ORDER BY updated_at DESC"),
    countMine: db.prepare("SELECT COUNT(*) AS n FROM places WHERE owner_id = ? AND kind = 'studio' AND deleted = 0"),
    insert: db.prepare(`INSERT INTO places (id, name, name_ru, description, description_ru, author_username, cover, created_at,
      kind, owner_id, visibility, i18n, version, updated_at) VALUES (?, ?, ?, '', '', ?, '', ?, 'studio', ?, 'private', '{}', 1, ?)`),
    one: db.prepare('SELECT * FROM places WHERE id = ? AND deleted = 0'),
    saveMeta: db.prepare('UPDATE places SET name = ?, name_ru = ?, description = ?, description_ru = ?, i18n = ?, version = version + 1, updated_at = ? WHERE id = ?'),
    setVisibility: db.prepare('UPDATE places SET visibility = ?, published_at = CASE WHEN ? = \'public\' AND published_at = 0 THEN ? ELSE published_at END WHERE id = ?'),
    setOptions: db.prepare('UPDATE places SET comments_enabled = ?, max_players = ? WHERE id = ?'),
    setCover: db.prepare('UPDATE places SET cover = ? WHERE id = ?'),
    setSquare: db.prepare('UPDATE places SET cover_square = ? WHERE id = ?'),
    del: db.prepare('UPDATE places SET deleted = 1 WHERE id = ?'),
    byOwnerPublic: db.prepare("SELECT * FROM places WHERE owner_id = ? AND kind = 'studio' AND deleted = 0 AND visibility IN (SELECT value FROM json_each(?)) ORDER BY visits DESC"),
    daily: db.prepare('SELECT day, visits, playtime_ms FROM place_daily WHERE place_id = ? AND day >= ? ORDER BY day'),
    uniques: db.prepare('SELECT COUNT(*) AS n, COALESCE(SUM(playtime_ms), 0) AS t FROM place_players WHERE place_id = ?'),
    returning: db.prepare('SELECT COUNT(*) AS n FROM place_players WHERE place_id = ? AND visits > 1'),
    votes: db.prepare('SELECT SUM(value = 1) AS likes, SUM(value = -1) AS dislikes FROM place_votes WHERE place_id = ?'),
    commentCount: db.prepare('SELECT COUNT(*) AS n FROM place_comments WHERE place_id = ?'),
    assets: db.prepare('SELECT * FROM assets WHERE owner_id = ? ORDER BY created_at DESC'),
    assetUsage: db.prepare('SELECT COUNT(*) AS n, COALESCE(SUM(size), 0) AS bytes FROM assets WHERE owner_id = ?'),
    asset: db.prepare('SELECT * FROM assets WHERE id = ?'),
    insertAsset: db.prepare('INSERT INTO assets (id, owner_id, name, mime, size, width, height, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)'),
    deleteAsset: db.prepare('DELETE FROM assets WHERE id = ?'),
    comments: db.prepare(`SELECT c.*, u.username, u.display_name, u.role, u.render_hash, u.colors, u.hat, u.face FROM place_comments c JOIN users u ON u.id = c.user_id
      WHERE c.place_id = ? AND c.id < ? AND u.banned = 0 ORDER BY c.id DESC LIMIT 30`),
    comment: db.prepare('SELECT * FROM place_comments WHERE id = ?'),
    insertComment: db.prepare('INSERT INTO place_comments (place_id, user_id, body, created_at) VALUES (?, ?, ?, ?)'),
    deleteComment: db.prepare('DELETE FROM place_comments WHERE id = ?'),
    userByName: db.prepare('SELECT * FROM users WHERE username = ?'),
  };

  const isStaff = (u) => u.role === 'owner' || u.role === 'admin';

  function ownPlace(req, id) {
    const auth = requireAuth(req);
    const row = q.one.get(id);
    if (!row || row.kind !== 'studio') throw new HttpError(404, 'no_place');
    if (row.owner_id !== auth.user.id && !isStaff(auth.user)) throw new HttpError(403, 'forbidden');
    return { ...auth, row };
  }

  function visiblePlace(req, id) {
    const auth = requireAuth(req);
    const row = q.one.get(id);
    if (!row || !store.canSee(row, auth.user, isFriend)) throw new HttpError(404, 'no_place');
    return { ...auth, row };
  }

  // Everything the owner sees about their place (the public view plus private fields).
  function studioView(row, viewer, lang) {
    const i18n = JSON.parse(row.i18n || '{}');
    return {
      ...placeView(row, viewer.id, lang),
      visibility: row.visibility,
      comments_enabled: !!row.comments_enabled,
      max_players: row.max_players,
      version: row.version,
      updated_at: row.updated_at,
      published_at: row.published_at,
      i18n,
    };
  }

  function saveMedia(id, kind, img) {
    // Old files with other extensions are replaced.
    for (const ext of ['png', 'jpg']) {
      try {
        fs.unlinkSync(path.join(store.mediaDir, `${id}-${kind}.${ext}`));
      } catch {}
    }
    const file = `${id}-${kind}.${img.ext}`;
    fs.writeFileSync(path.join(store.mediaDir, file), img.buf);
    return `/api/media/${file}?v=${Date.now().toString(36)}`;
  }

  function assetView(a) {
    return { id: a.id, name: a.name, url: `/api/assets/${a.id}`, ref: `asset://${a.id}`, size: a.size, width: a.width, height: a.height, created_at: a.created_at };
  }

  return {
    // --- your places ----------------------------------------------------------
    'GET /api/studio/places': (req) => {
      const { user } = requireAuth(req);
      const lang = pickLang(req);
      return { places: q.mine.all(user.id).map((r) => studioView(r, user, lang)) };
    },

    'POST /api/studio/places': (req, body) => {
      const { user } = requireAuth(req);
      if (!writeLimiter.allow('studio:' + user.id)) throw new HttpError(429, 'slow_down');
      if (q.countMine.get(user.id).n >= MAX_PLACES_PER_USER) throw bad('too_many_places');
      const name = cleanText(body.name, 60) || 'My place';
      let marp = templatePlace(name);
      if (body.marp) {
        try {
          marp = validateMarp(body.marp);
        } catch (e) {
          throw new HttpError(400, 'bad_place', { r: e.reason || '' });
        }
        marp.meta.name = name || marp.meta.name;
      }
      const id = store.newId();
      const now = Date.now();
      q.insert.run(id, name, name, user.username, now, user.id, now);
      store.write(id, marp);
      q.saveMeta.run(name, marp.meta.i18n.name.ru || name, marp.meta.description, marp.meta.i18n.description.ru || marp.meta.description, JSON.stringify(marp.meta.i18n), now, id);
      return { place: studioView(q.one.get(id), user, pickLang(req)) };
    },

    'GET /api/studio/places/:id': (req, _b, _u, params) => {
      const { user, row } = ownPlace(req, params.id);
      return { place: studioView(row, user, pickLang(req)), marp: store.load(row.id) };
    },

    // Saves the whole place. Name, description and their translations come from marp.meta.
    'PUT /api/studio/places/:id': (req, body, _u, params) => {
      const { user, row } = ownPlace(req, params.id);
      if (!writeLimiter.allow('studio:' + user.id)) throw new HttpError(429, 'slow_down');
      let marp;
      try {
        marp = validateMarp(body.marp);
      } catch (e) {
        throw new HttpError(400, 'bad_place', { r: e.reason || '' });
      }
      store.write(row.id, marp);
      const m = marp.meta;
      q.saveMeta.run(m.name, m.i18n.name.ru || m.name, m.description, m.i18n.description.ru || m.description, JSON.stringify(m.i18n), Date.now(), row.id);
      return { place: studioView(q.one.get(row.id), user, pickLang(req)) };
    },

    'PATCH /api/studio/places/:id': (req, body, _u, params) => {
      const { user, row } = ownPlace(req, params.id);
      if (body.visibility !== undefined) {
        if (!VISIBILITIES.includes(body.visibility)) throw bad('bad_visibility');
        q.setVisibility.run(body.visibility, body.visibility, Date.now(), row.id);
      }
      if (body.comments_enabled !== undefined || body.max_players !== undefined) {
        const cur = q.one.get(row.id);
        const comments = body.comments_enabled !== undefined ? (body.comments_enabled ? 1 : 0) : cur.comments_enabled;
        const maxPlayers = body.max_players !== undefined ? Math.max(1, Math.min(10, Math.round(Number(body.max_players) || 10))) : cur.max_players;
        q.setOptions.run(comments, maxPlayers, row.id);
      }
      return { place: studioView(q.one.get(row.id), user, pickLang(req)) };
    },

    // kind: "wide" (16:9, lists and the place page) or "square" (1:1 icon).
    'POST /api/studio/places/:id/cover': (req, body, _u, params) => {
      const { user, row } = ownPlace(req, params.id);
      const img = decodeImage(body.image, COVER_MAX_BYTES);
      if (!img) throw bad('bad_image');
      const kind = body.kind === 'square' ? 'square' : 'wide';
      const url = saveMedia(row.id, kind, img);
      (kind === 'square' ? q.setSquare : q.setCover).run(url, row.id);
      return { place: studioView(q.one.get(row.id), user, pickLang(req)) };
    },

    'DELETE /api/studio/places/:id': (req, _b, _u, params) => {
      const { row } = ownPlace(req, params.id);
      q.del.run(row.id);
      hub.closePlace?.(row.id);
      store.remove(row.id);
      return { ok: true };
    },

    'GET /api/studio/places/:id/stats': (req, _b, _u, params) => {
      const { row } = ownPlace(req, params.id);
      const since = new Date(Date.now() - 29 * 86400_000).toISOString().slice(0, 10);
      const u = q.uniques.get(row.id);
      const v = q.votes.get(row.id);
      return {
        stats: {
          visits: row.visits,
          playtime_ms: row.playtime_ms,
          unique_players: u.n,
          returning_players: q.returning.get(row.id).n,
          avg_session_ms: row.visits ? Math.round(row.playtime_ms / row.visits) : 0,
          playing: hub.playerCount(row.id),
          likes: v.likes || 0,
          dislikes: v.dislikes || 0,
          comments: q.commentCount.get(row.id).n,
          daily: q.daily.all(row.id, since),
        },
      };
    },

    // Public places of a player (friends-only ones too if you're friends; all of them for yourself).
    'GET /api/users/:name/places': (req, _b, _u, params) => {
      const { user } = requireAuth(req);
      const owner = q.userByName.get(params.name);
      if (!owner) throw new HttpError(404, 'no_user');
      let vis = ['public'];
      if (owner.id === user.id || isStaff(user)) vis = VISIBILITIES;
      else if (isFriend(owner.id, user.id)) vis = ['public', 'friends'];
      const lang = pickLang(req);
      return { places: q.byOwnerPublic.all(owner.id, JSON.stringify(vis)).map((r) => placeView(r, user.id, lang)) };
    },

    'GET /api/media/:file': (_req, _b, _u, params) => {
      const file = path.basename(params.file);
      const full = path.join(store.mediaDir, file);
      if (!/^p[0-9a-f]{10}-(wide|square)\.(png|jpg)$/.test(file) || !fs.existsSync(full)) throw new HttpError(404, 'not_found');
      return { __raw: { type: file.endsWith('.png') ? 'image/png' : 'image/jpeg', body: fs.readFileSync(full), cache: 'public, max-age=3600' } };
    },

    // --- assets (images for parts and UI) ----------------------------------------
    'GET /api/assets': (req) => {
      const { user } = requireAuth(req);
      const usage = q.assetUsage.get(user.id);
      return {
        assets: q.assets.all(user.id).map(assetView),
        usage: { count: usage.n, bytes: usage.bytes, max_count: ASSET_LIMIT_COUNT, max_bytes: ASSET_LIMIT_BYTES },
      };
    },

    'POST /api/assets': (req, body) => {
      const { user } = requireAuth(req);
      if (!writeLimiter.allow('asset:' + user.id)) throw new HttpError(429, 'slow_down');
      const img = decodeImage(body.image, ASSET_MAX_BYTES, 2048);
      if (!img) throw bad('bad_image');
      const usage = q.assetUsage.get(user.id);
      if (usage.n >= ASSET_LIMIT_COUNT || usage.bytes + img.buf.length > ASSET_LIMIT_BYTES) throw new HttpError(403, 'asset_quota');
      const id = crypto.randomBytes(8).toString('hex');
      fs.writeFileSync(path.join(store.assetDir, id), img.buf);
      q.insertAsset.run(id, user.id, cleanText(body.name, 60) || 'image', img.mime, img.buf.length, img.width, img.height, Date.now());
      return { asset: assetView(q.asset.get(id)) };
    },

    'GET /api/assets/:id': (_req, _b, _u, params) => {
      const a = q.asset.get(params.id);
      if (!a) throw new HttpError(404, 'not_found');
      const file = path.join(store.assetDir, a.id);
      if (!fs.existsSync(file)) throw new HttpError(404, 'not_found');
      return { __raw: { type: a.mime, body: fs.readFileSync(file), cache: 'public, max-age=86400' } };
    },

    'DELETE /api/assets/:id': (req, _b, _u, params) => {
      const { user } = requireAuth(req);
      const a = q.asset.get(params.id);
      if (!a) throw new HttpError(404, 'not_found');
      if (a.owner_id !== user.id && !isStaff(user)) throw new HttpError(403, 'forbidden');
      q.deleteAsset.run(a.id);
      try {
        fs.unlinkSync(path.join(store.assetDir, a.id));
      } catch {}
      return { ok: true };
    },

    // --- comments ----------------------------------------------------------------
    'GET /api/places/:id/comments': (req, _b, url, params) => {
      const { user, row } = visiblePlace(req, params.id);
      const before = Number(url.searchParams.get('before')) || Number.MAX_SAFE_INTEGER;
      const rules = chatRules(user.birthdate);
      const list = q.comments.all(row.id, before).map((c) => ({
        id: c.id,
        body: c.user_id !== user.id && rules.filter_dm ? filterText(c.body) : c.body,
        created_at: c.created_at,
        author: authorCard({ ...c, id: c.user_id }),
        can_delete: c.user_id === user.id || row.owner_id === user.id || isStaff(user),
      }));
      return { comments: list, enabled: !!row.comments_enabled || row.kind !== 'studio', can_post: chatRules(user.birthdate).chat };
    },

    'POST /api/places/:id/comments': (req, body, _u, params) => {
      const { user, row } = visiblePlace(req, params.id);
      if (row.kind === 'studio' && !row.comments_enabled) throw new HttpError(403, 'comments_off');
      if (!chatRules(user.birthdate).chat) throw new HttpError(403, 'dm_too_young');
      if (!writeLimiter.allow('comment:' + user.id)) throw new HttpError(429, 'slow_down');
      const text = String(body.text ?? '').replace(/[\u0000-\u0008\u000b-\u001f\u007f]/g, '').trim().slice(0, 500);
      if (!text) throw bad('empty');
      const info = q.insertComment.run(row.id, user.id, text, Date.now());
      return { comment: { id: Number(info.lastInsertRowid), body: text, created_at: Date.now(), author: publicProfile(user), can_delete: true } };
    },

    'DELETE /api/places/:id/comments/:cid': (req, _b, _u, params) => {
      const { user, row } = visiblePlace(req, params.id);
      const c = q.comment.get(Number(params.cid));
      if (!c || c.place_id !== row.id) throw new HttpError(404, 'not_found');
      if (c.user_id !== user.id && row.owner_id !== user.id && !isStaff(user)) throw new HttpError(403, 'forbidden');
      q.deleteComment.run(c.id);
      return { ok: true };
    },
  };
}
