// Meltiew website: a tiny single-page app on top of the same API the game uses.
const DL_BASE = 'https://github.com/narezy/Meltiew/raw/refs/heads/download/';
const DOWNLOADS = {
  android: DL_BASE + 'meltiew.apk',
  windows: DL_BASE + 'meltiew-windows.zip',
  linux: DL_BASE + 'meltiew-linux.zip',
};
const DOWNLOAD_URL = DOWNLOADS.android;
const PLATFORMS = [
  ['android', 'Android', 'APK · Android 7+'],
  ['windows', 'Windows', 'ZIP · 64-bit'],
  ['linux', 'Linux', 'ZIP · x86_64'],
];
function myPlatform() {
  const ua = navigator.userAgent.toLowerCase();
  if (ua.includes('android')) return 'android';
  if (ua.includes('windows')) return 'windows';
  if (ua.includes('linux') || ua.includes('x11')) return 'linux';
  return 'android';
}
// One big button for the visitor's OS, the other platforms next to it.
function downloadButtons() {
  const mine = myPlatform();
  const sorted = [...PLATFORMS].sort((a, b) => (a[0] === mine ? -1 : b[0] === mine ? 1 : 0));
  return `<div class="dl-grid">${sorted.map(([id, name, note], i) => `
    <a class="btn ${i === 0 ? 'big' : 'ghost'} dl" href="${DOWNLOADS[id]}">
      <span>${esc(t('download_for', name))}</span><small>${note}</small></a>`).join('')}</div>`;
}
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
    download_title: 'Get Meltiew', download_text: 'Android: open the APK and allow installing from your browser if asked. Windows and Linux: unzip and run.',
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
    download_for: 'Download for {0}', get_windows: 'Windows', get_linux: 'Linux', other_platforms: 'Also on', desktop_note: 'Unzip and run Meltiew. Same account, same friends.',
    last_seen: 'last seen {0}',
    messages: 'Messages', chats: 'Chats', dm_requests: 'Requests', no_chats: 'No chats yet. Open a profile and say hi!',
    no_dm_requests: 'No message requests', pick_chat: 'Pick a chat on the left', type_message: 'Message...',
    dm_request_from: '{0} wants to chat with you. Accept to reply.', dm_waiting: 'Sent! You can write more once {0} accepts.',
    dm_first: 'Your first message goes as a request. You can write more once they accept.', dm_unavailable: "You can't message this player.",
    you: 'You: ', message: 'Message', report: 'Report', report_title: 'Report {0}', report_reason: 'What happened?',
    r_chat: 'Rude chat or messages', r_name: 'Bad name or bio', r_avatar: 'Inappropriate avatar', r_cheating: 'Cheating', r_other: 'Something else',
    report_details: 'Details (optional)', report_send: 'Send report', reports: 'Reports', no_reports: 'No open reports', resolve: 'Resolve', reported_by: 'from {0}',
    friends_of: 'Friends', friends_hidden: 'Friends list is hidden', friends_online_n: '{0} online of {1}', no_friends_short: 'No friends yet',
    search_places: 'Search places', no_places: 'Nothing found', birthdate: 'Date of birth', birthdate_why: 'We need it to set up chat safety. After one free fix it can only be changed once every 6 months.',
    birthdate_title: 'When is your birthday?', birthdate_set: 'Set date of birth', continue: 'Continue', privacy: 'Privacy', hide_friends: 'Hide my friends list',
    face: 'Face', face_hint: 'Colors and hats are edited in the app. Faces work here too.',
    rules_kid: 'Under 13: chat and messages are turned off.', rules_teen: 'Chat and messages are filtered.',
    rules_older: 'Game chat is filtered, messages are not.', rules_adult: 'No filters.', rules_none: 'Add your date of birth to play and chat.',
    bd_change_free: 'Fix date of birth (one free change)', bd_change: 'Change date of birth', bd_next_change: 'You can change it again on {0}.',
    bd_change_why: 'Pick your real date of birth. After this change the next one is possible in 6 months.',
    search_everything: 'Search players and places', telegram: 'Telegram channel', lang_fallback: "The website isn't translated to this language yet, so it shows English. Places with their own translations will use it.", drag_to_spin: 'Drag to spin', admin_reset_bd: 'Reset birthdate', age_n: '{0} y.o.',
    studio: 'Studio', studio_web_text: 'You build places in the app (the Studio tab, best on a computer). Here you manage them and your images.',
    studio_docs: 'Studio docs', my_places: 'My places', my_images: 'My images', upload: 'Upload',
    studio_line: '{0} visits · {1} playing · edited {2}', no_my_places: 'No places yet. Open Studio in the app and press New place.',
    delete: 'Delete', delete_place_q: 'Delete this place? This can\'t be undone.', delete_image_q: 'Delete this image? Places using it will lose it.',
    asset_usage: '{0} of {1} images, {2} of {3} MB', copy_id: 'Copy ID', copied: 'Copied', no_images: 'No images yet. Upload a PNG or JPG up to 2 MB.',
    image_too_big: 'The image is bigger than 2 MB', uploaded: 'Uploaded',
    vis_private: 'Only me', vis_friends: 'Friends', vis_public: 'Everyone', who_can_play: 'Who can play', comments_on: 'Comments',
    your_place: 'Your place', edit_in_studio: 'To change the place itself, open it in Studio in the app.', visits_30: 'Visits, last 30 days',
    st_visits: 'Visits', st_players: 'Players', st_returning: 'Came back', st_playtime: 'Total playtime', st_session: 'Average session', st_now: 'Playing now',
    no_description: 'No description yet.', updated: 'updated {0}', places_of: 'Places',
    comments: 'Comments', comments_off: 'The author turned comments off.', comment_placeholder: 'Say something nice about this place',
    comments_too_young: 'Comments open up at 13.', no_comments: 'No comments yet. Be the first!', load_more: 'Show more', delete_comment_q: 'Delete this comment?',
    report_place: 'Report this place', report_comment: 'Report this comment', r_place: 'Inappropriate place', r_comment: 'Rude or spam comment',
    report_about_place: 'Place:', report_open_place: 'Open the place',
    doc_start: 'Getting started', doc_scripting: 'Scripting', doc_ui: 'User interface', doc_strings: 'Translations', doc_marp: 'The .marp file', doc_classes: 'Class reference',
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
    download_title: 'Скачать Meltiew', download_text: 'Android: открой APK и разреши установку из браузера, если спросит. Windows и Linux: распакуй и запусти.',
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
    download_for: 'Скачать для {0}', get_windows: 'Windows', get_linux: 'Linux', other_platforms: 'Ещё есть под', desktop_note: 'Распакуй и запусти Meltiew. Тот же аккаунт, те же друзья.',
    last_seen: 'был(а) {0}',
    messages: 'Сообщения', chats: 'Чаты', dm_requests: 'Запросы', no_chats: 'Чатов пока нет. Открой чей-нибудь профиль и напиши!',
    no_dm_requests: 'Запросов на переписку нет', pick_chat: 'Выбери чат слева', type_message: 'Сообщение...',
    dm_request_from: '{0} хочет с тобой переписываться. Прими, чтобы ответить.', dm_waiting: 'Отправлено! Дальше писать можно, когда {0} примет запрос.',
    dm_first: 'Первое сообщение уйдёт как запрос. Дальше можно будет писать, когда его примут.', dm_unavailable: 'Этому игроку писать нельзя.',
    you: 'Ты: ', message: 'Написать', report: 'Пожаловаться', report_title: 'Жалоба на {0}', report_reason: 'Что случилось?',
    r_chat: 'Грубит в чате или личке', r_name: 'Плохой ник или описание', r_avatar: 'Неприличный аватар', r_cheating: 'Читерит', r_other: 'Другое',
    report_details: 'Подробности (необязательно)', report_send: 'Отправить жалобу', reports: 'Жалобы', no_reports: 'Открытых жалоб нет', resolve: 'Закрыть', reported_by: 'от {0}',
    friends_of: 'Друзья', friends_hidden: 'Список друзей скрыт', friends_online_n: 'в сети {0} из {1}', no_friends_short: 'Друзей пока нет',
    search_places: 'Поиск плейсов', no_places: 'Ничего не нашли', birthdate: 'Дата рождения', birthdate_why: 'Нужна, чтобы настроить безопасность чата. После одного бесплатного исправления менять можно раз в полгода.',
    birthdate_title: 'Когда у тебя день рождения?', birthdate_set: 'Указать дату рождения', continue: 'Продолжить', privacy: 'Приватность', hide_friends: 'Скрыть мой список друзей',
    face: 'Лицо', face_hint: 'Цвета и шапки меняются в приложении. А лицо можно и тут.',
    rules_kid: 'До 13 лет чат и личные сообщения выключены.', rules_teen: 'Чат и личные сообщения фильтруются.',
    rules_older: 'Игровой чат фильтруется, личные сообщения нет.', rules_adult: 'Без фильтров.', rules_none: 'Укажи дату рождения, чтобы играть и общаться.',
    bd_change_free: 'Исправить дату рождения (одна бесплатная смена)', bd_change: 'Сменить дату рождения', bd_next_change: 'Снова сменить можно будет {0}.',
    bd_change_why: 'Выбери настоящую дату рождения. После этой смены следующая будет доступна через полгода.',
    search_everything: 'Поиск игроков и плейсов', telegram: 'Телеграм-канал', lang_fallback: 'Сайт пока не переведён на этот язык, поэтому он на английском. Плейсы со своими переводами будут на нём.', drag_to_spin: 'Потяни, чтобы покрутить', admin_reset_bd: 'Сбросить дату рождения', age_n: '{0} лет',
    studio: 'Студия', studio_web_text: 'Плейсы строятся в приложении (вкладка Студия, лучше с компьютера). Здесь ими и картинками можно управлять.',
    studio_docs: 'Документация студии', my_places: 'Мои плейсы', my_images: 'Мои картинки', upload: 'Загрузить',
    studio_line: '{0} визитов · {1} играют · изменён {2}', no_my_places: 'Плейсов пока нет. Открой Студию в приложении и нажми «Новый плейс».',
    delete: 'Удалить', delete_place_q: 'Удалить плейс? Вернуть не получится.', delete_image_q: 'Удалить картинку? Плейсы, где она стоит, её потеряют.',
    asset_usage: '{0} из {1} картинок, {2} из {3} МБ', copy_id: 'Копировать ID', copied: 'Скопировано', no_images: 'Картинок пока нет. Загрузи PNG или JPG до 2 МБ.',
    image_too_big: 'Картинка больше 2 МБ', uploaded: 'Загружено',
    vis_private: 'Только я', vis_friends: 'Друзья', vis_public: 'Все', who_can_play: 'Кто может играть', comments_on: 'Комментарии',
    your_place: 'Твой плейс', edit_in_studio: 'Сам плейс меняется в Студии в приложении.', visits_30: 'Визиты за 30 дней',
    st_visits: 'Визиты', st_players: 'Игроки', st_returning: 'Вернулись', st_playtime: 'Всего наиграно', st_session: 'Средняя сессия', st_now: 'Играют сейчас',
    no_description: 'Описания пока нет.', updated: 'обновлён {0}', places_of: 'Плейсы',
    comments: 'Комментарии', comments_off: 'Автор выключил комментарии.', comment_placeholder: 'Скажи что-нибудь хорошее про плейс',
    comments_too_young: 'Комментарии доступны с 13 лет.', no_comments: 'Комментариев пока нет. Будь первым!', load_more: 'Показать ещё', delete_comment_q: 'Удалить комментарий?',
    report_place: 'Пожаловаться на плейс', report_comment: 'Пожаловаться на комментарий', r_place: 'Неприемлемый плейс', r_comment: 'Грубость или спам',
    report_about_place: 'Плейс:', report_open_place: 'Открыть плейс',
    doc_start: 'С чего начать', doc_scripting: 'Скрипты', doc_ui: 'Интерфейс', doc_strings: 'Переводы', doc_marp: 'Файл .marp', doc_classes: 'Справочник классов',
  },
};

