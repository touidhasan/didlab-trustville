import { Suspense } from 'react';
import { to } from '../router.js';
import { moduleRange, neighbours, STOPS } from '../town.js';

function Neighbour({ stop, dir }) {
  if (!stop) return <span />;
  return (
    <a className={`neighbour neighbour-${dir}`} href={to(stop.slug)}>
      <span className="muted small">{dir === 'prev' ? '← Previous' : 'Next →'}</span>
      <strong>{stop.name}</strong>
      <span className="muted small">{moduleRange(stop)}</span>
    </a>
  );
}

/**
 * The frame every stop sits in: where you are in the walk, the trust problem, a nudge if
 * the wallet is not ready, the stop itself, and the way on.
 */
export default function StopPage({ stop, wallet, children }) {
  const { prev, next } = neighbours(stop.slug);
  const place = STOPS.findIndex((s) => s.slug === stop.slug);
  const ready = wallet.account && wallet.onDidlab;

  return (
    <div className="wrap stack">
      <nav className="crumbs small" aria-label="Where you are">
        <a href={to('map')}>Town map</a>
        <span aria-hidden="true"> › </span>
        <span>
          Stop {place} of {STOPS.length - 1}
          {stop.warmUp ? ' (warm-up)' : ''}
        </span>
      </nav>

      <header className="stop-head">
        <p className="eyebrow">{moduleRange(stop)}</p>
        <h1>{stop.name}</h1>
        <p className="stop-problem-lead">{stop.problem}</p>
      </header>

      {!ready && (
        <p className="setup-nudge">
          You can read this stop now. To use it, <a href={to('start')}>set up your wallet</a> first — about five
          minutes, and it never touches real money.
        </p>
      )}

      <div className="stop-body">
        <Suspense fallback={<div className="card muted">Loading the {stop.name}…</div>}>{children}</Suspense>
      </div>

      <nav className="neighbours" aria-label="Previous and next stop">
        <Neighbour stop={prev} dir="prev" />
        <Neighbour stop={next} dir="next" />
      </nav>
    </div>
  );
}
