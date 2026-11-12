// Drives the real pipeline (engine/pipeline.js) with simulated head motion.
//
// The motion model follows the fixture generator's ideas at a smaller scale: a scripted or
// user-set head pose, a little natural sway, sensor noise, and an earbud mounting offset, so
// calibration and smoothing have real work to do. Time can run faster than real time; the
// pipeline only ever sees timestamps, exactly as in the app.
import { PostureMonitor, defaultConfiguration, normalized, vec } from '../engine/pipeline.js';

const RAD = Math.PI / 180;
export const SAMPLE_RATE_HZ = 25;
const STEP = 1 / SAMPLE_RATE_HZ;
export const HISTORY_SECONDS = 60;
const MAX_STEPS_PER_FRAME = 60;

export const PRESETS = {
  gentle: { label: 'Gentle', threshold: 20, hold: 60 },
  balanced: { label: 'Balanced', threshold: 15, hold: 30 },
  strict: { label: 'Strict', threshold: 12, hold: 20 },
};

// [seconds from start, forward°, sideways°]; linear between keyframes.
export const SCENARIOS = {
  slouch: {
    label: 'Slouch and hold',
    note: 'Drifts to 24° forward over 10 s and stays there.',
    keyframes: [[0, 0, 0], [3, 0, 0], [13, 24, 0], [62, 24, 0], [65, 0, 0]],
  },
  glances: {
    label: 'Quick glances',
    note: 'Looks down at 30° for 4 s, five times. No reminder expected.',
    keyframes: [[0, 0, 0], [2, 0, 0], [2.4, 30, 0], [6, 30, 0], [6.4, 0, 0], [11, 0, 0], [11.4, 30, 0], [15, 30, 0],
      [15.4, 0, 0], [20, 0, 0], [20.4, 30, 0], [24, 30, 0], [24.4, 0, 0], [29, 0, 0], [29.4, 30, 0], [33, 30, 0],
      [33.4, 0, 0], [38, 0, 0], [38.4, 30, 0], [42, 30, 0], [42.4, 0, 0], [46, 0, 0]],
  },
  right: {
    label: 'Ear to shoulder',
    note: 'Tilts 20° to the right and holds.',
    keyframes: [[0, 0, 0], [2, 0, 0], [5, 0, 20], [50, 0, 20], [53, 0, 0]],
  },
  up: {
    label: 'Look up',
    note: 'Looks up 30° and holds. The backward limit is wider than the forward one.',
    keyframes: [[0, 0, 0], [2, 0, 0], [5, -30, 0], [50, -30, 0], [53, 0, 0]],
  },
};

function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** Rotates v about `axis` (unit) by `angle` radians (Rodrigues). */
function rotate(v, axis, angle) {
  const c = Math.cos(angle), s = Math.sin(angle);
  const d = axis.x * v.x + axis.y * v.y + axis.z * v.z;
  return vec(
    v.x * c + (axis.y * v.z - axis.z * v.y) * s + axis.x * d * (1 - c),
    v.y * c + (axis.z * v.x - axis.x * v.z) * s + axis.y * d * (1 - c),
    v.z * c + (axis.x * v.y - axis.y * v.x) * s + axis.z * d * (1 - c),
  );
}

function poseAt(keyframes, t) {
  if (t <= keyframes[0][0]) return [keyframes[0][1], keyframes[0][2]];
  for (let i = 1; i < keyframes.length; i++) {
    const [t1, f1, l1] = keyframes[i];
    if (t <= t1) {
      const [t0, f0, l0] = keyframes[i - 1];
      const k = (t - t0) / (t1 - t0 || 1);
      return [f0 + (f1 - f0) * k, l0 + (l1 - l0) * k];
    }
  }
  const last = keyframes[keyframes.length - 1];
  return [last[1], last[2]];
}

export class Simulation {
  listeners = new Set();
  speed = 5;
  preset = 'balanced';
  scenario = null;
  scenarioStart = 0;
  target = { forward: 0, lateral: 0 };
  pose = { forward: 0, lateral: 0 };
  sway = { forward: 0, lateral: 0 };
  time = 0;
  history = [];
  events = [];
  lastReminder = null;
  running = false;
  frame = 0;
  wallLast = 0;
  carry = 0;