// English by default; the EN/RU switch in the header is remembered.
const LANG_CODES = new Set((window.LANGUAGES || []).map(([c]) => c));
// First visit follows the browser language; the interface falls back to English past EN/RU.
const firstLang = () => {
  const nav = (navigator.language || 'en').slice(0, 2).toLowerCase();
  return LANG_CODES.has(nav) ? nav : 'en';
};
const state = {
  lang: LANG_CODES.has(localStorage.getItem('lang')) ? localStorage.getItem('lang') : firstLang(),
  token: localStorage.getItem('token') || '',
  me: null,
};

const $ = (sel, root = document) => root.querySelector(sel);
const t = (key, ...args) => (T[state.lang]?.[key] ?? T.en[key] ?? key).replace(/\{(\d)\}/g, (_, i) => args[i]);
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

async function launch(server = 'auto', game = 'playground') {
  if (!state.me) return go('/login');
  if (!(await askBirthdate(true))) return;
  try {
    await api('POST', '/api/launch', { server, game });
  } catch (e) {
    return toast(e.message, 'error');
  }
  const isAndroid = /android/i.test(navigator.userAgent);
  const fallback = encodeURIComponent(location.origin + '/download');
  // The link carries where to go, so the app can show "Joining..." the moment it opens.
  const q = `server=${encodeURIComponent(server)}&game=${encodeURIComponent(game)}`;
  const url = isAndroid
    ? `intent://play?${q}#Intent;scheme=meltiew;package=${PACKAGE};S.browser_fallback_url=${fallback};end`
    : `meltiew://play?${q}`;
  modal(`<h3>${t('opening')}</h3><p class="muted">${t('opening_text')}</p>
    <div class="row"><a class="btn ghost grow" href="/download" data-link>${t('download')}</a><button class="btn grow" data-close>${t('close')}</button></div>`);
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

const ICONS = {
  home: '<path d="M4 11.5 12 5l8 6.5V20a1 1 0 0 1-1 1h-4.5v-5.5h-5V21H5a1 1 0 0 1-1-1z"/>',
  friends: '<circle cx="9" cy="8.5" r="3.3"/><path d="M3.5 19.5c.6-3.3 2.8-5 5.5-5s4.9 1.7 5.5 5"/><circle cx="16.5" cy="9.5" r="2.6"/><path d="M16.5 14.4c2.2 0 3.7 1.4 4.1 4"/>',
  messages: '<path d="M4.5 5.5h15a1 1 0 0 1 1 1v9.5a1 1 0 0 1-1 1H10l-4.5 3.5V17h-1a1 1 0 0 1-1-1V6.5a1 1 0 0 1 1-1z"/>',
  download: '<path d="M12 4v11M7 10.5l5 5 5-5M5 20h14"/>',
  settings: '<circle cx="12" cy="12" r="3"/><path d="M12 3v2.5M12 18.5V21M3 12h2.5M18.5 12H21M5.6 5.6l1.8 1.8M16.6 16.6l1.8 1.8M5.6 18.4l1.8-1.8M16.6 7.4l1.8-1.8"/>',
  admin_panel: '<path d="M12 3.5 19 6v5.5c0 4.4-3 7.7-7 9-4-1.3-7-4.6-7-9V6z"/>',
  send: '<path d="M4 12 20 4l-4.5 16-3.5-6.5z"/>',
  telegram: '<path d="M20.5 4.5 3.5 11l5.5 2 2 6 3-4 5 3.5z"/>',
  studio: '<path d="M8.5 7 3.5 12l5 5M15.5 7l5 5-5 5M13.5 4.5l-3 15"/>',
};
const icon = (name, size = 22) => `<svg class="ic" width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.1" stroke-linecap="round" stroke-linejoin="round">${ICONS[name] || ''}</svg>`;
const TELEGRAM = 'https://t.me/meltiew';

// Unread messages and friend requests, shown as badges in the navigation.
const counts = { friends: 0, messages: 0, social: 0 };
function paintBadges() {
  document.querySelectorAll('[data-count]').forEach((el) => {
    const n = counts[el.dataset.count] || 0;
    el.textContent = n > 99 ? '99+' : n;
    el.hidden = n === 0;
  });
}
async function pollCounts() {
  if (!state.me) return;
  try {
    const n = await api('GET', '/api/notifications');
    counts.friends = n.friend_requests;
    counts.messages = n.dm_unread + n.dm_requests;
    counts.social = counts.friends + counts.messages;
    paintBadges();
  } catch {}
}
setInterval(pollCounts, 15000);

function renderNav(path) {
  // Friends and chats share one tab; its badge counts requests and unread messages together.
  const links = [['/', 'home'], ...(state.me ? [['/friends', 'friends'], ['/studio', 'studio']] : []), ['/download', 'download'], ...(state.me ? [['/settings', 'settings']] : []), ...(isStaff() ? [['/admin', 'admin_panel']] : [])];
  const on = (href) => (href === '/' ? path === '/' || path.startsWith('/place/')
    : href === '/friends' ? path.startsWith('/friends') || path.startsWith('/messages')
    : href === '/studio' ? path.startsWith('/studio') || path.startsWith('/docs') : path.startsWith(href));
  const count = (key) => (key === 'friends' ? '<b class="count" data-count="social" hidden></b>' : '');
  $('#nav').innerHTML = `
    <a class="brand" href="/" data-link><img src="/img/logo.svg" alt=""><span>meltiew</span></a>
    <div class="nav-links">${links.map(([href, key]) => `<a href="${href}" data-link class="${on(href) ? 'on' : ''}">${t(key)}${count(key)}</a>`).join('')}</div>
    <div class="nav-right">
      <select class="lang" id="langsel" aria-label="${t('language')}">${(window.LANGUAGES || [['en', 'English']]).map(([c, n]) => `<option value="${c}" ${state.lang === c ? 'selected' : ''}>${esc(n)}</option>`).join('')}</select>
      ${state.me
        ? `<a class="me-chip" href="/u/${encodeURIComponent(state.me.username)}" data-link>${bust(state.me)}<span>${nameHtml(state.me)}</span></a>`
        : `<a class="btn small" href="/login" data-link>${t('sign_in')}</a>`}
    </div>`;
  $('#nav').querySelectorAll('.me-chip .bust').forEach((b) => { b.style.width = b.style.height = '34px'; });
  $('#langsel').addEventListener('change', (e) => setLang(e.target.value));
  // Phones get an app-style tab bar at the bottom instead of a row of links.
  const bar = $('#tabbar');
  bar.innerHTML = links.map(([href, key]) => `<a href="${href}" data-link class="${on(href) ? 'on' : ''}">${icon(key)}<span>${t(key)}</span>${count(key)}</a>`).join('');
  paintBadges();
}

// Asks once per visit for a date of birth when the account has none. Resolves true once it's set.
function askBirthdate(force = false, changing = false) {
  if (!state.me || (state.me.birthdate && !changing)) return Promise.resolve(true);
  if (!force && sessionStorage.getItem('bd_asked')) return Promise.resolve(false);
  sessionStorage.setItem('bd_asked', '1');
  return new Promise((resolve) => {
    const bg = modal(`<h3>${t('birthdate_title')}</h3><p class="muted" style="margin:0">${t(changing ? 'bd_change_why' : 'birthdate_why')}</p>
      <form class="stack" id="bdf"><input type="date" name="bd" required max="${new Date().toISOString().slice(0, 10)}">
      <div class="error"></div><button class="btn">${t('continue')}</button></form>`);
    const done = (ok) => { bg.remove(); resolve(ok); };
    bg.addEventListener('click', (e) => { if (e.target === bg) resolve(false); });
    $('#bdf', bg).addEventListener('submit', async (e) => {
      e.preventDefault();
      try {
        const r = await api('PATCH', '/api/me', { birthdate: e.target.bd.value });
        state.me = r.user || { ...state.me, birthdate: e.target.bd.value };
        done(true);
      } catch (err) { $('.error', bg).textContent = err.message; }
    });
  });
}

// Pages register timers here; they are cleared when the route changes.
let cleanups = [];
const onLeave = (fn) => cleanups.push(fn);

// --- pages ------------------------------------------------------------------

const pages = {
  async '/'(root) {
    if (!state.me) return landing(root);
    root.innerHTML = `<h1>${esc(t('hi', state.me.display_name))}</h1><div id="fo"></div>
      <div class="row section-head"><h2 class="grow">${t('places')}</h2>
        <input id="pq" class="search" type="search" placeholder="${t('search_everything')}" autocomplete="off"></div>
      <div id="people"></div>
      <div class="places" id="places">${'<div class="card place-card skel-card"><i class="skel" style="height:auto;aspect-ratio:16/9"></i><i class="skel" style="width:60%;height:20px"></i><i class="skel" style="width:40%"></i></div>'.repeat(3)}</div>`;
    $('#fo').innerHTML = `<div class="carousel">${'<span class="chip"><i class="skel" style="width:76px;height:76px;border-radius:50%"></i><i class="skel" style="width:70px"></i></span>'.repeat(5)}</div>`;
    const loadPlaces = async () => {
      const q = $('#pq').value.trim();
      $('#pq').classList.add('busy');
      const [r, people] = await Promise.all([
        api('GET', '/api/places' + (q ? '?q=' + encodeURIComponent(q) : '')),
        q.length >= 2 ? api('GET', '/api/users/search?q=' + encodeURIComponent(q)) : { users: [] },
      ]);
      // Strangers open their profile; only friends are joined with one tap.
      $('#people').innerHTML = people.users.length ? `<div class="muted" style="font-weight:800;margin-bottom:8px">${t('users')}</div>
        <div class="carousel" style="margin-bottom:18px">${people.users.map((u) => friendChip(u.relation === 'friends' ? u : { ...u, playing: null })).join('')}</div>` : '';
      $('#pq').classList.remove('busy');
      $('#places').innerHTML = r.places.length ? r.places.map(placeCard).join('') : `<div class="empty">${t('no_places')}</div>`;
    };
    let timer;
    $('#pq').addEventListener('input', () => { clearTimeout(timer); timer = setTimeout(loadPlaces, 300); });
    const loadFriends = async () => {
      const { friends } = await api('GET', '/api/friends');
      if (!$('#fo')) return;
      $('#fo').innerHTML = friends.length ? `<div class="row section-head"><h2>${t('friends')}</h2>
        <span class="muted">${esc(t('friends_online_n', friends.filter((f) => f.online).length, friends.length))}</span></div>
        <div class="carousel">${sortFriends(friends).map(friendChip).join('')}</div>` : '';
    };
    await Promise.all([loadPlaces(), loadFriends()]);
    const iv = setInterval(loadFriends, 15000);
    onLeave(() => clearInterval(iv));
  },

  '/download'(root) {
    root.innerHTML = `<div class="hero"><div>
        <h1>${t('download_title')}</h1><p>${t('download_text')}</p>
        ${downloadButtons()}
        <p class="muted">${t('desktop_note')}</p></div>
        <img class="cover" src="/img/cover.png" alt=""></div>`;
  },

  '/login'(root) { authPage(root, 'login'); },
  '/register'(root) { authPage(root, 'register'); },

  async '/friends'(root) {
    if (!state.me) return go('/login');
    root.innerHTML = `${socialHeader('friends')}
      <input id="q" placeholder="${t('search')}" autocomplete="off">
      <div class="tabs" style="margin:16px 0">${['friends', 'incoming', 'outgoing'].map((k, i) => `<button data-tab="${k}" class="${i === 0 ? 'on' : ''}">${t(['my_friends', 'requests', 'sent'][i])}</button>`).join('')}</div>
      <div class="stack" id="list">${'<div class="card row"><i class="skel" style="width:52px;height:52px;border-radius:50%"></i><span class="grow stack" style="gap:8px"><i class="skel" style="width:40%"></i><i class="skel" style="width:25%"></i></span></div>'.repeat(4)}</div>`;
    let data = await api('GET', '/api/friends');
    let tab = 'friends';
    const actions = (u) => (tab === 'incoming'
      ? `<button class="btn small mint" data-fr="/api/friends/accept" data-uid="${u.id}">${t('accept')}</button><button class="btn small ghost" data-fr="/api/friends/remove" data-uid="${u.id}">${t('decline')}</button>`
      : tab === 'outgoing' ? `<button class="btn small ghost" data-fr="/api/friends/remove" data-uid="${u.id}">${t('cancel_request')}</button>` : '');
    const draw = (items, emptyKey, plain = false) => {
      $('#list').innerHTML = items.length ? items.map((u) => userRow(u, plain ? '' : actions(u))).join('') : `<div class="empty">${t(emptyKey)}</div>`;
      $('#list').querySelectorAll('[data-fr]').forEach((b) => b.addEventListener('click', async () => {
        b.disabled = true;
        try {
          await api('POST', b.dataset.fr, { user_id: Number(b.dataset.uid) });
          data = await api('GET', '/api/friends');
          show();
          pollCounts();
        } catch (e) { toast(e.message, 'error'); b.disabled = false; }
      }));
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
        draw(r.users, 'nobody', true);
      }, 300);
    });
    root.addEventListener('refresh', async () => { data = await api('GET', '/api/friends'); show(); });
    show();
  },

  async '/settings'(root) {
    if (!state.me) return go('/login');
    const me = state.me;
    const rules = me.rules || {};
    const rulesKey = !me.birthdate ? 'rules_none' : !rules.chat ? 'rules_kid' : rules.filter_dm ? 'rules_teen' : rules.filter_chat ? 'rules_older' : 'rules_adult';
    root.innerHTML = `<h1>${t('settings')}</h1><div class="grid2">
      <div class="card stack"><h3>${t('language')}</h3>
        <select id="langsel2">${(window.LANGUAGES || []).map(([c, n]) => `<option value="${c}" ${state.lang === c ? 'selected' : ''}>${esc(n)}</option>`).join('')}</select>
        ${state.lang !== 'en' && state.lang !== 'ru' ? `<span class="muted">${t('lang_fallback')}</span>` : ''}</div>
      <div class="card stack"><h3>${t('privacy')}</h3>
        <label class="switch"><input type="checkbox" id="hf" ${me.hide_friends ? 'checked' : ''}><i></i>${t('hide_friends')}</label>
        <div><span class="muted">${t('birthdate')}:</span> ${me.birthdate
          ? `<b>${esc(new Date(me.birthdate + 'T00:00').toLocaleDateString(state.lang === 'ru' ? 'ru-RU' : 'en-US'))}</b>`
          : `<button class="btn small" id="setbd">${t('birthdate_set')}</button>`}</div>
        ${me.birthdate && me.birthdate_change?.can ? `<button class="btn small ghost" id="changebd">${t(me.birthdate_change.free ? 'bd_change_free' : 'bd_change')}</button>` : ''}
        ${me.birthdate && !me.birthdate_change?.can && me.birthdate_change?.next_at ? `<span class="muted" style="font-size:14px">${esc(t('bd_next_change', new Date(me.birthdate_change.next_at).toLocaleDateString(state.lang === 'ru' ? 'ru-RU' : 'en-US')))}</span>` : ''}
        <span class="muted">${t(rulesKey)}</span></div>
      <div class="card stack" style="grid-column:1/-1"><h3>${t('face')}</h3><span class="muted">${t('face_hint')}</span>
        <div class="faces">${Object.entries(FACE_SLUGS).map(([id, slug]) => `<button class="face ${me.face === id ? 'on' : ''}" data-face="${esc(id)}" title="${esc(id)}"><img src="/img/faces/${slug}.png" alt="${esc(id)}"></button>`).join('')}</div></div>
      <form class="card stack" id="pw"><h3>${t('change_password')}</h3>
        <input type="password" name="old" placeholder="${t('current_password')}" required>
        <input type="password" name="new" placeholder="${t('new_password')}" minlength="6" required>
        <div class="error"></div><button class="btn ghost">${t('change_password')}</button>
        <button type="button" class="btn danger" id="logout">${t('sign_out')}</button></form>
      <a class="card stack tg" href="${TELEGRAM}" target="_blank" rel="noopener"><h3>${icon('telegram')} ${t('telegram')}</h3><span class="muted">t.me/meltiew</span></a></div>`;
    $('#langsel2').addEventListener('change', (e) => setLang(e.target.value));
    const patch = async (body) => {
      try { const r = await api('PATCH', '/api/me', body); state.me = r.user; toast(t('saved')); return true; }
      catch (e) { toast(e.message, 'error'); return false; }
    };
    $('#hf').addEventListener('change', (e) => patch({ hide_friends: e.target.checked }));
    $('#setbd')?.addEventListener('click', async () => { if (await askBirthdate(true)) render(); });
    $('#changebd')?.addEventListener('click', async () => { if (await askBirthdate(true, true)) render(); });
    root.querySelectorAll('[data-face]').forEach((b) => b.addEventListener('click', async () => {
      if (!(await patch({ face: b.dataset.face }))) return;
      root.querySelectorAll('[data-face]').forEach((x) => x.classList.toggle('on', x === b));
      try { await uploadMyBust(); renderNav(location.pathname); } catch (e) { console.warn('bust render failed', e); }
    }));
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
      ${downloadButtons()}
      <div class="row" style="margin-top:14px;flex-wrap:wrap"><a class="btn ghost" href="/register" data-link>${t('sign_up')}</a>
      <a class="btn ghost" href="${TELEGRAM}" target="_blank" rel="noopener">${icon('telegram', 20)}Telegram</a>
      <span class="muted" style="font-size:15px"><span id="srv">…</span></span></div></div>
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
    ${reg ? `<input name="password2" type="password" placeholder="${t('repeat')}" required>
      <label class="muted">${t('birthdate')}<input name="birthdate" type="date" required max="${new Date().toISOString().slice(0, 10)}"></label>
      <span class="muted" style="font-size:13px;margin-top:-6px">${t('birthdate_why')}</span>` : ''}
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

// `actions`: extra buttons, e.g. accepting or declining a friend request.
function userRow(u, actions = '') {
  return `<div class="card row user-row">${bust(u)}
    <div class="grow"><a href="/u/${encodeURIComponent(u.username)}" data-link><b>${nameHtml(u)}</b> <span class="muted">@${esc(u.username)}</span></a><div style="margin-top:6px">${status(u)}</div></div>
    ${u.playing ? `<button class="btn small mint" data-play="${esc(u.playing.server_id)}">${t('join')}</button>` : ''}
    ${actions || `<a class="btn small ghost" href="/u/${encodeURIComponent(u.username)}" data-link>›</a>`}</div>`;
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
  const msgBtn = me || rel === 'blocked' ? '' : `<button class="btn ghost" id="dm">${icon('messages', 20)}${t('message')}</button>`;
  const more = me ? '' : `<div class="row more">
    <button class="link" id="report">${t('report')}</button>
    <button class="link ${rel === 'blocked' ? '' : 'danger'}" data-act="${rel === 'blocked' ? '/api/blocks/remove' : '/api/blocks/add'}">${t(rel === 'blocked' ? 'unblock' : 'block')}</button></div>`;
  root.innerHTML = `<div class="card profile">
    <div class="stage" id="stage" title="${esc(t('drag_to_spin'))}">${bust(u, 'big')}</div>
    <div><h1 style="margin-bottom:4px">${nameHtml(u)}</h1><div class="muted">@${esc(u.username)}</div>
      <div style="margin-top:12px">${status(u)}</div>
      <p>${u.bio ? esc(u.bio) : `<span class="muted">${t('no_bio')}</span>`}</p>
      <div class="stats"><div><b>${u.friends}</b><span class="muted">${t('friends_count')}</span></div><div><b>${joined}</b><span class="muted">${t('member_since')}</span></div></div>
      <div class="row" style="flex-wrap:wrap">${u.playing && !me ? `<button class="btn mint" data-play="${esc(u.playing.server_id)}">${t('join')}</button>` : ''}${friendBtn}${msgBtn}</div>
      ${more}
      ${me ? `<p class="muted">${t('edit_in_app')}</p>` : ''}
    </div></div>
    <div id="pplaces"></div>
    <h2>${t('friends_of')}</h2><div id="pf"><div class="loader"><i></i></div></div>`;
  mellyViewer($('#stage'), u);
  api('GET', `/api/users/${encodeURIComponent(u.username)}/places`).then((r) => {
    const box = $('#pplaces');
    if (box && r.places.length) box.innerHTML = `<h2>${t('places_of')}</h2><div class="places" style="margin-bottom:10px">${r.places.map(placeCard).join('')}</div>`;
  }).catch(() => {});
  api('GET', `/api/users/${encodeURIComponent(u.username)}/friends`).then((r) => {
    const box = $('#pf');
    if (!box) return;
    if (r.hidden) box.innerHTML = `<div class="empty">${t('friends_hidden')}</div>`;
    else if (!r.friends.length) box.innerHTML = `<div class="empty">${t('no_friends_short')}</div>`;
    else box.innerHTML = `<div class="carousel wrap">${r.friends.map(friendChip).join('')}</div>`;
  }).catch(() => {});
  $('#dm')?.addEventListener('click', () => { state.dmOpen = u; go('/friends/chats'); });
  $('#report')?.addEventListener('click', () => reportDialog(u));
  root.querySelectorAll('[data-act]').forEach((b) => b.addEventListener('click', async () => {
    try {
      const r = await api('POST', b.dataset.act, { user_id: u.id });
      toast({ friends: t('now_friends'), outgoing: t('request_sent'), blocked: t('blocked') }[r.relation] || t('done'));
      profilePage(root, username);
    } catch (e) { toast(e.message, 'error'); }
  }));
}

// A player, or with `about` = { place_id } / { comment_id } their place or comment.
function reportDialog(u, about = {}) {
  const reasons = about.place_id ? ['place', 'name', 'other'] : about.comment_id ? ['comment', 'chat', 'other'] : ['chat', 'name', 'avatar', 'cheating', 'other'];
  const title = about.place_id ? t('report_place') : about.comment_id ? t('report_comment') : t('report_title', u.display_name);
  const bg = modal(`<h3>${esc(title)}</h3>
    <form class="stack" id="rep"><span class="muted">${t('report_reason')}</span>
      <div class="stack" style="gap:6px">${reasons.map((r, i) => `<label class="radio"><input type="radio" name="reason" value="${r}" ${i === 0 ? 'checked' : ''}>${t('r_' + r)}</label>`).join('')}</div>
      <input name="details" maxlength="300" placeholder="${t('report_details')}">
      <div class="row"><button type="button" class="btn ghost grow" data-close>${t('close')}</button><button class="btn danger grow">${t('report_send')}</button></div></form>`);
  $('#rep', bg).addEventListener('submit', async (e) => {
    e.preventDefault();
    const f = Object.fromEntries(new FormData(e.target));
    try { const r = await api('POST', '/api/report', { user_id: u.id, ...about, ...f }); toast(r.message || t('done')); bg.remove(); }
    catch (err) { toast(err.message, 'error'); }
  });
}

// --- 3D Melly ------------------------------------------------------------------

const FACE_SLUGS = {
  ':D': 'grin', ':)': 'smile', ':3': 'cat', ':P': 'tongue', ';)': 'wink', ':O': 'wow', xD: 'xd', 'B)': 'cool',
  '^_^': 'happy', owo: 'owo', uwu: 'uwu', '>_<': 'squint', 'T_T': 'cry', '-_-': 'meh', ':|': 'flat', '<3': 'love',
};
const BODY_PARTS = ['torso', 'head', 'arm_l', 'arm_r', 'leg_l', 'leg_r'];
const DEFAULT_COLORS = { torso: '#baa4e2', head: '#f5f1ec', arm_l: '#f5f1ec', arm_r: '#f5f1ec', leg_l: '#302d38', leg_r: '#302d38' };

let threeLibs = null;
async function loadThree() {
  if (!threeLibs) {
    threeLibs = Promise.all([import('three'), import('three/addons/loaders/GLTFLoader.js')])
      .then(([THREE, { GLTFLoader }]) => ({ THREE, GLTFLoader }));
  }
  return threeLibs;
}

// Hats, ported from client/scripts/avatar/hats.gd. Built in melly.glb units relative to the
// Head bone: the head box spans x ±0.69, z ±0.67 and y 0..1.33 above the bone.
function buildHat(THREE, id) {
  const TOP = 1.33;
  const D = Math.PI / 180;
  const root = new THREE.Group();
  const mat = (color, rough = 0.7, metal = 0, emission = 0) => new THREE.MeshStandardMaterial({
    color, roughness: rough, metalness: metal, emissive: emission ? color : 0x000000, emissiveIntensity: emission * 0.6,
  });
  const part = (parent, geo, m, pos, rot = [0, 0, 0]) => {
    const mesh = new THREE.Mesh(geo, m);
    mesh.position.set(...pos);
    mesh.rotation.set(rot[0] * D, rot[1] * D, rot[2] * D, 'YXZ');
    parent.add(mesh);
    return mesh;
  };
  // Godot primitives: prism with the apex on top, ellipsoid spheres, Y-axis tori.
  const prism = (w, h, d) => {
    const shape = new THREE.Shape([new THREE.Vector2(-w / 2, -h / 2), new THREE.Vector2(w / 2, -h / 2), new THREE.Vector2(0, h / 2)]);
    return new THREE.ExtrudeGeometry(shape, { depth: d, bevelEnabled: false }).translate(0, 0, -d / 2);
  };
  const sphere = (r, h, hemi = false) => (hemi
    ? new THREE.SphereGeometry(r, 32, 12, 0, Math.PI * 2, 0, Math.PI / 2).scale(1, h / r, 1)
    : new THREE.SphereGeometry(r, 24, 12).scale(1, h / 2 / r, 1));
  const cyl = (top, bottom, h) => new THREE.CylinderGeometry(top, bottom, h, 32);
  const torus = (inner, outer) => new THREE.TorusGeometry((inner + outer) / 2, (outer - inner) / 2, 16, 48).rotateX(Math.PI / 2);

  switch (id) {
    case 'catears': {
      const fur = mat('#302d38');
      const pink = mat('#ff8fb1');
      for (const side of [-1, 1]) {
        const x = side * 0.42;
        part(root, prism(0.5, 0.55, 0.2), fur, [x, TOP + 0.2, -0.05], [0, 0, -side * 14]);
        part(root, prism(0.3, 0.34, 0.06), pink, [x + side * 0.02, TOP + 0.16, 0.06], [0, 0, -side * 14]);
      }
      break;
    }
    case 'cap': {
      const red = mat('#ff6b6b');
      part(root, sphere(0.74, 0.8, true), red, [0, TOP - 0.2, 0]);
      part(root, new THREE.BoxGeometry(1.1, 0.07, 0.6), red, [0, TOP - 0.17, 0.85], [-6, 0, 0]);
      part(root, sphere(0.08, 0.16), mat('#f4f1ec'), [0, TOP + 0.2, 0]);
      break;
    }
    case 'crown': {
      const gold = mat('#ffd166', 0.3, 0.8);
      part(root, cyl(0.5, 0.47, 0.28), gold, [0, TOP + 0.12, 0]);
      const gems = ['#ff6b6b', '#4cc9f0', '#7ee0c3', '#e056fd', '#ff8fb1'];
      for (let i = 0; i < 5; i++) {
        const a = (Math.PI * 2 * i) / 5;
        const dx = Math.sin(a), dz = Math.cos(a);
        const spike = part(root, prism(0.22, 0.3, 0.08), gold, [dx * 0.47, TOP + 0.4, dz * 0.47]);
        spike.rotation.y = a;
        part(root, sphere(0.06, 0.12), mat(gems[i], 0.2, 0, 0.6), [dx * 0.51, TOP + 0.12, dz * 0.51]);
      }
      break;
    }
    case 'halo': {
      const ring = part(root, torus(0.42, 0.55), mat('#fff3b0', 0.2, 0, 2.2), [0, TOP + 0.45, 0]);
      ring.userData.bob = [TOP + 0.45, TOP + 0.58];
      break;
    }
    case 'tophat': {
      const black = mat('#1f1c27', 0.5);
      part(root, cyl(0.82, 0.82, 0.06), black, [0, TOP + 0.03, 0]);
      part(root, cyl(0.5, 0.46, 0.85), black, [0, TOP + 0.48, 0]);
      part(root, cyl(0.475, 0.47, 0.14), mat('#b89cff'), [0, TOP + 0.16, 0]);
      root.rotation.z = -6 * D;
      break;
    }
    case 'flower': {
      const flower = new THREE.Group();
      flower.position.set(0.5, TOP - 0.05, 0.25);
      flower.rotation.set(20 * D, 0, -35 * D, 'YXZ');
      root.add(flower);
      const pink = mat('#ff8fb1');
      for (let i = 0; i < 5; i++) {
        const a = (Math.PI * 2 * i) / 5;
        part(flower, sphere(0.16, 0.12), pink, [Math.cos(a) * 0.17, 0, Math.sin(a) * 0.17]);
      }
      part(flower, sphere(0.12, 0.18), mat('#ffd166'), [0, 0.04, 0]);
      break;
    }
    case 'headphones': {
      const dark = mat('#2e2940', 0.4);
      part(root, torus(0.72, 0.82), dark, [0, 0.62, 0], [90, 0, 0]);
      for (const side of [-1, 1]) {
        part(root, cyl(0.26, 0.26, 0.2), dark, [side * 0.78, 0.62, 0], [0, 0, 90]);
        part(root, cyl(0.18, 0.18, 0.22), mat('#7ee0c3'), [side * 0.8, 0.62, 0], [0, 0, 90]);
      }
      break;
    }
    default:
      return null;
  }
  return root;
}

// Loads melly.glb dressed as this player: body colors by bone, face texture and hat.
async function buildMelly(u) {
  const { THREE, GLTFLoader } = await loadThree();
  const gltf = await new GLTFLoader().loadAsync('/models/melly.glb');
  const model = gltf.scene;
  const colors = { ...DEFAULT_COLORS, ...(u.colors || {}) };
  const tints = BODY_PARTS.map((p) => new THREE.Color(colors[p]));
  const faceTex = await new THREE.TextureLoader().loadAsync(`/img/faces/${FACE_SLUGS[u.face] || 'grin'}.png`);
  faceTex.flipY = false;
  faceTex.colorSpace = THREE.SRGBColorSpace;
  let head = null;
  model.traverse((o) => {
    if (o.isBone && o.name === 'Head') head = o;
    if (!o.isMesh) return;
    if (o.material.name === 'Face') {
      o.material = new THREE.MeshLambertMaterial({ map: faceTex, transparent: true, alphaTest: 0.4 });
      return;
    }
    // Each vertex takes the color of the bone that moves it most (same as the game's shader).
    const g = o.geometry;
    const idx = g.attributes.skinIndex;
    const wt = g.attributes.skinWeight;
    const base = g.attributes.color;
    const out = new Float32Array(idx.count * 3);
    for (let i = 0; i < idx.count; i++) {
      let best = 0;
      for (let k = 1; k < 4; k++) if (wt.getComponent(i, k) > wt.getComponent(i, best)) best = k;
      const c = tints[idx.getComponent(i, best)] || tints[0];
      const shade = base ? base.getX(i) : 1;
      out[i * 3] = c.r * shade; out[i * 3 + 1] = c.g * shade; out[i * 3 + 2] = c.b * shade;
    }
    g.setAttribute('color', new THREE.BufferAttribute(out, 3));
    o.material = new THREE.MeshLambertMaterial({ vertexColors: true });
  });
  const hat = buildHat(THREE, u.hat);
  if (hat && head) head.add(hat);
  const bobbers = [];
  hat?.traverse((o) => { if (o.userData.bob) bobbers.push(o); });
  // Halo floats up and down like in the game.
  const animateHat = (t) => bobbers.forEach((o) => {
    const [lo, hi] = o.userData.bob;
    o.position.y = lo + (hi - lo) * (0.5 - 0.5 * Math.cos((t / 1.2) * Math.PI));
  });
  return { THREE, gltf, model, animateHat };
}

// Spinning, waving Melly in the player's look. The bust stays as a fallback
// until WebGL and the model are ready, or for good if either fails.
async function mellyViewer(el, u) {
  try {
    const { THREE, gltf, model, animateHat } = await buildMelly(u);
    if (!el.isConnected) return;
    const w = el.clientWidth || 240;
    const h = el.clientHeight || 300;
    const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    renderer.setSize(w, h);
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    const scene = new THREE.Scene();
    scene.add(new THREE.HemisphereLight(0xffffff, 0x5b4a80, 2.2));
    const sun = new THREE.DirectionalLight(0xffffff, 1.6);
    sun.position.set(2, 4, 5);
    scene.add(sun);

    const pivot = new THREE.Group();
    pivot.add(model);
    scene.add(pivot);
    const box = new THREE.Box3().setFromObject(model);
    const size = box.getSize(new THREE.Vector3());
    model.position.y = -box.min.y - size.y / 2;
    const camera = new THREE.PerspectiveCamera(28, w / h, 0.1, 100);
    camera.position.set(0, size.y * 0.04, size.y * 3.1);
    camera.lookAt(0, 0, 0);

    const mixer = new THREE.AnimationMixer(model);
    const clip = (name) => THREE.AnimationClip.findByName(gltf.animations, name);
    const idle = clip('Idle') && mixer.clipAction(clip('Idle')).play();
    const wave = () => {
      if (!clip('Wave')) return;
      const a = mixer.clipAction(clip('Wave'));
      a.reset().setLoop(THREE.LoopOnce, 1).fadeIn(0.15).play();
      idle?.fadeOut(0.15);
      setTimeout(() => { a.fadeOut(0.3); idle?.reset().fadeIn(0.3).play(); }, (clip('Wave').duration - 0.3) * 1000);
    };

    el.innerHTML = '';
    el.appendChild(renderer.domElement);
    el.classList.add('live');
    let yaw = 0.35, spin = 0.25, dragging = false, lastX = 0, moved = 0;
    const cv = renderer.domElement;
    cv.addEventListener('pointerdown', (e) => { dragging = true; lastX = e.clientX; moved = 0; cv.setPointerCapture(e.pointerId); });
    cv.addEventListener('pointermove', (e) => {
      if (!dragging) return;
      const dx = e.clientX - lastX;
      lastX = e.clientX; moved += Math.abs(dx);
      yaw += dx * 0.012; spin = dx * 0.6;
    });
    cv.addEventListener('pointerup', () => { dragging = false; if (moved < 6) wave(); });
    const start = performance.now();
    let last = start;
    setTimeout(wave, 500);
    const frame = () => {
      if (!el.isConnected) { renderer.dispose(); return; }
      const now = performance.now();
      const dt = Math.min((now - last) / 1000, 0.05);
      last = now;
      if (!dragging) { spin += (0.25 - spin) * Math.min(1, dt * 1.5); yaw += spin * dt; }
      pivot.rotation.y = yaw;
      mixer.update(dt);
      animateHat((now - start) / 1000);
      renderer.render(scene, camera);
      requestAnimationFrame(frame);
    };
    frame();
  } catch (e) {
    console.warn('3D preview unavailable', e);
  }
}

// Renders the head-and-shoulders portrait the same way the app does (client/scripts/autoload/busts.gd)
// and uploads it, so a look changed on the website shows up on every picture right away.
// The hash is web-only on purpose: the app re-renders its own version the next time it opens.
async function uploadMyBust() {
  const { THREE, gltf, model } = await buildMelly(state.me);
  const SIZE = 256;
  const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true, preserveDrawingBuffer: true });
  renderer.setSize(SIZE, SIZE);
  renderer.setPixelRatio(1);
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.AgXToneMapping;
  const scene = new THREE.Scene();
  scene.add(new THREE.AmbientLight(0xe6e0ff, 1.6));
  const key = new THREE.DirectionalLight(0xffffff, 3.2);
  key.position.set(1.2, 2.2, 3);
  scene.add(key);
  const fill = new THREE.DirectionalLight(0xb89cff, 1.0);
  fill.position.set(-2.5, 0.8, -2);
  scene.add(fill);
  model.scale.setScalar(0.34);
  model.rotation.y = 0.25;
  scene.add(model);
  const mixer = new THREE.AnimationMixer(model);
  const idle = THREE.AnimationClip.findByName(gltf.animations, 'Idle');
  if (idle) mixer.clipAction(idle).play();
  mixer.update(0);
  const camera = new THREE.PerspectiveCamera(24, 1, 0.05, 50);
  camera.position.set(0.25, 1.66, 2.1);
  camera.lookAt(0, 1.48, 0);
  renderer.render(scene, camera);
  const png = renderer.domElement.toDataURL('image/png').split(',')[1];
  renderer.dispose();
  const r = await api('POST', '/api/me/render', { hash: 'web' + Date.now().toString(36), png });
  state.me.render = r.render;
}

