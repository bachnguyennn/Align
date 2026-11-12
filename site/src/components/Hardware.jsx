import { axisCheck, findings, hardwareReport } from '../content.js';

export default function Hardware() {
  return (
    <section className="section" id="hardware" aria-labelledby="hardware-title">
      <div className="wrap">
        <div className="section-head">
          <h2 id="hardware-title">The first run on real hardware.</h2>
          <p>
            On 31 October 2026 the app ran on an iPhone 17 with AirPods for the first time. The
            axis signs matched what the code assumed. Three things did not go to plan. Calibration
            has been reworked since, and the new version has not run on a device yet, so all three
            stay open.
          </p>
        </div>
        <div className="hardware-grid">
          <div>
            <table className="axis-table">
              <caption>Axis check: degrees read off the Diagnostics screen</caption>
              <thead>
                <tr><th scope="col">Move</th><th scope="col">Expected</th><th scope="col">Forward</th><th scope="col">Sideways</th></tr>
              </thead>
              <tbody>
                {axisCheck.map((row) => (
                  <tr key={row.move}>
                    <th scope="row">{row.move}</th><td>{row.expected}</td><td className="num">{row.forward}</td><td className="num">{row.lateral}</td>
                  </tr>
                ))}
              </tbody>
            </table>
            <p className="source">
              Not yet measured: sample rate, battery use, disconnect handling, behaviour with the
              screen locked. <a href={hardwareReport}>Full report</a>.
            </p>
          </div>
          <ol className="findings">
            {findings.map((f) => (
              <li key={f.title}>
                <h3>{f.title} <span className="tag">Open</span></h3>
                <p>{f.body}</p>
              </li>
            ))}
          </ol>
        </div>
      </div>
    </section>
  );
}
