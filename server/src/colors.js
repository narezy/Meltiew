// Body parts in skin-joint order of melly.glb: Torso, Head, ArmL, ArmR, LegL, LegR.
export const BODY_PARTS = ['torso', 'head', 'arm_l', 'arm_r', 'leg_l', 'leg_r'];
export const COLOR_RE = /^#[0-9a-fA-F]{6}$/;
export const DEFAULT_COLORS = {
  torso: '#baa4e2',
  head: '#f5f1ec',
  arm_l: '#f5f1ec',
  arm_r: '#f5f1ec',
  leg_l: '#302d38',
  leg_r: '#302d38',
};

export function parseColors(raw) {
  let stored = {};
  try {
    stored = JSON.parse(raw || '{}') || {};
  } catch {
    stored = {};
  }
  const out = {};
  for (const part of BODY_PARTS) {
    out[part] = COLOR_RE.test(stored[part]) ? stored[part] : DEFAULT_COLORS[part];
  }
  return out;
}
