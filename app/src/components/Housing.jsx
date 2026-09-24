import { useCallback, useEffect, useState } from 'react';
import { formatUnits, isAddress, keccak256, parseUnits, stringToHex } from 'viem';
import { propertyDeedsAbi, rentEscrowAbi, townTokenAbi } from '../abi/generated.js';
import { contracts, explorerAddress, publicClient } from '../chain.js';
import { useRefresh } from '../refresh.js';
import { runTx } from '../tx.js';
import TxPanel from './TxPanel.jsx';

const deeds = contracts.PropertyDeeds;
const leases = contracts.RentEscrow;
const token = contracts.TownToken;

const STATE = ['—', 'Offered', 'Active', 'Claimed', 'Settled'];
const short = (a) => `${a.slice(0, 6)}…${a.slice(-4)}`;
const tvd = (v) => `${Number(formatUnits(v, 18)).toLocaleString()} TVD`;
const when = (t) => new Date(Number(t) * 1000).toLocaleString();

/** Modules 9–10: deeds that really transfer, and a deposit neither side controls. */
export default function Housing({ wallet }) {
  const { account } = wallet;
  const ready = account && wallet.onDidlab;

  const [props, setProps] = useState([]);
  const [myLeases, setMyLeases] = useState([]);
  const [tx, setTx] = useState(null);

  const [addr, setAddr] = useState('');
  const [tenant, setTenant] = useState('');
  const [rent, setRent] = useState('');
  const [deposit, setDeposit] = useState('');
  const [deedId, setDeedId] = useState('');

  const load = useCallback(async () => {
    if (!deeds) return;
    const read = (address, abi, functionName, args) =>
      publicClient.readContract({ address, abi, functionName, args });

    const n = await read(deeds, propertyDeedsAbi, 'count');
    const ids = [];
    for (let i = n; i > 0n && ids.length < 6; i--) ids.push(i);
    const rows = await Promise.all(
      ids.map(async (id) => ({
        id,
        owner: await read(deeds, propertyDeedsAbi, 'ownerOf', [id]),
        ...(await read(deeds, propertyDeedsAbi, 'get', [id])),
      })),
    );
    setProps(rows);

    if (!account) return;
    const mine = (await read(leases, rentEscrowAbi, 'leasesOf', [account])).slice(-5);
    setMyLeases(
      await Promise.all(mine.map(async (id) => ({ id, ...(await read(leases, rentEscrowAbi, 'get', [id])) }))),
    );
  }, [account]);

  useEffect(() => {
    load().catch(() => {});
  }, [load]);
  useRefresh(
    useCallback(() => {
      load().catch(() => {});
    }, [load]),
  );

  if (!deeds) {
    return (
      <section className="card" id="housing">
        <div className="card-head">
          <h2>Housing</h2>
        </div>
        <p className="notice-empty">
          Not deployed yet. Instructor: run <span className="mono">script/DeployHousing.s.sol</span>.
        </p>
      </section>
    );
  }

  const send = (opts) => runTx({ wallet, setTx, onDone: load, ...opts });

  /* ------------------------------------------------------------ module 9 */
  const register = (e) => {
    e.preventDefault();
    return send({
      address: deeds,
      abi: propertyDeedsAbi,
      functionName: 'register',
      args: [addr, keccak256(stringToHex(`title:${addr}`))],
      onDone: async () => {
        setAddr('');
        await load();
      },
    });
  };

  const sell = (id) => {
    const to = window.prompt('Transfer this deed to which address?');
    if (!to || !isAddress(to)) return;
    return send({
      address: deeds,
      abi: propertyDeedsAbi,
      functionName: 'transferFrom',
      args: [account, to, id],
    });
  };

  /* ----------------------------------------------------------- module 10 */
  const offer = (e) => {
    e.preventDefault();
    return send({
      address: leases,
      abi: rentEscrowAbi,
      functionName: 'offerLease',
      args: [BigInt(deedId), tenant, parseUnits(rent || '0', 18), parseUnits(deposit || '0', 18), 7200],
      onDone: async () => {
        setTenant('');
        setRent('');
        setDeposit('');
        setDeedId('');
        await load();
      },
    });
  };

  const accept = async (l) => {
    if (l.deposit > 0n) {
      const ok = await send({
        address: token,
        abi: townTokenAbi,
        functionName: 'approve',
        args: [leases, l.deposit],
      });
      if (!ok) return;
    }
    return send({ address: leases, abi: rentEscrowAbi, functionName: 'acceptLease', args: [l.id] });
  };

  const pay = async (l) => {
    if (l.rent > 0n) {
      const ok = await send({
        address: token,
        abi: townTokenAbi,
        functionName: 'approve',
        args: [leases, l.rent],
      });
      if (!ok) return;
    }
    return send({ address: leases, abi: rentEscrowAbi, functionName: 'payRent', args: [l.id] });
  };

  const claim = (l) => {
    const raw = window.prompt(`How much of the ${tvd(l.deposit)} deposit are you claiming?`, '0');
    if (raw === null) return;
    const reason = window.prompt('Reason (this is public)') || 'unspecified';
    return send({
      address: leases,
      abi: rentEscrowAbi,
      functionName: 'claimDeposit',
      args: [l.id, parseUnits(raw, 18), reason],
    });
  };

  const now = Math.floor(Date.now() / 1000);
  const CLAIM_WINDOW = 3600;

  return (
    <section className="card" id="housing">
      <div className="card-head">
        <h2>Housing · modules 9–10</h2>
        <p className="muted">
          A deed that genuinely changes hands, and a deposit that sits where neither the landlord nor the tenant
          can touch it alone.
        </p>
      </div>

      <div className="board">
        <div>
          {/* ------------------------------------------------------- deeds */}
          <div className="module">
            <h3>9 · Property deeds</h3>
            <p className="muted small">
              Same standard as your Passport, opposite rule: a deed is meant to be transferable. Registering is
              only a claim until the town certifies it — and certification is cleared when the deed moves.
            </p>
            <form onSubmit={register} className="post-form">
              <input value={addr} onChange={(e) => setAddr(e.target.value)} placeholder="12 Mill Lane" disabled={!ready} />
              <button className="btn" disabled={!ready || !addr.trim()}>
                Register property
              </button>
            </form>
            <ul className="notices">
              {props.length === 0 && <li className="muted">No properties yet.</li>}
              {props.map((p) => {
                const mine = account && p.owner.toLowerCase() === account.toLowerCase();
                return (
                  <li key={p.id.toString()}>
                    <span>
                      <b>{p.addressLine}</b> · deed #{p.id.toString()}
                      {p.certified ? ' · certified' : ' · unverified claim'}
                    </span>
                    <span className="muted small mono">owner {short(p.owner)}</span>
                    {ready && mine && (
                      <button className="btn btn-ghost small-btn" onClick={() => sell(p.id)}>
                        Transfer deed
                      </button>
                    )}
                  </li>
                );
              })}
            </ul>
          </div>

          {/* ------------------------------------------------------ leases */}
          <div className="module">
            <h3>10 · Rent escrow</h3>
            <p className="muted small">
              The deposit is locked for the lease. Afterwards the landlord has one hour to claim against it, in
              public, with a reason — otherwise the tenant simply takes it back.
            </p>
            <form onSubmit={offer} className="post-form">
              <input value={deedId} onChange={(e) => setDeedId(e.target.value)} placeholder="Deed #" inputMode="numeric" style={{ maxWidth: 90 }} disabled={!ready} />
              <input value={tenant} onChange={(e) => setTenant(e.target.value)} placeholder="0x… tenant" disabled={!ready} />
              <input value={rent} onChange={(e) => setRent(e.target.value)} placeholder="Rent" inputMode="decimal" style={{ maxWidth: 90 }} disabled={!ready} />
              <input value={deposit} onChange={(e) => setDeposit(e.target.value)} placeholder="Deposit" inputMode="decimal" style={{ maxWidth: 100 }} disabled={!ready} />
              <button className="btn" disabled={!ready || !deedId || !isAddress(tenant)}>
                Offer lease
              </button>
            </form>
            <ul className="notices">
              {myLeases.length === 0 && <li className="muted">No leases yet.</li>}
              {myLeases.map((l) => {
                const isTenant = account && l.tenant.toLowerCase() === account.toLowerCase();
                const ended = now >= Number(l.endsAt);
                const windowOver = now >= Number(l.endsAt) + CLAIM_WINDOW;
                return (
                  <li key={l.id.toString()}>
                    <span>
                      <b>#{l.id.toString()}</b> deed {l.deedId.toString()} · rent {tvd(l.rent)} · deposit{' '}
                      {tvd(l.deposit)} · {STATE[l.state]}
                    </span>
                    <span className="muted small">
                      {isTenant ? `landlord ${short(l.landlord)}` : `tenant ${short(l.tenant)}`} · ends{' '}
                      {when(l.endsAt)} · {l.rentPaid} rent payment{l.rentPaid === 1 ? '' : 's'}
                    </span>
                    {l.state === 3 && <span className="small error">claimed: {l.claimReason} ({tvd(l.claimAmount)})</span>}
                    {ready && (
                      <span className="row">
                        {isTenant && l.state === 1 && (
                          <button className="btn small-btn" onClick={() => accept(l)}>
                            Accept &amp; pay deposit
                          </button>
                        )}
                        {isTenant && l.state === 2 && !ended && (
                          <button className="btn small-btn" onClick={() => pay(l)}>
                            Pay rent
                          </button>
                        )}
                        {isTenant && l.state === 2 && windowOver && (
                          <button className="btn small-btn" onClick={() => send({ address: leases, abi: rentEscrowAbi, functionName: 'returnDeposit', args: [l.id] })}>
                            Take deposit back
                          </button>
                        )}
                        {!isTenant && l.state === 2 && ended && !windowOver && (
                          <button className="btn btn-ghost small-btn" onClick={() => claim(l)}>
                            Claim against deposit
                          </button>
                        )}
                      </span>
                    )}
                  </li>
                );
              })}
            </ul>
            <p className="muted small">
              Deeds{' '}
              <a className="mono" href={explorerAddress(deeds)} target="_blank" rel="noreferrer">
                {deeds.slice(0, 10)}…
              </a>{' '}
              · Leases{' '}
              <a className="mono" href={explorerAddress(leases)} target="_blank" rel="noreferrer">
                {leases?.slice(0, 10)}…
              </a>
            </p>
          </div>
        </div>
        <TxPanel tx={tx} />
      </div>
    </section>
  );
}
