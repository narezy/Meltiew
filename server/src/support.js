// Support: requests from the site's form and letters to support@narez.xyz, in one inbox in
// the admin panel. A ticket is a conversation: the team's replies go out by email (to
// letters, and to site requests that left an email as the contact), and the person's
// answers to that email come back into the same ticket.
//
// Postfix hands each letter for support@ to support_in.js, which only drops it into
// <dir>/in; pickUp() files them every few seconds.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { normalizeEmail } from './mail.js';

const MAX_TEXT = 20000;
const MAX_FILES = 10;
const MAX_FILE = 15 * 1024 * 1024;
const PER_SENDER_DAY = 20;
// Attachments the browser may show as pictures; everything else only downloads.
const IMAGE_TYPES = new Set(['image/png', 'image/jpeg', 'image/gif', 'image/webp']);

// --- reading letters ----------------------------------------------------------------------

function decodeBytes(buf, charset = 'utf-8') {
  const cs = String(charset || 'utf-8').trim().replace(/^"|"$/g, '').split('*')[0].toLowerCase();
  try {
    return new TextDecoder(cs).decode(buf);
  } catch {
    return new TextDecoder('utf-8').decode(buf);
  }
}

// Header text: UTF-8 if it is (newer mailers send it raw), Latin-1 otherwise.
function headerText(buf) {
  try {
    return new TextDecoder('utf-8', { fatal: true }).decode(buf);
  } catch {
    return buf.toString('latin1');
  }
}

/** "=?utf-8?B?...?=" words (RFC 2047); neighbouring words of one charset are joined first,
 *  since some mailers split a letter's bytes between them. */
export function decodeWords(s) {
  const re = /=\?([^?\s]+)\?([bBqQ])\?([^?\s]*)\?=/g;
  const out = [];
  let last = 0;
  let run = null; // { charset, bytes[] }
  const flush = () => {
    if (run) out.push(decodeBytes(Buffer.concat(run.bytes), run.charset));
    run = null;
  };
  for (let m; (m = re.exec(s)); ) {
    const between = s.slice(last, m.index);
    // Only whitespace between two encoded words: it isn't part of the text.
    if (!(run && /^\s*$/.test(between))) {
      flush();
      out.push(between);
    }
    const [, charset, enc, data] = m;
    const bytes = /b/i.test(enc)
      ? Buffer.from(data, 'base64')
      : Buffer.from(data.replace(/_/g, ' ').replace(/=([0-9a-f]{2})/gi, (_, h) => String.fromCharCode(parseInt(h, 16))), 'latin1');
    if (run && run.charset.toLowerCase() !== charset.toLowerCase()) flush();
    if (!run) run = { charset, bytes: [] };
    run.bytes.push(bytes);
    last = m.index + m[0].length;
  }
  flush();
  out.push(s.slice(last));
  return out.join('');
}

function splitHead(buf) {
  // A part with no headers starts with the empty line.
  if (buf[0] === 0x0a) return { head: '', body: buf.subarray(1) };
  if (buf[0] === 0x0d && buf[1] === 0x0a) return { head: '', body: buf.subarray(2) };
  let i = buf.indexOf('\r\n\r\n');
  let sep = 4;
  const j = buf.indexOf('\n\n');
  if (i < 0 || (j >= 0 && j < i)) {
    i = j;
    sep = 2;
  }
  if (i < 0) return { head: headerText(buf), body: Buffer.alloc(0) };
  return { head: headerText(buf.subarray(0, i)), body: buf.subarray(i + sep) };
}

function headerMap(head) {
  const map = new Map();
  for (const line of head.replace(/\r?\n[ \t]+/g, ' ').split(/\r?\n/)) {
    const i = line.indexOf(':');
    if (i <= 0) continue;
    const k = line.slice(0, i).trim().toLowerCase();
    if (!map.has(k)) map.set(k, []);
    map.get(k).push(line.slice(i + 1).trim());
  }
  return { get: (k) => map.get(k)?.[0] ?? '', all: (k) => map.get(k) ?? [] };
}