// Playing first, then online, then everyone else.
function sortFriends(list) {
  const rank = (f) => (f.playing ? 2 : f.online ? 1 : 0);
  return [...list].sort((a, b) => rank(b) - rank(a) || a.display_name.localeCompare(b.display_name));
}

// Round avatar with a status ring; tapping a friend who is playing joins their server.
function friendChip(f) {
  const ring = f.playing ? 'play' : f.online ? 'on' : '';
  const inner = `<span class="ring ${ring}">${bust(f)}</span><b>${esc(f.display_name)}</b>`;
  return f.playing
    ? `<button class="chip" data-play="${esc(f.playing.server_id)}">${inner}<small>${t('join')}</small></button>`
    : `<a class="chip" href="/u/${encodeURIComponent(f.username)}" data-link>${inner}</a>`;
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
    const mine = p.author.id === state.me.id;
    const studio = p.kind === 'studio';
    const game = `data-game="${esc(p.id)}"`;
    root.innerHTML = `<a href="/" data-link class="muted">${t('back')}</a>
      <div class="place" style="margin-top:14px">
        <img src="${esc(p.cover)}" alt="">
        <div class="stack">
          <div class="row">${p.cover_square ? `<img class="square" src="${esc(p.cover_square)}" alt="">` : ''}<h1 style="margin:0">${esc(field(p, 'name'))}</h1></div>
          <a class="row" style="gap:10px" href="/u/${encodeURIComponent(p.author.username)}" data-link>${t('by')} ${p.author.id ? bust(p.author, 'small') : ''}<b>${nameHtml(p.author)}</b></a>
          <div class="row" style="flex-wrap:wrap;gap:8px">
            ${p.visibility !== 'public' ? `<span class="pill">${esc(t('vis_' + p.visibility))}</span>` : ''}
            <span class="pill"><i class="dot on"></i>${esc(t('playing_n', p.playing))}</span>
            <span class="pill">${esc(t('visits_n', p.visits))}</span>
            <span class="pill">♥ ${esc(t('liked', total ? pct + '%' : '—'))}</span></div>
          <div class="row">
            <button class="btn ${p.my_vote === 1 ? '' : 'ghost'}" data-vote="${p.my_vote === 1 ? 0 : 1}">${THUMB} ${p.likes}</button>
            <button class="btn ${p.my_vote === -1 ? '' : 'ghost'}" data-vote="${p.my_vote === -1 ? 0 : -1}">${THUMB_DOWN} ${p.dislikes}</button>
            <div class="meter grow"><i style="width:${pct}%;background:var(--online)"></i></div></div>
          <button class="btn big" data-play="auto" ${game}>▶ ${t('play')}</button>
          <span class="muted" style="font-size:14px">${t('play_hint')}</span>
          ${studio && !mine ? `<div class="row more"><button class="link danger" id="report-place">${t('report_place')}</button></div>` : ''}
        </div></div>
      <div class="card" style="margin-top:20px"><h3>${t('about')}</h3><p style="margin:6px 0;white-space:pre-line">${esc(field(p, 'description')) || `<span class="muted">${t('no_description')}</span>`}</p>
        <span class="muted">${esc(t('created', created))}${studio && p.updated_at ? ' · ' + esc(t('updated', ago(p.updated_at))) : ''}</span></div>
      ${studio && mine ? '<div id="owner" style="margin-top:20px"></div>' : ''}
      <div class="row" style="margin-top:30px"><h2 class="grow" style="margin:0">${t('servers')}</h2><button class="btn ghost" data-play="new" ${game}>${t('new_server')}</button></div>
      <div class="stack" style="margin-top:14px">${servers.length ? servers.map((s) => `<div class="card server">
          <div class="grow"><h3>${esc(field(s, 'name'))}</h3><span class="muted">${s.friends.length ? esc(t('friends_here', s.friends.join(', '))) : '#' + esc(s.id)}</span></div>
          <div class="stack" style="gap:6px;align-items:flex-end"><b>${s.players} / ${s.max_players}</b><div class="meter"><i style="width:${(s.players / s.max_players) * 100}%"></i></div></div>
          <button class="btn mint" data-play="${esc(s.id)}" ${game} ${s.players >= s.max_players ? 'disabled' : ''}>${s.players >= s.max_players ? t('full') : t('join')}</button>
        </div>`).join('') : `<div class="empty">${t('no_servers')}</div>`}</div>
      <div id="comments" style="margin-top:30px"></div>`;
    root.querySelectorAll('[data-vote]').forEach((b) => b.addEventListener('click', async () => {
      try { await api('POST', `/api/places/${encodeURIComponent(id)}/vote`, { value: Number(b.dataset.vote) }); draw(); }
      catch (e) { toast(e.message, 'error'); }
    }));
    $('#report-place')?.addEventListener('click', () => reportDialog(p.author, { place_id: p.id }));
    if (studio && mine) ownerPanel($('#owner'), p, draw);
    commentsBlock($('#comments'), p);
  };
  await draw();
}

