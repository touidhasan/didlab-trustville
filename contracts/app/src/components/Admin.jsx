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

const ADMIN_OF = (what) => ({ name: 'DEFAULT_ADMIN_ROLE', what });

/**
 * Which roles exist on which contract, and what each one actually lets you do.
 *
 * Free text was a bad idea: a typo hashes to a role nobody holds, the transaction
 * succeeds, and you are left believing you granted something. Worse, a name that means
 * nothing to the reader ("CERTIFIER_ROLE") gets granted on the strength of sounding
 * harmless. Every entry here says what the holder can do, in the same place you pick it.
 *
 * Only contracts using AccessControl appear. TownSwap, the Governor, the Treasury and the
 * vote token have no roles at all, and offering them in a dropdown would be a lie.
 */
const ROLES = {
  ResidentRegistry: [
    ADMIN_OF('Grants every other role here, and opens or closes self-registration.'),
    {
      name: 'REGISTRAR_ROLE',
      what: 'Registers a resident on someone else’s behalf, and revokes a residency. For a student whose wallet will not cooperate.',
    },
  ],
  TrustvillePassport: [
    ADMIN_OF('Grants STAMPER_ROLE. Nothing else.'),
    {
      name: 'STAMPER_ROLE',
      what: 'Awards a module stamp. Every stamping contract needs this after a redeploy — the most forgotten step in this repository. Grant it to contracts, never to people.',
    },
  ],
  TownToken: [
    ADMIN_OF('Grants MINTER_ROLE — including to itself, which is the point module 3 makes.'),
    {
      name: 'MINTER_ROLE',
      what: 'Creates TVD from nothing, up to the supply cap. Held by TownBank so the rule is code rather than discretion. A person holding this is exactly what module 3 warns about.',
    },
  ],
  TownBank: [ADMIN_OF('Sets the welcome grant amount. Cannot mint directly.')],
  TownEscrow: [
    ADMIN_OF('Appoints arbiters.'),
    {
      name: 'ARBITER_ROLE',
      what: 'Decides a disputed order: pays the seller in full or refunds the buyer in full. Cannot send the money anywhere else, or change the amount.',
    },
  ],
  PropertyDeeds: [
    ADMIN_OF('Appoints certifiers.'),
    {
      name: 'CERTIFIER_ROLE',
      what: 'Vouches that a deed’s current owner really holds the property. The flag is cleared automatically the moment the deed is transferred.',
    },
  ],
  RentEscrow: [
    ADMIN_OF('Appoints arbiters.'),
    {
      name: 'ARBITER_ROLE',
      what: 'Splits a disputed tenancy deposit between landlord and tenant. The split must add up to the deposit exactly.',
    },
  ],
  TownCharity: [
    ADMIN_OF('Appoints arbiters.'),
    {
      name: 'ARBITER_ROLE',
      what: 'Approves a campaign milestone against its evidence, releasing that stage’s money — or rejects it, which cancels the campaign and opens pro-rata refunds.',
    },
  ],
  RainOracle: [
    ADMIN_OF('Sets the quorum and appoints reporters.'),
    {
      name: 'REPORTER_ROLE',
      what: 'Submits a rainfall reading for a finished period. One holder cannot move the median; a MAJORITY of holders decides the weather, and every policy settles on it.',
    },
  ],
  CropInsurance: [
    ADMIN_OF('Sets the trigger and premium for new policies, and withdraws surplus above the cover already promised.'),
  ],
  GrainToken: [
    ADMIN_OF('Sets the harvest cooldown. There is deliberately no minter: harvest() is the only way GRAIN comes into existence.'),
  ],
  GrainLoans: [ADMIN_OF('Sets the borrowing rate, capped at 50% a year.')],
  TownTimelock: [
    ADMIN_OF('Grants the three roles below. After deployment NOBODY should hold this — while someone does, the DAO is decorative. Check before trusting it.'),
    { name: 'PROPOSER_ROLE', what: 'Queues an operation. Only the Governor should hold it.' },
    {
      name: 'EXECUTOR_ROLE',
      what: 'Runs a queued operation once its delay has passed. Held by the zero address, meaning anyone may push the button.',
    },
    { name: 'CANCELLER_ROLE', what: 'Cancels a queued operation before it runs.' },
  ],
};

/** Settings that are a single admin-only call, grouped by the contract they live on. */
const SETTINGS = [
  {
    contract: 'TownToken',
    abi: townTokenAbi,
    fn: 'mint',
    title: 'Mint TVD',
    danger: true,
    help: 'Creates new TVD and sends it to one address. Requires MINTER_ROLE, which the admin does not hold by default — grant it above, mint, then renounce it. Every step is a public transaction. This is NOT the welcome grant below.',
    fields: [
      { name: 'to', label: 'To', placeholder: '0x…' },
      { name: 'amount', label: 'TVD', placeholder: '1000', cast: parseEther },
    ],
  },
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
    help: 'How much TVD EVERY future resident may claim once, for ever. This does not mint to anybody — to create TVD for one address, use Mint TVD above. The supply cap still binds; this is the rate, not the limit.',
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
  const [customRole, setCustomRole] = useState('');
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

  const chosenRole = roleName === '__custom' ? customRole : roleName;

  const roleOp = (functionName) => {
    const address = contracts[roleContract];
    if (!address) return;
    const target = functionName === 'renounceRole' ? account : roleTarget.trim();
    send({
      address,
      abi: accessControlAbi,
      functionName,
      args: [roleValue(chosenRole), target],
    });
  };

  const pickContract = (name) => {
    setRoleContract(name);
    setRoleName(ROLES[name]?.[0]?.name ?? 'DEFAULT_ADMIN_ROLE');
  };

  // Only contracts that actually use AccessControl. Offering the others would invite a
  // grantRole call that reverts for a reason nobody could guess from the UI.
  const known = Object.keys(ROLES).filter((n) => contracts[n]).sort();
  const available = ROLES[roleContract] ?? [];
  const described = available.find((r) => r.name === roleName);

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
              Pick the contract, then the role it defines — only contracts that use
              AccessControl are listed, and only the roles each one actually has. What the
              holder can do is written under your choice, because a role name alone tells you
              nothing about the power you are handing over.
            </p>
            <div className="post-form">
              <select value={roleContract} onChange={(e) => pickContract(e.target.value)}>
                {known.map((n) => (
                  <option key={n} value={n}>
                    {n}
                  </option>
                ))}
              </select>
              <select value={roleName} onChange={(e) => setRoleName(e.target.value)}>
                {available.map((r) => (
                  <option key={r.name} value={r.name}>
                    {r.name}
                  </option>
                ))}
                <option value="__custom">Something else…</option>
              </select>
              <input
                value={roleTarget}
                onChange={(e) => setRoleTarget(e.target.value)}
                placeholder="Address — 0x…"
              />
            </div>
            {roleName === '__custom' && (
              <div className="post-form">
                <input
                  value={customRole}
                  onChange={(e) => setCustomRole(e.target.value)}
                  placeholder="Role name or 0x… hash — for a contract this panel does not know"
                />
              </div>
            )}
            {described && <p className="muted small">{described.what}</p>}
            <p className="muted small mono">
              {chosenRole || 'DEFAULT_ADMIN_ROLE'} = {roleValue(chosenRole)}
            </p>
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
