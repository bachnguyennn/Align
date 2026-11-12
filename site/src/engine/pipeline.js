// JavaScript port of Align's posture pipeline.
//
// Source of truth: the Java reference in analytics/align-tools and the Swift package in
// ios/AlignKit/Sources/PostureDetection. This file mirrors them component for component and is
// checked against the same replay fixtures (shared/fixtures/motion) in fixtures.test.js.

export const TIME_EPSILON = 1e-9;
export const DECIMATION_EPSILON = 1e-6;
const DEG = 180 / Math.PI;

// ---- Vectors ------------------------------------------------------------------------------

export const vec = (x, y, z) => ({ x, y, z });
const ZERO = vec(0, 0, 0);
const add = (a, b) => vec(a.x + b.x, a.y + b.y, a.z + b.z);
const sub = (a, b) => vec(a.x - b.x, a.y - b.y, a.z - b.z);
const scale = (a, k) => vec(a.x * k, a.y * k, a.z * k);
const dot = (a, b) => a.x * b.x + a.y * b.y + a.z * b.z;
const cross = (a, b) => vec(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);
const length = (a) => Math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z);
export function normalized(a) {
  const l = length(a);
  return l > 0 ? vec(a.x / l, a.y / l, a.z / l) : ZERO;
}

/** Head-frame gravity for a head-to-world attitude [x, y, z, w] in a Z-up world. */
export function gravityFromAttitude(q) {
  const n = Math.hypot(q[0], q[1], q[2], q[3]);
  if (!(n > 0)) return vec(0, 0, -1);
  // Rotate (0, 0, -1) by the conjugate of the unit quaternion.
  const x = -q[0] / n, y = -q[1] / n, z = -q[2] / n, w = q[3] / n;
  return vec(-(2 * (x * z + w * y)), -(2 * (y * z - w * x)), -(1 - 2 * (x * x + y * y)));
}

// ---- Configuration ------------------------------------------------------------------------

export const defaultConfiguration = () => ({
  calibrationDuration: 10,
  calibrationMaxSpreadDegrees: 5,
  calibrationSpreadQuantile: 0.9,
  calibrationMaxDriftDegrees: 3,
  calibrationDriftWindow: 2,
  minimumCalibrationSamples: 100,
  forwardThresholdDegrees: 15,
  backwardThresholdDegrees: 20,
  lateralThresholdDegrees: 15,
  hysteresisDegrees: 3,
  sustainedDuration: 30,
  reminderCooldown: 300,
  smoothingTimeConstant: 0.5,
  maxProcessingRateHz: null,
  maxSampleGap: 1.0,
  // HeadAxisConvention.airPodsDefault (D-011): +X right ear, +Y nose, +Z up.
  forwardAxis: vec(-1, 0, 0),
  lateralAxis: vec(0, 1, 0),
  // Guided-nod axis calibration (D-017).
  axisCalibrationDuration: 8,
  axisCalibrationMinimumNodDegrees: 12,
  axisCalibrationMaxYawDegrees: 45,
  axisCalibrationMaxOffAxisRatio: 0.35,
});

// ---- MotionFilter -------------------------------------------------------------------------

/** Time-constant exponential smoothing of the gravity unit vector: alpha = 1 - exp(-dt / tau). */
export class MotionFilter {
  value = null;
  lastTimestamp = null;

  reset() {
    this.value = null;
    this.lastTimestamp = null;
  }

  update(gravity, timestamp, timeConstant) {
    if (this.value === null || this.lastTimestamp === null) {
      this.value = gravity;
      this.lastTimestamp = timestamp;
      return gravity;
    }
    const dt = Math.max(0, timestamp - this.lastTimestamp);
    const alpha = timeConstant <= 0 ? 1 : 1 - Math.exp(-dt / timeConstant);
    const blended = add(this.value, scale(sub(gravity, this.value), alpha));
    let result = normalized(blended);
    if (length(result) === 0) result = gravity;
    this.value = result;
    this.lastTimestamp = timestamp;
    return result;
  }
}

// ---- Tilt estimation (D-005) --------------------------------------------------------------

