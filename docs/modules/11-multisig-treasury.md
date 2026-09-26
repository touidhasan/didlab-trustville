# Module 11 · Multisig treasury

| | |
| --- | --- |
| **Contract** | `TownTreasury.sol` |
| **Stop** | Council |
| **Pattern** | M-of-N multisignature wallet |
| **Stamp** | Module 11 (awarded to whoever **executes**) |

## The problem

A single key controls everything it owns, absolutely and irreversibly. One phishing email,
one compromised laptop, one person who leaves badly, and the town's funds are gone with no
appeal.

Organisations do not run bank accounts this way. They require two signatures on a cheque,
four eyes on a payment, a board resolution above a threshold. Those controls exist because
concentrating authority in one person is a known failure mode, not a hypothetical one.

## The idea

**M of N.** A shared account with several owners, where a payment happens only when at
least M of them agree. No single key is sufficient, and losing one key is survivable.

Trustville's treasury adds one more idea worth dwelling on: the treasury governs **itself**.
Adding an owner, removing one, or changing the threshold are ordinary proposals that the
treasury executes on itself. There is no admin.

## Key terms

**Multisig.** A contract requiring M signatures from N owners. In practice on Ethereum this
is a contract that counts confirmations, not cryptographic multi-signature.

**Threshold.** The M. Choosing it is a real trade-off: too low and it is barely a control,
too high and one absent owner freezes the treasury. 2-of-3 and 3-of-5 are the common
answers.

**Arbitrary call.** The proposal carries `to`, `value` and `data`, so it can call any
function on any contract, not merely send money. This is what makes a multisig a general
administrator rather than a wallet.

**Self-governance.** A contract whose only administrator is itself. Elegant, and one
misconfiguration away from being permanently stuck.

## How it works

```solidity
struct Payment {
    address to;
    uint256 value;   // native TRUST sent with the call
    bytes data;      // contract call, e.g. an ERC-20 transfer
    string memo;
    uint32 confirmations;
    bool executed;
}
```

| Function | Who | What |
| --- | --- | --- |
| `propose(to, value, data, memo)` | an owner | Creates it — and confirms it |
| `confirm(id)` | an owner | One confirmation each |
| `revokeConfirmation(id)` | an owner | Only before execution |
| `execute(id)` | **anyone** | Only at or above the threshold |
| `addOwner` / `removeOwner` / `setThreshold` | **the treasury itself** | Via a proposal |
| `encodeTransfer(to, amount)` | view helper | Builds ERC-20 call data |

Three sentences in that table carry most of the design.

**Proposing is confirming.** `propose` calls `_confirm(id, msg.sender)` at the end. An owner
who puts a payment forward has obviously agreed to it; making them send a second
transaction would be ceremony.

**Anyone may execute.** Not just an owner:

```solidity
function execute(uint256 id) external {
    if (p.confirmations < threshold) revert NotEnoughConfirmations(p.confirmations, threshold);
    p.executed = true;                  // set BEFORE the call
    (bool ok, bytes memory result) = p.to.call{value: p.value}(p.data);
```

The confirmations are the authority; the final transaction is just the button. This matters
practically — an owner with no gas cannot block a payment everyone agreed to — and
conceptually: authority lives in the recorded agreement, not in who happened to broadcast.

**`executed` is set before the external call.** Classic reentrancy guard by ordering. If the
recipient calls back into `execute`, the flag is already true and it reverts. Getting this
backwards is how the DAO was drained in 2016.

## The detail that matters

**The treasury is its own administrator:**

```solidity
function addOwner(address owner) external onlyTreasury { … }
```

`onlyTreasury` means `msg.sender == address(this)`. The only way to reach it is a proposal
whose `to` is the treasury and whose `data` encodes the call — so the existing owners must
agree, at threshold, to change who the owners are.

This is the right design and it is unforgiving. Set the threshold above the owner count and
nothing can ever be executed again, including the proposal that would lower it. Remove
owners until fewer remain than the threshold and you have done the same thing. The contract
guards the obvious cases with `BadThreshold`, but the general lesson stands: **a contract
that governs itself can lock itself out, and no one can help it.**

Before every owner or threshold change, ask: after this executes, can the remaining owners
still reach the threshold?

