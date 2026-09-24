import { useCallback, useEffect, useState } from 'react';
import { formatUnits, keccak256, parseUnits, stringToHex } from 'viem';
import { townCharityAbi, townTokenAbi } from '../abi/generated.js';
import { contracts, explorerAddress, publicClient } from '../chain.js';
import { useRefresh } from '../refresh.js';
import { runTx } from '../tx.js';
import TxPanel from './TxPanel.jsx';

const charity = contracts.TownCharity;
const token = contracts.TownToken;

const STATE = ['—', 'Raising', 'Funded', 'Completed', 'Failed', 'Cancelled'];
const STEP = ['Waiting', 'Evidence submitted', 'Approved', 'Rejected'];
const short = (a) => `${a.slice(0, 6)}…${a.slice(-4)}`;
const tvd = (v) => `${Number(formatUnits(v ?? 0n, 18)).toLocaleString()} TVD`;
const when = (t) => new Date(Number(t) * 1000).toLocaleString();

/** Module 13: all-or-nothing pledges, then money released one milestone at a time. */
export default function Charity({ wallet }) {
  const { account } = wallet;
  const ready = account && wallet.onDidlab;

  const [rows, setRows] = useState([]);
  const [isArbiter, setIsArbiter] = useState(false);
  const [tx, setTx] = useState(null);

  const [cause, setCause] = useState('');
  const [mins, setMins] = useState('60');
  const [a1, setA1] = useState('');
  const [w1, setW1] = useState('');
  const [a2, setA2] = useState('');
  const [w2, setW2] = useState('');
  const [amounts, setAmounts] = useState({});

  const load = useCallback(async () => {
    if (!charity) return;
    const read = (functionName, args) =>
      publicClient.readContract({ address: charity, abi: townCharityAbi, functionName, args });

    const n = await read('count');
    const ids = [];
    for (let i = n; i > 0n && ids.length < 5; i--) ids.push(i);

    setRows(
      await Promise.all(
        ids.map(async (id) => ({
          id,
          ...(await read('get', [id])),
          steps: await read('milestonesOf', [id]),
          mine: account ? await read('pledgeOf', [id, account]) : 0n,
          owed: account ? await read('refundable', [id, account]) : 0n,
        })),
      ),
    );

    if (!account) return setIsArbiter(false);
    const role = await read('ARBITER_ROLE');
    setIsArbiter(await read('hasRole', [role, account]));
  }, [account]);

  useEffect(() => {
    load().catch(() => {});
  }, [load]);
  useRefresh(
    useCallback(() => {
      load().catch(() => {});
    }, [load]),
  );

  if (!charity) {
    return (
      <section className="card" id="charity">
        <div className="card-head">
          <h2>Charity</h2>
        </div>
        <p className="notice-empty">
          Not deployed yet. Instructor: run <span className="mono">script/DeployCharity.s.sol</span>.
        </p>
      </section>
    );
  }

  const send = (opts) => runTx({ wallet, setTx, onDone: load, ...opts });

  const create = (e) => {
    e.preventDefault();
    const one = parseUnits(a1 || '0', 18);
    const two = parseUnits(a2 || '0', 18);
    return send({
      address: charity,
      abi: townCharityAbi,
      functionName: 'create',
      // The goal is the sum of the milestones by construction — a donor should never have
      // to check that arithmetic, and the contract refuses it if it does not hold.
      args: [cause, one + two, BigInt(Math.round(Number(mins) * 60)), [one, two], [w1, w2]],
      onDone: async () => {
        setCause('');
        setA1('');
        setW1('');
        setA2('');
        setW2('');
        await load();
      },
    });
  };

  const pledge = async (c) => {
    const amount = parseUnits(amounts[c.id] || '0', 18);
    if (amount <= 0n) return;
    const ok = await send({
      address: token,
      abi: townTokenAbi,
      functionName: 'approve',
      args: [charity, amount],
    });
    if (!ok) return;
    return send({
      address: charity,
      abi: townCharityAbi,
      functionName: 'pledge',
      args: [c.id, amount],
      onDone: async () => {
        setAmounts((a) => ({ ...a, [c.id]: '' }));
        await load();
      },
    });
  };

  const evidence = (c, step) => {
    const text = window.prompt(
      'Describe the evidence — a link, a report reference, a receipt number.\nOnly its hash goes on chain; the document itself stays off it.',
    );
    if (!text) return;
    return send({
      address: charity,
      abi: townCharityAbi,
      functionName: 'submitEvidence',
      args: [c.id, BigInt(step), keccak256(stringToHex(text))],
    });
  };

  const reject = (c, step) => {
    const reason = window.prompt('Why is this milestone rejected? (public, and it stops the campaign)');
    if (!reason) return;
    return send({
      address: charity,
      abi: townCharityAbi,
      functionName: 'rejectMilestone',
      args: [c.id, BigInt(step), reason],
    });
  };

  const now = Math.floor(Date.now() / 1000);
  const goal = (parseFloat(a1 || '0') + parseFloat(a2 || '0')).toLocaleString();

  return (
    <section className="card" id="charity">
      <div className="card-head">
        <h2>Charity · module 13</h2>
        <p className="muted">
          Give to a cause and keep the receipt. Pledges are refundable until the goal is met, and even
          then the money leaves one milestone at a time, against evidence.
        </p>
      </div>

      <div className="board">
        <div>
          <div className="module">
            <h3>Start a campaign</h3>
            <p className="muted small">
              Two milestones, each with what it buys. The goal is their sum — <b>{goal} TVD</b> — so a
              donor can read exactly what their money is promised to before giving it.
            </p>
            <form onSubmit={create} className="post-form">
              <input value={cause} onChange={(e) => setCause(e.target.value)} placeholder="A well for Mill Lane" disabled={!ready} />
              <input value={mins} onChange={(e) => setMins(e.target.value)} placeholder="Open for (min)" inputMode="numeric" style={{ maxWidth: 130 }} disabled={!ready} />
              <input value={w1} onChange={(e) => setW1(e.target.value)} placeholder="Milestone 1 — dig the well" disabled={!ready} />
              <input value={a1} onChange={(e) => setA1(e.target.value)} placeholder="TVD" inputMode="decimal" style={{ maxWidth: 90 }} disabled={!ready} />
              <input value={w2} onChange={(e) => setW2(e.target.value)} placeholder="Milestone 2 — install the pump" disabled={!ready} />
              <input value={a2} onChange={(e) => setA2(e.target.value)} placeholder="TVD" inputMode="decimal" style={{ maxWidth: 90 }} disabled={!ready} />
              <button className="btn" disabled={!ready || !cause.trim() || !w1.trim() || !w2.trim() || !a1 || !a2}>
                Open for pledges
              </button>
            </form>
          </div>

          <div className="module">
            <h3>Campaigns</h3>
            <ul className="notices">
              {rows.length === 0 && <li className="muted">Nothing being raised for yet.</li>}
              {rows.map((c) => {
                const isBeneficiary = account && c.beneficiary.toLowerCase() === account.toLowerCase();
                const expired = now >= Number(c.deadline);
                const pct = c.goal > 0n ? Number((c.raised * 100n) / c.goal) : 0;
                return (
                  <li key={c.id.toString()}>
                    <span>
                      <b>{c.cause}</b> · {tvd(c.raised)} of {tvd(c.goal)} ({pct}%) · {STATE[c.state]}
                    </span>
                    <span className="muted small">
                      by {short(c.beneficiary)} · {c.state === 1 ? `closes ${when(c.deadline)}` : `released ${tvd(c.released)}`}
                      {c.mine > 0n && ` · you gave ${tvd(c.mine)}`}
                    </span>

                    <ul className="notices">
                      {c.steps.map((m, i) => (
                        <li key={i}>
                          <span className="small">
                            {i + 1}. {m.what} · {tvd(m.amount)} · {STEP[m.step]}
                          </span>
                          {ready && c.state === 2 && (
                            <span className="row">
                              {isBeneficiary && m.step === 0 && (
                                <button className="btn btn-ghost small-btn" onClick={() => evidence(c, i)}>
                                  Submit evidence
                                </button>
                              )}
                              {isArbiter && m.step === 1 && (
                                <>
                                  <button className="btn small-btn" onClick={() => send({ address: charity, abi: townCharityAbi, functionName: 'approveMilestone', args: [c.id, BigInt(i)] })}>
                                    Approve &amp; release {tvd(m.amount)}
                                  </button>
                                  <button className="btn btn-ghost small-btn" onClick={() => reject(c, i)}>
                                    Reject
                                  </button>
                                </>
                              )}
                            </span>
                          )}
                        </li>
                      ))}
                    </ul>

                    {ready && (
                      <span className="row">
                        {c.state === 1 && !expired && (
                          <>
                            <input
                              value={amounts[c.id] || ''}
                              onChange={(e) => setAmounts((a) => ({ ...a, [c.id]: e.target.value }))}
                              placeholder="TVD"
                              inputMode="decimal"
                              style={{ maxWidth: 90 }}
                            />
                            <button className="btn small-btn" onClick={() => pledge(c)}>
                              Pledge
                            </button>
                          </>
                        )}
                        {c.state === 1 && expired && (
                          <button className="btn btn-ghost small-btn" onClick={() => send({ address: charity, abi: townCharityAbi, functionName: 'closeFailed', args: [c.id] })}>
                            Close — the deadline passed
                          </button>
                        )}
                        {c.owed > 0n && (
                          <button className="btn small-btn" onClick={() => send({ address: charity, abi: townCharityAbi, functionName: 'refund', args: [c.id] })}>
                            Take back {tvd(c.owed)}
                          </button>
                        )}
                      </span>
                    )}
                  </li>
                );
              })}
            </ul>
            <p className="muted small">
              Anyone may close a campaign that ran out of time — it is not the organiser's decision. A
              rejected milestone stops the campaign and returns the unspent remainder pro rata, so the
              tranche already approved stays paid: that work was done.
            </p>
            <p className="muted small">
              Charity{' '}
              <a className="mono" href={explorerAddress(charity)} target="_blank" rel="noreferrer">
                {charity.slice(0, 10)}…
              </a>
            </p>
          </div>
        </div>
        <TxPanel tx={tx} />
      </div>
    </section>
  );
}
