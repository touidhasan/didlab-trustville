import { useCallback, useEffect, useMemo, useState } from 'react';
import { certificateRegistryAbi, privacyLabAbi } from '../abi/generated.js';
import { contracts, explorerAddress, publicClient } from '../chain.js';
import { useRefresh } from '../refresh.js';
import { runTx } from '../tx.js';
import { commitmentOf, nullifierOf, randomSecret } from '../zk/tree.js';
import { buildProof, hashSignal, preload } from '../zk/prove.js';
import GuideLinks from './GuideLinks.jsx';
import TxPanel from './TxPanel.jsx';

const lab = contracts.PrivacyLab;
const certs = contracts.CertificateRegistry;

/** Topics exist so a nullifier can be "one post per member per conversation". */
const TOPICS = [
  { id: 1n, name: 'Teaching and assessment' },
  { id: 2n, name: 'Buildings and facilities' },
  { id: 3n, name: 'Safety' },
  { id: 4n, name: 'Anything else' },
];

const MAX_LENGTH = 280;
const short = (a) => `${a.slice(0, 6)}…${a.slice(-4)}`;
const hex = (v) => '0x' + v.toString(16).padStart(64, '0');

/** One key per deployment: a redeployed lab has a different tree and a stale secret in it. */
const storageKey = (address) => `trustville.zk.secret.${address?.toLowerCase()}`;

function readStoredSecret(address) {
  try {
    const raw = localStorage.getItem(storageKey(address));
    return raw ? BigInt(raw) : null;
  } catch {
    return null; // private window, blocked storage — the panel still works, nothing is kept
  }
}

function writeStoredSecret(address, secret) {
  try {
    localStorage.setItem(storageKey(address), secret.toString());
  } catch {
    /* nothing to do; the student has been told to keep their own copy */
  }
}

/**
 * Module 16 — the Privacy Lab.
 *
 * Two transactions, deliberately far apart in time and signed by different accounts.
 * Enrolling is public and proves entitlement; posting proves membership and names nobody.
 * Everything between them — the secret, the Merkle path, the proof — is computed here, in
 * this browser, and none of it is sent anywhere.
 */
