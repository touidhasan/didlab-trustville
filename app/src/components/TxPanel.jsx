import { formatEther } from 'viem';
import { explorerTx } from '../chain.js';

/**
 * "What just happened on chain" — shown after every transaction.
 * tx = { hash, status: 'pending'|'success'|'reverted'|'error', receipt?, events?, error? }
 */
export default function TxPanel({ tx }) {
  if (!tx) return null;
  const { hash, status, receipt, events = [], error } = tx;

  return (
    <aside className={`tx-panel tx-${status}`}>
      <h4>What just happened on chain</h4>
      {error && <p className="error">{error}</p>}
      {hash && (
        <dl>
          <dt>Transaction</dt>
          <dd>
            <a className="mono" href={explorerTx(hash)} target="_blank" rel="noreferrer">
              {hash.slice(0, 18)}…
            </a>
          </dd>
          <dt>Status</dt>
          <dd>{status === 'pending' ? 'Waiting for a validator to include it…' : status}</dd>
          {receipt && (
            <>
              <dt>Block</dt>
              <dd>#{receipt.blockNumber.toString()}</dd>
              <dt>Signed by</dt>
              <dd className="mono">{receipt.from}</dd>
              <dt>Gas used</dt>
              <dd>
                {receipt.gasUsed.toLocaleString()} units
                {receipt.effectiveGasPrice !== undefined &&
                  ` · ${formatEther(receipt.gasUsed * receipt.effectiveGasPrice)} TRUST`}
              </dd>
            </>
          )}
        </dl>
      )}
      {events.length > 0 && (
        <>
          <h5>Events emitted</h5>
          {events.map((e, i) => (
            <pre key={i} className="event">
              {e.eventName}(
              {Object.entries(e.args)
                .map(([k, v]) => `${k}: ${typeof v === 'bigint' ? v.toString() : v}`)
                .join(', ')}
              )
            </pre>
          ))}
        </>
      )}
    </aside>
  );
}
