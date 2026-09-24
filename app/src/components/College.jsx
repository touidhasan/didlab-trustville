import { useCallback, useEffect, useState } from 'react';
import { formatUnits, isAddress, keccak256, parseUnits, stringToHex } from 'viem';
import { certificateRegistryAbi, eventTicketsAbi, townTokenAbi } from '../abi/generated.js';
import { contracts, explorerAddress, publicClient } from '../chain.js';
import { useRefresh } from '../refresh.js';
import { runTx } from '../tx.js';
import TxPanel from './TxPanel.jsx';

const certs = contracts.CertificateRegistry;
const tickets = contracts.EventTickets;
const token = contracts.TownToken;

const short = (a) => `${a.slice(0, 6)}…${a.slice(-4)}`;
const tvd = (v) => `${Number(formatUnits(v, 18)).toLocaleString()} TVD`;
const day = (t) => new Date(Number(t) * 1000).toLocaleDateString();

/** Modules 7–8: verifiable certificates and ERC-1155 event tickets. */
export default function College({ wallet }) {
  const { account } = wallet;
  const ready = account && wallet.onDidlab;

  const [held, setHeld] = useState([]);
  const [issued, setIssued] = useState([]);
  const [events, setEvents] = useState([]);
  const [tx, setTx] = useState(null);

  const [cTo, setCTo] = useState('');
  const [cCourse, setCCourse] = useState('');
  const [cDoc, setCDoc] = useState('');
  const [check, setCheck] = useState('');
  const [checkResult, setCheckResult] = useState(null);
  const [eName, setEName] = useState('');
  const [ePrice, setEPrice] = useState('');

  const load = useCallback(async () => {
    if (!certs) return;
    const read = (address, abi, functionName, args) =>
      publicClient.readContract({ address, abi, functionName, args });

    const n = await read(tickets, eventTicketsAbi, 'count');
    const ids = [];
    for (let i = n; i > 0n && ids.length < 5; i--) ids.push(i);
    const rows = await Promise.all(ids.map((id) => read(tickets, eventTicketsAbi, 'get', [id])));
    const mine = account
      ? await Promise.all(ids.map((id) => read(tickets, eventTicketsAbi, 'balanceOf', [account, id])))
      : ids.map(() => 0n);
    setEvents(rows.map((e, i) => ({ id: ids[i], mine: mine[i], ...e })));

    if (!account) return;
    const [holdIds, issuedIds] = await Promise.all([
      read(certs, certificateRegistryAbi, 'certificatesOf', [account]),
      read(certs, certificateRegistryAbi, 'issuedBy', [account]),
    ]);
    const fetchAll = (list) =>
      Promise.all(list.slice(-4).map(async (id) => ({ id, ...(await read(certs, certificateRegistryAbi, 'get', [id])) })));
    setHeld(await fetchAll(holdIds));
    setIssued(await fetchAll(issuedIds));
  }, [account]);

  useEffect(() => {
    load().catch(() => {});
  }, [load]);
  useRefresh(
    useCallback(() => {
      load().catch(() => {});
    }, [load]),
  );

  if (!certs) {
    return (
      <section className="card" id="college">
        <div className="card-head">
          <h2>College</h2>
        </div>
        <p className="notice-empty">
          Not deployed yet. Instructor: run <span className="mono">script/DeployCollege.s.sol</span>.
        </p>
      </section>
    );
  }

  const send = (opts) => runTx({ wallet, setTx, onDone: load, ...opts });

  /* ------------------------------------------------------------ module 7 */
  // The document never leaves your machine — only this hash is stored.
  const hashOf = (text) => keccak256(stringToHex(text));

  const issue = (e) => {
    e.preventDefault();
    return send({
      address: certs,
      abi: certificateRegistryAbi,
      functionName: 'issue',
      args: [cTo, cCourse, hashOf(cDoc)],
      onDone: async () => {
        setCTo('');
        setCCourse('');
        setCDoc('');
        await load();
      },
    });
  };

  const verify = async () => {
    const [known, valid, issuer, holder, course] = await publicClient.readContract({
      address: certs,
      abi: certificateRegistryAbi,
      functionName: 'verifyDocument',
      args: [hashOf(check)],
    });
    setCheckResult({ known, valid, issuer, holder, course });
  };

  const revoke = (id) =>
    send({
      address: certs,
      abi: certificateRegistryAbi,
      functionName: 'revoke',
      args: [id, 'issued in error'],
    });

  /* ------------------------------------------------------------ module 8 */
  const createEvent = (e) => {
    e.preventDefault();
    const startsAt = BigInt(Math.floor(Date.now() / 1000) + 7 * 24 * 3600); // one week out
    return send({
      address: tickets,
      abi: eventTicketsAbi,
      functionName: 'createEvent',
      args: [eName, parseUnits(ePrice || '0', 18), 100, startsAt],
      onDone: async () => {
        setEName('');
        setEPrice('');
        await load();
      },
    });
  };

  const buy = async (ev) => {
    const cost = ev.price;
    if (cost > 0n) {
      const ok = await send({
        address: token,
        abi: townTokenAbi,
        functionName: 'approve',
        args: [tickets, cost],
      });
      if (!ok) return;
    }
    return send({ address: tickets, abi: eventTicketsAbi, functionName: 'buy', args: [ev.id, 1] });
  };

  const ticketAction = (id, functionName, args = []) =>
    send({ address: tickets, abi: eventTicketsAbi, functionName, args: [id, ...args] });

  const now = Math.floor(Date.now() / 1000);

  return (
    <section className="card" id="college">
      <div className="card-head">
        <h2>College · modules 7–8</h2>
        <p className="muted">
          A diploma anyone can check without phoning the registrar, and a ticket that cannot be forged or used
          twice. Both keep the document itself off chain.
        </p>
      </div>

      <div className="board">
        <div>
          {/* --------------------------------------------------- certificates */}
          <div className="module">
            <h3>7 · Verifiable certificates</h3>
            <p className="muted small">
              Type the certificate text; only its hash is stored. Anyone can issue here — so verifying always
              means asking <em>who signed it</em>, never just "is it on the chain?".
            </p>
            <form onSubmit={issue} className="post-form">
              <input value={cTo} onChange={(e) => setCTo(e.target.value)} placeholder="0x… recipient" disabled={!ready} />
              <input value={cCourse} onChange={(e) => setCCourse(e.target.value)} placeholder="Course" disabled={!ready} />
              <input value={cDoc} onChange={(e) => setCDoc(e.target.value)} placeholder="Document text" disabled={!ready} />
              <button className="btn" disabled={!ready || !isAddress(cTo) || !cCourse.trim() || !cDoc.trim()}>
                Issue
              </button>
            </form>

            <div className="row" style={{ marginTop: 10 }}>
              <input
                value={check}
                onChange={(e) => {
                  setCheck(e.target.value);
                  setCheckResult(null);
                }}
                placeholder="Paste a document to verify"
                style={{ flex: 1, minWidth: 200, padding: '10px 12px', borderRadius: 10, border: '1px solid var(--line)', background: 'var(--bg)', color: 'var(--ink)', font: 'inherit' }}
              />
              <button className="btn btn-ghost" onClick={verify} disabled={!check.trim()}>
                Verify
              </button>
            </div>
            {checkResult && (
              <p className={checkResult.valid ? 'ok' : 'error'}>
                {!checkResult.known
                  ? 'Unknown document — no certificate was ever issued for this exact text.'
                  : checkResult.valid
                    ? `Valid · ${checkResult.course} · issued by ${short(checkResult.issuer)} to ${short(checkResult.holder)}`
                    : `REVOKED · was issued by ${short(checkResult.issuer)}`}
              </p>
            )}

            {held.length > 0 && (
              <>
                <p className="muted small" style={{ marginTop: 12 }}>
                  Held by you
                </p>
                <ul className="notices">
                  {held.map((c) => (
                    <li key={c.id.toString()}>
                      <span>
                        <b>{c.course}</b> · from {short(c.issuer)}
                      </span>
                      <span className={`small ${c.revokedAt > 0n ? 'error' : 'muted'}`}>
                        {c.revokedAt > 0n ? 'revoked' : `issued ${day(c.issuedAt)}`}
                      </span>
                    </li>
                  ))}
                </ul>
              </>
            )}
            {issued.length > 0 && (
              <>
                <p className="muted small" style={{ marginTop: 12 }}>
                  Issued by you
                </p>
                <ul className="notices">
                  {issued.map((c) => (
                    <li key={c.id.toString()}>
                      <span>
                        <b>{c.course}</b> · to {short(c.holder)}
                      </span>
                      {c.revokedAt > 0n ? (
                        <span className="small error">revoked</span>
                      ) : (
                        <button className="btn btn-ghost small-btn" onClick={() => revoke(c.id)}>
                          Revoke
                        </button>
                      )}
                    </li>
                  ))}
                </ul>
              </>
            )}
          </div>

          {/* --------------------------------------------------------- tickets */}
          <div className="module">
            <h3>8 · Event tickets</h3>
            <p className="muted small">
              One ERC-1155 token id per event, many identical tickets inside it. Ticket money is held by the
              contract until the event starts, so a cancelled event can refund everyone.
            </p>
            <form onSubmit={createEvent} className="post-form">
              <input value={eName} onChange={(e) => setEName(e.target.value)} placeholder="Event name" disabled={!ready} />
              <input
                value={ePrice}
                onChange={(e) => setEPrice(e.target.value)}
                placeholder="TVD"
                inputMode="decimal"
                disabled={!ready}
                style={{ maxWidth: 110 }}
              />
              <button className="btn" disabled={!ready || !eName.trim()}>
                Create event
              </button>
            </form>
            <ul className="notices">
              {events.length === 0 && <li className="muted">No events yet.</li>}
              {events.map((ev) => {
                const mineEvent = account && ev.organiser.toLowerCase() === account.toLowerCase();
                const started = now >= Number(ev.startsAt);
                return (
                  <li key={ev.id.toString()}>
                    <span>
                      <b>{ev.name}</b> · {tvd(ev.price)} · {ev.sold}/{ev.capacity} sold
                      {ev.cancelled && ' · cancelled'}
                    </span>
                    <span className="muted small mono">
                      starts {day(ev.startsAt)} · organiser {short(ev.organiser)}
                      {ev.mine > 0n && ` · you hold ${ev.mine.toString()}`}
                    </span>
                    {ready && (
                      <span className="row">
                        {!ev.cancelled && !started && !mineEvent && (
                          <button className="btn small-btn" onClick={() => buy(ev)}>
                            Buy a ticket
                          </button>
                        )}
                        {!ev.cancelled && ev.mine > 0n && (
                          <button className="btn btn-ghost small-btn" onClick={() => ticketAction(ev.id, 'redeem', [1])}>
                            Redeem 1
                          </button>
                        )}
                        {ev.cancelled && ev.mine >= 0n && (
                          <button className="btn small-btn" onClick={() => ticketAction(ev.id, 'refund')}>
                            Refund me
                          </button>
                        )}
                        {mineEvent && !ev.cancelled && !started && (
                          <button className="btn btn-ghost small-btn" onClick={() => ticketAction(ev.id, 'cancel')}>
                            Cancel event
                          </button>
                        )}
                        {mineEvent && !ev.cancelled && started && !ev.withdrawn && (
                          <button className="btn small-btn" onClick={() => ticketAction(ev.id, 'withdrawProceeds')}>
                            Withdraw proceeds
                          </button>
                        )}
                      </span>
                    )}
                  </li>
                );
              })}
            </ul>
            <p className="muted small">
              Certificates{' '}
              <a className="mono" href={explorerAddress(certs)} target="_blank" rel="noreferrer">
                {certs.slice(0, 10)}…
              </a>{' '}
              · Tickets{' '}
              <a className="mono" href={explorerAddress(tickets)} target="_blank" rel="noreferrer">
                {tickets?.slice(0, 10)}…
              </a>
            </p>
          </div>
        </div>
        <TxPanel tx={tx} />
      </div>
    </section>
  );
}
