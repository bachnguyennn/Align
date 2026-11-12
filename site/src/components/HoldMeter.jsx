import { useSim } from '../sim/useSim.js';

const clock = (seconds) => `${Math.floor(seconds / 60)}:${String(Math.floor(seconds % 60)).padStart(2, '0')}`;

/** What the detector is waiting for right now, in one line and one bar. */
export default function HoldMeter({ onDark = false }) {
  const kind = useSim((s) => s.state.kind);
  const direction = useSim((s) => s.state.direction ?? '');
  const held = useSim((s) => Math.floor(s.held));
  const hold = useSim((s) => s.config.sustainedDuration);
  const progress = useSim((s) => Math.round(Math.min(1, s.held / s.config.sustainedDuration) * 100));
  const cooldown = useSim((s) => Math.ceil(s.cooldownRemaining));
  const reminded = useSim((s) => s.state.kind === 'sustainedTilt' && s.lastReminder !== null && s.lastReminder.timestamp >= s.state.since);
  const calibration = useSim((s) => (s.state.kind === 'calibrating' ? Math.round(s.state.progress * 100) : 0));

  let title = 'Within your range';
  let detail = 'Nothing to do. Short glances past the dashed line are fine.';
  let fill = 0;
  let tone = 'ok';

  if (kind === 'calibrating') {
    title = 'Calibrating';
    detail = 'Hold still for 10 seconds so Align can learn your neutral position.';
    fill = calibration;
  } else if (kind === 'needsCalibration' || kind === 'unavailable') {
    title = 'Needs calibration';
    detail = 'The last calibration failed. Keep the head still and calibrate again.';
    tone = 'warn';
  } else if (kind === 'deviating') {
    title = `Tilted ${direction}: ${held} s of ${hold} s`;
    detail = 'Past the limit. Return before the bar fills and nothing happens.';
    fill = progress;
    tone = 'warn';
  } else if (kind === 'sustainedTilt') {
    title = reminded ? 'Reminder sent' : `Held ${direction} for ${held} s`;
    detail = reminded
      ? `One reminder per tilt. The next one is allowed in ${clock(cooldown)}.`
      : `A reminder went out recently. This tilt gets its own in ${clock(cooldown)} if it is still held.`;
    fill = 100;
    tone = 'warn';
  }

  return (
    <div className={`hold ${onDark ? 'on-dark' : ''}`} data-tone={tone}>
      <p className="hold-title" role="status">{title}</p>
      <div className="hold-bar" aria-hidden="true"><span style={{ inlineSize: `${fill}%` }} /></div>
      <p className="hold-detail">{detail}</p>
    </div>
  );
}
