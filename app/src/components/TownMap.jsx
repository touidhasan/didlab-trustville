import { stops } from '../stops.js';

export default function TownMap() {
  return (
    <section id="map">
      <div className="section-head">
        <h2>The town</h2>
        <p className="muted">Nine stops. Each one solves a real trust problem with a different blockchain feature.</p>
      </div>
      <div className="stops">
        {stops.map((s) => (
          <article key={s.name} className="stop">
            <div className="stop-top">
              <h3>{s.name}</h3>
              <span className={`badge ${s.phase === 'now' ? 'badge-open' : ''}`}>
                {s.phase === 'now' ? 'Open now' : `Opens in ${s.phase}`}
              </span>
            </div>
            <p className="stop-problem">{s.problem}</p>
            <ul>
              {s.modules.map((m) => (
                <li key={m}>{m}</li>
              ))}
            </ul>
          </article>
        ))}
      </div>
    </section>
  );
}
