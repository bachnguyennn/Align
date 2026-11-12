import { describe, expect, it } from 'vitest';
import { Simulation } from './simulation.js';

function run(sim, seconds) {
  const reminders = [];
  const steps = Math.round(seconds * 25);
  for (let i = 0; i < steps; i++) {
    const update = sim.step();
    if (update.reminder) reminders.push(update.reminder);
  }
  return reminders;
}

describe('simulated motion through the real pipeline', () => {
  it('starts calibrated and neutral', () => {
    const sim = new Simulation();
    run(sim, 5);
    expect(sim.monitor.baseline).not.toBeNull();
    expect(sim.monitor.state.kind).toBe('neutral');
  });

  it('recovers the tilt it was given despite the mounting offset', () => {
    const sim = new Simulation();
    sim.setTarget(20, 0);
    run(sim, 5);
    expect(sim.monitor.lastTilt.forwardDegrees).toBeGreaterThan(18.5);
    expect(sim.monitor.lastTilt.forwardDegrees).toBeLessThan(21.5);
    expect(Math.abs(sim.monitor.lastTilt.lateralDegrees)).toBeLessThan(1.5);
    sim.setTarget(0, -20);
    run(sim, 5);
    expect(sim.monitor.lastTilt.lateralDegrees).toBeLessThan(-18.5);
  });

  it('reminds once for a held slouch, about 30 s after crossing', () => {
    const sim = new Simulation();
    sim.play('slouch');
    const reminders = run(sim, 70);
    expect(reminders).toHaveLength(1);
    expect(reminders[0].direction).toBe('forward');
    expect(reminders[0].sustainedSeconds).toBeGreaterThan(29.99);
    expect(reminders[0].sustainedSeconds).toBeLessThan(30.1);
  });

  it('does not remind for quick glances', () => {
    const sim = new Simulation();
    sim.play('glances');
    expect(run(sim, 50)).toHaveLength(0);
  });

  it('fails calibration when the head moves', () => {
    const sim = new Simulation();
    sim.recalibrate();
    run(sim, 3);
    sim.setTarget(15, 0);
    run(sim, 9);
    expect(sim.events.some((e) => e.text.includes('moved too much'))).toBe(true);
  });
});
