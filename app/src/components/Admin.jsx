import { useCallback, useEffect, useState } from 'react';
import { keccak256, parseEther, stringToHex } from 'viem';
import {
  cropInsuranceAbi,
  grainLoansAbi,
  grainTokenAbi,
  propertyDeedsAbi,
  rainOracleAbi,
  residentRegistryAbi,
  townBankAbi,
  townTokenAbi,
} from '../abi/generated.js';
import { contracts, explorerAddress, publicClient } from '../chain.js';
import { useRefresh } from '../refresh.js';
import { runTx } from '../tx.js';
import TxPanel from './TxPanel.jsx';

/**
 * The town admin's controls.
 *
 * Why this exists: after the admin key was rotated into MetaMask, there was no way for the
 * admin to sign anything. Every admin call had to go through `cast --interactive`, which
 * means typing the key into a terminal -- the exact thing keeping it in MetaMask was
 * supposed to prevent. The explorer's write interface would have done the job, but it
 * needs verified contracts, and verification depends on a Blockscout microservice we do
 * not control.
 *
 * So the town carries its own admin surface. It signs with MetaMask like everything else,
 * and it is not a privileged back door: every function here is protected by a role check
 * in the contract. Hiding the panel from non-admins is a courtesy to the UI, not a
 * security boundary -- the contract refuses the call either way, which is the point, and
 * students are invited to try.
 */

const DEFAULT_ADMIN_ROLE = `0x${'0'.repeat(64)}`;

/** AccessControl is identical on every contract, so one small ABI covers all of them. */
const accessControlAbi = [
  {
    type: 'function',
    name: 'grantRole',
    inputs: [{ type: 'bytes32' }, { type: 'address' }],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'revokeRole',
    inputs: [{ type: 'bytes32' }, { type: 'address' }],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'renounceRole',
    inputs: [{ type: 'bytes32' }, { type: 'address' }],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'hasRole',
    inputs: [{ type: 'bytes32' }, { type: 'address' }],
    outputs: [{ type: 'bool' }],
    stateMutability: 'view',
  },
];

/**
 * Accepts a role NAME ("MINTER_ROLE"), a raw 32-byte hash, or nothing for the default
 * admin role. Typing the name is what people mean; hashing it here removes a step where
 * a wrong paste silently grants the wrong power.
 */
function roleValue(input) {
  const v = (input || '').trim();
  if (!v || /^(admin|default|default_admin_role)$/i.test(v)) return DEFAULT_ADMIN_ROLE;
  if (/^0x[0-9a-fA-F]{64}$/.test(v)) return v;
  return keccak256(stringToHex(v));
}