const PARALLEL_EPSILON = 1e-12;
const AXIS_DEGENERACY_EPSILON = 1e-3;

/** Minimal rotation taking unit vector `from` to unit vector `to`, as axis × angle (radians). */
export function rotationVector(from, to) {
  const c = cross(from, to);
  const s = length(c);
  if (s < PARALLEL_EPSILON) return ZERO;
  return scale(c, Math.atan2(s, dot(from, to)) / s);
}

/** `axis` projected onto the plane perpendicular to `baseline` (unit) and renormalized. */
export function baselinePlaneAxis(axis, baseline) {
  const a = normalized(axis);
  const p = sub(a, scale(baseline, dot(a, baseline)));
  const n = length(p);
  return n < AXIS_DEGENERACY_EPSILON ? a : scale(p, 1 / n);
}

export function angleDegrees(a, b) {
  return Math.atan2(length(cross(a, b)), dot(a, b)) * DEG;
}

/**
 * Tilt of head-frame `gravity` relative to the baseline gravity. Gravity seen in the head frame
 * rotates opposite to the head, so the head rotation vector is the negated gravity rotation.
 * Rotation about the baseline (turning the head) leaves gravity unchanged and so never registers.
 */
export function estimateTilt(timestamp, gravity, baseline, axes) {
  const g0 = normalized(baseline);
  const head = scale(rotationVector(g0, gravity), -1);
  return {
    timestamp,
    forwardDegrees: dot(head, baselinePlaneAxis(axes.forwardAxis, g0)) * DEG,
    lateralDegrees: dot(head, baselinePlaneAxis(axes.lateralAxis, g0)) * DEG,
    totalDegrees: angleDegrees(g0, gravity),
  };
}

// ---- Calibration --------------------------------------------------------------------------

const QUANTILE_EPSILON = 1e-9;

/**
 * Collects `calibrationDuration` seconds of smoothed gravity and turns it into a baseline.
 *
 * Spread rule (D-017): at least `calibrationSpreadQuantile` of the samples must lie within
 * `calibrationMaxSpreadDegrees` of the mean, so a brief fidget is tolerated. The baseline is the
 * mean of those inliers.
 *
 * Drift rule (D-020): the mean of the inliers in the first and in the last
 * `calibrationDriftWindow` seconds must be within `calibrationMaxDriftDegrees` of each other.
 * This catches a slow slouch, which the spread rule cannot.
 */
export class CalibrationService {
  isActive = false;
  startTimestamp = null;
  lastTimestamp = null;
  samples = [];
  timestamps = [];

  begin() {
    this.isActive = true;
    this.startTimestamp = null;
    this.lastTimestamp = null;
    this.samples = [];
    this.timestamps = [];
  }

  cancel() {
    this.isActive = false;
    this.startTimestamp = null;
    this.lastTimestamp = null;
    this.samples = [];
    this.timestamps = [];
  }

  progress(duration) {
    if (!this.isActive || this.startTimestamp === null || this.lastTimestamp === null) return 0;
    if (duration <= 0) return 1;
    return Math.min(1, Math.max(0, (this.lastTimestamp - this.startTimestamp) / duration));
  }

  /** Angle between the mean inlier gravity of the first and last `window` seconds; NaN if either is empty. */
  static driftDegrees(gravities, times, inliers, window) {
    if (times.length === 0) return NaN;
    const first = times[0], last = times[times.length - 1];
    let head = ZERO, tail = ZERO, headCount = 0, tailCount = 0;
    gravities.forEach((g, i) => {
      if (inliers && !inliers[i]) return;
      if (times[i] - first <= window + TIME_EPSILON) { head = add(head, g); headCount += 1; }
      if (last - times[i] <= window + TIME_EPSILON) { tail = add(tail, g); tailCount += 1; }
    });
    if (headCount === 0 || tailCount === 0) return NaN;
    return angleDegrees(normalized(head), normalized(tail));
  }

  static hasEnoughInliers(inliers, count, quantile) {
    const q = Math.min(1, Math.max(0, quantile));
    return inliers + QUANTILE_EPSILON * count >= q * count;
  }

