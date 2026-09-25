import { test } from 'node:test';
import assert from 'node:assert/strict';
import { MoveGuard, PLAYGROUND_LIMITS, KICK_POINTS } from '../src/anticheat.js';

const L = PLAYGROUND_LIMITS;
const STEP = 50; // ms between position updates (20 Hz)

// Moves along `velocity` (m/s) for `ms`, sending updates like the app does.
function run(guard, from, velocity, ms, t0, limits = L) {
  let p = from.slice();
  let t = t0;
  const bad = [];
  for (let k = 0; k < ms / STEP; k++) {
    t += STEP;
    p = [p[0] + (velocity[0] * STEP) / 1000, p[1] + (velocity[1] * STEP) / 1000, p[2] + (velocity[2] * STEP) / 1000];
    const r = guard.check(p, limits, t);
    if (r && !r.silent) bad.push(r.reason);
  }
  return { p, t, bad };
}

test('walking, sprinting and sliding are fine', () => {
  const g = new MoveGuard([0, 0.6, 10], 0);
  let r = run(g, [0, 0.6, 10], [5, 0, 0], 3000, 2000);
  assert.deepEqual(r.bad, []);
  r = run(g, r.p, [0, 0, 7], 3000, r.t);
  assert.deepEqual(r.bad, []);
  // Sprinting down a slide: 7 + 10 m/s.
  r = run(g, r.p, [17, 0, 0], 2000, r.t);
  assert.deepEqual(r.bad, []);
});

test('the mega trampoline is not flying', () => {
  const g = new MoveGuard([0, 0.6, 0], 0);
  // Launched at 26 m/s under 22 m/s² gravity, sampled like the app does.
  let t = 2000;
  let y = 0.6;
  let vy = 26;
  const bad = [];
  for (let k = 0; k < 60; k++) {
    t += STEP;
    vy -= 22 * (STEP / 1000);
    y = Math.max(0.6, y + vy * (STEP / 1000));
    const r = g.check([0, y, 0], L, t);
    if (r) bad.push(r.reason);
  }
  assert.deepEqual(bad, []);
});

test('a speed hack is caught and sent back', () => {
  const g = new MoveGuard([0, 0.6, 0], 0);
  const r = run(g, [0, 0.6, 0], [40, 0, 0], 1500, 2000);
  assert.ok(r.bad.includes('speed'));
  assert.ok(g.good[0] < 30, 'the good position stays behind the cheater');
});

test('teleports are caught, spawn and server teleports are not', () => {
  const g = new MoveGuard([0, 0.6, 0], 0);
  let res = g.check([80, 0.6, 80], L, 3000);
  assert.equal(res.reason, 'teleport');
  assert.deepEqual(res.back, [0, 0.6, 0]);
  // The client obeys the correction.
  assert.equal(g.check([0, 0.6, 0], L, 3100), null);
  // A server-side teleport resets the baseline.
  g.reset([100, 5, 100], 5000);
  assert.equal(g.check([100, 5, 100], L, 5100), null);
  assert.equal(g.check([100.2, 5, 100], L, 7000), null);
  // Dying and respawning near the spawn point is expected.
  g.expect([0, 0.6, 15], 6, 8000);
  assert.equal(g.check([1.5, 0.6, 16], L, 9000), null);
});

test('flying straight up is caught', () => {
  const g = new MoveGuard([0, 0.6, 0], 0);
  const r = run(g, [0, 0.6, 0], [0, 12, 0], 3000, 2000);
  assert.ok(r.bad.includes('rise') || r.bad.includes('ceiling'), r.bad.join(','));
});

test('studio limits follow the place: faster walk speed is allowed', () => {
  const fast = { walk: 30, sprint: 30, jump: 8.2, gravity: 22, check: true };
  const g = new MoveGuard([0, 0.6, 0], 0);
  assert.deepEqual(run(g, [0, 0.6, 0], [28, 0, 0], 2000, 2000, fast).bad, []);
  const off = { ...fast, walk: 5, sprint: 7, check: false };
  const g2 = new MoveGuard([0, 0.6, 0], 0);
  assert.deepEqual(run(g2, [0, 0.6, 0], [90, 0, 0], 2000, 2000, off).bad, []);
});

test('a cheater who keeps going gets kicked, lag spikes do not', () => {
  const g = new MoveGuard([0, 0.6, 0], 0);
  let t = 2000;
  let p = [0, 0.6, 0];
  for (let k = 0; k < 40 && !g.shouldKick; k++) {
    t += 300;
    p = [p[0] + 30, 0.6, 0]; // ignores every correction
    g.check(p, L, t);
  }
  assert.ok(g.shouldKick, `points ${g.points} of ${KICK_POINTS}`);

  // An honest player whose updates stall for 2 s and then catch up in a burst.
  const h = new MoveGuard([0, 0.6, 0], 0);
  let r = run(h, [0, 0.6, 0], [7, 0, 0], 1000, 2000);
  const after = [r.p[0] + 14, 0.6, 0]; // two seconds of sprinting, delivered late
  assert.equal(h.check(after, L, r.t + 2000), null);
});