/** Settings that are a single admin-only call, grouped by the contract they live on. */
const SETTINGS = [
  {
    contract: 'GrainToken',
    abi: grainTokenAbi,
    fn: 'setCooldown',
    title: 'Harvest cooldown',
    help: 'Seconds a resident waits between harvests. 60 is the contract floor, 604800 the ceiling. Normal is 600 — lower it only while seeding, and put it back.',
    fields: [{ name: 'cooldown', label: 'Seconds', placeholder: '600', cast: (v) => BigInt(v) }],
  },
  {
    contract: 'TownBank',
    abi: townBankAbi,
    fn: 'setGrantAmount',
    title: 'Welcome grant',
    help: 'TVD a new resident may claim once. The supply cap still binds; this is the rate, not the limit.',
    fields: [{ name: 'amount', label: 'TVD', placeholder: '100', cast: parseEther }],
  },
  {
    contract: 'RainOracle',
    abi: rainOracleAbi,
    fn: 'setQuorum',
    title: 'Oracle quorum',
    help: 'Reports needed before a period can be settled. Between 2 and 9. Raising it makes the median harder to move and easier to stall.',
    fields: [{ name: 'quorum', label: 'Reports', placeholder: '2', cast: (v) => Number(v) }],
  },
  {
    contract: 'CropInsurance',
    abi: cropInsuranceAbi,
    fn: 'setTerms',
    title: 'Insurance terms',
    help: 'Applies to policies sold AFTER this transaction. Live policies keep the trigger they were sold with — that is deliberate.',
    fields: [
      { name: 'triggerMm', label: 'Drought below (mm)', placeholder: '10', cast: (v) => Number(v) },
      { name: 'premiumBps', label: 'Premium (bps)', placeholder: '500', cast: (v) => Number(v) },
    ],
  },
  {
    contract: 'GrainLoans',
    abi: grainLoansAbi,
    fn: 'setRate',
    title: 'Borrowing rate',
    help: 'Simple interest per year, in basis points. 1000 = 10%. Capped at 5000.',
    fields: [{ name: 'rateBps', label: 'Basis points', placeholder: '1000', cast: (v) => BigInt(v) }],
  },
  {
    contract: 'ResidentRegistry',
    abi: residentRegistryAbi,
    fn: 'setOpenRegistration',
    title: 'Open registration',
    help: 'While open, anyone may register themselves. Close it after a term to freeze the roll.',
    fields: [
      {
        name: 'open',
        label: 'Open?',
        options: [
          ['true', 'open'],
          ['false', 'closed'],
        ],
        cast: (v) => v === 'true',
      },
    ],
  },
  {
    contract: 'PropertyDeeds',
    abi: propertyDeedsAbi,
    fn: 'certify',
    title: 'Certify a deed',
    help: 'The town vouches that this owner really holds this property. Certification is cleared automatically the moment the deed is transferred.',
    fields: [{ name: 'id', label: 'Deed id', placeholder: '1', cast: (v) => BigInt(v) }],
  },
  {
    contract: 'TownToken',
    abi: townTokenAbi,
    fn: 'mint',
    title: 'Mint TVD',
    danger: true,
    help: 'Requires MINTER_ROLE, which the admin does not hold by default — grant it above, mint, then renounce it. Every step is public. See module 3.',
    fields: [
      { name: 'to', label: 'To', placeholder: '0x…' },
      { name: 'amount', label: 'TVD', placeholder: '1000', cast: parseEther },
    ],
  },
];

function Setting({ item, address, ready, send }) {
  const [values, setValues] = useState({});
  const set = (k) => (e) => setValues((v) => ({ ...v, [k]: e.target.value }));

  const submit = (e) => {
    e.preventDefault();
    let args;
    try {
      args = item.fields.map((f) => (f.cast ? f.cast(values[f.name] ?? '') : (values[f.name] ?? '')));
    } catch {
      return; // a malformed number: the browser's own validation already says so
    }
    send({ address, abi: item.abi, functionName: item.fn, args });
  };

  return (
    <div className="module">
      <h3>
        {item.title}
        {item.danger && <span className="stamp stamp-warn"> care</span>}
      </h3>
      <p className="muted small">{item.help}</p>
      <form className="post-form" onSubmit={submit}>
        {item.fields.map((f) =>
          f.options ? (
            <select key={f.name} value={values[f.name] ?? ''} onChange={set(f.name)} required>
              <option value="" disabled>
                {f.label}
              </option>
              {f.options.map(([v, label]) => (
                <option key={v} value={v}>
                  {label}
                </option>
              ))}
            </select>
          ) : (
            <input
              key={f.name}
              value={values[f.name] ?? ''}
              onChange={set(f.name)}
              placeholder={`${f.label}${f.placeholder ? ` — e.g. ${f.placeholder}` : ''}`}
              required
            />
          ),
        )}
        <button className="btn" disabled={!ready}>
          {item.fn}
        </button>
      </form>
      <p className="muted small mono">
        {item.contract} · {item.fn}
      </p>
    </div>
  );
}

