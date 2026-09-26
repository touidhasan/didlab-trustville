# Module 2 · The soulbound Passport

| | |
| --- | --- |
| **Contract** | `TrustvillePassport.sol` |
| **Stop** | Town Hall |
| **Standards** | ERC-721, **ERC-5192** (soulbound), on-chain metadata |
| **Stamp** | Module 2 |

## The problem

You need a record of what somebody has actually done — and it must not be possible to buy
one.

An ordinary NFT fails this immediately. If a token can be transferred it can be sold, and a
certificate that can be sold certifies the buyer's money rather than the holder's work. The
whole value of a credential comes from the fact that it cannot move.

## The idea

An ERC-721 with transfers permanently disabled. Mint it to a resident and it stays there
for ever: no transfer, no approval, no sale. **ERC-5192** is the small standard that makes
this legible to wallets and marketplaces, so they can display it as non-transferable rather
than offering a Sell button that will always fail.

The Passport also collects **stamps** — one per module completed. The stamp is awarded by
the *contract you interacted with*, not by an instructor, so the record cannot be granted
as a favour or edited afterwards.

## Key terms

**ERC-721.** The NFT standard: unique tokens with an owner, `ownerOf`, `transferFrom`,
`approve`, and `tokenURI` for metadata. Trustville uses OpenZeppelin's implementation and
removes one capability.

**Soulbound (ERC-5192).** A token bound to an account. The standard is deliberately tiny:
one function, `locked(tokenId) → bool`, and one event, `Locked(tokenId)`, emitted at mint.
That is all a wallet needs to know not to offer a transfer.

**`_update` hook.** OpenZeppelin v5 routes every ownership change — mint, transfer, burn —
through one internal function. Overriding it once is how you block transfers without
missing a path. In v4 you would override `_beforeTokenTransfer`; knowing that the hook
moved between major versions is the kind of detail that bites people copying old tutorials.

**On-chain metadata.** `tokenURI` usually points at a web server or IPFS. Trustville builds
the JSON in Solidity and returns it as a `data:` URI, so the Passport has no external
dependency: if every server in the project vanished, the token still describes itself.

## How it works

```solidity
mapping(address => uint256) public passportOf;              // 0 = none
mapping(uint256 => mapping(uint16 => uint64)) public stampedAt;  // token → module → when
```

| Function | Who | What |
| --- | --- | --- |
| `mint()` | any resident, once | Issues their Passport |
| `stamp(resident, moduleId)` | `STAMPER_ROLE` | Records a completed module |
| `hasStamp(resident, moduleId)` | anyone | The progress query |
| `stampsOf(resident)` | anyone | Every module they have completed |
| `locked(tokenId)` | anyone | ERC-5192 — always `true` here |
| `tokenURI(tokenId)` | anyone | Base64 JSON built on chain |

Transfers revert with `Soulbound()`. A mint is the one movement allowed, because it comes
*from* the zero address.

**`STAMPER_ROLE` is held by contracts, never by people.** `TownEscrow` stamps module 5;
`CertificateRegistry` stamps module 7. No human address can award a stamp, so the record is
a byproduct of doing the work.

## The detail that matters

Every stamping contract inherits `Stamping.sol`, and it is worth reading, because the
obvious implementation is a trap that cost this project a real bug:

```solidity
function _stamp(address who, uint16 moduleId) internal {
    if (address(passport) == address(0)) return;
    if (passport.passportOf(who) == 0) return;
    if (passport.hasStamp(who, moduleId)) return;
    if (!passport.hasRole(passport.STAMPER_ROLE(), address(this))) return;
    passport.stamp(who, moduleId);
}
```

The natural version is `try passport.stamp(...) {} catch {}` — never let a missing stamp
break a real transaction. It is also broken in a way no unit test catches.

