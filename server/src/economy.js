// Meltiew economy: pieces (bought with money), orbs (earned by playing), the item
// shop, daily quests, gamepasses in places, payments through RollyPay, the legal
// pages' details and support tickets.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { CATALOG } from './accessories.js';
import { FACES } from './age.js';
import { decodeImage } from './studio/places.js';

// What pieces cost. The bigger packs add a little on top.
export const PACKS = [
  { id: 'p50', pieces: 50, rub: 49 },
  { id: 'p110', pieces: 110, rub: 99 },
  { id: 'p240', pieces: 240, rub: 199 },
  { id: 'p650', pieces: 650, rub: 499 },
  { id: 'p1400', pieces: 1400, rub: 999 },
];

// Everyone has these faces; the rest are bought.
export const FREE_FACES = [':D', ':)'];
export const FACE_PRICES = {
  ':3': { pieces: 10, orbs: 120 },
  ':P': { pieces: 8, orbs: 100 },
  ';)': { pieces: 8, orbs: 100 },
  ':O': { pieces: 8, orbs: 100 },
  xD: { pieces: 12, orbs: 150 },
  'B)': { pieces: 25 },
  '^_^': { pieces: 12, orbs: 150 },
  owo: { pieces: 19 },
  uwu: { pieces: 19 },
  '>_<': { pieces: 15, orbs: 180 },
  'T_T': { pieces: 10, orbs: 120 },
  '-_-': { pieces: 8, orbs: 100 },
  ':|': { pieces: 6, orbs: 80 },
  '<3': { pieces: 15 },
};

export const DAILY_ORBS = 15;
// A gamepass sale: the place's creator gets this share of the price as pieces
// (the platform keeps 5%).
export const CREATOR_SHARE = 0.95;
const QUESTS_PER_DAY = 3;
const MAX_PASSES_PER_PLACE = 30;
const PASS_IMAGE_BYTES = 1024 * 1024;

// Daily quests: three of these each day, a different mix per player.
export const QUESTS = [
  { id: 'playground10', kind: 'time_playground', target: 600, reward: 25, go: { type: 'place', id: 'playground' } },
  { id: 'friend', kind: 'with_friend', target: 1, reward: 30, go: { type: 'friends' } },
  { id: 'places3', kind: 'places', target: 3, reward: 25, go: { type: 'discover' } },
  { id: 'play30', kind: 'time', target: 1800, reward: 30, go: { type: 'discover' } },
  { id: 'like', kind: 'like', target: 1, reward: 10, go: { type: 'discover' } },
  { id: 'emotes5', kind: 'emote', target: 5, reward: 15, go: { type: 'place', id: 'playground' } },
];

/** The day in Moscow time (daily rewards and quests reset at midnight there). */
export const dayOf = (t = Date.now()) => new Date(t + 3 * 3600 * 1000).toISOString().slice(0, 10);

function hashNum(s) {
  return crypto.createHash('sha1').update(s).digest().readUInt32BE(0);
}

/** Price of an item: { pieces } or { orbs }, null when it's free. */
export function priceOf(kind, id) {
  if (kind === 'face') return FREE_FACES.includes(id) ? null : FACE_PRICES[id] || { pieces: 8, orbs: 100 };
  const it = CATALOG.items.find((i) => i.id === id);
  return it?.price || null;
}

