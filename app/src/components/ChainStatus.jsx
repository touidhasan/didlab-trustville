import { useEffect, useState } from 'react';
import { didlab, EXPLORER, publicClient } from '../chain.js';

/**
 * Live block height from whichever chain this build talks to — proof it is running.
 *
 * The name and id come from the same config as the RPC url, deliberately. They used to be
 * the hardcoded string "DIDLab 252501", which meant a build accidentally pointed at a local
 * anvil chain still announced itself as DIDLab while every request went to 127.0.0.1. The
 * status bar reported "Chain unreachable" and named the wrong chain in the same breath.
 * A status indicator that cannot be wrong about what it is watching is worth the two lines.
 */
export default function ChainStatus() {
  const [block, setBlock] = useState(null);
  const [down, setDown] = useState(false);

  useEffect(() => {
    let stop = false;
    const load = () =>
      publicClient
        .getBlockNumber()
        .then((b) => {
          if (stop) return;
          setBlock(b);
          setDown(false);
        })
        .catch(() => !stop && setDown(true));
    load();
    const t = setInterval(load, 4000);
    return () => {
      stop = true;
      clearInterval(t);
    };
  }, []);

  return (
    <a className="chain-status" href={EXPLORER} target="_blank" rel="noreferrer">
      <span className={`dot ${down ? 'dot-down' : block ? 'dot-up' : ''}`} />
      {down ? 'Chain unreachable' : block ? `Block #${block.toLocaleString()}` : 'Connecting…'}
      <span className="muted">
        {' '}
        · {didlab.name} {didlab.id}
      </span>
    </a>
  );
}
