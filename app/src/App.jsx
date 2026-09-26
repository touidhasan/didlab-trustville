import Bank from './components/Bank.jsx';
import ChainStatus from './components/ChainStatus.jsx';
import Charity from './components/Charity.jsx';
import College from './components/College.jsx';
import Council from './components/Council.jsx';
import Exchange from './components/Exchange.jsx';
import Housing from './components/Housing.jsx';
import Insurer from './components/Insurer.jsx';
import Market from './components/Market.jsx';
import NoticeBoard from './components/NoticeBoard.jsx';
import Onboarding from './components/Onboarding.jsx';
import TownHall from './components/TownHall.jsx';
import TownMap from './components/TownMap.jsx';
import { EXPLORER, FAUCET_URL, guideUrl } from './chain.js';
import { MODULES, MODULE_INDEX } from './modules.js';
import { useWallet } from './wallet.js';

const REPO = 'https://github.com/touidhasan/didlab-trustville';

export default function App() {
  const wallet = useWallet();

  return (
    <>
      <header className="topbar">
        <div className="wrap topbar-inner">
          <a className="brand" href="#">
            <img src="/favicon.svg" alt="" width="26" height="26" />
            Trustville
          </a>
          <ChainStatus />
        </div>
      </header>

      <main>
        <section className="hero">
          <div className="wrap">
            <p className="eyebrow">DIDLab blockchain showcase</p>
            <h1>A small town where trust is built into the infrastructure.</h1>
            <p className="lead">
              Trustville has a market, a college, a housing office and a town council. Each one has a trust problem
              people usually solve with paperwork or middlemen. Walk through the town, solve each problem with a
              blockchain feature, and check every step yourself on the explorer.
            </p>
            <div className="row">
              <a className="btn" href="#start">
                Get started
              </a>
              <a className="btn btn-ghost-light" href={guideUrl(MODULE_INDEX)} target="_blank" rel="noreferrer">
                Read the guides
              </a>
              <a className="btn btn-ghost-light" href={REPO} target="_blank" rel="noreferrer">
                Read the code
              </a>
            </div>
          </div>
        </section>

        <div className="wrap stack">
          <section className="card learn" id="learn">
            <div className="card-head">
              <h2>How to learn from this town</h2>
              <p className="muted">
                Pressing the buttons takes an afternoon. Understanding why each contract is shaped the way it
                is takes rather longer, and that is the part worth having — so every module has a written
                guide, and every stop below links to its own.
              </p>
            </div>

            <div className="board">
              <div>
                <div className="module">
                  <h3>Each guide answers the same questions</h3>
                  <p className="muted small">
                    What the trust problem is. The one idea the module turns on. The two or three lines of
                    Solidity that carry the design. What to do here, in order, and which events to look for on
                    the explorer. <strong>When a plain database would have been the better choice.</strong> And
                    what the contract did <strong>not</strong> fix — every module has a section on that,
                    because knowing exactly where the guarantee stops is most of the skill.
                  </p>
                </div>

                <div className="module">
                  <h3>Suggested order</h3>
                  <p className="muted small">
                    Read the guide, walk the stop, then read the "what this does not fix" section again with
                    the transaction in front of you. Modules build on each other: several of them take an
                    earlier module's stated limitation as their starting problem.
                  </p>
                </div>
              </div>

              <div>
                <div className="module">
                  <h3>All fifteen guides</h3>
                  <p className="guide-links">
                    {Object.entries(MODULES).map(([id, m]) => (
                      <a key={id} href={guideUrl(m.slug)} target="_blank" rel="noreferrer">
                        {id} · {m.title}
                      </a>
                    ))}
                  </p>
                  <p className="muted small">
                    Module 15 ships a <strong>deliberate vulnerability</strong> and a test that exploits it
                    successfully. Read its guide before its code.
                  </p>
                </div>
              </div>
            </div>
          </section>

          <Onboarding wallet={wallet} />
          <TownHall wallet={wallet} />
          <Bank wallet={wallet} />
          <Exchange wallet={wallet} />
          <Market wallet={wallet} />
          <College wallet={wallet} />
          <Housing wallet={wallet} />
          <Council wallet={wallet} />
          <Charity wallet={wallet} />
          <Insurer wallet={wallet} />
          <NoticeBoard wallet={wallet} />
          <TownMap />

          <section className="card honest">
            <h2>Good to know: this is a permissioned chain</h2>
            <p>
              DIDLab runs Hyperledger Besu with QBFT consensus and four known validators. Blocks are final right away
              and gas is free (TRUST comes from a faucet). Public chains like Ethereum differ: anyone can validate,
              finality takes minutes, and gas costs real money. The contracts here would run on either, but the
              trust model is not the same.
            </p>
          </section>
        </div>
      </main>

      <footer className="footer">
        <div className="wrap footer-inner">
          <span>Trustville · DIDLab · MIT licensed</span>
          <span className="row">
            <a href={EXPLORER} target="_blank" rel="noreferrer">
              Explorer
            </a>
            <a href={FAUCET_URL} target="_blank" rel="noreferrer">
              Faucet
            </a>
            <a href={REPO} target="_blank" rel="noreferrer">
              GitHub
            </a>
          </span>
        </div>
      </footer>
    </>
  );
}
