import crypto from 'node:crypto';
import { parseColors } from './colors.js';
import { wornOf, legacyHat } from './accessories.js';
import { msg } from './i18n.js';
import { MoveGuard, PLAYGROUND_LIMITS } from './anticheat.js';
import { chatRules } from './age.js';
import { filterText } from './filter.js';
import { PlaceVM } from './studio/vm.js';

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
const WORLD_LIMIT = 400;
export const ANIMS = new Set(['idle', 'walk', 'run', 'jump', 'fall', 'wave', 'dance', 'cheer', 'sit', 'clap', 'laugh', 'dead', 'climb']);
export const HEART_COOLDOWN_MS = 2500;
export const EMOTE_COOLDOWN_MS = 800;
export const EMOTES = new Set(['wave', 'heart', 'dance', 'cheer', 'sit', 'clap', 'laugh']);
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

function publicUser(u) {
  return {
    id: u.id,
    username: u.username,
    display_name: u.display_name,
    colors: parseColors(u.colors),
    hat: legacyHat(wornOf(u)),
    accessories: wornOf(u),
    role: u.role || 'user',
    face: u.face || ':D',
  };
}

/** The platform's owner (nrz): the only one with the in-game admin panel. */
export function isOwner(user) {
  return user?.role === 'owner';
}

