# Lab 1 · Shipping your first change

**Deliverable:** one merged pull request · **Time:** two hours

Your first week on any team is not spent writing clever code. It is spent getting the
project running, reading enough of it to find where a change belongs, and landing something
small without breaking anything. That is this lab.

## Setup (do this before the session if you can)

```bash
git clone <your fork>
cd didlab-trustville/contracts
forge install foundry-rs/forge-std --no-git
forge install OpenZeppelin/openzeppelin-contracts@v5.0.2 --no-git
cd .. && npm run local
```

You should have a private Trustville on localhost with 22 contracts deployed. Import the
anvil account the script prints, add the network to MetaMask, and complete the onboarding
steps in the UI. **If this does not work, nothing else in the course does** — fix it first
and write the incident up if it took real effort.

## The job

Two changes to the onboarding and Town Hall areas.

### 1. The network name is a lie

`Onboarding.jsx` tells every user to "Switch to the DIDLab network". Run against a local
chain and it still says DIDLab, while the wallet is being asked to add *Local Trustville*.

Fix it so every user-visible mention of the network reads from the configured chain rather
than a literal. `app/src/chain.js` already knows the name.

Hardcoded strings that duplicate configuration are one of the most common sources of
"works in dev, wrong in prod". Find them all — there is more than one.

### 2. Let a resident verify their own credential hash

Module 1 stores a hash of a credential document, never the document. Nothing in the UI lets
anyone check that the hash corresponds to what they hold.

Add to the Town Hall card, for a connected resident:

- their stored `credentialHash`, readable and copyable;
- an input where they paste their credential text;
- an immediate verdict: does it hash to the stored value or not.

The check happens **in the browser**. No transaction, no RPC call, no data leaving the
page. If it sends anything anywhere you have misunderstood the point of the feature.

## Acceptance criteria

- [ ] No user-visible string names a network that configuration did not supply.
- [ ] Running against a local chain, every network mention says the local chain's name.
- [ ] A registered resident sees their stored hash.
- [ ] Pasting the correct text shows a clear match; anything else shows a clear mismatch.
- [ ] A connected but **unregistered** address sees something sensible, not a crash and not
      a hash of zeros.
- [ ] A disconnected visitor sees the card without errors in the console.
- [ ] Verification performs no network request. Prove it in the PR with a screenshot of the
      network tab, or by explaining why there is nothing to show.
- [ ] `npm run build` succeeds and CI is green.

## Technical requirements

- Use `keccak256` and `stringToHex` from viem. Match exactly what `TownHall.jsx` does when
  it registers — if the two disagree, a correct document will fail to verify, and that is
  the bug students most often ship here.
- Follow the existing component patterns. Read `TownHall.jsx` and `Housing.jsx` first.
- No new dependencies.

## How your PR will be reviewed

A reviewer will check out your branch, run it against a local chain, and try to break the
feature: empty input, whitespace, a trailing newline, an address that never registered, a
wallet disconnected mid-use.

They will also read your description. "Fixed the network name and added hash verification"
is not a description — the diff says that. Tell them why you put the component where you
did, and what you decided about whitespace.

## Common ways this goes wrong

- **Trailing newline.** Paste from a text file and you get `\n` on the end, so the hash
  differs and the student concludes the feature is broken. Decide deliberately whether to
  trim, then document the decision.
- **Hashing the wrong thing.** Registration hashes a specific string. If you hash something
  else, verification always fails for honest users.
- **Rendering before the read resolves.** `credentialHash` is undefined for a moment.
  Undefined is not "no match", it is "not known yet", and they should look different.
- **A crash for a disconnected visitor.** Most of the site is readable without a wallet.
  Keep it that way.

## Out of scope

Do not change the contracts. Do not restyle the site. Do not fix unrelated things you find
— note them in the PR description instead, which is what a professional does with a bug
they were not sent to fix.

## Hand in

1. The PR, CI green, reviewed and approved by a classmate.
2. Your review of someone else's PR.
3. An incident write-up if anything broke — setup counts.