export function createEconomy({ db, hub, mediaDir, HttpError, bad, cleanText, requireAuth, requireStaff, authenticate, writeLimiter, log = () => {} }) {
  fs.mkdirSync(path.join(mediaDir, 'passes'), { recursive: true });

  const q = {
    user: db.prepare('SELECT * FROM users WHERE id = ?'),
    addPieces: db.prepare('UPDATE users SET pieces = pieces + ? WHERE id = ? AND pieces + ? >= 0'),
    addOrbs: db.prepare('UPDATE users SET orbs = orbs + ? WHERE id = ? AND orbs + ? >= 0'),
    forcePieces: db.prepare('UPDATE users SET pieces = MAX(0, pieces + ?) WHERE id = ?'),
    log: db.prepare('INSERT INTO wallet_log (user_id, currency, delta, reason, ref, created_at) VALUES (?, ?, ?, ?, ?, ?)'),
    history: db.prepare('SELECT currency, delta, reason, ref, created_at FROM wallet_log WHERE user_id = ? ORDER BY id DESC LIMIT 50'),
    owned: db.prepare('SELECT kind, item_id FROM owned_items WHERE user_id = ?'),
    owns: db.prepare('SELECT 1 FROM owned_items WHERE user_id = ? AND kind = ? AND item_id = ?'),
    give: db.prepare('INSERT OR IGNORE INTO owned_items (user_id, kind, item_id, source, created_at) VALUES (?, ?, ?, ?, ?)'),
    daily: db.prepare('UPDATE users SET daily_day = ? WHERE id = ? AND daily_day != ?'),
    quest: db.prepare('SELECT * FROM quest_progress WHERE user_id = ? AND day = ? AND quest_id = ?'),
    questRow: db.prepare('INSERT OR IGNORE INTO quest_progress (user_id, day, quest_id, progress, claimed) VALUES (?, ?, ?, 0, 0)'),
    questAdd: db.prepare('UPDATE quest_progress SET progress = MIN(?, progress + ?) WHERE user_id = ? AND day = ? AND quest_id = ?'),
    questAtLeast: db.prepare('UPDATE quest_progress SET progress = MAX(progress, ?) WHERE user_id = ? AND day = ? AND quest_id = ?'),
    questClaim: db.prepare('UPDATE quest_progress SET claimed = 1 WHERE user_id = ? AND day = ? AND quest_id = ? AND claimed = 0 AND progress >= ?'),
    questPlace: db.prepare('INSERT OR IGNORE INTO quest_places (user_id, day, place_id) VALUES (?, ?, ?)'),
    questPlaces: db.prepare('SELECT COUNT(*) AS n FROM quest_places WHERE user_id = ? AND day = ?'),
    payInsert: db.prepare('INSERT INTO payments (id, user_id, pack_id, pieces, amount, status, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)'),
    pay: db.prepare('SELECT * FROM payments WHERE id = ?'),
    paySet: db.prepare('UPDATE payments SET status = ?, provider_id = COALESCE(?, provider_id), pay_url = COALESCE(?, pay_url), paid_at = ? WHERE id = ?'),
    payRecent: db.prepare('SELECT p.*, u.username FROM payments p JOIN users u ON u.id = p.user_id ORDER BY p.created_at DESC LIMIT 100'),
    payTotals: db.prepare("SELECT COUNT(*) AS n, COALESCE(SUM(CAST(amount AS REAL)), 0) AS rub FROM payments WHERE status = 'paid'"),
    config: db.prepare('SELECT value FROM config WHERE key = ?'),
    setConfig: db.prepare('INSERT INTO config (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value'),
    ticketInsert: db.prepare('INSERT INTO tickets (user_id, contact, subject, body, status, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)'),
    ticketsMine: db.prepare('SELECT * FROM tickets WHERE user_id = ? ORDER BY id DESC LIMIT 30'),
    ticketsAll: db.prepare("SELECT t.*, u.username FROM tickets t LEFT JOIN users u ON u.id = t.user_id ORDER BY (t.status = 'open') DESC, t.id DESC LIMIT 200"),
    ticket: db.prepare('SELECT * FROM tickets WHERE id = ?'),
    ticketReply: db.prepare('UPDATE tickets SET reply = ?, status = ?, updated_at = ? WHERE id = ?'),
    ticketsOpenBy: db.prepare("SELECT COUNT(*) AS n FROM tickets WHERE user_id = ? AND status = 'open'"),
    place: db.prepare('SELECT * FROM places WHERE id = ? AND deleted = 0'),
    passes: db.prepare('SELECT * FROM gamepasses WHERE place_id = ? AND deleted = 0 ORDER BY price, id'),
    pass: db.prepare('SELECT * FROM gamepasses WHERE id = ? AND deleted = 0'),
    passCount: db.prepare('SELECT COUNT(*) AS n FROM gamepasses WHERE place_id = ? AND deleted = 0'),
    passInsert: db.prepare('INSERT INTO gamepasses (place_id, name, description, price, image, created_at) VALUES (?, ?, ?, ?, ?, ?)'),
    passUpdate: db.prepare('UPDATE gamepasses SET name = ?, description = ?, price = ?, image = ? WHERE id = ?'),
    passDelete: db.prepare('UPDATE gamepasses SET deleted = 1 WHERE id = ?'),
    passSold: db.prepare('UPDATE gamepasses SET sales = sales + 1 WHERE id = ?'),
    passOwner: db.prepare('SELECT 1 FROM gamepass_owners WHERE pass_id = ? AND user_id = ?'),
    passGive: db.prepare('INSERT OR IGNORE INTO gamepass_owners (pass_id, user_id, created_at) VALUES (?, ?, ?)'),
    passesOwned: db.prepare('SELECT o.pass_id FROM gamepass_owners o JOIN gamepasses g ON g.id = o.pass_id WHERE o.user_id = ? AND g.place_id = ?'),
  };

  // --- wallet ---------------------------------------------------------------------

  function tx(fn) {
    db.exec('BEGIN IMMEDIATE');
    try {
      const out = fn();
      db.exec('COMMIT');
      return out;
    } catch (e) {
      db.exec('ROLLBACK');
      throw e;
    }
  }

  /** Adds (or takes, if negative) currency; throws not_enough if the balance would go below zero. */
  function change(userId, currency, delta, reason, ref = '') {
    delta = Math.trunc(delta);
    if (!delta) return;
    // The platform owner's pieces never run out: spending them takes nothing.
    if (currency === 'pieces' && delta < 0 && q.user.get(userId)?.role === 'owner') {
      q.log.run(userId, currency, delta, reason, String(ref), Date.now());
      return;
    }
    const stmt = currency === 'pieces' ? q.addPieces : q.addOrbs;
    if (stmt.run(delta, userId, delta).changes !== 1) throw new HttpError(402, currency === 'pieces' ? 'not_enough_pieces' : 'not_enough_orbs');
    q.log.run(userId, currency, delta, reason, String(ref), Date.now());
  }

  function wallet(userId) {
    const u = q.user.get(userId);
    return { pieces: u?.pieces || 0, orbs: u?.orbs || 0, ...(u?.role === 'owner' ? { infinite: true } : {}) };
  }

  function ownedOf(userId) {
    const out = { accessories: [], faces: [...FREE_FACES] };
    for (const r of q.owned.all(userId)) {
      if (r.kind === 'accessory') out.accessories.push(r.item_id);
      else if (r.kind === 'face' && !out.faces.includes(r.item_id)) out.faces.push(r.item_id);
    }
    return out;
  }

  const owns = (userId, kind, id) => (kind === 'face' && FREE_FACES.includes(id)) || !!q.owns.get(userId, kind, id);

  /** First visit of the day: a few orbs. Returns how many were given (0 if already today). */
  function claimDaily(userId) {
    const day = dayOf();
    if (q.daily.run(day, userId, day).changes !== 1) return 0;
    change(userId, 'orbs', DAILY_ORBS, 'daily', day);
    return DAILY_ORBS;
  }

  // --- quests ---------------------------------------------------------------------

  function questsOf(userId, day = dayOf()) {
    const pool = [...QUESTS];
    const picked = [];
    let seed = hashNum(`${userId}:${day}`);
    while (picked.length < QUESTS_PER_DAY && pool.length) {
      picked.push(pool.splice(seed % pool.length, 1)[0]);
      seed = Math.floor(seed / 7) + 13;
    }
    return picked;
  }

  function questView(userId) {
    const day = dayOf();
    return questsOf(userId, day).map((qq) => {
      const row = q.quest.get(userId, day, qq.id);
      const progress = qq.kind === 'places' ? q.questPlaces.get(userId, day).n : row?.progress || 0;
      return { id: qq.id, target: qq.target, reward: qq.reward, progress: Math.min(progress, qq.target), claimed: !!row?.claimed, go: qq.go };
    });
  }

  /** Something that counts towards quests happened. */
  function progress(userId, kind, amount = 1, placeId = '') {
    const day = dayOf();
    for (const qq of questsOf(userId, day)) {
      if (qq.kind !== kind) continue;
      q.questRow.run(userId, day, qq.id);
      if (kind === 'places') {
        if (placeId) q.questPlace.run(userId, day, placeId);
        q.questAtLeast.run(Math.min(q.questPlaces.get(userId, day).n, qq.target), userId, day, qq.id);
      } else {
        q.questAdd.run(qq.target, amount, userId, day, qq.id);
      }
    }
  }

  // Once a minute: playtime for everyone in a game, and "played with a friend".
  const minute = setInterval(() => {
    try {
      for (const s of hub.sessions()) {
        for (const id of s.players) {
          progress(id, 'time', 60);
          if (s.game === 'playground') progress(id, 'time_playground', 60);
          if (s.players.length > 1) {
            const friends = s.friendsOf(id);
            if (s.players.some((o) => o !== id && friends.has(o))) progress(id, 'with_friend', 1);
          }
        }
      }
    } catch (e) {
      log(`quest tick failed: ${e.message}`);
    }
  }, 60_000);
  minute.unref();

  // --- payments (RollyPay) --------------------------------------------------------

  const cfg = (key, env) => q.config.get(key)?.value || process.env[env] || '';
  const payConfig = () => ({
    apiKey: cfg('rollypay_api_key', 'ROLLYPAY_API_KEY'),
    secret: cfg('rollypay_secret', 'ROLLYPAY_SIGNING_SECRET'),
    test: cfg('rollypay_test', 'ROLLYPAY_TEST') === '1',
    base: cfg('rollypay_base', 'ROLLYPAY_BASE') || 'https://rollypay.io/api/v1',
    site: cfg('site_url', 'MELTIEW_SITE') || 'https://meltiew.narez.xyz',
  });
  const paymentsOn = () => !!(payConfig().apiKey && payConfig().secret);

  async function createPayment(user, packId) {
    const pack = PACKS.find((p) => p.id === packId);
    if (!pack) throw bad('bad_pack');
    const c = payConfig();
    if (!c.apiKey || !c.secret) throw new HttpError(503, 'payments_off');
    const id = 'mp' + crypto.randomBytes(8).toString('hex');
    const amount = pack.rub.toFixed(2);
    q.payInsert.run(id, user.id, pack.id, pack.pieces, amount, 'created', Date.now());
    let res;
    try {
      res = await fetch(`${c.base}/payments`, {
        method: 'POST',
        headers: { 'content-type': 'application/json', 'x-api-key': c.apiKey, 'x-nonce': crypto.randomUUID() },
        body: JSON.stringify({
          amount,
          payment_currency: 'RUB',
          order_id: id,
          description: `Meltiew: ${pack.pieces} pieces for ${user.username}`,
          customer_id: String(user.id),
          success_redirect_url: `${c.site}/wallet?paid=${id}`,
          fail_redirect_url: `${c.site}/wallet?failed=${id}`,
          metadata: { user_id: user.id, pack: pack.id },
          ...(c.test ? { test: true } : {}),
        }),
        signal: AbortSignal.timeout(15_000),
      });
    } catch (e) {
      log(`rollypay create failed: ${e.message}`);
      q.paySet.run('failed', null, null, 0, id);
      throw new HttpError(502, 'payments_down');
    }
    const data = await res.json().catch(() => ({}));
    if (!res.ok || !data.pay_url) {
      log(`rollypay create ${res.status}: ${JSON.stringify(data).slice(0, 300)}`);
      q.paySet.run('failed', null, null, 0, id);
      throw new HttpError(502, 'payments_down');
    }
    q.paySet.run('created', String(data.payment_id || ''), String(data.pay_url), 0, id);
    return { id, pay_url: data.pay_url };
  }

  function validSignature(raw, ts, sig, secret) {
    if (!raw || !ts || !sig || !secret) return false;
    // Old or future timestamps are replays.
    const t = Number(ts);
    if (!Number.isFinite(t) || Math.abs(Date.now() / 1000 - (t > 1e12 ? t / 1000 : t)) > 60 * 60) return false;
    const mac = crypto.createHmac('sha256', secret).update(`${ts}.${raw}`).digest();
    const given = String(sig).replace(/^sha256=/, '').trim();
    for (const enc of ['hex', 'base64']) {
      const expect = Buffer.from(mac.toString(enc));
      const got = Buffer.from(given);
      if (expect.length === got.length && crypto.timingSafeEqual(expect, got)) return true;
    }
    return false;
  }

  /** RollyPay tells us a payment changed. Credits pieces exactly once. */
  function paymentCallback(req, body) {
    const c = payConfig();
    const raw = req.rawBody || '';
    if (!validSignature(raw, req.headers['x-timestamp'], req.headers['x-signature'], c.secret)) {
      log('rollypay callback with a bad signature');
      throw new HttpError(401, 'bad_signature');
    }
    if (req.headers['x-test-mode'] === 'true' && !c.test) return { ok: true, ignored: 'test' };
    const pay = q.pay.get(String(body.order_id || ''));
    if (!pay) return { ok: true, ignored: 'unknown' };
    const status = String(body.status || '');
    if (status === 'paid' && pay.status !== 'paid') {
      if (String(Number(body.amount).toFixed(2)) !== String(Number(pay.amount).toFixed(2)) || String(body.currency || 'RUB') !== 'RUB') {
        log(`rollypay amount mismatch on ${pay.id}: ${body.amount} ${body.currency}`);
        throw new HttpError(400, 'bad_amount');
      }
      tx(() => {
        q.paySet.run('paid', String(body.payment_id || ''), null, Date.now(), pay.id);
        change(pay.user_id, 'pieces', pay.pieces, 'purchase', pay.id);
      });
      log(`payment ${pay.id}: +${pay.pieces} pieces for user ${pay.user_id}`);
      hub.notifyWallet?.(pay.user_id, wallet(pay.user_id));
    } else if ((status === 'chargeback' || status === 'refunded') && pay.status === 'paid') {
      tx(() => {
        q.paySet.run(status, null, null, pay.paid_at || 0, pay.id);
        q.forcePieces.run(-pay.pieces, pay.user_id);
        q.log.run(pay.user_id, 'pieces', -pay.pieces, status, pay.id, Date.now());
      });
    } else if (['canceled', 'expired'].includes(status) && pay.status !== 'paid') {
      q.paySet.run(status, null, null, 0, pay.id);
    }
    return { ok: true };
  }

  // --- gamepasses -----------------------------------------------------------------

  const passView = (p, userId) => ({
    id: p.id,
    place_id: p.place_id,
    name: p.name,
    description: p.description,
    price: p.price,
    image: p.image ? `/api/passes/${p.id}/image?v=${encodeURIComponent(p.image)}` : '',
    sales: p.sales,
    owned: userId ? !!q.passOwner.get(p.id, userId) : false,
  });

  function ownPlace(req, placeId) {
    const auth = requireAuth(req);
    const row = q.place.get(placeId);
    if (!row || row.kind !== 'studio') throw new HttpError(404, 'no_place');
    if (!hub.canEditPlace?.(auth.user, row) && row.owner_id !== auth.user.id && auth.user.role !== 'owner' && auth.user.role !== 'admin') {
      throw new HttpError(403, 'forbidden');
    }
    return { ...auth, row };
  }

  function savePassImage(b64) {
    const img = decodeImage(b64, PASS_IMAGE_BYTES, 1024);
    if (!img) throw bad('bad_image');
    const name = crypto.randomBytes(8).toString('hex') + '.' + img.ext;
    fs.writeFileSync(path.join(mediaDir, 'passes', name), img.buf);
    return name;
  }

  function cleanPrice(v) {
    const n = Math.floor(Number(v));
    if (!Number.isFinite(n) || n < 1 || n > 100000) throw bad('bad_price');
    return n;
  }

  function buyPass(user, passId) {
    const pass = q.pass.get(passId);
    if (!pass) throw new HttpError(404, 'no_pass');
    if (q.passOwner.get(pass.id, user.id)) return { already: true };
    const place = q.place.get(pass.place_id);
    if (!place) throw new HttpError(404, 'no_place');
    tx(() => {
      change(user.id, 'pieces', -pass.price, 'gamepass', pass.id);
      q.passGive.run(pass.id, user.id, Date.now());
      q.passSold.run(pass.id);
      if (place.owner_id && place.owner_id !== user.id) change(place.owner_id, 'pieces', Math.floor(pass.price * CREATOR_SHARE), 'gamepass_sale', pass.id);
    });
    hub.passBought?.(user.id, pass.place_id, pass.id);
    return { already: false };
  }

  // --- support / legal --------------------------------------------------------------

  const LEGAL_KEYS = ['operator_name', 'operator_inn', 'support_email', 'support_telegram'];
  const legal = () => Object.fromEntries(LEGAL_KEYS.map((k) => [k, q.config.get(k)?.value || '']));

  // --- routes -----------------------------------------------------------------------

  const isOwner = (u) => u.role === 'owner';

  const routes = {
    'GET /api/shop': (req) => {
      const auth = authenticate(req);
      const uid = auth?.user.id;
      const owned = uid ? ownedOf(uid) : { accessories: [], faces: [...FREE_FACES] };
      return {
        accessories: CATALOG.items.map((it) => ({ id: it.id, name: it.name, slot: it.slot, price: it.price || null, owned: owned.accessories.includes(it.id) })),
        faces: FACES.map((f) => ({ id: f, price: priceOf('face', f), owned: owned.faces.includes(f) })),
        packs: PACKS,
        payments: paymentsOn(),
        wallet: uid ? wallet(uid) : null,
      };
    },

    'POST /api/shop/buy': (req, body) => {
      const { user } = requireAuth(req);
      if (!writeLimiter.allow('buy:' + user.id)) throw new HttpError(429, 'slow_down');
      const kind = body.kind === 'face' ? 'face' : 'accessory';
      const id = String(body.id || '');
      if (kind === 'face' ? !FACES.includes(id) : !CATALOG.items.some((i) => i.id === id)) throw new HttpError(404, 'no_item');
      const price = priceOf(kind, id);
      if (!price || owns(user.id, kind, id)) return { wallet: wallet(user.id), owned: ownedOf(user.id) };
      // Everything has a price in pieces; some items can be taken for orbs instead.
      const currency = body.currency === 'orbs' ? 'orbs' : body.currency === 'pieces' ? 'pieces' : price.pieces ? 'pieces' : 'orbs';
      if (!price[currency]) throw bad('not_for_' + currency);
      tx(() => {
        change(user.id, currency, -price[currency], 'buy_' + kind, id);
        q.give.run(user.id, kind, id, 'shop', Date.now());
      });
      return { wallet: wallet(user.id), owned: ownedOf(user.id) };
    },

    'GET /api/me/wallet': (req) => {
      const { user } = requireAuth(req);
      return { wallet: wallet(user.id), history: q.history.all(user.id) };
    },

    'GET /api/quests': (req) => {
      const { user } = requireAuth(req);
      return { quests: questView(user.id), daily_orbs: DAILY_ORBS, wallet: wallet(user.id) };
    },

    'POST /api/quests/:id/claim': (req, _b, _u, params) => {
      const { user } = requireAuth(req);
      const day = dayOf();
      const qq = questsOf(user.id, day).find((x) => x.id === params.id);
      if (!qq) throw new HttpError(404, 'no_quest');
      const view = questView(user.id).find((x) => x.id === qq.id);
      if (view.claimed) return { quests: questView(user.id), wallet: wallet(user.id) };
      if (view.progress < qq.target) throw bad('quest_not_done');
      tx(() => {
        // "places" keeps its count elsewhere; make sure the row exists before claiming.
        q.questRow.run(user.id, day, qq.id);
        q.questAtLeast.run(view.progress, user.id, day, qq.id);
        if (q.questClaim.run(user.id, day, qq.id, qq.target).changes === 1) change(user.id, 'orbs', qq.reward, 'quest', qq.id);
      });
      return { quests: questView(user.id), wallet: wallet(user.id) };
    },

    'GET /api/pay/packs': () => ({ packs: PACKS, payments: paymentsOn() }),

    'POST /api/pay': async (req, body) => {
      const { user } = requireAuth(req);
      if (!writeLimiter.allow('pay:' + user.id)) throw new HttpError(429, 'slow_down');
      return createPayment(user, String(body.pack || ''));
    },

    'GET /api/pay/:id': (req, _b, _u, params) => {
      const { user } = requireAuth(req);
      const p = q.pay.get(params.id);
      if (!p || p.user_id !== user.id) throw new HttpError(404, 'not_found');
      return { id: p.id, status: p.status, pieces: p.pieces, amount: p.amount, wallet: wallet(user.id) };
    },

    'POST /api/payments/rollypay/callback': (req, body) => paymentCallback(req, body),

    // Gamepasses
    'GET /api/places/:id/passes': (req, _b, _u, params) => {
      const uid = authenticate(req)?.user.id;
      return { passes: q.passes.all(params.id).map((p) => passView(p, uid)) };
    },

    'POST /api/studio/places/:id/passes': (req, body, _u, params) => {
      const { row } = ownPlace(req, params.id);
      if (q.passCount.get(row.id).n >= MAX_PASSES_PER_PLACE) throw bad('too_many_passes');
      const name = cleanText(body.name, 50);
      if (name.length < 2) throw bad('bad_name');
      const image = body.image ? savePassImage(body.image) : '';
      const info = q.passInsert.run(row.id, name, cleanText(body.description, 300), cleanPrice(body.price), image, Date.now());
      return { pass: passView(q.pass.get(Number(info.lastInsertRowid)), null) };
    },

    'PATCH /api/studio/places/:id/passes/:pid': (req, body, _u, params) => {
      const { row } = ownPlace(req, params.id);
      const pass = q.pass.get(Number(params.pid));
      if (!pass || pass.place_id !== row.id) throw new HttpError(404, 'no_pass');
      const name = body.name !== undefined ? cleanText(body.name, 50) : pass.name;
      if (name.length < 2) throw bad('bad_name');
      const image = body.image ? savePassImage(body.image) : pass.image;
      q.passUpdate.run(name, body.description !== undefined ? cleanText(body.description, 300) : pass.description,
        body.price !== undefined ? cleanPrice(body.price) : pass.price, image, pass.id);
      return { pass: passView(q.pass.get(pass.id), null) };
    },

    'DELETE /api/studio/places/:id/passes/:pid': (req, _b, _u, params) => {
      const { row } = ownPlace(req, params.id);
      const pass = q.pass.get(Number(params.pid));
      if (!pass || pass.place_id !== row.id) throw new HttpError(404, 'no_pass');
      q.passDelete.run(pass.id);
      return { ok: true };
    },

    'GET /api/passes/:pid/image': (_req, _b, _u, params) => {
      const pass = db.prepare('SELECT image FROM gamepasses WHERE id = ?').get(Number(params.pid));
      if (!pass?.image || !/^[0-9a-f]{16}\.(png|jpg)$/.test(pass.image)) throw new HttpError(404, 'not_found');
      const file = path.join(mediaDir, 'passes', pass.image);
      if (!fs.existsSync(file)) throw new HttpError(404, 'not_found');
      return { __raw: { type: pass.image.endsWith('.png') ? 'image/png' : 'image/jpeg', cache: 'public, max-age=86400', body: fs.readFileSync(file) } };
    },

    'POST /api/passes/:pid/buy': (req, _b, _u, params) => {
      const { user } = requireAuth(req);
      if (!writeLimiter.allow('buy:' + user.id)) throw new HttpError(429, 'slow_down');
      buyPass(user, Number(params.pid));
      const pass = q.pass.get(Number(params.pid));
      return { pass: passView(pass, user.id), wallet: wallet(user.id) };
    },

    // Legal pages and support
    'GET /api/legal': () => legal(),

    'POST /api/support': (req, body) => {
      const auth = authenticate(req);
      const key = 'ticket:' + (auth ? auth.user.id : req.socket.remoteAddress);
      if (!writeLimiter.allow(key) || !writeLimiter.allow(key + ':2')) throw new HttpError(429, 'slow_down');
      if (auth && q.ticketsOpenBy.get(auth.user.id).n >= 5) throw bad('too_many_tickets');
      const subject = cleanText(body.subject, 120);
      const text = String(body.body ?? '').replace(/[\u0000-\u0008\u000b-\u001f]/g, '').trim().slice(0, 4000);
      const contact = cleanText(body.contact, 120);
      if (subject.length < 3 || text.length < 5) throw bad('ticket_short');
      if (!auth && contact.length < 3) throw bad('ticket_contact');
      const now = Date.now();
      q.ticketInsert.run(auth ? auth.user.id : null, contact, subject, text, 'open', now, now);
      return { ok: true };
    },

    'GET /api/support': (req) => {
      const { user } = requireAuth(req);
      return { tickets: q.ticketsMine.all(user.id) };
    },

    // Admin
    'GET /api/admin/tickets': (req) => {
      requireStaff(req);
      return { tickets: q.ticketsAll.all() };
    },

    'POST /api/admin/tickets/:id': (req, body, _u, params) => {
      requireStaff(req);
      const t = q.ticket.get(Number(params.id));
      if (!t) throw new HttpError(404, 'not_found');
      q.ticketReply.run(String(body.reply ?? t.reply ?? '').slice(0, 4000), body.status === 'open' ? 'open' : 'closed', Date.now(), t.id);
      return { ticket: q.ticket.get(t.id) };
    },

    'GET /api/admin/payments': (req) => {
      const { user } = requireStaff(req);
      const c = payConfig();
      return {
        payments: q.payRecent.all(),
        totals: q.payTotals.get(),
        config: isOwner(user) ? { api_key_set: !!c.apiKey, secret_set: !!c.secret, test: c.test, site: c.site, callback: `${c.site}/api/payments/rollypay/callback` } : null,
        legal: legal(),
      };
    },

    // Keys and the legal details are set from the admin panel (owner only).
    'POST /api/admin/payments/config': (req, body) => {
      const { user } = requireStaff(req);
      if (!isOwner(user)) throw new HttpError(403, 'forbidden');
      if (typeof body.api_key === 'string' && body.api_key.trim()) q.setConfig.run('rollypay_api_key', body.api_key.trim());
      if (typeof body.secret === 'string' && body.secret.trim()) q.setConfig.run('rollypay_secret', body.secret.trim());
      if (body.test !== undefined) q.setConfig.run('rollypay_test', body.test ? '1' : '0');
      if (typeof body.site === 'string' && /^https?:\/\/[^\s/]+$/.test(body.site.trim())) q.setConfig.run('site_url', body.site.trim());
      for (const k of LEGAL_KEYS) if (typeof body[k] === 'string') q.setConfig.run(k, cleanText(body[k], 200));
      return { ok: true };
    },

    // Give (or take, with a negative number) pieces or orbs to anyone.
    'POST /api/admin/wallet': (req, body) => {
      const { user } = requireStaff(req);
      if (!isOwner(user)) throw new HttpError(403, 'forbidden');
      const target = body.username ? db.prepare('SELECT * FROM users WHERE username = ?').get(String(body.username)) : q.user.get(Number(body.user_id));
      if (!target) throw new HttpError(404, 'no_user');
      const currency = body.currency === 'orbs' ? 'orbs' : 'pieces';
      change(target.id, currency, Number(body.delta) || 0, 'admin', user.username);
      return { wallet: wallet(target.id) };
    },
  };

  return {
    routes,
    change,
    wallet,
    ownedOf,
    owns,
    claimDaily,
    progress,
    passesOwned: (userId, placeId) => q.passesOwned.all(userId, placeId).map((r) => r.pass_id),
    passesInfo: (placeId) => q.passes.all(placeId).map((p) => ({ id: p.id, name: p.name, price: p.price })),
    stop: () => clearInterval(minute),
  };
}

