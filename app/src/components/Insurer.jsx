import { useCallback, useEffect, useState } from 'react';
import { formatUnits, parseUnits } from 'viem';
import { cropInsuranceAbi, rainOracleAbi, townTokenAbi } from '../abi/generated.js';
import { contracts, explorerAddress, publicClient } from '../chain.js';
import { useRefresh } from '../refresh.js';
import { runTx } from '../tx.js';
import TxPanel from './TxPanel.jsx';

const oracle = contracts.RainOracle;
const insurer = contracts.CropInsurance;
const token = contracts.TownToken;

const STATUS = ['—', 'Active', 'Paid out', 'No payout'];
const short = (a) => `${a.slice(0, 6)}…${a.slice(-4)}`;
const tvd = (v) => `${Number(formatUnits(v ?? 0n, 18)).toLocaleString()} TVD`;

/** Module 14: an outside fact, reported by several people, paying out with no assessor. */
export default function Insurer({ wallet }) {
  const { account } = wallet;
  const ready = account && wallet.onDidlab;

  const [terms, setTerms] = useState(null);
  const [periods, setPeriods] = useState([]);
  const [policies, setPolicies] = useState([]);
  const [tx, setTx] = useState(null);

  const [coverage, setCoverage] = useState('');
  const [period, setPeriod] = useState('');
  const [fundAmount, setFundAmount] = useState('');

  const load = useCallback(async () => {
    if (!oracle || !insurer) return;
    const ora = (functionName, args) =>
      publicClient.readContract({ address: oracle, abi: rainOracleAbi, functionName, args });
    const ins = (functionName, args) =>
      publicClient.readContract({ address: insurer, abi: cropInsuranceAbi, functionName, args });

    const [current, periodSeconds, quorum, triggerMm, premiumBps, reserved, available, pool] =
      await Promise.all([
        ora('currentPeriod'),
        ora('periodSeconds'),
        ora('quorum'),
        ins('triggerMm'),
        ins('premiumBps'),
        ins('reserved'),
        ins('available'),
        publicClient.readContract({
          address: token,
          abi: townTokenAbi,
          functionName: 'balanceOf',
          args: [insurer],
        }),
      ]);
    setTerms({ current, periodSeconds, quorum, triggerMm, premiumBps, reserved, available, pool });
    if (period === '') setPeriod(String(Number(current) + 1));

    const recent = [];
    for (let p = Number(current); p >= 0 && recent.length < 4; p--) recent.push(p);
    setPeriods(
      await Promise.all(
        recent.map(async (p) => {
          const [finalized, mm, count] = await ora('reading', [p]);
          const [who, values] = await ora('reportsOf', [p]);
          return { p, finalized, mm, count, who, values };
        }),
      ),
    );

    if (!account) return setPolicies([]);
    const ids = (await ins('policiesOf', [account])).slice(-5);
    setPolicies(await Promise.all(ids.map(async (id) => ({ id, ...(await ins('get', [id])) }))));
  }, [account, period]);

  useEffect(() => {
    load().catch(() => {});
  }, [load]);
  useRefresh(
    useCallback(() => {
      load().catch(() => {});
    }, [load]),
  );

  if (!oracle || !insurer) {
    return (
      <section className="card" id="insurer">
        <div className="card-head">
          <h2>Insurer</h2>
        </div>
        <p className="notice-empty">
          Not deployed yet. Instructor: run <span className="mono">script/DeployInsurer.s.sol</span>.
        </p>
      </section>
    );
  }

  const send = (opts) => runTx({ wallet, setTx, onDone: load, ...opts });

  const approveThen = async (amount, next) => {
    const ok = await send({
      address: token,
      abi: townTokenAbi,
      functionName: 'approve',
      args: [insurer, amount],
    });
    if (ok) return next();
    return false;
  };

  const fund = (e) => {
    e.preventDefault();
    const amount = parseUnits(fundAmount || '0', 18);
    if (amount <= 0n) return;
    return approveThen(amount, () =>
      send({
        address: insurer,
        abi: cropInsuranceAbi,
        functionName: 'fund',
        args: [amount],
        onDone: async () => {
          setFundAmount('');
          await load();
        },
      }),
    );
  };

  const buy = (e) => {
    e.preventDefault();
    const cover = parseUnits(coverage || '0', 18);
    if (cover <= 0n) return;
    const premium = (cover * BigInt(terms?.premiumBps ?? 0)) / 10000n;
    return approveThen(premium, () =>
      send({
        address: insurer,
        abi: cropInsuranceAbi,
        functionName: 'buy',
        args: [Number(period), cover],
        onDone: async () => {
          setCoverage('');
          await load();
        },
      }),
    );
  };

  const windowOf = (p) => {
    if (!terms) return '';
    const start = p * Number(terms.periodSeconds) * 1000;
    return new Date(start).toLocaleTimeString();
  };

  const premiumNow = terms && coverage ? (parseFloat(coverage) * terms.premiumBps) / 10000 : 0;

  return (
    <section className="card" id="insurer">
      <div className="card-head">
        <h2>Insurer · module 14</h2>
        <p className="muted">
          The first stop where the chain depends on something outside it. Several reporters say what
          the rainfall was, the contract takes the middle answer, and a policy pays on that number —
          with no assessor, no claim form and no argument.
        </p>
      </div>

      <div className="board">
        <div>
          {/* ------------------------------------------------------- the oracle */}
          <div className="module">
            <h3>The rain gauge</h3>
            {terms && (
              <p className="muted small">
                Period <b>{String(terms.current)}</b> is running now · each period lasts{' '}
                {Number(terms.periodSeconds) / 60} minutes · <b>{String(terms.quorum)}</b> reports
                needed before a period can be settled · under <b>{String(terms.triggerMm)}mm</b> is a
                drought.
              </p>
            )}
            <ul className="notices">
              {periods.map((r) => (
                <li key={r.p}>
                  <span>
                    <b>Period {r.p}</b> · from {windowOf(r.p)} ·{' '}
                    {r.finalized
                      ? `settled at ${r.mm}mm (median of ${r.count})`
                      : `${r.who.length} report${r.who.length === 1 ? '' : 's'} in, not settled`}
                  </span>
                  {r.who.length > 0 && (
                    <span className="muted small mono">
                      {r.who.map((w, i) => `${short(w)} said ${r.values[i]}mm`).join(' · ')}
                    </span>
                  )}
                  {ready && !r.finalized && terms && r.who.length >= Number(terms.quorum) && (
                    <button
                      className="btn small-btn"
                      onClick={() => send({ address: oracle, abi: rainOracleAbi, functionName: 'finalize', args: [r.p] })}
                    >
                      Settle this period
                    </button>
                  )}
                </li>
              ))}
            </ul>
            <p className="muted small">
              Anyone may settle a period once enough reports are in — including someone holding a
              policy on it, because the caller cannot change what the answer is. Every individual
              report stays visible above, for ever: a reporter whose figure sat far from the middle
              is on the record.
            </p>
          </div>

          {/* ---------------------------------------------------- the insurance */}
          <div className="module">
            <h3>Drought cover</h3>
            {terms && (
              <p className="muted small">
                Pool holds {tvd(terms.pool)} · promised to live policies {tvd(terms.reserved)} ·{' '}
                <b>{tvd(terms.available)}</b> still sellable · premium{' '}
                {Number(terms.premiumBps) / 100}% of cover.
              </p>
            )}

            <form onSubmit={buy} className="post-form">
              <input value={period} onChange={(e) => setPeriod(e.target.value)} placeholder="Period" inputMode="numeric" style={{ maxWidth: 90 }} disabled={!ready} />
              <input value={coverage} onChange={(e) => setCoverage(e.target.value)} placeholder="Cover (TVD)" inputMode="decimal" style={{ maxWidth: 130 }} disabled={!ready} />
              <button className="btn" disabled={!ready || !coverage || !period}>
                Buy cover {premiumNow > 0 ? `for ${premiumNow.toLocaleString()} TVD` : ''}
              </button>
            </form>
            <p className="muted small">
              You can only insure a period that has not started. Otherwise you could watch the
              drought happen and then buy cover for it.
            </p>

            <ul className="notices">
              {policies.length === 0 && <li className="muted">No policies yet.</li>}
              {policies.map((p) => {
                const reading = periods.find((r) => r.p === Number(p.period));
                const settleable = p.status === 1 && reading?.finalized;
                return (
                  <li key={p.id.toString()}>
                    <span>
                      <b>#{p.id.toString()}</b> · period {String(p.period)} · cover {tvd(p.coverage)} ·
                      paid {tvd(p.premium)} · pays under {String(p.triggerMm)}mm · {STATUS[p.status]}
                    </span>
                    {ready && settleable && (
                      <button className="btn small-btn" onClick={() => send({ address: insurer, abi: cropInsuranceAbi, functionName: 'settle', args: [p.id] })}>
                        Settle — the reading is in
                      </button>
                    )}
                    {ready && p.status === 1 && !reading?.finalized && (
                      <span className="muted small">waiting for period {String(p.period)} to be settled</span>
                    )}
                  </li>
                );
              })}
            </ul>
          </div>

          {/* --------------------------------------------------------- the pool */}
          <div className="module">
            <h3>Back the insurer</h3>
            <p className="muted small">
              Anyone may capitalise the pool. The insurer can never sell more cover than it holds —
              which is why it refuses a sale rather than promising money it does not have.
            </p>
            <form onSubmit={fund} className="post-form">
              <input value={fundAmount} onChange={(e) => setFundAmount(e.target.value)} placeholder="TVD" inputMode="decimal" style={{ maxWidth: 110 }} disabled={!ready} />
              <button className="btn btn-ghost" disabled={!ready || !fundAmount}>
                Add to the pool
              </button>
            </form>
            <p className="muted small">
              Oracle{' '}
              <a className="mono" href={explorerAddress(oracle)} target="_blank" rel="noreferrer">
                {oracle.slice(0, 10)}…
              </a>{' '}
              · Insurer{' '}
              <a className="mono" href={explorerAddress(insurer)} target="_blank" rel="noreferrer">
                {insurer.slice(0, 10)}…
              </a>
            </p>
          </div>
        </div>
        <TxPanel tx={tx} />
      </div>
    </section>
  );
}
