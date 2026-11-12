import { profile } from '../content.js';
import { ArrowDown, GitHub } from './icons.jsx';
import Phone from './Phone.jsx';
import HoldMeter from './HoldMeter.jsx';

export default function Hero() {
  return (
    <section className="hero" id="top">
      <div className="wrap hero-grid">
        <div className="hero-copy">
          <h1>A posture reminder from the AirPods you already wear.</h1>
          <p className="lede">
            Align is an iPhone app that reads head motion from your AirPods. When your head stays
            tilted for 30 seconds, it reminds you once, then stays quiet.
          </p>
          <div className="actions">
            <a className="btn btn-primary" href="#detector">
              <span>Try the detector</span>
              <ArrowDown />
            </a>
            <a className="btn btn-secondary" href={profile.repo}>
              <GitHub />
              <span>View source</span>
            </a>
          </div>
          <p className="status-line">
            Phase 1 build, passing in CI. First run on an iPhone 17 on 31 October 2026. Not yet on
            the App Store.
          </p>
        </div>
        <div className="hero-device">
          <Phone />
          <div className="device-side">
            <HoldMeter />
            <p className="device-note">
              The head motion here is simulated. The detection logic is the app’s own, ported to
              JavaScript. Drag the dot to tilt the head.
            </p>
          </div>
        </div>
      </div>
    </section>
  );
}
