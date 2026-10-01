import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { openDb } from '../src/db.js';
import { createSupport, parseMail, decodeWords, htmlToText } from '../src/support.js';

class HttpError extends Error {
  constructor(status, code) {
    super(code);
    this.status = status;
  }
}

const crlf = (s) => s.replace(/\r?\n/g, '\r\n');
const PNG = Buffer.from('89504e470d0a1a0a0000000d49484452', 'hex');

// A letter like a phone mail app sends: the text in two forms, a picture, a Russian
// name and subject split over two encoded words, the text in windows-1251.
const cp1251 = (s) => Buffer.from([...s].map((c) => (c >= 'А' && c <= 'я' ? c.charCodeAt(0) - 0x350 : c === 'ё' ? 0xb8 : c.charCodeAt(0))));
const qp = (buf) => [...buf].map((b) => (b > 126 || b === 61 ? '=' + b.toString(16).toUpperCase().padStart(2, '0') : String.fromCharCode(b))).join('');
const letter = (extra = '') => Buffer.from(crlf(`Return-Path: <ivan.petrov@gmail.com>
From: =?UTF-8?B?0JjQstCw0L0=?= <Ivan.Petrov@gmail.com>
To: support@narez.xyz
Subject: =?UTF-8?B?0J3QtSDQv9GA0LjRiNC70Lgg?=
 =?UTF-8?B?0LrRg9GB0L7Rh9C60Lg=?=
Message-ID: <abc123@mail.gmail.com>
${extra}MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="outer"

--outer
Content-Type: multipart/alternative; boundary="outer-alt"

--outer-alt
Content-Type: text/plain; charset=windows-1251
Content-Transfer-Encoding: quoted-printable

${qp(cp1251('Купил кусочки, а они не пришли.'))}
--outer-alt
Content-Type: text/html; charset=utf-8

<p>Купил кусочки, а они не пришли.</p>
--outer-alt--

--outer
Content-Type: image/png
Content-Disposition: attachment; filename*=utf-8''%D1%87%D0%B5%D0%BA.png
Content-Transfer-Encoding: base64

${PNG.toString('base64')}
--outer--
`), 'latin1');

test('support: reads a letter (encodings, nested parts, attachment)', () => {
  const m = parseMail(letter());
  assert.deepEqual(m.from, { addr: 'ivan.petrov@gmail.com', name: 'Иван' });
  assert.equal(m.subject, 'Не пришли кусочки');
  assert.equal(m.messageId, '<abc123@mail.gmail.com>');
  assert.equal(m.text, 'Купил кусочки, а они не пришли.');
  assert.equal(m.files.length, 1);
  assert.equal(m.files[0].name, 'чек.png');
  assert.equal(m.files[0].type, 'image/png');
  assert.deepEqual(m.files[0].data, PNG);
  assert.equal(m.auto, false);
  assert.equal(decodeWords('=?koi8-r?Q?=F0=D2=C9=D7=C5=D4?= world'), 'Привет world');
  assert.equal(htmlToText('<style>p{}</style><p>Hi&nbsp;there</p><div>A<br>B &amp; C</div>'), 'Hi there\nA\nB & C');
  // An HTML-only letter still has its text.
  const html = parseMail(Buffer.from(crlf('From: a@b.co\nContent-Type: text/html; charset=utf-8\n\n<b>Hello</b><br>world')));
  assert.equal(html.text, 'Hello\nworld');
  // Robots don't open tickets.
  assert.equal(parseMail(Buffer.from(crlf('From: a@b.co\nAuto-Submitted: auto-replied\n\nI am away'))).auto, true);
});