// Your own place: who can play, comments on/off and the numbers. Editing is in the app's Studio.
async function ownerPanel(box, p, redraw) {
  const vis = ['private', 'friends', 'public'];
  box.innerHTML = `<div class="card stack">
    <div class="row"><h3 class="grow" style="margin:0">${t('your_place')}</h3><a class="link" href="/docs/studio" data-link>${t('studio_docs')}</a></div>
    <span class="muted">${t('edit_in_studio')}</span>
    <div class="row" style="flex-wrap:wrap;gap:14px">
      <label class="stack" style="gap:6px"><span class="muted">${t('who_can_play')}</span>
        <select id="vis">${vis.map((v) => `<option value="${v}" ${p.visibility === v ? 'selected' : ''}>${t('vis_' + v)}</option>`).join('')}</select></label>
      <label class="radio" style="align-self:flex-end"><input type="checkbox" id="cm" ${p.comments_enabled ? 'checked' : ''}>${t('comments_on')}</label>
    </div>
    <div id="pstats"><div class="loader"><i></i></div></div></div>`;
  const patch = async (body) => {
    try { await api('PATCH', `/api/studio/places/${encodeURIComponent(p.id)}`, body); toast(t('saved')); redraw(); }
    catch (e) { toast(e.message, 'error'); }
  };
  $('#vis', box).addEventListener('change', (e) => patch({ visibility: e.target.value }));
  $('#cm', box).addEventListener('change', (e) => patch({ comments_enabled: e.target.checked }));
  try {
    const { stats: s } = await api('GET', `/api/studio/places/${encodeURIComponent(p.id)}/stats`);
    const hours = s.playtime_ms / 3600000;
    const tiles = [['st_visits', s.visits], ['st_players', s.unique_players], ['st_returning', s.returning_players],
      ['st_playtime', hours >= 1 ? hours.toFixed(1) + ' h' : Math.round(hours * 60) + ' min'],
      ['st_session', Math.round(s.avg_session_ms / 60000) + ' min'], ['st_now', s.playing], ['comments', s.comments]];
    const days = [];
    for (let i = 29; i >= 0; i--) {
      const d = new Date(Date.now() - i * 86400000).toISOString().slice(0, 10);
      days.push({ d, v: s.daily.find((x) => x.day === d)?.visits || 0 });
    }
    const max = Math.max(1, ...days.map((x) => x.v));
    $('#pstats', box).innerHTML = `<div class="tiles">${tiles.map(([k, v]) => `<div class="card tile"><span class="muted">${t(k)}</span><b>${esc(v)}</b></div>`).join('')}</div>
      <div class="muted" style="margin:14px 0 6px;font-weight:800">${t('visits_30')}</div>
      <div class="bars">${days.map((x) => `<i style="height:${Math.max(3, (x.v / max) * 100)}%" title="${x.d}: ${x.v}"></i>`).join('')}</div>`;
  } catch { $('#pstats', box).innerHTML = ''; }
}

