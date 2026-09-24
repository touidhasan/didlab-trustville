import { useCallback, useEffect, useState } from 'react';
import {
  encodeAbiParameters,
  encodeFunctionData,
  formatUnits,
  isAddress,
  keccak256,
  parseUnits,
  stringToHex,
} from 'viem';
import {
  townGovernorAbi,
  townTimelockAbi,
  townTokenAbi,
  townTreasuryAbi,
  voteTokenAbi,
} from '../abi/generated.js';
import { contracts, explorerAddress, publicClient } from '../chain.js';
import { useRefresh } from '../refresh.js';
import { runTx } from '../tx.js';
import TxPanel from './TxPanel.jsx';

const treasury = contracts.TownTreasury;
const governor = contracts.TownGovernor;
const timelock = contracts.TownTimelock;
const votes = contracts.VoteToken;
const token = contracts.TownToken;

const PROPOSAL_STATE = [
  'Pending',
  'Active',
  'Canceled',
  'Defeated',
  'Succeeded',
  'Queued',
  'Expired',
  'Executed',
];
const short = (a) => `${a.slice(0, 6)}…${a.slice(-4)}`;
const tvd = (v) => `${Number(formatUnits(v ?? 0n, 18)).toLocaleString()} TVD`;

/// The proposal id IS its content: keccak256 of the targets, values, calldatas and the
/// hash of the description. Identical content is always the same proposal — which is why
/// the same payment cannot be proposed twice without changing the wording.
const proposalIdOf = (targets, values, calldatas, description) =>
  BigInt(
    keccak256(
      encodeAbiParameters(
        [{ type: 'address[]' }, { type: 'uint256[]' }, { type: 'bytes[]' }, { type: 'bytes32' }],
        [targets, values, calldatas, keccak256(stringToHex(description))],
      ),
    ),
  );

/// Only the hash of the description is stored on chain, so the words have to survive
/// somewhere. This browser remembers them; the ProposalCreated event on the explorer is
/// the copy everyone else can read.
const remember = (id, description) => {
  try {
    localStorage.setItem(`trustville.proposal.${id}`, description);
  } catch {
    /* private mode, cleared storage — the explorer still has it */
  }
};
const recall = (id) => {
  try {
    return localStorage.getItem(`trustville.proposal.${id}`) ?? '';
  } catch {
    return '';
  }
};

