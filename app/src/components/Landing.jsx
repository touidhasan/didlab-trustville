import { BRAND } from '../brand.js';
import { CHAIN_ID, didlab, EXPLORER, guideUrl } from '../chain.js';
import { MODULE_INDEX } from '../modules.js';
import { useStamps } from '../progress.js';
import { to } from '../router.js';
import { StopGrid } from './TownMap.jsx';

/**
 * The front door. It answers, in order, what a first-time visitor actually asks:
 * what is this, is it for me, how do I start, and what here is real.
 */
export default function Landing({ wallet }) {
  const { stamps, hasPassport, done } = useStamps(wallet.account);
  const returning = Boolean(wallet.account && hasPassport);

  return (
    <>
      <section className="hero">
        <div className="wrap">
          <p className="eyebrow">{BRAND.operator} · learn blockchain by doing</p>
          <h1>Learn blockchain by fixing the trust problems of a small town.</h1>
          <p className="lead">
            {BRAND.name} is a working town of smart contracts on a live chain. Walk its sixteen modules in order —
            identity, money, markets, credentials, property, governance, oracles, lending and zero-knowledge — and
            check every step you take on the block explorer.
          </p>
          <div className="row">
            {returning ? (
              <a className="btn" href={to('map')}>
                Continue — {done} of 16 done
              </a>
            ) : (
              <a className="btn" href={to('start')}>
                Start learning
              </a>
            )}
            <a className="btn btn-ghost-light" href={to('map')}>
              See the town map
            </a>
            {BRAND.trainingUrl && (
              <a className="btn btn-ghost-light" href={BRAND.trainingUrl} target="_blank" rel="noreferrer">
                Training for teams
              </a>
            )}
          </div>
        </div>
      </section>

      <div className="wrap stack">
        <section className="card">
          <div className="card-head">
            <h2>How it works</h2>
          </div>
          <ol className="how">
            <li>
              <strong>Set up a wallet.</strong>
              <span className="muted">
                About five minutes, once. You get free test currency, and nothing here ever touches real money.
              </span>
            </li>
            <li>
              <strong>Walk the stops in order.</strong>
              <span className="muted">
                Each stop poses a trust problem an ordinary town has, and lets you solve it with a contract. Read its
                guide first.
              </span>
            </li>
            <li>
              <strong>Earn a stamp for every module.</strong>
              <span className="muted">
                The contract stamps your passport when you finish. Your progress lives on the chain, not on this site,
                and anyone can check it.
              </span>
            </li>
          </ol>
        </section>

        <section>
          <div className="section-head">
            <h2>What you will learn</h2>
            <p className="muted">Ten stops after a short warm-up, sixteen modules, in the order you walk them.</p>
          </div>
          <StopGrid stamps={stamps} compact />
        </section>

        <section className="card">
          <div className="card-head">
            <h2>Who it is for</h2>
          </div>
          <div className="who">
            <div>
              <h3>Students in a course</h3>
              <p className="muted small">
                Your instructor gives you a course code for the faucet, and the labs are graded work. The guides are
                what your instructor expects you to have read.
              </p>
            </div>
            <div>
              <h3>Learning on your own</h3>
              <p className="muted small">
                Everything here is free: every stop, every guide, every lab. Go at your own pace; your progress waits on
                the chain for you.
              </p>
            </div>
            <div>
              <h3>Instructors</h3>
              <p className="muted small">
                The whole town is open source (MIT). One command runs a private copy on your own machine — chain,
                contracts and site — for your own class.{' '}
                <a href={BRAND.repo} target="_blank" rel="noreferrer">
                  The code
                </a>
              </p>
            </div>
          </div>
        </section>

        <section className="card learn">
          <div className="card-head">
            <h2>Every module teaches the judgement, not just the button</h2>
            <p className="muted">
              Pressing the buttons takes an afternoon. Understanding why each contract is shaped the way it is takes
              longer, and that is the part worth having.
            </p>
          </div>
          <div className="board">
            <div className="module">
              <h3>Each guide answers the same questions</h3>
              <p className="muted small">
                What the trust problem is, and the one idea the module turns on. The two or three lines of code that
                carry the design. What to do here, in order, and what to look for on the explorer.{' '}
                <strong>When a plain database would have been the better choice.</strong> And what the contract does{' '}
                <strong>not</strong> fix — because knowing exactly where a guarantee stops is most of the skill.
              </p>
              <p>
                <a href={guideUrl(MODULE_INDEX)} target="_blank" rel="noreferrer">
                  Read the module guides
                </a>
              </p>
            </div>
            <div className="module">
              <h3>Two modules to know about</h3>
              <p className="muted small">
                Module 15 ships a <strong>deliberate vulnerability</strong>, and a test that exploits it: read its guide
                before its code. Module 16 proves something without revealing it — and spends as much of its guide on
                what the proof does <strong>not</strong> hide.
              </p>
            </div>
          </div>
        </section>

        <section className="card honest">
          <h2>What is real here, and what is not</h2>
          <p>
            The chain is real:{' '}
            {CHAIN_ID === 252501
              ? `${didlab.name} runs Hyperledger Besu with four known validators, blocks are final at once,`
              : `this town runs on ${didlab.name} (chain ${CHAIN_ID}),`}{' '}
            and every transaction is public on{' '}
            {EXPLORER ? (
              <a href={EXPLORER} target="_blank" rel="noreferrer">
                the explorer
              </a>
            ) : (
              'the explorer'
            )}
            . The money is not: TRUST and every town token are free test currency with no value, and they stay that
            way.
          </p>
          <p>
            <strong>Never connect a wallet that holds real money.</strong> Make a fresh one for {BRAND.name}. Public
            chains like Ethereum differ in the ways that matter: anyone can validate, finality takes minutes, and gas
            costs real money. The contracts here would run there too; the trust model would not be the same.
          </p>
        </section>
      </div>
    </>
  );
}
