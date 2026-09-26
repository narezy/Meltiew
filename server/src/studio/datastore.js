// DataStoreService for studio places: small saved values per place (coins, levels,
// builds...), kept in SQLite. Scripts reach it through the runtime ("ds" operations);
// the answer comes back on the next server step.
export const DS_LIMITS = {
  keyLength: 50,
  storeNameLength: 50,
  valueBytes: 64 * 1024,
  placeBytes: 4 * 1024 * 1024,
  keysPerPlace: 20000,
  // Requests per server per second (a burst of up to 3 seconds is fine).
  perSecond: 20,
};

export function createDataStore(db) {
  const q = {
    get: db.prepare('SELECT value FROM datastore WHERE place_id = ? AND store = ? AND key = ?'),
    set: db.prepare(`INSERT INTO datastore (place_id, store, key, value, updated_at) VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(place_id, store, key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at`),
    del: db.prepare('DELETE FROM datastore WHERE place_id = ? AND store = ? AND key = ?'),
    usage: db.prepare('SELECT COUNT(*) AS n, COALESCE(SUM(LENGTH(value) + LENGTH(key)), 0) AS bytes FROM datastore WHERE place_id = ?'),
    list: db.prepare('SELECT key FROM datastore WHERE place_id = ? AND store = ? AND key > ? ORDER BY key LIMIT ?'),
  };
  const buckets = new Map(); // server id -> { tokens, at }

  function allow(serverId) {
    const now = Date.now();
    const b = buckets.get(serverId) || { tokens: DS_LIMITS.perSecond * 3, at: now };
    b.tokens = Math.min(DS_LIMITS.perSecond * 3, b.tokens + ((now - b.at) / 1000) * DS_LIMITS.perSecond);
    b.at = now;
    buckets.set(serverId, b);
    if (b.tokens < 1) return false;
    b.tokens -= 1;
    return true;
  }

  /** One request from a place's scripts. Returns { ok, value } or { ok: false, err }. */
  function handle(placeId, serverId, op) {
    const store = String(op.store ?? '');
    const key = String(op.key ?? '');
    if (!store || store.length > DS_LIMITS.storeNameLength) return { ok: false, err: 'bad store name' };
    if (op.op !== 'list' && (!key || key.length > DS_LIMITS.keyLength)) return { ok: false, err: `keys are 1 to ${DS_LIMITS.keyLength} characters` };
    if (!allow(serverId)) return { ok: false, err: 'too many DataStore requests, slow down' };
    const read = () => {
      const row = q.get.get(placeId, store, key);
      return row ? JSON.parse(row.value) : null;
    };
    switch (op.op) {
      case 'get':
        return { ok: true, value: read() };
      case 'set': {
        if (op.value === null || op.value === undefined) {
          q.del.run(placeId, store, key);
          return { ok: true, value: null };
        }
        const text = JSON.stringify(op.value);
        if (Buffer.byteLength(text) > DS_LIMITS.valueBytes) return { ok: false, err: `a value can be at most ${DS_LIMITS.valueBytes / 1024} KB` };
        const u = q.usage.get(placeId);
        const old = q.get.get(placeId, store, key);
        if (!old && u.n >= DS_LIMITS.keysPerPlace) return { ok: false, err: `this place already has ${DS_LIMITS.keysPerPlace} saved keys` };
        if (u.bytes - (old ? old.value.length + key.length : 0) + text.length + key.length > DS_LIMITS.placeBytes) {
          return { ok: false, err: `this place's saved data is full (${DS_LIMITS.placeBytes / 1024 / 1024} MB)` };
        }
        q.set.run(placeId, store, key, text, Date.now());
        return { ok: true, value: op.value };
      }
      case 'inc': {
        const cur = read();
        const base = typeof cur === 'number' ? cur : cur === null ? 0 : NaN;
        if (Number.isNaN(base)) return { ok: false, err: 'IncrementAsync needs a number stored at that key' };
        const value = base + (Number(op.delta) || 0);
        q.set.run(placeId, store, key, JSON.stringify(value), Date.now());
        return { ok: true, value };
      }
      case 'remove': {
        const value = read();
        q.del.run(placeId, store, key);
        return { ok: true, value };
      }
      case 'list': {
        const rows = q.list.all(placeId, store, String(op.after ?? ''), Math.max(1, Math.min(100, Number(op.limit) || 50)));
        return { ok: true, value: rows.map((r) => r.key) };
      }
      default:
        return { ok: false, err: 'unknown DataStore request' };
    }
  }

  return { handle, usage: (placeId) => q.usage.get(placeId), forget: (serverId) => buckets.delete(serverId) };
}
