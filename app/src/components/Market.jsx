import { useCallback, useEffect, useState } from 'react';
import { encodePacked, formatUnits, isAddress, keccak256, parseUnits, stringToHex } from 'viem';
import { productRegistryAbi, sealedAuctionAbi, townEscrowAbi, townTokenAbi } from '../abi/generated.js';
import { contracts, explorerAddress, publicClient } from '../chain.js';
import { useRefresh } from '../refresh.js';
import { runTx } from '../tx.js';
import GuideLinks from './GuideLinks.jsx';
import TxPanel from './TxPanel.jsx';

const registry = contracts.ProductRegistry;
const escrow = contracts.TownEscrow;
const auction = contracts.SealedAuction;
const token = contracts.TownToken;

const ORDER_STATE = ['—', 'Funded', 'Released', 'Refunded', 'Disputed'];
const short = (a) => `${a.slice(0, 6)}…${a.slice(-4)}`;
const tvd = (v) => `${Number(formatUnits(v, 18)).toLocaleString()} TVD`;
const when = (t) => new Date(Number(t) * 1000).toLocaleString();

/** Salts live only in this browser. Lose one and that bid can never be revealed. */
const saltKey = (id) => `trustville.bid.${id}`;
const saveBid = (id, amount, salt) => {
  try {
    localStorage.setItem(saltKey(id), JSON.stringify({ amount, salt }));
  } catch {
    /* private window: the student must keep the salt themselves */
  }
};
const loadBid = (id) => {
  try {
    return JSON.parse(localStorage.getItem(saltKey(id)) || 'null');
  } catch {
    return null;
  }
};

