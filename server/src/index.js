import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';
import { WebSocketServer } from 'ws';
import { openDb } from './db.js';
import { createApi, clientIp } from './api.js';
import { pickLang, msg } from './i18n.js';
import { GameHub } from './game.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const PORT = Number(process.env.PORT || 7350);
const HOST = process.env.HOST || '127.0.0.1';
const DB_FILE = process.env.MELTIEW_DB || path.join(here, '..', 'data', 'meltiew.db');
const PUBLIC_DIR = process.env.MELTIEW_PUBLIC || path.join(here, '..', 'public');

const log = (...a) => console.log(new Date().toISOString(), ...a);

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
  '.apk': 'application/vnd.android.package-archive',
  '.json': 'application/json',
  '.glb': 'model/gltf-binary',
};

function serveStatic(req, res) {
  const url = new URL(req.url, 'http://local');
  let rel = decodeURIComponent(url.pathname);
  if (rel.endsWith('/')) rel += 'index.html';
  const file = path.normalize(path.join(PUBLIC_DIR, rel));
  if (!file.startsWith(path.normalize(PUBLIC_DIR))) {
    res.writeHead(403).end();
    return;
  }
  fs.stat(file, (err, st) => {
    if (err || !st.isFile()) {
      // Single-page site: extensionless paths (/play, /u/name) get the app shell.
      if (!path.extname(rel)) {
        const shell = path.join(PUBLIC_DIR, 'index.html');
        res.writeHead(200, { 'content-type': MIME['.html'], 'cache-control': 'no-cache' });
        fs.createReadStream(shell).pipe(res);
        return;
      }
      res.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' }).end('Not found');
      return;
    }
    res.writeHead(200, {
      'content-type': MIME[path.extname(file)] || 'application/octet-stream',
      'content-length': st.size,
      // Site code must never go stale after a deploy; images can be cached briefly.
      'cache-control': ['.html', '.js', '.css'].includes(path.extname(file)) ? 'no-cache' : 'public, max-age=300',
    });
    fs.createReadStream(file).pipe(res);
  });
}

export function startServer({ port = PORT, host = HOST, dbFile = DB_FILE, renderDir, owner } = {}) {
  const db = openDb(dbFile);
  const renders = renderDir || (dbFile === ':memory:' ? path.join(os.tmpdir(), `meltiew-renders-${process.pid}`) : path.join(path.dirname(dbFile), 'renders'));
  let api;
  const hub = new GameHub({
    log,
    loadBlocks: (id) => api.blockSet(id),
    loadFriends: (id) => api.friendSet(id),
    onJoin: (game) => api.countVisit(game),
  });
  api = createApi({ db, hub, renderDir: renders, owner });

  const server = http.createServer((req, res) => {
    if (req.url.startsWith('/api/')) {
      api.handle(req, res);
    } else if (req.method === 'GET' || req.method === 'HEAD') {
      serveStatic(req, res);
    } else {
      res.writeHead(405).end();
    }
  });

  const wss = new WebSocketServer({ noServer: true, maxPayload: 8 * 1024 });
  server.on('upgrade', (req, socket, head) => {
    const url = new URL(req.url, 'http://local');
    if (url.pathname !== '/ws') {
      socket.destroy();
      return;
    }
    const auth = api.userForToken(url.searchParams.get('token') || '');
    if (!auth) {
      socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
      socket.destroy();
      return;
    }
    wss.handleUpgrade(req, socket, head, (ws) => {
      const lang = url.searchParams.get('lang') === 'ru' ? 'ru' : pickLang(req);
      if (!api.gate.allows('app', url.searchParams.get('v'))) {
        ws.send(JSON.stringify({ t: 'kicked', code: 'update', m: msg('update_required', lang, { v: api.gate.min() }) }));
        ws.close(4003, 'update');
        return;
      }
      ws.isAlive = true;
      ws.on('pong', () => (ws.isAlive = true));
      log(`ws open ${auth.user.username} from ${clientIp(req)}`);
      hub.attach(ws, auth.user, lang);
    });
  });

  // Drop dead mobile connections so the 10-slot servers don't fill with ghosts.
  const heartbeat = setInterval(() => {
    for (const ws of wss.clients) {
      if (!ws.isAlive) {
        ws.terminate();
        continue;
      }
      ws.isAlive = false;
      ws.ping();
    }
  }, 15_000);
  heartbeat.unref();

  server.listen(port, host, () => log(`Meltiew server on http://${host}:${port}`));

  const close = () =>
    new Promise((resolve) => {
      clearInterval(heartbeat);
      hub.stop();
      wss.close();
      server.closeAllConnections?.();
      server.close(() => {
        db.close();
        resolve();
      });
    });
  return { server, hub, db, close };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const app = startServer();
  const shutdown = () => {
    log('shutting down');
    app.close().then(() => process.exit(0));
    setTimeout(() => process.exit(0), 3000).unref();
  };
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}
