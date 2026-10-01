// Email: sign-up codes and support answers. A tiny SMTP client. Two setups, from the service's env:
//   our own Postfix on this machine (it signs with DKIM for narez.xyz):
//     MELTIEW_SMTP_HOST=127.0.0.1 MELTIEW_SMTP_PORT=25 MELTIEW_MAIL_FROM=noreply@narez.xyz
//   or a provider over implicit TLS with a login (port 465):
//     MELTIEW_SMTP_HOST, MELTIEW_SMTP_PORT, MELTIEW_SMTP_USER, MELTIEW_SMTP_PASS, MELTIEW_MAIL_FROM
import tls from 'node:tls';
import net from 'node:net';
import crypto from 'node:crypto';

export function mailConfigured(env = process.env) {
  return Boolean(env.MELTIEW_SMTP_HOST && (env.MELTIEW_SMTP_USER || env.MELTIEW_MAIL_FROM));
}

// Only big providers that verify their users: throwaway domains can't be used for bots.
export const EMAIL_DOMAINS = new Set([
  'gmail.com', 'googlemail.com',
  'outlook.com', 'hotmail.com', 'live.com', 'msn.com', 'outlook.ru',
  'icloud.com', 'me.com', 'mac.com',
  'yahoo.com', 'ymail.com', 'aol.com',
  'yandex.ru', 'ya.ru', 'yandex.com', 'yandex.by', 'yandex.kz', 'yandex.ua',
  'mail.ru', 'bk.ru', 'inbox.ru', 'list.ru', 'internet.ru', 'rambler.ru',
  'proton.me', 'protonmail.com', 'pm.me',
  'gmx.com', 'gmx.de', 'gmx.net', 'web.de', 'zoho.com', 'ukr.net',
]);

/**
 * The address as the account keeps it, or null if it isn't one we accept. Gmail ignores
 * dots and every provider here ignores "+tag", so those don't make new addresses.
 */
export function normalizeEmail(raw) {
  const s = String(raw ?? '').trim().toLowerCase();
  const m = /^([a-z0-9._%+-]{1,64})@([a-z0-9.-]{3,80})$/.exec(s);
  if (!m) return null;
  let [, local, domain] = m;
  if (domain === 'googlemail.com') domain = 'gmail.com';
  if (!EMAIL_DOMAINS.has(domain)) return null;
  local = local.split('+')[0];
  if (domain === 'gmail.com') local = local.replace(/\./g, '');
  if (!local) return null;
  return `${local}@${domain}`;
}

export function newCode() {
  return String(crypto.randomInt(0, 1_000_000)).padStart(6, '0');
}

export function hashCode(code) {
  return crypto.createHash('sha256').update('meltiew-code:' + code).digest('hex');
}

const TEXT = {
  en: {
    subject: (code) => `${code} is your Meltiew code`,
    title: 'Your code',
    lead: 'Enter it in Meltiew to confirm your email.',
    expires: 'It works for 15 minutes.',
    ignore: "If you didn't ask for it, just ignore this email: nothing will happen.",
    footer: 'Meltiew · a place to play and make games together',
  },
  ru: {
    subject: (code) => `${code} — твой код Meltiew`,
    title: 'Твой код',
    lead: 'Введи его в Meltiew, чтобы подтвердить почту.',
    expires: 'Код действует 15 минут.',
    ignore: 'Если ты его не запрашивал(а), просто не обращай внимания на письмо: ничего не случится.',
    footer: 'Meltiew · место, где вместе играют и делают игры',
  },
};

const SITE = 'https://meltiew.narez.xyz';

// Colours from the site (public/style.css). Tables and inline styles: that's what every
// mail app (Gmail, Outlook, phones) draws the same way.
function codeHtml(code, t) {
  return `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="dark light"></head>
<body style="margin:0;padding:0;background:#16141d">
<div style="display:none;max-height:0;overflow:hidden">${t.lead} ${t.expires}</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#16141d;padding:32px 12px">
<tr><td align="center">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:460px">
  <tr><td align="center" style="padding-bottom:20px">
    <a href="${SITE}" style="text-decoration:none"><img src="${SITE}/img/icon.png" width="56" height="56" alt="" style="display:block;border:0;border-radius:14px">
    <div style="font:800 22px/1.2 'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#f4f1ec;padding-top:10px;letter-spacing:.5px">Meltiew</div></a>
  </td></tr>
  <tr><td style="background:#242030;border-radius:20px;padding:32px 28px;font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif">
    <div style="font-size:22px;font-weight:800;color:#f4f1ec">${t.title}</div>
    <div style="font-size:15px;line-height:1.5;color:#9d96b0;padding-top:6px">${t.lead}</div>
    <div style="margin:24px 0;padding:18px 8px;background:#2e2940;border:2px solid #b89cff;border-radius:16px;text-align:center;white-space:nowrap;font:800 34px/1 'Segoe UI',Roboto,Helvetica,Arial,sans-serif;letter-spacing:6px;color:#f4f1ec">${code}</div>
    <div style="font-size:14px;line-height:1.5;color:#f4f1ec">${t.expires}</div>
    <div style="font-size:13px;line-height:1.5;color:#9d96b0;padding-top:10px">${t.ignore}</div>
  </td></tr>
  <tr><td align="center" style="padding-top:18px;font:13px/1.5 'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#9d96b0">
    <a href="${SITE}" style="color:#b89cff;text-decoration:none">${t.footer}</a>
  </td></tr>
  </table>
</td></tr></table></body></html>`;
}

