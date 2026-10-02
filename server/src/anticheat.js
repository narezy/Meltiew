// Server-side movement checks. Clients own their character's position, so the
// server checks every update against what the place allows (speed, jump height,
// gravity) and snaps cheaters back to their last good position. Repeated
// violations get the player kicked.

// Playground: sprint 7 m/s plus a slide's 10 m/s push and the carousel; the mega
// trampoline launches at 26 m/s (about 15 m up).
export const PLAYGROUND_LIMITS = { walk: 5, sprint: 17, jump: 26, gravity: 22, ceiling: 90, check: true };

const WINDOW_MS = 1000; // horizontal speed is measured over this long
// ...and over this long, tighter: a sped-up game clock (a "speedhack") gains a little
// every second, which a short window hides in its slack.
const LONG_WINDOW_MS = 3000;
const LONG_FACTOR = 1.12;
const LONG_SLACK = 3;
// ...and over 10 seconds, tighter still: a small speed-up that runs for long.
const LONGEST_WINDOW_MS = 10000;
const LONGEST_FACTOR = 1.06;
// The app sends where it is 15 times a second at most; its clock sped up sends more.
// Counted over RATE_WINDOW_MS; twice over the limit in a row (a network hiccup that
// delivers a backlog at once happens only once) is a sped-up clock.
export const SEND_HZ = 15;
const RATE_WINDOW_MS = 5000;
const RATE_FACTOR = 1.3;
const RISE_WINDOW_MS = 3000; // climbing is measured over this long
const SLACK_H = 4; // metres of slack for lag and rounding
const SLACK_RISE = 3;
const TELEPORT_SLACK = 12; // a single jump this far beyond the limit is a teleport
const DECAY_MS = 4000; // one violation point fades every this many ms
// Violations one after another (each within this long of the last) cost more each time:
// running too fast and taking the snap-back every few seconds would otherwise never add
// up to a kick.
const STREAK_MS = 10000;
const STREAK_MAX = 5;
export const KICK_POINTS = 14;
const POINTS = { speed: 1, rise: 2, ceiling: 3, teleport: 3, fly: 2, timer: 4 };
// In the air (Studio places, which tell us what's under each player): lag and the
// footing check (4 times a second) get this much slack; the app never falls faster.
const AIR_SLACK_MS = 600;
// Above where they took off, a jump reaches v²/2g; this much more for steps and lag.
const APEX_SLACK = 1.5;
// Standing on something only the place's scripts know about right now (a lift, a moving
// platform): the take-off height follows it up at most this fast (studs a second).
const LIFT_SPEED = 14;
const MAX_FALL = 50;
const EXPECT_MS = 4000; // how long a server teleport waits for the client to arrive
const EXPECT_RADIUS = 14; // "arrived": this close to where the server put them
const GLIDE_RADIUS = 6; // a Glide: this close to the straight line counts as on the way
const GLIDE_SLACK_MS = 1500; // and this long after it should have arrived

export class MoveGuard {
  constructor(pos, now = Date.now()) {
    this.reset(pos, now);
    this.points = 0;
    this.lastDecay = now;
    this.total = 0;
    this.lastReason = '';
    this.sent = [];
    this.rateStrikes = 0;
    this.rateAt = 0;
  }

  /** Too many updates for a normal clock (see SEND_HZ); true when it's time to act. */
  _fastClock(now) {
    this.sent.push(now);
    while (this.sent.length && now - this.sent[0] > RATE_WINDOW_MS) this.sent.shift();
    if (now - this.rateAt < RATE_WINDOW_MS) return false; // one verdict per window
    if (this.sent.length <= (SEND_HZ * RATE_WINDOW_MS * RATE_FACTOR) / 1000) {
      if (now - this.rateAt > RATE_WINDOW_MS * 2) this.rateStrikes = 0;
      return false;
    }
    this.rateAt = now;
    this.sent = [];
    return ++this.rateStrikes >= 2;
  }