/** Modules 11–12: a multisig treasury, and a DAO where a vote actually moves money. */
export default function Council({ wallet }) {
  const { account } = wallet;
  const ready = account && wallet.onDidlab;

  const [owners, setOwners] = useState([]);
  const [thresholdN, setThresholdN] = useState(0n);
  const [treasuryBalance, setTreasuryBalance] = useState(0n);
  const [payments, setPayments] = useState([]);

  const [power, setPower] = useState({ wrapped: 0n, votes: 0n, delegate: null });
  const [timelockBalance, setTimelockBalance] = useState(0n);
  const [proposals, setProposals] = useState([]);
  const [tx, setTx] = useState(null);

  const [payTo, setPayTo] = useState('');
  const [payAmount, setPayAmount] = useState('');
  const [wrapAmount, setWrapAmount] = useState('');
  const [propTo, setPropTo] = useState('');
  const [propAmount, setPropAmount] = useState('');
  const [propWhy, setPropWhy] = useState('');

  const load = useCallback(async () => {
    if (!treasury) return;
    const read = (address, abi, functionName, args) =>
      publicClient.readContract({ address, abi, functionName, args });

    const [ownerList, th, tb, n, tlb] = await Promise.all([
      read(treasury, townTreasuryAbi, 'owners'),
      read(treasury, townTreasuryAbi, 'threshold'),
      read(token, townTokenAbi, 'balanceOf', [treasury]),
      read(treasury, townTreasuryAbi, 'count'),
      read(token, townTokenAbi, 'balanceOf', [timelock]),
    ]);
    setOwners(ownerList);
    setThresholdN(th);
    setTreasuryBalance(tb);
    setTimelockBalance(tlb);

    const ids = [];
    for (let i = n; i > 0n && ids.length < 4; i--) ids.push(i);
    setPayments(
      await Promise.all(
        ids.map(async (id) => ({
          id,
          ...(await read(treasury, townTreasuryAbi, 'get', [id])),
          mine: account ? await read(treasury, townTreasuryAbi, 'confirmedBy', [id, account]) : false,
        })),
      ),
    );

    const propIds = await read(governor, townGovernorAbi, 'recentProposals', [4n]);
    setProposals(
      await Promise.all(
        propIds.map(async (id) => {
          const [state, deadline, snapshot, tally] = await Promise.all([
            read(governor, townGovernorAbi, 'state', [id]),
            read(governor, townGovernorAbi, 'proposalDeadline', [id]),
            read(governor, townGovernorAbi, 'proposalSnapshot', [id]),
            read(governor, townGovernorAbi, 'proposalVotes', [id]),
          ]);
          const mine = account ? await read(governor, townGovernorAbi, 'hasVoted', [id, account]) : false;
          return { id, state, deadline, snapshot, against: tally[0], forVotes: tally[1], mine };
        }),
      ),
    );

    if (!account) return;
    const [wrapped, myVotes, delegate] = await Promise.all([
      read(votes, voteTokenAbi, 'balanceOf', [account]),
      read(votes, voteTokenAbi, 'getVotes', [account]),
      read(votes, voteTokenAbi, 'delegates', [account]),
    ]);
    setPower({ wrapped, votes: myVotes, delegate });
  }, [account]);

  useEffect(() => {
    load().catch(() => {});
  }, [load]);
  useRefresh(
    useCallback(() => {
      load().catch(() => {});
    }, [load]),
  );

  if (!treasury) {
    return (
      <section className="card" id="council">
        <div className="card-head">
          <h2>Council</h2>
        </div>
        <p className="notice-empty">
          Not deployed yet. Instructor: run <span className="mono">script/DeployCouncil.s.sol</span>.
        </p>
      </section>
    );
  }

  const send = (opts) => runTx({ wallet, setTx, onDone: load, ...opts });
  const isOwner = owners.some((o) => account && o.toLowerCase() === account.toLowerCase());

  /* ----------------------------------------------------------- module 11 */
  const proposePayment = async (e) => {
    e.preventDefault();
    const data = encodeFunctionData({
      abi: townTokenAbi,
      functionName: 'transfer',
      args: [payTo, parseUnits(payAmount, 18)],
    });
    return send({
      address: treasury,
      abi: townTreasuryAbi,
      functionName: 'propose',
      args: [token, 0n, data, `pay ${payAmount} TVD`],
      onDone: async () => {
        setPayTo('');
        setPayAmount('');
        await load();
      },
    });
  };

  /* ----------------------------------------------------------- module 12 */
  const wrap = async (e) => {
    e.preventDefault();
    const amount = parseUnits(wrapAmount, 18);
    const ok = await send({
      address: token,
      abi: townTokenAbi,
      functionName: 'approve',
      args: [votes, amount],
    });
    if (!ok) return;
    return send({
      address: votes,
      abi: voteTokenAbi,
      functionName: 'depositAndSelfDelegate',
      args: [amount],
      onDone: async () => {
        setWrapAmount('');
        await load();
      },
    });
  };

  // A proposal is (targets, values, calldatas, description). Queue and execute must be
  // given exactly the same arrays, which is why the description matters so much.
  const proposalCall = (to, amount) => ({
    targets: [token],
    values: [0n],
    calldatas: [
      encodeFunctionData({ abi: townTokenAbi, functionName: 'transfer', args: [to, amount] }),
    ],
  });

  const propose = (e) => {
    e.preventDefault();
    const { targets, values, calldatas } = proposalCall(propTo, parseUnits(propAmount, 18));
    const description = `${propWhy} — pay ${propAmount} TVD to ${propTo}`;
    // Remember the description: without it nobody can queue or execute this proposal.
    remember(proposalIdOf(targets, values, calldatas, description), description);
    return send({
      address: governor,
      abi: townGovernorAbi,
      functionName: 'propose',
      args: [targets, values, calldatas, description],
      onDone: async () => {
        setPropTo('');
        setPropAmount('');
        setPropWhy('');
        await load();
      },
    });
  };

  const vote = (id, support) =>
    send({ address: governor, abi: townGovernorAbi, functionName: 'castVote', args: [id, support] });

  const advance = async (p, fn) => {
    const saved = recall(p.id);
    const description = window.prompt(
      saved
        ? 'The description, exactly as proposed. Only its hash is on chain, so one changed\ncharacter is a different proposal and this call will fail:'
        : 'This browser has no copy of the description. Find the ProposalCreated event on the\nexplorer and paste its description here, exactly:',
      saved,
    );
    if (!description) return;
    const match = description.match(/pay ([\d.]+) TVD to (0x[a-fA-F0-9]{40})/);
    if (!match) {
      window.alert('Could not read an amount and address out of that description.');
      return;
    }
    const { targets, values, calldatas } = proposalCall(match[2], parseUnits(match[1], 18));
    if (proposalIdOf(targets, values, calldatas, description) !== p.id) {
      window.alert(
        'That text does not hash to this proposal.\n\nThe id is keccak256 of the call plus the ' +
          'description hash, so a changed character — a hyphen for an em dash, a lower-cased ' +
          'address — produces a different proposal that does not exist.',
      );
      return;
    }
    return send({
      address: governor,
      abi: townGovernorAbi,
      functionName: fn,
      args: [targets, values, calldatas, keccak256(stringToHex(description))],
    });
  };

  return (
    <section className="card" id="council">
      <div className="card-head">
        <h2>Council · modules 11–12</h2>
        <p className="muted">
          Two ways to spend public money. The treasury trusts a few named signers and moves fast; the Council
          trusts token holders and moves slowly, in public. Neither is simply better.
        </p>
      </div>

      <div className="board">
        <div>
          {/* --------------------------------------------------- multisig */}
          <div className="module">
            <h3>11 · Multisig treasury</h3>
            <div className="figures">
              <div>
                <span className="figure">{tvd(treasuryBalance)}</span>
                <span className="muted small">treasury holds</span>
              </div>
              <div>
                <span className="figure">
                  {thresholdN.toString()} of {owners.length}
                </span>
                <span className="muted small">signatures needed</span>
              </div>
            </div>
            <p className="muted small">
              Signers: {owners.map((o) => short(o)).join(', ') || 'none'}
              {isOwner && ' · you are a signer'}
            </p>
            {isOwner && (
              <form onSubmit={proposePayment} className="post-form">
                <input value={payTo} onChange={(e) => setPayTo(e.target.value)} placeholder="0x… payee" disabled={!ready} />
                <input value={payAmount} onChange={(e) => setPayAmount(e.target.value)} placeholder="TVD" inputMode="decimal" style={{ maxWidth: 100 }} disabled={!ready} />
                <button className="btn" disabled={!ready || !isAddress(payTo) || !(Number(payAmount) > 0)}>
                  Propose payment
                </button>
              </form>
            )}
            <ul className="notices">
              {payments.length === 0 && <li className="muted">No payments proposed yet.</li>}
              {payments.map((p) => (
                <li key={p.id.toString()}>
                  <span>
                    <b>#{p.id.toString()}</b> {p.memo} · to {short(p.to)} ·{' '}
                    {p.executed ? 'executed' : `${p.confirmations}/${thresholdN.toString()} signed`}
                  </span>
                  {ready && !p.executed && (
                    <span className="row">
                      {isOwner && !p.mine && (
                        <button className="btn small-btn" onClick={() => send({ address: treasury, abi: townTreasuryAbi, functionName: 'confirm', args: [p.id] })}>
                          Confirm
                        </button>
                      )}
                      {isOwner && p.mine && (
                        <button className="btn btn-ghost small-btn" onClick={() => send({ address: treasury, abi: townTreasuryAbi, functionName: 'revokeConfirmation', args: [p.id] })}>
                          Withdraw my signature
                        </button>
                      )}
                      {p.confirmations >= Number(thresholdN) && (
                        <button className="btn small-btn" onClick={() => send({ address: treasury, abi: townTreasuryAbi, functionName: 'execute', args: [p.id] })}>
                          Execute
                        </button>
                      )}
                    </span>
                  )}
                </li>
              ))}
            </ul>
          </div>

          {/* ---------------------------------------------------- the DAO */}
          <div className="module">
            <h3>12 · Town governance</h3>
            <div className="figures">
              <div>
                <span className="figure">{tvd(timelockBalance)}</span>
                <span className="muted small">under the Council</span>
              </div>
              <div>
                <span className="figure">{tvd(power.votes)}</span>
                <span className="muted small">your voting power</span>
              </div>
              <div>
                <span className="figure">{tvd(power.wrapped)}</span>
                <span className="muted small">your vTVD</span>
              </div>
            </div>
            {power.wrapped > 0n && power.votes === 0n && (
              <p className="error">
                You hold vTVD but delegated to nobody, so your tokens count for nothing. Delegate to yourself.
              </p>
            )}
            <form onSubmit={wrap} className="post-form">
              <input value={wrapAmount} onChange={(e) => setWrapAmount(e.target.value)} placeholder="TVD to wrap" inputMode="decimal" style={{ maxWidth: 140 }} disabled={!ready} />
              <button className="btn" disabled={!ready || !(Number(wrapAmount) > 0)}>
                Wrap &amp; delegate to me
              </button>
              {power.wrapped > 0n && (
                <button
                  type="button"
                  className="btn btn-ghost"
                  onClick={() => send({ address: votes, abi: voteTokenAbi, functionName: 'withdrawTo', args: [account, power.wrapped] })}
                >
                  Unwrap all
                </button>
              )}
            </form>

            <form onSubmit={propose} className="post-form">
              <input value={propWhy} onChange={(e) => setPropWhy(e.target.value)} placeholder="What is it for?" disabled={!ready} />
              <input value={propTo} onChange={(e) => setPropTo(e.target.value)} placeholder="0x… payee" disabled={!ready} />
              <input value={propAmount} onChange={(e) => setPropAmount(e.target.value)} placeholder="TVD" inputMode="decimal" style={{ maxWidth: 90 }} disabled={!ready} />
              <button className="btn" disabled={!ready || !isAddress(propTo) || !(Number(propAmount) > 0) || !propWhy.trim()}>
                Propose
              </button>
            </form>

            <ul className="notices">
              {proposals.length === 0 && <li className="muted">No proposals yet.</li>}
              {proposals.map((p) => (
                <li key={p.id.toString()}>
                  <span>
                    <b>#{p.id.toString().slice(0, 8)}…</b> · {PROPOSAL_STATE[p.state]} · for {tvd(p.forVotes)} ·
                    against {tvd(p.against)}
                    {p.mine && ' · you voted'}
                  </span>
                  {ready && (
                    <span className="row">
                      {p.state === 1 && !p.mine && (
                        <>
                          <button className="btn small-btn" onClick={() => vote(p.id, 1)}>
                            Vote for
                          </button>
                          <button className="btn btn-ghost small-btn" onClick={() => vote(p.id, 0)}>
                            Vote against
                          </button>
                        </>
                      )}
                      {p.state === 4 && (
                        <button className="btn small-btn" onClick={() => advance(p, 'queue')}>
                          Queue
                        </button>
                      )}
                      {p.state === 5 && (
                        <button className="btn small-btn" onClick={() => advance(p, 'execute')}>
                          Execute
                        </button>
                      )}
                    </span>
                  )}
                </li>
              ))}
            </ul>
            <p className="muted small">
              Treasury{' '}
              <a className="mono" href={explorerAddress(treasury)} target="_blank" rel="noreferrer">
                {treasury.slice(0, 10)}…
              </a>{' '}
              · Governor{' '}
              <a className="mono" href={explorerAddress(governor)} target="_blank" rel="noreferrer">
                {governor?.slice(0, 10)}…
              </a>{' '}
              · Timelock{' '}
              <a className="mono" href={explorerAddress(timelock)} target="_blank" rel="noreferrer">
                {timelock?.slice(0, 10)}…
              </a>
            </p>
          </div>
        </div>
        <TxPanel tx={tx} />
      </div>
    </section>
  );
}
