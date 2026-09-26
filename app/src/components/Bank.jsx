import { useCallback, useEffect, useState } from 'react';
import { formatUnits, isAddress, parseUnits } from 'viem';
import { townBankAbi, townTokenAbi } from '../abi/generated.js';
import { contracts, explorerAddress, publicClient } from '../chain.js';
import { useRefresh } from '../refresh.js';
import { runTx } from '../tx.js';
import GuideLinks from './GuideLinks.jsx';
import TxPanel from './TxPanel.jsx';

const bank = contracts.TownBank;
const token = contracts.TownToken;

/** Module 3: the town currency. An ordinary ERC-20 that no human can mint. */
export default function Bank({ wallet }) {
  const [balance, setBalance] = useState(null);
  const [supply, setSupply] = useState(null);
  const [claimed, setClaimed] = useState(false);
  const [grant, setGrant] = useState(null);
  const [to, setTo] = useState('');
  const [amount, setAmount] = useState('');
  const [tx, setTx] = useState(null);

  const { account } = wallet;

  const load = useCallback(async () => {
    if (!token || !bank) return;
    const [s, g] = await Promise.all([
      publicClient.readContract({ address: token, abi: townTokenAbi, functionName: 'totalSupply' }),
      publicClient.readContract({ address: bank, abi: townBankAbi, functionName: 'grantAmount' }),
    ]);
    setSupply(s);
    setGrant(g);
    if (!account) return;
    const [b, c] = await Promise.all([
      publicClient.readContract({ address: token, abi: townTokenAbi, functionName: 'balanceOf', args: [account] }),
      publicClient.readContract({ address: bank, abi: townBankAbi, functionName: 'hasClaimed', args: [account] }),
    ]);
    setBalance(b);
    setClaimed(c);
  }, [account]);

  useEffect(() => {
    load().catch(() => {});
  }, [load]);

  // Reload when any module's transaction lands.
  useRefresh(useCallback(() => {
    load().catch(() => {});
  }, [load]));

  if (!bank) {
    return (
      <section className="card" id="bank">
        <div className="card-head">
          <h2>Bank</h2>
        </div>
        <p className="notice-empty">Not deployed yet — deploy the town contracts first.</p>
      </section>
    );
  }

  const ready = account && wallet.onDidlab && tx?.status !== 'pending';
  const validTransfer = isAddress(to) && Number(amount) > 0;

  const claim = () =>
    runTx({ wallet, address: bank, abi: townBankAbi, functionName: 'claimWelcomeGrant', setTx, onDone: load });

  const send = (e) => {
    e.preventDefault();
    return runTx({
      wallet,
      address: token,
      abi: townTokenAbi,
      functionName: 'transfer',
      args: [to, parseUnits(amount, 18)],
      setTx,
      onDone: async () => {
        setAmount('');
        await load();
      },
    });
  };

  const fmt = (v) => (v === null ? '—' : Number(formatUnits(v, 18)).toLocaleString());

  return (
    <section className="card" id="bank">
      <div className="card-head">
        <h2>Bank · module 3</h2>
        <p className="muted">
          TVD is the town currency, an ERC-20 anyone can audit. TRUST pays gas; TVD buys things. Only the Bank
          contract can mint, so no person — not even the town admin — can print money.
        </p>
        <GuideLinks ids={[3]} />
      </div>

      <div className="board">
        <div>
          <div className="figures">
            <div>
              <span className="figure">{fmt(balance)}</span>
              <span className="muted small">your TVD</span>
            </div>
            <div>
              <span className="figure">{fmt(supply)}</span>
              <span className="muted small">total minted</span>
            </div>
            <div>
              <span className="figure">{fmt(grant)}</span>
              <span className="muted small">welcome grant</span>
            </div>
          </div>

          <div className="module">
            <h3>Welcome grant</h3>
            {claimed ? (
              <p className="ok">Claimed. One per resident, enforced by the contract.</p>
            ) : (
              <button className="btn" disabled={!ready} onClick={claim}>
                Claim {fmt(grant)} TVD
              </button>
            )}
          </div>

          <div className="module">
            <h3>Send TVD</h3>
            <form onSubmit={send} className="post-form">
              <input value={to} onChange={(e) => setTo(e.target.value)} placeholder="0x… recipient" disabled={!ready} />
              <input
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
                placeholder="Amount"
                inputMode="decimal"
                disabled={!ready}
                style={{ maxWidth: 120 }}
              />
              <button className="btn" disabled={!ready || !validTransfer}>
                Send
              </button>
            </form>
            <p className="muted small">
              Token{' '}
              <a className="mono" href={explorerAddress(token)} target="_blank" rel="noreferrer">
                {token?.slice(0, 10)}…
              </a>{' '}
              · Bank{' '}
              <a className="mono" href={explorerAddress(bank)} target="_blank" rel="noreferrer">
                {bank.slice(0, 10)}…
              </a>
            </p>
          </div>
        </div>
        <TxPanel tx={tx} />
      </div>
    </section>
  );
}
