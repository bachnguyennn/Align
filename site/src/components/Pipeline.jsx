import { file } from '../content.js';
import { useSim } from '../sim/useSim.js';

const v3 = (v) => (v ? `(${[v.x, v.y, v.z].map((n) => (n >= 0 ? '+' : '−') + Math.abs(n).toFixed(3)).join(', ')})` : 'waiting for a sample');
const deg = (n) => `${n >= 0 ? '+' : '−'}${Math.abs(n).toFixed(1)}°`;

/** The five stages of PostureMonitor.process, each with its live value and its source file. */
export default function Pipeline() {
  const gravity = useSim((s) => v3(s.gravity));
  const smoothed = useSim((s) => v3(s.smoothed));
  const tilt = useSim((s) => (s.tilt ? `forward ${deg(s.tilt.forwardDegrees)}, sideways ${deg(s.tilt.lateralDegrees)}` : 'no baseline yet'));
  const state = useSim((s) => {
    const k = s.state.kind;
    if (k === 'deviating') return `deviating ${s.state.direction}, ${s.held.toFixed(0)}\u00a0s`;
    if (k === 'sustainedTilt') return `sustained ${s.state.direction}, ${s.held.toFixed(0)}\u00a0s`;
    if (k === 'calibrating') return `calibrating, ${Math.round(s.state.progress * 100)}%`;
    return k === 'needsCalibration' ? 'needs calibration' : k;
  });
  const reminder = useSim((s) => (s.lastReminder
    ? `sent at ${s.lastReminder.timestamp.toFixed(1)} s, cooldown ${Math.ceil(s.cooldownRemaining)}\u00a0s left`
    : 'none sent yet'));
  const tau = useSim((s) => s.config.smoothingTimeConstant);
  const hysteresis = useSim((s) => s.config.hysteresisDegrees);
  const cooldown = useSim((s) => s.config.reminderCooldown);

  const steps = [
    { name: 'Sense', what: 'AirPods report which way gravity points inside the head’s frame, about 25 times a second.', value: gravity, path: 'ios/AlignKit/Sources/Sensors/RealAirPodsSensorProvider.swift', fileName: 'RealAirPodsSensorProvider.swift' },
    { name: 'Smooth', what: `An exponential filter with a ${tau} s time constant removes jitter. It is time-based, so it behaves the same at any sample rate.`, value: smoothed, path: 'ios/AlignKit/Sources/PostureDetection/MotionFilter.swift', fileName: 'MotionFilter.swift' },
    { name: 'Measure', what: 'The rotation from calibrated gravity to current gravity is split into forward and sideways tilt.', value: tilt, path: 'ios/AlignKit/Sources/PostureDetection/TiltEstimator.swift', fileName: 'TiltEstimator.swift' },
    { name: 'Decide', what: `Past a limit the state becomes deviating, then sustained. It releases ${hysteresis}° below the limit, so it cannot flicker.`, value: state, path: 'ios/AlignKit/Sources/PostureDetection/PostureDetector.swift', fileName: 'PostureDetector.swift' },
    { name: 'Remind', what: `One reminder per sustained tilt, and at most one every ${cooldown / 60} minutes.`, value: reminder, path: 'ios/AlignKit/Sources/PostureDetection/ReminderDecisionEngine.swift', fileName: 'ReminderDecisionEngine.swift' },
  ];

  return (
    <ol className="pipeline">
      {steps.map((step) => (
        <li key={step.name}>
          <h3>{step.name}</h3>
          <p>{step.what}</p>
          <code className="live">{step.value}</code>
          <a href={file(step.path)}>{step.fileName}</a>
        </li>
      ))}
    </ol>
  );
}