**Revocation before execution.** An owner can change their mind. Real multisigs need this —
information arrives, a proposal turns out to be a mistake — and it must be impossible after
execution, because by then the money is gone.

**The `memo` is for humans.** The `data` field is bytes; nobody reads calldata in a hurry.
The memo is what an owner sees before confirming, and it is unverified — a payment memoed
"office supplies" can encode anything. The correct habit is to decode `data`, not to read
`memo`. Teach yourself to distrust it now.

## Walk through it

1. The treasury is 2-of-3 with the instructor and two students as owners.
2. **Owner A:** propose a TVD transfer. Use `encodeTransfer(recipient, amount)` to build the
   data, and give it an honest memo.
3. Check the proposal. One confirmation — A's own.
4. **Try to execute.** `NotEnoughConfirmations(1, 2)`.
5. **Owner B:** confirm. Now two.
6. **Anyone at all — a non-owner:** execute. It works.
7. Try to execute again. `AlreadyExecuted`.

Then the self-governance path:

8. Propose a call to the treasury itself, encoding `addOwner(newAddress)`.
9. Confirm and execute. The owner set changed with no admin anywhere.
10. Before you do it, work out what the threshold will mean afterwards.

## What actually happened on chain

```
PaymentProposed(id: 4, proposer: 0x…, to: 0x…, value: 0, memo: "grant to the charity")
PaymentConfirmed(id: 4, owner: 0x…, confirmations: 1)
PaymentConfirmed(id: 4, owner: 0x…, confirmations: 2)
PaymentExecuted(id: 4, to: 0x…, result: 0x…01)
Stamped(tokenId: …, moduleId: 11, by: townTreasury)
```

The `result` bytes are the return value of the inner call — `0x…01` here is an ERC-20
`transfer` returning true. When an execution fails, `CallFailed(reason)` carries the inner
revert data, which is the only way to find out why a proposal that looked fine did not work.

## When a plain database is better

A company bank account with dual authorisation does this, with a bank behind it, reversal
for fraud, and a regulator. For most organisations that is simply better.

A multisig earns its place when **the assets are on chain anyway** — there is no bank for
tokens — when the signers are in different countries or organisations with no shared
institution, or when the control itself must be publicly auditable. Note that a large
fraction of serious on-chain treasuries are multisigs rather than DAOs, because the DAO
(module 12) is slower and its own security model is harder.

## What this does not fix

- **Compromise of M keys.** If the same phishing campaign catches two of three owners, the
  threshold bought you nothing. Signers should differ in device, location and habits.
- **Collusion.** M owners who agree to steal are indistinguishable from M owners who agree
  to pay.
- **Sending to the wrong address.** Everyone confirms the same mistake.
- **Malicious calldata.** See the memo warning above.
- **Owner absence.** N−M owners unavailable and the treasury is frozen until they return.

## Security checklist

- [ ] Can a non-owner propose or confirm?
- [ ] Can one owner confirm the same payment twice?
- [ ] Is `executed` set before the external call?
- [ ] Can the threshold be set above the owner count, now or after a removal?
- [ ] Can an owner revoke after execution?
- [ ] Does the reentrancy path through a hostile recipient reach anything?
- [ ] Who, in the end, can add an owner — and is there any path that is not a proposal?

## Extend it

1. Add a timelock: executable only after a delay from reaching the threshold. Say what
   attack that stops and what it costs in an emergency. (Module 12 does exactly this.)
2. Add per-proposal expiry, so a stale confirmation set cannot be executed months later
   under different circumstances.
3. Add spending tiers — 1-of-3 below 10 TVD, 3-of-3 above 1000 — and notice you have just
   reinvented a corporate delegation of authority.
4. Decode `data` in the front end and show owners a human-readable summary before they
   confirm. This is the single highest-value improvement, and real multisig interfaces have
   spent years on it.

## Further reading

- [Safe (formerly Gnosis Safe)](https://docs.safe.global/) — the multisig most on-chain
  treasuries actually use. Compare its design with this one.
- [Reentrancy](https://docs.soliditylang.org/en/latest/security-considerations.html#reentrancy)
- [`abi.encodeWithSignature`](https://docs.soliditylang.org/en/latest/units-and-global-variables.html#abi-encoding-and-decoding-functions)

**Next:** [Module 12 · DAO governance →](12-dao-governance.md)
