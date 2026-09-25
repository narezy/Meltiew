import { hashPassword, verifyPassword, newToken, RateLimiter } from './security.js';
import { GAMES, MAX_PLAYERS } from './game.js';
import { BODY_PARTS, COLOR_RE, parseColors } from './colors.js';
import { msg, pickLang } from './i18n.js';
import fs from 'node:fs';
import { createVersionGate, DOWNLOAD_PAGE, LATEST_CLIENT } from './version.js';
import { FACES, ageOf, chatRules, validBirthdate } from './age.js';
import { filterText } from './filter.js';
import { createStudioRoutes } from './studio/routes.js';
import path from 'node:path';

const USERNAME_RE = /^[A-Za-z0-9_]{3,20}$/;
export { LEGACY_HATS as HATS } from './accessories.js';
import { CATALOG, cleanWorn, wornOf, legacyHat, accessoryExists } from './accessories.js';
const ONLINE_WINDOW_MS = 60_000;
const SESSION_TTL_MS = 1000 * 60 * 60 * 24 * 60;
const MAX_BODY = 16 * 1024;
const MAX_RENDER_BODY = 600 * 1024;
// Studio: whole place files and images.
const MAX_STUDIO_BODY = 12 * 1024 * 1024;
const LAUNCH_TTL_MS = 3 * 60_000;
const PNG_MAGIC = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

class HttpError extends Error {
  constructor(status, code, vars = {}) {
    super(code);
    this.status = status;
    this.code = code;
    this.vars = vars;
  }
}
const bad = (code) => new HttpError(400, code);

function cleanText(value, max) {
  return String(value ?? '')
    .replace(/[\u0000-\u001f\u007f]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, max);
}

function readJson(req, limit = MAX_BODY) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on('data', (c) => {
      size += c.length;
      if (size > limit) {
        reject(new HttpError(413, 'too_large'));
        req.destroy();
        return;
      }
      chunks.push(c);
    });
    req.on('end', () => {
      if (!chunks.length) return resolve({});
      try {
        const data = JSON.parse(Buffer.concat(chunks).toString('utf8'));
        resolve(data && typeof data === 'object' ? data : {});
      } catch {
        reject(bad('bad_json'));
      }
    });
    req.on('error', reject);
  });
}

export function clientIp(req) {
  const fwd = req.headers['x-real-ip'] || String(req.headers['x-forwarded-for'] || '').split(',')[0].trim();
  return fwd || req.socket.remoteAddress || '?';
}