  add(gravity, timestamp, config) {
    if (this.startTimestamp === null) this.startTimestamp = timestamp;
    this.lastTimestamp = timestamp;
    this.samples.push(gravity);
    this.timestamps.push(timestamp);
    const duration = config.calibrationDuration;
    if (timestamp - this.startTimestamp + TIME_EPSILON < duration) {
      return { kind: 'inProgress', progress: this.progress(duration) };
    }
    const collected = this.samples;
    const times = this.timestamps;
    this.cancel();
    const sampleCount = collected.length;
    const failed = (failure) => ({ kind: 'failed', failure, sampleCount });
    if (sampleCount < config.minimumCalibrationSamples) return failed('insufficientSamples');
    const mean = normalized(collected.reduce(add, ZERO));
    if (length(mean) === 0) return failed('tooMuchMovement');

    const isInlier = collected.map((g) => angleDegrees(g, mean) <= config.calibrationMaxSpreadDegrees);
    const inliers = isInlier.filter(Boolean).length;
    if (!CalibrationService.hasEnoughInliers(inliers, sampleCount, config.calibrationSpreadQuantile)) {
      return failed('tooMuchMovement');
    }
    // A window without inliers gives NaN, which fails this comparison.
    const drift = CalibrationService.driftDegrees(collected, times, isInlier, config.calibrationDriftWindow);
    if (!(drift <= config.calibrationMaxDriftDegrees)) return failed('tooMuchMovement');

    const meanGravity = inliers === sampleCount
      ? mean
      : normalized(collected.reduce((sum, g, i) => (isInlier[i] ? add(sum, g) : sum), ZERO));
    if (length(meanGravity) === 0) return failed('tooMuchMovement');
    return { kind: 'succeeded', meanGravity, sampleCount };
  }
}

// ---- Axis calibration (guided nod, D-017) -------------------------------------------------

const AXIS_MOTION_FLOOR_DEGREES = 3;
const AXIS_RETURN_DEGREES = 5;

/**
 * Learns the forward axis from one nod. Each smoothed sample becomes the head rotation vector
 * relative to the baseline; the forward axis line is the principal axis of those vectors in the
 * baseline plane. The sign comes from the configured axis, so a nod down or up both work. A fit
 * too far from the default axis, or with too much sideways motion, is rejected.
 */
export class AxisCalibrationService {
  isActive = false;
  startTimestamp = null;
  lastTimestamp = null;
  peakDegrees = 0;
  rotations = [];

  begin() {
    this.isActive = true;
    this.startTimestamp = null;
    this.lastTimestamp = null;
    this.peakDegrees = 0;
    this.rotations = [];
  }

  cancel() {
    this.isActive = false;
    this.startTimestamp = null;
    this.lastTimestamp = null;
    this.peakDegrees = 0;
    this.rotations = [];
  }

  progress(duration) {
    if (!this.isActive || this.startTimestamp === null || this.lastTimestamp === null) return 0;
    if (duration <= 0) return 1;
    return Math.min(1, Math.max(0, (this.lastTimestamp - this.startTimestamp) / duration));
  }

  add(gravity, timestamp, baselineGravity, config) {
    if (this.startTimestamp === null) this.startTimestamp = timestamp;
    this.lastTimestamp = timestamp;
    const g0 = normalized(baselineGravity);
    const head = scale(rotationVector(g0, gravity), -1);
    const angle = length(head) * DEG;
    const minimumNod = config.axisCalibrationMinimumNodDegrees;
    if (angle >= Math.min(AXIS_MOTION_FLOOR_DEGREES, 0.5 * minimumNod)) this.rotations.push(head);
    if (angle > this.peakDegrees) this.peakDegrees = angle;
    const validPeak = this.peakDegrees >= minimumNod;
    const returned = validPeak && angle <= Math.min(AXIS_RETURN_DEGREES, 0.5 * minimumNod);
    const duration = config.axisCalibrationDuration;
    if (!returned && timestamp - this.startTimestamp + TIME_EPSILON < duration) {
      return { kind: 'inProgress', progress: this.progress(duration) };
    }

    const used = this.rotations;
    this.cancel();
    if (!validPeak || used.length === 0) return { kind: 'failed', failure: 'noNodDetected' };
    const fit = AxisCalibrationService.fit(used, g0, config);
    if (fit.axes === null
      || Math.abs(fit.yawDegrees) > config.axisCalibrationMaxYawDegrees
      || !(fit.offAxisRatio <= config.axisCalibrationMaxOffAxisRatio)) {
      return { kind: 'failed', failure: 'inconsistentMotion' };
    }
    return { kind: 'succeeded', axes: fit.axes, yawDegrees: fit.yawDegrees };
  }

