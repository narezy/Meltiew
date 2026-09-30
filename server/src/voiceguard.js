// Voice packets are 12 kHz IMA ADPCM (see the app's voice.gd). The server doesn't play
// them, but it listens to how loud they are: a "soundpad" pushing files through voice at
// double volume is clipping noise, not someone talking, and it isn't passed on.

const STEPS = [7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130, 143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658, 724, 796, 876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899, 15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767];
const INDEX = [-1, -1, -1, -1, 2, 4, 6, 8, -1, -1, -1, -1, 2, 4, 6, 8];

/** How loud a packet is: { rms, clipped } (0..1, share of samples at the limit). */
export function loudness(b64) {
  const data = Buffer.from(b64, 'base64');
  if (data.length < 4) return { rms: 0, clipped: 0 };
  let pred = data.readInt16LE(0);
  let idx = Math.min(Math.max(data[2], 0), 88);
  const n = (data.length - 3) * 2;
  let sum = 0;
  let clipped = 0;
  for (let i = 0; i < n; i++) {
    const b = data[3 + (i >> 1)];
    const code = i % 2 === 0 ? b & 15 : b >> 4;
    const step = STEPS[idx];
    let delta = step >> 3;
    if (code & 4) delta += step;
    if (code & 2) delta += step >> 1;
    if (code & 1) delta += step >> 2;
    pred = Math.min(Math.max(code & 8 ? pred - delta : pred + delta, -32768), 32767);
    idx = Math.min(Math.max(idx + INDEX[code], 0), 88);
    const s = pred / 32768;
    sum += s * s;
    if (Math.abs(s) > 0.97) clipped += 1;
  }
  return { rms: Math.sqrt(sum / n), clipped: clipped / n };
}

// Shouting into a phone stays under these; music at twice the volume doesn't.
export const MAX_RMS = 0.42;
export const MAX_CLIPPED = 0.08;

export function tooLoud(b64) {
  const { rms, clipped } = loudness(b64);
  return rms > MAX_RMS || clipped > MAX_CLIPPED;
}