export function createApi({ db, hub, renderDir, store, owner = process.env.MELTIEW_OWNER || 'nrz' }) {
  fs.mkdirSync(renderDir, { recursive: true });
  const gate = createVersionGate(db);
  const launches = new Map(); // userId -> { server, game, at }
  const authLimiter = new RateLimiter(20, 60_000);
  const writeLimiter = new RateLimiter(120, 60_000);
  setInterval(() => {
    authLimiter.sweep();
    writeLimiter.sweep();
    db.prepare('DELETE FROM sessions WHERE used_at < ?').run(Date.now() - SESSION_TTL_MS);
  }, 60_000).unref();

  const q = {
    userById: db.prepare('SELECT * FROM users WHERE id = ?'),
    userByName: db.prepare('SELECT * FROM users WHERE username = ?'),
    insertUser: db.prepare(
      'INSERT INTO users (username, pass_hash, display_name, created_at, last_seen) VALUES (?, ?, ?, ?, ?)',
    ),
    insertSession: db.prepare('INSERT INTO sessions (token, user_id, created_at, used_at) VALUES (?, ?, ?, ?)'),
    session: db.prepare('SELECT * FROM sessions WHERE token = ?'),
    touchSession: db.prepare('UPDATE sessions SET used_at = ? WHERE token = ?'),
    touchUser: db.prepare('UPDATE users SET last_seen = ? WHERE id = ?'),
    deleteSession: db.prepare('DELETE FROM sessions WHERE token = ?'),
    deleteOtherSessions: db.prepare('DELETE FROM sessions WHERE user_id = ? AND token != ?'),
    search: db.prepare(
      "SELECT * FROM users WHERE (username LIKE ? ESCAPE '\\' OR display_name LIKE ? ESCAPE '\\') AND id != ? ORDER BY last_seen DESC LIMIT 20",
    ),
    friendRow: db.prepare('SELECT * FROM friendships WHERE from_id = ? AND to_id = ?'),
    friendsOf: db.prepare(`
      SELECT u.*, f.status, f.from_id, f.to_id FROM friendships f
      JOIN users u ON u.id = CASE WHEN f.from_id = ? THEN f.to_id ELSE f.from_id END
      WHERE f.from_id = ? OR f.to_id = ?`),
    insertFriend: db.prepare('INSERT INTO friendships (from_id, to_id, status, created_at) VALUES (?, ?, ?, ?)'),
    acceptFriend: db.prepare("UPDATE friendships SET status = 'accepted' WHERE from_id = ? AND to_id = ?"),
    deleteFriend: db.prepare('DELETE FROM friendships WHERE (from_id = ? AND to_id = ?) OR (from_id = ? AND to_id = ?)'),
    countFriends: db.prepare(
      "SELECT COUNT(*) AS n FROM friendships WHERE status = 'accepted' AND (from_id = ? OR to_id = ?)",
    ),
    countUsers: db.prepare('SELECT COUNT(*) AS n FROM users'),
    blockRow: db.prepare('SELECT 1 FROM blocks WHERE user_id = ? AND blocked_id = ?'),
    blockedBy: db.prepare('SELECT blocked_id FROM blocks WHERE user_id = ?'),
    blockedUsers: db.prepare('SELECT u.* FROM blocks b JOIN users u ON u.id = b.blocked_id WHERE b.user_id = ? ORDER BY b.created_at DESC'),
    insertBlock: db.prepare('INSERT OR IGNORE INTO blocks (user_id, blocked_id, created_at) VALUES (?, ?, ?)'),
    deleteBlock: db.prepare('DELETE FROM blocks WHERE user_id = ? AND blocked_id = ?'),
    setRender: db.prepare('UPDATE users SET render_hash = ? WHERE id = ?'),
  };

  // The platform owner gets the owner role as soon as the account exists.
  const promoteOwner = () => db.prepare("UPDATE users SET role = 'owner' WHERE username = ? AND role != 'owner'").run(owner);
  promoteOwner();

  const pq = {
    // Listed: the built-in games and published (public) studio places.
    all: db.prepare("SELECT * FROM places WHERE deleted = 0 AND (kind = 'builtin' OR visibility = 'public') ORDER BY created_at"),
    one: db.prepare('SELECT * FROM places WHERE id = ?'),
    votes: db.prepare('SELECT SUM(value = 1) AS likes, SUM(value = -1) AS dislikes FROM place_votes WHERE place_id = ?'),
    myVote: db.prepare('SELECT value FROM place_votes WHERE place_id = ? AND user_id = ?'),
    setVote: db.prepare('INSERT INTO place_votes (place_id, user_id, value) VALUES (?, ?, ?) ON CONFLICT(place_id, user_id) DO UPDATE SET value = excluded.value'),
    clearVote: db.prepare('DELETE FROM place_votes WHERE place_id = ? AND user_id = ?'),
    visit: db.prepare('UPDATE places SET visits = visits + 1 WHERE id = ?'),
    update: db.prepare('UPDATE places SET name = ?, name_ru = ?, description = ?, description_ru = ? WHERE id = ?'),
  };

  function friendSet(userId) {
    return new Set(
      q.friendsOf
        .all(userId, userId, userId)
        .filter((r) => r.status === 'accepted')
        .map((r) => r.id),
    );
  }

  function placeView(p, viewerId, lang = 'en') {
    const v = pq.votes.get(p.id);
    const studio = p.kind === 'studio';
    const author = studio ? q.userById.get(p.owner_id) : q.userByName.get(p.author_username);
    // Studio places carry their own translations; the built-in one has EN/RU columns.
    let i18n = {};
    try {
      i18n = JSON.parse(p.i18n || '{}');
    } catch {}
    const name = studio ? i18n.name?.[lang] || p.name : p.name;
    const description = studio ? i18n.description?.[lang] || p.description : p.description;
    return {
      id: p.id,
      kind: p.kind || 'builtin',
      name,
      name_ru: studio ? i18n.name?.ru || name : p.name_ru,
      description,
      description_ru: studio ? i18n.description?.ru || description : p.description_ru,
      cover: p.cover || '/img/place-cover.png',
      cover_square: p.cover_square || '',
      visits: p.visits,
      created_at: p.created_at,
      updated_at: p.updated_at || p.created_at,
      visibility: p.visibility || 'public',
      comments_enabled: studio ? !!p.comments_enabled : true,
      likes: v.likes || 0,
      dislikes: v.dislikes || 0,
      my_vote: viewerId ? pq.myVote.get(p.id, viewerId)?.value || 0 : 0,
      playing: hub.playerCount(p.id),
      max_players: studio ? p.max_players : MAX_PLAYERS,
      // The owner gets the untranslated texts and every translation to edit.
      ...(studio && viewerId && p.owner_id === viewerId ? { edit: { name: p.name, description: p.description, i18n } } : {}),
      author: author
        ? authorCard(author)
        : { id: 0, username: p.author_username, display_name: p.author_username, role: 'owner', render: '' },
    };
  }

  const isFriend = (a, b) => a === b || !!(q.friendRow.get(a, b)?.status === 'accepted' || q.friendRow.get(b, a)?.status === 'accepted');
  function visibleRow(user, id) {
    const p = pq.one.get(id);
    if (!p || p.deleted || !store.canSee(p, user, isFriend)) throw new HttpError(404, 'no_place');
    return p;
  }

  function serversFor(game, userId) {
    const friendIds = friendSet(userId);
    return hub.listServers(game).map((s) => {
      const friends = s.player_ids.filter((id) => friendIds.has(id)).map((id) => q.userById.get(id)?.display_name).filter(Boolean);
      const { player_ids, ...rest } = s;
      return { ...rest, friends };
    });
  }

  function requireStaff(req) {
    const auth = requireAuth(req);
    if (auth.user.role !== 'admin' && auth.user.role !== 'owner') throw new HttpError(403, 'forbidden');
    return auth;
  }

  function adminUser(u) {
    return {
      ...publicProfile(u),
      banned: !!u.banned,
      ban_reason: u.ban_reason,
      age: ageOf(u.birthdate),
      last_seen: u.last_seen,
    };
  }

  function blockSet(userId) {
    return new Set(q.blockedBy.all(userId).map((r) => r.blocked_id));
  }

  function presence(u) {
    const where = hub.whereIs(u.id);
    if (where) return { online: true, playing: where };
    return { online: Date.now() - u.last_seen < ONLINE_WINDOW_MS, playing: null };
  }

  // What an avatar looks like: enough for the app to draw a portrait or a character.
  function lookOf(u) {
    const worn = wornOf(u);
    return { colors: parseColors(u.colors), hat: legacyHat(worn), accessories: worn, face: u.face || ':D', render: u.render_hash || '' };
  }

  /** A small author card (places, comments) that still draws the right avatar. */
  function authorCard(u) {
    return { id: u.id, username: u.username, display_name: u.display_name, role: u.role || 'user', ...lookOf(u) };
  }

  function publicProfile(u, viewerId = null) {
    const out = {
      id: u.id,
      username: u.username,
      display_name: u.display_name,
      bio: u.bio,
      ...lookOf(u),
      role: u.role || 'user',
      created_at: u.created_at,
      friends: q.countFriends.get(u.id, u.id).n,
      ...presence(u),
    };
    if (viewerId != null && viewerId !== u.id) out.relation = relation(viewerId, u.id);
    return out;
  }

  /** The signed-in user's own profile, with private fields. */
  // One free change of the date of birth after it is first set, then one every six months.
  const BIRTHDATE_COOLDOWN_MS = 182 * 24 * 3600 * 1000;
  function birthdateChange(u) {
    if (!u.birthdate) return { can: true, free: false, next_at: 0 };
    if (!u.birthdate_changed_at) return { can: true, free: true, next_at: 0 };
    const nextAt = u.birthdate_changed_at + BIRTHDATE_COOLDOWN_MS;
    return { can: Date.now() >= nextAt, free: false, next_at: nextAt };
  }

  function selfProfile(u) {
    return {
      ...publicProfile(u),
      birthdate: u.birthdate || '',
      birthdate_change: birthdateChange(u),
      hide_friends: !!u.hide_friends,
      rules: chatRules(u.birthdate),
    };
  }

  function relation(me, other) {
    if (q.blockRow.get(me, other)) return 'blocked';
    const out = q.friendRow.get(me, other);
    const inc = q.friendRow.get(other, me);
    if ((out && out.status === 'accepted') || (inc && inc.status === 'accepted')) return 'friends';
    if (out) return 'outgoing';
    if (inc) return 'incoming';
    return 'none';
  }

  /** 'open' | 'outgoing' (my request waits) | 'incoming' (their request waits) | 'none'. */
  function dmState(me, other) {
    if (relation(me, other) === 'friends') return 'open';
    const out = db.prepare('SELECT status FROM dm_requests WHERE from_id = ? AND to_id = ?').get(me, other);
    const inc = db.prepare('SELECT status FROM dm_requests WHERE from_id = ? AND to_id = ?').get(other, me);
    if (out?.status === 'accepted' || inc?.status === 'accepted') return 'open';
    if (inc?.status === 'pending') return 'incoming';
    if (out?.status === 'pending') return 'outgoing';
    return 'none';
  }

  function issueSession(userId) {
    const token = newToken();
    const now = Date.now();
    q.insertSession.run(token, userId, now, now);
    return token;
  }

  function authenticate(req) {
    const header = req.headers.authorization || '';
    const token = header.startsWith('Bearer ') ? header.slice(7).trim() : '';
    return userForToken(token);
  }

  function userForToken(token) {
    if (!token || token.length > 128) return null;
    const s = q.session.get(token);
    if (!s) return null;
    const now = Date.now();
    if (now - s.used_at > SESSION_TTL_MS) {
      q.deleteSession.run(token);
      return null;
    }
    q.touchSession.run(now, token);
    q.touchUser.run(now, s.user_id);
    const user = q.userById.get(s.user_id);
    if (!user || user.banned) return null;
    return { user, token };
  }

  function requireAuth(req) {
    const auth = authenticate(req);
    if (!auth) throw new HttpError(401, 'unauthorized');
    return auth;
  }

  function lookupTarget(body) {
    let target = null;
    if (body.user_id != null) target = q.userById.get(Number(body.user_id));
    else if (body.username) target = q.userByName.get(String(body.username));
    if (!target) throw new HttpError(404, 'no_user');
    return target;
  }

  const routes = {
    // The accessory catalog (public, same for everyone).
    'GET /api/accessories': () => CATALOG,

    'GET /api/health': () => ({
      ok: true,
      users: q.countUsers.get().n,
      time: Date.now(),
      latest_client: LATEST_CLIENT,
      min_client: gate.min(),
      download: DOWNLOAD_PAGE,
    }),

    'POST /api/admin/min-version': (req, body) => {
      const { user } = requireStaff(req);
      if (user.role !== 'owner') throw new HttpError(403, 'forbidden');
      const v = String(body.version ?? '').trim();
      if (!/^\d+\.\d+\.\d+$/.test(v)) throw bad('bad_name');
      gate.setMin(v);
      return { min_client: gate.min() };
    },

    'POST /api/register': async (req, body) => {
      if (!authLimiter.allow('reg:' + clientIp(req))) throw new HttpError(429, 'slow_down');
      const username = String(body.username ?? '').trim();
      const password = String(body.password ?? '');
      const displayName = cleanText(body.display_name || username, 24);
      if (!USERNAME_RE.test(username)) throw bad('bad_username');
      if (password.length < 6 || password.length > 128) throw bad('bad_password');
      if (displayName.length < 2) throw bad('bad_name');
      if (!validBirthdate(body.birthdate)) throw bad('bad_birthdate');
      if (q.userByName.get(username)) throw new HttpError(409, 'taken');
      const now = Date.now();
      const info = q.insertUser.run(username, hashPassword(password), displayName, now, now);
      db.prepare('UPDATE users SET birthdate = ? WHERE id = ?').run(body.birthdate, Number(info.lastInsertRowid));
      promoteOwner();
      const user = q.userById.get(Number(info.lastInsertRowid));
      return { token: issueSession(user.id), user: selfProfile(user) };
    },

    'POST /api/login': async (req, body) => {
      if (!authLimiter.allow('login:' + clientIp(req))) throw new HttpError(429, 'slow_down');
      const user = q.userByName.get(String(body.username ?? '').trim());
      if (!user || !verifyPassword(String(body.password ?? ''), user.pass_hash)) {
        throw new HttpError(401, 'bad_credentials');
      }
      if (user.banned) throw new HttpError(403, user.ban_reason ? 'banned_reason' : 'banned', { r: user.ban_reason });
      q.touchUser.run(Date.now(), user.id);
      return { token: issueSession(user.id), user: selfProfile(user) };
    },

    'POST /api/logout': (req) => {
      const { token } = requireAuth(req);
      q.deleteSession.run(token);
      return { ok: true };
    },

    'GET /api/me': (req) => {
      const { user } = requireAuth(req);
      return { user: selfProfile(user) };
    },

    'PATCH /api/me': (req, body) => {
      const { user } = requireAuth(req);
      if (!writeLimiter.allow('me:' + user.id)) throw new HttpError(429, 'slow_down');
      const next = { ...user };
      if (body.display_name !== undefined) {
        next.display_name = cleanText(body.display_name, 24);
        if (next.display_name.length < 2) throw bad('bad_name');
      }
      if (body.bio !== undefined) next.bio = cleanText(body.bio, 160);
      if (body.colors !== undefined) {
        if (!body.colors || typeof body.colors !== 'object') throw bad('bad_color');
        const merged = parseColors(user.colors);
        for (const [part, value] of Object.entries(body.colors)) {
          if (!BODY_PARTS.includes(part)) throw bad('bad_part');
          if (!COLOR_RE.test(value)) throw bad('bad_color');
          merged[part] = value.toLowerCase();
        }
        next.colors = JSON.stringify(merged);
      }
      let birthdateChanged = false;
      if (body.birthdate !== undefined && body.birthdate !== user.birthdate) {
        if (!validBirthdate(body.birthdate)) throw bad('bad_birthdate');
        if (user.birthdate) {
          const change = birthdateChange(user);
          if (!change.can) {
            const date = new Date(change.next_at).toISOString().slice(0, 10);
            throw new HttpError(403, 'birthdate_locked', { d: date });
          }
          birthdateChanged = true;
        }
        next.birthdate = body.birthdate;
      }
      if (body.face !== undefined) {
        if (!FACES.includes(body.face)) throw bad('bad_face');
        next.face = body.face;
      }
      if (body.hide_friends !== undefined) next.hide_friends = body.hide_friends ? 1 : 0;
      let worn = wornOf(user);
      if (body.accessories !== undefined) {
        worn = cleanWorn(body.accessories);
        if (!worn) throw bad('bad_hat');
      } else if (body.hat !== undefined) {
        // Older apps only know one hat: swap it, keep everything else that's worn.
        if (body.hat !== 'none' && !accessoryExists(body.hat)) throw bad('bad_hat');
        worn = cleanWorn([...worn.filter((id) => legacyHat([id]) === 'none'), ...(body.hat === 'none' ? [] : [body.hat])]);
      }
      next.hat = legacyHat(worn);
      db.prepare(
        'UPDATE users SET display_name = ?, bio = ?, colors = ?, hat = ?, accessories = ?, birthdate = ?, face = ?, hide_friends = ? WHERE id = ?',
      ).run(
        next.display_name,
        next.bio,
        next.colors,
        next.hat,
        JSON.stringify(worn),
        next.birthdate || '',
        next.face || ':D',
        next.hide_friends ? 1 : 0,
        user.id,
      );
      if (birthdateChanged) db.prepare('UPDATE users SET birthdate_changed_at = ? WHERE id = ?').run(Date.now(), user.id);
      const fresh = q.userById.get(user.id);
      hub.updateUser(fresh);
      return { user: selfProfile(fresh) };
    },

    'POST /api/me/password': (req, body) => {
      const { user, token } = requireAuth(req);
      if (!authLimiter.allow('pw:' + user.id)) throw new HttpError(429, 'slow_down');
      if (!verifyPassword(String(body.old_password ?? ''), user.pass_hash)) throw bad('wrong_password');
      const pw = String(body.new_password ?? '');
      if (pw.length < 6 || pw.length > 128) throw bad('bad_password');
      db.prepare('UPDATE users SET pass_hash = ? WHERE id = ?').run(hashPassword(pw), user.id);
      q.deleteOtherSessions.run(user.id, token);
      return { ok: true };
    },

    'GET /api/users/search': (req, _body, url) => {
      const { user } = requireAuth(req);
      const term = cleanText(url.searchParams.get('q'), 24);
      if (term.length < 2) return { users: [] };
      const like = '%' + term.replace(/[\\%_]/g, (m) => '\\' + m) + '%';
      return { users: q.search.all(like, like, user.id).map((u) => publicProfile(u, user.id)) };
    },

    'GET /api/users/:name': (req, _body, _url, params) => {
      const { user } = requireAuth(req);
      const target = q.userByName.get(params.name);
      if (!target) throw new HttpError(404, 'no_user');
      return { user: publicProfile(target, user.id) };
    },

    'GET /api/friends': (req) => {
      const { user } = requireAuth(req);
      const friends = [];
      const incoming = [];
      const outgoing = [];
      for (const row of q.friendsOf.all(user.id, user.id, user.id)) {
        const p = publicProfile(row);
        if (row.status === 'accepted') friends.push(p);
        else if (row.to_id === user.id) incoming.push(p);
        else outgoing.push(p);
      }
      friends.sort((a, b) => Number(!!b.playing) - Number(!!a.playing) || Number(b.online) - Number(a.online) || a.display_name.localeCompare(b.display_name));
      return { friends, incoming, outgoing };
    },

    'POST /api/friends/request': (req, body) => {
      const { user } = requireAuth(req);
      if (!writeLimiter.allow('fr:' + user.id)) throw new HttpError(429, 'slow_down');
      const target = lookupTarget(body);
      if (target.id === user.id) throw bad('self');
      if (q.blockRow.get(target.id, user.id) || q.blockRow.get(user.id, target.id)) throw new HttpError(403, 'blocked');
      const rel = relation(user.id, target.id);
      if (rel === 'friends') return { relation: 'friends' };
      if (rel === 'outgoing') return { relation: 'outgoing' };
      if (rel === 'incoming') {
        q.acceptFriend.run(target.id, user.id);
        return { relation: 'friends' };
      }
      q.insertFriend.run(user.id, target.id, 'pending', Date.now());
      return { relation: 'outgoing' };
    },

    'POST /api/friends/accept': (req, body) => {
      const { user } = requireAuth(req);
      const target = lookupTarget(body);
      const row = q.friendRow.get(target.id, user.id);
      if (!row) throw new HttpError(404, 'no_request');
      q.acceptFriend.run(target.id, user.id);
      return { relation: 'friends' };
    },

    'POST /api/friends/remove': (req, body) => {
      const { user } = requireAuth(req);
      const target = lookupTarget(body);
      q.deleteFriend.run(user.id, target.id, target.id, user.id);
      return { relation: 'none' };
    },

    'GET /api/blocks': (req) => {
      const { user } = requireAuth(req);
      return { users: q.blockedUsers.all(user.id).map((u) => publicProfile(u)) };
    },

    'POST /api/blocks/add': (req, body) => {
      const { user } = requireAuth(req);
      const target = lookupTarget(body);
      if (target.id === user.id) throw bad('self');
      q.insertBlock.run(user.id, target.id, Date.now());
      q.deleteFriend.run(user.id, target.id, target.id, user.id);
      hub.setBlocks(user.id, blockSet(user.id));
      return { relation: 'blocked' };
    },

    'POST /api/blocks/remove': (req, body) => {
      const { user } = requireAuth(req);
      const target = lookupTarget(body);
      q.deleteBlock.run(user.id, target.id);
      hub.setBlocks(user.id, blockSet(user.id));
      return { relation: 'none' };
    },

    // The website queues a join, then opens the app (meltiew://play); the app picks it up.
    'POST /api/launch': (req, body) => {
      const { user } = requireAuth(req);
      let game = 'playground';
      if (GAMES[body.game]) game = body.game;
      else if (body.game) game = visibleRow(user, String(body.game)).id;
      let server = String(body.server ?? 'auto');
      if (server !== 'auto' && server !== 'new') {
        if (!hub.hasServer(server)) throw new HttpError(404, 'bad_server');
        // A specific server decides the place (joining a friend wherever they are).
        const on = hub.gameOf(server);
        game = GAMES[on] ? on : visibleRow(user, on).id;
      }
      launches.set(user.id, { server, game, at: Date.now() });
      return { ok: true, server, game };
    },

    'GET /api/launch': (req) => {
      const { user } = requireAuth(req);
      const l = launches.get(user.id);
      launches.delete(user.id);
      if (!l || Date.now() - l.at > LAUNCH_TTL_MS) return { launch: null };
      return { launch: { server: l.server, game: l.game } };
    },

    // The app renders a bust of the avatar and uploads it for the website.
    'POST /api/me/render': (req, body) => {
      const { user } = requireAuth(req);
      if (!writeLimiter.allow('render:' + user.id)) throw new HttpError(429, 'slow_down');
      const hash = String(body.hash ?? '').replace(/[^a-z0-9]/gi, '').slice(0, 40);
      let png;
      try {
        png = Buffer.from(String(body.png ?? ''), 'base64');
      } catch {
        throw bad('bad_image');
      }
      if (!hash || png.length < 64 || png.length > 450 * 1024 || !png.subarray(0, 8).equals(PNG_MAGIC)) throw bad('bad_image');
      const file = path.join(renderDir, `${user.id}.png`);
      fs.writeFileSync(file + '.tmp', png);
      fs.renameSync(file + '.tmp', file);
      q.setRender.run(hash, user.id);
      return { render: hash };
    },

    'GET /api/avatar/:file': (_req, _body, _url, params) => {
      const id = parseInt(params.file, 10);
      const file = path.join(renderDir, `${id}.png`);
      if (Number.isFinite(id) && fs.existsSync(file)) {
        return { __raw: { type: 'image/png', body: fs.readFileSync(file), cache: 'public, max-age=60' } };
      }
      return { __redirect: '/img/default-bust.png' };
    },

    'GET /api/places': (req, _body, url) => {
      const { user } = requireAuth(req);
      const term = cleanText(url.searchParams.get('q'), 40).toLowerCase();
      let list = pq.all.all();
      if (term) {
        list = list.filter((p) =>
          [p.name, p.name_ru, p.description, p.description_ru, p.author_username, p.i18n].some((f) => String(f).toLowerCase().includes(term)),
        );
      }
      const lang = pickLang(req);
      const views = list.map((p) => placeView(p, user.id, lang));
      // Busy places first, then the most liked and visited.
      views.sort((a, b) => b.playing - a.playing || b.likes - a.likes || b.visits - a.visits);
      return { places: views };
    },

    'GET /api/places/:id': (req, _body, _url, params) => {
      const { user } = requireAuth(req);
      const p = visibleRow(user, params.id);
      return { place: placeView(p, user.id, pickLang(req)), servers: serversFor(p.id, user.id) };
    },

    'POST /api/places/:id/vote': (req, body, _url, params) => {
      const { user } = requireAuth(req);
      if (!writeLimiter.allow('vote:' + user.id)) throw new HttpError(429, 'slow_down');
      const p = visibleRow(user, params.id);
      const value = Number(body.value);
      if (value === 1 || value === -1) pq.setVote.run(p.id, user.id, value);
      else pq.clearVote.run(p.id, user.id);
      return { place: placeView(p, user.id, pickLang(req)) };
    },

    // --- admin panel (admins and the owner) ---------------------------------
    'GET /api/admin/stats': (req) => {
      requireStaff(req);
      const count = (sql, ...a) => db.prepare(sql).get(...a).n;
      const day = Date.now() - 86_400_000;
      return {
        users: count('SELECT COUNT(*) AS n FROM users'),
        new_today: count('SELECT COUNT(*) AS n FROM users WHERE created_at > ?', day),
        active_today: count('SELECT COUNT(*) AS n FROM users WHERE last_seen > ?', day),
        online: count('SELECT COUNT(*) AS n FROM users WHERE last_seen > ?', Date.now() - ONLINE_WINDOW_MS),
        banned: count('SELECT COUNT(*) AS n FROM users WHERE banned = 1'),
        friendships: count("SELECT COUNT(*) AS n FROM friendships WHERE status = 'accepted'"),
        servers: hub.servers.size,
        playing: [...hub.servers.values()].reduce((n, s) => n + s.players.size, 0),
        uptime: Math.round(process.uptime()),
        memory_mb: Math.round(process.memoryUsage().rss / 1048576),
      };
    },

    'GET /api/admin/users': (req, _body, url) => {
      requireStaff(req);
      const term = cleanText(url.searchParams.get('q'), 24);
      const like = '%' + term.replace(/[\\%_]/g, (m) => '\\' + m) + '%';
      const rows = db
        .prepare(
          "SELECT * FROM users WHERE username LIKE ? ESCAPE '\\' OR display_name LIKE ? ESCAPE '\\' ORDER BY last_seen DESC LIMIT 60",
        )
        .all(like, like);
      return { users: rows.map(adminUser) };
    },

    'POST /api/admin/users/:id': (req, body, _url, params) => {
      const { user: me } = requireStaff(req);
      const target = q.userById.get(Number(params.id));
      if (!target) throw new HttpError(404, 'no_user');
      const isOwner = me.role === 'owner';
      // Admins can moderate regular users; only the owner manages admins.
      if (!isOwner && target.role !== 'user') throw new HttpError(403, 'forbidden');
      if (target.role === 'owner') throw new HttpError(403, 'forbidden');
      if (body.banned !== undefined) {
        const banned = body.banned ? 1 : 0;
        db.prepare('UPDATE users SET banned = ?, ban_reason = ? WHERE id = ?').run(banned, banned ? cleanText(body.reason, 120) : '', target.id);
        if (banned) {
          db.prepare('DELETE FROM sessions WHERE user_id = ?').run(target.id);
          hub.kick(target.id, 'banned', msg('banned', 'en'));
        }
      }
      if (body.role !== undefined) {
        if (!isOwner || !['user', 'admin'].includes(body.role)) throw new HttpError(403, 'forbidden');
        db.prepare('UPDATE users SET role = ? WHERE id = ?').run(body.role, target.id);
      }
      if (body.reset_birthdate) db.prepare("UPDATE users SET birthdate = '' WHERE id = ?").run(target.id);
      if (body.reset_profile) {
        db.prepare("UPDATE users SET bio = '', display_name = username WHERE id = ?").run(target.id);
        hub.updateUser(q.userById.get(target.id));
      }
      return { user: adminUser(q.userById.get(target.id)) };
    },

    'POST /api/admin/kick': (req, body) => {
      requireStaff(req);
      const target = lookupTarget(body);
      return { kicked: hub.kick(target.id, 'kicked', msg('kicked', 'en')) };
    },

    'GET /api/admin/servers': (req) => {
      requireStaff(req);
      return {
        servers: [...hub.servers.values()].map((s) => ({
          ...hub.describe(s),
          players_list: [...s.players.values()].map((p) => ({ id: p.user.id, username: p.user.username, display_name: p.user.display_name })),
        })),
      };
    },

    'POST /api/admin/servers/:id/close': (req, _body, _url, params) => {
      requireStaff(req);
      return { closed: hub.closeServer(params.id) };
    },

    'POST /api/admin/announce': (req, body) => {
      requireStaff(req);
      const text = cleanText(body.text, 200);
      if (!text) throw bad('bad_name');
      hub.announce(text);
      return { ok: true };
    },

    'PATCH /api/admin/places/:id': (req, body, _url, params) => {
      requireStaff(req);
      const p = pq.one.get(params.id);
      if (!p) throw new HttpError(404, 'no_place');
      pq.update.run(
        cleanText(body.name ?? p.name, 40),
        cleanText(body.name_ru ?? p.name_ru, 40),
        cleanText(body.description ?? p.description, 300),
        cleanText(body.description_ru ?? p.description_ru, 300),
        p.id,
      );
      return { place: placeView(pq.one.get(p.id), null) };
    },

    'GET /api/users/:name/friends': (req, _body, _url, params) => {
      const { user } = requireAuth(req);
      const target = q.userByName.get(params.name);
      if (!target) throw new HttpError(404, 'no_user');
      const staff = user.role === 'owner' || user.role === 'admin';
      if (target.hide_friends && target.id !== user.id && !staff) return { hidden: true, friends: [] };
      const friends = q.friendsOf
        .all(target.id, target.id, target.id)
        .filter((r) => r.status === 'accepted')
        .map((r) => publicProfile(r));
      friends.sort((a, b) => Number(!!b.playing) - Number(!!a.playing) || Number(b.online) - Number(a.online));
      return { hidden: false, friends };
    },

    'GET /api/notifications': (req) => {
      const { user } = requireAuth(req);
      const n = (sql, ...a) => db.prepare(sql).get(...a).n;
      return {
        dm_unread: n('SELECT COUNT(*) AS n FROM messages m WHERE m.to_id = ? AND m.read = 0 AND NOT EXISTS (SELECT 1 FROM blocks b WHERE b.user_id = ? AND b.blocked_id = m.from_id)', user.id, user.id),
        dm_requests: n("SELECT COUNT(*) AS n FROM dm_requests WHERE to_id = ? AND status = 'pending'", user.id),
        friend_requests: n("SELECT COUNT(*) AS n FROM friendships WHERE to_id = ? AND status = 'pending'", user.id),
      };
    },

    // --- direct messages ------------------------------------------------------
    'GET /api/dm': (req) => {
      const { user } = requireAuth(req);
      const rules = chatRules(user.birthdate);
      const partners = db
        .prepare(
          `SELECT other, MAX(id) AS last_id FROM (
             SELECT to_id AS other, id FROM messages WHERE from_id = ?
             UNION ALL SELECT from_id AS other, id FROM messages WHERE to_id = ?)
           GROUP BY other ORDER BY last_id DESC LIMIT 100`,
        )
        .all(user.id, user.id);
      const blocked = blockSet(user.id);
      const out = [];
      for (const row of partners) {
        if (blocked.has(row.other)) continue;
        const other = q.userById.get(row.other);
        if (!other) continue;
        const last = db.prepare('SELECT * FROM messages WHERE id = ?').get(row.last_id);
        const unread = db.prepare('SELECT COUNT(*) AS n FROM messages WHERE from_id = ? AND to_id = ? AND read = 0').get(other.id, user.id).n;
        out.push({
          user: publicProfile(other),
          state: dmState(user.id, other.id),
          unread,
          last: {
            from_me: last.from_id === user.id,
            body: last.from_id !== user.id && rules.filter_dm ? filterText(last.body) : last.body,
            created_at: last.created_at,
          },
        });
      }
      return { conversations: out, rules };
    },

    'GET /api/dm/:id': (req, _body, url, params) => {
      const { user } = requireAuth(req);
      const other = q.userById.get(Number(params.id));
      if (!other) throw new HttpError(404, 'no_user');
      const rules = chatRules(user.birthdate);
      const after = Number(url.searchParams.get('after') || 0);
      const rows = db
        .prepare(
          `SELECT * FROM messages WHERE ((from_id = ? AND to_id = ?) OR (from_id = ? AND to_id = ?)) AND id > ?
           ORDER BY id DESC LIMIT 100`,
        )
        .all(user.id, other.id, other.id, user.id, after)
        .reverse();
      db.prepare('UPDATE messages SET read = 1 WHERE from_id = ? AND to_id = ? AND read = 0').run(other.id, user.id);
      return {
        user: publicProfile(other, user.id),
        state: dmState(user.id, other.id),
        can_message: rules.dm && chatRules(other.birthdate).dm,
        messages: rows.map((m) => ({
          id: m.id,
          from_me: m.from_id === user.id,
          body: m.from_id !== user.id && rules.filter_dm ? filterText(m.body) : m.body,
          created_at: m.created_at,
        })),
      };
    },

    'POST /api/dm/:id': (req, body, _url, params) => {
      const { user } = requireAuth(req);
      if (!writeLimiter.allow('dm:' + user.id)) throw new HttpError(429, 'slow_down');
      const other = q.userById.get(Number(params.id));
      if (!other || other.id === user.id) throw new HttpError(404, 'no_user');
      if (!chatRules(user.birthdate).dm) throw new HttpError(403, 'dm_too_young');
      if (!chatRules(other.birthdate).dm) throw new HttpError(403, 'dm_unavailable');
      if (q.blockRow.get(other.id, user.id) || q.blockRow.get(user.id, other.id)) throw new HttpError(403, 'blocked');
      const text = String(body.text ?? '').replace(/[\u0000-\u0008\u000b-\u001f\u007f]/g, '').trim().slice(0, 500);
      if (!text) throw bad('empty');
      let state = dmState(user.id, other.id);
      if (state === 'outgoing') throw new HttpError(403, 'dm_wait');
      if (state === 'incoming') {
        // Replying to a request accepts it.
        db.prepare("UPDATE dm_requests SET status = 'accepted' WHERE from_id = ? AND to_id = ?").run(other.id, user.id);
        state = 'open';
      } else if (state === 'none') {
        db.prepare("INSERT OR REPLACE INTO dm_requests (from_id, to_id, status, created_at) VALUES (?, ?, 'pending', ?)").run(user.id, other.id, Date.now());
        state = 'outgoing';
      }
      const info = db.prepare('INSERT INTO messages (from_id, to_id, body, created_at) VALUES (?, ?, ?, ?)').run(user.id, other.id, text, Date.now());
      return { id: Number(info.lastInsertRowid), state };
    },

    'POST /api/dm/:id/accept': (req, _body, _url, params) => {
      const { user } = requireAuth(req);
      db.prepare("UPDATE dm_requests SET status = 'accepted' WHERE from_id = ? AND to_id = ?").run(Number(params.id), user.id);
      return { state: dmState(user.id, Number(params.id)) };
    },

    'POST /api/dm/:id/decline': (req, _body, _url, params) => {
      const { user } = requireAuth(req);
      const otherId = Number(params.id);
      db.prepare('DELETE FROM dm_requests WHERE from_id = ? AND to_id = ?').run(otherId, user.id);
      db.prepare('DELETE FROM messages WHERE from_id = ? AND to_id = ?').run(otherId, user.id);
      return { state: 'none' };
    },

    // --- reports ----------------------------------------------------------------
    'POST /api/report': (req, body) => {
      const { user } = requireAuth(req);
      if (!writeLimiter.allow('report:' + user.id)) throw new HttpError(429, 'slow_down');
      // A player, a place (target = its owner) or a comment (target = its author).
      let target;
      let type = 'user';
      let ref = '';
      if (body.place_id) {
        const p = visibleRow(user, String(body.place_id));
        target = q.userById.get(p.owner_id) || q.userByName.get(p.author_username);
        type = 'place';
        ref = p.id;
      } else if (body.comment_id) {
        const c = db.prepare('SELECT * FROM place_comments WHERE id = ?').get(Number(body.comment_id));
        if (!c) throw new HttpError(404, 'not_found');
        target = q.userById.get(c.user_id);
        type = 'comment';
        ref = String(c.id);
      } else {
        target = lookupTarget(body);
      }
      if (!target) throw new HttpError(404, 'no_user');
      const reason = ['chat', 'name', 'avatar', 'cheating', 'place', 'comment', 'other'].includes(body.reason) ? body.reason : 'other';
      db.prepare('INSERT INTO reports (reporter_id, target_id, reason, details, created_at, target_type, target_ref) VALUES (?, ?, ?, ?, ?, ?, ?)').run(
        user.id,
        target.id,
        reason,
        cleanText(body.details, 300),
        Date.now(),
        type,
        ref,
      );
      return { ok: true, message: msg('reported', pickLang(req)) };
    },

    'GET /api/admin/reports': (req) => {
      requireStaff(req);
      const rows = db.prepare('SELECT * FROM reports WHERE resolved = 0 ORDER BY id DESC LIMIT 100').all();
      return {
        reports: rows.map((r) => ({
          id: r.id,
          reason: r.reason,
          details: r.details,
          created_at: r.created_at,
          reporter: q.userById.get(r.reporter_id) ? publicProfile(q.userById.get(r.reporter_id)) : null,
          target: q.userById.get(r.target_id) ? adminUser(q.userById.get(r.target_id)) : null,
          target_type: r.target_type || 'user',
          place: r.target_type === 'place' ? (() => { const p = pq.one.get(r.target_ref); return p ? { id: p.id, name: p.name } : null; })() : null,
          comment: r.target_type === 'comment' ? db.prepare('SELECT body, place_id FROM place_comments WHERE id = ?').get(Number(r.target_ref)) || null : null,
        })),
      };
    },

    'POST /api/admin/reports/:id/resolve': (req, _body, _url, params) => {
      requireStaff(req);
      db.prepare('UPDATE reports SET resolved = 1 WHERE id = ?').run(Number(params.id));
      return { ok: true };
    },

    'GET /api/games': (req) => {
      requireAuth(req);
      return {
        games: Object.values(GAMES).map((g) => ({ ...g, playing: hub.playerCount(g.id), max_players: MAX_PLAYERS })),
      };
    },

    'GET /api/servers': (req, _body, url) => {
      const { user } = requireAuth(req);
      const game = url.searchParams.get('game') || 'playground';
      return { servers: serversFor(game, user.id), max_players: MAX_PLAYERS };
    },
  };

  Object.assign(
    routes,
    createStudioRoutes({ db, hub, store, requireAuth, requireStaff, HttpError, bad, cleanText, writeLimiter, publicProfile, authorCard, isFriend, placeView, pickLang }),
  );

  const compiled = Object.entries(routes).map(([key, handler]) => {
    const [method, pattern] = key.split(' ');
    const names = [];
    const re = new RegExp(
      '^' +
        pattern.replace(/:([a-z_]+)/g, (_, n) => {
          names.push(n);
          return '([^/]+)';
        }) +
        '$',
    );
    return { method, re, names, handler };
  });

  async function handle(req, res) {
    const url = new URL(req.url, 'http://local');
    const lang = pickLang(req);
    const send = (status, data) => {
      const body = JSON.stringify(data);
      res.writeHead(status, {
        'content-type': 'application/json; charset=utf-8',
        'cache-control': 'no-store',
        'access-control-allow-origin': '*',
        'access-control-allow-headers': 'authorization, content-type, x-lang, x-client, x-client-version',
        'access-control-allow-methods': 'GET, POST, PATCH, PUT, DELETE, OPTIONS',
      });
      res.end(body);
    };
    if (req.method === 'OPTIONS') return send(204, {});
    // Outdated apps get a clear "please update" instead of half-working.
    const ungated =
      url.pathname === '/api/health' ||
      url.pathname.startsWith('/api/avatar/') ||
      url.pathname.startsWith('/api/assets/') ||
      url.pathname.startsWith('/api/media/');
    if (!ungated && !gate.allows(req.headers['x-client'], req.headers['x-client-version'], req.headers['user-agent'])) {
      return send(426, {
        error: 'update_required',
        message: msg('update_required', lang, { v: gate.min() }),
        min_client: gate.min(),
        download: DOWNLOAD_PAGE,
      });
    }
    let matchedPath = false;
    for (const r of compiled) {
      const m = r.re.exec(url.pathname);
      if (!m) continue;
      matchedPath = true;
      if (r.method !== req.method) continue;
      const params = {};
      r.names.forEach((n, i) => (params[n] = decodeURIComponent(m[i + 1])));
      try {
        // Place files, covers and images are bigger than the usual JSON.
        const big = url.pathname.startsWith('/api/studio/') || url.pathname === '/api/assets';
        const limit = url.pathname === '/api/me/render' ? MAX_RENDER_BODY : big ? MAX_STUDIO_BODY : MAX_BODY;
        const body = req.method === 'GET' ? {} : await readJson(req, limit);
        const out = await r.handler(req, body, url, params);
        if (out && out.__raw) {
          res.writeHead(200, { 'content-type': out.__raw.type, 'cache-control': out.__raw.cache, 'access-control-allow-origin': '*' });
          return res.end(out.__raw.body);
        }
        if (out && out.__redirect) {
          res.writeHead(302, { location: out.__redirect, 'cache-control': 'public, max-age=60' });
          return res.end();
        }
        return send(200, out);
      } catch (err) {
        if (err instanceof HttpError) return send(err.status, { error: err.code, message: msg(err.code, lang, err.vars) });
        console.error(err);
        return send(500, { error: 'internal', message: msg('internal', lang) });
      }
    }
    return send(matchedPath ? 405 : 404, { error: 'not_found', message: msg('not_found', lang) });
  }

  // The anti-cheat kicked someone: leave a note in the admin reports queue.
  function cheatReport(user, reason, game) {
    try {
      db.prepare('INSERT INTO reports (reporter_id, target_id, reason, details, created_at, target_type, target_ref) VALUES (?, ?, ?, ?, ?, ?, ?)').run(
        user.id, user.id, 'cheating', `Anti-cheat: ${reason} in ${game}`, Date.now(), 'user', '');
    } catch {}
  }

  return { handle, userForToken, blockSet, friendSet, isFriend, countVisit: (id) => pq.visit.run(id), gate, cheatReport };
}
