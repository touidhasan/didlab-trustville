import { CHAIN_ID } from '../chain.js';

/**
 * What a stop shows when its contracts are not on this chain.
 *
 * Visitors get one plain sentence. The deploy instructions are for whoever runs the town,
 * so they sit behind a fold instead of greeting every student with a shell command.
 */
export default function NotDeployed({ what, script, extra }) {
  return (
    <div className="notice-empty">
      <p>{what} is not open in this town yet.</p>
      <details className="small">
        <summary>For whoever runs this town</summary>
        {extra && <p>{extra}</p>}
        <p>
          Run <span className="mono">{script}</span>, add the addresses to{' '}
          <span className="mono">deployments/{CHAIN_ID}.json</span>, then rebuild the site.
        </p>
      </details>
    </div>
  );
}
