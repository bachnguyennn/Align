// D-022: the "get ready" countdown before a neutral calibration. Mirrors CalibrationCountdownTest
// (Java, analytics/align-tools) and CalibrationCountdownTests (Swift, AlignKit).
import { describe, expect, it } from 'vitest';
import { CalibrationService, PostureMonitor, angleDegrees, defaultConfiguration, vec } from './pipeline.js';

const RAD = Math.PI / 180;
// Head-frame gravity for a pure forward tilt about the default forward axis (-1, 0, 0).
const gFor = (forward) => vec(0, Math.sin(forward * RAD), -Math.cos(forward * RAD));
const lookUp = (t, at) => gFor(t < at ? 30 : 0);
const noCountdown = () => ({ ...defaultConfiguration(), calibrationCountdown: 0 });

function run(service, config, gravityAt, seconds) {
  let step = null;
  for (let i = 0; i <= Math.round(seconds * 25); i++) {
    const t = i / 25;
    step = service.add(gravityAt(t), t, config);
    if (step.kind !== 'inProgress') return { step, t };
  }
  return { step, t: null };
}

describe('calibration countdown (D-022)', () => {
  it('defaults to 3 s', () => {
    expect(defaultConfiguration().calibrationCountdown).toBe(3);
  });

  it('discards the countdown samples and starts the hold after it', () => {
    const c = new CalibrationService();
    c.begin();
    expect(c.isCountingDown).toBe(true);
    expect(c.countdownRemaining(3)).toBe(3);
    const first = c.add(gFor(30), 0, defaultConfiguration());
    expect(first).toEqual({ kind: 'inProgress', progress: 0 });
    c.add(gFor(30), 1, defaultConfiguration());
    expect(c.countdownRemaining(3)).toBeCloseTo(2, 9);
    c.cancel();

    const s = new CalibrationService();
    s.begin();
    const { step, t } = run(s, defaultConfiguration(), (x) => lookUp(x, 2), 13);
    expect(t).toBeCloseTo(13, 9);  // 3 s countdown + 10 s hold
    expect(step.kind).toBe('succeeded');
    expect(step.sampleCount).toBe(251);  // t = 3.0 .. 13.0; the 75 countdown samples are dropped
    expect(angleDegrees(step.meanGravity, gFor(0))).toBeCloseTo(0, 9);
  });

  it('fails the same look-up without a countdown', () => {
    const c = new CalibrationService();
    c.begin();
    const { step } = run(c, noCountdown(), (x) => lookUp(x, 2), 10);
    expect(step).toMatchObject({ kind: 'failed', failure: 'tooMuchMovement' });
  });

  it('still fails when the head moves during the hold', () => {
    const c = new CalibrationService();
    c.begin();
    const { step } = run(c, defaultConfiguration(), (x) => gFor(x >= 3 && x < 8 ? 9 : 0), 13);
    expect(step).toMatchObject({ kind: 'failed', failure: 'tooMuchMovement' });
  });

  it('reports calibrating at 0 and the remaining countdown; cancel gives no outcome', () => {
    const m = new PostureMonitor(defaultConfiguration());
    expect(m.calibrationCountdownRemaining).toBeNull();
    m.beginCalibration();
    expect(m.calibrationCountdownRemaining).toBe(3);
    let update = null;
    for (let i = 0; i < 25; i++) update = m.process({ timestamp: i * 0.04, gravity: gFor(30) });
    expect(update.state).toEqual({ kind: 'calibrating', progress: 0 });
    expect(m.calibrationCountdownRemaining).toBeCloseTo(3 - 0.96, 9);
    m.cancelCalibration();
    expect(m.calibrationCountdownRemaining).toBeNull();
    update = m.process({ timestamp: 1, gravity: gFor(0) });
    expect(update.state.kind).toBe('needsCalibration');
    expect(update.calibrationOutcome ?? null).toBeNull();
  });
});