function commentRow(c) {
  return `<div class="card comment" data-cid="${c.id}">${bust(c.author, 'small')}
    <div class="grow"><div class="row" style="gap:8px;flex-wrap:wrap"><a href="/u/${encodeURIComponent(c.author.username)}" data-link><b>${nameHtml(c.author)}</b></a><span class="muted" style="font-size:13px">${esc(ago(c.created_at))}</span></div>
      <p>${esc(c.body)}</p></div>
    <div class="stack" style="gap:4px;align-items:flex-end">
      ${c.can_delete ? `<button class="link" data-del="${c.id}">${t('delete')}</button>` : ''}
      ${c.author.id !== state.me.id ? `<button class="link danger" data-rep="${c.id}">${t('report')}</button>` : ''}</div></div>`;
}

async function commentsBlock(box, p) {
  const base = `/api/places/${encodeURIComponent(p.id)}/comments`;
  let list = [];
  let r;
  try { r = await api('GET', base); } catch (e) { box.innerHTML = ''; return; }
  list = r.comments;
  const paint = () => {
    box.innerHTML = `<h2>${t('comments')}${list.length ? ` <span class="muted" style="font-size:18px">${list.length}${r.comments.length >= 30 ? '+' : ''}</span>` : ''}</h2>
      ${!r.enabled ? `<div class="empty">${t('comments_off')}</div>`
        : r.can_post ? `<form class="row" id="cf" style="margin-bottom:14px"><input name="text" class="grow" maxlength="500" required placeholder="${t('comment_placeholder')}"><button class="btn">${icon('send', 20)}</button></form>`
        : `<p class="muted">${t('comments_too_young')}</p>`}
      <div class="stack" id="cl">${list.length ? list.map(commentRow).join('') : r.enabled ? `<div class="empty">${t('no_comments')}</div>` : ''}</div>
      ${r.comments.length >= 30 ? `<button class="btn ghost" id="cmore" style="margin-top:12px">${t('load_more')}</button>` : ''}`;
    $('#cf', box)?.addEventListener('submit', async (e) => {
      e.preventDefault();
      const input = e.target.text;
      try {
        const res = await api('POST', base, { text: input.value });
        list.unshift(res.comment);
        paint();
      } catch (err) { toast(err.message, 'error'); }
    });
    $('#cmore', box)?.addEventListener('click', async () => {
      r = await api('GET', base + '?before=' + list[list.length - 1].id);
      list = list.concat(r.comments);
      paint();
    });
    box.querySelectorAll('[data-del]').forEach((b) => b.addEventListener('click', async () => {
      if (!confirm(t('delete_comment_q'))) return;
      try { await api('DELETE', `${base}/${b.dataset.del}`); list = list.filter((c) => String(c.id) !== b.dataset.del); paint(); }
      catch (err) { toast(err.message, 'error'); }
    }));
    box.querySelectorAll('[data-rep]').forEach((b) => b.addEventListener('click', () => {
      const c = list.find((x) => String(x.id) === b.dataset.rep);
      reportDialog(c.author, { comment_id: c.id });
    }));
  };
  paint();
}

