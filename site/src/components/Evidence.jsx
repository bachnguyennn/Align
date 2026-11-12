import { file, flicker, glances, latency, suites } from '../content.js';

export default function Evidence() {
  const maxFlicker = Math.max(...flicker.map((f) => f.value));
  return (
    <section className="section" id="evidence" aria-labelledby="evidence-title">
      <div className="wrap">
        <div className="section-head">
          <h2 id="evidence-title">What has been verified, and how.</h2>
          <p>
            Every number here comes from a file in the repository. The algorithm figures are from
            synthetic motion made by a seeded generator. They are not measurements of people.
          </p>
        </div>

        <table className="suite-table">
          <caption>Automated tests, all passing</caption>
          <thead>
            <tr><th scope="col">Tests</th><th scope="col">Suite</th><th scope="col">What it covers</th><th scope="col">Run with</th></tr>
          </thead>
          <tbody>
            {suites.map((s) => (
              <tr key={s.name}>
                <td className="num">{s.count}</td>
                <th scope="row"><a href={`${file(s.path).replace('/blob/', '/tree/')}`}>{s.name}</a></th>
                <td>{s.covers}</td>
                <td><code>{s.command}</code></td>
              </tr>
            ))}
          </tbody>
        </table>

        <div className="findings-grid">
          <figure className="figure">
            <h3>A glance shorter than 30 seconds never triggers a reminder.</h3>
            <div className="bars" role="img" aria-label="Runs out of 20 that produced a reminder, by glance length: 5, 10, 20 and 29 seconds gave 0; 31, 32 and 40 seconds gave 20.">
              {glances.map((g) => (
                <div className="bar-col" key={g.seconds}>
                  <span className="bar-value">{g.reminded}</span>
                  <span className="bar-track"><span className="bar-fill" style={{ blockSize: `${Math.max(2, (g.reminded / 20) * 100)}%` }} data-on={g.reminded > 0} /></span>
                  <span className="bar-label">{g.seconds} s</span>
                </div>
              ))}
            </div>
            <figcaption>Runs out of 20 with a reminder, by length of a 30° glance. Hold time 30 s.</figcaption>
          </figure>

          <figure className="figure">
            <h3>Smoothing and hysteresis stop flicker at the limit.</h3>
            <ul className="hbars">
              {flicker.map((f) => (
                <li key={f.label} data-shipped={Boolean(f.shipped)}>
                  <span className="hbar-label">{f.label}</span>
                  <span className="hbar-track"><span className="hbar-fill" style={{ inlineSize: `${Math.max(1.5, (f.value / maxFlicker) * 100)}%` }} /></span>
                  <span className="hbar-value">{f.value.toFixed(1)}</span>
                </li>
              ))}
            </ul>
            <figcaption>Times the state flipped to “deviating” in a 60 s hold at exactly 15°, the limit. Mean of 20 runs.</figcaption>
          </figure>
        </div>

        <table className="latency-table">
          <caption>The reminder arrives about half a second after the 30 second mark</caption>
          <thead>
            <tr><th scope="col">Scenario</th><th scope="col">Exactly one reminder</th><th scope="col">Mean delay past 30 s</th></tr>
          </thead>
          <tbody>
            {latency.map((l) => (
              <tr key={l.scenario}><th scope="row">{l.scenario}</th><td className="num">{l.once}</td><td className="num">{l.delay}</td></tr>
            ))}
          </tbody>
        </table>
        <p className="source">
          Source: <a href={file('analytics/align-tools/results/evaluation.md')}>evaluation.md</a> for the
          figures and the <a href={file('docs/agents/integration-log.md')}>integration log</a> for the test counts.
        </p>
      </div>
    </section>
  );
}
