import { useSim } from '../sim/useSim.js';
import Controls from './Controls.jsx';
import HoldMeter from './HoldMeter.jsx';
import Pipeline from './Pipeline.jsx';
import TiltChart from './TiltChart.jsx';

function EventLog() {
  const events = useSim((s) => s.events);
  return (
    <div className="log">
      <h3>Events</h3>
      {events.length === 0
        ? <p className="log-empty">Nothing yet. Hold a tilt past the limit to see a reminder here.</p>
        : (
          <ul>
            {events.map((event) => (
              <li key={event.id} data-type={event.type}>
                <time>{event.t.toFixed(1)} s</time>
                <span>{event.text}</span>
              </li>
            ))}
          </ul>
        )}
    </div>
  );
}

export default function Detector() {
  return (
    <section className="band-dark" id="detector" aria-labelledby="detector-title">
      <div className="wrap">
        <div className="section-head">
          <h2 id="detector-title">Run the detector yourself.</h2>
          <p>
            This page runs a JavaScript port of the app’s detection pipeline. It passes the same
            14 motion fixtures as the Swift and Java versions. The head motion is
            simulated; the logic is not.
          </p>
        </div>
        <div className="lab">
          <Controls />
          <div className="lab-main">
            <HoldMeter onDark />
            <TiltChart />
            <EventLog />
          </div>
        </div>
        <div className="section-head section-head-inner">
          <h2>Five steps from earbud to reminder.</h2>
          <p>Each step is one small type in the Swift package. The values below are live.</p>
        </div>
        <Pipeline />
      </div>
    </section>
  );
}
