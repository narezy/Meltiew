import { DatabaseSync } from 'node:sqlite';
import fs from 'node:fs';
import path from 'node:path';
import { migrateEconomy } from './economy.js';
import { migrateBadges } from './badges.js';
import { migrateAnimations } from './animations.js';

export function openDb(file) {
  if (file !== ':memory:') fs.mkdirSync(path.dirname(file), { recursive: true });
  const db = new DatabaseSync(file);
  db.exec(`
    PRAGMA journal_mode = WAL;
    PRAGMA foreign_keys = ON;

    CREATE TABLE IF NOT EXISTS users (
      id           INTEGER PRIMARY KEY AUTOINCREMENT,
      username     TEXT NOT NULL UNIQUE COLLATE NOCASE,
      pass_hash    TEXT NOT NULL,
      display_name TEXT NOT NULL,
      bio          TEXT NOT NULL DEFAULT '',
      colors       TEXT NOT NULL DEFAULT '{}',
      hat          TEXT NOT NULL DEFAULT 'none',
      created_at   INTEGER NOT NULL,
      last_seen    INTEGER NOT NULL DEFAULT 0
    );

    CREATE TABLE IF NOT EXISTS sessions (
      token      TEXT PRIMARY KEY,
      user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      created_at INTEGER NOT NULL,
      used_at    INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS sessions_user ON sessions(user_id);

    -- One row per directed request. status: pending | accepted
    CREATE TABLE IF NOT EXISTS friendships (
      from_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      to_id      INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      status     TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      PRIMARY KEY (from_id, to_id)
    );
    CREATE INDEX IF NOT EXISTS friendships_to ON friendships(to_id);

    -- user_id no longer sees blocked_id (chat, requests).
    CREATE TABLE IF NOT EXISTS blocks (
      user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      blocked_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      created_at INTEGER NOT NULL,
      PRIMARY KEY (user_id, blocked_id)
    );

    -- Places are the games on the platform. The playground is seeded below.
    CREATE TABLE IF NOT EXISTS places (
      id              TEXT PRIMARY KEY,
      name            TEXT NOT NULL,
      name_ru         TEXT NOT NULL,
      description     TEXT NOT NULL,
      description_ru  TEXT NOT NULL,
      author_username TEXT NOT NULL,
      cover           TEXT NOT NULL,
      visits          INTEGER NOT NULL DEFAULT 0,
      created_at      INTEGER NOT NULL
    );

    -- Small key/value store for runtime settings (e.g. the minimum app version).
    CREATE TABLE IF NOT EXISTS config (
      key   TEXT PRIMARY KEY,
      value TEXT NOT NULL
    );

    -- Direct messages. A conversation is open between friends or once a message
    -- request was accepted; until then the sender gets exactly one message in.
    CREATE TABLE IF NOT EXISTS messages (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      from_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      to_id      INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      body       TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      read       INTEGER NOT NULL DEFAULT 0
    );
    CREATE INDEX IF NOT EXISTS messages_pair ON messages(from_id, to_id, id);
    CREATE INDEX IF NOT EXISTS messages_to ON messages(to_id, read);

    CREATE TABLE IF NOT EXISTS dm_requests (
      from_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      to_id      INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      status     TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      PRIMARY KEY (from_id, to_id)
    );

    CREATE TABLE IF NOT EXISTS reports (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      reporter_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      target_id   INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      reason      TEXT NOT NULL,
      details     TEXT NOT NULL DEFAULT '',
      created_at  INTEGER NOT NULL,
      resolved    INTEGER NOT NULL DEFAULT 0
    );

    CREATE TABLE IF NOT EXISTS place_votes (
      place_id TEXT NOT NULL REFERENCES places(id) ON DELETE CASCADE,
      user_id  INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      value    INTEGER NOT NULL,
      PRIMARY KEY (place_id, user_id)
    );
  `);
  migrate(db);
  return db;
}