/** Modules 4–6: provenance, escrow, and a sealed-bid auction. */
export default function Market({ wallet }) {
  const { account } = wallet;
  const ready = account && wallet.onDidlab;

  const [products, setProducts] = useState([]);
  const [orders, setOrders] = useState([]);
  const [auctions, setAuctions] = useState([]);
  const [refund, setRefund] = useState(0n);
  const [tx, setTx] = useState(null);

  // forms
  const [pName, setPName] = useState('');
  const [pOrigin, setPOrigin] = useState('');
  const [oSeller, setOSeller] = useState('');
  const [oAmount, setOAmount] = useState('');
  const [aTitle, setATitle] = useState('');
  const [bidAmounts, setBidAmounts] = useState({});

  const load = useCallback(async () => {
    if (!registry) return;
    const read = (address, abi, functionName, args) =>
      publicClient.readContract({ address, abi, functionName, args });

    // last 6 products
    const n = await read(registry, productRegistryAbi, 'count');
    const ids = [];
    for (let i = n; i > 0n && ids.length < 6; i--) ids.push(i);
    setProducts(
      (await Promise.all(ids.map((id) => read(registry, productRegistryAbi, 'get', [id])))).map((p, i) => ({
        id: ids[i],
        ...p,
      })),
    );

    // last 4 auctions
    const an = await read(auction, sealedAuctionAbi, 'count');
    const aIds = [];
    for (let i = an; i > 0n && aIds.length < 4; i--) aIds.push(i);
    setAuctions(
      (await Promise.all(aIds.map((id) => read(auction, sealedAuctionAbi, 'get', [id])))).map((a, i) => ({
        id: aIds[i],
        ...a,
      })),
    );

    if (!account) return;
    const myOrderIds = await read(escrow, townEscrowAbi, 'ordersOf', [account]);
    const mine = myOrderIds.slice(-5);
    setOrders(
      (await Promise.all(mine.map((id) => read(escrow, townEscrowAbi, 'get', [id])))).map((o, i) => ({
        id: mine[i],
        ...o,
      })),
    );
    setRefund(await read(auction, sealedAuctionAbi, 'refunds', [account]));
  }, [account]);

  useEffect(() => {
    load().catch(() => {});
  }, [load]);
  useRefresh(
    useCallback(() => {
      load().catch(() => {});
    }, [load]),
  );

  if (!registry) {
    return (
      <section className="card" id="market">
        <div className="card-head">
          <h2>Market</h2>
        </div>
        <p className="notice-empty">
          Not deployed yet. Instructor: run <span className="mono">script/DeployMarket.s.sol</span>.
        </p>
      </section>
    );
  }

  const send = (opts) => runTx({ wallet, setTx, onDone: load, ...opts });

  /* ------------------------------------------------------------ module 4 */
  const registerProduct = (e) => {
    e.preventDefault();
    return send({
      address: registry,
      abi: productRegistryAbi,
      functionName: 'register',
      // The certificate itself stays with you; only this hash goes on chain.
      args: [pName, pOrigin, keccak256(stringToHex(`${pName}|${pOrigin}|${account}`))],
      onDone: async () => {
        setPName('');
        setPOrigin('');
        await load();
      },
    });
  };

  const handOver = (id) => {
    const to = window.prompt('Transfer custody to which address?');
    if (!to || !isAddress(to)) return;
    return send({
      address: registry,
      abi: productRegistryAbi,
      functionName: 'transferCustody',
      args: [id, to, 'handed over at the market'],
    });
  };

  /* ------------------------------------------------------------ module 5 */
  const createOrder = async (e) => {
    e.preventDefault();
    const amount = parseUnits(oAmount, 18);
    // Two transactions: approve the escrow to move your TVD, then fund the order.
    const approved = await send({
      address: token,
      abi: townTokenAbi,
      functionName: 'approve',
      args: [escrow, amount],
    });
    if (!approved) return;
    return send({
      address: escrow,
      abi: townEscrowAbi,
      functionName: 'createOrder',
      args: [oSeller, amount, 0n, 3600],
      onDone: async () => {
        setOAmount('');
        await load();
      },
    });
  };

  const orderAction = (id, functionName) =>
    send({ address: escrow, abi: townEscrowAbi, functionName, args: [id] });

  /* ------------------------------------------------------------ module 6 */
  const createAuction = (e) => {
    e.preventDefault();
    return send({
      address: auction,
      abi: sealedAuctionAbi,
      functionName: 'createAuction',
      args: [aTitle, 0n, 300, 300], // 5 minutes to commit, 5 to reveal
      onDone: async () => {
        setATitle('');
        await load();
      },
    });
  };

  const commit = (id) => {
    const raw = bidAmounts[id];
    if (!raw) return;
    const amount = parseUnits(raw, 18);
    const salt = keccak256(stringToHex(`${Date.now()}-${Math.random()}`));
    const commitment = keccak256(encodePacked(['address', 'uint256', 'bytes32'], [account, amount, salt]));
    saveBid(id, raw, salt);
    return send({
      address: auction,
      abi: sealedAuctionAbi,
      functionName: 'commitBid',
      args: [id, commitment],
    });
  };

  const reveal = async (id) => {
    const saved = loadBid(id);
    if (!saved) {
      window.alert('No saved bid in this browser. Without the salt the bid cannot be revealed.');
      return;
    }
    const amount = parseUnits(saved.amount, 18);
    const approved = await send({
      address: token,
      abi: townTokenAbi,
      functionName: 'approve',
      args: [auction, amount],
    });
    if (!approved) return;
    return send({
      address: auction,
      abi: sealedAuctionAbi,
      functionName: 'revealBid',
      args: [id, amount, saved.salt],
    });
  };

  const now = Math.floor(Date.now() / 1000);

  return (
    <section className="card" id="market">
      <div className="card-head">
        <h2>Market · modules 4–6</h2>
        <p className="muted">
          Where goods change hands between people who have no reason to trust each other: a custody trail, an
          escrow that holds the money, and an auction where bids stay secret until everyone has committed.
        </p>
        <GuideLinks ids={[4, 5, 6]} />
      </div>

      <div className="board">
        <div>
          {/* ---------------------------------------------------- provenance */}
          <div className="module">
            <h3>4 · Provenance</h3>
            <p className="muted small">
              Register a product and hand it on. Every transfer is a public record. The chain proves the record
              never changed — not that the origin was true when written.
            </p>
            <form onSubmit={registerProduct} className="post-form">
              <input value={pName} onChange={(e) => setPName(e.target.value)} placeholder="Product" disabled={!ready} />
              <input value={pOrigin} onChange={(e) => setPOrigin(e.target.value)} placeholder="Origin" disabled={!ready} />
              <button className="btn" disabled={!ready || !pName.trim() || !pOrigin.trim()}>
                Register
              </button>
            </form>
            <ul className="notices">
              {products.length === 0 && <li className="muted">No products yet.</li>}
              {products.map((p) => (
                <li key={p.id.toString()}>
                  <span>
                    <b>{p.name}</b> · {p.origin}
                  </span>
                  <span className="muted small mono">
                    #{p.id.toString()} · holder {short(p.holder)} · {p.transfers} transfer
                    {p.transfers === 1 ? '' : 's'}
                  </span>
                  {ready && p.holder.toLowerCase() === account.toLowerCase() && (
                    <button className="btn btn-ghost small-btn" onClick={() => handOver(p.id)}>
                      Hand over
                    </button>
                  )}
                </li>
              ))}
            </ul>
          </div>

          {/* -------------------------------------------------------- escrow */}
          <div className="module">
            <h3>5 · Escrow</h3>
            <p className="muted small">
              Your TVD sits in the contract, not with the seller. Confirm and they are paid; stay silent and they
              can claim after an hour; dispute and the town admin decides.
            </p>
            <form onSubmit={createOrder} className="post-form">
              <input value={oSeller} onChange={(e) => setOSeller(e.target.value)} placeholder="0x… seller" disabled={!ready} />
              <input
                value={oAmount}
                onChange={(e) => setOAmount(e.target.value)}
                placeholder="TVD"
                inputMode="decimal"
                disabled={!ready}
                style={{ maxWidth: 110 }}
              />
              <button className="btn" disabled={!ready || !isAddress(oSeller) || !(Number(oAmount) > 0)}>
                Pay into escrow
              </button>
            </form>
            <ul className="notices">
              {orders.length === 0 && <li className="muted">No orders yet.</li>}
              {orders.map((o) => {
                const isBuyer = account && o.buyer.toLowerCase() === account.toLowerCase();
                const funded = o.state === 1;
                return (
                  <li key={o.id.toString()}>
                    <span>
                      <b>#{o.id.toString()}</b> {tvd(o.amount)} · {ORDER_STATE[o.state]} ·{' '}
                      {isBuyer ? `to ${short(o.seller)}` : `from ${short(o.buyer)}`}
                    </span>
                    <span className="muted small">seller may claim after {when(o.deadline)}</span>
                    {ready && funded && (
                      <span className="row">
                        {isBuyer ? (
                          <>
                            <button className="btn small-btn" onClick={() => orderAction(o.id, 'confirmReceipt')}>
                              Confirm receipt
                            </button>
                            <button className="btn btn-ghost small-btn" onClick={() => orderAction(o.id, 'dispute')}>
                              Dispute
                            </button>
                          </>
                        ) : (
                          <button
                            className="btn small-btn"
                            disabled={now < Number(o.deadline)}
                            onClick={() => orderAction(o.id, 'claimAfterWindow')}
                          >
                            Claim after window
                          </button>
                        )}
                      </span>
                    )}
                  </li>
                );
              })}
            </ul>
          </div>

          {/* ------------------------------------------------------- auction */}
          <div className="module">
            <h3>6 · Sealed-bid auction</h3>
            <p className="muted small">
              Commit a hash of your bid, reveal it later. Your salt is saved in this browser only — clear your
              storage and the bid is void, which is exactly the trade-off commit–reveal makes.
            </p>
            <form onSubmit={createAuction} className="post-form">
              <input value={aTitle} onChange={(e) => setATitle(e.target.value)} placeholder="What are you selling?" disabled={!ready} />
              <button className="btn" disabled={!ready || !aTitle.trim()}>
                Start auction
              </button>
            </form>
            {refund > 0n && (
              <p className="row">
                <span className="ok">You have {tvd(refund)} to withdraw.</span>
                <button
                  className="btn small-btn"
                  onClick={() => send({ address: auction, abi: sealedAuctionAbi, functionName: 'withdrawRefund' })}
                >
                  Withdraw
                </button>
              </p>
            )}
            <ul className="notices">
              {auctions.length === 0 && <li className="muted">No auctions yet.</li>}
              {auctions.map((a) => {
                const phase =
                  now < Number(a.commitEnd) ? 'commit' : now < Number(a.revealEnd) ? 'reveal' : 'ended';
                const mine = account && a.seller.toLowerCase() === account.toLowerCase();
                return (
                  <li key={a.id.toString()}>
                    <span>
                      <b>{a.title}</b> · {phase === 'ended' ? 'ended' : `${phase} phase`}
                    </span>
                    <span className="muted small">
                      {phase === 'commit' && `commit until ${when(a.commitEnd)}`}
                      {phase === 'reveal' && `reveal until ${when(a.revealEnd)}`}
                      {phase === 'ended' &&
                        (a.highBidder === '0x0000000000000000000000000000000000000000'
                          ? 'no bids revealed'
                          : `winner ${short(a.highBidder)} at ${tvd(a.highBid)}`)}
                    </span>
                    {ready && !mine && phase === 'commit' && (
                      <span className="row">
                        <input
                          value={bidAmounts[a.id] || ''}
                          onChange={(e) => setBidAmounts({ ...bidAmounts, [a.id]: e.target.value })}
                          placeholder="Secret bid (TVD)"
                          inputMode="decimal"
                          style={{ maxWidth: 150 }}
                        />
                        <button className="btn small-btn" onClick={() => commit(a.id)}>
                          Commit
                        </button>
                      </span>
                    )}
                    {ready && !mine && phase === 'reveal' && (
                      <button className="btn small-btn" onClick={() => reveal(a.id)}>
                        Reveal my bid
                      </button>
                    )}
                    {phase === 'ended' && !a.settled && (
                      <button
                        className="btn btn-ghost small-btn"
                        onClick={() => send({ address: auction, abi: sealedAuctionAbi, functionName: 'settle', args: [a.id] })}
                      >
                        Settle
                      </button>
                    )}
                  </li>
                );
              })}
            </ul>
            <p className="muted small">
              Registry{' '}
              <a className="mono" href={explorerAddress(registry)} target="_blank" rel="noreferrer">
                {registry.slice(0, 10)}…
              </a>{' '}
              · Escrow{' '}
              <a className="mono" href={explorerAddress(escrow)} target="_blank" rel="noreferrer">
                {escrow?.slice(0, 10)}…
              </a>{' '}
              · Auction{' '}
              <a className="mono" href={explorerAddress(auction)} target="_blank" rel="noreferrer">
                {auction?.slice(0, 10)}…
              </a>
            </p>
          </div>
        </div>
        <TxPanel tx={tx} />
      </div>
    </section>
  );
}
