// Accessory catalog: shapes the app and the website build the 3D model from.
// Adding an accessory is an edit to accessories.json (see tools/make_accessories.py);
// apps pick it up from GET /api/accessories without an update.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
export const CATALOG = JSON.parse(fs.readFileSync(path.join(here, 'accessories.json'), 'utf8'));
const BY_ID = new Map(CATALOG.items.map((it) => [it.id, it]));

export function accessoryExists(id) {
  return BY_ID.has(id);
}

/** Cleans a worn list: known items only, one per slot (the last one wins), at most max_worn. */
export function cleanWorn(ids) {
  if (!Array.isArray(ids)) return null;
  const bySlot = new Map();
  for (const raw of ids.slice(0, 20)) {
    const it = BY_ID.get(String(raw));
    if (!it) return null;
    bySlot.delete(it.slot);
    bySlot.set(it.slot, it.id);
  }
  return [...bySlot.values()].slice(-CATALOG.max_worn);
}

/** What someone wears, from the database row (older rows only have `hat`). */
export function wornOf(u) {
  try {
    const list = JSON.parse(u.accessories || 'null');
    if (Array.isArray(list)) return list.filter((id) => BY_ID.has(id));
  } catch {}
  return u.hat && u.hat !== 'none' && BY_ID.has(u.hat) ? [u.hat] : [];
}

/** The single "hat" older apps understand: the first worn head item they know. */
export const LEGACY_HATS = ['cap', 'crown', 'catears', 'halo', 'tophat', 'flower', 'headphones'];
export function legacyHat(worn) {
  return worn.find((id) => LEGACY_HATS.includes(id)) || 'none';
}
