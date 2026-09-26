// Communities: groups of players with a name, members, roles and text channels.
// Creating one costs 10 pieces or 100 orbs. A community can own places: members
// whose role allows it open, edit and publish them in Studio together.
//
// Roles have a rank (1-255; the owner is 255) and permissions:
//   manage   - edit the community, its channels and roles, give roles below your own
//   moderate - delete messages, remove and ban members ranked below you
//   places   - make, edit and publish the community's places
//   post     - write in channels (each channel can also ask for a minimum rank)
import { chatRules } from './age.js';
import { filterText } from './filter.js';
import { pickLang } from './i18n.js';

export const COMMUNITY_PRICE = { pieces: 10, orbs: 100 };
export const PERMS = ['manage', 'moderate', 'places', 'post'];
const MAX_OWNED = 5;
const MAX_JOINED = 50;
const MAX_ROLES = 12;
const MAX_CHANNELS = 15;
const COLORS = ['#b79cff', '#7ee0c3', '#4cc9f0', '#ffb86b', '#ff8fb1', '#ffd166', '#9d7bff', '#6bd6a5'];

export function migrateCommunities(db) {
  db.exec(`
    CREATE TABLE IF NOT EXISTS communities (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      name        TEXT NOT NULL,
      name_lc     TEXT NOT NULL UNIQUE,
      description TEXT NOT NULL DEFAULT '',
      color       TEXT NOT NULL DEFAULT '#b79cff',
      owner_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      members     INTEGER NOT NULL DEFAULT 0,
      deleted     INTEGER NOT NULL DEFAULT 0,
      created_at  INTEGER NOT NULL
    );
    CREATE TABLE IF NOT EXISTS community_roles (
      id           INTEGER PRIMARY KEY AUTOINCREMENT,
      community_id INTEGER NOT NULL REFERENCES communities(id) ON DELETE CASCADE,
      name         TEXT NOT NULL,
      rank         INTEGER NOT NULL,
      perms        TEXT NOT NULL DEFAULT '[]'
    );
    CREATE TABLE IF NOT EXISTS community_members (
      community_id INTEGER NOT NULL REFERENCES communities(id) ON DELETE CASCADE,
      user_id      INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      role_id      INTEGER NOT NULL,
      joined_at    INTEGER NOT NULL,
      PRIMARY KEY (community_id, user_id)
    );
    CREATE INDEX IF NOT EXISTS community_members_user ON community_members(user_id);
    CREATE TABLE IF NOT EXISTS community_bans (
      community_id INTEGER NOT NULL REFERENCES communities(id) ON DELETE CASCADE,
      user_id      INTEGER NOT NULL,
      PRIMARY KEY (community_id, user_id)
    );
    CREATE TABLE IF NOT EXISTS community_channels (
      id           INTEGER PRIMARY KEY AUTOINCREMENT,
      community_id INTEGER NOT NULL REFERENCES communities(id) ON DELETE CASCADE,
      name         TEXT NOT NULL,
      post_rank    INTEGER NOT NULL DEFAULT 1,
      position     INTEGER NOT NULL DEFAULT 0
    );
    CREATE TABLE IF NOT EXISTS community_messages (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      channel_id INTEGER NOT NULL REFERENCES community_channels(id) ON DELETE CASCADE,
      user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      body       TEXT NOT NULL,
      created_at INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS community_messages_channel ON community_messages(channel_id, id);
  `);
  const cols = new Set(db.prepare('PRAGMA table_info(places)').all().map((c) => c.name));
  if (!cols.has('community_id')) db.exec('ALTER TABLE places ADD COLUMN community_id INTEGER');
  if (!cols.has('edited_by')) db.exec('ALTER TABLE places ADD COLUMN edited_by INTEGER');
}

