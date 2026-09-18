import { useCallback, useEffect, useState } from 'react';
import { keccak256, stringToHex } from 'viem';
import { residentRegistryAbi, trustvillePassportAbi } from '../abi/generated.js';
import { contracts, explorerAddress, publicClient } from '../chain.js';
import { useRefresh } from '../refresh.js';
import { runTx } from '../tx.js';
import TxPanel from './TxPanel.jsx';

const registry = contracts.ResidentRegistry;
const passport = contracts.TrustvillePassport;

const MODULE_NAMES = {
  1: 'Resident',
  2: 'Passport',
  3: 'Town token',
  4: 'Provenance',
  5: 'Escrow',
  6: 'Auction',
  7: 'Certificate',
  8: 'Tickets',
};

/** Modules 1 and 2: identity you control, and a soulbound record of what you did. */
export default function TownHall({ wallet }) {
  const [resident, setResident] = useState(null);
  const [tokenId, setTokenId] = useState(0n);
  const [stamps, setStamps] = useState([]);
  const [tx, setTx] = useState(null);

  const { account } = wallet;

  const load = useCallback(async () => {
    if (!account || !registry) return;
    const r = await publicClient.readContract({
      address: registry,
      abi: residentRegistryAbi,
      functionName: 'residentOf',
      args: [account],
    });
    setResident(r);
    if (!passport) return;
    const [id, s] = await Promise.all([
      publicClient.readContract({ address: passport, abi: trustvillePassportAbi, functionName: 'passportOf', args: [account] }),
      publicClient.readContract({ address: passport, abi: trustvillePassportAbi, functionName: 'stampsOf', args: [account] }),
    ]);
    setTokenId(id);
    setStamps(s);
  }, [account]);

  useEffect(() => {
    load().catch(() => {});
  }, [load]);

  // Reload when any module's transaction lands.
  useRefresh(useCallback(() => {
    load().catch(() => {});
  }, [load]));

  if (!registry) {
    return (
      <section className="card" id="townhall">
        <div className="card-head">
          <h2>Town Hall</h2>
        </div>
        <p className="notice-empty">
          Not deployed yet. Instructor: run <span className="mono">script/DeployTown.s.sol</span>.
        </p>
      </section>
    );
  }

  const isResident = resident?.since > 0n && resident?.revokedAt === 0n;
  const revoked = resident?.revokedAt > 0n;
  const ready = account && wallet.onDidlab;

  // The credential document stays with you; only its hash goes on chain.
  const credentialHash = account ? keccak256(stringToHex(`trustville-resident:${account.toLowerCase()}`)) : null;

  const register = () =>
    runTx({
      wallet,
      address: registry,
      abi: residentRegistryAbi,
      functionName: 'register',
      args: [credentialHash],
      setTx,
      onDone: load,
    });

  const mintPassport = () =>
    runTx({
      wallet,
      address: passport,
      abi: trustvillePassportAbi,
      functionName: 'mint',
      setTx,
      onDone: load,
    });

  return (
    <section className="card" id="townhall">
      <div className="card-head">
        <h2>Town Hall · modules 1–2</h2>
        <p className="muted">
          Register as a resident, then mint a passport that records what you complete. The passport cannot be
          sold or transferred — that is what makes it worth anything.
        </p>
      </div>

      <div className="board">
        <div>
          <div className="module">
            <h3>1 · Resident record</h3>
            <p className="muted small">
              Your credential document stays with you. Only its hash goes on chain, so the town can prove the
              record is unchanged without holding your details.
            </p>
            {isResident ? (
              <p className="ok">
                Registered · hash <span className="mono">{resident.credentialHash.slice(0, 14)}…</span>
              </p>
            ) : revoked ? (
              <p className="error">Your residency was revoked.</p>
            ) : (
              <button className="btn" disabled={!ready || tx?.status === 'pending'} onClick={register}>
                Become a resident
              </button>
            )}
          </div>

          <div className="module">
            <h3>2 · Passport</h3>
            {tokenId > 0n ? (
              <>
                <p className="ok">Passport #{tokenId.toString()} · soulbound</p>
                <div className="stamps">
                  {stamps.map((m) => (
                    <span key={m} className="stamp">
                      {MODULE_NAMES[m] || `Module ${m}`}
                    </span>
                  ))}
                </div>
              </>
            ) : (
              <>
                <p className="muted small">Minting adds your first two stamps. Requires an active resident record.</p>
                <button className="btn" disabled={!ready || !isResident || tx?.status === 'pending'} onClick={mintPassport}>
                  Mint my passport
                </button>
              </>
            )}
          </div>

          <p className="muted small">
            Registry{' '}
            <a className="mono" href={explorerAddress(registry)} target="_blank" rel="noreferrer">
              {registry.slice(0, 10)}…
            </a>{' '}
            · Passport{' '}
            <a className="mono" href={explorerAddress(passport)} target="_blank" rel="noreferrer">
              {passport?.slice(0, 10)}…
            </a>
          </p>
        </div>
        <TxPanel tx={tx} />
      </div>
    </section>
  );
}