export default function PrivacyLab({ wallet }) {
  const { account } = wallet;
  const ready = account && wallet.onDidlab;

  const [enrolments, setEnrolments] = useState([]);
  const [posts, setPosts] = useState([]);
  const [myCerts, setMyCerts] = useState([]);
  const [certId, setCertId] = useState('');

  const [secret, setSecret] = useState(null);
  const [revealed, setRevealed] = useState(false);
  const [savedIt, setSavedIt] = useState(false);
  const [restore, setRestore] = useState('');

  const [topic, setTopic] = useState(TOPICS[0].id.toString());
  const [text, setText] = useState('');
  const [proof, setProof] = useState(null);
  const [proving, setProving] = useState('');
  const [proveError, setProveError] = useState('');
  const [acceptLink, setAcceptLink] = useState(false);
  const [tx, setTx] = useState(null);

  useEffect(() => {
    if (lab) setSecret(readStoredSecret(lab));
  }, []);

  const leaves = useMemo(() => enrolments.map((e) => e.commitment), [enrolments]);
  const commitment = useMemo(() => (secret === null ? null : commitmentOf(secret)), [secret]);
  const leafIndex = useMemo(
    () => (commitment === null ? -1 : leaves.findIndex((l) => l === commitment)),
    [leaves, commitment],
  );
  const enrolled = leafIndex >= 0;

  /**
   * The enrolment list comes from events, sorted by the leaf index the contract assigned —
   * never by the order the node happened to return them. Insertion order IS the tree, and a
   * tree built in a different order has a different root, which surfaces much later as an
   * unhelpful `UnknownRoot`.
   *
   * A production system would read this from an indexer instead of scanning the chain. Note
   * what that costs: the indexer then knows which leaf you asked about, which is most of
   * what the proof was hiding. The convenient architecture is the one that quietly removes
   * the privacy — see app/src/zk/tree.js.
   */
  const load = useCallback(async () => {
    if (!lab) return;
    const ev = (name) => privacyLabAbi.find((x) => x.type === 'event' && x.name === name);

    const [enrolLogs, postLogs] = await Promise.all([
      publicClient.getLogs({ address: lab, event: ev('Enrolled'), fromBlock: 0n, toBlock: 'latest' }),
      publicClient.getLogs({ address: lab, event: ev('AnonymousPost'), fromBlock: 0n, toBlock: 'latest' }),
    ]);

    setEnrolments(
      enrolLogs
        .map((l) => ({
          by: l.args.by,
          commitment: l.args.commitment,
          leafIndex: Number(l.args.leafIndex),
          certificateId: l.args.certificateId,
        }))
        .sort((a, b) => a.leafIndex - b.leafIndex),
    );

    setPosts(
      postLogs
        .map((l) => ({
          topic: l.args.topic,
          nullifierHash: l.args.nullifierHash,
          text: l.args.text,
          block: l.blockNumber,
        }))
        .sort((a, b) => Number(b.block - a.block))
        .slice(0, 8),
    );

    if (!account || !certs) return setMyCerts([]);
    const held = await publicClient.readContract({
      address: certs,
      abi: certificateRegistryAbi,
      functionName: 'certificatesOf',
      args: [account],
    });
    const rows = await Promise.all(
      held.map(async (id) => {
        const [valid, used] = await Promise.all([
          publicClient.readContract({ address: certs, abi: certificateRegistryAbi, functionName: 'isValid', args: [id] }),
          publicClient.readContract({ address: lab, abi: privacyLabAbi, functionName: 'certificateEnrolled', args: [id] }),
        ]);
        const c = await publicClient.readContract({ address: certs, abi: certificateRegistryAbi, functionName: 'get', args: [id] });
        return { id, valid, used, course: c.course };
      }),
    );
    setMyCerts(rows);
  }, [account]);

  useEffect(() => {
    load().catch(() => {});
  }, [load]);
  useRefresh(
    useCallback(() => {
      load().catch(() => {});
    }, [load]),
  );

  const usable = myCerts.filter((c) => c.valid && !c.used);
  useEffect(() => {
    if (!certId && usable.length) setCertId(usable[0].id.toString());
  }, [usable, certId]);

  /* -------------------------------------------------------------------------- enrol */

  const makeSecret = () => {
    const s = randomSecret();
    setSecret(s);
    setRevealed(true);
    setSavedIt(false);
    writeStoredSecret(lab, s);
  };

  const useRestored = () => {
    try {
      const s = BigInt(restore.trim());
      if (s <= 0n) throw new Error('not a secret');
      setSecret(s);
      setRestore('');
      setSavedIt(true);
      writeStoredSecret(lab, s);
    } catch {
      setProveError('That is not a secret this lab produced.');
    }
  };

  const enrol = (ev) => {
    ev.preventDefault();
    if (!wallet.walletClient || commitment === null) return;
    return runTx({
      wallet,
      address: lab,
      abi: privacyLabAbi,
      functionName: 'enrol',
      args: [BigInt(certId), commitment],
      setTx,
      onDone: load,
    });
  };

  /* --------------------------------------------------------------------- prove, post */

  const nullifierHash = useMemo(
    () => (secret === null ? null : nullifierOf(secret, BigInt(topic))),
    [secret, topic],
  );

  const prove = async (ev) => {
    ev.preventDefault();
    setProveError('');
    setProof(null);
    try {
      // A ten-second proof that the contract will refuse anyway is a waste of ten seconds.
      const used = await publicClient.readContract({
        address: lab,
        abi: privacyLabAbi,
        functionName: 'nullifierUsed',
        args: [nullifierHash],
      });
      if (used) {
        setProveError(
          'You have already posted on this topic. One nullifier per secret per topic — that is ' +
            'what stops a member voting twice, and it applies to you as much as to anyone.',
        );
        return;
      }

      setProving('starting');
      const p = await buildProof({
        secret,
        topic: BigInt(topic),
        text,
        leaves,
        leafIndex,
        onProgress: setProving,
      });

      // The root must still be one the contract recognises. It keeps the last 32, so this
      // only fails if the class enrolled en masse while the proof was being built.
      const known = await publicClient.readContract({
        address: lab,
        abi: privacyLabAbi,
        functionName: 'isKnownRoot',
        args: [p.root],
      });
      if (!known) {
        setProveError('The root moved out of the contract\'s window while proving. Prove again.');
        return;
      }
      setProof(p);
    } catch (e) {
      setProveError(e.message || String(e));
    } finally {
      setProving('');
    }
  };

  const senderIsEnrolled = Boolean(account && enrolments.some((e) => e.by?.toLowerCase() === account.toLowerCase()));

  const post = (ev) => {
    ev.preventDefault();
    if (!wallet.walletClient || !proof) return;
    return runTx({
      wallet,
      address: lab,
      abi: privacyLabAbi,
      functionName: 'postAnonymously',
      args: [proof.pA, proof.pB, proof.pC, proof.root, proof.nullifierHash, BigInt(topic), text],
      setTx,
      onDone: async () => {
        setProof(null);
        setText('');
        await load();
      },
    });
  };

  if (!lab) {
    return (
      <section className="card" id="privacy">
        <div className="card-head">
          <h2>The Privacy Lab</h2>
          <GuideLinks ids={[16]} />
        </div>
        <p className="notice-empty">
          Not deployed yet. Instructor: build the circuit with <span className="mono">npm run circuit</span>, then
          run <span className="mono">script/DeployPrivacyLab.s.sol</span>.
        </p>
      </section>
    );
  }

  const members = enrolments.length;

  return (
    <section className="card zk" id="privacy">
      <div className="card-head">
        <h2>The Privacy Lab</h2>
        <GuideLinks ids={[16]} />
        <p className="muted">
          Module 7 can prove you hold a certificate — by showing the whole certificate, tied to an address whose
          entire history is public. Here you prove the same thing and reveal nothing else: not which certificate,
          not which course, not who you are.
        </p>
      </div>

      <div className="anon-set">
        <div>
          <span className="figure">{members}</span>
          <span className="muted small">
            {members === 0
              ? 'Nobody has enrolled. There is nothing to hide among.'
              : members === 1
                ? 'One member. A proof of membership identifies that member — the mathematics is perfect and the anonymity is zero.'
                : `You are hiding among ${members}. That number, not the cryptography, is your privacy.`}
          </span>
        </div>
        <p className="muted small">
          Contract{' '}
          <a className="mono" href={explorerAddress(lab)} target="_blank" rel="noreferrer">
            {short(lab)}
          </a>{' '}
          · proving happens in this browser · the secret is never sent anywhere
        </p>
      </div>

      <div className="board">
        <div>
          {/* ------------------------------------------------------------- step one */}
          <div className="module">
            <h3>1 · Enrol, in public</h3>
            <p className="muted small">
              Signed by you, with a certificate you hold. Everyone can see that you joined — that is the point,
              it is what proves you are entitled to be in the set.
            </p>

            {secret === null ? (
              <>
                <button className="btn" onClick={makeSecret} disabled={!ready}>
                  Generate a secret
                </button>
                <details className="small">
                  <summary>I already have a secret</summary>
                  <div className="post-form">
                    <input
                      value={restore}
                      onChange={(e) => setRestore(e.target.value)}
                      placeholder="paste the long number you saved"
                    />
                    <button className="btn btn-ghost small-btn" onClick={useRestored}>
                      Use it
                    </button>
                  </div>
                </details>
              </>
            ) : (
              <>
                <p className="secret-box">
                  {revealed ? (
                    <span className="mono">{secret.toString()}</span>
                  ) : (
                    <button className="btn btn-ghost small-btn" onClick={() => setRevealed(true)}>
                      Show my secret
                    </button>
                  )}
                </p>
                <p className="muted small">
                  Copy this somewhere safe. It lives in this browser's local storage, which means two things:
                  clearing site data destroys it permanently and no one can recover it, and anyone who can open
                  this browser has it. There is no reset — a lost secret is a membership you can never use again,
                  and a leaked one is an identity someone else can speak with.
                </p>
                <p className="mono small muted">commitment {short(hex(commitment))}</p>
              </>
            )}

            {secret !== null && !enrolled && (
              <form onSubmit={enrol} className="post-form">
                <select value={certId} onChange={(e) => setCertId(e.target.value)} disabled={!ready || !usable.length}>
                  {usable.length === 0 && <option value="">no unused valid certificate</option>}
                  {usable.map((c) => (
                    <option key={c.id.toString()} value={c.id.toString()}>
                      #{c.id.toString()} · {c.course}
                    </option>
                  ))}
                </select>
                <label className="check small">
                  <input type="checkbox" checked={savedIt} onChange={(e) => setSavedIt(e.target.checked)} />
                  I have saved my secret
                </label>
                <button className="btn" disabled={!ready || !usable.length || !savedIt || tx?.status === 'pending'}>
                  Enrol
                </button>
              </form>
            )}

            {enrolled && (
              <p className="muted small">
                Enrolled as leaf #{leafIndex}. One certificate is one membership — enrol a second and a single
                holder could speak as a crowd, which is the whole reason module 7 is a prerequisite here.
              </p>
            )}
          </div>

          {/* ------------------------------------------------------------- step two */}
          <div className="module">
            <h3>2 · Post, as nobody in particular</h3>
            {!enrolled ? (
              <p className="muted small">Enrol first. There is nothing to prove membership of yet.</p>
            ) : (
              <>
                <form onSubmit={prove} className="post-form">
                  <select value={topic} onChange={(e) => setTopic(e.target.value)}>
                    {TOPICS.map((t) => (
                      <option key={t.id.toString()} value={t.id.toString()}>
                        {t.name}
                      </option>
                    ))}
                  </select>
                  <input
                    value={text}
                    maxLength={MAX_LENGTH}
                    onChange={(e) => {
                      setText(e.target.value);
                      setProof(null); // the proof is bound to the exact text; a keystroke voids it
                    }}
                    onFocus={preload}
                    placeholder="the lifts in the science block have been broken for a month"
                  />
                  <button className="btn" disabled={!text.trim() || Boolean(proving)}>
                    {proving ? `Proving… ${proving}` : 'Build the proof'}
                  </button>
                </form>
                <p className="muted small">
                  {MAX_LENGTH - text.length} characters left · one post per topic, because your nullifier for this
                  topic is {nullifierHash ? short(hex(nullifierHash)) : '…'} and the contract remembers it
                </p>
                {proveError && <p className="error small">{proveError}</p>}

                {proof && (
                  <>
                    <p className="muted small">
                      Proved in {proof.seconds.toFixed(1)}s, on this machine. The proof says: someone whose
                      commitment is a leaf under root {short(hex(proof.root))} is saying exactly this sentence. It
                      does not say which leaf.
                    </p>
                    {senderIsEnrolled && (
                      <label className="check small stamp-warn">
                        <input type="checkbox" checked={acceptLink} onChange={(e) => setAcceptLink(e.target.checked)} />
                        This account, {short(account)}, is on the enrolment list. Sending from it puts the post and
                        an enrolment in the same transaction record. Switch MetaMask to an account that never
                        enrolled — or tick this to publish the link anyway.
                      </label>
                    )}
                    <button
                      className="btn"
                      onClick={post}
                      disabled={!ready || tx?.status === 'pending' || (senderIsEnrolled && !acceptLink)}
                    >
                      Post anonymously
                    </button>
                  </>
                )}
              </>
            )}
          </div>

          {/* ------------------------------------------------------------ the record */}
          <div className="module">
            <h3>What the chain shows</h3>
            <ul className="notices">
              {posts.length === 0 && <li className="muted">Nothing posted yet.</li>}
              {posts.map((p) => (
                <li key={p.nullifierHash.toString()}>
                  <span>{p.text}</span>
                  <span className="muted small mono">
                    {TOPICS.find((t) => t.id === p.topic)?.name ?? `topic ${p.topic}`} · nullifier{' '}
                    {short(hex(p.nullifierHash))} · block #{p.block.toString()}
                  </span>
                </li>
              ))}
            </ul>
            <p className="muted small">
              No author, anywhere — not in the event, not in the arguments. What the record does hold is the
              sender who paid the gas, so look at that on the explorer and ask yourself what it tells you. That
              question is the module.
            </p>
            {enrolments.length > 0 && (
              <details className="small">
                <summary>The enrolment list ({enrolments.length})</summary>
                <ul className="notices">
                  {enrolments.map((e) => (
                    <li key={e.leafIndex}>
                      <span className="mono small">
                        #{e.leafIndex} · {short(e.by)} · {short(hex(e.commitment))}
                      </span>
                    </li>
                  ))}
                </ul>
                <p className="muted small">
                  Public by design. Everyone can see who could have posted; nobody can see who did.
                </p>
              </details>
            )}
          </div>
        </div>

        <TxPanel tx={tx} />
      </div>
    </section>
  );
}
