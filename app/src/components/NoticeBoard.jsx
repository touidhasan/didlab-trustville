import { useCallback, useEffect, useState } from 'react';
import { townNoticeBoardAbi } from '../abi/generated.js';
import { contracts, explorerAddress, publicClient } from '../chain.js';
import { useRefresh } from '../refresh.js';
import { runTx } from '../tx.js';
import TxPanel from './TxPanel.jsx';

const address = contracts.TownNoticeBoard;

/** D0 warm-up: the first contract call every student makes. */
export default function NoticeBoard({ wallet }) {
  const [notices, setNotices] = useState([]);
  const [text, setText] = useState('');
  const [tx, setTx] = useState(null);

  const load = useCallback(async () => {
    if (!address) return;
    const n = await publicClient.readContract({ address, abi: townNoticeBoardAbi, functionName: 'count' });
    const ids = [];
    for (let i = n - 1n; i >= 0n && ids.length < 5; i--) ids.push(i);
    const rows = await Promise.all(
      ids.map((id) => publicClient.readContract({ address, abi: townNoticeBoardAbi, functionName: 'get', args: [id] })),
    );
    setNotices(rows.map((r, i) => ({ id: ids[i], ...r })));
  }, []);

  useEffect(() => {
    load().catch(() => {});
  }, [load]);

  // Reload when any module's transaction lands.
  useRefresh(useCallback(() => {
    load().catch(() => {});
  }, [load]));

  const post = (ev) => {
    ev.preventDefault();
    if (!wallet.walletClient) return;
    // runTx simulates first, so a doomed transaction never reaches MetaMask.
    return runTx({
      wallet,
      address,
      abi: townNoticeBoardAbi,
      functionName: 'post',
      args: [text],
      setTx,
      onDone: async () => {
        setText('');
        await load();
      },
    });
  };

  const ready = wallet.account && wallet.onDidlab;

  return (
    <section className="card">
      <div className="card-head">
        <h2>Warm-up: the Town Notice Board</h2>
        <p className="muted">
          Your first transaction. Post a notice and watch the three basics: state changes, an event is emitted, and
          your address is recorded as the signer.
        </p>
      </div>

      {!address ? (
        <p className="notice-empty">
          Not deployed yet. Instructor: run <span className="mono">script/DeployNoticeBoard.s.sol</span> and add the
          address to <span className="mono">deployments/252501.json</span>.
        </p>
      ) : (
        <div className="board">
          <div>
            <form onSubmit={post} className="post-form">
              <input
                value={text}
                maxLength={140}
                onChange={(e) => setText(e.target.value)}
                placeholder={ready ? 'Market opens at 9 on Saturday…' : 'Finish the resident steps first'}
                disabled={!ready}
              />
              <button className="btn" disabled={!ready || !text.trim() || tx?.status === 'pending'}>
                Post
              </button>
            </form>
            <p className="muted small">
              Contract{' '}
              <a className="mono" href={explorerAddress(address)} target="_blank" rel="noreferrer">
                {address.slice(0, 10)}…
              </a>
            </p>
            <ul className="notices">
              {notices.length === 0 && <li className="muted">No notices yet. Be the first.</li>}
              {notices.map((n) => (
                <li key={n.id.toString()}>
                  <span>{n.text}</span>
                  <span className="muted small mono">
                    #{n.id.toString()} · {n.author.slice(0, 8)}… ·{' '}
                    {new Date(Number(n.postedAt) * 1000).toLocaleString()}
                  </span>
                </li>
              ))}
            </ul>
          </div>
          <TxPanel tx={tx} />
        </div>
      )}
    </section>
  );
}
