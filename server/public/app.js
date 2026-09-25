// Meltiew website: a tiny single-page app on top of the same API the game uses.
const DL_BASE = 'https://github.com/narezy/Meltiew/raw/refs/heads/download/';
const DOWNLOADS = {
  android: DL_BASE + 'meltiew.apk',
  windows: DL_BASE + 'meltiew-windows.zip',
  linux: DL_BASE + 'meltiew-linux.zip',
};
const DOWNLOAD_URL = DOWNLOADS.android;
const PACKAGE = 'cat.narezany.meltiew';

const T = {
  en: {
    home: 'Home', friends: 'Friends', download: 'Download', settings: 'Settings',
    sign_in: 'Sign in', sign_up: 'Sign up', sign_out: 'Sign out',
    hero_title: 'Play, dress up and hang out with friends',
    hero_text: 'A playground with slides, trampolines, a hedge maze and parkour above the clouds. Build your Melly, invite friends and join the same server. Up to 10 players per server.',
    get_app: 'Download for Android', apk_note: 'APK · Android 7+',
    f1: 'Your look', f1t: 'Six body parts, any color and hats from cat ears to a crown.',
    f2: 'Friends', f2t: 'Requests, online status and joining a friend in one tap.',
    f3: 'Play from here', f3t: 'Pick a server on the website and the app opens right on it.',
    hi: 'Hi, {0}!', places: 'Places', playground: 'Playground',
    playground_desc: 'Slides, swings, trampolines, a hedge maze, a duck pond and parkour above the clouds.',
    playing_now: '{0} playing now', play: 'Play', new_server: 'New server', servers: 'Servers',
    no_servers: 'No servers yet. Press Play and the first one is yours.', full: 'Full', join: 'Join',
    friends_here: 'Friends here: {0}', friends_online: 'Friends online',
    username: 'Username', password: 'Password', display_name: 'Display name', repeat: 'Repeat password',
    no_account: 'No account yet?', have_account: 'Already have an account?', create: 'Create account',
    passwords_mismatch: "Passwords don't match",
    opening: 'Opening Meltiew...', opening_text: "The game will join that server as soon as it opens. Nothing happened? Install the app first.",
    close: 'Close', search: 'Search players', requests: 'Requests', sent: 'Sent', my_friends: 'My friends',
    no_friends: 'No friends yet. Try the search above!', no_requests: 'No new requests', no_sent: 'No sent requests',
    nobody: 'Nobody found', online: 'Online', offline: 'Offline', playing: 'Playing: {0}',
    add_friend: 'Add friend', remove_friend: 'Remove friend', cancel_request: 'Cancel request', accept: 'Accept',
    decline: 'Decline', block: 'Block', unblock: 'Unblock', request_sent: 'Request sent', now_friends: "You're friends now!",
    friends_count: 'friends', member_since: 'member since', no_bio: 'No bio yet', not_found: 'Player not found',
    language: 'Language', account: 'Account', change_password: 'Change password', current_password: 'Current password',
    new_password: 'New password', saved: 'Saved', edit_in_app: 'Edit your avatar in the app: Avatar tab.',
    download_title: 'Get Meltiew for Android', download_text: 'Download the APK, open it and allow installing from your browser if Android asks.',
    server_up: 'Server online', server_down: 'Server offline', signed_out: 'Signed out', sign_in_to_play: 'Sign in to play',
    blocked: 'Blocked', done: 'Done',
    places: 'Places', by: 'by', playing_n: '{0} playing', visits_n: '{0} visits', liked: '{0} liked', about: 'About',
    created: 'Created {0}', back: '← Back', play_hint: 'Play puts you on a server with your friends if any are playing.',
    owner: 'OWNER', admin: 'ADMIN', admin_panel: 'Admin', overview: 'Overview', users: 'Users', places_admin: 'Places',
    st_users: 'Accounts', st_new: 'New today', st_active: 'Active today', st_online: 'Online now', st_banned: 'Banned',
    st_servers: 'Servers', st_playing: 'In game', st_uptime: 'Uptime', st_memory: 'Memory',
    announce: 'Announcement to every server', send: 'Send', sent_ok: 'Sent',
    min_version: 'Minimum app version', min_version_hint: 'Older apps are told to update and can\'t play.', apply: 'Apply',
    ban: 'Ban', unban: 'Unban', make_admin: 'Make admin', remove_admin: 'Remove admin', kick: 'Kick', reset_profile: 'Reset profile',
    ban_reason: 'Ban reason (optional)', close_server: 'Close', no_live: 'No live servers', banned_tag: 'BANNED',
    save: 'Save', name_en: 'Name (EN)', name_ru: 'Name (RU)', desc_en: 'Description (EN)', desc_ru: 'Description (RU)',
    get_windows: 'Windows', get_linux: 'Linux', other_platforms: 'Also on', desktop_note: 'Unzip and run Meltiew. Same account, same friends.',
    last_seen: 'last seen {0}',
  },
  ru: {
    home: 'Главная', friends: 'Друзья', download: 'Скачать', settings: 'Настройки',
    sign_in: 'Войти', sign_up: 'Регистрация', sign_out: 'Выйти',
    hero_title: 'Играй, наряжайся и тусуйся с друзьями',
    hero_text: 'Площадка с горками, батутами, лабиринтом и паркуром над облаками. Собери свою Melly, позови друзей и заходите на один сервер. До 10 человек на сервер.',
    get_app: 'Скачать для Android', apk_note: 'APK · Android 7 и новее',
    f1: 'Свой образ', f1t: 'Шесть частей тела, любой цвет и шапки: от кошачьих ушек до короны.',
    f2: 'Друзья', f2t: 'Заявки, статус онлайн и вход к другу в одно касание.',
    f3: 'Играй отсюда', f3t: 'Выбери сервер на сайте, и приложение откроется сразу на нём.',
    hi: 'Привет, {0}!', places: 'Плейсы', playground: 'Детская площадка',
    playground_desc: 'Горки, качели, батуты, лабиринт, утиный пруд и паркур над облаками.',
    playing_now: 'Сейчас играют: {0}', play: 'Играть', new_server: 'Новый сервер', servers: 'Серверы',
    no_servers: 'Пока ни одного сервера. Жми «Играть», и первый будет твоим.', full: 'Полный', join: 'Войти',
    friends_here: 'Здесь друзья: {0}', friends_online: 'Друзья онлайн',
    username: 'Логин', password: 'Пароль', display_name: 'Ник', repeat: 'Повтори пароль',
    no_account: 'Нет аккаунта?', have_account: 'Уже есть аккаунт?', create: 'Создать аккаунт',
    passwords_mismatch: 'Пароли не совпадают',
    opening: 'Открываем Meltiew...', opening_text: 'Игра зайдёт на этот сервер, как только откроется. Ничего не произошло? Сначала установи приложение.',
    close: 'Закрыть', search: 'Поиск игроков', requests: 'Заявки', sent: 'Отправленные', my_friends: 'Мои друзья',
    no_friends: 'Пока друзей нет. Попробуй поиск сверху!', no_requests: 'Новых заявок нет', no_sent: 'Нет отправленных заявок',
    nobody: 'Никого не нашли', online: 'В сети', offline: 'Не в сети', playing: 'Играет: {0}',
    add_friend: 'Добавить в друзья', remove_friend: 'Удалить из друзей', cancel_request: 'Отменить заявку', accept: 'Принять',
    decline: 'Отклонить', block: 'Заблокировать', unblock: 'Разблокировать', request_sent: 'Заявка отправлена', now_friends: 'Вы теперь друзья!',
    friends_count: 'друзей', member_since: 'с нами с', no_bio: 'Пока ничего о себе не рассказал(а)', not_found: 'Игрок не найден',
    language: 'Язык', account: 'Аккаунт', change_password: 'Сменить пароль', current_password: 'Текущий пароль',
    new_password: 'Новый пароль', saved: 'Сохранено', edit_in_app: 'Образ редактируется в приложении, вкладка «Аватар».',
    download_title: 'Meltiew для Android', download_text: 'Скачай APK, открой его и разреши установку из браузера, если Android спросит.',
    server_up: 'Сервер онлайн', server_down: 'Сервер недоступен', signed_out: 'Ты вышел(ла)', sign_in_to_play: 'Войди, чтобы играть',
    blocked: 'Заблокирован', done: 'Готово',
    places: 'Плейсы', by: 'от', playing_n: 'играют: {0}', visits_n: 'посещений: {0}', liked: '{0} лайков', about: 'Описание',
    created: 'Создан {0}', back: '← Назад', play_hint: '«Играть» закинет тебя на сервер к друзьям, если они играют.',
    owner: 'ОВНЕР', admin: 'АДМИН', admin_panel: 'Админка', overview: 'Обзор', users: 'Игроки', places_admin: 'Плейсы',
    st_users: 'Аккаунтов', st_new: 'Новых за сутки', st_active: 'Активных за сутки', st_online: 'Онлайн', st_banned: 'Забанено',
    st_servers: 'Серверов', st_playing: 'В игре', st_uptime: 'Аптайм', st_memory: 'Память',
    announce: 'Объявление на все серверы', send: 'Отправить', sent_ok: 'Отправлено',
    min_version: 'Минимальная версия приложения', min_version_hint: 'Старые версии попросит обновиться и не пустит в игру.', apply: 'Применить',
    ban: 'Забанить', unban: 'Разбанить', make_admin: 'Сделать админом', remove_admin: 'Снять админку', kick: 'Кикнуть', reset_profile: 'Сбросить профиль',
    ban_reason: 'Причина бана (необязательно)', close_server: 'Закрыть', no_live: 'Живых серверов нет', banned_tag: 'БАН',
    save: 'Сохранить', name_en: 'Название (EN)', name_ru: 'Название (RU)', desc_en: 'Описание (EN)', desc_ru: 'Описание (RU)',
    get_windows: 'Windows', get_linux: 'Linux', other_platforms: 'Ещё есть под', desktop_note: 'Распакуй и запусти Meltiew. Тот же аккаунт, те же друзья.',
    last_seen: 'был(а) {0}',
  },
};

