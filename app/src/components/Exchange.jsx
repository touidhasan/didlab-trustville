import { useCallback, useEffect, useState } from 'react';
import { formatUnits, parseUnits } from 'viem';
import { grainLoansAbi, grainTokenAbi, townSwapAbi, townTokenAbi } from '../abi/generated.js';
import { contracts, explorerAddress, publicClient } from '../chain.js';
import { useRefresh } from '../refresh.js';
import { runTx } from '../tx.js';
import TxPanel from './TxPanel.jsx';

const grain = contracts.GrainToken;
const swap = contracts.TownSwap;
const loans = contracts.GrainLoans;
const token = contracts.TownToken;

const n = (v, d = 2) => Number(formatUnits(v ?? 0n, 18)).toLocaleString(undefined, { maximumFractionDigits: d });
const when = (t) => new Date(Number(t) * 1000).toLocaleTimeString();

/** Module 15: a market with two assets, and a loan priced off it. */
export default function Exchange({ wallet }) {
  const { account } = wallet;
  const ready = account && wallet.onDidlab;

  const [d, setD] = useState(null);
  const [tx, setTx] = useState(null);

  const [sellTvd, setSellTvd] = useState(true);
  const [amountIn, setAmountIn] = useState('');
  const [preview, setPreview] = useState(null);
  const [lpTvd, setLpTvd] = useState('');
  const [supplyAmt, setSupplyAmt] = useState('');
  const [collateral, setCollateral] = useState('');
  const [borrowAmt, setBorrowAmt] = useState('');

  const load = useCallback(async () => {
    if (!swap) return;
    const read = (address, abi, functionName, args) =>
      publicClient.readContract({ address, abi, functionName, args });

    const [reserveTvd, reserveGrain, totalShares, rateBps, poolValue] = await Promise.all([
      read(swap, townSwapAbi, 'reserveTvd'),
      read(swap, townSwapAbi, 'reserveGrain'),
      read(swap, townSwapAbi, 'totalShares'),
      read(loans, grainLoansAbi, 'rateBps'),
      read(loans, grainLoansAbi, 'poolValue'),
    ]);
    const price = reserveGrain > 0n ? (reserveTvd * 10n ** 18n) / reserveGrain : 0n;

    const mine = account
      ? await Promise.all([
          read(token, townTokenAbi, 'balanceOf', [account]),
          read(grain, grainTokenAbi, 'balanceOf', [account]),
          read(grain, grainTokenAbi, 'harvestableAt', [account]),
          read(swap, townSwapAbi, 'sharesOf', [account]),
          read(loans, grainLoansAbi, 'sharesOf', [account]),
          read(loans, grainLoansAbi, 'positionOf', [account]),
          read(loans, grainLoansAbi, 'availableToBorrow', [account]),
          read(loans, grainLoansAbi, 'healthFactor', [account]),
        ])
      : null;

    setD({
      reserveTvd,
      reserveGrain,
      totalShares,
      price,
      rateBps,
      poolValue,
      tvd: mine?.[0] ?? 0n,
      grain: mine?.[1] ?? 0n,
      harvestAt: mine?.[2] ?? 0n,
      lpShares: mine?.[3] ?? 0n,
      lendShares: mine?.[4] ?? 0n,
      position: mine?.[5] ?? [0n, 0n],
      canBorrow: mine?.[6] ?? 0n,
      health: mine?.[7] ?? 0n,
    });
  }, [account]);

  useEffect(() => {
    load().catch(() => {});
  }, [load]);
  useRefresh(
    useCallback(() => {
      load().catch(() => {});
    }, [load]),
  );

  // Quote on every keystroke: the number you sign for should be the number you were shown.
  useEffect(() => {
    let cancelled = false;
    (async () => {
      if (!swap || !amountIn || Number(amountIn) <= 0) return setPreview(null);
      try {
        const out = await publicClient.readContract({
          address: swap,
          abi: townSwapAbi,
          functionName: 'quote',
          args: [parseUnits(amountIn, 18), sellTvd],
        });
        if (!cancelled) setPreview(out);
      } catch {
        if (!cancelled) setPreview(null);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [amountIn, sellTvd]);

  if (!swap) {
    return (
      <section className="card" id="exchange">
        <div className="card-head">
          <h2>Exchange</h2>
        </div>
        <p className="notice-empty">
          Not deployed yet. Instructor: run <span className="mono">script/DeployDefi.s.sol</span>.
        </p>
      </section>
    );
  }

  const send = (opts) => runTx({ wallet, setTx, onDone: load, ...opts });
  const approve = (tokenAddr, abi, spender, amount) =>
    send({ address: tokenAddr, abi, functionName: 'approve', args: [spender, amount] });

  const doSwap = async (e) => {
    e.preventDefault();
    const amount = parseUnits(amountIn || '0', 18);
    if (amount <= 0n || preview == null) return;
    // 1% below the quote: enough for normal movement, tight enough to refuse a sandwich.
    const minOut = (preview * 99n) / 100n;
    const ok = sellTvd
      ? await approve(token, townTokenAbi, swap, amount)
      : await approve(grain, grainTokenAbi, swap, amount);
    if (!ok) return;
    return send({
      address: swap,
      abi: townSwapAbi,
      functionName: sellTvd ? 'swapTvdForGrain' : 'swapGrainForTvd',
      args: [amount, minOut, 0n],
      onDone: async () => {
        setAmountIn('');
        await load();
      },
    });
  };

  const addLiquidity = async (e) => {
    e.preventDefault();
    const amount = parseUnits(lpTvd || '0', 18);
    if (amount <= 0n) return;
    // Matching GRAIN at the current ratio, plus 2% headroom for the price moving underneath.
    const needGrain =
      d.reserveTvd > 0n ? (amount * d.reserveGrain * 102n) / (d.reserveTvd * 100n) : amount;
    if (!(await approve(token, townTokenAbi, swap, amount))) return;
    if (!(await approve(grain, grainTokenAbi, swap, needGrain))) return;
    return send({
      address: swap,
      abi: townSwapAbi,
      functionName: 'addLiquidity',
      args: [amount, needGrain, 0n],
      onDone: async () => {
        setLpTvd('');
        await load();
      },
    });
  };

  const supply = async (e) => {
    e.preventDefault();
    const amount = parseUnits(supplyAmt || '0', 18);
    if (amount <= 0n) return;
    if (!(await approve(token, townTokenAbi, loans, amount))) return;
    return send({
      address: loans,
      abi: grainLoansAbi,
      functionName: 'supply',
      args: [amount],
      onDone: async () => {
        setSupplyAmt('');
        await load();
      },
    });
  };

  const deposit = async (e) => {
    e.preventDefault();
    const amount = parseUnits(collateral || '0', 18);
    if (amount <= 0n) return;
    if (!(await approve(grain, grainTokenAbi, loans, amount))) return;
    return send({
      address: loans,
      abi: grainLoansAbi,
      functionName: 'depositCollateral',
      args: [amount],
      onDone: async () => {
        setCollateral('');
        await load();
      },
    });
  };

  const borrow = (e) => {
    e.preventDefault();
    const amount = parseUnits(borrowAmt || '0', 18);
    if (amount <= 0n) return;
    return send({
      address: loans,
      abi: grainLoansAbi,
      functionName: 'borrow',
      args: [amount],
      onDone: async () => {
        setBorrowAmt('');
        await load();
      },
    });
  };

  const repay = async () => {
    const debt = d.position[1];
    if (debt <= 0n) return;
    if (!(await approve(token, townTokenAbi, loans, debt))) return;
    return send({ address: loans, abi: grainLoansAbi, functionName: 'repay', args: [debt] });
  };

  const now = Math.floor(Date.now() / 1000);
  const canHarvest = d && (d.harvestAt === 0n || now >= Number(d.harvestAt));
  const health = d ? Number(formatUnits(d.health > 10n ** 30n ? 0n : d.health, 18)) : 0;
  const hasDebt = d && d.position[1] > 0n;

  return (
    <section className="card" id="exchange">
      <div className="card-head">
        <h2>Exchange &amp; loans · module 15</h2>
        <p className="muted">
          A second asset makes a price possible. Nobody sets it — the pool's two reserves are the
          price, and every trade moves them.
        </p>
      </div>

      <div className="board">
        <div>
          {/* ------------------------------------------------------- harvest */}
          <div className="module">
            <h3>Grain</h3>
            <p className="muted small">
              GRAIN has no mint function. Harvesting is the only way it comes into existence: any
              resident, a fixed 100, once per cooldown — the same rule for the town admin as for
              anyone else.
            </p>
            {d && (
              <p className="muted small">
                You hold <b>{n(d.grain)} GRAIN</b> and <b>{n(d.tvd)} TVD</b>
                {!canHarvest && d.harvestAt > 0n && ` · next harvest ${when(d.harvestAt)}`}
              </p>
            )}
            <button
              className="btn"
              disabled={!ready || !canHarvest}
              onClick={() => send({ address: grain, abi: grainTokenAbi, functionName: 'harvest' })}
            >
              Harvest 100 GRAIN
            </button>
          </div>

          {/* ---------------------------------------------------------- swap */}
          <div className="module">
            <h3>Swap</h3>
            {d && (
              <p className="muted small">
                Pool holds <b>{n(d.reserveTvd)} TVD</b> and <b>{n(d.reserveGrain)} GRAIN</b> · 1 GRAIN
                ≈ <b>{n(d.price, 4)} TVD</b> · fee 0.3%
              </p>
            )}
            <form onSubmit={doSwap} className="post-form">
              <button type="button" className="btn btn-ghost small-btn" onClick={() => setSellTvd((s) => !s)}>
                {sellTvd ? 'TVD → GRAIN' : 'GRAIN → TVD'}
              </button>
              <input
                value={amountIn}
                onChange={(e) => setAmountIn(e.target.value)}
                placeholder={sellTvd ? 'TVD in' : 'GRAIN in'}
                inputMode="decimal"
                style={{ maxWidth: 120 }}
                disabled={!ready}
              />
              <button className="btn" disabled={!ready || !preview}>
                Swap
              </button>
            </form>
            {preview != null && amountIn && (
              <p className="muted small">
                You get <b>{n(preview, 4)} {sellTvd ? 'GRAIN' : 'TVD'}</b> — an effective rate of{' '}
                {(Number(formatUnits(preview, 18)) / Number(amountIn)).toFixed(4)}. Compare it with a
                tiny trade: the difference is slippage, and it is the curve, not a fee. The order is
                sent with a 1% floor, so it fails rather than fills badly if someone trades first.
              </p>
            )}
          </div>

          {/* ----------------------------------------------------- liquidity */}
          <div className="module">
            <h3>Be the market</h3>
            <p className="muted small">
              Supply both assets and you earn the fees — but the pool sells whichever one is rising,
              so after a big move you hold more of the loser. That is impermanent loss, and it is a
              position, not a deposit.
            </p>
            <form onSubmit={addLiquidity} className="post-form">
              <input value={lpTvd} onChange={(e) => setLpTvd(e.target.value)} placeholder="TVD (GRAIN matched)" inputMode="decimal" style={{ maxWidth: 170 }} disabled={!ready} />
              <button className="btn" disabled={!ready || !lpTvd}>
                Add liquidity
              </button>
              {d && d.lpShares > 0n && (
                <button
                  type="button"
                  className="btn btn-ghost"
                  onClick={() => send({ address: swap, abi: townSwapAbi, functionName: 'removeLiquidity', args: [d.lpShares, 0n] })}
                >
                  Withdraw all ({n(d.lpShares)} shares)
                </button>
              )}
            </form>
          </div>

          {/* --------------------------------------------------------- loans */}
          <div className="module">
            <h3>Borrow against grain</h3>
            {d && (
              <p className="muted small">
                Lending pool: <b>{n(d.poolValue)} TVD</b> · borrowing costs{' '}
                {Number(d.rateBps) / 100}% a year · deposit GRAIN, borrow up to half its value, and
                you are liquidated past 70%.
              </p>
            )}

            <form onSubmit={supply} className="post-form">
              <input value={supplyAmt} onChange={(e) => setSupplyAmt(e.target.value)} placeholder="Lend TVD" inputMode="decimal" style={{ maxWidth: 120 }} disabled={!ready} />
              <button className="btn btn-ghost" disabled={!ready || !supplyAmt}>
                Lend
              </button>
              {d && d.lendShares > 0n && (
                <button
                  type="button"
                  className="btn btn-ghost"
                  onClick={() => send({ address: loans, abi: grainLoansAbi, functionName: 'withdrawSupply', args: [d.lendShares] })}
                >
                  Take back ({n(d.lendShares)} shares)
                </button>
              )}
            </form>

            <form onSubmit={deposit} className="post-form">
              <input value={collateral} onChange={(e) => setCollateral(e.target.value)} placeholder="GRAIN as collateral" inputMode="decimal" style={{ maxWidth: 180 }} disabled={!ready} />
              <button className="btn" disabled={!ready || !collateral}>
                Deposit collateral
              </button>
            </form>

            <form onSubmit={borrow} className="post-form">
              <input value={borrowAmt} onChange={(e) => setBorrowAmt(e.target.value)} placeholder="Borrow TVD" inputMode="decimal" style={{ maxWidth: 140 }} disabled={!ready} />
              <button className="btn" disabled={!ready || !borrowAmt}>
                Borrow
              </button>
              {hasDebt && (
                <button type="button" className="btn btn-ghost" onClick={repay}>
                  Repay everything ({n(d.position[1])} TVD)
                </button>
              )}
            </form>

            {d && (d.position[0] > 0n || hasDebt) && (
              <p className="muted small">
                Your position: <b>{n(d.position[0])} GRAIN</b> down, <b>{n(d.position[1])} TVD</b>{' '}
                owed · you could still take <b>{n(d.canBorrow)} TVD</b> ·{' '}
                {hasDebt ? (
                  <b className={health < 1 ? 'error' : undefined}>
                    health {health.toFixed(2)}
                    {health < 1 ? ' — anyone may liquidate you' : ''}
                  </b>
                ) : (
                  'no debt'
                )}
                {d.position[0] > 0n && !hasDebt && (
                  <>
                    {' · '}
                    <button
                      className="btn btn-ghost small-btn"
                      onClick={() => send({ address: loans, abi: grainLoansAbi, functionName: 'withdrawCollateral', args: [d.position[0]] })}
                    >
                      Withdraw collateral
                    </button>
                  </>
                )}
              </p>
            )}

            <p className="muted small">
              <b>Read the code before you trust this one.</b> The loan values your collateral at the
              pool's price this instant — and that price is just the two reserves, which anyone with
              enough capital can move inside a single transaction. It is left that way on purpose:
              see <span className="mono">docs/modules/15-defi.md</span>.
            </p>
            <p className="muted small">
              Grain{' '}
              <a className="mono" href={explorerAddress(grain)} target="_blank" rel="noreferrer">
                {grain?.slice(0, 10)}…
              </a>{' '}
              · Swap{' '}
              <a className="mono" href={explorerAddress(swap)} target="_blank" rel="noreferrer">
                {swap.slice(0, 10)}…
              </a>{' '}
              · Loans{' '}
              <a className="mono" href={explorerAddress(loans)} target="_blank" rel="noreferrer">
                {loans?.slice(0, 10)}…
              </a>
            </p>
          </div>
        </div>
        <TxPanel tx={tx} />
      </div>
    </section>
  );
}
