import { profile } from '../content.js';
import { ArrowOut, GitHub, Mark } from './icons.jsx';

export default function Footer() {
  const links = [
    profile.linkedin && { label: 'LinkedIn', href: profile.linkedin },
    profile.email && { label: 'Email', href: `mailto:${profile.email}` },
    profile.resume && { label: 'Résumé', href: profile.resume },
  ].filter(Boolean);

  return (
    <footer className="footer">
      <div className="wrap">
        <div className="closing">
          <h2>Read the code behind the demo.</h2>
          <p>The app, the Java reference, the sync server, the fixtures, the test plan and this page are all in one repository.</p>
          <a className="btn btn-primary" href={profile.repo}>
            <GitHub />
            <span>Open the repository</span>
          </a>
        </div>
        <div className="footer-row">
          <div className="footer-brand">
            <Mark />
            <p>
              <strong>Align</strong> is designed and built by <a href={profile.github}>{profile.name}</a>.
            </p>
          </div>
          <ul className="footer-links">
            <li><a href={profile.github}>GitHub <ArrowOut /></a></li>
            {links.map((l) => (<li key={l.label}><a href={l.href}>{l.label} <ArrowOut /></a></li>))}
          </ul>
        </div>
        <p className="disclaimer">
          Align is a wellness tool, not a medical device. It measures head tilt, not how far the
          head sits forward, and its limits are not medically validated.
        </p>
      </div>
    </footer>
  );
}