// English by default; the EN/RU switch in the header is remembered.
const state = {
  lang: localStorage.getItem('lang') === 'ru' ? 'ru' : 'en',
  token: localStorage.getItem('token') || '',
  me: null,
};

const $ = (sel, root = document) => root.querySelector(sel);
const t = (key, ...args) => (T[state.lang][key] ?? T.en[key] ?? key).replace(/\{(\d)\}/g, (_, i) => args[i]);
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
const field = (o, key) => (state.lang === 'ru' && o[key + '_ru']) || o[key] || '';
const badge = (u) => (u && (u.role === 'owner' || u.role === 'admin') ? `<span class="badge ${u.role}">${t(u.role)}</span>` : '');
const THUMB = '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:-4px"><path d="M3 11h4v10H3zM7 11l4-7.5 2 .5.5 5H20l1 2-2 9-1.5 1H7"/></svg>';
const THUMB_DOWN = THUMB.replace('style="', 'style="transform:scaleY(-1);');
const nameHtml = (u) => `${esc(u.display_name)}${badge(u)}`;
const isStaff = () => state.me && (state.me.role === 'owner' || state.me.role === 'admin');
const ago = (ms) => {
  const m = Math.round((Date.now() - ms) / 60000);
  if (m < 2) return state.lang === 'ru' ? 'только что' : 'just now';
  if (m < 60) return state.lang === 'ru' ? `${m} мин назад` : `${m} min ago`;
  const h = Math.round(m / 60);
  if (h < 48) return state.lang === 'ru' ? `${h} ч назад` : `${h} h ago`;
  return new Date(ms).toLocaleDateString(state.lang === 'ru' ? 'ru-RU' : 'en-US');
};
const bust = (u, cls = '') => `<img class="bust ${cls}" alt="" loading="lazy" src="/api/avatar/${u.id}.png?v=${esc(u.render || '0')}">`;