/** Economy tables; runs with the other migrations, before any query is prepared. */
export function migrateEconomy(db) {
  const cols = new Set(db.prepare('PRAGMA table_info(users)').all().map((c) => c.name));
  if (!cols.has('pieces')) db.exec('ALTER TABLE users ADD COLUMN pieces INTEGER NOT NULL DEFAULT 0');
  if (!cols.has('orbs')) db.exec('ALTER TABLE users ADD COLUMN orbs INTEGER NOT NULL DEFAULT 0');
  if (!cols.has('daily_day')) db.exec("ALTER TABLE users ADD COLUMN daily_day TEXT NOT NULL DEFAULT ''");
  db.exec(`
    CREATE TABLE IF NOT EXISTS owned_items (
      user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      kind       TEXT NOT NULL,
      item_id    TEXT NOT NULL,
      source     TEXT NOT NULL DEFAULT '',
      created_at INTEGER NOT NULL,
      PRIMARY KEY (user_id, kind, item_id)
    );
    CREATE TABLE IF NOT EXISTS wallet_log (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      currency   TEXT NOT NULL,
      delta      INTEGER NOT NULL,
      reason     TEXT NOT NULL,
      ref        TEXT NOT NULL DEFAULT '',
      created_at INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS wallet_log_user ON wallet_log(user_id, id);
    CREATE TABLE IF NOT EXISTS payments (
      id          TEXT PRIMARY KEY,
      user_id     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      pack_id     TEXT NOT NULL,
      pieces      INTEGER NOT NULL,
      amount      TEXT NOT NULL,
      status      TEXT NOT NULL,
      provider_id TEXT,
      pay_url     TEXT,
      created_at  INTEGER NOT NULL,
      paid_at     INTEGER NOT NULL DEFAULT 0
    );
    CREATE TABLE IF NOT EXISTS quest_progress (
      user_id  INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      day      TEXT NOT NULL,
      quest_id TEXT NOT NULL,
      progress INTEGER NOT NULL DEFAULT 0,
      claimed  INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (user_id, day, quest_id)
    );
    CREATE TABLE IF NOT EXISTS quest_places (
      user_id  INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      day      TEXT NOT NULL,
      place_id TEXT NOT NULL,
      PRIMARY KEY (user_id, day, place_id)
    );
    CREATE TABLE IF NOT EXISTS gamepasses (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      place_id    TEXT NOT NULL,
      name        TEXT NOT NULL,
      description TEXT NOT NULL DEFAULT '',
      price       INTEGER NOT NULL,
      image       TEXT NOT NULL DEFAULT '',
      sales       INTEGER NOT NULL DEFAULT 0,
      deleted     INTEGER NOT NULL DEFAULT 0,
      created_at  INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS gamepasses_place ON gamepasses(place_id);
    CREATE TABLE IF NOT EXISTS gamepass_owners (
      pass_id    INTEGER NOT NULL REFERENCES gamepasses(id),
      user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      created_at INTEGER NOT NULL,
      PRIMARY KEY (pass_id, user_id)
    );
    CREATE TABLE IF NOT EXISTS tickets (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id    INTEGER REFERENCES users(id) ON DELETE SET NULL,
      contact    TEXT NOT NULL DEFAULT '',
      subject    TEXT NOT NULL,
      body       TEXT NOT NULL,
      reply      TEXT NOT NULL DEFAULT '',
      status     TEXT NOT NULL DEFAULT 'open',
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    );
    CREATE TABLE IF NOT EXISTS datastore (
      place_id   TEXT NOT NULL,
      store      TEXT NOT NULL,
      key        TEXT NOT NULL,
      value      TEXT NOT NULL,
      updated_at INTEGER NOT NULL,
      PRIMARY KEY (place_id, store, key)
    );
  `);
  // Once, when the shop opened: everyone keeps what they were already wearing.
  const done = db.prepare("SELECT value FROM config WHERE key = 'economy_v1'").get();
  if (!done) {
    const now = Date.now();
    const give = db.prepare("INSERT OR IGNORE INTO owned_items (user_id, kind, item_id, source, created_at) VALUES (?, ?, ?, 'grandfathered', ?)");
    for (const u of db.prepare('SELECT id, accessories, hat, face FROM users').all()) {
      let worn = [];
      try {
        worn = JSON.parse(u.accessories || '[]');
      } catch {}
      if (!Array.isArray(worn)) worn = [];
      if (u.hat && u.hat !== 'none') worn.push(u.hat);
      for (const id of new Set(worn.map(String))) give.run(u.id, 'accessory', id, now);
      if (u.face && !FREE_FACES.includes(u.face)) give.run(u.id, 'face', u.face, now);
    }
    db.prepare("INSERT INTO config (key, value) VALUES ('economy_v1', ?)").run(String(now));
  }
}
