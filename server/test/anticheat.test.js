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

test('a server teleport ignores stale updates from the old spot, then checks from the new one', () => {
  const limits = { walk: 0, sprint: 0, jump: 0, gravity: 22, check: true };
  const g = new MoveGuard([0, 2, 0], 0);
  g.teleportTo([0, 3.5, 520], 1000);
  // An update sent before the client heard about the teleport.
  assert.equal(g.check([0.5, 2, 0.2], limits, 1050)?.silent, true);
  // The client arrives (frozen: walk speed 0), falls onto the ground, stands still.
  assert.equal(g.check([0, 3.4, 520], limits, 1150), null);
  assert.equal(g.check([0, 0.1, 520], limits, 1600), null);
  assert.equal(g.check([0, 0.1, 520], limits, 3200), null);
  assert.equal(g.points, 0);
});

test('a server teleport the client never follows puts them there without points', () => {
  const limits = { walk: 5, sprint: 7, jump: 8, gravity: 22, check: true };
  const g = new MoveGuard([0, 2, 0], 0);
  g.teleportTo([0, 3.5, 520], 1000);
  const r = g.check([1, 2, 0], limits, 5200);
  assert.deepEqual(r.back, [0, 3.5, 520]);
  assert.equal(g.points, 0);
});

test('a Glide from the place goes through, a flight of your own does not', () => {
  const g = new MoveGuard([0, 0.6, 0], 0);
  let r = run(g, [0, 0.6, 0], [0, 0, 5], 2000, 0);
  // Up 14 studs in a second, then 40 studs across in one more: far beyond walking and jumping.
  g.glideTo(r.p, [r.p[0], 14.6, r.p[2]], 1000, r.t);
  r = run(g, r.p, [0, 14, 0], 1000, r.t);
  assert.deepEqual(r.bad, []);
  // Hanging there (Humanoid.Floating) is fine too.
  r = run(g, r.p, [0, 0, 0], 2000, r.t);
  assert.deepEqual(r.bad, []);
  g.glideTo(r.p, [r.p[0] + 40, 3, r.p[2]], 1000, r.t);
  r = run(g, r.p, [40, -11.6, 0], 1000, r.t);
  assert.deepEqual(r.bad, []);
  // Long after the trip, flying up again on your own is caught.
  r = run(g, r.p, [0, 0, 0], 3000, r.t);
  r = run(g, r.p, [0, 14, 0], 2000, r.t);
  assert.ok(r.bad.length > 0);
});

// A Studio place: the server knows what's under the player (grounded / floating / climb).
const S = { walk: 5, sprint: 7, jump: 8.2, gravity: 22, rise: 7, check: true };

// Jumps or falls with real gravity from `from` (vy up), sending updates at 20 Hz.
function arc(guard, from, vy, ms, t0, ground = 0, extra = {}) {
  let p = from.slice();
  let v = vy;
  let t = t0;
  const bad = [];
  for (let k = 0; k < ms / STEP; k++) {
    t += STEP;
    v = Math.max(v - (S.gravity * STEP) / 1000, -50);
    p = [p[0] + 0.2, Math.max(ground, p[1] + (v * STEP) / 1000), p[2]];
    const grounded = p[1] <= ground + 0.01;
    const r = guard.check(p, { ...S, grounded, floating: false, climb: false, ...extra }, t);
    if (r && !r.silent) bad.push(r.reason);
  }
  return { p, t, bad };
}

test('in the air: a real jump and a long fall pass, jumping off nothing and hanging are flying', () => {
  const g = new MoveGuard([0, 0, 0], 0);
  let r = arc(g, [0, 0, 0], 8.2, 3000, 2000);
  assert.deepEqual(r.bad, []);
  // Off a 60-stud cliff (put up there by the place first).
  g.reset([r.p[0], 60, 0], r.t);
  r = arc(g, [r.p[0], 60, 0], 0, 4000, r.t);
  assert.deepEqual(r.bad, []);
  // A second jump at the top of the first, with nothing underfoot.
  const f = new MoveGuard([0, 0, 0], 0);
  r = arc(f, [0, 0, 0], 8.2, 380, 2000);
  const flights = [];
  for (let k = 0; k < 4; k++) {
    r = arc(f, r.p, 8.2, 380, r.t);
    flights.push(...r.bad);
  }
  assert.ok(flights.includes('fly'), JSON.stringify(flights));
  // Hanging 5 studs up.
  const h = new MoveGuard([0, 0, 0], 0);
  r = arc(h, [0, 0, 0], 8.2, 400, 2000);
  let t = r.t;
  const bad = [];
  for (let k = 0; k < 60; k++) {
    t += STEP;
    const x = h.check([0, 1.5, 0], { ...S, grounded: false }, t);
    if (x && !x.silent) bad.push(x.reason);
  }
  assert.ok(bad.includes('fly'));
  // The same hanging with Humanoid.Floating (the place's doing) is fine.
  const fl = new MoveGuard([0, 1.5, 0], 0);
  const ok = [];
  for (let k = 0; k < 60; k++) {
    const x = fl.check([0, 1.5, 0], { ...S, grounded: false, floating: true }, 2000 + k * STEP);
    if (x && !x.silent) ok.push(x.reason);
  }
  assert.deepEqual(ok, []);
});

