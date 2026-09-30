import { lazy, Suspense, useEffect } from 'react';
import { useIsAdmin } from './admin.js';
import { BRAND } from './brand.js';
import { EXPLORER, FAUCET_URL, guideUrl } from './chain.js';
import ChainStatus from './components/ChainStatus.jsx';
import Landing from './components/Landing.jsx';
import Onboarding from './components/Onboarding.jsx';
import StopPage from './components/StopPage.jsx';
import TownMap from './components/TownMap.jsx';
import { MODULE_INDEX } from './modules.js';
import { to, useRoute } from './router.js';
import { STOP_BY_SLUG, STOPS } from './town.js';
import { useWallet } from './wallet.js';

/**
 * Each stop's code is loaded only when someone opens that stop. The whole town used to
 * mount on one page, so opening the site meant every panel reading the chain at once.
 */
const STOP_COMPONENTS = {
  'notice-board': lazy(() => import('./components/NoticeBoard.jsx')),
  'town-hall': lazy(() => import('./components/TownHall.jsx')),
  bank: lazy(() => import('./components/Bank.jsx')),
  market: lazy(() => import('./components/Market.jsx')),
  college: lazy(() => import('./components/College.jsx')),
  housing: lazy(() => import('./components/Housing.jsx')),
  council: lazy(() => import('./components/Council.jsx')),
  charity: lazy(() => import('./components/Charity.jsx')),
  insurer: lazy(() => import('./components/Insurer.jsx')),
  exchange: lazy(() => import('./components/Exchange.jsx')),
  'privacy-lab': lazy(() => import('./components/PrivacyLab.jsx')),
};
const Admin = lazy(() => import('./components/Admin.jsx'));

// A stop added to town.js without a component, or the other way round, is a bug worth
// hearing about in development rather than as a blank page in class.
if (import.meta.env.DEV) {
  for (const s of STOPS) if (!STOP_COMPONENTS[s.slug]) console.error(`No component for stop "${s.slug}"`);
}

function StartPage({ wallet }) {
  const ready = wallet.account && wallet.onDidlab && wallet.balance > 0n;
  return (
    <div className="wrap stack">
      <header className="stop-head">
        <p className="eyebrow">Before the first stop</p>
        <h1>Get ready</h1>
        <p className="stop-problem-lead">Every stop needs a wallet on this chain and a little test currency for gas.</p>
      </header>
      <Onboarding wallet={wallet} />
      {ready && (
        <p className="row">
          <a className="btn" href={to('notice-board')}>
            Go to the warm-up
          </a>
          <a className="btn btn-ghost" href={to('map')}>
            See the town map
          </a>
        </p>
      )}
    </div>
  );
}

function NotFound() {
  return (
    <div className="wrap stack">
      <section className="card">
        <h2>There is no such place in town</h2>
        <p className="muted">
          The link may be from an older version of the site. <a href={to('map')}>The town map</a> has every stop.
        </p>
      </section>
    </div>
  );
}

export default function App() {
  const wallet = useWallet();
  const isAdmin = useIsAdmin(wallet.account);
  const [page] = useRoute();
  const stop = STOP_BY_SLUG[page];

  useEffect(() => {
    const where = stop ? stop.name : page === 'map' ? 'Town map' : page === 'start' ? 'Wallet setup' : null;
    document.title = where ? `${where} · ${BRAND.name}` : `${BRAND.name} — ${BRAND.operator}`;
  }, [page, stop]);

  let body;
  if (!page) body = <Landing wallet={wallet} />;
  else if (page === 'start') body = <StartPage wallet={wallet} />;
  else if (page === 'map') body = <TownMap wallet={wallet} />;
  else if (page === 'admin')
    body = (
      <div className="wrap stack">
        <Suspense fallback={<div className="card muted">Loading…</div>}>
          <Admin wallet={wallet} />
        </Suspense>
        {!isAdmin && (
          <p className="muted">
            This page is for the town admin. Every action on it is checked by the contracts themselves, so connect a
            different account and they will refuse — try it.
          </p>
        )}
      </div>
    );
  else if (stop) {
    const Stop = STOP_COMPONENTS[stop.slug];
    body = (
      <StopPage stop={stop} wallet={wallet}>
        <Stop wallet={wallet} />
      </StopPage>
    );
  } else body = <NotFound />;

  return (
    <>
      <header className="topbar">
        <div className="wrap topbar-inner">
          <a className="brand" href={to()}>
            <img src="/favicon.svg" alt="" width="26" height="26" />
            {BRAND.name}
          </a>
          <nav className="topnav" aria-label="Main">
            <a href={to('map')} aria-current={page === 'map' ? 'page' : undefined}>
              Town map
            </a>
            <a href={guideUrl(MODULE_INDEX)} target="_blank" rel="noreferrer">
              Guides
            </a>
            {isAdmin && (
              <a href={to('admin')} aria-current={page === 'admin' ? 'page' : undefined}>
                Admin
              </a>
            )}
          </nav>
          <ChainStatus />
        </div>
      </header>

      <main>{body}</main>

      <footer className="footer">
        <div className="wrap footer-inner">
          <span>
            {BRAND.name} · {BRAND.operator} · MIT licensed
          </span>
          <span className="row">
            {EXPLORER && (
              <a href={EXPLORER} target="_blank" rel="noreferrer">
                Explorer
              </a>
            )}
            {FAUCET_URL && (
              <a href={FAUCET_URL} target="_blank" rel="noreferrer">
                Faucet
              </a>
            )}
            <a href={BRAND.repo} target="_blank" rel="noreferrer">
              Code
            </a>
            {BRAND.contactEmail && <a href={`mailto:${BRAND.contactEmail}`}>Contact</a>}
          </span>
        </div>
      </footer>
    </>
  );
}