/** "text/plain; charset=utf-8; name*=utf-8''%D0%A4" -> { value, params } (with RFC 2231). */
export function headerParams(value) {
  const parts = [];
  let cur = '';
  let quoted = false;
  for (const ch of String(value)) {
    if (ch === '"') quoted = !quoted;
    if (ch === ';' && !quoted) {
      parts.push(cur);
      cur = '';
    } else cur += ch;
  }
  parts.push(cur);
  const main = parts.shift().trim().toLowerCase();
  const params = {};
  const pieces = {};
  for (const p of parts) {
    const i = p.indexOf('=');
    if (i < 0) continue;
    const key = p.slice(0, i).trim().toLowerCase();
    let v = p.slice(i + 1).trim();
    if (v.startsWith('"') && v.endsWith('"')) v = v.slice(1, -1).replace(/\\(.)/g, '$1');
    const m = /^([^*]+)(?:\*(\d+))?(\*)?$/.exec(key);
    if (!m) continue;
    const [, name, idx, enc] = m;
    if (idx === undefined && !enc) params[name] = decodeWords(v);
    else (pieces[name] ||= []).push({ i: Number(idx || 0), v, enc: !!enc });
  }
  for (const [name, list] of Object.entries(pieces)) {
    list.sort((a, b) => a.i - b.i);
    let charset = 'utf-8';
    const bytes = list.map((p, n) => {
      let v = p.v;
      if (!p.enc) return Buffer.from(v, 'latin1');
      if (n === 0) {
        const m = /^([^']*)'[^']*'(.*)$/.exec(v);
        if (m) {
          charset = m[1] || 'utf-8';
          v = m[2];
        }
      }
      return Buffer.from(v.replace(/%([0-9a-f]{2})/gi, (_, h) => String.fromCharCode(parseInt(h, 16))), 'latin1');
    });
    params[name] = decodeBytes(Buffer.concat(bytes), charset);
  }
  return { value: main, params };
}

function decodeTransfer(body, cte) {
  if (cte === 'base64') return Buffer.from(body.toString('latin1').replace(/[^A-Za-z0-9+/=]/g, ''), 'base64');
  if (cte === 'quoted-printable') {
    const s = body.toString('latin1').replace(/=\r?\n/g, '').replace(/=([0-9a-f]{2})/gi, (_, h) => String.fromCharCode(parseInt(h, 16)));
    return Buffer.from(s, 'latin1');
  }
  return body;
}

function splitMultipart(body, boundary) {
  const s = body.toString('latin1'); // one char per byte: indexes match the buffer
  const delim = '--' + boundary;
  // A delimiter line: "--boundary" at a line start, "--" after it on the last one, then
  // nothing but spaces (an inner boundary may begin with the outer one).
  const find = (from) => {
    for (let i = s.indexOf(delim, from); i >= 0; i = s.indexOf(delim, i + 1)) {
      if (i > 0 && s[i - 1] !== '\n') continue;
      const eol = s.indexOf('\n', i);
      const tail = s.slice(i + delim.length, eol < 0 ? s.length : eol);
      if (/^(--)?[ \t\r]*$/.test(tail)) return { at: i, close: tail.startsWith('--'), next: eol < 0 ? s.length : eol + 1 };
    }
    return null;
  };
  const parts = [];
  let d = find(0);
  while (d && !d.close) {
    const n = find(d.next);
    if (!n) {
      parts.push(body.subarray(d.next));
      break;
    }
    // The line break before a delimiter belongs to the delimiter.
    let end = n.at;
    if (end > d.next && s[end - 1] === '\n') end -= 1;
    if (end > d.next && s[end - 1] === '\r') end -= 1;
    parts.push(body.subarray(d.next, end));
    d = n;
  }
  return parts;
}

function walk(buf, out, depth) {
  const { head, body } = splitHead(buf);
  const h = headerMap(head);
  const ct = headerParams(h.get('content-type') || 'text/plain');
  const cte = h.get('content-transfer-encoding').toLowerCase();
  if (ct.value.startsWith('multipart/') && ct.params.boundary && depth < 12) {
    for (const part of splitMultipart(body, ct.params.boundary)) walk(part, out, depth + 1);
    return;
  }
  const data = decodeTransfer(body, cte);
  const cd = headerParams(h.get('content-disposition') || '');
  const name = cd.params.filename || ct.params.name || '';
  if ((ct.value === 'text/plain' || ct.value === 'text/html') && cd.value !== 'attachment' && !name) {
    (ct.value === 'text/plain' ? out.plain : out.html).push(decodeBytes(data, ct.params.charset));
    return;
  }
  const ext = { 'message/rfc822': '.eml', 'text/plain': '.txt', 'text/html': '.html' }[ct.value] || '';
  out.files.push({ name: name || `file${out.files.length + 1}${ext}`, type: ct.value || 'application/octet-stream', data });
}

const ENTITIES = { nbsp: ' ', amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", laquo: '«', raquo: '»', mdash: '—', ndash: '–', hellip: '…' };

/** An HTML-only letter as plain text: line breaks kept, tags dropped. */
export function htmlToText(html) {
  return String(html)
    .replace(/<(head|style|script|title)\b[\s\S]*?<\/\1\s*>/gi, '')
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<li\b[^>]*>/gi, '\n• ')
    .replace(/<\/(p|div|tr|h[1-6]|li|blockquote|table)\s*>/gi, '\n')
    .replace(/<[^>]*>/g, '')
    .replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (m, e) => {
      if (e[0] === '#') {
        const n = e[1] === 'x' || e[1] === 'X' ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10);
        return n > 0 && n < 0x110000 ? String.fromCodePoint(n) : '';
      }
      return ENTITIES[e.toLowerCase()] ?? m;
    })
    .split('\n')
    .map((l) => l.replace(/[ \t ]+/g, ' ').trim())
    .join('\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

function address(v) {
  if (!v) return null;
  const s = decodeWords(v);
  const m = /<([^<>\s]+@[^<>\s]+)>/.exec(s);
  const addr = (m ? m[1] : (/([^\s<>"',;:]+@[^\s<>"',;:]+)/.exec(s) || [])[1] || '').toLowerCase();
  if (!/^[^@\s]+@[^@\s]+\.[a-z0-9-]{2,}$/i.test(addr)) return null;
  const name = m ? s.slice(0, m.index).trim().replace(/^"(.*)"$/, '$1').trim() : '';
  return { addr, name };
}

const ids = (v) => String(v || '').match(/<[^<>\s]+>/g) || [];

/** A raw letter -> what the inbox needs from it. */
export function parseMail(buf) {
  const { head } = splitHead(buf);
  const h = headerMap(head);
  const out = { plain: [], html: [], files: [] };
  walk(buf, out, 0);
  const plain = out.plain.join('\n\n').trim();
  const autoSubmitted = h.get('auto-submitted').toLowerCase();
  return {
    from: address(h.get('from')),
    replyTo: address(h.get('reply-to')),
    subject: decodeWords(h.get('subject')).replace(/\s+/g, ' ').trim(),
    messageId: ids(h.get('message-id'))[0] || '',
    inReplyTo: ids(h.get('in-reply-to')),
    references: ids(h.get('references')),
    text: (plain || htmlToText(out.html.join('\n'))).replace(/\r\n?/g, '\n'),
    files: out.files,
    // Robots: vacation replies, bounces, mailing lists. They don't open tickets.
    auto:
      (autoSubmitted !== '' && autoSubmitted !== 'no') ||
      /^(bulk|junk|list)$/i.test(h.get('precedence')) ||
      h.get('return-path') === '<>' ||
      !!h.get('x-autoreply') ||
      !!h.get('list-id'),
  };
}

// --- the inbox ----------------------------------------------------------------------------

export function createSupport({ db, dir, HttpError, bad, cleanText, requireAuth, requireStaff, authenticate, writeLimiter, sendMail, mailOn = () => false, address = 'support@narez.xyz', site = 'https://meltiew.narez.xyz', log = () => {} }) {
  const cols = new Set(db.prepare('PRAGMA table_info(tickets)').all().map((c) => c.name));
  if (!cols.has('email')) db.exec("ALTER TABLE tickets ADD COLUMN email TEXT NOT NULL DEFAULT ''");
  if (!cols.has('source')) db.exec("ALTER TABLE tickets ADD COLUMN source TEXT NOT NULL DEFAULT 'site'");
  if (!cols.has('name')) db.exec("ALTER TABLE tickets ADD COLUMN name TEXT NOT NULL DEFAULT ''");
  // Message-IDs of the letters both ways, for In-Reply-To / References on replies.
  if (!cols.has('thread')) db.exec("ALTER TABLE tickets ADD COLUMN thread TEXT NOT NULL DEFAULT ''");
  db.exec(`CREATE TABLE IF NOT EXISTS ticket_messages (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    ticket_id  INTEGER NOT NULL,
    dir        TEXT NOT NULL,
    author_id  INTEGER,
    body       TEXT NOT NULL,
    files      TEXT NOT NULL DEFAULT '[]',
    emailed    INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL
  )`);
  db.exec('CREATE INDEX IF NOT EXISTS ticket_messages_ticket ON ticket_messages(ticket_id, id)');
  db.exec('CREATE TABLE IF NOT EXISTS support_blocked (email TEXT PRIMARY KEY, created_at INTEGER NOT NULL)');

  const q = {
    insert: db.prepare('INSERT INTO tickets (user_id, contact, subject, body, status, created_at, updated_at, email, source, name, thread) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'),
    mine: db.prepare('SELECT * FROM tickets WHERE user_id = ? ORDER BY id DESC LIMIT 30'),
    all: db.prepare(`SELECT t.*, u.username,
        (SELECT body FROM ticket_messages m WHERE m.ticket_id = t.id ORDER BY m.id DESC LIMIT 1) AS last,
        (SELECT COUNT(*) FROM ticket_messages m WHERE m.ticket_id = t.id) AS n
      FROM tickets t LEFT JOIN users u ON u.id = t.user_id
      ORDER BY (t.status = 'open') DESC, t.updated_at DESC LIMIT 300`),
    ticket: db.prepare('SELECT * FROM tickets WHERE id = ?'),
    byThread: db.prepare("SELECT * FROM tickets WHERE thread != '' AND instr(' ' || thread || ' ', ' ' || ? || ' ') > 0 ORDER BY id DESC LIMIT 1"),
    openBy: db.prepare("SELECT COUNT(*) AS n FROM tickets WHERE user_id = ? AND status = 'open'"),
    openCount: db.prepare("SELECT COUNT(*) AS n FROM tickets WHERE status = 'open'"),
    touch: db.prepare('UPDATE tickets SET status = ?, updated_at = ?, thread = ? WHERE id = ?'),
    reply: db.prepare('UPDATE tickets SET reply = ?, status = ?, updated_at = ?, thread = ? WHERE id = ?'),
    status: db.prepare('UPDATE tickets SET status = ?, updated_at = ? WHERE id = ?'),
    del: db.prepare('DELETE FROM tickets WHERE id = ?'),
    msgAdd: db.prepare('INSERT INTO ticket_messages (ticket_id, dir, author_id, body, files, emailed, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)'),
    msgs: db.prepare('SELECT m.*, u.display_name AS author FROM ticket_messages m LEFT JOIN users u ON u.id = m.author_id WHERE m.ticket_id = ? ORDER BY m.id'),
    msg: db.prepare('SELECT * FROM ticket_messages WHERE id = ? AND ticket_id = ?'),
    lastIn: db.prepare("SELECT * FROM ticket_messages WHERE ticket_id = ? AND dir = 'in' ORDER BY id DESC LIMIT 1"),
    msgsDel: db.prepare('DELETE FROM ticket_messages WHERE ticket_id = ?'),
    blocked: db.prepare('SELECT 1 FROM support_blocked WHERE email = ?'),
    block: db.prepare('INSERT OR IGNORE INTO support_blocked (email, created_at) VALUES (?, ?)'),
    userByEmail: db.prepare('SELECT id FROM users WHERE email = ?'),
  };
  const inDir = path.join(dir, 'in');
  const filesDir = path.join(dir, 'files');
  const domain = address.split('@')[1];
  const looksLikeEmail = (s) => /^[^@\s<>]+@[^@\s<>]+\.[a-z0-9-]{2,}$/i.test(String(s || ''));
  /** Where a reply to this ticket goes by email, if anywhere. */
  const mailTo = (t) => t.email || (looksLikeEmail(t.contact) ? t.contact.toLowerCase() : '');
  const addThread = (thread, id) => (id ? [...thread.split(' ').filter(Boolean).filter((x) => x !== id), id].slice(-20).join(' ') : thread);

  function saveFiles(ticketId, files) {
    const kept = [];
    for (const f of files.slice(0, MAX_FILES)) {
      if (!f.data.length || f.data.length > MAX_FILE) continue;
      const key = crypto.randomBytes(9).toString('hex');
      fs.mkdirSync(path.join(filesDir, String(ticketId)), { recursive: true });
      fs.writeFileSync(path.join(filesDir, String(ticketId), key), f.data);
      kept.push({ n: kept.length, key, name: String(f.name).replace(/[\u0000-\u001f/\\]/g, '_').slice(0, 120), type: String(f.type).slice(0, 80), size: f.data.length });
    }
    return kept;
  }

  // Letters per sender in the last day: a flood from one address stops being filed.
  const recent = new Map();
  function tooMany(addr, now) {
    const list = (recent.get(addr) || []).filter((t) => now - t < 86_400_000);
    list.push(now);
    recent.set(addr, list);
    return list.length > PER_SENDER_DAY;
  }

  /** Files one raw letter. Returns the ticket id, or null when it's dropped. */
  function receive(raw, now = Date.now()) {
    const mail = parseMail(raw);
    const who = mail.replyTo || mail.from;
    if (!who || mail.auto) return null;
    if (q.blocked.get(who.addr) || (mail.from && q.blocked.get(mail.from.addr))) return null;
    if (tooMany(who.addr, now)) return null;
    const text = mail.text.trim().slice(0, MAX_TEXT);
    // Which ticket: our reply's Message-ID (t<id>.<random>@domain) in the answer's headers,
    // a letter already in a ticket, or the [#id] tag in the subject from the same address.
    let t = null;
    for (const id of [...mail.inReplyTo, ...mail.references].reverse()) {
      const m = new RegExp(`^<t(\\d+)\\.[0-9a-f]+@${domain.replace(/\./g, '\\.')}>$`, 'i').exec(id);
      t = m ? q.ticket.get(Number(m[1])) : q.byThread.get(id);
      if (t) break;
    }
    if (!t) {
      const tag = /\[#(\d+)\]/.exec(mail.subject);
      const cand = tag ? q.ticket.get(Number(tag[1])) : null;
      if (cand && mailTo(cand) === who.addr) t = cand;
    }
    if (t) {
      const msg = q.msgAdd.run(t.id, 'in', null, text, '[]', 0, now).lastInsertRowid;
      const files = saveFiles(t.id, mail.files);
      if (files.length) db.prepare('UPDATE ticket_messages SET files = ? WHERE id = ?').run(JSON.stringify(files), msg);
      q.touch.run('open', now, addThread(t.thread, mail.messageId), t.id);
      return t.id;
    }
    const norm = normalizeEmail(who.addr);
    const user = norm ? q.userByEmail.get(norm) : null;
    const subject = (cleanText(mail.subject, 120) || '(no subject)').slice(0, 120);
    const id = Number(q.insert.run(user ? user.id : null, who.addr, subject, text.slice(0, 4000), 'open', now, now,
      who.addr, 'email', cleanText(who.name, 80), mail.messageId).lastInsertRowid);
    const files = saveFiles(id, mail.files);
    q.msgAdd.run(id, 'in', null, text, JSON.stringify(files), 0, now);
    return id;
  }

  /** Files the letters Postfix has dropped off since the last call. */
  function pickUp() {
    let names;
    try {
      names = fs.readdirSync(inDir).filter((n) => n.endsWith('.eml')).sort();
    } catch {
      return 0;
    }
    let n = 0;
    for (const name of names) {
      const file = path.join(inDir, name);
      try {
        const id = receive(fs.readFileSync(file));
        log(id ? `support: letter filed in ticket #${id}` : 'support: letter dropped (robot, blocked or flood)');
        fs.unlinkSync(file);
        n += 1;
      } catch (err) {
        // Kept aside, not retried forever.
        log(`support: can't read ${name}: ${err.message}`);
        fs.mkdirSync(path.join(dir, 'bad'), { recursive: true });
        try { fs.renameSync(file, path.join(dir, 'bad', name)); } catch {}
      }
    }
    return n;
  }

  function quoteOf(t, text) {
    const last = q.lastIn.get(t.id);
    if (!last || !last.body) return '';
    const ru = /[а-яё]/i.test(text);
    const when = new Date(last.created_at).toLocaleString(ru ? 'ru-RU' : 'en-GB', { timeZone: 'Europe/Moscow', dateStyle: 'medium', timeStyle: 'short' });
    const lines = last.body.split('\n');
    const cut = lines.slice(0, 60).map((l) => (l.startsWith('>') ? '>' + l : '> ' + l));
    if (lines.length > 60) cut.push('> …');
    return `\n\n${when}, ${t.name || t.email || t.contact} ${ru ? 'пишет' : 'wrote'}:\n${cut.join('\n')}`;
  }

  async function emailReply(t, text) {
    const to = mailTo(t);
    if (!to || !mailOn()) return { emailed: false };
    const ru = /[а-яё]/i.test(text);
    const sign = ru ? 'Поддержка Meltiew' : 'Meltiew Support';
    const tag = `[#${t.id}]`;
    let subject = /^(re|ответ)\s*:/i.test(t.subject) ? t.subject : `Re: ${t.subject}`;
    if (!subject.includes(tag)) subject += ' ' + tag;
    const messageId = `<t${t.id}.${crypto.randomBytes(8).toString('hex')}@${domain}>`;
    const thread = t.thread.split(' ').filter(Boolean);
    const headers = thread.length ? [`In-Reply-To: ${thread.at(-1)}`, `References: ${thread.slice(-10).join(' ')}`] : [];
    await sendMail({ to, subject, text: `${text}\n\n${sign}\n${site}${quoteOf(t, text)}`, from: address, name: sign, messageId, headers });
    return { emailed: true, messageId };
  }

  function view(t) {
    return { ...t, mail_to: mailTo(t) };
  }

  const routes = {
    'POST /api/support': (req, body) => {
      const auth = authenticate(req);
      const key = 'ticket:' + (auth ? auth.user.id : req.socket.remoteAddress);
      if (!writeLimiter.allow(key) || !writeLimiter.allow(key + ':2')) throw new HttpError(429, 'slow_down');
      if (auth && q.openBy.get(auth.user.id).n >= 5) throw bad('too_many_tickets');
      const subject = cleanText(body.subject, 120);
      const text = String(body.body ?? '').replace(/[\u0000-\u0008\u000b-\u001f]/g, '').trim().slice(0, 4000);
      const contact = cleanText(body.contact, 120);
      if (subject.length < 3 || text.length < 5) throw bad('ticket_short');
      if (!auth && contact.length < 3) throw bad('ticket_contact');
      const now = Date.now();
      const id = Number(q.insert.run(auth ? auth.user.id : null, contact, subject, text, 'open', now, now, '', 'site', auth ? auth.user.display_name : '', '').lastInsertRowid);
      q.msgAdd.run(id, 'in', null, text, '[]', 0, now);
      return { ok: true };
    },

    'GET /api/support': (req) => {
      const { user } = requireAuth(req);
      return { tickets: q.mine.all(user.id) };
    },

    'GET /api/admin/tickets': (req) => {
      requireStaff(req);
      return {
        tickets: q.all.all().map((t) => ({ ...view(t), last: String(t.last ?? t.body).slice(0, 160), thread: undefined })),
        mail: mailOn(),
        address,
      };
    },

    'GET /api/admin/tickets/:id': (req, _b, _u, params) => {
      requireStaff(req);
      const t = q.ticket.get(Number(params.id));
      if (!t) throw new HttpError(404, 'not_found');
      let messages = q.msgs.all(t.id).map((m) => ({
        id: m.id, dir: m.dir, body: m.body, author: m.author || '', emailed: !!m.emailed, created_at: m.created_at,
        files: JSON.parse(m.files).map((f) => ({ n: f.n, name: f.name, type: f.type, size: f.size, image: IMAGE_TYPES.has(f.type) })),
      }));
      // Requests from before conversations: the question and the one answer.
      if (!messages.length) {
        messages = [{ id: 0, dir: 'in', body: t.body, author: '', emailed: false, created_at: t.created_at, files: [] }];
        if (t.reply) messages.push({ id: 0, dir: 'out', body: t.reply, author: '', emailed: false, created_at: t.updated_at, files: [] });
      }
      const username = t.user_id ? db.prepare('SELECT username FROM users WHERE id = ?').get(t.user_id)?.username : null;
      return { ticket: { ...view(t), username, thread: undefined }, messages };
    },

    // A reply (sent by email when there's an address) and/or a new status.
    'POST /api/admin/tickets/:id': async (req, body, _u, params) => {
      const { user } = requireStaff(req);
      const t = q.ticket.get(Number(params.id));
      if (!t) throw new HttpError(404, 'not_found');
      const now = Date.now();
      const status = body.status === 'open' ? 'open' : 'closed';
      const text = String(body.reply ?? '').replace(/[\u0000-\u0008\u000b-\u001f]/g, '').trim().slice(0, 8000);
      if (!text) {
        q.status.run(status, now, t.id);
        return { ticket: view(q.ticket.get(t.id)), emailed: false };
      }
      let sent = { emailed: false };
      let mailError = '';
      try {
        sent = await emailReply(t, text);
      } catch (err) {
        mailError = err.message;
        log(`support: reply to #${t.id} not emailed: ${err.message}`);
      }
      q.msgAdd.run(t.id, 'out', user.id, text, '[]', sent.emailed ? 1 : 0, now);
      q.reply.run(text, status, now, addThread(t.thread, sent.messageId), t.id);
      return { ticket: view(q.ticket.get(t.id)), emailed: sent.emailed, mail_error: mailError };
    },

    'DELETE /api/admin/tickets/:id': (req, _b, _u, params) => {
      requireStaff(req);
      remove(Number(params.id));
      return { ok: true };
    },

    // Spam: the sender's address won't open tickets any more, and this one goes.
    'POST /api/admin/tickets/:id/spam': (req, _b, _u, params) => {
      requireStaff(req);
      const t = q.ticket.get(Number(params.id));
      if (!t) throw new HttpError(404, 'not_found');
      const addr = mailTo(t);
      if (addr) q.block.run(addr, Date.now());
      remove(t.id);
      return { ok: true, blocked: addr };
    },

    'GET /api/admin/tickets/:id/files/:mid/:n': (req, _b, _u, params) => {
      requireStaff(req);
      const m = q.msg.get(Number(params.mid), Number(params.id));
      const f = m && JSON.parse(m.files).find((x) => x.n === Number(params.n));
      if (!f) throw new HttpError(404, 'not_found');
      let data;
      try {
        data = fs.readFileSync(path.join(filesDir, String(m.ticket_id), f.key));
      } catch {
        throw new HttpError(404, 'not_found');
      }
      const image = IMAGE_TYPES.has(f.type);
      return {
        __raw: {
          type: image ? f.type : 'application/octet-stream',
          cache: 'private, no-store',
          body: data,
          headers: {
            'content-disposition': `${image ? 'inline' : 'attachment'}; filename*=UTF-8''${encodeURIComponent(f.name)}`,
            'content-security-policy': "default-src 'none'",
          },
        },
      };
    },
  };

  function remove(id) {
    q.msgsDel.run(id);
    q.del.run(id);
    fs.rmSync(path.join(filesDir, String(id)), { recursive: true, force: true });
  }

  return { routes, receive, pickUp, openCount: () => q.openCount.get().n };
}
