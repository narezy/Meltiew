// Custom animations made in Studio's animator. Each is saved with a number and
// used as "anim://<id>" by scripts (Humanoid:PlayAnimation, Rig.Animation) and by
// a place's emote wheel. Anyone may play any animation; only its maker edits it.
//
// Data: { length, loop, keys: { Bone: [[t, rx, ry, rz], ...] }, moves: { Bone: [[t, x, y, z], ...] } }
// Bones are Melly's: Torso, Head, ArmL, ArmR, LegL, LegR. Rotations in degrees,
// moves in studs from where the part rests. (Older data has the torso's moves as `pos`.)

export const BONES = ['Torso', 'Head', 'ArmL', 'ArmR', 'LegL', 'LegR'];
export const MAX_ANIMATIONS = 200;
const MAX_KEYS = 240;

export function migrateAnimations(db) {
  db.exec(`
    CREATE TABLE IF NOT EXISTS animations (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      owner_id   INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      name       TEXT NOT NULL,
      data       TEXT NOT NULL,
      length     REAL NOT NULL,
      loop       INTEGER NOT NULL DEFAULT 0,
      deleted    INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS animations_owner ON animations(owner_id);
  `);
}

const num = (v, lo, hi) => {
  const n = Number(v);
  if (!Number.isFinite(n)) return null;
  return Math.min(hi, Math.max(lo, Math.round(n * 1000) / 1000));
};

/** Checks and tidies animation data; throws `bad` on anything malformed. */
export function cleanAnimation(data, bad) {
  if (!data || typeof data !== 'object') throw bad('bad_animation');
  const length = num(data.length, 0.1, 30);
  if (length == null) throw bad('bad_animation');
  const keys = {};
  let total = 0;
  const track = (list, lo, hi) => {
    if (!Array.isArray(list)) throw bad('bad_animation');
    const out = [];
    for (const k of list) {
      if (!Array.isArray(k) || k.length !== 4) throw bad('bad_animation');
      const t = num(k[0], 0, length);
      const vals = k.slice(1).map((v) => num(v, lo, hi));
      if (t == null || vals.includes(null)) throw bad('bad_animation');
      out.push([t, ...vals]);
    }
    total += out.length;
    if (out.length > MAX_KEYS) throw bad('bad_animation');
    return out.sort((a, b) => a[0] - b[0]);
  };
  for (const [bone, list] of Object.entries(data.keys || {})) {
    if (!BONES.includes(bone)) throw bad('bad_animation');
    keys[bone] = track(list, -720, 720);
  }
  const moves = {};
  for (const [bone, list] of Object.entries(data.moves || {})) {
    if (!BONES.includes(bone)) throw bad('bad_animation');
    moves[bone] = track(list, -6, 6);
  }
  if (Array.isArray(data.pos) && data.pos.length && !moves.Torso) moves.Torso = track(data.pos, -6, 6);
  if (total === 0) throw bad('empty_animation');
  return { length, loop: data.loop === true, keys, moves };
}

export function createAnimations({ db, HttpError, bad, cleanText, requireAuth, writeLimiter }) {
  const q = {
    mine: db.prepare('SELECT id, name, length, loop, updated_at FROM animations WHERE owner_id = ? AND deleted = 0 ORDER BY updated_at DESC'),
    count: db.prepare('SELECT COUNT(*) AS n FROM animations WHERE owner_id = ? AND deleted = 0'),
    one: db.prepare('SELECT a.*, u.username FROM animations a JOIN users u ON u.id = a.owner_id WHERE a.id = ? AND a.deleted = 0'),
    insert: db.prepare('INSERT INTO animations (owner_id, name, data, length, loop, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)'),
    update: db.prepare('UPDATE animations SET name = ?, data = ?, length = ?, loop = ?, updated_at = ? WHERE id = ?'),
    remove: db.prepare('UPDATE animations SET deleted = 1 WHERE id = ?'),
  };
  const view = (a, withData) => ({
    id: a.id,
    ref: `anim://${a.id}`,
    name: a.name,
    length: a.length,
    loop: !!a.loop,
    by: a.username,
    ...(withData ? { data: JSON.parse(a.data) } : {}),
  });

  function mineOrThrow(req, id) {
    const { user } = requireAuth(req);
    const a = q.one.get(Number(id));
    if (!a) throw new HttpError(404, 'no_animation');
    if (a.owner_id !== user.id) throw new HttpError(403, 'forbidden');
    return { user, a };
  }

  const routes = {
    'GET /api/animations': (req) => {
      const { user } = requireAuth(req);
      return { animations: q.mine.all(user.id).map((a) => ({ ...view(a, false), by: user.username })), max: MAX_ANIMATIONS };
    },

    // Public: any place can play any animation.
    'GET /api/animations/:id': (_req, _b, _u, params) => {
      const a = q.one.get(Number(params.id));
      if (!a) throw new HttpError(404, 'no_animation');
      return { animation: view(a, true) };
    },

    'POST /api/animations': (req, body) => {
      const { user } = requireAuth(req);
      if (!writeLimiter.allow('anim:' + user.id)) throw new HttpError(429, 'slow_down');
      if (q.count.get(user.id).n >= MAX_ANIMATIONS) throw bad('too_many_animations');
      const data = cleanAnimation(body.data, bad);
      const name = cleanText(body.name, 50) || 'Animation';
      const now = Date.now();
      const info = q.insert.run(user.id, name, JSON.stringify(data), data.length, data.loop ? 1 : 0, now, now);
      return { animation: view(q.one.get(Number(info.lastInsertRowid)), true) };
    },

    'PUT /api/animations/:id': (req, body, _u, params) => {
      const { a } = mineOrThrow(req, params.id);
      const data = cleanAnimation(body.data, bad);
      const name = body.name !== undefined ? cleanText(body.name, 50) || a.name : a.name;
      q.update.run(name, JSON.stringify(data), data.length, data.loop ? 1 : 0, Date.now(), a.id);
      return { animation: view(q.one.get(a.id), true) };
    },

    'DELETE /api/animations/:id': (req, _b, _u, params) => {
      const { a } = mineOrThrow(req, params.id);
      q.remove.run(a.id);
      return { ok: true };
    },
  };
  return { routes };
}
