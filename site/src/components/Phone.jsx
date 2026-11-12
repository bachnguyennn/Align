import { useEffect, useRef, useState } from 'react';
import { useSim, useSimulation } from '../sim/useSim.js';
import { Alert, Bell, Check, Scope } from './icons.jsx';

const SIZE = 300;
const R = SIZE / 2;
const MARKER = 36;
const TRAVEL = R - MARKER / 2;

const signed = (v) => `${v >= 0 ? '+' : '−'}${Math.abs(v).toFixed(1)}°`;

// Same copy as ReminderCopy in ios/AlignApp/Notifications/ReminderNotifier.swift.
const reminderBody = {
  forward: 'Time for a posture reset. Lift your head and relax your shoulders.',
  backward: 'Time for a posture reset. Bring your head back to level and relax your shoulders.',
  left: 'Time for a posture reset. Bring your head back to center and relax your shoulders.',
  right: 'Time for a posture reset. Bring your head back to center and relax your shoulders.',
};

/** The dashed reminder outline of HeadOrientationIndicator: forward below, backward above. */
function outlinePath(forward, backward, lateral, range) {
  const points = [];
  for (let i = 0; i <= 120; i++) {
    const theta = (i / 120) * 2 * Math.PI;
    const vertical = (Math.sin(theta) >= 0 ? forward : backward) / range;
    points.push(`${(R + (lateral / range) * R * Math.cos(theta)).toFixed(1)},${(R + vertical * R * Math.sin(theta)).toFixed(1)}`);
  }
  return `M${points.join('L')}Z`;
}

function Indicator() {
  const sim = useSimulation();
  const forward = useSim((s) => (s.tilt ? Math.round(s.tilt.forwardDegrees * 5) / 5 : null));
  const lateral = useSim((s) => (s.tilt ? Math.round(s.tilt.lateralDegrees * 5) / 5 : null));
  const outside = useSim((s) => s.outside);
  const fwdLimit = useSim((s) => s.config.forwardThresholdDegrees);
  const backLimit = useSim((s) => s.config.backwardThresholdDegrees);
  const latLimit = useSim((s) => s.config.lateralThresholdDegrees);
  const range = Math.max(fwdLimit, backLimit, latLimit, 5) * 2;
  const ref = useRef(null);
  const dragging = useRef(false);

  let x = 0, y = 0;
  if (forward !== null) {
    x = lateral / range;
    y = forward / range;
    const len = Math.hypot(x, y);
    if (len > 1) { x /= len; y /= len; }
  }

  const aim = (event) => {
    const box = ref.current.getBoundingClientRect();
    const px = ((event.clientX - box.left) / box.width) * SIZE - R;
    const py = ((event.clientY - box.top) / box.height) * SIZE - R;
    sim.setTarget((py / TRAVEL) * range, (px / TRAVEL) * range);
  };

  const onKey = (event) => {
    const step = event.shiftKey ? 5 : 1;
    const { forward: f, lateral: l } = sim.getSnapshot().target;
    const moves = { ArrowDown: [step, 0], ArrowUp: [-step, 0], ArrowRight: [0, step], ArrowLeft: [0, -step] };
    if (event.key === 'Home') { sim.setTarget(0, 0); event.preventDefault(); return; }
    const move = moves[event.key];
    if (!move) return;
    event.preventDefault();
    sim.setTarget(f + move[0], l + move[1]);
  };

  return (
    <svg
      ref={ref}
      className="indicator"
      viewBox={`0 0 ${SIZE} ${SIZE}`}
      role="slider"
      tabIndex={0}
      aria-label="Head tilt. Arrow keys tilt the head, Home returns to neutral."
      aria-valuetext={forward === null ? 'No tilt data' : `${signed(forward)} forward, ${signed(lateral)} sideways, ${outside ? 'outside' : 'within'} your range`}
      aria-valuenow={forward ?? 0}
      aria-valuemin={-30}
      aria-valuemax={40}
      onKeyDown={onKey}
      onPointerDown={(e) => { dragging.current = true; e.currentTarget.setPointerCapture(e.pointerId); aim(e); }}
      onPointerMove={(e) => { if (dragging.current) aim(e); }}
      onPointerUp={() => { dragging.current = false; }}
      onPointerCancel={() => { dragging.current = false; }}
    >
      <circle cx={R} cy={R} r={R - 0.5} className="ind-face" />
      <path d={`M0 ${R}H${SIZE}M${R} 0V${SIZE}`} className="ind-cross" />
      <path d={outlinePath(fwdLimit, backLimit, latLimit, range)} className="ind-limit" />
      <g className="ind-labels" aria-hidden="true">
        <text x={R} y={18}>Up</text>
        <text x={R} y={SIZE - 9}>Down</text>
        <text x={13} y={R + 4}>L</text>
        <text x={SIZE - 13} y={R + 4}>R</text>
      </g>
      {forward !== null && (
        <g transform={`translate(${R + x * TRAVEL} ${R + y * TRAVEL})`} className="ind-marker" data-outside={outside}>
          <circle r={MARKER / 2} className="ind-dot" />
          {outside
            ? <path d="M0 -8V2M0 7.5v.5" className="ind-bang" />
            : <circle r={MARKER / 2 - 7.5} className="ind-ring" />}
        </g>
      )}
    </svg>
  );
}

