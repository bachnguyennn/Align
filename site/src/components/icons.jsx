// One small authored icon set: 1.75 stroke, round caps, 20 px grid.
const base = { width: 20, height: 20, viewBox: '0 0 20 20', fill: 'none', stroke: 'currentColor', strokeWidth: 1.75, strokeLinecap: 'round', strokeLinejoin: 'round', 'aria-hidden': true };

export const ArrowDown = () => (<svg {...base}><path d="M10 4v12M5 11l5 5 5-5" /></svg>);
export const ArrowOut = () => (<svg {...base}><path d="M7 13 13 7M8 7h5v5" /></svg>);
export const Check = () => (<svg {...base}><path d="m4.5 10.5 3.5 3.5 7.5-8" /></svg>);
export const Alert = () => (<svg {...base}><circle cx="10" cy="10" r="7.5" /><path d="M10 6.2v4.6M10 13.6v.2" /></svg>);
export const Bell = () => (<svg {...base}><path d="M5 13.5V9a5 5 0 0 1 10 0v4.5l1.5 1.5h-13zM8.5 17h3" /></svg>);
export const Scope = () => (<svg {...base}><circle cx="10" cy="10" r="5.5" /><path d="M10 2v3M10 15v3M2 10h3M15 10h3" /></svg>);

export const GitHub = () => (
  <svg width="20" height="20" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
    <path d="M10 1.5a8.5 8.5 0 0 0-2.69 16.57c.43.08.58-.18.58-.41v-1.5c-2.36.51-2.86-1-2.86-1-.39-.98-.95-1.24-.95-1.24-.77-.53.06-.52.06-.52.85.06 1.3.88 1.3.88.76 1.3 1.99.92 2.47.7.08-.55.3-.92.54-1.13-1.89-.21-3.87-.94-3.87-4.2 0-.93.33-1.69.88-2.28-.09-.22-.38-1.08.08-2.25 0 0 .72-.23 2.34.87a8.1 8.1 0 0 1 4.26 0c1.62-1.1 2.33-.87 2.33-.87.47 1.17.18 2.03.09 2.25.55.59.88 1.35.88 2.28 0 3.27-1.99 3.99-3.88 4.2.3.26.57.78.57 1.57v2.33c0 .23.15.5.58.41A8.5 8.5 0 0 0 10 1.5Z" />
  </svg>
);

export const Mark = () => (
  <svg width="26" height="26" viewBox="0 0 32 32" aria-hidden="true">
    <rect width="32" height="32" rx="8" fill="var(--accent)" />
    <circle cx="16" cy="16" r="9" fill="none" stroke="#fff" strokeWidth="2" strokeDasharray="3 3" />
    <circle cx="16" cy="19" r="4" fill="#fff" />
  </svg>
);
