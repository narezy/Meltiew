// Server-side movement checks. Clients own their character's position, so the
// server checks every update against what the place allows (speed, jump height,
// gravity) and snaps cheaters back to their last good position. Repeated
// violations get the player kicked.

// Playground: sprint 7 m/s plus a slide's 10 m/s push and the carousel; the mega
// trampoline launches at 26 m/s (about 15 m up).
export const PLAYGROUND_LIMITS = { walk: 5, sprint: 17, jump: 26, gravity: 22, ceiling: 90, check: true };

const WINDOW_MS = 1000; // horizontal speed is measured over this long
const RISE_WINDOW_MS = 3000; // climbing is measured over this long
const SLACK_H = 4; // metres of slack for lag and rounding
const SLACK_RISE = 3;
const TELEPORT_SLACK = 12; // a single jump this far beyond the limit is a teleport
const DECAY_MS = 4000; // one violation point fades every this many ms
export const KICK_POINTS = 14;
const POINTS = { speed: 1, rise: 2, ceiling: 3, teleport: 3 };

export class MoveGuard {
  constructor(pos, now = Date.now()) {
    this.reset(pos, now);
    this.points = 0;
    this.lastDecay = now;
    this.total = 0;
    this.lastReason = '';
  }

  /** A legit jump in position (spawn, respawn, server teleport): start over from here. */
  reset(pos, now = Date.now()) {
    this.correcting = null;
    this.good = pos.slice();
    this.samples = [{ t: now, p: pos.slice() }];
    this.graceUntil = now + 1500; // the client needs a moment to actually move there
  }

  /** Lets the next update land anywhere near `pos` (a respawn the client does itself). */
  expect(pos, radius, now = Date.now()) {
    this.pending = { p: pos.slice(), r: radius, until: now + 8000 };
  }

  /**
   * Checks a new position. Returns null when it's fine, or { reason, back } where
   * `back` is where the player should be put instead.
   */
  check(pos, limits, now = Date.now()) {
    this._decay(now);
    if (!limits.check) return this._accept(pos, now);
    // An announced respawn: accept the jump if it lands near the spawn.
    if (this.pending && now < this.pending.until && dist3(pos, this.pending.p) <= this.pending.r) {
      this.pending = null;
      this.reset(pos, now);
      return null;
    }
    // Snapped back: ignore (without new points) whatever was already on its way
    // until the client reports being where we put it.
    if (this.correcting) {
      if (dist3(pos, this.good) <= 4) {
        this.correcting = null;
        return this._accept(pos, now);
      }
      if (now < this.correcting.until) return { reason: 'wait', back: this.good.slice(), silent: true };
      return this._violate(this.lastReason || 'speed', now);
    }
    const inGrace = now < this.graceUntil;
    const maxH = Math.max(limits.walk, limits.sprint);
    const last = this.samples[this.samples.length - 1];
    const dtLast = Math.max((now - last.t) / 1000, 0.05);
    const jump = distH(pos, last.p);
    const maxRise = (limits.jump * limits.jump) / (2 * Math.max(limits.gravity, 1)) + SLACK_RISE;
    if (!inGrace && jump > maxH * dtLast * 1.5 + TELEPORT_SLACK) return this._violate('teleport', now);
    if (!inGrace && pos[1] - last.p[1] > maxRise + limits.jump * dtLast + TELEPORT_SLACK) return this._violate('teleport', now);
    if (limits.ceiling && pos[1] > limits.ceiling) return this._violate('ceiling', now);
    // Speed over the last second: fast enough to cross the gap only by cheating.
    const old = this._sampleBefore(now - WINDOW_MS);
    if (old && !inGrace) {
      const secs = Math.max((now - old.t) / 1000, 0.2);
      if (distH(pos, old.p) > maxH * secs * 1.25 + SLACK_H) return this._violate('speed', now, old.p);
    }
    // Going up: more than a jump (or trampoline) gives, plus steady climbing (Climbable
    // walls, stairs) at up to `limits.rise` studs a second, within a few seconds.
    if (!inGrace) {
      let low = null;
      for (const s of this.samples) if (now - s.t <= RISE_WINDOW_MS && (!low || s.p[1] < low.p[1])) low = s;
      const climb = (limits.rise || 0) * Math.max((now - (low?.t ?? now)) / 1000, 0);
      if (low && pos[1] - low.p[1] > maxRise * 1.2 + SLACK_RISE + climb) return this._violate('rise', now, low.p);
    }
    return this._accept(pos, now);
  }

  _accept(pos, now) {
    this.good = pos.slice();
    this.samples.push({ t: now, p: pos.slice() });
    while (this.samples.length > 2 && now - this.samples[0].t > RISE_WINDOW_MS + 500) this.samples.shift();
    if (this.samples.length > 120) this.samples.splice(0, this.samples.length - 120);
    return null;
  }

  // `back`: where the cheating started (start of the measured window), else the last good spot.
  _violate(reason, now, back = null) {
    if (back) this.good = back.slice();
    this.points += POINTS[reason] || 1;
    this.total += 1;
    this.lastReason = reason;
    // The rejected position isn't recorded; the player goes back to the last good one.
    this.samples = [{ t: now, p: this.good.slice() }];
    this.correcting = { until: now + 2000 };
    return { reason, back: this.good.slice() };
  }

  _decay(now) {
    while (now - this.lastDecay >= DECAY_MS) {
      this.lastDecay += DECAY_MS;
      if (this.points > 0) this.points -= 1;
    }
  }

  _sampleBefore(t) {
    let found = null;
    for (const s of this.samples) {
      if (s.t <= t) found = s;
      else break;
    }
    return found;
  }

  get shouldKick() {
    return this.points >= KICK_POINTS;
  }
}

function distH(a, b) {
  return Math.hypot(a[0] - b[0], a[2] - b[2]);
}

function dist3(a, b) {
  return Math.hypot(a[0] - b[0], a[1] - b[1], a[2] - b[2]);
}
