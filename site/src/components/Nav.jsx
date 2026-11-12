import { profile } from '../content.js';
import { GitHub, Mark } from './icons.jsx';

export default function Nav() {
  return (
    <header className="nav">
      <div className="wrap nav-row">
        <a className="brand" href="#top" aria-label="Align, back to top">
          <Mark />
          <span>Align</span>
        </a>
        <nav aria-label="Sections">
          <a href="#detector">Detector</a>
          <a href="#evidence">Evidence</a>
          <a href="#decisions">Decisions</a>
          <a href="#hardware">Hardware run</a>
        </nav>
        <a className="btn btn-quiet nav-source" href={profile.repo}>
          <GitHub />
          <span>Source</span>
        </a>
      </div>
    </header>
  );
}