  /** Principal axis of `rotations` in the plane perpendicular to unit `baseline`. */
  static fit(rotations, baseline, reference) {
    const e1 = baselinePlaneAxis(reference.forwardAxis, baseline);
    const e2 = normalized(cross(baseline, e1));
    if (length(e2) === 0) return { axes: null, yawDegrees: 90, offAxisRatio: Infinity };
    let saa = 0, sbb = 0, sab = 0;
    for (const v of rotations) {
      const a = dot(v, e1), c = dot(v, e2);
      saa += a * a;
      sbb += c * c;
      sab += a * c;
    }
    const angle = 0.5 * Math.atan2(2 * sab, saa - sbb);
    const forwardAxis = normalized(add(scale(e1, Math.cos(angle)), scale(e2, Math.sin(angle))));
    const lateralAxis = normalized(cross(baseline, forwardAxis));
    let along = 0, across = 0;
    for (const v of rotations) {
      along += Math.abs(dot(v, forwardAxis));
      across += Math.abs(dot(v, lateralAxis));
    }
    return {
      axes: { forwardAxis, lateralAxis },
      yawDegrees: angle * DEG,
      offAxisRatio: along > 0 ? across / along : Infinity,
    };
  }
}

// ---- PostureDetector ----------------------------------------------------------------------

const MINIMUM_THRESHOLD = 1e-6;
export const DIRECTIONS = ['forward', 'backward', 'left', 'right'];

/** Signed tilt in `direction` (degrees): positive means tilted that way. */
export function component(tilt, direction) {
  switch (direction) {
    case 'forward': return tilt.forwardDegrees;
    case 'backward': return -tilt.forwardDegrees;
    case 'right': return tilt.lateralDegrees;
    default: return -tilt.lateralDegrees;
  }
}

export function threshold(direction, config) {
  const t = direction === 'forward' ? config.forwardThresholdDegrees
    : direction === 'backward' ? config.backwardThresholdDegrees
    : config.lateralThresholdDegrees;
  return Math.max(t, MINIMUM_THRESHOLD);
}

/** The direction whose component/threshold ratio is largest among those at or over threshold. */
export function dominantDirection(tilt, config) {
  let best = null;
  let bestRatio = 0;
  for (const candidate of DIRECTIONS) {
    const ratio = component(tilt, candidate) / threshold(candidate, config);
    if (ratio >= 1 && ratio > bestRatio) {
      best = candidate;
      bestRatio = ratio;
    }
  }
  return best;
}

/**
 * neutral → deviating(d) when a direction reaches its threshold (direction then locked);
 * deviating → sustained after `sustainedDuration`; back to neutral once d's component drops
 * below threshold − hysteresis. Leaving sustained produces an episode.
 */
export class PostureDetector {
  phase = 'neutral';
  direction = null;
  since = null;
  peakDegrees = 0;
  reminderTriggered = false;

  get state() {
    if (this.phase === 'neutral' || this.direction === null || this.since === null) {
      return { kind: 'neutral' };
    }
    return {
      kind: this.phase === 'sustained' ? 'sustainedTilt' : 'deviating',
      direction: this.direction,
      since: this.since,
    };
  }

  reset() {
    this.phase = 'neutral';
    this.direction = null;
    this.since = null;
    this.peakDegrees = 0;
    this.reminderTriggered = false;
  }

