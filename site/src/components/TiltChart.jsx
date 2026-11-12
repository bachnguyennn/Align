import { useEffect, useRef } from 'react';
import { HISTORY_SECONDS } from '../sim/simulation.js';
import { useSimulation } from '../sim/useSim.js';

const Y_MIN = -35;
const Y_MAX = 45;

/** The last minute of forward and sideways tilt, drawn straight from the simulation's history. */
export default function TiltChart() {
  const sim = useSimulation();
  const ref = useRef(null);

  useEffect(() => {
    const canvas = ref.current;
    const ctx = canvas.getContext('2d');
    const css = getComputedStyle(canvas);
    const color = (name) => css.getPropertyValue(name).trim();
    const c = {
      grid: color('--chart-grid'), text: color('--chart-text'), forward: color('--chart-forward'),
      lateral: color('--chart-lateral'), raw: color('--chart-raw'), limit: color('--chart-limit'),
      held: color('--chart-held'), sustained: color('--chart-sustained'), reminder: color('--chart-reminder'),
    };
    let width = 0, height = 0, frame = 0;

    const resize = () => {
      const box = canvas.getBoundingClientRect();
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      width = box.width;
      height = box.height;
      canvas.width = Math.round(width * dpr);
      canvas.height = Math.round(height * dpr);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    };
    const observer = new ResizeObserver(resize);
    observer.observe(canvas);
    resize();

    const draw = () => {
      frame = requestAnimationFrame(draw);
      if (!width) return;
      const pad = { l: 40, r: 12, t: 12, b: 24 };
      const w = width - pad.l - pad.r;
      const h = height - pad.t - pad.b;
      const now = sim.time;
      const x = (t) => pad.l + ((t - (now - HISTORY_SECONDS)) / HISTORY_SECONDS) * w;
      const y = (deg) => pad.t + ((Y_MAX - deg) / (Y_MAX - Y_MIN)) * h;
      const { config, history } = sim;

      ctx.clearRect(0, 0, width, height);
      ctx.font = '11px "Geist Mono Variable", ui-monospace, monospace';
      ctx.textBaseline = 'middle';

      // Spans where the detector was past a limit.
      let spanStart = null, spanKind = null;
      const flush = (end) => {
        if (spanStart === null) return;
        ctx.fillStyle = spanKind === 'sustainedTilt' ? c.sustained : c.held;
        const x0 = Math.max(pad.l, x(spanStart));
        ctx.fillRect(x0, pad.t, Math.max(0, x(end) - x0), h);
        spanStart = null;
      };
      for (const p of history) {
        const active = p.kind === 'deviating' || p.kind === 'sustainedTilt';
        if (active && (spanStart === null || p.kind !== spanKind)) { flush(p.t); spanStart = p.t; spanKind = p.kind; }
        if (!active) flush(p.t);
      }
      flush(now);

      // Grid and axis labels.
      ctx.lineWidth = 1;
      for (const deg of [-30, -15, 0, 15, 30, 45]) {
        ctx.strokeStyle = c.grid;
        ctx.beginPath(); ctx.moveTo(pad.l, y(deg)); ctx.lineTo(pad.l + w, y(deg)); ctx.stroke();
        ctx.fillStyle = c.text; ctx.textAlign = 'right';
        ctx.fillText(`${deg}°`, pad.l - 8, y(deg));
      }
      ctx.textAlign = 'center';
      for (const ago of [60, 45, 30, 15, 0]) {
        ctx.fillText(ago === 0 ? 'now' : `−${ago} s`, Math.min(pad.l + w - 12, Math.max(pad.l + 14, x(now - ago))), height - 9);
      }

      // Limits: forward and backward thresholds, and the release line (threshold − hysteresis).
      ctx.strokeStyle = c.limit;
      ctx.setLineDash([6, 4]);
      for (const deg of [config.forwardThresholdDegrees, -config.backwardThresholdDegrees]) {
        ctx.beginPath(); ctx.moveTo(pad.l, y(deg)); ctx.lineTo(pad.l + w, y(deg)); ctx.stroke();
      }
      ctx.setLineDash([2, 5]);
      ctx.beginPath();
      ctx.moveTo(pad.l, y(config.forwardThresholdDegrees - config.hysteresisDegrees));
      ctx.lineTo(pad.l + w, y(config.forwardThresholdDegrees - config.hysteresisDegrees));
      ctx.stroke();
      ctx.setLineDash([]);

      ctx.save();
      ctx.beginPath(); ctx.rect(pad.l, pad.t, w, h); ctx.clip();

      // Raw forward samples before smoothing.
      ctx.fillStyle = c.raw;
      for (let i = 0; i < history.length; i += 2) {
        const p = history[i];
        ctx.fillRect(x(p.t) - 0.75, y(p.raw) - 0.75, 1.5, 1.5);
      }

      const line = (key, stroke, lineWidth) => {
        ctx.strokeStyle = stroke; ctx.lineWidth = lineWidth; ctx.lineJoin = 'round';
        ctx.beginPath();
        let pen = false;
        for (const p of history) {
          if (p[key] === null) { pen = false; continue; }
          if (pen) ctx.lineTo(x(p.t), y(p[key])); else ctx.moveTo(x(p.t), y(p[key]));
          pen = true;
        }
        ctx.stroke();
      };
      line('lateral', c.lateral, 1.5);
      line('forward', c.forward, 2.25);

      // Reminder marker.
      const reminder = sim.lastReminder;
      if (reminder && reminder.timestamp > now - HISTORY_SECONDS) {
        const rx = x(reminder.timestamp);
        ctx.strokeStyle = c.reminder; ctx.lineWidth = 1.5;
        ctx.beginPath(); ctx.moveTo(rx, pad.t); ctx.lineTo(rx, pad.t + h); ctx.stroke();
        ctx.fillStyle = c.reminder;
        ctx.beginPath(); ctx.arc(rx, pad.t + 6, 4, 0, Math.PI * 2); ctx.fill();
      }
      ctx.restore();
    };
    frame = requestAnimationFrame(draw);

    return () => { cancelAnimationFrame(frame); observer.disconnect(); };
  }, [sim]);

  return (
    <figure className="chart">
      <canvas ref={ref} role="img" aria-label="Line chart of forward and sideways head tilt over the last 60 seconds, with the reminder limits. Live values are listed in the pipeline below." />
      <figcaption className="legend">
        <span><i className="key key-forward" />Forward tilt, smoothed</span>
        <span><i className="key key-raw" />Raw samples</span>
        <span><i className="key key-lateral" />Sideways tilt</span>
        <span><i className="key key-limit" />Limits</span>
        <span><i className="key key-release" />Release line</span>
        <span><i className="key key-held" />Past a limit</span>
        <span><i className="key key-reminder" />Reminder</span>
      </figcaption>
    </figure>
  );
}