// The fly cheats people actually use, against a real map: the server works out what's
// under the feet itself (Occluders.standing), like game.js does.
import { Occluders } from '../src/occlusion.js';

describe_fly();

function describe_fly() {
  const I = [1, 0, 0, 0, 1, 0, 0, 0, 1];
  const solids = new Occluders([
    [0, -1, 0, 200, 1, 200, ...I, 2], // floor, top at y = 0
    [20, 5, 0, 1, 5, 10, ...I, 2], // a wall at x = 19..21, 10 high
    [0, 1, 20, 3, 1, 3, ...I, 2], // a 2-high box (a jump gets you on it)
    [-20, 6, 0, 3, 6, 3, ...I, 2], // a 12-high tower
  ], 2);
  const run = (guard, path, t0 = 1000, extra = {}) => {
    const bad = [];
    let t = t0;
    for (const p of path) {
      t += STEP;
      const standing = solids.standing(p);
      const r = guard.check(p, { ...S, grounded: standing, standing, floating: false, climb: false, ...extra }, t);
      if (r && !r.silent) bad.push(r.reason);
    }
    return { bad, t };
  };
  // Physics like the app: jump at `vy` whenever asked, fall with gravity, land on the floor.
  const sim = (from, steps, { jumpAt = [], ground = 0, dx = 0.3, vy0 = 0 } = {}) => {
    const out = [];
    let [x, y, z] = from;
    let v = vy0;
    for (let k = 0; k < steps; k++) {
      if (jumpAt.includes(k)) v = S.jump;
      v -= (S.gravity * STEP) / 1000;
      x += dx;
      y += (v * STEP) / 1000;
      if (y <= ground) {
        y = ground;
        v = 0;
      }
      out.push([x, y, z]);
    }
    return out;
  };

  test('fly: ordinary jumps, and hopping onto a box a jump reaches, are fine', () => {
    const g = new MoveGuard([-5, 0, 20], 0);
    const r1 = run(g, sim([-5, 0, 20], 60, { jumpAt: [5, 30], dx: 0.25 }), 2000);
    assert.deepEqual(r1.bad, []);
    // Onto the 2-high box: jump from its edge, land on top (the apex is ~1.5 + slack).
    const g2 = new MoveGuard([-3.5, 0, 20], 0);
    const path = [];
    for (let k = 0; k < 6; k++) path.push([-3.5, [0.35, 0.65, 0.9, 1.2, 1.6, 2][k], 20]);
    for (let k = 0; k < 10; k++) path.push([-2.5 + k * 0.2, 2, 20]);
    assert.deepEqual(run(g2, path, 2000).bad, []);
  });

  test('fly: a place\'s high, quick steps (Humanoid.StepHeight / StepSpeed) are walked up', () => {
    // Steps 4 high and 1.5 deep: walked up one per update, without jumping.
    const stairs = new Occluders([[0, -1, 0, 200, 1, 200, ...I, 2],
      ...[0, 1, 2, 3, 4].map((k) => [40 + k * 1.5, (k + 1) * 2, 40, 0.75, (k + 1) * 2, 3, ...I, 2])], 2);
    const climb = (extra) => {
      const g = new MoveGuard([38, 0, 40], 0);
      const bad = [];
      let t = 2000;
      for (let k = 0; k < 5; k++) {
        t += STEP;
        const p = [40 + k * 1.5, (k + 1) * 4, 40];
        const standing = stairs.standing(p);
        const r = g.check(p, { ...S, grounded: standing, standing, floating: false, climb: false, ...extra }, t);
        if (r && !r.silent) bad.push(r.reason);
      }
      return bad;
    };
    assert.ok(climb({}).includes('fly'), 'with the usual steps, rising 4 studs at once is flying');
    assert.deepEqual(climb({ step: 4, stepRate: 10 }), []);
  });

  test('fly: air jumps (jumping again in mid-air to go up) are caught', () => {
    const g = new MoveGuard([0, 0, 0], 0);
    // Jump, and jump again every time the arc starts to fall.
    const path = [];
    let y = 0;
    let v = S.jump;
    for (let k = 0; k < 80; k++) {
      v -= (S.gravity * STEP) / 1000;
      if (v < 0) v = S.jump;
      y += (v * STEP) / 1000;
      path.push([k * 0.1, y, 0]);
    }
    const { bad } = run(g, path, 2000);
    assert.ok(bad.includes('fly'), JSON.stringify(bad));
    // Caught before getting 4 studs up.
    const firstAt = path.findIndex((p, i) => i >= 0 && p[1] > 3.2);
    assert.ok(firstAt > 0);
  });

  test('fly: slowly floating up (even hugging a wall) is caught before the top', () => {
    const g = new MoveGuard([18.5, 0, 0], 0);
    const path = [];
    for (let k = 0; k < 60; k++) path.push([18.5, k * 0.2, 0]); // 4 studs a second, by the wall
    const { bad } = run(g, path, 2000);
    assert.ok(bad.includes('fly'), JSON.stringify(bad));
  });

  test('fly: getting onto the tall tower without a ladder is caught', () => {
    const g = new MoveGuard([-15, 0, 0], 0);
    const path = [];
    // Up fast in half a second (not a teleport), then onto the roof.
    for (let k = 0; k < 10; k++) path.push([-15, (k + 1) * 1.25, 0]);
    for (let k = 0; k < 10; k++) path.push([-15 - k * 0.3, 12.5, 0]);
    const { bad } = run(g, path, 2000);
    assert.ok(bad.includes('fly'), JSON.stringify(bad));
    // And sent back down to where they took off.
    assert.ok(g.good[1] < 1, JSON.stringify(g.good));
  });

  test('fly: stairs are walked up, falls off the tower are fine', () => {
    const steps = new Occluders([[0, -1, 0, 200, 1, 200, ...I, 2], ...[...Array(10)].map((_, i) => [5 + i, 0.25 + i * 0.25, 0, 0.5, 0.25 + i * 0.25, 2, ...I, 2])], 2);
    const g = new MoveGuard([3, 0, 0], 0);
    let t = 2000;
    const bad = [];
    for (let k = 0; k <= 40; k++) {
      t += STEP;
      const x = 3 + k * 0.3;
      const i = Math.floor(x - 4.5);
      const y = i >= 0 ? Math.min(i, 9) * 0.5 + 0.5 : 0;
      const standing = steps.standing([x, y, 0]);
      const r = g.check([x, y, 0], { ...S, grounded: standing, standing, floating: false, climb: false }, t);
      if (r && !r.silent) bad.push(r.reason);
    }
    assert.deepEqual(bad, []);
    const g2 = new MoveGuard([-20, 12, 0], 0);
    assert.deepEqual(run(g2, sim([-20, 12, 0], 50, { dx: 0.3, ground: 0 }), 2000).bad, []);
  });

  test('fly: a lift the scripts move (only the runtime knows it is ground) is fine', () => {
    const g = new MoveGuard([50, 0, 50], 0);
    let t = 2000;
    const bad = [];
    for (let k = 0; k < 60; k++) {
      t += STEP;
      const p = [50, k * 0.4, 50]; // 8 studs a second up, on a platform the solids don't have yet
      const r = g.check(p, { ...S, grounded: true, standing: false, floating: false, climb: false }, t);
      if (r && !r.silent) bad.push(r.reason);
    }
    assert.deepEqual(bad, []);
  });
}