  /** A legit jump in position (spawn, respawn, server teleport): start over from here. */
  reset(pos, now = Date.now()) {
    this.correcting = null;
    this.air = null;
    this.arriving = null;
    this.base = { p: pos.slice(), t: now };
    this.good = pos.slice();
    this.samples = [{ t: now, p: pos.slice() }];
    this.graceUntil = now + 1500; // the client needs a moment to actually move there
  }
  /**
   * The server moved the player (a place's Teleport, an admin's bring). Updates
   * already on their way from the old spot are ignored until the client reports
   * being at the new one; if it never does, it's put there.
   */
  teleportTo(pos, now = Date.now()) {
    this.reset(pos, now);
    this.arriving = { p: pos.slice(), until: now + EXPECT_MS };
  }


  /**
   * The place flies the player from `from` to `to` in `ms` (Player:Glide): anything
   * along that line goes through until a moment after they should have arrived.
   */
  glideTo(from, to, ms, now = Date.now()) {
    this.gliding = { from: from.slice(), to: to.slice(), until: now + ms + GLIDE_SLACK_MS };
    this.graceUntil = now + 1500;
  }

  /** The place pushed the player (a script set their speed): a moment of grace for the trip. */
  pushed(now = Date.now()) {
    this.graceUntil = Math.max(this.graceUntil, now + 1500);
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
    if (limits.check && this._fastClock(now)) return this._violate('timer', now);
    if (this.gliding) {
      if (now > this.gliding.until) this.gliding = null;
      else if (distToSegment(pos, this.gliding.from, this.gliding.to) <= GLIDE_RADIUS) {
        this.reset(pos, now);
        return null;
      }
    }
    if (this.arriving) {
      if (dist3(pos, this.arriving.p) <= EXPECT_RADIUS) {
        this.arriving = null;
        this.reset(pos, now);
        return null;
      }
      if (now < this.arriving.until) return { reason: 'wait', back: this.arriving.p.slice(), silent: true };
      // Never got there: put them where the server sent them (no points, it's not their doing).
      const back = this.arriving.p.slice();
      this.reset(back, now);
      this.correcting = { until: now + 2000 };
      return { reason: 'teleport', back, noPoints: true };
    }
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
    const oldest = this._sampleBefore(now - LONGEST_WINDOW_MS);
    if (oldest && !inGrace && now - oldest.t < LONGEST_WINDOW_MS + 2000) {
      const secs = (now - oldest.t) / 1000;
      if (distH(pos, oldest.p) > maxH * secs * LONGEST_FACTOR + LONG_SLACK) return this._violate('speed', now, oldest.p);
    }
    const older = this._sampleBefore(now - LONG_WINDOW_MS);
    if (older && !inGrace && now - older.t < LONG_WINDOW_MS + 1500) {
      const secs = (now - older.t) / 1000;
      if (distH(pos, older.p) > maxH * secs * LONG_FACTOR + LONG_SLACK) return this._violate('speed', now, older.p);
    }
    // Going up: more than a jump (or trampoline) gives, plus steady climbing (Climbable
    // walls, stairs) at up to `limits.rise` studs a second, within a few seconds.
    if (!inGrace) {
      let low = null;
      for (const s of this.samples) if (now - s.t <= RISE_WINDOW_MS && (!low || s.p[1] < low.p[1])) low = s;
      const climb = (limits.rise || 0) * Math.max((now - (low?.t ?? now)) / 1000, 0);
      if (low && pos[1] - low.p[1] > maxRise * 1.2 + SLACK_RISE + climb) return this._violate('rise', now, low.p);
    }
    const air = this._air(pos, limits, now, inGrace);
    if (air) return air;
    return this._accept(pos, now);
  }

