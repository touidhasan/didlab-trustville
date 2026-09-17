import { useEffect, useState } from 'react';
import { EXPLORER, publicClient } from '../chain.js';

/** Live block height from eth.didlab.org — proof the chain is running. */
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
      <span className="muted"> · DIDLab 252501</span>
    </a>
  );
}