/** Additive migrations for databases created by older versions. */
function migrate(db) {
  const cols = new Set(db.prepare('PRAGMA table_info(users)').all().map((c) => c.name));
  if (!cols.has('render_hash')) db.exec("ALTER TABLE users ADD COLUMN render_hash TEXT NOT NULL DEFAULT ''");
  if (!cols.has('role')) db.exec("ALTER TABLE users ADD COLUMN role TEXT NOT NULL DEFAULT 'user'");
  if (!cols.has('banned')) db.exec('ALTER TABLE users ADD COLUMN banned INTEGER NOT NULL DEFAULT 0');
  if (!cols.has('ban_reason')) db.exec("ALTER TABLE users ADD COLUMN ban_reason TEXT NOT NULL DEFAULT ''");
  if (!cols.has('birthdate')) db.exec("ALTER TABLE users ADD COLUMN birthdate TEXT NOT NULL DEFAULT ''");
  // 0 = the free change after sign-up is still unused; otherwise when it was last changed.
  if (!cols.has('birthdate_changed_at')) db.exec('ALTER TABLE users ADD COLUMN birthdate_changed_at INTEGER NOT NULL DEFAULT 0');
  if (!cols.has('face')) db.exec("ALTER TABLE users ADD COLUMN face TEXT NOT NULL DEFAULT ':D'");
  if (!cols.has('hide_friends')) db.exec('ALTER TABLE users ADD COLUMN hide_friends INTEGER NOT NULL DEFAULT 0');
  if (!cols.has('accessories')) {
    // Several accessories at once; the old single hat becomes the first of them.
    db.exec("ALTER TABLE users ADD COLUMN accessories TEXT NOT NULL DEFAULT '[]'");
    db.exec(`UPDATE users SET accessories = json_array(hat) WHERE hat != 'none' AND hat != ''`);
  }
  const pcols = new Set(db.prepare('PRAGMA table_info(places)').all().map((c) => c.name));
  if (!pcols.has('cover_square')) db.exec("ALTER TABLE places ADD COLUMN cover_square TEXT NOT NULL DEFAULT ''");
  db.prepare(
    `INSERT OR IGNORE INTO places (id, name, name_ru, description, description_ru, author_username, cover, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
  ).run(
    'playground',
    'Playground',
    'Детская площадка',
    'Slides, swings, trampolines, a hedge maze, a duck pond and parkour above the clouds. Hang out with friends!',
    'Горки, качели, батуты, лабиринт, утиный пруд и паркур над облаками. Тусуйся с друзьями!',
    'nrz',
    '/img/cover.png',
    Date.UTC(2026, 8, 25),
  );
  // Runs after the seed insert so fresh databases get the square cover too.
  db.prepare("UPDATE places SET cover_square = '/img/cover_square.png' WHERE id = 'playground' AND cover_square = ''").run();

  // Studio places (made by players). The built-in playground keeps kind = 'builtin'.
  const add = (col, def) => {
    if (!pcols.has(col)) db.exec(`ALTER TABLE places ADD COLUMN ${col} ${def}`);
  };
  add('kind', "TEXT NOT NULL DEFAULT 'builtin'");
  add('owner_id', 'INTEGER NOT NULL DEFAULT 0');
  add('visibility', "TEXT NOT NULL DEFAULT 'public'"); // private | friends | public
  add('i18n', "TEXT NOT NULL DEFAULT '{}'"); // { name: { lang: text }, description: { lang: text } }
  add('version', 'INTEGER NOT NULL DEFAULT 0');
  add('updated_at', 'INTEGER NOT NULL DEFAULT 0');
  add('published_at', 'INTEGER NOT NULL DEFAULT 0');
  add('playtime_ms', 'INTEGER NOT NULL DEFAULT 0');
  add('max_players', 'INTEGER NOT NULL DEFAULT 10');
  add('comments_enabled', 'INTEGER NOT NULL DEFAULT 1');
  add('deleted', 'INTEGER NOT NULL DEFAULT 0');
  db.exec(`
    CREATE TABLE IF NOT EXISTS place_players (
      place_id    TEXT NOT NULL,
      user_id     INTEGER NOT NULL,
      visits      INTEGER NOT NULL DEFAULT 0,
      playtime_ms INTEGER NOT NULL DEFAULT 0,
      first_at    INTEGER NOT NULL,
      last_at     INTEGER NOT NULL,
      PRIMARY KEY (place_id, user_id)
    );
    CREATE TABLE IF NOT EXISTS place_daily (
      place_id    TEXT NOT NULL,
      day         TEXT NOT NULL,
      visits      INTEGER NOT NULL DEFAULT 0,
      playtime_ms INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (place_id, day)
    );
    CREATE TABLE IF NOT EXISTS place_comments (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      place_id   TEXT NOT NULL,
      user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      body       TEXT NOT NULL,
      created_at INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS place_comments_by_place ON place_comments(place_id, id);
    CREATE TABLE IF NOT EXISTS assets (
      id         TEXT PRIMARY KEY,
      owner_id   INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      name       TEXT NOT NULL,
      mime       TEXT NOT NULL,
      size       INTEGER NOT NULL,
      width      INTEGER NOT NULL DEFAULT 0,
      height     INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL
    );
  `);
  // Uploaded assets are images or sounds.
  const acols = new Set(db.prepare('PRAGMA table_info(assets)').all().map((c) => c.name));
  if (!acols.has('kind')) db.exec("ALTER TABLE assets ADD COLUMN kind TEXT NOT NULL DEFAULT 'image'");
  // Reports can be about a player, a place or a comment.
  const rcols = new Set(db.prepare('PRAGMA table_info(reports)').all().map((c) => c.name));
  if (!rcols.has('target_type')) db.exec("ALTER TABLE reports ADD COLUMN target_type TEXT NOT NULL DEFAULT 'user'");
  if (!rcols.has('target_ref')) db.exec("ALTER TABLE reports ADD COLUMN target_ref TEXT NOT NULL DEFAULT ''");
  migrateEconomy(db);
  migrateBadges(db);
  migrateAnimations(db);
}