// --- studio on the website: your places and images (building happens in the app) ---

async function studioPage(root) {
  if (!state.me) { sessionStorage.setItem('after_login', '/studio'); return go('/login'); }
  root.innerHTML = `<div class="row section-head" style="flex-wrap:wrap"><div class="grow"><h1 style="margin:0">${t('studio')}</h1>
      <p class="muted" style="margin:6px 0 0">${t('studio_web_text')}</p></div>
      <a class="btn ghost" href="/docs/studio" data-link>${t('studio_docs')}</a></div>
    <h2>${t('my_places')}</h2><div class="stack" id="sp"><div class="loader"><i></i></div></div>
    <div class="row section-head" style="margin-top:30px"><h2 class="grow" style="margin:0">${t('my_images')}</h2>
      <label class="btn">${t('upload')}<input type="file" id="up" accept="image/png,image/jpeg" hidden></label></div>
    <div id="au" class="muted" style="margin:8px 0 14px"></div><div class="assets" id="as"></div>`;
  const vis = ['private', 'friends', 'public'];
  const loadPlaces = async () => {
    const { places } = await api('GET', '/api/studio/places');
    $('#sp').innerHTML = places.length ? places.map((p) => `<div class="card row studio-row">
        <a href="/place/${encodeURIComponent(p.id)}" data-link><img src="${esc(p.cover)}" alt=""></a>
        <div class="grow"><a href="/place/${encodeURIComponent(p.id)}" data-link><h3 style="margin:0">${esc(field(p, 'name'))}</h3></a>
          <span class="muted" style="font-size:14px">${esc(t('studio_line', p.visits, p.playing, ago(p.updated_at)))}</span></div>
        <select data-vis="${esc(p.id)}">${vis.map((v) => `<option value="${v}" ${p.visibility === v ? 'selected' : ''}>${t('vis_' + v)}</option>`).join('')}</select>
        <button class="btn small mint" data-play="auto" data-game="${esc(p.id)}">▶</button>
        <button class="link danger" data-delp="${esc(p.id)}">${t('delete')}</button></div>`).join('')
      : `<div class="empty">${t('no_my_places')}</div>`;
    $('#sp').querySelectorAll('[data-vis]').forEach((sel) => sel.addEventListener('change', async () => {
      try { await api('PATCH', `/api/studio/places/${encodeURIComponent(sel.dataset.vis)}`, { visibility: sel.value }); toast(t('saved')); }
      catch (e) { toast(e.message, 'error'); }
    }));
    $('#sp').querySelectorAll('[data-delp]').forEach((b) => b.addEventListener('click', async () => {
      if (!confirm(t('delete_place_q'))) return;
      try { await api('DELETE', `/api/studio/places/${encodeURIComponent(b.dataset.delp)}`); loadPlaces(); }
      catch (e) { toast(e.message, 'error'); }
    }));
  };
  const loadAssets = async () => {
    const { assets, usage } = await api('GET', '/api/assets');
    $('#au').textContent = t('asset_usage', usage.count, usage.max_count, (usage.bytes / 1048576).toFixed(1), Math.round(usage.max_bytes / 1048576));
    $('#as').innerHTML = assets.length ? assets.map((a) => `<div class="card asset">
        <img src="/api/assets/${esc(a.id)}" alt="" loading="lazy"><b title="${esc(a.name)}">${esc(a.name)}</b>
        <div class="row" style="gap:6px"><button class="btn small ghost grow" data-copy="asset://${esc(a.id)}">${t('copy_id')}</button>
          <button class="btn small ghost" data-dela="${esc(a.id)}" aria-label="${t('delete')}">✕</button></div></div>`).join('')
      : `<div class="empty">${t('no_images')}</div>`;
    $('#as').querySelectorAll('[data-copy]').forEach((b) => b.addEventListener('click', async () => {
      try { await navigator.clipboard.writeText(b.dataset.copy); toast(t('copied')); } catch { prompt('', b.dataset.copy); }
    }));
    $('#as').querySelectorAll('[data-dela]').forEach((b) => b.addEventListener('click', async () => {
      if (!confirm(t('delete_image_q'))) return;
      try { await api('DELETE', `/api/assets/${b.dataset.dela}`); loadAssets(); }
      catch (e) { toast(e.message, 'error'); }
    }));
  };
  $('#up').addEventListener('change', async (e) => {
    const file = e.target.files[0];
    e.target.value = '';
    if (!file) return;
    if (file.size > 2 * 1024 * 1024) return toast(t('image_too_big'), 'error');
    const b64 = await new Promise((ok) => {
      const r = new FileReader();
      r.onload = () => ok(String(r.result).split(',')[1]);
      r.readAsDataURL(file);
    });
    try { await api('POST', '/api/assets', { name: file.name.replace(/\.[^.]+$/, ''), image: b64 }); toast(t('uploaded')); loadAssets(); }
    catch (err) { toast(err.message, 'error'); }
  });
  await Promise.all([loadPlaces(), loadAssets()]);
}

