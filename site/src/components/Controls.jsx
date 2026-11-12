import { PRESETS, SCENARIOS } from '../sim/simulation.js';
import { useSim, useSimulation } from '../sim/useSim.js';

function Segmented({ label, value, options, onChange }) {
  return (
    <fieldset className="segmented">
      <legend>{label}</legend>
      <div className="segmented-row">
        {options.map((option) => (
          <label key={option.value} data-checked={option.value === value}>
            <input type="radio" name={label} checked={option.value === value} onChange={() => onChange(option.value)} />
            <span>{option.label}</span>
          </label>
        ))}
      </div>
    </fieldset>
  );
}

export default function Controls() {
  const sim = useSimulation();
  const scenario = useSim((s) => s.scenario);
  const forward = useSim((s) => Math.round(s.target.forward));
  const lateral = useSim((s) => Math.round(s.target.lateral));
  const speed = useSim((s) => s.speed);
  const preset = useSim((s) => s.preset);
  const calibrating = useSim((s) => s.state.kind === 'calibrating');
  const cooling = useSim((s) => s.cooldownRemaining > 0);
  const p = PRESETS[preset];

  return (
    <div className="controls">
      <fieldset className="scenarios">
        <legend>Play a scenario</legend>
        <div className="scenario-row">
          {Object.entries(SCENARIOS).map(([key, s]) => (
            <button key={key} type="button" className="chip" aria-pressed={scenario === key} onClick={() => sim.play(key)}>
              {s.label}
            </button>
          ))}
        </div>
        <p className="hint">{scenario ? SCENARIOS[scenario].note : 'Or set the head tilt yourself below.'}</p>
      </fieldset>

      <div className="sliders">
        <label className="slider">
          <span className="slider-head"><span>Forward tilt</span><output>{forward}°</output></span>
          <input type="range" min={-30} max={40} step={1} value={forward} onChange={(e) => sim.setTarget(Number(e.target.value), sim.getSnapshot().target.lateral)} />
        </label>
        <label className="slider">
          <span className="slider-head"><span>Sideways tilt</span><output>{lateral}°</output></span>
          <input type="range" min={-30} max={30} step={1} value={lateral} onChange={(e) => sim.setTarget(sim.getSnapshot().target.forward, Number(e.target.value))} />
        </label>
        <button type="button" className="btn btn-ghost" onClick={() => sim.setTarget(0, 0)}>Back to neutral</button>
      </div>

      <Segmented
        label="Sensitivity"
        value={preset}
        options={Object.entries(PRESETS).map(([value, o]) => ({ value, label: o.label }))}
        onChange={(v) => sim.setPreset(v)}
      />
      <p className="hint">Past {p.threshold}° for {p.hold} seconds. Looking up gets {p.threshold + 5}°.</p>

      <Segmented
        label="Clock speed"
        value={speed}
        options={[{ value: 1, label: '1×' }, { value: 5, label: '5×' }, { value: 20, label: '20×' }]}
        onChange={(v) => sim.setSpeed(v)}
      />
      <p className="hint">The pipeline works from timestamps, so a faster clock changes nothing but your wait.</p>

      <div className="control-actions">
        <button type="button" className="btn btn-ghost" disabled={calibrating} onClick={() => sim.recalibrate()}>
          {calibrating ? 'Calibrating…' : 'Recalibrate'}
        </button>
        <button type="button" className="btn btn-ghost" disabled={!cooling} onClick={() => sim.resetCooldown()}>
          Reset cooldown
        </button>
      </div>
    </div>
  );
}
