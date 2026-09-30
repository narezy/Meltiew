import crypto from 'node:crypto';
import { parseColors, BODY_PARTS, COLOR_RE } from './colors.js';
import { wornOf, legacyHat, accessoryExists, cleanWorn } from './accessories.js';
import { msg } from './i18n.js';
import { MoveGuard, PLAYGROUND_LIMITS } from './anticheat.js';
import { Occluders, eyes, canSee } from './occlusion.js';
import { tooLoud } from './voiceguard.js';
import fs from 'node:fs';

// The playground's solid shapes (client/tools/export_playground.tscn writes them), so
// the fly check knows what players stand on there too.
const PLAYGROUND_BOXES = JSON.parse(fs.readFileSync(new URL('./playground_solids.json', import.meta.url), 'utf8'));
const PLAYGROUND_SOLIDS = new Occluders(PLAYGROUND_BOXES, 2);
// What hides players there (the anti-wallhack): its still blocks big in two directions.
const PLAYGROUND_OCC = new Occluders(
  PLAYGROUND_BOXES.filter((b) => !(b[15] & 4) && [b[3], b[4], b[5]].sort((x, y) => x - y)[1] * 2 >= 1.5),
  2,
);
// Its trampolines: taking off from around them, a bounce goes up to PLAYGROUND_LIMITS.jump.
const TRAMPOLINES = [22, 20];
const TRAMPOLINE_RADIUS = 11;
const TRAMPOLINE_PADS = 8.5; // the mat they stand on
const PLAYGROUND_JUMP = 8.2;
import { chatRules, FACES } from './age.js';
import { filterText, tameMarks } from './filter.js';
import { PlaceVM } from './studio/vm.js';
import { createOutbox, splitOps, splitSnapshot, CHUNK_BYTES } from './outbox.js';

export const MAX_PLAYERS = 10;
// Studio places can take more (the owner sets it; new places start at 10).
export const MAX_PLACE_PLAYERS = 30;
export const GAMES = {
  playground: {
    id: 'playground',
    name: 'Playground',
    name_ru: 'Детская площадка',
    description: 'Slides, swings, trampolines, a maze and parkour above the clouds. Hang out with friends!',
    description_ru: 'Горки, качели, батуты, лабиринт и паркур над облаками. Тусуйся с друзьями!',
  },
};

const TICK_HZ = 20;
// Studio place servers: how many events a player may send per tick, and when a
// server whose scripts keep crashing the runtime is shut down.
const MAX_EVENTS_PER_TICK = 40;
const MAX_VM_FAILURES = 20;
const LOG_LINES = 200;
const TOOL_EVENTS = new Set(['equip', 'unequip', 'activate', 'deactivate', 'drop']);
const EMPTY_SERVER_TTL_MS = 30_000;
// After the creator saves a new version, live servers wait this long (more saves
// restart the wait) and then move everyone to a fresh server running it.
const MIGRATE_DELAY_MS = 4000;
// How far from the origin a player may be. Places put maps far from the lobby
// (Meltopia's are 500-700 studs out), so the same room as physics parts.
const WORLD_LIMIT = 5000;
// Anti-wallhack: how often the place's blocks and who-sees-whom are worked out, and
// how long someone stays sent after they were last in sight.
const GEOMETRY_EVERY_MS = 1000;
const VISIBILITY_EVERY_MS = 150;
const VISIBLE_HOLD_MS = 700;
// How far a voice carries (studs).
const VOICE_RANGE = 45;
// Physics parts (unanchored): one app simulates each, the rest follow its reports.
const PHYS_MAX_BATCH = 64;
const PHYS_CLAIM_RANGE = 12; // how close you must be to take a part over
const PHYS_HANDOFF_MARGIN = 3; // someone must be this much closer to take it from its owner
const PHYS_LIMIT = 5000;
export const ANIMS = new Set(['idle', 'walk', 'run', 'jump', 'fall', 'wave', 'dance', 'cheer', 'sit', 'clap', 'laugh', 'dead', 'climb', 'punch', 'throw', 'hug', 'hugging']);
export const HEART_COOLDOWN_MS = 2500;
export const EMOTE_COOLDOWN_MS = 800;
export const EMOTES = new Set(['wave', 'heart', 'dance', 'cheer', 'sit', 'clap', 'laugh', 'hug']);
const SERVER_NAMES = [
  ['Sunny', 'Солнечная'],
  ['Vanilla', 'Ванильная'],
  ['Fluffy', 'Пушистая'],
  ['Happy', 'Весёлая'],
  ['Cozy', 'Уютная'],
  ['Minty', 'Мятная'],
  ['Starry', 'Звёздная'],
  ['Cloudy', 'Облачная'],
  ['Caramel', 'Карамельная'],
  ['Lavender', 'Лавандовая'],
];

function clothesOf(u) {
  try {
    const ids = JSON.parse(u.clothes || '[]');
    return Array.isArray(ids) ? ids.filter(Number.isSafeInteger).slice(0, 5) : [];
  } catch {
    return [];
  }
}

function publicUser(u) {
  return {
    id: u.id,
    username: u.username,
    display_name: u.display_name,
    colors: parseColors(u.colors),
    hat: legacyHat(wornOf(u)),
    accessories: wornOf(u),
    clothes: clothesOf(u),
    role: u.role || 'user',
    face: u.face || ':D',
  };
}

/** The platform's owner (nrz): the only one with the in-game admin panel. */
export function isOwner(user) {
  return user?.role === 'owner';
}