// A sped-up game clock (Cheat Engine's speedhack): the app moves faster and sends more.
test('speedhack: 1.3x running is caught, normal running for a long time is not', () => {
  const run = (speed, hz, secs) => {
    const g = new MoveGuard([0, 0, 0], 0);
    const bad = [];
    const dt = 1000 / hz;
    for (let t = 2000, x = 0; t < 2000 + secs * 1000; t += dt) {
      x += (S.sprint * speed * dt) / 1000;
      const r = g.check([x, 0, 0], { ...S, grounded: true, standing: true }, t);
      if (r && !r.silent) bad.push(r.reason);
      if (r) x = g.good[0];
    }
    return bad;
  };
  assert.deepEqual(run(1, 15, 30), []);
  assert.ok(run(1.3, 15, 10).includes('speed'));
  // The clock sped up: updates come 1.5x as often even if each one moves normally.
  assert.ok(run(1, 22.5, 15).includes('timer'));
});

test('speedhack: one network hiccup delivering a backlog is not a sped-up clock', () => {
  const g = new MoveGuard([0, 0, 0], 0);
  const bad = [];
  let t = 2000;
  let x = 0;
  const send = () => {
    x += S.walk / 15;
    const r = g.check([x, 0, 0], { ...S, grounded: true, standing: true }, t);
    if (r && !r.silent) bad.push(r.reason);
  };
  for (let k = 0; k < 150; k++) {
    t += 1000 / 15;
    send();
  }
  // 2 seconds stuck, then all of them at once.
  t += 2000;
  for (let k = 0; k < 30; k++) send();
  for (let k = 0; k < 150; k++) {
    t += 1000 / 15;
    send();
  }
  assert.ok(!bad.includes('timer'), JSON.stringify(bad));
});

