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
  `);
  migrate(db);
  return db;
}

/** Additive migrations for databases created by older versions. */
function migrate(db) {
  const cols = new Set(db.prepare('PRAGMA table_info(users)').all().map((c) => c.name));
  if (!cols.has('render_hash')) db.exec("ALTER TABLE users ADD COLUMN render_hash TEXT NOT NULL DEFAULT ''");
}