export default function Admin({ wallet }) {
  const { account } = wallet;
  const [isAdmin, setIsAdmin] = useState(false);
  const [tx, setTx] = useState(null);

  const [roleContract, setRoleContract] = useState('TrustvillePassport');
  const [roleName, setRoleName] = useState('STAMPER_ROLE');
  const [roleTarget, setRoleTarget] = useState('');

  const registry = contracts.ResidentRegistry;

  const load = useCallback(async () => {
    if (!account || !registry) return setIsAdmin(false);
    try {
      const held = await publicClient.readContract({
        address: registry,
        abi: accessControlAbi,
        functionName: 'hasRole',
        args: [DEFAULT_ADMIN_ROLE, account],
      });
      setIsAdmin(Boolean(held));
    } catch {
      setIsAdmin(false);
    }
  }, [account, registry]);

  useEffect(() => {
    load().catch(() => {});
  }, [load]);
  useRefresh(useCallback(() => load().catch(() => {}), [load]));

  // Nothing to show for the people who cannot use it, which is almost everybody.
  if (!isAdmin) return null;

  const ready = account && wallet.onDidlab && tx?.status !== 'pending';
  const send = (opts) => runTx({ wallet, setTx, ...opts });

  const roleOp = (functionName) => {
    const address = contracts[roleContract];
    if (!address) return;
    const target = functionName === 'renounceRole' ? account : roleTarget.trim();
    send({
      address,
      abi: accessControlAbi,
      functionName,
      args: [roleValue(roleName), target],
    });
  };

  const known = Object.keys(contracts).sort();

  return (
    <section className="card admin" id="admin">
      <div className="card-head">
        <h2>Town admin</h2>
        <p className="muted">
          You are holding the admin key, so this section is visible. Every function below is
          guarded by a role check inside the contract — hiding this panel from everyone else is
          tidiness, not security. Try calling any of it from another account and watch the
          contract refuse.
        </p>
      </div>

      <div className="board">
        <div>
          <div className="module">
            <h3>Roles</h3>
            <p className="muted small">
              Type a role name and it is hashed for you — <span className="mono">STAMPER_ROLE</span>{' '}
              rather than a 32-byte value pasted from somewhere. Leave it empty for the default
              admin role. Every stamping contract needs{' '}
              <span className="mono">STAMPER_ROLE</span> on the Passport after a redeploy, which is
              the single most forgotten step in this repository.
            </p>
            <div className="post-form">
              <select value={roleContract} onChange={(e) => setRoleContract(e.target.value)}>
                {known.map((n) => (
                  <option key={n} value={n}>
                    {n}
                  </option>
                ))}
              </select>
              <input
                value={roleName}
                onChange={(e) => setRoleName(e.target.value)}
                placeholder="Role — e.g. STAMPER_ROLE"
              />
              <input
                value={roleTarget}
                onChange={(e) => setRoleTarget(e.target.value)}
                placeholder="Address — 0x…"
              />
            </div>
            <div className="row">
              <button className="btn" disabled={!ready || !roleTarget} onClick={() => roleOp('grantRole')}>
                Grant
              </button>
              <button
                className="btn btn-ghost"
                disabled={!ready || !roleTarget}
                onClick={() => roleOp('revokeRole')}
              >
                Revoke
              </button>
              <button className="btn btn-ghost" disabled={!ready} onClick={() => roleOp('renounceRole')}>
                Renounce mine
              </button>
            </div>
            <p className="muted small">
              <b>Renounce mine</b> gives up the role on your own account and cannot be undone by
              you — only by someone who still holds the admin role on that contract. Read the button
              twice before pressing it.
            </p>
            {contracts[roleContract] && (
              <p className="muted small mono">
                <a href={explorerAddress(contracts[roleContract])} target="_blank" rel="noreferrer">
                  {contracts[roleContract]}
                </a>
              </p>
            )}
          </div>

          {SETTINGS.filter((s) => contracts[s.contract]).map((s) => (
            <Setting
              key={`${s.contract}.${s.fn}`}
              item={s}
              address={contracts[s.contract]}
              ready={ready}
              send={send}
            />
          ))}
        </div>

        <div>
          <TxPanel tx={tx} />
        </div>
      </div>
    </section>
  );
}