  /**
   * Nothing solid underfoot (the place's own geometry, checked on the server): you're
   * jumping or falling. A jump rises only at its start; after the top you fall, faster
   * and faster. Rising again in mid-air (jumping off nothing) or hanging there is flying.
   * Humanoid.Floating, Glide, Climbable parts and seats (solid parts) are fine.
   */
  _air(pos, limits, now, inGrace) {
    if (limits.grounded === undefined) return null; // the playground: no footing info
    const g = Math.max(limits.gravity, 1);
    const free = limits.floating || limits.climb || inGrace;
    // (the playground: a normal jump except off its trampolines, see game.js)
    const jump = Math.max(limits.airJump ?? limits.jump, this.air?.jump || 0);
    const base = this.base || { p: pos.slice(), t: now };
    // Steps up (Humanoid.StepHeight / StepSpeed): a few of them can come between two updates
    // on a staircase. The usual step fits in the slack; a place's high, quick steps add more.
    const steps = (limits.step ?? 0.65) * (1 + (limits.stepRate ?? 5) * Math.max(0.07, (now - base.t) / 1000)) + 0.5;
    const apex = (jump * jump) / (2 * g) + Math.max(APEX_SLACK, steps);
    if (limits.grounded || free) {
      // Standing higher than a jump from where they took off can reach: they flew up
      // there (even in one quick hop between two updates).
      if (limits.standing && !free && pos[1] > base.p[1] + apex) {
        this.air = null;
        return this._violate('fly', now, base.p);
      }
      // Ground the server checked itself (or floating, climbing): take off from here.
      // Ground only the place's scripts vouch for (it may be moving): follow it up slowly.
      let y = pos[1];
      if (!limits.standing && !free) y = Math.min(y, base.p[1] + (LIFT_SPEED * (now - base.t)) / 1000);
      this.base = { p: [pos[0], y, pos[2]], t: now };
      this.air = null;
      return null;
    }
    // In the air higher than the jump goes: flying, air-jumping, climbing thin air.
    if (pos[1] > base.p[1] + apex) {
      this.air = null;
      return this._violate('fly', now, base.p);
    }
    if (!this.air) {
      this.air = { since: now, top: pos[1], topAt: now, jump: limits.airJump ?? limits.jump };
      return null;
    }
    this.air.jump = Math.max(this.air.jump, limits.airJump ?? limits.jump);
    if (pos[1] > this.air.top + 0.5) {
      // Still going up: fine while the jump lasts, a second jump in the air isn't.
      if (now - this.air.since > (limits.jump / g) * 1000 + AIR_SLACK_MS) {
        this.air = null;
        return this._violate('fly', now);
      }
      this.air.top = pos[1];
      this.air.topAt = now;
      return null;
    }
    const t = (now - this.air.topAt - AIR_SLACK_MS) / 1000;
    if (t > 0.4 && this.air.top - pos[1] < Math.min(0.5 * g * t * t, MAX_FALL * t) * 0.3) {
      this.air = null;
      return this._violate('fly', now);
    }
    return null;
  }

  _accept(pos, now) {
    this.good = pos.slice();
    this.samples.push({ t: now, p: pos.slice() });
    while (this.samples.length > 2 && now - this.samples[0].t > LONGEST_WINDOW_MS + 2500) this.samples.shift();
    if (this.samples.length > 300) this.samples.splice(0, this.samples.length - 300);
    return null;
  }

  // `back`: where the cheating started (start of the measured window), else the last good spot.
  _violate(reason, now, back = null) {
    if (back) this.good = back.slice();
    this.streak = now - (this.lastViolation || -Infinity) < STREAK_MS ? Math.min((this.streak || 1) + 1, STREAK_MAX) : 1;
    this.lastViolation = now;
    this.points += (POINTS[reason] || 1) * this.streak;
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

function distToSegment(p, a, b) {
  const ab = [b[0] - a[0], b[1] - a[1], b[2] - a[2]];
  const len2 = ab[0] * ab[0] + ab[1] * ab[1] + ab[2] * ab[2];
  const t = len2 > 0 ? Math.max(0, Math.min(1, ((p[0] - a[0]) * ab[0] + (p[1] - a[1]) * ab[1] + (p[2] - a[2]) * ab[2]) / len2)) : 0;
  return dist3(p, [a[0] + ab[0] * t, a[1] + ab[1] * t, a[2] + ab[2] * t]);
}

function dist3(a, b) {
  return Math.hypot(a[0] - b[0], a[1] - b[1], a[2] - b[2]);
}