function meltHash(melt) {
  return crypto.createHash('sha1').update(JSON.stringify(melt)).digest('hex');
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
      for (const p of s.players.values()) p.conn.ws.close(1001, 'server shutdown');
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
          if (who && Array.isArray(v)) who.guard.reset(v.map(Number));
          this.target(server, op.to, { o: 'spawn', pos: op.pos });
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
      if (o.length) p.conn.send({ t: 'r', o });
    }
    server.shared = [];
    server.targeted = new Map();
  }

  stepPlace(server, now) {
    const dt = Math.min(0.25, (now - server.lastStep) / 1000);
    server.lastStep = now;
    try {
      const events = server.inbox;
      server.inbox = [];
      for (const p of server.players.values()) {
        p.events = 0;
        if (p.posDirty) {
          p.posDirty = false;
          events.push({ e: 'pos', userId: p.user.id, p: { $v3: p.p } });
        }
      }
      if (events.length) this.routeOps(server, server.vm.dispatch(events));
      this.routeOps(server, server.vm.step(dt));
      if (!server.limitsAt || now - server.limitsAt > 1000) {
        server.limitsAt = now;
        server.limits = server.vm.limits();
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
    };
    conn.send = (m) => {
      if (ws.readyState === 1) ws.send(JSON.stringify(m));
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
        return this.placeEvent(conn, m);
      case 'state':
        return this.state(conn, m);
      case 'chat':
        return this.chat(conn, m);
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
    if (m.t === 'remote') server.inbox.push({ e: 'fire', userId, id, args: Array.isArray(m.args) ? m.args.slice(0, 20) : [] });
    else if (m.t === 'invoke') server.inbox.push({ e: 'invoke', userId, id, rid: Number(m.rid) || 0, args: Array.isArray(m.args) ? m.args.slice(0, 20) : [] });
    else if (m.t === 'touch') server.inbox.push({ e: 'touch', userId, id, ended: m.ended === true });
    else if (m.t === 'click') server.inbox.push({ e: 'click', userId, id });
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
      existing.conn.ws.close(4000, 'duplicate');
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
    const place = studio ? { id: game, strings: server.strings, snapshot: server.vm.snapshot(), passes, pass_info: passInfo, badges, badge_info: badgeInfo } : null;
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
    this.broadcast(server, { t: 'join', player: { ...player.user, p: player.p, r: player.r, a: player.a } }, conn.user.id);
    this.broadcast(server, { t: 'sys', k: 'joined', n: player.user.display_name }, conn.user.id);
    if (studio) {
      this.routeOps(server, server.vm.dispatch([{ e: 'player_add', userId: conn.user.id, name: conn.user.username, display: conn.user.display_name, lang: conn.lang, passes, pass_info: passInfo, badges, badge_info: badgeInfo }]));
      this.flushPlace(server);
    }
    // Every place (the playground too) keeps visit history: stats and "recently played".
    this.places?.visit(game, conn.user.id);
    this.onJoin(game);
    this.economy?.progress(conn.user.id, 'places', 1, game);
    this.log(`${conn.user.username} joined ${server.id} (${server.players.size}/${MAX_PLAYERS})`);
  }

  state(conn, m) {
    const pl = conn.player;
    if (!pl || !Array.isArray(m.p)) return;
    const pos = [finite(m.p[0], WORLD_LIMIT), finite(m.p[1], WORLD_LIMIT), finite(m.p[2], WORLD_LIMIT)];
    // The platform owner flies and speeds around with the in-game admin panel.
    if (isOwner(conn.user)) pl.guard.reset(pos);
    else {
      const bad = pl.guard.check(pos, this.limitsFor(conn.server, conn.user.id));
      if (bad) return this.caught(conn, pl, bad);
    }
    pl.p = pos;
    pl.r = finite(m.r, 100);
    // Built-in states, or a custom animation from the animator (anim://<id>).
    pl.a = ANIMS.has(m.a) || /^anim:\/\/\d{1,10}$/.test(String(m.a)) ? m.a : 'idle';
    pl.dirty = true;
    pl.posDirty = true;
  }

  /** How fast and high this player may go in this place right now. */
  limitsFor(server, userId) {
    if (!server?.vm) return PLAYGROUND_LIMITS;
    const l = server.limits?.[String(userId)];
    return l ? { ...l, check: l.check !== false } : { walk: 5, sprint: 7, jump: 8.2, gravity: 22, check: true };
  }

  /** A movement check failed: put the player back, and kick repeat offenders. */
  caught(conn, pl, bad) {
    if (bad.silent) return;
    conn.send({ t: 'correct', p: bad.back });
    this.log(`anticheat: ${conn.user.username} ${bad.reason} (points ${pl.guard.points}) on ${conn.server?.id}`);
    if (pl.guard.shouldKick) {
      this.log(`anticheat: kicked ${conn.user.username} for ${bad.reason}`);
      this.onCheat(conn.user, bad.reason, conn.server?.game || '');
      this.kick(conn.user.id, 'cheat', msg('kicked_cheat', conn.lang));
    }
  }

  chat(conn, m) {
    if (!conn.server || conn.server.chat === false) return;
    const text = String(m.m ?? '')
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
      if (p.conn.ws.readyState === 1) p.conn.ws.send(data);
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
        target.guard.reset(pos);
        target.conn.send({ t: 'correct', p: pos });
        return done('bring', target.user.display_name);
      }
      case 'kill':
        if (!target) return;
        target.conn.send({ t: 'admin_kill' });
        return done('kill', target.user.display_name);
      case 'announce': {
        const text = String(m.m ?? '').replace(/[\u0000-\u001f\u007f]/g, ' ').trim().slice(0, 200);
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
      this.places?.playtime(server.game, conn.user.id, Date.now() - player.joinedAt);
      if (server.players.size === 0) server.emptySince = Date.now();
      this.log(`${conn.user.username} left ${server.id} (${server.players.size}/${MAX_PLAYERS})`);
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
    entry.player.user = publicUser(user);
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
    entry.conn.ws.close(4001, code);
    this.leave(entry.conn);
    return true;
  }

  closeServer(id) {
    const server = this.servers.get(String(id));
    if (!server) return false;
    for (const p of [...server.players.values()]) {
      p.conn.send({ t: 'kicked', code: 'closed', m: '' });
      p.conn.ws.close(4002, 'closed');
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

  broadcast(server, m, exceptId = null) {
    const data = JSON.stringify(m);
    for (const [id, p] of server.players) {
      if (id === exceptId) continue;
      if (p.conn.ws.readyState === 1) p.conn.ws.send(data);
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
      if (server.vm) this.stepPlace(server, now);
      const states = [];
      for (const [id, p] of server.players) {
        if (!p.dirty) continue;
        p.dirty = false;
        states.push([id, +p.p[0].toFixed(3), +p.p[1].toFixed(3), +p.p[2].toFixed(3), +p.r.toFixed(3), p.a]);
      }
      if (states.length) this.broadcast(server, { t: 's', s: states, ts: now });
    }
  }
}