export function createCommunities({ db, economy, HttpError, bad, cleanText, requireAuth, writeLimiter, authorCard, placeView, canSee }) {
  const q = {
    one: db.prepare('SELECT * FROM communities WHERE id = ? AND deleted = 0'),
    byName: db.prepare('SELECT id FROM communities WHERE name_lc = ? AND deleted = 0'),
    insert: db.prepare('INSERT INTO communities (name, name_lc, description, color, owner_id, members, created_at) VALUES (?, ?, ?, ?, ?, 0, ?)'),
    update: db.prepare('UPDATE communities SET name = ?, name_lc = ?, description = ?, color = ? WHERE id = ?'),
    remove: db.prepare("UPDATE communities SET deleted = 1, name_lc = name_lc || '#' || id WHERE id = ?"),
    search: db.prepare("SELECT * FROM communities WHERE deleted = 0 AND name_lc LIKE ? ESCAPE '\\' ORDER BY members DESC, id LIMIT 30"),
    top: db.prepare('SELECT * FROM communities WHERE deleted = 0 ORDER BY members DESC, id LIMIT 30'),
    mine: db.prepare(`SELECT c.*, r.name AS role_name, r.rank AS role_rank FROM community_members m
      JOIN communities c ON c.id = m.community_id AND c.deleted = 0 JOIN community_roles r ON r.id = m.role_id
      WHERE m.user_id = ? ORDER BY r.rank DESC, c.name`),
    ownedCount: db.prepare('SELECT COUNT(*) AS n FROM communities WHERE owner_id = ? AND deleted = 0'),
    joinedCount: db.prepare('SELECT COUNT(*) AS n FROM community_members m JOIN communities c ON c.id = m.community_id AND c.deleted = 0 WHERE m.user_id = ?'),
    recount: db.prepare('UPDATE communities SET members = (SELECT COUNT(*) FROM community_members WHERE community_id = ?) WHERE id = ?'),
    roles: db.prepare('SELECT * FROM community_roles WHERE community_id = ? ORDER BY rank DESC'),
    role: db.prepare('SELECT * FROM community_roles WHERE id = ? AND community_id = ?'),
    insertRole: db.prepare('INSERT INTO community_roles (community_id, name, rank, perms) VALUES (?, ?, ?, ?)'),
    updateRole: db.prepare('UPDATE community_roles SET name = ?, rank = ?, perms = ? WHERE id = ?'),
    deleteRole: db.prepare('DELETE FROM community_roles WHERE id = ?'),
    lowestRole: db.prepare('SELECT * FROM community_roles WHERE community_id = ? ORDER BY rank ASC LIMIT 1'),
    member: db.prepare('SELECT m.*, r.rank, r.perms, r.name AS role_name FROM community_members m JOIN community_roles r ON r.id = m.role_id WHERE m.community_id = ? AND m.user_id = ?'),
    members: db.prepare(`SELECT m.user_id, m.role_id, m.joined_at, u.* FROM community_members m JOIN users u ON u.id = m.user_id
      JOIN community_roles r ON r.id = m.role_id WHERE m.community_id = ? AND u.banned = 0 ORDER BY r.rank DESC, m.joined_at LIMIT 100 OFFSET ?`),
    addMember: db.prepare('INSERT INTO community_members (community_id, user_id, role_id, joined_at) VALUES (?, ?, ?, ?)'),
    setRole: db.prepare('UPDATE community_members SET role_id = ? WHERE community_id = ? AND user_id = ?'),
    moveRole: db.prepare('UPDATE community_members SET role_id = ? WHERE role_id = ?'),
    removeMember: db.prepare('DELETE FROM community_members WHERE community_id = ? AND user_id = ?'),
    ban: db.prepare('INSERT OR IGNORE INTO community_bans (community_id, user_id) VALUES (?, ?)'),
    banned: db.prepare('SELECT 1 FROM community_bans WHERE community_id = ? AND user_id = ?'),
    channels: db.prepare('SELECT * FROM community_channels WHERE community_id = ? ORDER BY position, id'),
    channel: db.prepare('SELECT * FROM community_channels WHERE id = ? AND community_id = ?'),
    insertChannel: db.prepare('INSERT INTO community_channels (community_id, name, post_rank, position) VALUES (?, ?, ?, ?)'),
    updateChannel: db.prepare('UPDATE community_channels SET name = ?, post_rank = ? WHERE id = ?'),
    deleteChannel: db.prepare('DELETE FROM community_channels WHERE id = ?'),
    after: db.prepare(`SELECT m.*, u.username, u.display_name, u.role, u.render_hash, u.colors, u.hat, u.face FROM community_messages m
      JOIN users u ON u.id = m.user_id WHERE m.channel_id = ? AND m.id > ? AND u.banned = 0 ORDER BY m.id LIMIT 60`),
    before: db.prepare(`SELECT m.*, u.username, u.display_name, u.role, u.render_hash, u.colors, u.hat, u.face FROM community_messages m
      JOIN users u ON u.id = m.user_id WHERE m.channel_id = ? AND m.id < ? AND u.banned = 0 ORDER BY m.id DESC LIMIT 50`),
    message: db.prepare('SELECT m.*, c.community_id FROM community_messages m JOIN community_channels c ON c.id = m.channel_id WHERE m.id = ?'),
    insertMessage: db.prepare('INSERT INTO community_messages (channel_id, user_id, body, created_at) VALUES (?, ?, ?, ?)'),
    deleteMessage: db.prepare('DELETE FROM community_messages WHERE id = ?'),
    places: db.prepare("SELECT * FROM places WHERE community_id = ? AND kind = 'studio' AND deleted = 0 ORDER BY visits DESC"),
    releasePlaces: db.prepare('UPDATE places SET community_id = NULL, owner_id = ? WHERE community_id = ?'),
    userById: db.prepare('SELECT * FROM users WHERE id = ?'),
  };

  function tx(fn) {
    db.exec('BEGIN IMMEDIATE');
    try {
      const out = fn();
      db.exec('COMMIT');
      return out;
    } catch (e) {
      db.exec('ROLLBACK');
      throw e;
    }
  }

  const perms = (row) => {
    try {
      return new Set(JSON.parse(row?.perms || '[]'));
    } catch {
      return new Set();
    }
  };
  const cleanPerms = (list) => (Array.isArray(list) ? PERMS.filter((p) => list.includes(p)) : []);

  /** Your place in a community: { rank, perms:Set, role_id } or null. */
  function membership(communityId, userId) {
    const m = q.member.get(communityId, userId);
    return m ? { rank: m.rank, perms: perms(m), role_id: m.role_id, role_name: m.role_name } : null;
  }

  function can(communityId, userId, perm) {
    const m = membership(communityId, userId);
    return !!m && (m.rank >= 255 || m.perms.has(perm));
  }

  function communityOr404(id) {
    const c = q.one.get(Number(id));
    if (!c) throw new HttpError(404, 'no_community');
    return c;
  }

  function need(req, id, perm) {
    const auth = requireAuth(req);
    const c = communityOr404(id);
    const m = membership(c.id, auth.user.id);
    if (!m || (m.rank < 255 && !m.perms.has(perm))) throw new HttpError(403, 'forbidden');
    return { ...auth, c, m };
  }

  function cleanName(v) {
    const name = cleanText(v, 40);
    if (name.length < 3 || filterText(name) !== name) throw bad('bad_community_name');
    return name;
  }

  const roleView = (r) => ({ id: r.id, name: r.name, rank: r.rank, perms: [...perms(r)] });
  const channelView = (ch) => ({ id: ch.id, name: ch.name, post_rank: ch.post_rank });

  function card(c) {
    return { id: c.id, name: c.name, description: c.description, color: c.color, members: c.members, created_at: c.created_at };
  }

  function view(c, userId) {
    const m = membership(c.id, userId);
    const owner = q.userById.get(c.owner_id);
    return {
      ...card(c),
      owner: owner ? authorCard(owner) : null,
      roles: q.roles.all(c.id).map(roleView),
      channels: q.channels.all(c.id).map(channelView),
      me: m ? { rank: m.rank, role_id: m.role_id, role_name: m.role_name, perms: m.rank >= 255 ? [...PERMS] : [...m.perms] } : null,
      banned: !m && !!q.banned.get(c.id, userId),
    };
  }

  function messageView(m, viewer) {
    const body = viewer.rules.filter_chat && m.user_id !== viewer.id ? filterText(m.body) : m.body;
    return { id: m.id, body, created_at: m.created_at, author: authorCard({ ...m, id: m.user_id }) };
  }

  const routes = {
    // Search by name, or the biggest ones.
    'GET /api/communities': (req, _b, url) => {
      requireAuth(req);
      const text = String(url.searchParams.get('q') || '').trim().toLowerCase().slice(0, 40);
      const rows = text ? q.search.all('%' + text.replace(/[\\%_]/g, (ch) => '\\' + ch) + '%') : q.top.all();
      return { communities: rows.map(card), price: COMMUNITY_PRICE };
    },

    'GET /api/communities/mine': (req) => {
      const { user } = requireAuth(req);
      return { communities: q.mine.all(user.id).map((c) => ({ ...card(c), role_name: c.role_name, rank: c.role_rank })), price: COMMUNITY_PRICE };
    },

    'POST /api/communities': (req, body) => {
      const { user } = requireAuth(req);
      if (!writeLimiter.allow('community:' + user.id)) throw new HttpError(429, 'slow_down');
      const name = cleanName(body.name);
      const description = String(body.description ?? '').slice(0, 1000);
      const currency = body.currency === 'orbs' ? 'orbs' : 'pieces';
      if (q.ownedCount.get(user.id).n >= MAX_OWNED) throw bad('too_many_communities');
      if (q.joinedCount.get(user.id).n >= MAX_JOINED) throw bad('too_many_joined');
      if (q.byName.get(name.toLowerCase())) throw bad('community_name_taken');
      const color = COLORS.includes(body.color) ? body.color : COLORS[Math.floor(Math.random() * COLORS.length)];
      const id = tx(() => {
        economy.change(user.id, currency, -COMMUNITY_PRICE[currency], 'community', name);
        const now = Date.now();
        const cid = Number(q.insert.run(name, name.toLowerCase(), description, color, user.id, now).lastInsertRowid);
        const ownerRole = Number(q.insertRole.run(cid, 'Owner', 255, JSON.stringify(PERMS)).lastInsertRowid);
        q.insertRole.run(cid, 'Admin', 200, JSON.stringify(['manage', 'moderate', 'places', 'post']));
        q.insertRole.run(cid, 'Builder', 100, JSON.stringify(['places', 'post']));
        q.insertRole.run(cid, 'Member', 1, JSON.stringify(['post']));
        q.insertChannel.run(cid, 'general', 1, 0);
        q.insertChannel.run(cid, 'announcements', 200, 1);
        q.addMember.run(cid, user.id, ownerRole, now);
        q.recount.run(cid, cid);
        return cid;
      });
      return { community: view(q.one.get(id), user.id), wallet: economy.wallet(user.id) };
    },

    'GET /api/communities/:id': (req, _b, _u, params) => {
      const { user } = requireAuth(req);
      return { community: view(communityOr404(params.id), user.id) };
    },

    'PATCH /api/communities/:id': (req, body, _u, params) => {
      const { user, c } = need(req, params.id, 'manage');
      const name = body.name !== undefined ? cleanName(body.name) : c.name;
      if (name.toLowerCase() !== c.name_lc && q.byName.get(name.toLowerCase())) throw bad('community_name_taken');
      const description = body.description !== undefined ? String(body.description).slice(0, 1000) : c.description;
      const color = COLORS.includes(body.color) ? body.color : c.color;
      q.update.run(name, name.toLowerCase(), description, color, c.id);
      return { community: view(q.one.get(c.id), user.id) };
    },

    // Only the owner deletes it; its places go back to the owner.
    'DELETE /api/communities/:id': (req, _b, _u, params) => {
      const { user } = requireAuth(req);
      const c = communityOr404(params.id);
      if (c.owner_id !== user.id) throw new HttpError(403, 'forbidden');
      tx(() => {
        q.releasePlaces.run(c.owner_id, c.id);
        q.remove.run(c.id);
      });
      return { ok: true };
    },

    'POST /api/communities/:id/join': (req, _b, _u, params) => {
      const { user } = requireAuth(req);
      const c = communityOr404(params.id);
      if (q.member.get(c.id, user.id)) return { community: view(c, user.id) };
      if (q.banned.get(c.id, user.id)) throw new HttpError(403, 'community_banned');
      if (q.joinedCount.get(user.id).n >= MAX_JOINED) throw bad('too_many_joined');
      tx(() => {
        q.addMember.run(c.id, user.id, q.lowestRole.get(c.id).id, Date.now());
        q.recount.run(c.id, c.id);
      });
      return { community: view(q.one.get(c.id), user.id) };
    },

    'POST /api/communities/:id/leave': (req, _b, _u, params) => {
      const { user } = requireAuth(req);
      const c = communityOr404(params.id);
      if (c.owner_id === user.id) throw bad('owner_cannot_leave');
      tx(() => {
        q.removeMember.run(c.id, user.id);
        q.recount.run(c.id, c.id);
      });
      return { community: view(q.one.get(c.id), user.id) };
    },

    'GET /api/communities/:id/members': (req, _b, url, params) => {
      requireAuth(req);
      const c = communityOr404(params.id);
      const offset = Math.max(0, Number(url.searchParams.get('offset')) || 0);
      return { members: q.members.all(c.id, offset).map((m) => ({ ...authorCard({ ...m, id: m.user_id }), role_id: m.role_id, joined_at: m.joined_at })) };
    },

    // Give someone ranked below you a role ranked below you.
    'PATCH /api/communities/:id/members/:uid': (req, body, _u, params) => {
      const { c, m } = need(req, params.id, 'manage');
      const target = membership(c.id, Number(params.uid));
      const role = q.role.get(Number(body.role_id), c.id);
      if (!target || !role) throw new HttpError(404, 'no_member');
      if (target.rank >= m.rank || role.rank >= m.rank) throw new HttpError(403, 'forbidden');
      q.setRole.run(role.id, c.id, Number(params.uid));
      return { ok: true };
    },

    // Remove (and optionally ban) someone ranked below you.
    'DELETE /api/communities/:id/members/:uid': (req, body, url, params) => {
      const { c, m } = need(req, params.id, 'moderate');
      const uid = Number(params.uid);
      const target = membership(c.id, uid);
      if (!target) throw new HttpError(404, 'no_member');
      if (target.rank >= m.rank) throw new HttpError(403, 'forbidden');
      tx(() => {
        q.removeMember.run(c.id, uid);
        if (body?.ban || url.searchParams.get('ban') === '1') q.ban.run(c.id, uid);
        q.recount.run(c.id, c.id);
      });
      return { ok: true };
    },

    'POST /api/communities/:id/roles': (req, body, _u, params) => {
      const { user, c, m } = need(req, params.id, 'manage');
      if (q.roles.all(c.id).length >= MAX_ROLES) throw bad('too_many_roles');
      const rank = Math.round(Number(body.rank));
      if (!(rank >= 2 && rank <= 254) || rank >= m.rank) throw bad('bad_rank');
      const name = cleanText(body.name, 30);
      if (!name) throw bad('bad_name');
      q.insertRole.run(c.id, name, rank, JSON.stringify(cleanPerms(body.perms)));
      return { community: view(c, user.id) };
    },

    'PATCH /api/communities/:id/roles/:rid': (req, body, _u, params) => {
      const { user, c, m } = need(req, params.id, 'manage');
      const role = q.role.get(Number(params.rid), c.id);
      if (!role) throw new HttpError(404, 'no_role');
      if (role.rank >= m.rank) throw new HttpError(403, 'forbidden');
      const lowest = q.lowestRole.get(c.id);
      let rank = body.rank !== undefined ? Math.round(Number(body.rank)) : role.rank;
      // The entry role stays the lowest one.
      if (role.id === lowest.id) rank = role.rank;
      else if (!(rank >= 2 && rank <= 254) || rank >= m.rank) throw bad('bad_rank');
      const name = body.name !== undefined ? cleanText(body.name, 30) || role.name : role.name;
      const list = body.perms !== undefined ? cleanPerms(body.perms) : [...perms(role)];
      q.updateRole.run(name, rank, JSON.stringify(list), role.id);
      return { community: view(c, user.id) };
    },

    'DELETE /api/communities/:id/roles/:rid': (req, _b, _u, params) => {
      const { user, c, m } = need(req, params.id, 'manage');
      const role = q.role.get(Number(params.rid), c.id);
      const lowest = q.lowestRole.get(c.id);
      if (!role) throw new HttpError(404, 'no_role');
      if (role.rank >= m.rank || role.id === lowest.id) throw new HttpError(403, 'forbidden');
      tx(() => {
        q.moveRole.run(lowest.id, role.id);
        q.deleteRole.run(role.id);
      });
      return { community: view(c, user.id) };
    },

    'POST /api/communities/:id/channels': (req, body, _u, params) => {
      const { user, c } = need(req, params.id, 'manage');
      const list = q.channels.all(c.id);
      if (list.length >= MAX_CHANNELS) throw bad('too_many_channels');
      const name = cleanText(body.name, 30).toLowerCase().replace(/\s+/g, '-');
      if (!name) throw bad('bad_name');
      const postRank = Math.max(1, Math.min(255, Math.round(Number(body.post_rank) || 1)));
      q.insertChannel.run(c.id, name, postRank, list.length);
      return { community: view(c, user.id) };
    },

    'PATCH /api/communities/:id/channels/:cid': (req, body, _u, params) => {
      const { user, c } = need(req, params.id, 'manage');
      const ch = q.channel.get(Number(params.cid), c.id);
      if (!ch) throw new HttpError(404, 'no_channel');
      const name = body.name !== undefined ? cleanText(body.name, 30).toLowerCase().replace(/\s+/g, '-') || ch.name : ch.name;
      const postRank = body.post_rank !== undefined ? Math.max(1, Math.min(255, Math.round(Number(body.post_rank) || 1))) : ch.post_rank;
      q.updateChannel.run(name, postRank, ch.id);
      return { community: view(c, user.id) };
    },

    'DELETE /api/communities/:id/channels/:cid': (req, _b, _u, params) => {
      const { user, c } = need(req, params.id, 'manage');
      const ch = q.channel.get(Number(params.cid), c.id);
      if (!ch) throw new HttpError(404, 'no_channel');
      if (q.channels.all(c.id).length <= 1) throw bad('last_channel');
      q.deleteChannel.run(ch.id);
      return { community: view(c, user.id) };
    },

    // Channels are readable by anyone who can see the community; `after` polls for new ones.
    'GET /api/communities/:id/channels/:cid/messages': (req, _b, url, params) => {
      const auth = requireAuth(req);
      const c = communityOr404(params.id);
      const ch = q.channel.get(Number(params.cid), c.id);
      if (!ch) throw new HttpError(404, 'no_channel');
      const viewer = { id: auth.user.id, rules: chatRules(auth.user.birthdate) };
      const after = url.searchParams.get('after');
      const rows = after != null ? q.after.all(ch.id, Number(after) || 0) : q.before.all(ch.id, Number(url.searchParams.get('before')) || 2 ** 53).reverse();
      return { messages: rows.map((m) => messageView(m, viewer)) };
    },

    'POST /api/communities/:id/channels/:cid/messages': (req, body, _u, params) => {
      const auth = requireAuth(req);
      const c = communityOr404(params.id);
      const ch = q.channel.get(Number(params.cid), c.id);
      if (!ch) throw new HttpError(404, 'no_channel');
      const m = membership(c.id, auth.user.id);
      if (!m || (m.rank < 255 && !m.perms.has('post')) || m.rank < ch.post_rank) throw new HttpError(403, 'cannot_post');
      const rules = chatRules(auth.user.birthdate);
      if (!rules.chat) throw new HttpError(403, 'chat_age');
      if (!writeLimiter.allow('cmsg:' + auth.user.id)) throw new HttpError(429, 'slow_down');
      const text = String(body.text ?? '').replace(/[\u0000-\u0009\u000b-\u001f\u007f]/g, ' ').trim().slice(0, 1000);
      if (!text) throw bad('empty_message');
      const id = Number(q.insertMessage.run(ch.id, auth.user.id, text, Date.now()).lastInsertRowid);
      const row = q.after.all(ch.id, id - 1)[0];
      return { message: messageView(row, { id: auth.user.id, rules }) };
    },

    // The community's places this viewer may see (members see private ones too).
    'GET /api/communities/:id/places': (req, _b, _u, params) => {
      const { user } = requireAuth(req);
      const c = communityOr404(params.id);
      const lang = pickLang(req);
      return { places: q.places.all(c.id).filter((p) => canSee(p, user)).map((p) => placeView(p, user.id, lang)) };
    },

    'DELETE /api/communities/:id/messages/:mid': (req, _b, _u, params) => {
      const { user } = requireAuth(req);
      const c = communityOr404(params.id);
      const msg = q.message.get(Number(params.mid));
      if (!msg || msg.community_id !== c.id) throw new HttpError(404, 'no_message');
      if (msg.user_id !== user.id) {
        const m = membership(c.id, user.id);
        const author = membership(c.id, msg.user_id);
        if (!m || (m.rank < 255 && !m.perms.has('moderate')) || (author && author.rank >= m.rank)) throw new HttpError(403, 'forbidden');
      }
      q.deleteMessage.run(msg.id);
      return { ok: true };
    },
  };

  return {
    routes,
    membership,
    /** May this user open, save and publish this place (their own, or their community's)? */
    canEditPlace: (row, user) => row.owner_id === user.id || (row.community_id != null && can(row.community_id, user.id, 'places')),
    /** Private community places are visible to the community's members. */
    isMember: (communityId, userId) => !!q.member.get(communityId, userId),
    canMakePlaces: (communityId, userId) => !!q.one.get(communityId) && can(communityId, userId, 'places'),
    card: (id) => {
      const c = q.one.get(id);
      return c ? card(c) : null;
    },
    placesOf: (communityId) => q.places.all(communityId),
    /** Someone's communities with their role there (profiles). */
    of: (userId) => q.mine.all(userId).map((c) => ({ ...card(c), role_name: c.role_name, rank: c.role_rank })),
    /** Communities where this user may make places (for Studio's "publish as"). */
    buildable: (userId) => q.mine.all(userId).filter((c) => can(c.id, userId, 'places')).map(card),
  };
}