// Studio docs: markdown files next to the site, rendered with marked.
const DOC_PAGES = [['index', 'doc_start'], ['scripting', 'doc_scripting'], ['ui', 'doc_ui'], ['strings', 'doc_strings'], ['marp', 'doc_marp'], ['classes', 'doc_classes']];
let markedLib = null;
async function docsPage(root, page) {
  if (!DOC_PAGES.some(([p]) => p === page)) page = 'index';
  const [md, lib] = await Promise.all([
    fetch(`/docs/studio/${page}.md`).then((r) => (r.ok ? r.text() : Promise.reject(new Error(t('not_found'))))),
    markedLib || import('https://cdn.jsdelivr.net/npm/marked@18.0.14/lib/marked.esm.js'),
  ]);
  markedLib = lib;
  root.innerHTML = `<div class="docs"><aside class="card stack">${DOC_PAGES.map(([p, k]) =>
      `<a href="/docs/studio${p === 'index' ? '' : '/' + p}" data-link class="${p === page ? 'on' : ''}">${t(k)}</a>`).join('')}</aside>
    <article class="md">${lib.marked.parse(md)}</article></div>`;
  const art = $('.md', root);
  const slug = (s) => s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
  art.querySelectorAll('h2, h3').forEach((h) => { h.id = slug(h.textContent); });
  art.querySelectorAll('a[href]').forEach((a) => {
    const href = a.getAttribute('href');
    const doc = href.match(/^([a-z]+)\.md(#.*)?$/);
    if (doc) {
      a.setAttribute('href', `/docs/studio${doc[1] === 'index' ? '' : '/' + doc[1]}`);
      a.dataset.link = '';
    } else if (href.startsWith('#')) {
      a.addEventListener('click', (e) => { e.preventDefault(); $(href, art)?.scrollIntoView({ behavior: 'smooth' }); });
    } else if (/^https?:/.test(href)) {
      a.target = '_blank';
      a.rel = 'noopener';
    }
  });
}

// --- direct messages -------------------------------------------------------------

// Friends and chats are one section on the website: a switch on top of both pages.
function socialHeader(active) {
  return `<div class="row social-head"><h1 class="grow" style="margin:0">${t('friends')}</h1>
    <div class="segment">
      <a href="/friends/chats" data-link class="${active === 'chats' ? 'on' : ''}">${icon('messages', 18)}${t('chats')}<b class="count" data-count="messages" hidden></b></a>
      <a href="/friends" data-link class="${active === 'friends' ? 'on' : ''}">${icon('friends', 18)}${t('friends')}<b class="count" data-count="friends" hidden></b></a>
    </div></div>`;
}

async function messagesPage(root) {
  if (!state.me) { sessionStorage.setItem('after_login', '/friends/chats'); return go('/login'); }
  root.innerHTML = `${socialHeader('chats')}<div class="dm">
    <div class="dm-side stack">
      <div class="tabs"><button data-tab="chats" class="on">${t('chats')}</button><button data-tab="requests">${t('dm_requests')}</button></div>
      <div class="stack dm-list" id="convs"><div class="loader"><i></i></div></div></div>
    <div class="card dm-pane" id="pane"><div class="empty dm-empty">${icon('messages', 44)}<br>${t('pick_chat')}</div></div></div>`;
  let tab = 'chats';
  let convs = [];
  let current = null;
  let lastId = 0;

  const drawList = () => {
    root.querySelectorAll('[data-tab]').forEach((b) => b.classList.toggle('on', b.dataset.tab === tab));
    const reqs = convs.filter((c) => c.state === 'incoming');
    root.querySelector('[data-tab="requests"]').textContent = t('dm_requests') + (reqs.length ? ` (${reqs.length})` : '');
    const items = convs.filter((c) => (c.state === 'incoming') === (tab === 'requests'));
    $('#convs').innerHTML = items.length ? items.map((c) => `
      <button class="card row conv ${current && current.id === c.user.id ? 'on' : ''}" data-open="${c.user.id}">${bust(c.user)}
        <span class="grow"><b>${nameHtml(c.user)}</b><span class="muted preview">${c.last.from_me ? t('you') : ''}${esc(c.last.body)}</span></span>
        ${c.unread ? `<b class="count">${c.unread}</b>` : ''}</button>`).join('')
      : `<div class="empty">${t(tab === 'requests' ? 'no_dm_requests' : 'no_chats')}</div>`;
  };
  const loadList = async () => {
    const r = await api('GET', '/api/dm');
    convs = r.conversations;
    if ($('#convs')) drawList();
  };
  const bubble = (m) => `<div class="bubble ${m.from_me ? 'me' : ''}">${esc(m.body)}</div>`;
  const scrollDown = () => { const b = $('#msgs'); if (b) b.scrollTop = b.scrollHeight; };

  const open = async (user) => {
    current = user;
    lastId = 0;
    root.querySelector('.dm').classList.add('chat-open');
    drawList();
    $('#pane').innerHTML = '<div class="loader"><i></i></div>';
    const r = await api('GET', `/api/dm/${user.id}`);
    if (!current || current.id !== user.id) return;
    const u = r.user;
    let composer = '';
    if (!r.can_message) composer = `<div class="note">${t('dm_unavailable')}</div>`;
    else if (r.state === 'incoming') composer = `<div class="note">${esc(t('dm_request_from', u.display_name))}</div>
      <div class="row"><button class="btn ghost grow" id="decline">${t('decline')}</button><button class="btn mint grow" id="accept">${t('accept')}</button></div>`;
    else if (r.state === 'outgoing') composer = `<div class="note">${esc(t('dm_waiting', u.display_name))}</div>`;
    else composer = `${r.state === 'none' ? `<div class="note">${t('dm_first')}</div>` : ''}
      <form class="row" id="send"><input name="text" maxlength="500" placeholder="${t('type_message')}" autocomplete="off" required>
      <button class="btn" aria-label="${t('send')}">${icon('send', 20)}</button></form>`;
    $('#pane').innerHTML = `<div class="row dm-head"><button class="btn small ghost back" id="back">←</button>${bust(u)}
        <a class="grow" href="/u/${encodeURIComponent(u.username)}" data-link><b>${nameHtml(u)}</b><div>${status(u)}</div></a></div>
      <div class="msgs" id="msgs">${r.messages.map(bubble).join('')}</div>${composer}`;
    lastId = r.messages.length ? r.messages[r.messages.length - 1].id : 0;
    scrollDown();
    $('#back').addEventListener('click', () => { current = null; root.querySelector('.dm').classList.remove('chat-open'); drawList(); });
    $('#accept')?.addEventListener('click', async () => { await api('POST', `/api/dm/${u.id}/accept`); tab = 'chats'; await loadList(); open(u); });
    $('#decline')?.addEventListener('click', async () => {
      await api('POST', `/api/dm/${u.id}/decline`);
      current = null;
      $('#pane').innerHTML = `<div class="empty dm-empty">${t('pick_chat')}</div>`;
      root.querySelector('.dm').classList.remove('chat-open');
      loadList();
    });
    $('#send')?.addEventListener('submit', async (e) => {
      e.preventDefault();
      const input = e.target.text;
      const text = input.value.trim();
      if (!text) return;
      input.value = '';
      try {
        const res = await api('POST', `/api/dm/${u.id}`, { text });
        if (res.state !== 'open') open(u);
        else await poll();
        loadList();
      } catch (err) { toast(err.message, 'error'); input.value = text; }
    });
    pollCounts();
  };
  const poll = async () => {
    if (!current) return;
    const id = current.id;
    const r = await api('GET', `/api/dm/${id}?after=${lastId}`);
    if (!current || current.id !== id || !$('#msgs')) return;
    const fresh = r.messages.filter((m) => m.id > lastId);
    if (!fresh.length) return;
    $('#msgs').insertAdjacentHTML('beforeend', fresh.map(bubble).join(''));
    lastId = fresh[fresh.length - 1].id;
    scrollDown();
  };

  root.querySelectorAll('[data-tab]').forEach((b) => b.addEventListener('click', () => { tab = b.dataset.tab; drawList(); }));
  $('#convs').addEventListener('click', (e) => {
    const b = e.target.closest('[data-open]');
    if (!b) return;
    const c = convs.find((x) => x.user.id === Number(b.dataset.open));
    if (c) open(c.user);
  });
  await loadList();
  if (state.dmOpen) { const u = state.dmOpen; state.dmOpen = null; open(u); }
  const iv = setInterval(() => { loadList().catch(() => {}); poll().catch(() => {}); }, 3000);
  onLeave(() => clearInterval(iv));
}

// --- admin panel --------------------------------------------------------------

async function adminPage(root) {
  if (!isStaff()) return go('/');
  const owner = state.me.role === 'owner';
  let tab = sessionStorage.getItem('admin_tab') || 'overview';
  root.innerHTML = `<h1>${t('admin_panel')}</h1>
    <div class="tabs">${['overview', 'reports', 'users', 'servers', 'places_admin'].map((k) => `<button data-tab="${k}">${t(k)}</button>`).join('')}</div>
    <div id="admin" class="stack" style="margin-top:18px"></div>`;
  const box = $('#admin');
  const tabs = root.querySelectorAll('[data-tab]');
  const show = async () => {
    sessionStorage.setItem('admin_tab', tab);
    tabs.forEach((b) => b.classList.toggle('on', b.dataset.tab === tab));
    box.innerHTML = '…';
    try { await ({ overview, reports, users, servers, places_admin: placesAdmin })[tab](); }
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

  async function reports() {
    const r = await api('GET', '/api/admin/reports');
    box.innerHTML = r.reports.length ? r.reports.map((x) => `<div class="card stack">
        <div class="row" style="flex-wrap:wrap">${x.target ? bust(x.target) : ''}
          <div class="grow">${x.target ? `<a href="/u/${encodeURIComponent(x.target.username)}" data-link><b>${nameHtml(x.target)}</b> <span class="muted">@${esc(x.target.username)}</span></a>` : '?'}
            <div class="muted" style="font-size:14px">${esc(t('r_' + x.reason))} · ${esc(t('reported_by', x.reporter ? x.reporter.display_name : '?'))} · ${esc(ago(x.created_at))}</div></div>
          <button class="btn small ghost" data-resolve="${x.id}">${t('resolve')}</button>
          ${x.target && !x.target.banned && x.target.role === 'user' ? `<button class="btn small danger" data-ban="${x.target.id}" data-rid="${x.id}">${t('ban')}</button>` : ''}</div>
        ${x.place ? `<div>${t('report_about_place')} <a href="/place/${encodeURIComponent(x.place.id)}" data-link><b>${esc(x.place.name)}</b></a></div>` : ''}
        ${x.comment ? `<blockquote class="quote">${esc(x.comment.body)}</blockquote><a class="muted" href="/place/${encodeURIComponent(x.comment.place_id)}" data-link>${t('report_open_place')}</a>` : ''}
        ${x.details ? `<p style="margin:0">${esc(x.details)}</p>` : ''}</div>`).join('') : `<div class="empty">${t('no_reports')}</div>`;
    box.querySelectorAll('[data-resolve]').forEach((b) => b.addEventListener('click', async () => {
      await api('POST', `/api/admin/reports/${b.dataset.resolve}/resolve`); reports();
    }));
    box.querySelectorAll('[data-ban]').forEach((b) => b.addEventListener('click', async () => {
      const reason = prompt(t('ban_reason'));
      if (reason === null) return;
      try {
        await api('POST', `/api/admin/users/${b.dataset.ban}`, { banned: true, reason });
        await api('POST', `/api/admin/reports/${b.dataset.rid}/resolve`);
        toast(t('done')); reports();
      } catch (e) { toast(e.message, 'error'); }
    }));
  }

  async function users(q = '') {
    const r = await api('GET', '/api/admin/users?q=' + encodeURIComponent(q));
    box.innerHTML = `<input id="uq" placeholder="${t('search')}" value="${esc(q)}"><div class="stack" id="ul"></div>`;
    $('#ul').innerHTML = r.users.map((u) => {
      const canTouch = u.role !== 'owner' && (owner || u.role === 'user');
      return `<div class="card row admin-user">${bust(u)}
        <div class="grow"><a href="/u/${encodeURIComponent(u.username)}" data-link><b>${nameHtml(u)}</b> <span class="muted">@${esc(u.username)}</span></a>
          ${u.banned ? `<span class="badge banned">${t('banned_tag')}</span>` : ''}
          <div class="muted" style="font-size:14px">${u.age != null ? esc(t('age_n', u.age)) + ' · ' : ''}${u.playing ? esc(t('playing', field(u.playing, 'server_name'))) : esc(t('last_seen', ago(u.last_seen)))}${u.ban_reason ? ' · ' + esc(u.ban_reason) : ''}</div></div>
        ${canTouch ? `<div class="row" style="flex-wrap:wrap;gap:6px;justify-content:flex-end">
          ${u.playing ? `<button class="btn small ghost" data-kick="${u.id}">${t('kick')}</button>` : ''}
          <button class="btn small ghost" data-reset="${u.id}">${t('reset_profile')}</button>
          ${u.age != null ? `<button class="btn small ghost" data-resetbd="${u.id}">${t('admin_reset_bd')}</button>` : ''}
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
    box.querySelectorAll('[data-resetbd]').forEach((b) => b.addEventListener('click', () => act(() => api('POST', `/api/admin/users/${b.dataset.resetbd}`, { reset_birthdate: true }))));
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

function setLang(code) {
  if (!LANG_CODES.has(code)) return;
  state.lang = code;
  localStorage.setItem('lang', code);
  render();
}

function go(path) {
  history.pushState({}, '', path);
  render();
}

async function render() {
  const path = location.pathname;
  cleanups.forEach((fn) => fn());
  cleanups = [];
  document.documentElement.lang = state.lang;
  renderNav(path);
  pollCounts();
  const root = $('#app');
  root.innerHTML = '<div class="loader"><i></i></div>';
  try {
    if (path.startsWith('/messages') || path.startsWith('/friends/chats')) await messagesPage(root);
    else if (path.startsWith('/u/')) await profilePage(root, decodeURIComponent(path.slice(3)));
    else if (path.startsWith('/place/')) await placePage(root, decodeURIComponent(path.slice(7)));
    else if (path === '/admin') await adminPage(root);
    else if (path === '/studio') await studioPage(root);
    else if (path.startsWith('/docs/studio')) await docsPage(root, path.split('/')[3] || 'index');
    else await (pages[path] || pages['/'])(root);
  } catch (e) {
    root.innerHTML = `<div class="empty">${esc(e.message)}</div>`;
  }
  window.scrollTo(0, 0);
}

document.addEventListener('click', (e) => {
  const link = e.target.closest('[data-link]');
  if (link && !e.metaKey && !e.ctrlKey) {
    e.preventDefault();
    return go(link.getAttribute('href'));
  }
  const play = e.target.closest('[data-play]');
  if (play) launch(play.dataset.play, play.dataset.game);
});
window.addEventListener('popstate', render);

(async () => {
  if (state.token) {
    try { state.me = (await api('GET', '/api/me')).user; } catch { state.me = null; }
  }
  await render();
  askBirthdate();
})();