async function api(method, path, body) {
  const res = await fetch(path, {
    method,
    headers: {
      'content-type': 'application/json',
      'x-lang': state.lang,
      'x-client': 'web',
      ...(state.token ? { authorization: 'Bearer ' + state.token } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  let data = {};
  try { data = await res.json(); } catch {}
  if (res.status === 401 && state.token && path !== '/api/login') {
    state.token = ''; state.me = null; localStorage.removeItem('token');
  }
  if (!res.ok) throw new Error(data.message || res.statusText);
  return data;
}

function toast(text, kind = 'ok') {
  const el = document.createElement('div');
  el.className = 'toast ' + kind;
  el.textContent = text;
  document.body.appendChild(el);
  setTimeout(() => el.remove(), 2800);
}

function status(u) {
  if (u.playing) return `<span class="pill"><i class="dot play"></i>${esc(t('playing', field(u.playing, 'server_name')))}</span>`;
  return `<span class="pill"><i class="dot ${u.online ? 'on' : ''}"></i>${t(u.online ? 'online' : 'offline')}</span>`;
}

// --- launching the game -----------------------------------------------------

async function launch(server = 'auto') {
  if (!state.me) return go('/login');
  try {
    await api('POST', '/api/launch', { server, game: 'playground' });
  } catch (e) {
    return toast(e.message, 'error');
  }
  const isAndroid = /android/i.test(navigator.userAgent);
  const fallback = encodeURIComponent(location.origin + '/download');
  const url = isAndroid
    ? `intent://play#Intent;scheme=meltiew;package=${PACKAGE};S.browser_fallback_url=${fallback};end`
    : 'meltiew://play';
  modal(`<h3>${t('opening')}</h3><p class="muted">${t('opening_text')}</p>
    <div class="row"><a class="btn ghost grow" href="${DOWNLOAD_URL}">${t('get_app')}</a><button class="btn grow" data-close>${t('close')}</button></div>`);
  location.href = url;
}

function modal(html) {
  const bg = document.createElement('div');
  bg.className = 'modal-bg';
  bg.innerHTML = `<div class="card modal stack">${html}</div>`;
  bg.addEventListener('click', (e) => { if (e.target === bg || e.target.hasAttribute('data-close')) bg.remove(); });
  document.body.appendChild(bg);
  return bg;
}

// --- chrome -----------------------------------------------------------------

function renderNav(path) {
  const links = [['/', 'home'], ...(state.me ? [['/friends', 'friends']] : []), ['/download', 'download'], ...(state.me ? [['/settings', 'settings']] : []), ...(isStaff() ? [['/admin', 'admin_panel']] : [])];
  $('#nav').innerHTML = `
    <a class="brand" href="/" data-link><img src="/img/logo.svg" alt="">meltiew</a>
    <div class="nav-links">${links.map(([href, key]) => `<a href="${href}" data-link class="${path === href ? 'on' : ''}">${t(key)}</a>`).join('')}</div>
    <div class="nav-right">
      <div class="lang">${['en', 'ru'].map((l) => `<button data-lang="${l}" class="${state.lang === l ? 'on' : ''}">${l.toUpperCase()}</button>`).join('')}</div>
      ${state.me
        ? `<a class="me-chip" href="/u/${encodeURIComponent(state.me.username)}" data-link>${bust(state.me)}<span>${nameHtml(state.me)}</span></a>`
        : `<a class="btn small" href="/login" data-link>${t('sign_in')}</a>`}
    </div>`;
  $('#nav').querySelectorAll('.me-chip .bust').forEach((b) => { b.style.width = b.style.height = '34px'; });
}

// --- pages ------------------------------------------------------------------

const pages = {
  async '/'(root) {
    if (!state.me) return landing(root);
    root.innerHTML = `<h1>${esc(t('hi', state.me.display_name))}</h1><div id="fo"></div>
      <h2>${t('places')}</h2><div class="places" id="places"></div>`;
    const [places, friends] = await Promise.all([api('GET', '/api/places'), api('GET', '/api/friends')]);
    $('#places').innerHTML = places.places.map(placeCard).join('');
    const online = friends.friends.filter((f) => f.online);
    if (online.length) {
      $('#fo').innerHTML = `<h2>${t('friends_online')}</h2><div class="friend-strip">${online.map((f) => `
        <div class="card row">${bust(f)}<div class="grow stack" style="gap:4px">
          <a href="/u/${encodeURIComponent(f.username)}" data-link><b>${nameHtml(f)}</b></a>${status(f)}
          ${f.playing ? `<button class="btn small mint" data-play="${esc(f.playing.server_id)}">${t('join')}</button>` : ''}
        </div></div>`).join('')}</div>`;
    }
  },

  '/download'(root) {
    root.innerHTML = `<div class="hero"><div>
        <h1>${t('download_title')}</h1><p>${t('download_text')}</p>
        <a class="btn big" href="${DOWNLOADS.android}">${t('get_app')}</a>
        <p class="muted">${t('apk_note')}</p>
        <h3 style="margin-top:26px">${t('other_platforms')}</h3>
        <div class="row" style="flex-wrap:wrap"><a class="btn ghost" href="${DOWNLOADS.windows}">${t('get_windows')}</a><a class="btn ghost" href="${DOWNLOADS.linux}">${t('get_linux')}</a></div>
        <p class="muted">${t('desktop_note')}</p></div>
        <img class="cover" src="/img/cover.png" alt=""></div>`;
  },

  '/login'(root) { authPage(root, 'login'); },
  '/register'(root) { authPage(root, 'register'); },

  async '/friends'(root) {
    if (!state.me) return go('/login');
    root.innerHTML = `<h1>${t('friends')}</h1>
      <input id="q" placeholder="${t('search')}" autocomplete="off">
      <div class="tabs" style="margin:16px 0">${['friends', 'incoming', 'outgoing'].map((k, i) => `<button data-tab="${k}" class="${i === 0 ? 'on' : ''}">${t(['my_friends', 'requests', 'sent'][i])}</button>`).join('')}</div>
      <div class="stack" id="list"></div>`;
    let data = await api('GET', '/api/friends');
    let tab = 'friends';
    const draw = (items, emptyKey) => {
      $('#list').innerHTML = items.length ? items.map(userRow).join('') : `<div class="empty">${t(emptyKey)}</div>`;
    };
    const show = () => draw(data[tab], { friends: 'no_friends', incoming: 'no_requests', outgoing: 'no_sent' }[tab]);
    root.querySelectorAll('[data-tab]').forEach((b) => b.addEventListener('click', () => {
      tab = b.dataset.tab;
      root.querySelectorAll('[data-tab]').forEach((x) => x.classList.toggle('on', x === b));
      $('#q').value = '';
      show();
    }));
    let timer;
    $('#q').addEventListener('input', () => {
      clearTimeout(timer);
      timer = setTimeout(async () => {
        const q = $('#q').value.trim();
        if (q.length < 2) return show();
        const r = await api('GET', '/api/users/search?q=' + encodeURIComponent(q));
        draw(r.users, 'nobody');
      }, 300);
    });
    root.addEventListener('refresh', async () => { data = await api('GET', '/api/friends'); show(); });
    show();
  },

  async '/settings'(root) {
    if (!state.me) return go('/login');
    root.innerHTML = `<h1>${t('settings')}</h1><div class="grid2">
      <div class="card stack"><h3>${t('language')}</h3>
        <div class="tabs">${['en', 'ru'].map((l) => `<button data-lang="${l}" class="${state.lang === l ? 'on' : ''}">${l === 'en' ? 'English' : 'Русский'}</button>`).join('')}</div>
        <p class="muted">${t('edit_in_app')}</p></div>
      <form class="card stack" id="pw"><h3>${t('change_password')}</h3>
        <input type="password" name="old" placeholder="${t('current_password')}" required>
        <input type="password" name="new" placeholder="${t('new_password')}" minlength="6" required>
        <div class="error"></div><button class="btn ghost">${t('change_password')}</button>
        <button type="button" class="btn danger" id="logout">${t('sign_out')}</button></form></div>`;
    $('#pw').addEventListener('submit', async (e) => {
      e.preventDefault();
      const f = new FormData(e.target);
      try {
        await api('POST', '/api/me/password', { old_password: f.get('old'), new_password: f.get('new') });
        e.target.reset();
        toast(t('saved'));
      } catch (err) { $('.error', e.target).textContent = err.message; }
    });
    $('#logout').addEventListener('click', async () => {
      try { await api('POST', '/api/logout'); } catch {}
      state.token = ''; state.me = null; localStorage.removeItem('token');
      toast(t('signed_out'));
      go('/');
    });
  },
};

function landing(root) {
  root.innerHTML = `<section class="hero"><div>
      <h1>${t('hero_title')}</h1><p>${t('hero_text')}</p>
      <div class="row" style="flex-wrap:wrap"><a class="btn big" href="${DOWNLOAD_URL}">${t('get_app')}</a>
      <a class="btn ghost big" href="/register" data-link>${t('sign_up')}</a></div>
      <p class="muted" style="font-size:15px">${t('apk_note')} · ${t('other_platforms')} <a href="${DOWNLOADS.windows}" style="color:var(--accent)">Windows</a> / <a href="${DOWNLOADS.linux}" style="color:var(--accent)">Linux</a> · <span id="srv">…</span></p></div>
      <img class="cover" src="/img/cover.png" alt="Meltiew playground"></section>
    <section class="features">
      <div class="card"><b>${t('f1')}</b><span>${t('f1t')}</span></div>
      <div class="card"><b>${t('f2')}</b><span>${t('f2t')}</span></div>
      <div class="card"><b>${t('f3')}</b><span>${t('f3t')}</span></div></section>`;
  api('GET', '/api/health').then(() => { $('#srv').innerHTML = `<i class="dot on"></i> ${t('server_up')}`; })
    .catch(() => { $('#srv').textContent = t('server_down'); });
}

function authPage(root, mode) {
  const reg = mode === 'register';
  root.innerHTML = `<div style="display:grid;place-items:center;min-height:60vh"><form class="card modal stack" id="auth">
    <h3 style="font-size:28px">${t(reg ? 'sign_up' : 'sign_in')}</h3>
    <input name="username" placeholder="${t('username')}" autocomplete="username" required>
    ${reg ? `<input name="display_name" placeholder="${t('display_name')}">` : ''}
    <input name="password" type="password" placeholder="${t('password')}" autocomplete="${reg ? 'new-password' : 'current-password'}" required>
    ${reg ? `<input name="password2" type="password" placeholder="${t('repeat')}" required>` : ''}
    <div class="error"></div>
    <button class="btn big">${t(reg ? 'create' : 'sign_in')}</button>
    <p class="muted" style="margin:0;text-align:center">${t(reg ? 'have_account' : 'no_account')} <a href="${reg ? '/login' : '/register'}" data-link style="color:var(--accent)">${t(reg ? 'sign_in' : 'sign_up')}</a></p>
  </form></div>`;
  $('#auth').addEventListener('submit', async (e) => {
    e.preventDefault();
    const f = Object.fromEntries(new FormData(e.target));
    const err = $('.error', e.target);
    if (reg && f.password !== f.password2) return (err.textContent = t('passwords_mismatch'));
    try {
      const r = await api('POST', reg ? '/api/register' : '/api/login', f);
      state.token = r.token; state.me = r.user; localStorage.setItem('token', r.token);
      go(sessionStorage.getItem('after_login') || '/');
      sessionStorage.removeItem('after_login');
    } catch (ex) { err.textContent = ex.message; }
  });
}

function userRow(u) {
  return `<div class="card row">${bust(u)}
    <div class="grow"><a href="/u/${encodeURIComponent(u.username)}" data-link><b>${nameHtml(u)}</b> <span class="muted">@${esc(u.username)}</span></a><div style="margin-top:6px">${status(u)}</div></div>
    ${u.playing ? `<button class="btn small mint" data-play="${esc(u.playing.server_id)}">${t('join')}</button>` : ''}
    <a class="btn small ghost" href="/u/${encodeURIComponent(u.username)}" data-link>›</a></div>`;
}

async function profilePage(root, username) {
  if (!state.me) { sessionStorage.setItem('after_login', location.pathname); return go('/login'); }
  let u;
  try { u = (await api('GET', '/api/users/' + encodeURIComponent(username))).user; }
  catch { root.innerHTML = `<div class="empty">${t('not_found')}</div>`; return; }
  const me = u.id === state.me.id;
  const joined = new Date(u.created_at).toLocaleDateString(state.lang === 'ru' ? 'ru-RU' : 'en-US');
  const rel = u.relation || 'none';
  const friendBtn = me || rel === 'blocked' ? '' : {
    friends: `<button class="btn ghost" data-act="/api/friends/remove">${t('remove_friend')}</button>`,
    outgoing: `<button class="btn ghost" data-act="/api/friends/remove">${t('cancel_request')}</button>`,
    incoming: `<button class="btn mint" data-act="/api/friends/accept">${t('accept')}</button>`,
    none: `<button class="btn" data-act="/api/friends/request">${t('add_friend')}</button>`,
  }[rel];
  const blockBtn = me ? '' : `<button class="btn ${rel === 'blocked' ? 'ghost' : 'danger'}" data-act="${rel === 'blocked' ? '/api/blocks/remove' : '/api/blocks/add'}">${t(rel === 'blocked' ? 'unblock' : 'block')}</button>`;
  root.innerHTML = `<div class="card profile">${bust(u, 'big')}
    <div><h1 style="margin-bottom:4px">${nameHtml(u)}</h1><div class="muted">@${esc(u.username)}</div>
      <div style="margin-top:12px">${status(u)}</div>
      <p>${u.bio ? esc(u.bio) : `<span class="muted">${t('no_bio')}</span>`}</p>
      <div class="stats"><div><b>${u.friends}</b><span class="muted">${t('friends_count')}</span></div><div><b>${joined}</b><span class="muted">${t('member_since')}</span></div></div>
      <div class="row" style="flex-wrap:wrap">${u.playing && !me ? `<button class="btn mint" data-play="${esc(u.playing.server_id)}">${t('join')}</button>` : ''}${friendBtn}${blockBtn}</div>
      ${me ? `<p class="muted">${t('edit_in_app')}</p>` : ''}
    </div></div>`;
  root.querySelectorAll('[data-act]').forEach((b) => b.addEventListener('click', async () => {
    try {
      const r = await api('POST', b.dataset.act, { user_id: u.id });
      toast({ friends: t('now_friends'), outgoing: t('request_sent'), blocked: t('blocked') }[r.relation] || t('done'));
      profilePage(root, username);
    } catch (e) { toast(e.message, 'error'); }
  }));
}

function placeCard(p) {
  const total = p.likes + p.dislikes;
  const rating = total ? Math.round((100 * p.likes) / total) + '%' : '—';
  return `<a class="card place-card" href="/place/${encodeURIComponent(p.id)}" data-link>
    <img src="${esc(p.cover)}" alt="">
    <h3>${esc(field(p, 'name'))}</h3>
    <div class="muted">${t('by')} ${nameHtml(p.author)}</div>
    <div class="row muted" style="gap:14px;margin-top:6px"><span>♥ ${rating}</span><span><i class="dot on"></i> ${esc(t('playing_n', p.playing))}</span></div></a>`;
}

async function placePage(root, id) {
  if (!state.me) { sessionStorage.setItem('after_login', location.pathname); return go('/login'); }
  const draw = async () => {
    const { place: p, servers } = await api('GET', '/api/places/' + encodeURIComponent(id));
    const total = p.likes + p.dislikes;
    const pct = total ? Math.round((100 * p.likes) / total) : 0;
    const created = new Date(p.created_at).toLocaleDateString(state.lang === 'ru' ? 'ru-RU' : 'en-US');
    root.innerHTML = `<a href="/" data-link class="muted">${t('back')}</a>
      <div class="place" style="margin-top:14px">
        <img src="${esc(p.cover)}" alt="">
        <div class="stack">
          <h1 style="margin:0">${esc(field(p, 'name'))}</h1>
          <a class="row" style="gap:10px" href="/u/${encodeURIComponent(p.author.username)}" data-link>${t('by')} ${p.author.id ? bust(p.author, 'small') : ''}<b>${nameHtml(p.author)}</b></a>
          <div class="row" style="flex-wrap:wrap;gap:8px">
            <span class="pill"><i class="dot on"></i>${esc(t('playing_n', p.playing))}</span>
            <span class="pill">${esc(t('visits_n', p.visits))}</span>
            <span class="pill">♥ ${esc(t('liked', total ? pct + '%' : '—'))}</span></div>
          <div class="row">
            <button class="btn ${p.my_vote === 1 ? '' : 'ghost'}" data-vote="${p.my_vote === 1 ? 0 : 1}">${THUMB} ${p.likes}</button>
            <button class="btn ${p.my_vote === -1 ? '' : 'ghost'}" data-vote="${p.my_vote === -1 ? 0 : -1}">${THUMB_DOWN} ${p.dislikes}</button>
            <div class="meter grow"><i style="width:${pct}%;background:var(--online)"></i></div></div>
          <button class="btn big" data-play="auto">▶ ${t('play')}</button>
          <span class="muted" style="font-size:14px">${t('play_hint')}</span>
        </div></div>
      <div class="card" style="margin-top:20px"><h3>${t('about')}</h3><p style="margin:6px 0">${esc(field(p, 'description'))}</p>
        <span class="muted">${esc(t('created', created))}</span></div>
      <div class="row" style="margin-top:30px"><h2 class="grow" style="margin:0">${t('servers')}</h2><button class="btn ghost" data-play="new">${t('new_server')}</button></div>
      <div class="stack" style="margin-top:14px">${servers.length ? servers.map((s) => `<div class="card server">
          <div class="grow"><h3>${esc(field(s, 'name'))}</h3><span class="muted">${s.friends.length ? esc(t('friends_here', s.friends.join(', '))) : '#' + esc(s.id)}</span></div>
          <div class="stack" style="gap:6px;align-items:flex-end"><b>${s.players} / ${s.max_players}</b><div class="meter"><i style="width:${(s.players / s.max_players) * 100}%"></i></div></div>
          <button class="btn mint" data-play="${esc(s.id)}" ${s.players >= s.max_players ? 'disabled' : ''}>${s.players >= s.max_players ? t('full') : t('join')}</button>
        </div>`).join('') : `<div class="empty">${t('no_servers')}</div>`}</div>`;
    root.querySelectorAll('[data-vote]').forEach((b) => b.addEventListener('click', async () => {
      try { await api('POST', `/api/places/${encodeURIComponent(id)}/vote`, { value: Number(b.dataset.vote) }); draw(); }
      catch (e) { toast(e.message, 'error'); }
    }));
  };
  await draw();
}

// --- admin panel --------------------------------------------------------------

async function adminPage(root) {
  if (!isStaff()) return go('/');
  const owner = state.me.role === 'owner';
  let tab = sessionStorage.getItem('admin_tab') || 'overview';
  root.innerHTML = `<h1>${t('admin_panel')}</h1>
    <div class="tabs">${['overview', 'users', 'servers', 'places_admin'].map((k) => `<button data-tab="${k}">${t(k)}</button>`).join('')}</div>
    <div id="admin" class="stack" style="margin-top:18px"></div>`;
  const box = $('#admin');
  const tabs = root.querySelectorAll('[data-tab]');
  const show = async () => {
    sessionStorage.setItem('admin_tab', tab);
    tabs.forEach((b) => b.classList.toggle('on', b.dataset.tab === tab));
    box.innerHTML = '…';
    try { await ({ overview, users, servers, places_admin: placesAdmin })[tab](); }
    catch (e) { box.innerHTML = `<div class="empty">${esc(e.message)}</div>`; }
  };
  tabs.forEach((b) => b.addEventListener('click', () => { tab = b.dataset.tab; show(); }));

  async function overview() {
    const [st, health] = await Promise.all([api('GET', '/api/admin/stats'), api('GET', '/api/health')]);
    const up = `${Math.floor(st.uptime / 3600)}h ${Math.floor((st.uptime % 3600) / 60)}m`;
    const tiles = [['st_users', st.users], ['st_new', st.new_today], ['st_active', st.active_today], ['st_online', st.online],
      ['st_servers', st.servers], ['st_playing', st.playing], ['st_banned', st.banned], ['st_uptime', up], ['st_memory', st.memory_mb + ' MB']];
    box.innerHTML = `<div class="tiles">${tiles.map(([k, v]) => `<div class="card tile"><span class="muted">${t(k)}</span><b>${esc(v)}</b></div>`).join('')}</div>
      <form class="card stack" id="ann"><h3>${t('announce')}</h3><input name="text" maxlength="200" required><button class="btn">${t('send')}</button></form>
      ${owner ? `<form class="card stack" id="minv"><h3>${t('min_version')}</h3><span class="muted">${t('min_version_hint')}</span>
        <input name="version" value="${esc(health.min_client)}" pattern="\\d+\\.\\d+\\.\\d+" required><button class="btn ghost">${t('apply')}</button></form>` : ''}`;
    $('#ann').addEventListener('submit', async (e) => {
      e.preventDefault();
      try { await api('POST', '/api/admin/announce', { text: e.target.text.value }); e.target.reset(); toast(t('sent_ok')); }
      catch (err) { toast(err.message, 'error'); }
    });
    $('#minv')?.addEventListener('submit', async (e) => {
      e.preventDefault();
      try { await api('POST', '/api/admin/min-version', { version: e.target.version.value }); toast(t('saved')); }
      catch (err) { toast(err.message, 'error'); }
    });
  }

  async function users(q = '') {
    const r = await api('GET', '/api/admin/users?q=' + encodeURIComponent(q));
    box.innerHTML = `<input id="uq" placeholder="${t('search')}" value="${esc(q)}"><div class="stack" id="ul"></div>`;
    $('#ul').innerHTML = r.users.map((u) => {
      const canTouch = u.role !== 'owner' && (owner || u.role === 'user');
      return `<div class="card row admin-user">${bust(u)}
        <div class="grow"><a href="/u/${encodeURIComponent(u.username)}" data-link><b>${nameHtml(u)}</b> <span class="muted">@${esc(u.username)}</span></a>
          ${u.banned ? `<span class="badge banned">${t('banned_tag')}</span>` : ''}
          <div class="muted" style="font-size:14px">${u.playing ? esc(t('playing', field(u.playing, 'server_name'))) : esc(t('last_seen', ago(u.last_seen)))}${u.ban_reason ? ' · ' + esc(u.ban_reason) : ''}</div></div>
        ${canTouch ? `<div class="row" style="flex-wrap:wrap;gap:6px;justify-content:flex-end">
          ${u.playing ? `<button class="btn small ghost" data-kick="${u.id}">${t('kick')}</button>` : ''}
          <button class="btn small ghost" data-reset="${u.id}">${t('reset_profile')}</button>
          ${owner ? `<button class="btn small ghost" data-role="${u.id}" data-to="${u.role === 'admin' ? 'user' : 'admin'}">${t(u.role === 'admin' ? 'remove_admin' : 'make_admin')}</button>` : ''}
          <button class="btn small ${u.banned ? 'mint' : 'danger'}" data-ban="${u.id}" data-to="${u.banned ? 0 : 1}">${t(u.banned ? 'unban' : 'ban')}</button></div>` : ''}
      </div>`;
    }).join('');
    let timer;
    $('#uq').addEventListener('input', (e) => { clearTimeout(timer); timer = setTimeout(() => users(e.target.value.trim()), 300); });
    const act = async (fn) => { try { await fn(); toast(t('done')); users($('#uq').value.trim()); } catch (e) { toast(e.message, 'error'); } };
    box.querySelectorAll('[data-ban]').forEach((b) => b.addEventListener('click', () => act(async () => {
      const banned = b.dataset.to === '1';
      const reason = banned ? prompt(t('ban_reason')) ?? '' : '';
      await api('POST', `/api/admin/users/${b.dataset.ban}`, { banned, reason });
    })));
    box.querySelectorAll('[data-role]').forEach((b) => b.addEventListener('click', () => act(() => api('POST', `/api/admin/users/${b.dataset.role}`, { role: b.dataset.to }))));
    box.querySelectorAll('[data-reset]').forEach((b) => b.addEventListener('click', () => act(() => api('POST', `/api/admin/users/${b.dataset.reset}`, { reset_profile: true }))));
    box.querySelectorAll('[data-kick]').forEach((b) => b.addEventListener('click', () => act(() => api('POST', '/api/admin/kick', { user_id: Number(b.dataset.kick) }))));
  }

  async function servers() {
    const r = await api('GET', '/api/admin/servers');
    box.innerHTML = r.servers.length ? r.servers.map((s) => `<div class="card stack">
        <div class="row"><div class="grow"><h3>${esc(field(s, 'name'))}</h3><span class="muted">#${esc(s.id)} · ${s.players}/${s.max_players}</span></div>
        <button class="btn small danger" data-close="${esc(s.id)}">${t('close_server')}</button></div>
        <div class="row" style="flex-wrap:wrap;gap:8px">${s.players_list.map((p) => `<span class="pill">${esc(p.display_name)} <button class="btn small ghost" data-kick="${p.id}">${t('kick')}</button></span>`).join('')}</div>
      </div>`).join('') : `<div class="empty">${t('no_live')}</div>`;
    box.querySelectorAll('[data-close]').forEach((b) => b.addEventListener('click', async () => {
      await api('POST', `/api/admin/servers/${encodeURIComponent(b.dataset.close)}/close`); toast(t('done')); servers();
    }));
    box.querySelectorAll('[data-kick]').forEach((b) => b.addEventListener('click', async () => {
      await api('POST', '/api/admin/kick', { user_id: Number(b.dataset.kick) }); toast(t('done')); servers();
    }));
  }

  async function placesAdmin() {
    const r = await api('GET', '/api/places');
    box.innerHTML = r.places.map((p) => `<form class="card stack" data-place="${esc(p.id)}"><h3>${esc(p.name)}</h3>
      <label class="muted">${t('name_en')}<input name="name" value="${esc(p.name)}"></label>
      <label class="muted">${t('name_ru')}<input name="name_ru" value="${esc(p.name_ru)}"></label>
      <label class="muted">${t('desc_en')}<input name="description" value="${esc(p.description)}"></label>
      <label class="muted">${t('desc_ru')}<input name="description_ru" value="${esc(p.description_ru)}"></label>
      <button class="btn">${t('save')}</button></form>`).join('');
    box.querySelectorAll('[data-place]').forEach((f) => f.addEventListener('submit', async (e) => {
      e.preventDefault();
      try { await api('PATCH', `/api/admin/places/${encodeURIComponent(f.dataset.place)}`, Object.fromEntries(new FormData(f))); toast(t('saved')); }
      catch (err) { toast(err.message, 'error'); }
    }));
  }

  show();
}

// --- router -----------------------------------------------------------------

function go(path) {
  history.pushState({}, '', path);
  render();
}

async function render() {
  const path = location.pathname;
  document.documentElement.lang = state.lang;
  renderNav(path);
  const root = $('#app');
  root.innerHTML = '';
  try {
    if (path.startsWith('/u/')) await profilePage(root, decodeURIComponent(path.slice(3)));
    else if (path.startsWith('/place/')) await placePage(root, decodeURIComponent(path.slice(7)));
    else if (path === '/admin') await adminPage(root);
    else await (pages[path] || pages['/'])(root);
  } catch (e) {
    root.innerHTML = `<div class="empty">${esc(e.message)}</div>`;
  }
}

document.addEventListener('click', (e) => {
  const link = e.target.closest('[data-link]');
  if (link && !e.metaKey && !e.ctrlKey) {
    e.preventDefault();
    return go(link.getAttribute('href'));
  }
  const lang = e.target.closest('[data-lang]');
  if (lang) {
    state.lang = lang.dataset.lang;
    localStorage.setItem('lang', state.lang);
    return render();
  }
  const play = e.target.closest('[data-play]');
  if (play) launch(play.dataset.play);
});
window.addEventListener('popstate', render);

(async () => {
  if (state.token) {
    try { state.me = (await api('GET', '/api/me')).user; } catch { state.me = null; }
  }
  render();
})();