  constructor(seed = 20261031) {
    this.random = mulberry32(seed);
    this.config = defaultConfiguration();
    this.monitor = new PostureMonitor(this.config);
    // Gravity an upright head reports with the earbud sitting 8° pitched and 3° rolled in the ear.
    this.neutralGravity = rotate(rotate(vec(0, 0, -1), vec(1, 0, 0), 8 * RAD), vec(0, 1, 0), -3 * RAD);
    this.calibrateInstantly();
    this.snapshot = this.buildSnapshot(null);
  }

  // ---- Subscription (useSyncExternalStore) ------------------------------------------------

  subscribe = (listener) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };

  getSnapshot = () => this.snapshot;

  emit(update) {
    this.snapshot = this.buildSnapshot(update);
    for (const listener of this.listeners) listener();
  }

  // ---- Clock ------------------------------------------------------------------------------

  start() {
    if (this.running || typeof requestAnimationFrame === 'undefined') return;
    this.running = true;
    this.wallLast = performance.now();
    const tick = (now) => {
      if (!this.running) return;
      // A hidden tab pauses the simulation instead of jumping ahead on return.
      const elapsed = Math.min(0.1, (now - this.wallLast) / 1000);
      this.wallLast = now;
      this.advance(elapsed * this.speed);
      this.frame = requestAnimationFrame(tick);
    };
    this.frame = requestAnimationFrame(tick);
  }

  stop() {
    this.running = false;
    if (typeof cancelAnimationFrame !== 'undefined') cancelAnimationFrame(this.frame);
  }

  /** Advances simulated time, feeding the pipeline one sample per 1/25 s. */
  advance(simSeconds) {
    this.carry += simSeconds;
    let steps = Math.min(MAX_STEPS_PER_FRAME, Math.floor(this.carry / STEP));
    this.carry -= steps * STEP;
    if (this.carry > STEP * MAX_STEPS_PER_FRAME) this.carry = 0;
    let update = null;
    while (steps-- > 0) update = this.step();
    if (update) this.emit(update);
  }

  step() {
    this.time += STEP;
    const t = this.time;

    if (this.scenario) {
      const frames = SCENARIOS[this.scenario].keyframes;
      const local = t - this.scenarioStart;
      const [f, l] = poseAt(frames, local);
      this.target = { forward: f, lateral: l };
      if (local > frames[frames.length - 1][0] + 2) this.scenario = null;
    }

    // The head eases toward the target and sways a little around it.
    const follow = 1 - Math.exp(-STEP / 0.18);
    this.pose.forward += (this.target.forward - this.pose.forward) * follow;
    this.pose.lateral += (this.target.lateral - this.pose.lateral) * follow;
    const decay = Math.exp(-STEP / 2.5);
    this.sway.forward = this.sway.forward * decay + this.gauss() * 0.07;
    this.sway.lateral = this.sway.lateral * decay + this.gauss() * 0.07;

    const raw = {
      forward: this.pose.forward + this.sway.forward + this.gauss() * 0.35,
      lateral: this.pose.lateral + this.sway.lateral + this.gauss() * 0.35,
    };
    const gravity = this.gravityFor(raw.forward, raw.lateral);
    const update = this.monitor.process({ timestamp: t, gravity });
    this.record(update, raw, gravity);
    return update;
  }

  /** Head-frame gravity for a head tilted `forward`/`lateral` degrees from neutral. */
  gravityFor(forward, lateral) {
    const f = this.config.forwardAxis, l = this.config.lateralAxis;
    const r = vec(
      (f.x * forward + l.x * lateral) * RAD,
      (f.y * forward + l.y * lateral) * RAD,
      (f.z * forward + l.z * lateral) * RAD,
    );
    const angle = Math.hypot(r.x, r.y, r.z);
    if (angle < 1e-9) return this.neutralGravity;
    // Gravity seen in the head frame rotates opposite to the head.
    return normalized(rotate(this.neutralGravity, vec(r.x / angle, r.y / angle, r.z / angle), -angle));
  }

  gauss() {
    const u = Math.max(this.random(), 1e-12);
    return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * this.random());
  }

  record(update, raw, gravity) {
    const t = update.timestamp;
    this.lastGravity = gravity;
    this.history.push({
      t,
      raw: raw.forward,
      forward: update.tilt ? update.tilt.forwardDegrees : null,
      lateral: update.tilt ? update.tilt.lateralDegrees : null,
      kind: update.state.kind,
    });
    while (this.history.length && this.history[0].t < t - HISTORY_SECONDS - 1) this.history.shift();

    if (update.reminder) {
      this.lastReminder = update.reminder;
      this.log(t, 'reminder', `Reminder sent: ${update.reminder.direction} tilt of ${update.reminder.deviationDegrees.toFixed(1)}° held ${update.reminder.sustainedSeconds.toFixed(1)} s`);
    }
    if (update.completedEpisode) {
      const e = update.completedEpisode;
      this.log(t, 'episode', `Episode closed: ${e.direction}, ${(e.endTimestamp - e.startTimestamp).toFixed(1)} s, peak ${e.peakDeviationDegrees.toFixed(1)}°`);
    }
    if (update.calibrationOutcome) {
      const o = update.calibrationOutcome;
      this.log(t, 'calibration', o.kind === 'succeeded'
        ? `Calibrated from ${o.baseline.sampleCount} samples`
        : o.failure === 'tooMuchMovement' ? 'Calibration failed: the head moved too much' : `Calibration failed: ${o.failure}`);
    }
  }

  log(t, type, text) {
    this.events = [{ id: `${type}-${t.toFixed(2)}`, t, type, text }, ...this.events].slice(0, 5);
  }

  // ---- Commands ---------------------------------------------------------------------------

  /** Runs the 10 s calibration on a still head without waiting, so the page starts ready. */
  calibrateInstantly() {
    this.monitor.beginCalibration();
    const samples = Math.round(this.config.calibrationDuration * SAMPLE_RATE_HZ) + 1;
    for (let i = 0; i < samples; i++) {
      this.time += STEP;
      this.monitor.process({ timestamp: this.time, gravity: this.neutralGravity });
    }
  }

  recalibrate() {
    this.scenario = null;
    this.monitor.beginCalibration();
    this.emit(null);
  }

  setTarget(forward, lateral) {
    this.scenario = null;
    this.target = {
      forward: Math.max(-30, Math.min(40, forward)),
      lateral: Math.max(-30, Math.min(30, lateral)),
    };
    this.emit(null);
  }

  play(name) {
    this.scenario = name;
    this.scenarioStart = this.time;
    this.emit(null);
  }

  setSpeed(speed) {
    this.speed = speed;
    this.emit(null);
  }

  setPreset(name) {
    const p = PRESETS[name];
    this.preset = name;
    // Same mapping as SensitivityPreset.apply(to:) in the app.
    this.config.forwardThresholdDegrees = p.threshold;
    this.config.lateralThresholdDegrees = p.threshold;
    this.config.backwardThresholdDegrees = p.threshold + 5;
    this.config.sustainedDuration = p.hold;
    this.emit(null);
  }

  resetCooldown() {
    this.monitor.resetCooldown();
    this.emit(null);
  }

  // ---- Snapshot ---------------------------------------------------------------------------

  buildSnapshot(update) {
    const m = this.monitor;
    const state = m.state;
    const tilt = update?.tilt ?? m.lastTilt;
    const held = state.since != null ? Math.max(0, this.time - state.since) : 0;
    return {
      time: this.time,
      state,
      tilt,
      held,
      gravity: this.lastGravity ?? this.neutralGravity,
      smoothed: m.filter.value,
      outside: state.kind === 'deviating' || state.kind === 'sustainedTilt',
      cooldownRemaining: m.reminders.remaining(this.time, this.config.reminderCooldown),
      lastReminder: this.lastReminder,
      events: this.events,
      target: this.target,
      scenario: this.scenario,
      speed: this.speed,
      preset: this.preset,
      config: this.config,
    };
  }
}
