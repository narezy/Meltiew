import crypto from 'node:crypto';
import { parseColors } from './colors.js';
import { msg } from './i18n.js';

export const MAX_PLAYERS = 10;
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
const EMPTY_SERVER_TTL_MS = 30_000;
const WORLD_LIMIT = 400;
export const ANIMS = new Set(['idle', 'walk', 'run', 'jump', 'fall', 'wave', 'dance', 'cheer', 'sit', 'clap', 'laugh', 'dead']);
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
    hat: u.hat,
  };
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
  constructor({ log = () => {}, loadBlocks = () => new Set() } = {}) {
    this.servers = new Map(); // id -> server
    this.byUser = new Map(); // userId -> { server, player, conn }
    this.log = log;
    this.loadBlocks = loadBlocks;
    this.timer = setInterval(() => this.tick(), 1000 / TICK_HZ);
    this.timer.unref?.();
    this.nameCounter = 0;
  }

  stop() {
    clearInterval(this.timer);
    for (const s of this.servers.values()) {
      for (const p of s.players.values()) p.conn.ws.close(1001, 'server shutdown');
    }
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
      .filter((s) => s.game === game)
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
      max_players: MAX_PLAYERS,
      created_at: s.createdAt,
      player_ids: [...s.players.keys()],
    };
  }

  hasServer(id) {
    return this.servers.has(String(id));
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

  /** Picks the fullest server with a free slot, or makes a new one. */
  pickServer(game) {
    let best = null;
    for (const s of this.servers.values()) {
      if (s.game !== game || s.players.size >= MAX_PLAYERS) continue;
      if (!best || s.players.size > best.players.size) best = s;
    }
    return best || this.createServer(game);
  }

  /** Called for every authenticated websocket. */
  attach(ws, user, lang = 'en') {
    const conn = {
      ws,
      user,
      lang,
      player: null,
      server: null,
      lastChat: 0,
      chatBurst: 0,
      blocks: this.loadBlocks(user.id),
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
        return this.join(conn, m);
      case 'state':
        return this.state(conn, m);
      case 'chat':
        return this.chat(conn, m);
      case 'emote':
        if (conn.server && EMOTES.has(m.e)) {
          this.broadcast(conn.server, { t: 'emote', id: conn.user.id, e: m.e }, conn.user.id);
        }
        return;
      case 'dead':
        if (conn.server) this.broadcast(conn.server, { t: 'dead', id: conn.user.id }, conn.user.id);
        return;
      case 'ping':
        return conn.send({ t: 'pong', c: m.c ?? 0, s: Date.now() });
      default:
    }
  }

  join(conn, m) {
    if (conn.server) this.leave(conn);
    const game = GAMES[m.game] ? m.game : 'playground';
    let server;
    if (m.server === 'new') {
      server = this.createServer(game);
    } else if (m.server && m.server !== 'auto') {
      server = this.servers.get(String(m.server));
      if (!server) return conn.send({ t: 'error', code: 'not_found', m: msg('server_gone', conn.lang) });
    } else {
      server = this.pickServer(game);
    }
    if (server.players.size >= MAX_PLAYERS) {
      return conn.send({ t: 'error', code: 'full', m: msg('server_full', conn.lang, { n: MAX_PLAYERS }) });
    }

    // One live session per account: the newest connection wins.
    const existing = this.byUser.get(conn.user.id);
    if (existing && existing.conn !== conn) {
      existing.conn.send({ t: 'kicked', code: 'duplicate', m: msg('duplicate', existing.conn.lang) });
      existing.conn.ws.close(4000, 'duplicate');
      this.leave(existing.conn);
    }

    const angle = Math.random() * Math.PI * 2;
    const spawn = [Math.cos(angle) * 2.5, 0.5, 10 + Math.sin(angle) * 2.5];
    const player = { user: publicUser(conn.user), p: spawn, r: Math.PI, a: 'idle', hp: 100, dirty: true, conn };
    server.players.set(conn.user.id, player);
    server.emptySince = 0;
    conn.player = player;
    conn.server = server;
    this.byUser.set(conn.user.id, { server, player, conn });

    conn.send({
      t: 'welcome',
      server: this.describe(server),
      you: conn.user.id,
      spawn,
      players: [...server.players.values()]
        .filter((p) => p !== player)
        .map((p) => ({ ...p.user, p: p.p, r: p.r, a: p.a })),
    });
    this.broadcast(server, { t: 'join', player: { ...player.user, p: player.p, r: player.r, a: player.a } }, conn.user.id);
    this.broadcast(server, { t: 'sys', k: 'joined', n: player.user.display_name }, conn.user.id);
    this.log(`${conn.user.username} joined ${server.id} (${server.players.size}/${MAX_PLAYERS})`);
  }

  state(conn, m) {
    const pl = conn.player;
    if (!pl || !Array.isArray(m.p)) return;
    pl.p = [finite(m.p[0], WORLD_LIMIT), finite(m.p[1], WORLD_LIMIT), finite(m.p[2], WORLD_LIMIT)];
    pl.r = finite(m.r, 100);
    pl.a = ANIMS.has(m.a) ? m.a : 'idle';
    pl.dirty = true;
  }

  chat(conn, m) {
    if (!conn.server) return;
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
    const data = JSON.stringify({ t: 'chat', id: conn.user.id, name: conn.user.display_name, m: text });
    for (const p of conn.server.players.values()) {
      // Whoever blocked the sender never receives their messages.
      if (p.conn.blocks.has(conn.user.id)) continue;
      if (p.conn.ws.readyState === 1) p.conn.ws.send(data);
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
      if (server.players.size === 0) server.emptySince = Date.now();
      this.log(`${conn.user.username} left ${server.id} (${server.players.size}/${MAX_PLAYERS})`);
    }
    conn.server = null;
    conn.player = null;
  }

  /** Pushes fresh profile data (colors, hat, name) to everyone who can see this user. */
  updateUser(user) {
    const entry = this.byUser.get(user.id);
    if (!entry) return;
    entry.conn.user = user;
    entry.player.user = publicUser(user);
    this.broadcast(entry.server, { t: 'look', player: entry.player.user });
  }

  /** Refreshes the live block list after the user blocks/unblocks someone. */
  setBlocks(userId, blocks) {
    const entry = this.byUser.get(userId);
    if (entry) entry.conn.blocks = blocks;
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
          this.log(`server ${server.id} closed (empty)`);
        }
        continue;
      }
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