/** Does a LocalScript in this place make parts (a world built in each app, like BlockCraft's)? */
function buildsWorldInApp(melt) {
  const walk = (n) => {
    if (!n || typeof n !== 'object') return false;
    if (n.c === 'LocalScript' && /Instance\.new\(\s*["'](Part|Seat|SpawnLocation)["']/.test(String(n.p?.Source || ''))) return true;
    return (n.k || []).some(walk);
  };
  return walk(melt?.tree);
}

function dist(a, b) {
  return Math.hypot(a[0] - b[0], a[1] - b[1], a[2] - b[2]);
}

function meltHash(melt) {
  return crypto.createHash('sha1').update(JSON.stringify(melt)).digest('hex');
}

/** A place's Appearance for a player, checked: known colors, face and accessories. */
function cleanLook(raw) {
  if (!raw || typeof raw !== 'object' || raw.reset) return null;
  const colors = {};
  for (const part of BODY_PARTS) if (COLOR_RE.test(raw.colors?.[part])) colors[part] = raw.colors[part];
  const list = Array.isArray(raw.accessories) ? raw.accessories.map(String).filter(accessoryExists) : [];
  const keep = raw.keep || {};
  return {
    colors,
    face: FACES.includes(raw.face) ? raw.face : ':D',
    accessories: cleanWorn(list) || [],
    keep: { colors: keep.colors === true, face: keep.face === true, accessories: keep.accessories === true },
  };
}

/** Someone's public look with a place's Appearance on top (their real avatar stays as it is). */
function withLook(u, look) {
  if (!look) return u;
  const out = { ...u };
  if (!look.keep.colors) out.colors = { ...u.colors, ...look.colors };
  if (!look.keep.face) out.face = look.face;
  if (!look.keep.accessories) {
    out.accessories = look.accessories;
    out.hat = legacyHat(look.accessories);
  }
  return out;
}

function finite(n, lim) {
  const v = Number(n);
  if (!Number.isFinite(v)) return 0;
  return Math.max(-lim, Math.min(lim, v));
}

export class GameHub {
  /**
   * @param {object} opts
   * @param {(userId:number)=>Set<number>} [opts.loadBlocks] ids this user has blocked
   */
  /**
   * @param {object} [opts.places] studio places: { load(id) -> melt, row(id), canJoin(user, id), visit(id, userId), playtime(id, userId, ms) }
   */
  constructor({ log = () => {}, loadBlocks = () => new Set(), loadFriends = () => new Set(), onJoin = () => {}, places = null, onCheat = () => {} } = {}) {
    // Movement checks are off unless MELTIEW_ANTICHEAT=1: they kept snapping honest
    // players back after a place teleported them.
    this.anticheat = process.env.MELTIEW_ANTICHEAT === '1';
    this.servers = new Map(); // id -> server
    this.byUser = new Map(); // userId -> { server, player, conn }
    this.log = log;
    this.loadBlocks = loadBlocks;
    this.loadFriends = loadFriends;
    this.onJoin = onJoin;
    this.places = places;
    this.onCheat = onCheat;
    this.timer = setInterval(() => this.tick(), 1000 / TICK_HZ);
    this.timer.unref?.();
    this.nameCounter = 0;
  }

  stop() {
    clearInterval(this.timer);
    for (const s of this.servers.values()) {
      for (const p of s.players.values()) p.conn.out.close(1001, 'server shutdown');
      s.vm?.close();
    }
  }

  isStudio(game) {
    return !GAMES[game] && !!this.places?.row(game);
  }

  /** A server for a studio place: its own sandboxed Luau VM running the place's scripts. */
  async createPlaceServer(placeId) {
    const row = this.places.row(placeId);
    const melt = this.places.load(placeId);
    if (!row || !melt) throw new Error('no place');
    const vm = await PlaceVM.create();
    const hash = meltHash(melt);
    let id;
    do id = crypto.randomBytes(3).toString('hex'); while (this.servers.has(id));
    this.nameCounter += 1;
    const starter = (melt.tree.k || []).find((n) => n.c === 'StarterPlayer')?.p || {};
    const server = {
      id,
      game: placeId,
      kind: 'studio',
      name: `Server #${this.nameCounter}`,
      name_ru: `Сервер #${this.nameCounter}`,
      players: new Map(),
      createdAt: Date.now(),
      emptySince: Date.now(),
      maxPlayers: Math.max(1, Math.min(MAX_PLACE_PLAYERS, row.max_players || MAX_PLAYERS)),
      ownerId: row.owner_id,
      chat: starter.ChatEnabled !== false,
      emotes: starter.EmotesEnabled !== false,
      strings: melt.strings || {},
      vm,
      inbox: [],
      shared: [],
      targeted: new Map(),
      kicks: [],
      logs: [],
      failures: 0,
      lastStep: Date.now(),
      hash, // which version of the place this server runs
      retired: false, // replaced by a server with the newer version
      migrateAt: 0,
      phys: new Map(), // part id -> { owner, p, at }
      physOut: [], // updates to relay this tick
      physOwn: {}, // ownership changes to announce this tick
      physVm: new Map(), // latest update per part, for the scripts
      physAt: 0,
      // The place builds solid parts in players' apps (a LocalScript's Instance.new):
      // the server can't know what they stand on, so it doesn't judge flying there.
      clientWorld: buildsWorldInApp(melt),
    };
    this.servers.set(id, server);
    this.routeOps(server, vm.init({ role: 'server', place: melt, seed: crypto.randomInt(1 << 30) }));
    this.routeOps(server, vm.start());
    this.log(`place server ${id} created for ${placeId}`);
    return server;
  }

  /** Sorts what a place's VM produced: replication for everyone, remotes for someone, logs. */
  routeOps(server, ops) {
    for (const op of ops) {
      switch (op.o) {
        case 'new':
        case 'set':
        case 'del':
        case 'parent':
        case 'sound':
        case 'sound_stop':
        case 'rig_anim':
        case 'mesh':
        case 'meshv':
        case 'particles':
          server.shared.push(op);
          break;
        case 'fire':
          if (op.to === 'all') server.shared.push({ o: 'fire', id: op.id, args: op.args });
          else this.target(server, op.to, { o: 'fire', id: op.id, args: op.args });
          break;
        case 'ret':
          this.target(server, op.to, { o: 'ret', rid: op.rid, ok: op.ok, values: op.values });
          break;
        case 'spawn': {
          // The place moved this player (spawn, respawn, Teleport): that jump is legit.
          const who = server.players.get(Number(op.to));
          const v = op.pos?.$v3;
          if (who && Array.isArray(v)) who.guard.teleportTo(v.map(Number));
          this.target(server, op.to, { o: 'spawn', pos: op.pos });
          break;
        }
        case 'glide': {
          // Player:Glide: the app flies there itself; the movement check expects the trip.
          const who = server.players.get(Number(op.to));
          const v = op.pos?.$v3;
          const t = Math.max(0.05, Math.min(30, Number(op.t) || 1));
          if (!who || !Array.isArray(v)) break;
          who.guard.glideTo(who.p, v.map(Number), t * 1000);
          this.target(server, op.to, { o: 'glide', pos: op.pos, t });
          break;
        }
        case 'kick':
          server.kicks.push(op);
          break;
        case 'badge': {
          // A script awards one of this place's badges (other places' ids are refused).
          const uid = Number(op.to);
          if (!server.players.has(uid)) break;
          const res = this.badges?.award(server.game, uid, op.id);
          if (res?.ok && res.fresh) {
            const b = res.badge;
            this.byUser.get(uid)?.conn.send({ t: 'badge', badge: { id: b.id, name: b.name, description: b.description, image: this.badges.imageUrl(b) } });
            this.target(server, uid, { o: 'badge_got', id: b.id });
          }
          break;
        }
        case 'look': {
          // Appearance from a script: this player looks like that for everyone here, in this place only.
          const who = server.players.get(Number(op.to));
          if (!who) break;
          who.look = cleanLook(op.look);
          who.user = withLook(publicUser(who.conn.user), who.look);
          this.broadcast(server, { t: 'look', player: who.user });
          break;
        }
        case 'ulook': {
          // Players:GetUserAppearanceAsync: someone's own look by username (answered like a DataStore call).
          const look = this.userLook?.(String(op.name || '').slice(0, 40));
          server.inbox.push({ e: 'ds_ret', rid: op.rid, ok: !!look, value: look || null, err: look ? '' : 'no player with that name' });
          break;
        }
        case 'sit':
          // Seat:Sit from a script: that player's app sits them down.
          this.target(server, op.to, { o: 'sit', id: String(op.id || '') });
          break;
        case 'anim':
          // A script animates a player's character: their app plays it (everyone sees it through their state).
          this.target(server, op.to, { o: 'anim', anim: String(op.anim || '') });
          break;
        case 'prompt_pass':
          // A script offers a gamepass: that player's app shows the purchase dialog.
          this.target(server, op.to, { o: 'prompt_pass', id: op.id });
          break;
        case 'ds': {
          // DataStore: answered on the next step (scripts wait for it).
          const res = this.places?.datastore ? this.places.datastore(server.game, server.id, op) : { ok: false, err: 'DataStore is not available' };
          server.inbox.push({ e: 'ds_ret', rid: op.rid, ok: res.ok, value: res.value ?? null, err: res.err || '' });
          break;
        }
        case 'print': {
          const line = { level: op.level, msg: String(op.msg).slice(0, 2000), src: op.src || '', at: Date.now() };
          server.logs.push(line);
          if (server.logs.length > LOG_LINES) server.logs.shift();
          // The place's creator sees the server console while playing.
          if (server.players.has(server.ownerId)) this.target(server, server.ownerId, { o: 'print', ...line, server: true });
          break;
        }
        default:
      }
    }
  }

  target(server, userId, op) {
    const list = server.targeted.get(userId) || [];
    list.push(op);
    server.targeted.set(userId, list);
  }

  flushPlace(server) {
    if (!server.shared.length && !server.targeted.size) return;
    const shared = server.shared;
    for (const [id, p] of server.players) {
      const own = server.targeted.get(id);
      const o = own ? shared.concat(own) : shared;
      if (o.length) p.conn.sendOps(o);
    }
    server.shared = [];
    server.targeted = new Map();
  }

  stepPlace(server, now) {
    const dt = Math.min(0.25, (now - server.lastStep) / 1000);
    server.lastStep = now;
    try {
      // Where everyone is first, then what they did: a shot is judged from where the
      // shooter stands now, not a tick ago.
      const events = [];
      for (const p of server.players.values()) {
        p.events = 0;
        if (p.posDirty) {
          p.posDirty = false;
          events.push({ e: 'pos', userId: p.user.id, p: { $v3: p.p } });
        }
      }
      events.push(...server.inbox);
      server.inbox = [];
      if (events.length) this.routeOps(server, server.vm.dispatch(events));
      this.routeOps(server, server.vm.step(dt));
      if (!server.limitsAt || now - server.limitsAt > 250) {
        server.limitsAt = now;
        server.limits = server.vm.limits();
      }
      if (this.anticheat && (!server.occAt || now - server.occAt > GEOMETRY_EVERY_MS)) {
        server.occAt = now;
        const geo = server.vm.geometry();
        server.occ = new Occluders(geo, 1);
        server.solids = new Occluders(geo, 2);
      }
    } catch (err) {
      server.failures += 1;
      this.log(`place server ${server.id} runtime error: ${err.message}`);
      if (server.failures > MAX_VM_FAILURES) {
        this.log(`place server ${server.id} closed after repeated runtime errors`);
        this.closeServer(server.id);
        return;
      }
    }
    for (const k of server.kicks.splice(0)) {
      const p = server.players.get(Number(k.to));
      if (p) this.kick(p.user.id, 'place', k.msg);
    }
    this.flushPlace(server);
  }

  /** Where an app's physics parts went. Only the part's owner (or a first claimant) counts. */
  physIn(conn, m) {
    const server = conn.server;
    if (!server?.vm || !conn.player || !Array.isArray(m.u)) return;
    const uid = conn.user.id;
    const now = Date.now();
    for (const raw of m.u.slice(0, PHYS_MAX_BATCH)) {
      if (!Array.isArray(raw) || raw.length < 7) continue;
      const id = String(raw[0]).slice(0, 20);
      const nums = raw.slice(1, 10).map((v) => finite(v, PHYS_LIMIT));
      let e = server.phys.get(id);
      if (!e) {
        e = { owner: uid, p: nums.slice(0, 3), at: now };
        server.phys.set(id, e);
        server.physOwn[id] = uid;
      } else if (e.owner !== uid) continue;
      e.p = nums.slice(0, 3);
      e.at = now;
      const u = [id, ...nums.map((v) => Math.round(v * 1000) / 1000)];
      server.physOut.push(u);
      server.physVm.set(id, u);
    }
  }

  /** An app bumped into a part someone else simulates: hand it over if it's really closer. */
  physClaim(conn, m) {
    const server = conn.server;
    if (!server?.vm || !conn.player) return;
    const id = String(m.id ?? '').slice(0, 20);
    const e = server.phys.get(id);
    if (!e || e.owner === conn.user.id) return;
    const mine = dist(conn.player.p, e.p);
    if (mine > PHYS_CLAIM_RANGE) return;
    const owner = server.players.get(e.owner);
    if (owner && Date.now() - e.at < 1000 && dist(owner.p, e.p) < mine) return;
    e.owner = conn.user.id;
    server.physOwn[id] = e.owner;
  }

  /** Once a second: each part goes to whoever is clearly nearest; relays and announces the rest. */
  stepPhys(server, now) {
    if (now - server.physAt > 1000) {
      server.physAt = now;
      for (const [id, e] of server.phys) {
        const cur = server.players.get(e.owner);
        let best = null;
        let bestD = Infinity;
        for (const p of server.players.values()) {
          const d = dist(p.p, e.p);
          if (d < bestD) {
            bestD = d;
            best = p;
          }
        }
        if (!best) continue;
        if (!cur || (best !== cur && bestD + PHYS_HANDOFF_MARGIN < dist(cur.p, e.p))) {
          e.owner = best.user.id;
          server.physOwn[id] = e.owner;
        }
      }
    }
    if (server.physOut.length) {
      this.broadcast(server, { t: 'phys', u: server.physOut });
      server.physOut = [];
    }
    if (Object.keys(server.physOwn).length) {
      this.broadcast(server, { t: 'phys_own', o: server.physOwn });
      server.physOwn = {};
    }
    // Scripts get the latest positions a few times a second.
    if (server.physVm.size && (!server.physVmAt || now - server.physVmAt > 250)) {
      server.physVmAt = now;
      server.inbox.push({ e: 'phys', u: [...server.physVm.values()] });
      server.physVm.clear();
    }
  }

  /** The creator saved the place: servers running an older version move everyone soon. */
  placeUpdated(placeId) {
    const melt = this.places?.load(placeId);
    if (!melt) return;
    const hash = meltHash(melt);
    for (const s of this.servers.values()) {
      if (s.game !== placeId || !s.vm || s.retired || s.hash === hash) continue;
      if (s.players.size === 0) {
        s.retired = true; // nobody to move: just never hand it out again
        continue;
      }
      s.migrateAt = Date.now() + MIGRATE_DELAY_MS;
    }
  }

  /** Starts a server with the place's newest version and sends this server's players to it. */
  async migrate(server) {
    server.migrateAt = 0;
    server.retired = true;
    let fresh;
    try {
      fresh = await this.createPlaceServer(server.game);
    } catch (err) {
      this.log(`migrate ${server.id} failed: ${err.message}`);
      return;
    }
    fresh.maxPlayers = Math.max(fresh.maxPlayers, server.players.size);
    this.log(`place ${server.game} updated: moving ${server.players.size} from ${server.id} to ${fresh.id}`);
    for (const p of server.players.values()) p.conn.send({ t: 'rejoin', server: fresh.id, m: msg('place_updated', p.conn.lang) });
  }

  /** Closes every server of a studio place (it was deleted or made private). */
  closePlace(placeId) {
    for (const s of [...this.servers.values()]) if (s.game === placeId) this.closeServer(s.id);
  }

  createServer(game = 'playground') {
    if (!GAMES[game]) throw new Error('unknown game');
    let id;
    do id = crypto.randomBytes(3).toString('hex'); while (this.servers.has(id));
    this.nameCounter += 1;
    const [en, ru] = SERVER_NAMES[Math.floor(Math.random() * SERVER_NAMES.length)];
    const server = {
      id,
      game,
      name: `${en} Playground #${this.nameCounter}`,
      name_ru: `${ru} площадка #${this.nameCounter}`,
      players: new Map(),
      createdAt: Date.now(),
      emptySince: Date.now(),
    };
    this.servers.set(id, server);
    this.log(`server ${id} created (${server.name})`);
    return server;
  }

  listServers(game = 'playground') {
    return [...this.servers.values()]
      .filter((s) => s.game === game && !s.retired)
      .map((s) => this.describe(s))
      .sort((a, b) => b.players - a.players || a.created_at - b.created_at);
  }

  describe(s) {
    return {
      id: s.id,
      game: s.game,
      name: s.name,
      name_ru: s.name_ru,
      players: s.players.size,
      max_players: s.maxPlayers || MAX_PLAYERS,
      created_at: s.createdAt,
      player_ids: [...s.players.keys()],
    };
  }

  hasServer(id) {
    return this.servers.has(String(id));
  }

  gameOf(serverId) {
    return this.servers.get(String(serverId))?.game || null;
  }

  playerCount(game) {
    let n = 0;
    for (const s of this.servers.values()) if (s.game === game) n += s.players.size;
    return n;
  }

  whereIs(userId) {
    const entry = this.byUser.get(userId);
    if (!entry) return null;
    const s = entry.server;
    return { server_id: s.id, game: s.game, server_name: s.name, server_name_ru: s.name_ru };
  }

  /**
   * Quick play: the server with the most of your friends (and a free slot),
   * otherwise the fullest server with room, otherwise a new one.
   */
  pickServer(game, friendIds = new Set()) {
    let best = null;
    let bestScore = -1;
    for (const s of this.servers.values()) {
      if (s.game !== game || s.retired || s.players.size >= (s.maxPlayers || MAX_PLAYERS)) continue;
      let friends = 0;
      for (const id of s.players.keys()) if (friendIds.has(id)) friends += 1;
      const score = friends * 100 + s.players.size;
      if (score > bestScore) {
        best = s;
        bestScore = score;
      }
    }
    return best;
  }

  /** Called for every authenticated websocket. */
  attach(ws, user, lang = 'en', caps = {}) {
    const conn = {
      ws,
      user,
      lang,
      player: null,
      server: null,
      lastChat: 0,
      chatBurst: 0,
      blocks: this.loadBlocks(user.id),
      rules: chatRules(user.birthdate),
      luau: caps.luau === true, // the app can run place scripts (64-bit builds)
      out: createOutbox(ws, caps.buffer),
    };
    conn.send = (m) => conn.out.send(JSON.stringify(m));
    conn.sendRaw = (data) => conn.out.send(data);
    // Replication, cut to fit the app's receive buffer.
    conn.sendOps = (ops) => {
      for (const o of splitOps(ops)) conn.send({ t: 'r', o });
    };

    ws.on('message', (raw) => {
      let m;
      try {
        m = JSON.parse(raw.toString());
      } catch {
        return;
      }
      if (!m || typeof m !== 'object') return;
      try {
        this.handle(conn, m);
      } catch (err) {
        this.log(`ws handler error: ${err.stack || err}`);
      }
    });
    ws.on('close', () => this.leave(conn));
    ws.on('error', () => {});
    conn.send({ t: 'hello', you: publicUser(user) });
  }

  handle(conn, m) {
    switch (m.t) {
      case 'join':
        return this.join(conn, m).catch((err) => {
          this.log(`join failed: ${err.stack || err}`);
          conn.send({ t: 'error', code: 'not_found', m: msg('no_place', conn.lang) });
        });
      // Studio places: remote events, touches, clicks from the player's app.
      case 'remote':
      case 'invoke':
      case 'touch':
      case 'click':
      case 'tool':
      case 'seat':
      case 'prompt':
        return this.placeEvent(conn, m);
      case 'state':
        return this.state(conn, m);
      case 'chat':
        return this.chat(conn, m);
      case 'hug':
        return this.hug(conn, m);
      case 'voice':
        return this.voice(conn, m);
      case 'emote':
        if (conn.server && conn.player && EMOTES.has(m.e) && conn.server.emotes !== false) {
          // Spamming (hearts especially) floods everyone's screen: one per cooldown.
          const now = Date.now();
          const wait = m.e === 'heart' ? HEART_COOLDOWN_MS : EMOTE_COOLDOWN_MS;
          if (now - (conn.player.emotesAt[m.e] || 0) < wait) return;
          conn.player.emotesAt[m.e] = now;
          this.economy?.progress(conn.user.id, 'emote', 1);
          this.broadcast(conn.server, { t: 'emote', id: conn.user.id, e: m.e }, conn.user.id);
        }
        return;
      case 'dead':
        if (conn.player && !conn.server?.vm) conn.player.guard.expect(conn.player.spawn, 6);
        if (conn.server) this.broadcast(conn.server, { t: 'dead', id: conn.user.id }, conn.user.id);
        if (conn.server?.vm) conn.server.inbox.push({ e: 'died', userId: conn.user.id });
        return;
      case 'ping':
        return conn.send({ t: 'pong', c: m.c ?? 0, s: Date.now() });
      case 'admin':
        return this.adminCommand(conn, m);
      case 'phys':
        return this.physIn(conn, m);
      case 'phys_claim':
        return this.physClaim(conn, m);
      default:
    }
  }

  placeEvent(conn, m) {
    const server = conn.server;
    const pl = conn.player;
    if (!server?.vm || !pl) return;
    if (++pl.events > MAX_EVENTS_PER_TICK) return;
    const id = String(m.id ?? '').slice(0, 20);
    const userId = conn.user.id;
    // Apps from 1.6.2 send where they are with shots and tool uses: checked like any move,
    // and put in right before the event, so the server sees the shooter where they are.
    if (Array.isArray(m.p) && (m.t === 'remote' || m.t === 'invoke' || m.t === 'tool' || m.t === 'prompt')) {
      const before = pl.p;
      this.state(conn, { p: m.p, r: pl.r, a: pl.a });
      if (pl.p !== before) {
        pl.posDirty = false;
        server.inbox.push({ e: 'pos', userId, p: { $v3: pl.p } });
      }
    }
    if (m.t === 'remote') server.inbox.push({ e: 'fire', userId, id, args: Array.isArray(m.args) ? m.args.slice(0, 20) : [] });
    else if (m.t === 'invoke') server.inbox.push({ e: 'invoke', userId, id, rid: Number(m.rid) || 0, args: Array.isArray(m.args) ? m.args.slice(0, 20) : [] });
    else if (m.t === 'touch') server.inbox.push({ e: 'touch', userId, id, ended: m.ended === true });
    else if (m.t === 'click') server.inbox.push({ e: 'click', userId, id });
    else if (m.t === 'prompt') server.inbox.push({ e: 'prompt', userId, id });
    else if (m.t === 'seat') server.inbox.push({ e: 'seat', userId, id: m.id == null ? undefined : id });
    else if (m.t === 'tool' && TOOL_EVENTS.has(m.ev)) {
      const p = Array.isArray(m.p?.$v3) ? { $v3: m.p.$v3.slice(0, 3).map(Number) } : undefined;
      server.inbox.push({ e: 'tool', userId, id: m.id == null ? undefined : id, ev: m.ev, p });
    }
  }

  async join(conn, m) {
    if (conn.rules.age === null) {
      return conn.send({ t: 'error', code: 'birthdate', m: msg('birthdate_needed', conn.lang) });
    }
    if (conn.server) this.leave(conn);
    let game = 'playground';
    if (GAMES[m.game]) game = m.game;
    else if (m.game && this.isStudio(String(m.game))) {
      game = String(m.game);
      if (!this.places.canJoin(conn.user, game)) return conn.send({ t: 'error', code: 'not_found', m: msg('no_place', conn.lang) });
    }
    const studio = !GAMES[game];
    // Studio places run scripts on the device too; apps without the Luau library can't.
    if (studio && !conn.luau) return conn.send({ t: 'error', code: 'device', m: msg('device_unsupported', conn.lang) });
    let server;
    if (m.server && m.server !== 'auto' && m.server !== 'new') {
      server = this.servers.get(String(m.server));
      if (!server || server.game !== game) return conn.send({ t: 'error', code: 'not_found', m: msg('server_gone', conn.lang) });
      // A server replaced by a newer version of the place: go to a current one instead.
      if (server.retired) server = this.pickServer(game, this.loadFriends(conn.user.id)) || (await this.createPlaceServer(game));
    } else {
      if (m.server !== 'new') server = this.pickServer(game, this.loadFriends(conn.user.id));
      if (!server) server = studio ? await this.createPlaceServer(game) : this.createServer(game);
    }
    // The socket may have closed while the place was loading.
    if (conn.ws.readyState !== 1) return;
    const cap = server.maxPlayers || MAX_PLAYERS;
    if (server.players.size >= cap) {
      return conn.send({ t: 'error', code: 'full', m: msg('server_full', conn.lang, { n: cap }) });
    }

    // One live session per account: the newest connection wins.
    const existing = this.byUser.get(conn.user.id);
    if (existing && existing.conn !== conn) {
      existing.conn.send({ t: 'kicked', code: 'duplicate', m: msg('duplicate', existing.conn.lang) });
      existing.conn.out.close(4000, 'duplicate');
      this.leave(existing.conn);
    }

    const angle = Math.random() * Math.PI * 2;
    const spawn = [Math.cos(angle) * 2.2, 0.6, 15.5 + Math.sin(angle) * 1.2];
    const player = { user: publicUser(conn.user), p: spawn, r: Math.PI, a: 'idle', hp: 100, dirty: true, conn, joinedAt: Date.now(), events: 0, spawn, guard: new MoveGuard(spawn), emotesAt: {} };
    server.players.set(conn.user.id, player);
    server.emptySince = 0;
    conn.player = player;
    conn.server = server;
    this.byUser.set(conn.user.id, { server, player, conn });

    // Studio places: the joining app gets the current world first, then hears about
    // its own arrival (Player, character, spawn point) like everyone else.
    // Gamepasses: which of this place's passes the player owns, and what's on sale.
    const passes = studio ? this.economy?.passesOwned(conn.user.id, game) || [] : [];
    const passInfo = studio ? this.economy?.passesInfo(game) || [] : [];
    const badges = studio ? this.badges?.ownedIn(conn.user.id, game) || [] : [];
    const badgeInfo = studio ? this.badges?.info(game) || [] : [];
    // A big world doesn't fit the welcome: what's in Workspace follows it as replication.
    const snap = studio ? splitSnapshot(server.vm.snapshot(), Math.min(conn.out.buffer / 2, 8 * 1024 * 1024) - CHUNK_BYTES) : null;
    const place = studio ? { id: game, strings: server.strings, snapshot: snap.head, passes, pass_info: passInfo, badges, badge_info: badgeInfo } : null;
    conn.send({
      t: 'welcome',
      server: this.describe(server),
      you: conn.user.id,
      chat: conn.rules.chat && server.chat !== false,
      emotes: server.emotes !== false,
      place,
      spawn,
      players: [...server.players.values()]
        .filter((p) => p !== player)
        .map((p) => ({ ...p.user, p: p.p, r: p.r, a: p.a })),
    });
    if (snap?.rest.length) conn.sendOps(snap.rest);
    this.broadcast(server, { t: 'join', player: { ...player.user, p: player.p, r: player.r, a: player.a } }, conn.user.id);
    this.broadcast(server, { t: 'sys', k: 'joined', n: player.user.display_name }, conn.user.id);
    if (studio && server.phys.size) {
      conn.send({ t: 'phys_own', o: Object.fromEntries([...server.phys].map(([id, e]) => [id, e.owner])) });
    }
    if (studio) {
      const look = { colors: player.user.colors, face: player.user.face, accessories: player.user.accessories };
      this.routeOps(server, server.vm.dispatch([{ e: 'player_add', userId: conn.user.id, name: conn.user.username, display: conn.user.display_name, lang: conn.lang, look, passes, pass_info: passInfo, badges, badge_info: badgeInfo }]));
      this.flushPlace(server);
    }
    // Every place (the playground too) keeps visit history: stats and "recently played".
    // A visit is a new player, not every join.
    if (!this.places || this.places.visit(game, conn.user.id) !== false) this.onJoin(game);
    this.economy?.progress(conn.user.id, 'places', 1, game);
    this.log(`${conn.user.username} joined ${server.id} (${server.players.size}/${server.maxPlayers || MAX_PLAYERS})`);
  }

  state(conn, m) {
    const pl = conn.player;
    if (!pl || !Array.isArray(m.p)) return;
    const pos = [finite(m.p[0], WORLD_LIMIT), finite(m.p[1], WORLD_LIMIT), finite(m.p[2], WORLD_LIMIT)];
    // The platform owner flies and speeds around with the in-game admin panel.
    if (!this.anticheat || isOwner(conn.user)) pl.guard.reset(pos);
    else {
      const lim = { ...this.limitsFor(conn.server, conn.user.id) };
      // Footing for this very position against the place's solids (the runtime's own
      // answer is a quarter second old, but knows about parts moving right now).
      if (!conn.server?.vm) {
        // The playground: its own shapes; a normal jump except off the trampolines.
        const from = pl.guard.base?.p || pos;
        if (Math.hypot(from[0] - TRAMPOLINES[0], from[2] - TRAMPOLINES[1]) > TRAMPOLINE_RADIUS) lim.airJump = PLAYGROUND_JUMP;
        // The trampolines throw you up before your feet ever touch them: low over the pads
        // counts as standing, or a run of bounces looks like one endless flight.
        const onPads = Math.hypot(pos[0] - TRAMPOLINES[0], pos[2] - TRAMPOLINES[1]) < TRAMPOLINE_PADS && pos[1] < 4;
        lim.standing = onPads || PLAYGROUND_SOLIDS.standing(pos);
        lim.grounded = lim.standing;
      } else if (conn.server?.clientWorld) delete lim.grounded;
      else if (conn.server?.solids && lim.grounded !== undefined) {
        lim.standing = conn.server.solids.standing(pos);
        lim.grounded = lim.standing || lim.grounded;
      }
      const bad = pl.guard.check(pos, lim);
      if (bad) return this.caught(conn, pl, bad);
    }
    pl.p = pos;
    pl.r = finite(m.r, 100);
    // Built-in states, or a custom animation from the animator (anim://<id>).
    pl.a = ANIMS.has(m.a) || /^anim:\/\/\d{1,10}$/.test(String(m.a)) ? m.a : 'idle';
    // Whose character the camera follows (spectating): the anti-wallhack looks from there too.
    pl.watch = Number.isSafeInteger(m.w) && m.w > 0 ? m.w : 0;
    pl.dirty = true;
    pl.posDirty = true;
  }

  /**
   * Voice: 100 ms of the speaker's microphone (12 kHz ADPCM, base64) goes to players
   * within earshot. Not for those whose age rules turn chat off (either way), not in
   * servers without chat, not from someone muted, and never between people where
   * either blocked the other. Voice can't be filtered like text, so it only goes
   * between people of the same age group: adults hear adults, teens hear teens.
   */
  voice(conn, m) {
    const server = conn.server;
    const me = conn.player;
    if (!server || !me || server.chat === false || !conn.rules.chat || server.muted?.has(conn.user.id)) return;
    const d = typeof m.d === 'string' ? m.d : '';
    if (!d || d.length > 2400 || !/^[A-Za-z0-9+/=]+$/.test(d)) return;
    // At most 12 packets a second (it sends 10).
    const now = Date.now();
    if (!me.voiceAt || now - me.voiceAt > 1000) {
      me.voiceAt = now;
      me.voiceN = 0;
    }
    if (++me.voiceN > 12) return;
    // Blasting clipped noise (a "soundpad" at double volume) isn't passed on.
    if (tooLoud(d)) {
      me.loudN = (me.loudN || 0) + 1;
      if (me.loudN === 30) this.log(`voice: ${conn.user.username} keeps sending clipped audio`);
      return;
    }
    // Where it's coming from, for listeners who don't see the speaker (behind a wall).
    const data = JSON.stringify({ t: 'voice', id: conn.user.id, d, p: me.p.map((v) => +v.toFixed(1)) });
    for (const [id, p] of server.players) {
      if (id === conn.user.id || !p.conn.rules.chat || p.conn.blocks.has(conn.user.id) || conn.blocks.has(id)) continue;
      if (Boolean(p.conn.rules.filter_chat) !== Boolean(conn.rules.filter_chat)) continue;
      if (dist(p.p, me.p) <= VOICE_RANGE) p.conn.sendRaw(data);
    }
  }

  /**
   * Taking someone's open arms (they're doing the hug emote, and close): you're put
   * right in front of them, face to face, and both apps play the hug once.
   */
  hug(conn, m) {
    const server = conn.server;
    const me = conn.player;
    const other = server?.players.get(Number(m.id));
    if (!me || !other || other === me || server.emotes === false) return;
    if (other.a !== 'hug' || dist(me.p, other.p) > 12) return;
    const yaw = Number(other.r) || 0;
    // Where they face: the app turns Melly by `yaw`, facing (-sin, 0, -cos).
    const front = [other.p[0] - Math.sin(yaw) * 0.95, other.p[1], other.p[2] - Math.cos(yaw) * 0.95];
    me.guard.teleportTo(front);
    conn.send({ t: 'hug', with: other.user.id, pos: front, r: yaw + Math.PI });
    other.conn.send({ t: 'hug', with: me.user.id });
  }

  /** How fast and high this player may go in this place right now. */
  limitsFor(server, userId) {
    if (!server?.vm) return PLAYGROUND_LIMITS;
    const l = server.limits?.[String(userId)];
    const cur = l ? { ...l, check: l.check !== false } : { walk: 5, sprint: 7, jump: 8.2, gravity: 22, check: true };
    // A place slowing someone down (freezing them, say) still lets through what they
    // were doing a moment ago: their app hasn't heard about it yet.
    server.recentLimits ??= new Map();
    const t = Date.now();
    const hist = (server.recentLimits.get(userId) || []).filter((h) => t - h.t <= 11000);
    hist.push({ t, walk: cur.walk, sprint: cur.sprint, jump: cur.jump });
    server.recentLimits.set(userId, hist);
    for (const h of hist) {
      cur.walk = Math.max(cur.walk, h.walk);
      cur.sprint = Math.max(cur.sprint, h.sprint);
      cur.jump = Math.max(cur.jump, h.jump);
    }
    return cur;
  }

  /** A movement check failed: put the player back, and kick repeat offenders. */
  caught(conn, pl, bad) {
    if (bad.silent) return;
    conn.send({ t: 'correct', p: bad.back });
    if (bad.noPoints) return;
    this.log(`anticheat: ${conn.user.username} ${bad.reason} (points ${pl.guard.points}) on ${conn.server?.id}`);
    if (pl.guard.shouldKick) {
      this.log(`anticheat: kicked ${conn.user.username} for ${bad.reason}`);
      this.onCheat(conn.user, bad.reason, conn.server?.game || '');
      this.kick(conn.user.id, 'cheat', msg('kicked_cheat', conn.lang));
    }
  }

  chat(conn, m) {
    if (!conn.server || conn.server.chat === false) return;
    const text = tameMarks(m.m)
      .replace(/[\u0000-\u001f\u007f]/g, ' ')
      .trim()
      .slice(0, 200);
    if (!text) return;
    const now = Date.now();
    if (now - conn.lastChat > 5000) conn.chatBurst = 0;
    conn.chatBurst += 1;
    conn.lastChat = now;
    if (conn.chatBurst > 6) return conn.send({ t: 'sys', k: 'slow' });
    if (!conn.rules.chat) return conn.send({ t: 'sys', k: 'no_chat' });
    if (conn.server.muted?.has(conn.user.id)) return conn.send({ t: 'sys', k: 'muted' });
    const base = { t: 'chat', id: conn.user.id, name: conn.user.display_name };
    // Staff get their badge next to the name, like on profiles.
    if (conn.user.role === 'owner' || conn.user.role === 'admin') base.role = conn.user.role;
    const raw = JSON.stringify({ ...base, m: text });
    const clean = JSON.stringify({ ...base, m: filterText(text) });
    for (const p of conn.server.players.values()) {
      // Whoever blocked the sender never receives their messages; under-13s see no chat.
      if (p.conn.blocks.has(conn.user.id) || !p.conn.rules.chat) continue;
      // The sender always sees what they typed; minors get the filtered version.
      const data = p.conn !== conn && p.conn.rules.filter_chat ? clean : raw;
      p.conn.sendRaw(data);
    }
  }

  /**
   * The in-game admin panel (the platform owner only): mute for this server, kick,
   * bring, kill, announce. Flying and speed happen in the owner's own app.
   */
  adminCommand(conn, m) {
    const server = conn.server;
    if (!server || !isOwner(conn.user)) return;
    const target = server.players.get(Number(m.id));
    server.muted ??= new Set();
    const done = (k, name = '') => conn.send({ t: 'admin', ok: k, name, muted: [...server.muted] });
    switch (m.cmd) {
      case 'state':
        return done('state');
      case 'mute':
        if (!target || target.conn === conn) return;
        server.muted.add(target.user.id);
        target.conn.send({ t: 'sys', k: 'muted' });
        return done('mute', target.user.display_name);
      case 'unmute':
        if (!target) return;
        server.muted.delete(target.user.id);
        target.conn.send({ t: 'sys', k: 'unmuted' });
        return done('unmute', target.user.display_name);
      case 'kick':
        if (!target || target.conn === conn) return;
        this.kick(target.user.id, 'kicked', '');
        return done('kick', target.user.display_name);
      case 'bring': {
        if (!target || target.conn === conn) return;
        const p = conn.player.p;
        const pos = [p[0] + 1.5, p[1] + 0.5, p[2]];
        target.guard.teleportTo(pos);
        target.conn.send({ t: 'correct', p: pos });
        return done('bring', target.user.display_name);
      }
      case 'kill':
        if (!target) return;
        target.conn.send({ t: 'admin_kill' });
        return done('kill', target.user.display_name);
      case 'announce': {
        const text = tameMarks(m.m).replace(/[\u0000-\u001f\u007f]/g, ' ').trim().slice(0, 200);
        if (!text) return;
        this.broadcast(server, { t: 'sys', k: 'admin', m: text });
        return done('announce');
      }
      default:
    }
  }

  leave(conn) {
    const server = conn.server;
    if (!server) return;
    const player = server.players.get(conn.user.id);
    if (player && player.conn === conn) {
      server.players.delete(conn.user.id);
      server.recentLimits?.delete(conn.user.id);
      const entry = this.byUser.get(conn.user.id);
      if (entry && entry.conn === conn) this.byUser.delete(conn.user.id);
      this.broadcast(server, { t: 'leave', id: conn.user.id });
      this.broadcast(server, { t: 'sys', k: 'left', n: player.user.display_name });
      if (server.vm) {
        try {
          this.routeOps(server, server.vm.dispatch([{ e: 'player_remove', userId: conn.user.id }]));
        } catch (err) {
          this.log(`player_remove failed: ${err.message}`);
        }
      }
      // Parts this app simulated: nobody's for now (the next report or the nearest player takes them).
      if (server.phys) {
        for (const [id, e] of server.phys) {
          if (e.owner === conn.user.id) {
            e.owner = 0;
            server.physOwn[id] = 0;
          }
        }
      }
      this.places?.playtime(server.game, conn.user.id, Date.now() - player.joinedAt);
      if (server.players.size === 0) server.emptySince = Date.now();
      this.log(`${conn.user.username} left ${server.id} (${server.players.size}/${server.maxPlayers || MAX_PLAYERS})`);
    }
    conn.server = null;
    conn.player = null;
  }

  /** Who plays where, for the once-a-minute quest progress. */
  sessions() {
    return [...this.servers.values()]
      .filter((s) => s.players.size)
      .map((s) => ({ game: s.game, players: [...s.players.keys()], friendsOf: (id) => this.loadFriends(id) }));
  }

  /** Someone bought a gamepass: scripts in that place hear about it right away. */
  passBought(userId, placeId, passId) {
    const entry = this.byUser.get(userId);
    if (!entry || entry.server.game !== placeId || !entry.server.vm) return;
    entry.server.inbox.push({ e: 'pass_bought', userId, id: passId });
  }

  /** New balance after a purchase lands (the app updates its counters). */
  notifyWallet(userId, wallet) {
    this.byUser.get(userId)?.conn.send({ t: 'wallet', wallet });
  }

  /** Pushes fresh profile data (colors, hat, name) to everyone who can see this user. */
  updateUser(user) {
    const entry = this.byUser.get(user.id);
    if (!entry) return;
    entry.conn.user = user;
    entry.conn.rules = chatRules(user.birthdate);
    entry.player.user = withLook(publicUser(user), entry.player.look);
    this.broadcast(entry.server, { t: 'look', player: entry.player.user });
  }

  /** Refreshes the live block list after the user blocks/unblocks someone. */
  setBlocks(userId, blocks) {
    const entry = this.byUser.get(userId);
    if (entry) entry.conn.blocks = blocks;
  }

  /** Disconnects a user from the game (admin kick or ban). */
  kick(userId, code, message) {
    const entry = this.byUser.get(userId);
    if (!entry) return false;
    entry.conn.send({ t: 'kicked', code, m: message });
    entry.conn.out.close(4001, code);
    this.leave(entry.conn);
    return true;
  }

  closeServer(id) {
    const server = this.servers.get(String(id));
    if (!server) return false;
    for (const p of [...server.players.values()]) {
      p.conn.send({ t: 'kicked', code: 'closed', m: '' });
      p.conn.out.close(4002, 'closed');
      this.leave(p.conn);
    }
    this.servers.delete(server.id);
    server.vm?.close();
    return true;
  }

  /** Announcement from the admin panel, shown in every server's chat. */
  announce(text) {
    for (const server of this.servers.values()) this.broadcast(server, { t: 'sys', k: 'admin', m: text });
  }

  /**
   * Where everyone is, 20 times a second. A place with StarterPlayer.PlayerSyncRange
   * only tells each player about the ones near them (unless Player.SyncAll): what a
   * wallhack can't receive, it can't draw. Someone leaving your range is sent once to
   * far below the world, so every app (old ones too) stops showing them. The same goes
   * for players hidden behind the place's walls (see occlusion.js).
   */
  sendStates(server, now) {
    if (!server.vm && server.game === 'playground' && this.anticheat) server.occ ??= PLAYGROUND_OCC;
    if (server.occ && (!server.visAt || now - server.visAt >= VISIBILITY_EVERY_MS)) {
      server.visAt = now;
      this.updateVisibility(server, now);
    }
    const state = (id, p) => [id, +p.p[0].toFixed(3), +p.p[1].toFixed(3), +p.p[2].toFixed(3), +p.r.toFixed(3), p.a];
    const dirty = [];
    for (const [id, p] of server.players) {
      if (p.dirty) dirty.push(id);
      p.dirty = false;
    }
    const all = [];
    for (const id of dirty) all.push(state(id, server.players.get(id)));
    for (const [rid, r] of server.players) {
      const lim = server.limits?.[String(rid)];
      const range = server.vm && lim && !lim.all ? Number(lim.range) || 0 : 0;
      const hidden = r.hidden;
      if (range <= 0 && !hidden) {
        // Everyone in sight: whoever moved, plus anyone this player lost track of before.
        let out = all;
        if (r.seen) {
          out = all.slice();
          for (const [id, p] of server.players) if (id !== rid && !r.seen.has(id) && !dirty.includes(id)) out.push(state(id, p));
          r.seen = null;
        }
        if (out.length) r.conn.send({ t: 's', s: out, ts: now });
        continue;
      }
      r.seen ??= new Set([...server.players.keys()]);
      const out = [];
      for (const [id, p] of server.players) {
        if (id === rid) continue;
        const near = (range <= 0 || dist(p.p, r.p) <= range) && !hidden?.has(id);
        if (near && (dirty.includes(id) || !r.seen.has(id))) {
          out.push(state(id, p));
          r.seen.add(id);
        } else if (!near && r.seen.has(id)) {
          out.push([id, 0, -10000, 0, 0, 'idle']);
          r.seen.delete(id);
        }
      }
      if (out.length) r.conn.send({ t: 's', s: out, ts: now });
    }
  }

  /**
   * Who each player can't see: fully behind solid blocks from every spot their camera
   * can be in (and the camera of whoever they're spectating). Someone seen stays sent
   * for a moment after, so peeking around a corner doesn't flicker.
   */
  updateVisibility(server, now) {
    const occ = server.occ;
    for (const [rid, r] of server.players) {
      // The playground has no place rules: everyone is checked, from the default camera.
      const lim = server.vm ? server.limits?.[String(rid)] : { check: true, zoom: 16 };
      if (!lim || lim.check === false || lim.all || isOwner(r.conn.user)) {
        r.hidden = null;
        continue;
      }
      const zoom = Math.min(Math.max(Number(lim.zoom) || 16, 0), 60);
      const from = eyes(occ, r.p, zoom);
      const w = r.watch && r.watch !== rid ? server.players.get(r.watch) : null;
      if (w) from.push(...eyes(occ, w.p, zoom));
      r.seenUntil ??= new Map();
      const hidden = new Set();
      for (const [id, p] of server.players) {
        if (id === rid) continue;
        if ((r.seenUntil.get(id) || 0) > now + VISIBLE_HOLD_MS - VISIBILITY_EVERY_MS * 2) continue;
        if (canSee(occ, from, p.p)) r.seenUntil.set(id, now + VISIBLE_HOLD_MS);
        else if ((r.seenUntil.get(id) || 0) < now) hidden.add(id);
      }
      for (const id of r.seenUntil.keys()) if (!server.players.has(id)) r.seenUntil.delete(id);
      r.hidden = hidden.size ? hidden : null;
    }
  }

  broadcast(server, m, exceptId = null) {
    const data = JSON.stringify(m);
    for (const [id, p] of server.players) {
      if (id === exceptId) continue;
      p.conn.sendRaw(data);
    }
  }

  tick() {
    const now = Date.now();
    for (const server of this.servers.values()) {
      if (server.players.size === 0) {
        if (server.emptySince && now - server.emptySince > EMPTY_SERVER_TTL_MS) {
          this.servers.delete(server.id);
          server.vm?.close();
          this.log(`server ${server.id} closed (empty)`);
        }
        continue;
      }
      if (server.migrateAt && now >= server.migrateAt) this.migrate(server);
      if (server.vm) {
        this.stepPhys(server, now);
        this.stepPlace(server, now);
      }
      this.sendStates(server, now);
    }
  }
}
