import { decisions, file, profile, stack } from '../content.js';

export default function Decisions() {
  return (
    <section className="section section-tint" id="decisions" aria-labelledby="decisions-title">
      <div className="wrap">
        <div className="section-head">
          <h2 id="decisions-title">Seven decisions that shaped it.</h2>
          <p>
            The project keeps a <a href={file('docs/agents/decisions.md')}>decision log</a> with 21
            entries. These are the ones that explain the most.
          </p>
        </div>
        <ol className="decisions">
          {decisions.map((d) => (
            <li key={d.id}>
              <code className="decision-id">{d.id}</code>
              <div>
                <h3>{d.title}</h3>
                <p>{d.body}</p>
                <a href={file(d.path)}>{d.path.split('/').pop()}</a>
              </div>
            </li>
          ))}
        </ol>

        <div className="stack">
          <h3>Built with</h3>
          <dl>
            {stack.map((s) => (
              <div key={s.area}><dt>{s.area}</dt><dd>{s.items}</dd></div>
            ))}
          </dl>
          <p>The app has no third-party dependencies. <a href={profile.repo}>Read the source</a>.</p>
        </div>
      </div>
    </section>
  );
}
