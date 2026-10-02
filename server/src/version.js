// App version gate: clients older than the minimum are turned away with 426.
// The minimum defaults to the release this server ships with and can be raised
// at runtime from the admin panel (stored in the config table).
export const LATEST_CLIENT = '1.9.0';
export const DOWNLOAD_PAGE = 'https://meltiew.narez.xyz/download';

// Every published app is exported with this Godot. A different engine in the app's
// User-Agent means someone built their own (with cheats in it).
export const CLIENT_ENGINE = '4.7.2';

function officialEngine(userAgent) {
  const m = /^GodotEngine\/(\d+\.\d+(?:\.\d+)?)/.exec(String(userAgent));
  return !m || m[1] === CLIENT_ENGINE;
}

export function compareVersions(a, b) {
  const pa = String(a || '0').split('.').map((n) => parseInt(n, 10) || 0);
  const pb = String(b || '0').split('.').map((n) => parseInt(n, 10) || 0);
  for (let i = 0; i < 3; i++) {
    if ((pa[i] || 0) !== (pb[i] || 0)) return (pa[i] || 0) < (pb[i] || 0) ? -1 : 1;
  }
  return 0;
}

export function createVersionGate(db) {
  const get = db.prepare("SELECT value FROM config WHERE key = 'min_client'");
  const set = db.prepare("INSERT INTO config (key, value) VALUES ('min_client', ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value");
  const stored = get.get()?.value;
  // A newly deployed server never accepts clients older than itself.
  if (!stored || compareVersions(stored, LATEST_CLIENT) < 0) set.run(LATEST_CLIENT);
  return {
    min: () => get.get()?.value || LATEST_CLIENT,
    setMin: (v) => set.run(v),
    /**
     * Only the game app is gated. It is recognised by X-Client: app or by Godot's
     * User-Agent (old builds sent neither version nor X-Client). Browsers always pass,
     * even with a stale cached site script.
     */
    allows(client, version, userAgent = '') {
      if (client === 'web') return true;
      const isApp = client === 'app' || /^GodotEngine\//.test(String(userAgent));
      if (!isApp) return true;
      // Newer than the newest release: a build nobody published (a modified client).
      return compareVersions(version, this.min()) >= 0 && compareVersions(version, LATEST_CLIENT) <= 0;
    },
    /**
     * The HTTP API stays open to every app that reports its version, so an old
     * app never loses unsaved work in Studio; it's asked to update when it joins
     * a game instead. Only builds too old to say their version are turned away.
     */
    allowsHttp(client, version, userAgent = '') {
      if (client === 'web') return true;
      const isApp = client === 'app' || /^GodotEngine\//.test(String(userAgent));
      return !isApp || (!!version && compareVersions(version, LATEST_CLIENT) <= 0 && officialEngine(userAgent));
    },
  };
}