  markReminderTriggered() {
    this.reminderTriggered = true;
  }

  interrupt(timestamp) {
    const episode = this.phase === 'sustained' ? this.makeEpisode(timestamp) : null;
    this.reset();
    return episode;
  }

  update(tilt, config) {
    const t = tilt.timestamp;
    let completedEpisode = null;
    let becameSustained = false;

    if (this.phase !== 'neutral') {
      if (this.direction !== null && this.since !== null) {
        const value = component(tilt, this.direction);
        const release = threshold(this.direction, config) - config.hysteresisDegrees;
        if (value < release) {
          if (this.phase === 'sustained') completedEpisode = this.makeEpisode(t);
          this.reset();
        } else {
          if (value > this.peakDegrees) this.peakDegrees = value;
          const elapsed = t - this.since + TIME_EPSILON;
          if (this.phase === 'deviating' && elapsed >= config.sustainedDuration) {
            this.phase = 'sustained';
            becameSustained = true;
          }
        }
      } else {
        this.reset();
      }
    }

    if (this.phase === 'neutral') {
      const d = dominantDirection(tilt, config);
      if (d !== null) {
        this.phase = 'deviating';
        this.direction = d;
        this.since = t;
        this.peakDegrees = component(tilt, d);
        this.reminderTriggered = false;
        if (config.sustainedDuration <= TIME_EPSILON) {
          this.phase = 'sustained';
          becameSustained = true;
        }
      }
    }

    return { state: this.state, becameSustained, completedEpisode };
  }

  makeEpisode(end) {
    if (this.direction === null || this.since === null) return null;
    return {
      direction: this.direction,
      startTimestamp: this.since,
      endTimestamp: end,
      peakDeviationDegrees: this.peakDegrees,
      reminderTriggered: this.reminderTriggered,
    };
  }
}

// ---- Reminder cooldown --------------------------------------------------------------------

/** At most one reminder per `cooldown` seconds; a clock that went backwards also allows one. */
export class ReminderDecisionEngine {
  lastReminderTimestamp = null;

  reset() {
    this.lastReminderTimestamp = null;
  }

  /** Seconds until a reminder is allowed again at `timestamp` (0 when one is allowed now). */
  remaining(timestamp, cooldown) {
    const last = this.lastReminderTimestamp;
    if (last === null || timestamp < last) return 0;
    return Math.max(0, cooldown - (timestamp - last));
  }

  evaluate(timestamp, direction, deviationDegrees, sustainedSeconds, cooldown) {
    const last = this.lastReminderTimestamp;
    if (last !== null && timestamp >= last && timestamp - last + TIME_EPSILON < cooldown) {
      return null;
    }
    this.lastReminderTimestamp = timestamp;
    return { timestamp, direction, deviationDegrees, sustainedSeconds };
  }
}

// ---- PostureMonitor -----------------------------------------------------------------------

/**
 * The whole pipeline. Per sample: validate → gap check → decimation → MotionFilter →
 * CalibrationService or AxisCalibrationService (while calibrating), otherwise tilt estimate +
 * PostureDetector → reminder decision. Tilt uses the axes learned from a nod when there are any.
 */
export class PostureMonitor {
  filter = new MotionFilter();
  calibration = new CalibrationService();
  axisCalibration = new AxisCalibrationService();
  detector = new PostureDetector();
  reminders = new ReminderDecisionEngine();
  lastReceivedTimestamp = null;
  lastProcessedTimestamp = null;
  nextProcessingDue = null;
  hasData = false;
  lastTilt = null;
  pendingEpisode = null;
  pendingAxisOutcome = null;

  constructor(configuration = defaultConfiguration(), baseline = null) {
    this.configuration = configuration;
    this.baseline = baseline;
  }

  get state() {
    if (this.calibration.isActive) {
      return {
        kind: 'calibrating',
        progress: this.calibration.progress(this.configuration.calibrationDuration),
      };
    }
    if (this.axisCalibration.isActive) {
      return {
        kind: 'calibrating',
        progress: this.axisCalibration.progress(this.configuration.axisCalibrationDuration),
      };
    }
    if (!this.hasData) return { kind: 'unavailable' };
    if (this.baseline === null) return { kind: 'needsCalibration' };
    return this.detector.state;
  }

