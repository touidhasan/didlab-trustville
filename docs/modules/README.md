# Module guides

Trustville is one town told in sixteen modules. Each one takes a trust problem an ordinary
town actually has, builds the smallest honest contract that addresses it, and then says
plainly what it did **not** fix.

You can read these in any order, but they are written to be read in sequence: later modules
reuse the patterns earlier ones introduce, and several of them deliberately reuse an earlier
module's *limitation* as the next module's problem.

## Every guide has the same shape

| Section | What you get |
| --- | --- |
| **The problem** | The everyday trust problem, stated without jargon |
| **The idea** | The one insight the module turns on |
| **Key terms** | The vocabulary, defined where you meet it |
| **How it works** | The data, the functions, who may call them |
| **The detail that matters** | The two or three lines that carry the design |
| **Walk through it** | What to do on [dapp.didlab.org](https://dapp.didlab.org), in order |
| **What actually happened on chain** | The real events, and how to read them |
| **When a plain database is better** | Honest cases against using a blockchain at all |
| **What this does not fix** | The limitations, stated rather than hidden |
| **Common mistakes** | What goes wrong, including what went wrong here |
| **Security checklist** | Questions to ask before you deploy your own version |
| **Extend it** | Three or four exercises, each with a trap in it |
| **Further reading** | Standards, and one or two things worth reading properly |

## The modules

### Town Hall — identity and money

| # | Guide | Contract | Standard or pattern |
| --- | --- | --- | --- |
| 1 | [Resident record](01-resident-record.md) | `ResidentRegistry` | Registry, hash anchoring |
| 2 | [Soulbound Passport](02-soulbound-passport.md) | `TrustvillePassport` | ERC-721 + ERC-5192 |
| 3 | [Town token](03-town-token.md) | `TownToken`, `TownBank` | ERC-20 |

### Market — trade between strangers

| # | Guide | Contract | Standard or pattern |
| --- | --- | --- | --- |
| 4 | [Product provenance](04-product-provenance.md) | `ProductRegistry` | Custody chain in events |
| 5 | [Escrow](05-escrow.md) | `TownEscrow` | State machine, arbitration |
| 6 | [Sealed-bid auction](06-sealed-bid-auction.md) | `SealedAuction` | Commit–reveal, pull payments |

### College — credentials and access

| # | Guide | Contract | Standard or pattern |
| --- | --- | --- | --- |
| 7 | [Verifiable certificates](07-verifiable-certificates.md) | `CertificateRegistry` | W3C VC, simplified |
| 8 | [Event tickets](08-event-tickets.md) | `EventTickets` | ERC-1155 |

### Housing — property and deposits

| # | Guide | Contract | Standard or pattern |
| --- | --- | --- | --- |
| 9 | [Property deeds](09-property-deeds.md) | `PropertyDeeds` | ERC-721 + transfer hook |
| 10 | [Rent escrow](10-rent-escrow.md) | `RentEscrow` | Two-asset state machine |

### Council — collective decisions

| # | Guide | Contract | Standard or pattern |
| --- | --- | --- | --- |
| 11 | [Multisig treasury](11-multisig-treasury.md) | `TownTreasury` | M-of-N multisig |
| 12 | [DAO governance](12-dao-governance.md) | `VoteToken`, `TownGovernor`, `TownTimelock` | ERC-20Votes, ERC-6372, Governor |

### Charity, Insurer, Exchange — money with conditions

| # | Guide | Contract | Standard or pattern |
| --- | --- | --- | --- |
| 13 | [Charity](13-charity.md) | `TownCharity` | Milestone funding, pro-rata refunds |
| 14 | [Insurer and oracle](14-insurer.md) | `RainOracle`, `CropInsurance` | M-of-N oracle, parametric cover |
| 15 | [Swap and lending](15-defi.md) ⚠ | `GrainToken`, `TownSwap`, `GrainLoans` | Constant-product AMM, over-collateralised lending |

### Still to come

| # | Module | Status |
| --- | --- | --- |
| 16 | Zero-knowledge proofs | Not yet built |

⚠ **Module 15 contains a deliberate vulnerability.** It is there to be exploited, and there
is a test that exploits it. Read the guide before you read the contract.

## Threads that run through the whole town

Once you have read three or four guides you will start seeing the same ideas return. They
are worth naming.

**Hash anchoring.** Modules 1, 4, 7, 9 and 13 all put a `bytes32` on chain and keep the
document off it. The chain proves integrity and timing; it never proves content, and it is
the wrong place for personal data.

**Pull, never push.** Modules 6, 8 and 13 record what they owe and let people withdraw. A
contract that loops over addresses paying them out can be frozen for everyone by a single
recipient who reverts.

**Checks, effects, interactions.** Set your state before you call out. Modules 5, 6, 11 and
15 all depend on it, and module 11 explains what happens when you get it backwards.

**Time as a right.** A deadline is not bookkeeping — it is the moment somebody gains a power
they did not have. Modules 5, 6, 8, 10, 12 and 13 each turn on one, and in each case it is
worth asking *whom* the clock protects.

**The oracle problem.** Modules 4, 7, 13 and 14 are four attempts at the same question: how
does a contract learn a fact about the world? None of them solves it. Module 14 is the most
honest about that.

**Who decides.** Almost every module ends up with a human somewhere — an arbiter, a
certifier, a reporter, a voter. Trace where that person sits in each design, and what they
can and cannot do. That is usually the real security model.

## Before you start

- Live town: [dapp.didlab.org](https://dapp.didlab.org)
- Explorer: [explorer.didlab.org](https://explorer.didlab.org)
- Chain: DIDLab, chain id **252501**, RPC `https://eth.didlab.org`, native token TRUST
- You need MetaMask, a little TRUST for gas, and to register in module 1 before most of the
  rest will let you do anything.

Running the whole town locally, with no MetaMask and no TRUST needed, takes one command —
see the
[repository README](https://github.com/touidhasan/didlab-trustville#readme).

## Labs

The guides explain the town. The [labs](../labs/) are the graded work: shipping a change,
reading the chain, writing transactions, a vertical slice, state machines and time, and
finally money, prices and failure. They assume you have read the guide for the module they
touch.
