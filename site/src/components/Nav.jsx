import { useRef, useState } from 'react';
import { profile } from '../content.js';
import { GitHub, Mark } from './icons.jsx';

export default function Nav() {
  const [expanded, setExpanded] = useState(false);
  const toggle = useRef(null);

  function handleEscape(event) {
    if (event.key === 'Escape' && expanded) {
      setExpanded(false);
      toggle.current.focus();
    }
  }

  function selectSection(event) {
    if (!expanded || !toggle.current.getClientRects().length ||
        event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;

    const section = document.getElementById(event.currentTarget.hash.slice(1));
    setExpanded(false);
    section?.setAttribute('tabindex', '-1');
    section?.focus({ preventScroll: true });
  }

  return (
    <header className="nav" onKeyDown={handleEscape}>
      <div className="wrap nav-row">
        <a className="brand" href="#top" aria-label="Align, back to top">
          <Mark />
          <span>Align</span>
        </a>
        <button ref={toggle} type="button" className="btn btn-secondary nav-toggle"
          aria-expanded={expanded} aria-controls="section-links" onClick={() => setExpanded(!expanded)}>
          Sections
        </button>
        <nav id="section-links" aria-label="Sections" data-expanded={expanded}>
          <a href="#detector" onClick={selectSection}>Detector</a>
          <a href="#evidence" onClick={selectSection}>Evidence</a>
          <a href="#decisions" onClick={selectSection}>Decisions</a>
          <a href="#hardware" onClick={selectSection}>Hardware run</a>
        </nav>
        <a className="btn btn-quiet nav-source" href={profile.repo}>
          <GitHub />
          <span>Source</span>
        </a>
      </div>
    </header>
  );
}