export function sendCode(to, code, lang = 'en', env = process.env) {
  const t = TEXT[lang] || TEXT.en;
  const text = `${t.title}: ${code}\n\n${t.lead}\n${t.expires}\n\n${t.ignore}\n\n${SITE}`;
  return sendMail({ to, subject: t.subject(code), text, html: codeHtml(code, t) }, env);
}

function b64(s) {
  return Buffer.from(s, 'utf8').toString('base64');
}

// Headers and body: just the text, or the text and the HTML version side by side
// (apps show the HTML, and the text is there for the ones that can't).
function body(text, html) {
  const part = (type, s) => [`Content-Type: ${type}; charset=UTF-8`, 'Content-Transfer-Encoding: base64', '', b64(s).replace(/.{76}/g, '$&\r\n')];
  if (!html) return part('text/plain', text);
  const edge = 'meltiew-' + crypto.randomUUID();
  return [`Content-Type: multipart/alternative; boundary="${edge}"`, '', `--${edge}`, ...part('text/plain', text), `--${edge}`, ...part('text/html', html), `--${edge}--`];
}

// A display name as a header allows it: plain if it's ASCII, encoded otherwise.
const headerName = (s) => (/^[\x20-\x7e]*$/.test(s) ? `"${s.replace(/["\\]/g, '')}"` : `=?UTF-8?B?${b64(s)}?=`);

/**
 * One email over SMTP (plain text, and HTML when given); resolves when it's accepted.
 * Sent as the service's address unless `from` is given (support answers as support@);
 * `headers` are extra lines, like In-Reply-To.
 */
export function sendMail({ to, subject, text, html, from: fromAddr, name = 'Meltiew', messageId, headers = [] }, env = process.env) {
  const host = env.MELTIEW_SMTP_HOST;
  const port = Number(env.MELTIEW_SMTP_PORT) || 465;
  const user = env.MELTIEW_SMTP_USER;
  const from = fromAddr || env.MELTIEW_MAIL_FROM || user;
  const message = [
    `From: ${headerName(name)} <${from}>`,
    `To: <${to}>`,
    `Subject: =?UTF-8?B?${b64(subject)}?=`,
    `Date: ${new Date().toUTCString()}`,
    `Message-ID: ${messageId || `<${crypto.randomUUID()}@${from.split('@')[1] || 'meltiew'}>`}`,
    ...headers.filter((h) => /^[\x20-\x7e]+$/.test(h)),
    'MIME-Version: 1.0',
    ...body(text, html),
  ].join('\r\n');
  const steps = [
    [null, 220],
    ['EHLO meltiew', 250],
    // A login only for a provider; our own local Postfix takes mail from this machine.
    ...(user ? [['AUTH PLAIN ' + b64(`\0${user}\0${env.MELTIEW_SMTP_PASS}`), 235]] : []),
    [`MAIL FROM:<${from}>`, 250],
    [`RCPT TO:<${to}>`, 250],
    ['DATA', 354],
    [message + '\r\n.', 250],
    ['QUIT', 221],
  ];
  return new Promise((resolve, reject) => {
    const sock = port === 465 ? tls.connect({ host, port, servername: host }) : net.connect({ host, port });
    let buf = '';
    let i = 0;
    const fail = (err) => {
      sock.destroy();
      reject(err instanceof Error ? err : new Error(String(err)));
    };
    sock.setTimeout(15000, () => fail('smtp timeout'));
    sock.on('error', fail);
    sock.on('data', (d) => {
      buf += d.toString('utf8');
      // A reply is complete at a line "NNN text" (not "NNN-text").
      const lines = buf.split('\r\n');
      const last = lines.findLast((l) => /^\d{3} /.test(l));
      if (!last) return;
      buf = '';
      const code = Number(last.slice(0, 3));
      if (code !== steps[i][1]) return fail(`smtp ${steps[i][0]?.split(' ')[0] || 'greeting'}: ${last}`);
      i += 1;
      if (i >= steps.length) {
        sock.end();
        return resolve();
      }
      sock.write(steps[i][0] + '\r\n');
    });
  });
}
