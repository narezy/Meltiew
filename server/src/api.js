import { hashPassword, verifyPassword, newToken, RateLimiter } from './security.js';
import { GAMES, MAX_PLAYERS } from './game.js';
import { BODY_PARTS, COLOR_RE, parseColors } from './colors.js';
import { msg, pickLang } from './i18n.js';
import fs from 'node:fs';
import path from 'node:path';

const USERNAME_RE = /^[A-Za-z0-9_]{3,20}$/;
export const HATS = ['none', 'cap', 'crown', 'catears', 'halo', 'tophat', 'flower', 'headphones'];
const ONLINE_WINDOW_MS = 60_000;
const SESSION_TTL_MS = 1000 * 60 * 60 * 24 * 60;
const MAX_BODY = 16 * 1024;
const MAX_RENDER_BODY = 600 * 1024;
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

export function createApi({ db, hub, renderDir }) {
  fs.mkdirSync(renderDir, { recursive: true });
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

  function blockSet(userId) {
    return new Set(q.blockedBy.all(userId).map((r) => r.blocked_id));
  }

  function presence(u) {
    const where = hub.whereIs(u.id);
    if (where) return { online: true, playing: where };
    return { online: Date.now() - u.last_seen < ONLINE_WINDOW_MS, playing: null };
  }

  function publicProfile(u, viewerId = null) {
    const out = {
      id: u.id,
      username: u.username,
      display_name: u.display_name,
      bio: u.bio,
      colors: parseColors(u.colors),
      hat: u.hat,
      render: u.render_hash || '',
      created_at: u.created_at,
      friends: q.countFriends.get(u.id, u.id).n,
      ...presence(u),
    };
    if (viewerId != null && viewerId !== u.id) out.relation = relation(viewerId, u.id);
    return out;
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
    return user ? { user, token } : null;
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
    'GET /api/health': () => ({ ok: true, users: q.countUsers.get().n, time: Date.now() }),

    'POST /api/register': async (req, body) => {
      if (!authLimiter.allow('reg:' + clientIp(req))) throw new HttpError(429, 'slow_down');
      const username = String(body.username ?? '').trim();
      const password = String(body.password ?? '');
      const displayName = cleanText(body.display_name || username, 24);
      if (!USERNAME_RE.test(username)) throw bad('bad_username');
      if (password.length < 6 || password.length > 128) throw bad('bad_password');
      if (displayName.length < 2) throw bad('bad_name');
      if (q.userByName.get(username)) throw new HttpError(409, 'taken');
      const now = Date.now();
      const info = q.insertUser.run(username, hashPassword(password), displayName, now, now);
      const user = q.userById.get(Number(info.lastInsertRowid));
      return { token: issueSession(user.id), user: publicProfile(user) };
    },

    'POST /api/login': async (req, body) => {
      if (!authLimiter.allow('login:' + clientIp(req))) throw new HttpError(429, 'slow_down');
      const user = q.userByName.get(String(body.username ?? '').trim());
      if (!user || !verifyPassword(String(body.password ?? ''), user.pass_hash)) {
        throw new HttpError(401, 'bad_credentials');
      }
      q.touchUser.run(Date.now(), user.id);
      return { token: issueSession(user.id), user: publicProfile(user) };
    },

    'POST /api/logout': (req) => {
      const { token } = requireAuth(req);
      q.deleteSession.run(token);
      return { ok: true };
    },

    'GET /api/me': (req) => {
      const { user } = requireAuth(req);
      return { user: publicProfile(user) };
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
      if (body.hat !== undefined) {
        if (!HATS.includes(body.hat)) throw bad('bad_hat');
        next.hat = body.hat;
      }
      db.prepare(
        'UPDATE users SET display_name = ?, bio = ?, colors = ?, hat = ? WHERE id = ?',
      ).run(
        next.display_name,
        next.bio,
        next.colors,
        next.hat,
        user.id,
      );
      const fresh = q.userById.get(user.id);
      hub.updateUser(fresh);
      return { user: publicProfile(fresh) };
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
      const game = GAMES[body.game] ? body.game : 'playground';
      let server = String(body.server ?? 'auto');
      if (server !== 'auto' && server !== 'new' && !hub.hasServer(server)) throw new HttpError(404, 'bad_server');
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

    'GET /api/games': (req) => {
      requireAuth(req);
      return {
        games: Object.values(GAMES).map((g) => ({ ...g, playing: hub.playerCount(g.id), max_players: MAX_PLAYERS })),
      };
    },

    'GET /api/servers': (req, _body, url) => {
      const { user } = requireAuth(req);
      const game = url.searchParams.get('game') || 'playground';
      const friendIds = new Set(
        q.friendsOf
          .all(user.id, user.id, user.id)
          .filter((r) => r.status === 'accepted')
          .map((r) => r.id),
      );
      const servers = hub.listServers(game).map((s) => {
        const friends = s.player_ids.filter((id) => friendIds.has(id)).map((id) => q.userById.get(id)?.display_name).filter(Boolean);
        const { player_ids, ...rest } = s;
        return { ...rest, friends };
      });
      return { servers, max_players: MAX_PLAYERS };
    },
  };

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
        'access-control-allow-headers': 'authorization, content-type, x-lang',
        'access-control-allow-methods': 'GET, POST, PATCH, OPTIONS',
      });
      res.end(body);
    };
    if (req.method === 'OPTIONS') return send(204, {});
    let matchedPath = false;
    for (const r of compiled) {
      const m = r.re.exec(url.pathname);
      if (!m) continue;
      matchedPath = true;
      if (r.method !== req.method) continue;
      const params = {};
      r.names.forEach((n, i) => (params[n] = decodeURIComponent(m[i + 1])));
      try {
        const limit = url.pathname === '/api/me/render' ? MAX_RENDER_BODY : MAX_BODY;
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

  return { handle, userForToken, blockSet };
}