test('support: letters become tickets, replies go by email and answers come back', async () => {
  const db = openDb(':memory:');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'meltiew-support-test-'));
  const add = db.prepare("INSERT INTO users (username, pass_hash, display_name, created_at, last_seen, email, role) VALUES (?, 'x', ?, 0, 0, ?, ?)");
  const staffId = Number(add.run('nrz', 'nrz', '', 'owner').lastInsertRowid);
  const ivanId = Number(add.run('ivan', 'Ivan', 'ivanpetrov@gmail.com', 'user').lastInsertRowid);
  const sent = [];
  const s = createSupport({
    db,
    dir,
    HttpError,
    bad: (c) => new HttpError(400, c),
    cleanText: (v, n) => String(v ?? '').replace(/\s+/g, ' ').trim().slice(0, n),
    requireAuth: () => ({ user: db.prepare('SELECT * FROM users WHERE id = ?').get(staffId) }),
    requireStaff: () => ({ user: db.prepare('SELECT * FROM users WHERE id = ?').get(staffId) }),
    authenticate: () => null,
    writeLimiter: { allow: () => true },
    sendMail: async (m) => sent.push(m),
    mailOn: () => true,
  });

  // Postfix drops the letter off; the server files it.
  fs.mkdirSync(path.join(dir, 'in'), { recursive: true });
  fs.writeFileSync(path.join(dir, 'in', '1.eml'), letter());
  assert.equal(s.pickUp(), 1);
  assert.deepEqual(fs.readdirSync(path.join(dir, 'in')), []);
  const list = s.routes['GET /api/admin/tickets']({}).tickets;
  assert.equal(list.length, 1);
  const t = list[0];
  assert.equal(t.source, 'email');
  assert.equal(t.mail_to, 'ivan.petrov@gmail.com');
  assert.equal(t.user_id, ivanId); // the account with that (normalized) email
  assert.equal(s.openCount(), 1);

  const one = s.routes['GET /api/admin/tickets/:id']({}, {}, null, { id: String(t.id) });
  assert.equal(one.messages.length, 1);
  assert.equal(one.messages[0].files[0].image, true);
  const file = s.routes['GET /api/admin/tickets/:id/files/:mid/:n']({}, {}, null, { id: String(t.id), mid: String(one.messages[0].id), n: '0' });
  assert.deepEqual(file.__raw.body, PNG);
  assert.equal(file.__raw.type, 'image/png');

  // The reply goes by email, in the same thread, and closes the ticket.
  const r = await s.routes['POST /api/admin/tickets/:id']({}, { reply: 'Проверили, кусочки зачислены.' }, null, { id: String(t.id) });
  assert.equal(r.emailed, true);
  assert.equal(r.ticket.status, 'closed');
  assert.equal(sent.length, 1);
  assert.equal(sent[0].to, 'ivan.petrov@gmail.com');
  assert.equal(sent[0].from, 'support@narez.xyz');
  assert.equal(sent[0].subject, `Re: Не пришли кусочки [#${t.id}]`);
  assert.ok(sent[0].headers.includes('In-Reply-To: <abc123@mail.gmail.com>'));
  assert.match(sent[0].text, /^Проверили, кусочки зачислены\.\n\nПоддержка Meltiew/);
  assert.match(sent[0].text, /> Купил кусочки/);

  // Ivan answers: back into the same ticket, open again.
  const answer = Buffer.from(crlf(`From: Ivan <ivan.petrov@gmail.com>
Subject: Re: Не пришли кусочки [#${t.id}]
Message-ID: <def456@mail.gmail.com>
In-Reply-To: ${sent[0].messageId}
Content-Type: text/plain; charset=utf-8

Спасибо, всё пришло!`));
  assert.equal(s.receive(answer), t.id);
  const again = s.routes['GET /api/admin/tickets/:id']({}, {}, null, { id: String(t.id) });
  assert.deepEqual(again.messages.map((m) => m.dir), ['in', 'out', 'in']);
  assert.equal(again.ticket.status, 'open');

  // Spam: the sender is blocked and their ticket goes away.
  const spamId = s.receive(Buffer.from(crlf('From: promo@spam.example\nSubject: SEO\n\nBuy links')));
  assert.ok(spamId);
  s.routes['POST /api/admin/tickets/:id/spam']({}, {}, null, { id: String(spamId) });
  assert.equal(s.receive(Buffer.from(crlf('From: promo@spam.example\nSubject: SEO 2\n\nBuy more'))), null);
  assert.equal(s.routes['GET /api/admin/tickets']({}).tickets.length, 1);

  // A site request that left an email as the contact gets the answer by email too.
  s.routes['POST /api/support']({ socket: {} }, { subject: 'Не могу войти', body: 'Забыл пароль, помогите', contact: 'Someone@Mail.ru' });
  const site = s.routes['GET /api/admin/tickets']({}).tickets.find((x) => x.source === 'site');
  assert.equal(site.mail_to, 'someone@mail.ru');
  await s.routes['POST /api/admin/tickets/:id']({}, { reply: 'Hi! Write us from that email.' }, null, { id: String(site.id) });
  assert.equal(sent.at(-1).to, 'someone@mail.ru');
  assert.equal(sent.at(-1).name, 'Meltiew Support');

  s.routes['DELETE /api/admin/tickets/:id']({}, {}, null, { id: String(t.id) });
  assert.equal(fs.existsSync(path.join(dir, 'files', String(t.id))), false);
  fs.rmSync(dir, { recursive: true, force: true });
});