function Banner() {
  const stamp = useSim((s) => s.lastReminder?.timestamp ?? null);
  const direction = useSim((s) => s.lastReminder?.direction ?? 'forward');
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    if (stamp === null) return undefined;
    setVisible(true);
    const timer = setTimeout(() => setVisible(false), 6000);
    return () => clearTimeout(timer);
  }, [stamp]);

  return (
    <div className="banner" data-visible={visible} role="status" aria-live="polite">
      {visible && (
        <>
          <span className="banner-icon"><Bell /></span>
          <span className="banner-text">
            <strong>Posture reset</strong>
            <span>{reminderBody[direction]}</span>
          </span>
        </>
      )}
    </div>
  );
}

/** A reconstruction of the app's Live view (LiveMonitoringView.swift), driven by the simulation. */
export default function Phone() {
  const kind = useSim((s) => s.state.kind);
  const outside = useSim((s) => s.outside);
  const forward = useSim((s) => (s.tilt ? s.tilt.forwardDegrees.toFixed(1) : null));
  const lateral = useSim((s) => (s.tilt ? s.tilt.lateralDegrees.toFixed(1) : null));
  const fwdLimit = useSim((s) => s.config.forwardThresholdDegrees);
  const latLimit = useSim((s) => s.config.lateralThresholdDegrees);
  const hold = useSim((s) => s.config.sustainedDuration);

  const status = kind === 'calibrating' ? ['Calibrating', <Scope key="i" />]
    : kind === 'needsCalibration' || kind === 'unavailable' ? ['Calibrate to start', <Scope key="i" />]
    : outside ? ['Outside your range', <Alert key="i" />]
    : ['Within your range', <Check key="i" />];

  return (
    <div className="phone">
      <div className="phone-screen">
        <div className="island" aria-hidden="true" />
        <Banner />
        <p className="screen-title">Live view</p>
        <Indicator />
        <p className="screen-status" data-outside={outside}>
          <span className="status-icon">{status[1]}</span>
          {status[0]}
        </p>
        <div className="readouts">
          <div className="readout">
            <span className="readout-name">Forward</span>
            <span className="readout-value">{forward === null ? '—' : signed(Number(forward))}</span>
            <span className="readout-limit">limit {fwdLimit}°</span>
          </div>
          <div className="readout">
            <span className="readout-name">Sideways</span>
            <span className="readout-value">{lateral === null ? '—' : signed(Number(lateral))}</span>
            <span className="readout-limit">limit {latLimit}°</span>
          </div>
        </div>
        <p className="screen-foot">
          The dashed outline shows your reminder angles. Align only reminds you when a tilt lasts {hold} seconds.
        </p>
      </div>
    </div>
  );
}