`eth_estimateGas` binary-searches for the cheapest gas limit at which the transaction
*succeeds*. A caught failure still succeeds. So the estimator settles on a limit where the
inner `stamp` call runs out of gas and is swallowed, the outer call reports success, and
**no stamp is ever awarded in a real wallet** — while every test passes, because tests do
not estimate gas.

Checking the preconditions with view calls instead makes the real cost visible to the
estimator. The general lesson: never swallow an error in a path that gas estimation has to
price.

## Walk through it

1. Mint your Passport at Town Hall.
2. On the explorer, call `passportOf(yourAddress)` to get your token id.
3. Call `tokenURI(tokenId)`. Decode the Base64 — it is a complete JSON document, built by
   the contract.
4. Try `transferFrom(you, someoneElse, tokenId)` from the explorer's write tab. It reverts
   with `Soulbound()`.
5. Complete any module and call `hasStamp(you, thatModule)`.

## What actually happened on chain

```
Transfer(from: 0x0, to: 0x…, tokenId: 1)   // ERC-721 mint
Locked(tokenId: 1)                          // ERC-5192 — bound for ever
PassportIssued(resident: 0x…, tokenId: 1)
```

Three events for one action. `Transfer` so NFT tooling sees it, `Locked` so wallets know
not to offer a sale, and a human-readable one for the app.

## When a plain database is better

For tracking coursework inside one institution, a database wins outright: cheaper, faster,
private, and correctable when an instructor makes a mistake — which matters more than
people expect.

Soulbound tokens earn their place when the holder needs to show the record **to someone who
does not trust the issuer's database**, and when the record's value depends on it being
unsellable. Professional licences, sanctions, membership, reputation.

Notice the tension: "correctable by an instructor" and "cannot be edited afterwards" are
the same property seen from two sides, and you cannot have both.

## What this does not fix

- **Key loss.** Lose the private key and the Passport is unreachable for ever. It cannot be
  transferred to a new wallet — that is the point — so recovery means re-issuing to a new
  address and abandoning the old record. Real soulbound systems agonise over this.
- **Sybil resistance.** One address, one Passport. Nothing stops a person making fifty
  addresses. Rate limits help; identity does not exist here.
- **Selling the account.** You cannot sell the token, but you can sell the private key.
  Non-transferable on chain is not non-transferable in life.

## Common mistakes

- **Blocking only `transferFrom`.** `safeTransferFrom`, `approve` and `setApprovalForAll`
  are other doors. Override `_update` and close them all at once.
- **Forgetting `Locked`.** Without it, wallets and marketplaces have no way to know, and
  will happily list a token that can never be sold.
- **Stamping from a human address.** The moment a person can award stamps, the record means
  "somebody said so" instead of "this happened".
- **Swallowing stamp failures.** See above.

## Security checklist

- [ ] Is every transfer path blocked, including approvals?
- [ ] Who holds `STAMPER_ROLE`? Is any of them an externally owned account?
- [ ] Can a resident hold two Passports? Via a second address?
- [ ] Can a stamp be awarded twice, or removed?
- [ ] If the Passport contract is redeployed, what happens to the existing stamps?

## Extend it

1. Add expiry to stamps, so a skill lapses if unused. Then decide who re-awards it.
2. Add a *recovery* path: a registrar can re-issue a Passport to a new address if the old
   key is lost, carrying the stamps over. You have just reintroduced a trusted party —
   argue whether the trade is worth it.
3. Render the Passport as an on-chain SVG that grows with each stamp. Note what that costs
   in gas, and at what point you would give up and use a server.

## Further reading

- [ERC-5192: Minimal Soulbound NFTs](https://eips.ethereum.org/EIPS/eip-5192)
- [ERC-721](https://eips.ethereum.org/EIPS/eip-721)
- Vitalik Buterin, Weyl and Ohlhaver, *Decentralized Society: Finding Web3's Soul* — where
  the term came from, and worth reading critically rather than reverently.

**Next:** [Module 3 · The town currency →](03-town-token.md)