  get effectiveAxes() {
    return this.baseline?.learnedAxes ?? this.configuration;
  }

  beginCalibration() {
    this.closeOpenEpisode();
    this.axisCalibration.cancel();
    this.calibration.begin();
  }

  /** Starts the guided nod. Needs a baseline; without one the next update reports `needsBaseline`. */
  beginAxisCalibration() {
    this.calibration.cancel();
    this.closeOpenEpisode();
    if (this.baseline === null) {
      this.axisCalibration.cancel();
      this.pendingAxisOutcome = { kind: 'failed', failure: 'needsBaseline' };
      return;
    }
    this.axisCalibration.begin();
  }

  cancelAxisCalibration() {
    this.axisCalibration.cancel();
    this.detector.reset();
  }

  clearLearnedAxes() {
    if (this.baseline?.learnedAxes) this.baseline = { ...this.baseline, learnedAxes: null };
  }

  closeOpenEpisode() {
    if (this.detector.phase !== 'neutral') {
      const episode = this.detector.interrupt(this.lastProcessedTimestamp ?? 0);
      if (this.pendingEpisode === null) this.pendingEpisode = episode;
    }
    this.detector.reset();
  }

  cancelCalibration() {
    this.calibration.cancel();
    this.detector.reset();
  }

  resetCooldown() {
    this.reminders.reset();
  }

  interrupt(timestamp) {
    const { episode, outcome, axisOutcome } = this.interruptCore(timestamp);
    const pendingAxis = this.takePendingAxisOutcome();
    return {
      timestamp,
      tilt: null,
      state: this.state,
      reminder: null,
      completedEpisode: episode,
      calibrationOutcome: outcome,
      axisCalibrationOutcome: axisOutcome ?? pendingAxis,
    };
  }

  /** sample: { timestamp, gravity?: {x,y,z}, attitude?: [x,y,z,w] } */
  process(sample) {
    const t = sample.timestamp;
    const gravity = normalized(sample.gravity ?? gravityFromAttitude(sample.attitude ?? [0, 0, 0, 1]));
    if (length(gravity) === 0) return this.passiveUpdate(t, null, null, null);
    if (this.lastReceivedTimestamp !== null && t <= this.lastReceivedTimestamp) {
      return this.passiveUpdate(t, null, null, null);
    }

    let gapEpisode = null;
    let gapOutcome = null;
    let gapAxisOutcome = null;
    if (this.lastReceivedTimestamp !== null && t - this.lastReceivedTimestamp > this.configuration.maxSampleGap) {
      const result = this.interruptCore(this.lastReceivedTimestamp);
      gapEpisode = result.episode;
      gapOutcome = result.outcome;
      gapAxisOutcome = result.axisOutcome;
    }
    this.lastReceivedTimestamp = t;

    if (!this.shouldProcess(t)) return this.passiveUpdate(t, gapEpisode, gapOutcome, gapAxisOutcome);

    const config = this.configuration;
    const smoothed = this.filter.update(gravity, t, config.smoothingTimeConstant);
    this.hasData = true;
    this.lastProcessedTimestamp = t;

    let episode = this.takePendingEpisode() ?? gapEpisode;
    let outcome = gapOutcome;
    let axisOutcome = this.takePendingAxisOutcome() ?? gapAxisOutcome;
    let reminder = null;
    let tilt = null;

    if (this.calibration.isActive) {
      const step = this.calibration.add(smoothed, t, config);
      if (step.kind === 'succeeded') {
        this.baseline = {
          gravity: step.meanGravity,
          sampleCount: step.sampleCount,
          version: (this.baseline?.version ?? 0) + 1,
          // A new neutral calibration clears learned axes: each earbud insertion is a new fit.
          learnedAxes: null,
        };
        outcome = { kind: 'succeeded', baseline: this.baseline };
        this.detector.reset();
      } else if (step.kind === 'failed') {
        outcome = { kind: 'failed', failure: step.failure };
        this.detector.reset();
      }
      if (this.baseline !== null) tilt = this.estimate(t, smoothed);
    } else if (this.axisCalibration.isActive && this.baseline !== null) {
      const step = this.axisCalibration.add(smoothed, t, this.baseline.gravity, config);
      if (step.kind === 'succeeded') {
        this.baseline = { ...this.baseline, learnedAxes: step.axes, version: this.baseline.version + 1 };
        axisOutcome = { kind: 'succeeded', axes: step.axes, yawDegrees: step.yawDegrees };
        this.detector.reset();
      } else if (step.kind === 'failed') {
        axisOutcome = { kind: 'failed', failure: step.failure };
        this.detector.reset();
      }
      tilt = this.estimate(t, smoothed);
    } else if (this.baseline !== null) {
      tilt = this.estimate(t, smoothed);
      const out = this.detector.update(tilt, config);
      if (episode === null && out.completedEpisode !== null) episode = out.completedEpisode;
      // Evaluated on every sustained update until this episode has reminded, so a tilt that
      // became sustained during the cooldown still reminds once the cooldown ends (D-016).
      const d = this.detector;
      if (d.phase === 'sustained' && !d.reminderTriggered && d.direction !== null && d.since !== null) {
        const decision = this.reminders.evaluate(
          t, d.direction, component(tilt, d.direction), t - d.since, config.reminderCooldown,
        );
        if (decision !== null) {
          d.markReminderTriggered();
          reminder = decision;
        }
      }
    }

    this.lastTilt = tilt;
    return {
      timestamp: t, tilt, state: this.state, reminder,
      completedEpisode: episode, calibrationOutcome: outcome, axisCalibrationOutcome: axisOutcome,
    };
  }

