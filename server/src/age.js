// Age rules for chat and direct messages.
//   under 13: no game chat and no direct messages
//   13-15:    game chat and direct messages are filtered
//   16-17:    game chat is filtered, direct messages are not
//   18+:      no filters
export const FACES = [':D', ':)', ':3', ':P', ';)', ':O', 'xD', 'B)', '^_^', 'owo', 'uwu', '>_<', 'T_T', '-_-', ':|', '<3'];

export function ageOf(birthdate, now = new Date()) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(birthdate || ''));
  if (!m) return null;
  const [y, mo, d] = [Number(m[1]), Number(m[2]), Number(m[3])];
  let age = now.getUTCFullYear() - y;
  if (now.getUTCMonth() + 1 < mo || (now.getUTCMonth() + 1 === mo && now.getUTCDate() < d)) age -= 1;
  return age;
}

export function validBirthdate(s) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(s || ''));
  if (!m) return false;
  const date = new Date(Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3])));
  if (date.getUTCMonth() + 1 !== Number(m[2]) || date.getUTCDate() !== Number(m[3])) return false;
  const age = ageOf(s);
  return age !== null && age >= 3 && age <= 120;
}

export function chatRules(birthdate) {
  const age = ageOf(birthdate);
  if (age === null) return { age: null, chat: false, dm: false, filter_chat: true, filter_dm: true };
  return {
    age,
    chat: age >= 13,
    dm: age >= 13,
    filter_chat: age < 18,
    filter_dm: age < 16,
  };
}
