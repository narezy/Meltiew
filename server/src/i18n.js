// Server-side strings in English (default) and Russian.
export const MESSAGES = {
  too_large: ['Request is too large', 'Слишком большой запрос'],
  bad_json: ['Malformed JSON', 'Некорректный JSON'],
  unauthorized: ['Please sign in', 'Нужно войти в аккаунт'],
  no_user: ['Player not found', 'Игрок не найден'],
  slow_down: ['Too many attempts, wait a minute', 'Слишком много попыток, подожди минутку'],
  bad_username: ['Username: 3–20 characters, latin letters, digits and _', 'Логин: 3–20 символов, латиница, цифры и _'],
  bad_password: ['Password must be at least 6 characters', 'Пароль должен быть от 6 символов'],
  wrong_password: ['Current password is wrong', 'Старый пароль не подходит'],
  bad_name: ['Name is too short', 'Имя слишком короткое'],
  taken: ['This username is taken', 'Этот логин уже занят'],
  bad_credentials: ['Wrong username or password', 'Неверный логин или пароль'],
  bad_color: ['Invalid color', 'Некорректный цвет'],
  bad_part: ['Unknown body part', 'Нет такой части тела'],
  bad_hat: ['Unknown hat', 'Такой шапки нет'],
  self: ["You're already your own best friend", 'Дружить с собой можно, но не тут :)'],
  no_request: ['Request not found', 'Заявка не найдена'],
  blocked: ["You can't interact with this player", 'С этим игроком нельзя взаимодействовать'],
  bad_image: ['Invalid image', 'Некорректная картинка'],
  bad_server: ['Unknown server', 'Нет такого сервера'],
  banned: ['This account is banned', 'Этот аккаунт заблокирован'],
  banned_reason: ['This account is banned: {r}', 'Этот аккаунт заблокирован: {r}'],
  forbidden: ["You don't have access to this", 'Нет доступа'],
  kicked: ['You were removed from the server by an admin', 'Админ выгнал тебя с сервера'],
  no_place: ['Place not found', 'Плейс не найден'],
  internal: ['Something broke on the server', 'Что-то сломалось на сервере'],
  not_found: ['No such endpoint', 'Нет такого метода'],
  // Game socket
  server_gone: ['That server has closed', 'Сервер уже закрылся'],
  server_full: ['Server is full ({n}/{n})', 'Сервер заполнен ({n}/{n})'],
  duplicate: ['You joined from another device', 'Ты зашёл(ла) в игру с другого устройства'],
};

export function pickLang(req) {
  const explicit = String(req.headers['x-lang'] || '').toLowerCase();
  if (explicit === 'ru' || explicit === 'en') return explicit;
  const accept = String(req.headers['accept-language'] || '').toLowerCase();
  return accept.startsWith('ru') ? 'ru' : 'en';
}

export function msg(code, lang = 'en', vars = {}) {
  const entry = MESSAGES[code] || MESSAGES.internal;
  let text = entry[lang === 'ru' ? 1 : 0];
  for (const [k, v] of Object.entries(vars)) text = text.replaceAll(`{${k}}`, String(v));
  return text;
}
