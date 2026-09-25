import crypto from 'node:crypto';
import { parseColors } from './colors.js';

export const MAX_PLAYERS = 10;
export const GAMES = {
  playground: {
    id: 'playground',
    name: 'Детская площадка',
    description: 'Горки, качели, батуты и паркур над облаками. Тусуйся с друзьями!',
  },
};

const TICK_HZ = 15;
const EMPTY_SERVER_TTL_MS = 30_000;
const WORLD_LIMIT = 400;
const ANIMS = new Set(['idle', 'walk', 'run', 'jump', 'fall', 'wave', 'sit']);
const EMOTES = new Set(['wave', 'dance', 'laugh', 'heart']);
const SERVER_ADJECTIVES = ['Солнечная', 'Ванильная', 'Пушистая', 'Весёлая', 'Уютная', 'Мятная', 'Звёздная', 'Облачная', 'Карамельная', 'Лавандовая'];

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
  constructor({ log = () => {} } = {}) {
    this.servers = new Map(); // id -> server
    this.byUser = new Map(); // userId -> { server, player }
    this.log = log;
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
    const adj = SERVER_ADJECTIVES[Math.floor(Math.random() * SERVER_ADJECTIVES.length)];
    const server = {
      id,
      game,
      name: `${adj} площадка #${this.nameCounter}`,
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
      players: s.players.size,
      max_players: MAX_PLAYERS,
      created_at: s.createdAt,
      player_ids: [...s.players.keys()],
    };
  }

  playerCount(game) {
    let n = 0;
    for (const s of this.servers.values()) if (s.game === game) n += s.players.size;
    return n;
  }

  whereIs(userId) {
    const entry = this.byUser.get(userId);
    if (!entry) return null;
    return { server_id: entry.server.id, game: entry.server.game, server_name: entry.server.name };
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
  attach(ws, user) {
    const conn = { ws, user, player: null, server: null, lastChat: 0, chatBurst: 0 };
    const send = (msg) => {
      if (ws.readyState === 1) ws.send(JSON.stringify(msg));
    };
    conn.send = send;

    ws.on('message', (raw) => {
      let msg;
      try {
        msg = JSON.parse(raw.toString());
      } catch {
        return;
      }
      if (!msg || typeof msg !== 'object') return;
      try {
        this.handle(conn, msg);
      } catch (err) {
        this.log(`ws handler error: ${err.stack || err}`);
      }
    });
    ws.on('close', () => this.leave(conn));
    ws.on('error', () => {});
    send({ t: 'hello', you: publicUser(user) });
  }

  handle(conn, msg) {
    switch (msg.t) {
      case 'join':
        return this.join(conn, msg);
      case 'state':
        return this.state(conn, msg);
      case 'chat':
        return this.chat(conn, msg);
      case 'emote':
        if (conn.server && EMOTES.has(msg.e)) {
          this.broadcast(conn.server, { t: 'emote', id: conn.user.id, e: msg.e });
        }
        return;
      case 'ping':
        return conn.send({ t: 'pong', c: msg.c ?? 0, s: Date.now() });
      default:
    }
  }

  join(conn, msg) {
    if (conn.server) this.leave(conn);
    const game = GAMES[msg.game] ? msg.game : 'playground';
    let server;
    if (msg.server === 'new') {
      server = this.createServer(game);
    } else if (msg.server && msg.server !== 'auto') {
      server = this.servers.get(String(msg.server));
      if (!server) return conn.send({ t: 'error', code: 'not_found', m: 'Сервер уже закрылся' });
    } else {
      server = this.pickServer(game);
    }
    if (server.players.size >= MAX_PLAYERS) {
      return conn.send({ t: 'error', code: 'full', m: `Сервер заполнен (${MAX_PLAYERS}/${MAX_PLAYERS})` });
    }

    // One live session per account: the newest connection wins.
    const existing = this.byUser.get(conn.user.id);
    if (existing && existing.conn !== conn) {
      existing.conn.send({ t: 'kicked', m: 'Вы зашли в игру с другого устройства' });
      existing.conn.ws.close(4000, 'duplicate');
      this.leave(existing.conn);
    }

    const spawn = [(Math.random() - 0.5) * 6, 1, 8 + (Math.random() - 0.5) * 4];
    const player = {
      user: publicUser(conn.user),
      p: spawn,
      r: Math.PI,
      a: 'idle',
      dirty: true,
      conn,
    };
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
    this.broadcast(server, { t: 'sys', m: `${player.user.display_name} зашёл(ла) на площадку` }, conn.user.id);
    this.log(`${conn.user.username} joined ${server.id} (${server.players.size}/${MAX_PLAYERS})`);
  }

  state(conn, msg) {
    const pl = conn.player;
    if (!pl || !Array.isArray(msg.p)) return;
    pl.p = [finite(msg.p[0], WORLD_LIMIT), finite(msg.p[1], WORLD_LIMIT), finite(msg.p[2], WORLD_LIMIT)];
    pl.r = finite(msg.r, 100);
    pl.a = ANIMS.has(msg.a) ? msg.a : 'idle';
    pl.dirty = true;
  }

  chat(conn, msg) {
    if (!conn.server) return;
    const text = String(msg.m ?? '')
      .replace(/[\u0000-\u001f\u007f]/g, ' ')
      .trim()
      .slice(0, 200);
    if (!text) return;
    const now = Date.now();
    if (now - conn.lastChat > 5000) conn.chatBurst = 0;
    conn.chatBurst += 1;
    conn.lastChat = now;
    if (conn.chatBurst > 6) {
      return conn.send({ t: 'sys', m: 'Помедленнее, чат не успевает :)' });
    }
    this.broadcast(conn.server, {
      t: 'chat',
      id: conn.user.id,
      name: conn.user.display_name,
      m: text,
    });
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
      this.broadcast(server, { t: 'sys', m: `${player.user.display_name} ушёл(ла)` });
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

  broadcast(server, msg, exceptId = null) {
    const data = JSON.stringify(msg);
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
      if (states.length) this.broadcast(server, { t: 's', s: states });
    }
  }
}
