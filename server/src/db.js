import { DatabaseSync } from 'node:sqlite';
import fs from 'node:fs';
import path from 'node:path';

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
  if (!cols.has('face')) db.exec("ALTER TABLE users ADD COLUMN face TEXT NOT NULL DEFAULT ':D'");
  if (!cols.has('hide_friends')) db.exec('ALTER TABLE users ADD COLUMN hide_friends INTEGER NOT NULL DEFAULT 0');
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
}
