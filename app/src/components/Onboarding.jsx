import { useState } from 'react';
import { formatEther } from 'viem';
import { didlab, explorerAddress, FAUCET_URL } from '../chain.js';

const SAFETY_KEY = 'trustville.safetyRead';

function readSafety() {
  try {
    return localStorage.getItem(SAFETY_KEY) === '1';
  } catch {
    return false;
  }
}

function Step({ n, title, done, active, children }) {
  return (
    <li className={`step ${done ? 'done' : ''} ${active ? 'active' : ''}`}>
      <div className="step-num">{done ? '✓' : n}</div>
      <div className="step-body">
        <h3>{title}</h3>
        {(active || done) && <div className="step-content">{children}</div>}
      </div>
    </li>
  );
}

const short = (a) => `${a.slice(0, 6)}…${a.slice(-4)}`;

export default function Onboarding({ wallet }) {
  const { hasProvider, account, onDidlab, balance, error, connect, switchToDidlab } = wallet;
  const [safetyRead, setSafetyRead] = useState(readSafety);
  const [copied, setCopied] = useState(false);

  const funded = balance !== null && balance > 0n;
  const done = [hasProvider, safetyRead, Boolean(account), onDidlab, funded];
  const current = done.indexOf(false); // -1 when everything is done

  const ackSafety = () => {
    setSafetyRead(true);
    try {
      localStorage.setItem(SAFETY_KEY, '1');
    } catch {
      /* storage unavailable — fine */
    }
  };

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(account);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch {
      /* ignore */
    }
  };

  return (
    <section className="card" id="start">
      <div className="card-head">
        <h2>Become a resident</h2>
        <p className="muted">Five steps, about five minutes. Every Trustville stop needs these.</p>
      </div>

      <ol className="steps">
        <Step n={1} title="Install MetaMask" done={done[0]} active={current === 0}>
          {hasProvider ? (
            <p>MetaMask detected.</p>
          ) : (
            <p>
              Install the MetaMask browser extension from{' '}
              <a href="https://metamask.io/download/" target="_blank" rel="noreferrer">
                metamask.io
              </a>
              , create a wallet, then reload this page.
            </p>
          )}
        </Step>

        <Step n={2} title="Read the key-safety rules" done={done[1]} active={current === 1}>
          <ul className="rules">
            <li>Your 12-word recovery phrase <b>is</b> your wallet. Write it on paper; never type it into a website or chat.</li>
            <li>Nobody from DIDLab will ever ask for it.</li>
            <li>Read every MetaMask pop-up: which site, which contract, what it can do with your tokens.</li>
            <li>This wallet is for the course chain. Don't reuse it for real money.</li>
          </ul>
          {!safetyRead && (
            <button className="btn" onClick={ackSafety}>
              I understand
            </button>
          )}
        </Step>

        <Step n={3} title="Connect your wallet" done={done[2]} active={current === 2}>
          {account ? (
            <p>
              Connected as{' '}
              <a href={explorerAddress(account)} target="_blank" rel="noreferrer" className="mono">
                {short(account)}
              </a>
            </p>
          ) : (
            <>
              <p>MetaMask will ask which account to share. This only reveals your address; it spends nothing.</p>
              <button className="btn" onClick={connect}>
                Connect MetaMask
              </button>
            </>
          )}
        </Step>

        <Step n={4} title="Switch to the DIDLab network" done={done[3]} active={current === 3}>
          {onDidlab ? (
            <p>You're on DIDLab (chain ID {didlab.id}).</p>
          ) : (
            <>
              <p>
                Adds the network to MetaMask: RPC <span className="mono">eth.didlab.org</span>, chain ID{' '}
                <span className="mono">{didlab.id}</span>, currency <span className="mono">TRUST</span>.
              </p>
              <button className="btn" onClick={switchToDidlab}>
                Add / switch network
              </button>
            </>
          )}
        </Step>

        <Step n={5} title="Get TRUST for gas" done={done[4]} active={current === 4}>
          <p>
            Balance:{' '}
            <b>{balance === null ? '—' : `${Number(formatEther(balance)).toLocaleString()} TRUST`}</b>
            {!funded && ' · this updates automatically.'}
          </p>
          {!funded && account && (
            <div className="row">
              <button className="btn btn-ghost" onClick={copy}>
                {copied ? 'Copied' : 'Copy my address'}
              </button>
              <a className="btn" href={FAUCET_URL} target="_blank" rel="noreferrer">
                Open the faucet
              </a>
            </div>
          )}
        </Step>
      </ol>

      {error && <p className="error">{error}</p>}
      {current === -1 && <p className="success">You're a Trustville resident. Pick a stop below.</p>}
    </section>
  );
}
