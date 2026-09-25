// Profanity filter for chat and direct messages, English and Russian.
// Works per word: the word is normalized (case, leetspeak, look-alike letters,
// repeated letters) and masked with '#' if it contains a banned root.

const LEET = { 0: 'o', 1: 'i', 3: 'e', 4: 'a', 5: 's', 7: 't', 8: 'b', '@': 'a', $: 's', '!': 'i', '|': 'i' };

// Latin look-alikes typed instead of Cyrillic ("xуй", "пизда" spelled with a Latin 'a', ...).
const LATIN_TO_CYR = { a: 'а', b: 'в', c: 'с', e: 'е', h: 'н', k: 'к', m: 'м', o: 'о', p: 'р', t: 'т', x: 'х', y: 'у' };

// Roots matched anywhere inside a normalized word (no everyday word contains them).
const RU_ANYWHERE = ['хуй', 'хуе', 'хуя', 'хуи', 'хуло', 'пизд', 'пезд', 'залуп', 'шлюх', 'гандон', 'дроч', 'пидор', 'пидар', 'долбоеб', 'еблан', 'уебок', 'уебан'];
// Roots that must start the word, optionally after a verb prefix ("за-еб-ал", "про-еб-ал").
// Kept apart so "корабля", "требую" or "команда" never trip the filter.
const RU_PREFIXES = ['', 'за', 'вы', 'у', 'на', 'до', 'от', 'отъ', 'по', 'пере', 'раз', 'рас', 'съ', 'об', 'объ', 'при', 'про', 'из', 'въ', 'недо'];
const RU_START = ['еба', 'ебу', 'ебл', 'ебн', 'еби', 'ебе', 'ебо', 'ебш', 'бля', 'сука', 'суки', 'сучк', 'сучар', 'мудак', 'мудил', 'мраз', 'гнид'];
// Whole words only.
const RU_WORDS = ['хер', 'нахер', 'похер', 'нахуй', 'похуй', 'манда', 'манды', 'манде', 'шалава', 'чмо', 'тварь', 'педик', 'педики'];

const EN_ROOTS = ['fuck', 'fuk', 'fck', 'shit', 'bitch', 'cunt', 'pussy', 'asshole', 'bastard', 'slut', 'whore', 'nigg', 'faggot', 'retard', 'motherf', 'dickhead', 'wank', 'twat', 'bollock'];
const EN_WORDS = ['dick', 'dicks', 'cock', 'cocks', 'fag', 'fags', 'ass', 'prick', 'tits', 'piss'];

function collapseRepeats(s) {
  return s.replace(/(.)\1+/g, '$1');
}

function normalizeLatin(word, collapse = true) {
  let out = '';
  for (const ch of word.toLowerCase()) out += LEET[ch] ?? ch;
  out = out.replace(/[^a-z]/g, '');
  return collapse ? collapseRepeats(out) : out;
}

function normalizeCyrillic(word) {
  let out = '';
  for (const ch of word.toLowerCase()) {
    const c = LEET[ch] ?? ch;
    out += LATIN_TO_CYR[c] ?? c;
  }
  return collapseRepeats(out.replace(/ё/g, 'е').replace(/[^а-я]/g, ''));
}

function isBad(word) {
  const lat = normalizeLatin(word);
  if (lat.length >= 2) {
    // Whole words are compared as typed, so "ass" doesn't collapse into "as".
    if (EN_WORDS.includes(normalizeLatin(word, false))) return true;
    if (EN_ROOTS.some((r) => lat.includes(collapseRepeats(r)))) return true;
  }
  const cyr = normalizeCyrillic(word);
  if (cyr.length >= 2) {
    if (RU_WORDS.some((w) => cyr === collapseRepeats(w))) return true;
    if (RU_ANYWHERE.some((r) => cyr.includes(collapseRepeats(r)))) return true;
    for (const pre of RU_PREFIXES) {
      if (!cyr.startsWith(pre)) continue;
      const rest = cyr.slice(pre.length);
      if (RU_START.some((r) => rest.startsWith(collapseRepeats(r)))) return true;
    }
  }
  return false;
}

/** Returns the text with every offending word replaced by '#' characters. */
export function filterText(text) {
  return String(text).replace(/[^\s.,!?;:()"'«»\-–—]+/g, (word) => (isBad(word) ? '#'.repeat(word.length) : word));
}

export function hasProfanity(text) {
  return filterText(text) !== String(text);
}