  estimate(t, smoothed) {
    return estimateTilt(t, smoothed, this.baseline.gravity, this.effectiveAxes);
  }

  takePendingAxisOutcome() {
    const outcome = this.pendingAxisOutcome;
    this.pendingAxisOutcome = null;
    return outcome;
  }

  takePendingEpisode() {
    const episode = this.pendingEpisode;
    this.pendingEpisode = null;
    return episode;
  }

  interruptCore(timestamp) {
    const pending = this.takePendingEpisode();
    const detectorEpisode = this.detector.interrupt(timestamp);
    let outcome = null;
    if (this.calibration.isActive) {
      this.calibration.cancel();
      outcome = { kind: 'failed', failure: 'sensorInterrupted' };
    }
    let axisOutcome = null;
    if (this.axisCalibration.isActive) {
      this.axisCalibration.cancel();
      axisOutcome = { kind: 'failed', failure: 'sensorInterrupted' };
    }
    this.filter.reset();
    this.hasData = false;
    this.lastReceivedTimestamp = null;
    this.lastProcessedTimestamp = null;
    this.nextProcessingDue = null;
    this.lastTilt = null;
    return { episode: pending ?? detectorEpisode, outcome, axisOutcome };
  }

  shouldProcess(t) {
    const rate = this.configuration.maxProcessingRateHz;
    if (!(rate > 0)) {
      this.nextProcessingDue = null;
      return true;
    }
    const period = 1 / rate;
    if (this.nextProcessingDue === null) {
      this.nextProcessingDue = t + period;
      return true;
    }
    if (t + DECIMATION_EPSILON < this.nextProcessingDue) return false;
    let next = this.nextProcessingDue + period;
    if (next <= t) next = t + period;
    this.nextProcessingDue = next;
    return true;
  }

  passiveUpdate(t, episode, outcome, axisOutcome) {
    const pending = this.takePendingEpisode();
    const pendingAxis = this.takePendingAxisOutcome();
    return {
      timestamp: t,
      tilt: this.lastTilt,
      state: this.state,
      reminder: null,
      completedEpisode: episode ?? pending,
      calibrationOutcome: outcome,
      axisCalibrationOutcome: axisOutcome ?? pendingAxis,
    };
  }
}