test('spider: climbing a wall of stacked bricks is caught, standing on its top is fine', () => {
  const I = [1, 0, 0, 0, 1, 0, 0, 0, 1];
  // floor, and a wall at x = 10..11 made of 1-high bricks up to y = 10
  const boxes = [[0, -1, 0, 100, 1, 100, ...I, 2]];
  for (let k = 0; k < 10; k++) boxes.push([10.5, k + 0.5, 0, 0.5, 0.5, 3, ...I, 2]);
  const solids = new Occluders(boxes, 2);
  // Beside the wall (capsule touching it), 0.3 above a brick seam: not a floor.
  assert.equal(solids.standing([9.6, 4.3, 0]), false);
  assert.equal(solids.standing([10.5, 10.02, 0]), true);
  const g = new MoveGuard([9.5, 0, 0], 0);
  const bad = [];
  let t = 2000;
  for (let k = 0; k < 60; k++) {
    t += STEP;
    const p = [9.6, k * 0.2, 0];
    const standing = solids.standing(p);
    const r = g.check(p, { ...S, grounded: standing, standing, floating: false, climb: false }, t);
    if (r && !r.silent) bad.push(r.reason);
  }
  assert.ok(bad.includes('fly'), JSON.stringify(bad));
});

test('fly: popping up onto a high ledge between two updates is caught', () => {
  const I = [1, 0, 0, 0, 1, 0, 0, 0, 1];
  const solids = new Occluders([[0, -1, 0, 100, 1, 100, ...I, 2], [5, 3, 0, 2, 3, 2, ...I, 2]], 2);
  const g = new MoveGuard([2, 0, 0], 0);
  const bad = [];
  let t = 2000;
  for (const p of [[2, 0, 0], [2.3, 0, 0], [4.5, 6.02, 0], [4.8, 6.02, 0]]) {
    t += STEP;
    const standing = solids.standing(p);
    const r = g.check(p, { ...S, grounded: standing, standing, floating: false, climb: false }, t);
    if (r && !r.silent) bad.push(r.reason);
  }
  assert.ok(bad.includes('fly'), JSON.stringify(bad));
});

test('speedhack: a small 1.15x speed-up held for long is caught', () => {
  const g = new MoveGuard([0, 0, 0], 0);
  const bad = [];
  let x = 0;
  for (let t = 2000; t < 20000; t += 1000 / 15) {
    x += (S.sprint * 1.15) / 15;
    const r = g.check([x, 0, 0], { ...S, grounded: true, standing: true }, t);
    if (r && !r.silent) bad.push(r.reason);
    if (r) x = g.good[0];
  }
  assert.ok(bad.includes('speed'), JSON.stringify(bad));
});

test('running too fast and taking the snap-back every few seconds adds up to a kick', () => {
  const g = new MoveGuard([0, 0, 0], 0);
  let x = 0;
  let t = 2000;
  for (let k = 0; k < 600 && !g.shouldKick; k++) {
    t += 1000 / 15;
    x += (S.sprint * 1.8) / 15;
    const r = g.check([x, 0, 0], { ...S, grounded: true, standing: true }, t);
    if (r && !r.silent) x = g.good[0];
  }
  assert.ok(g.shouldKick, 'never kicked');
  assert.ok(t - 2000 < 30000, `took ${t - 2000} ms`);
});

test('two lag spikes in a row are not a kick', () => {
  const g = new MoveGuard([0, 0, 0], 0);
  let t = 2000;
  let x = 0;
  for (let k = 0; k < 450; k++) {
    t += 1000 / 15;
    x += S.walk / 15;
    // twice, a burst of 15 studs at once (a lagged backlog)
    if (k === 100 || k === 160) x += 15;
    const r = g.check([x, 0, 0], { ...S, grounded: true, standing: true }, t);
    if (r && !r.silent) x = g.good[0];
  }
  assert.ok(!g.shouldKick, `points ${g.points}`);
});
