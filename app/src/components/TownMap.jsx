import { contracts } from '../chain.js';
import { useStamps } from '../progress.js';
import { to } from '../router.js';
import { STOPS, isOpen, moduleNumbers, moduleRange, moduleTitle, stopOfModule } from '../town.js';

/**
 * Every stop, in order, as cards. `stamps` marks the modules already earned.
 * Used full-size on the map page and compact on the landing page.
 */
export function StopGrid({ stamps = new Set(), compact = false }) {
  return (
    <ol className={`stops ${compact ? 'stops-compact' : ''}`}>
      {STOPS.map((s) => {
        const open = isOpen(s, contracts);
        const earned = s.modules.filter((m) => stamps.has(m)).length;
        const complete = s.modules.length > 0 && earned === s.modules.length;
        return (
          <li key={s.slug} className={`stop ${complete ? 'stop-done' : ''}`}>
            <a className="stop-link" href={to(s.slug)}>
              <div className="stop-top">
                <span className="stop-num" aria-hidden="true">
                  {complete ? '✓' : moduleNumbers(s)}
                </span>
                <div>
                  <h3>{s.name}</h3>
                  <p className="muted small">
                    <span className="nowrap">{moduleRange(s)}</span>
                    {!open && <span className="badge stop-badge">Not open here</span>}
                  </p>
                </div>
              </div>
              <p className="stop-problem">{s.problem}</p>
              {!compact && s.modules.length > 0 && (
                <ul className="stop-modules">
                  {s.modules.map((m) => (
                    <li key={m} className={stamps.has(m) ? 'earned' : ''}>
                      <span className="mono">{m}</span> {moduleTitle(m)}
                      {stamps.has(m) && <span className="sr-only"> (stamped)</span>}
                    </li>
                  ))}
                </ul>
              )}
            </a>
          </li>
        );
      })}
    </ol>
  );
}

/** The map page: progress, a Continue button, and the whole town. */
export default function TownMap({ wallet }) {
  const { stamps, hasPassport, nextModule, done } = useStamps(wallet.account);
  const nextStop = nextModule ? stopOfModule(nextModule) : null;

  return (
    <div className="wrap stack">
      <section className="map-head">
        <p className="eyebrow">The town map</p>
        <h1>Walk the modules in order, 1 to 16.</h1>
        <p className="muted">
          Each stop solves one trust problem. Finish a module and its contract stamps your passport, so the map below
          shows exactly what anyone could check on the explorer.
        </p>

        {!wallet.account ? (
          <p className="row">
            <a className="btn" href={to('start')}>
              Set up your wallet
            </a>
            <span className="muted small">Progress appears here once you connect.</span>
          </p>
        ) : !hasPassport ? (
          <p className="row">
            <a className="btn" href={to('notice-board')}>
              Start with the warm-up
            </a>
            <span className="muted small">No passport yet: you earn one at the Town Hall.</span>
          </p>
        ) : (
          <div className="progress">
            <div className="progress-bar" role="progressbar" aria-valuemin={0} aria-valuemax={16} aria-valuenow={done}>
              <span style={{ width: `${(done / 16) * 100}%` }} />
            </div>
            <p className="row">
              <strong>{done} of 16 modules stamped.</strong>
              {nextStop ? (
                <a className="btn" href={to(nextStop.slug)}>
                  Continue: module {nextModule} at the {nextStop.name}
                </a>
              ) : (
                <span>Every module is stamped. The whole town is yours.</span>
              )}
            </p>
          </div>
        )}
      </section>

      <StopGrid stamps={stamps} />
    </div>
  );
}
