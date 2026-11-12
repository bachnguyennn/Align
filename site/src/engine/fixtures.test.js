// Replays the shared motion fixtures through the JavaScript port and checks it against the
// `reference` block written by the reference implementation, the same way the Swift and Java
// suites do (shared/fixtures/README.md).
import { readdirSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { PostureMonitor, defaultConfiguration, vec } from './pipeline.js';

const dir = fileURLToPath(new URL('../../../shared/fixtures/motion/', import.meta.url));
const fixtures = readdirSync(dir).filter((f) => f.endsWith('.json')).sort();

function configuration(overrides = {}) {
  const config = defaultConfiguration();
  for (const [key, value] of Object.entries(overrides ?? {})) {
    config[key] = key.endsWith('Axis') ? vec(...value) : value;
  }
  return config;
}

function replay(fixture) {
  const baseline = fixture.baseline
    ? {
      gravity: vec(...fixture.baseline.gravity),
      version: fixture.baseline.version ?? 1,
      sampleCount: fixture.baseline.sampleCount ?? 0,
      learnedAxes: fixture.baseline.learnedAxes
        ? { forwardAxis: vec(...fixture.baseline.learnedAxes.forwardAxis), lateralAxis: vec(...fixture.baseline.learnedAxes.lateralAxis) }
        : null,
    }
    : null;
  const monitor = new PostureMonitor(configuration(fixture.config), baseline);
  const actions = [...(fixture.actions ?? [])].map((a, i) => [a, i]).sort((l, r) => l[0].t - r[0].t || l[1] - r[1]).map(([a]) => a);
  const result = { reminders: [], episodes: [], calibrationOutcomes: [], axisCalibrationOutcomes: [], learnedAxes: null, finalState: '', stateTransitions: 0 };
  let previousKind = null;

  const record = (update) => {
    if (update.reminder) result.reminders.push(update.reminder);
    if (update.completedEpisode) result.episodes.push(update.completedEpisode);
    if (update.calibrationOutcome) {
      const o = update.calibrationOutcome;
      result.calibrationOutcomes.push(o.kind === 'succeeded' ? 'succeeded' : o.failure);
    }
    if (update.axisCalibrationOutcome) {
      const o = update.axisCalibrationOutcome;
      result.axisCalibrationOutcomes.push(o.kind === 'succeeded' ? 'succeeded' : o.failure);
    }
    if (previousKind !== null && previousKind !== update.state.kind) result.stateTransitions += 1;
    previousKind = update.state.kind;
  };
  const apply = (action) => {
    if (action.type === 'beginCalibration') monitor.beginCalibration();
    else if (action.type === 'cancelCalibration') monitor.cancelCalibration();
    else if (action.type === 'beginAxisCalibration') monitor.beginAxisCalibration();
    else if (action.type === 'cancelAxisCalibration') monitor.cancelAxisCalibration();
    else if (action.type === 'clearLearnedAxes') monitor.clearLearnedAxes();
    else if (action.type === 'resetCooldown') monitor.resetCooldown();
    else if (action.type === 'interrupt') record(monitor.interrupt(action.t));
    else throw new Error(`unknown action ${action.type}`);
  };

  let index = 0;
  for (const s of fixture.samples) {
    while (index < actions.length && actions[index].t <= s.t) apply(actions[index++]);
    record(monitor.process({ timestamp: s.t, attitude: s.q, gravity: s.g ? vec(...s.g) : undefined }));
  }
  while (index < actions.length) apply(actions[index++]);
  result.finalState = monitor.state.kind;
  result.learnedAxes = monitor.baseline?.learnedAxes ?? null;
  return result;
}

describe('fixture replay parity with the reference implementation', () => {
  it('finds every committed fixture', () => {
    expect(fixtures).toHaveLength(14);
  });

  for (const file of fixtures) {
    it(file.replace('.json', ''), () => {
      const fixture = JSON.parse(readFileSync(dir + file, 'utf8'));
      const ref = fixture.reference;
      const got = replay(fixture);

      expect(got.calibrationOutcomes).toEqual(ref.calibrationOutcomes);
      expect(got.finalState).toBe(ref.finalState);
      expect(got.stateTransitions).toBe(ref.stateTransitions);

      expect(got.reminders.map((r) => r.direction)).toEqual(ref.reminders.map((r) => r.direction));
      got.reminders.forEach((r, i) => {
        expect(r.timestamp).toBeCloseTo(ref.reminders[i].t, 6);
        expect(r.deviationDegrees).toBeCloseTo(ref.reminders[i].deviationDegrees, 3);
        expect(r.sustainedSeconds).toBeCloseTo(ref.reminders[i].sustainedSeconds, 3);
      });

      expect(got.axisCalibrationOutcomes).toEqual(ref.axisCalibrationOutcomes ?? []);
      if (ref.axisCalibrationOutcomes) {
        expect(got.learnedAxes === null).toBe((ref.learnedAxes ?? null) === null);
        if (got.learnedAxes && ref.learnedAxes) {
          for (const axis of ['forwardAxis', 'lateralAxis']) {
            ['x', 'y', 'z'].forEach((k, i) => expect(got.learnedAxes[axis][k]).toBeCloseTo(ref.learnedAxes[axis][i], 4));
          }
        }
      }

      expect(got.episodes.map((e) => e.direction)).toEqual(ref.episodes.map((e) => e.direction));
      got.episodes.forEach((e, i) => {
        expect(e.startTimestamp).toBeCloseTo(ref.episodes[i].start, 6);
        expect(e.endTimestamp).toBeCloseTo(ref.episodes[i].end, 6);
        expect(e.peakDeviationDegrees).toBeCloseTo(ref.episodes[i].peakDeviationDegrees, 3);
        expect(e.reminderTriggered).toBe(ref.episodes[i].reminderTriggered);
      });
    });
  }
});
