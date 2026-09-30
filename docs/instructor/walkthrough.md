# Instructor walkthrough

How to run Trustville as a hands-on class, walking the modules in order, 1 to 16. Each
module's own guide has the detailed steps under *Walk through it*; this page is what the
person at the front of the room needs on top of that: what to prepare, who needs a partner,
which steps need you, and where classes tend to get stuck.

## The day before

- [ ] Seed the town so every stop has something on it:

  ```bash
  cd contracts
  DEPLOYER=$(cast wallet address --account didlab-deployer)
  forge script script/SeedDemo.s.sol --rpc-url didlab --account didlab-deployer \
    --sender "$DEPLOYER" --legacy --slow --broadcast
  ```

  It posts a welcome notice, registers a product and opens a sealed-bid auction on it (48
  hours of bidding), creates a town meeting with tickets, a charity campaign with three
  milestones, and a property. It leaves alone anything that needs two people or a role —
  those are better done live.
- [ ] Check the faucet holds enough TRUST for the class, and note the course code.
- [ ] From the admin account, put money where three stops pay out of it (Bank → *Send TVD*,
  or *Add to the pool* at the Insurer). Without it modules 11, 12 and 14 stall mid-class:
  - the **Treasury** (module 11) — about 5 TVD per group;
  - the **Council's Timelock** (module 12) — what passing proposals will spend;
  - the **Insurer's pool** (module 14) — cover can only be sold against money in it.

  The addresses are at the foot of each stop's panel.
- [ ] Open the site in a fresh browser profile with a new wallet and do the warm-up yourself.
  If that fails, the class will fail the same way.

## At the start of class

- [ ] The block number in the site's header is moving.
- [ ] The explorer and the faucet both load.
- [ ] The course code is on the first slide, with the rule: **never use a wallet that holds
  real money.**
- [ ] A laptop running `npm run local` is ready as the fallback if the chain is down. It is a
  complete town on one machine; students can follow on the projector.

## Module by module

**Pairs** marks the modules where a student needs a classmate. **You** marks the steps only
the instructor can do, because they need a role held by the town admin account — so connect
that account in a separate browser profile before class. Put students in pairs from the start.

| # | Stop | Pairs | You | Where classes get stuck |
| --- | --- | --- | --- | --- |
| 0 | Notice Board (warm-up) | | | The wallet is on the wrong network; the site offers a *Switch* button |
| 1 | Town Hall · resident record | | | Nothing, usually. The first real contract call |
| 2 | Town Hall · passport | | | Forgetting to mint after registering |
| 3 | Bank · town token | Pairs for the transfer | | Sending to their own address |
| 4 | Market · provenance | Pairs | | Transferring custody of a product they do not hold |
| 5 | Market · escrow | Pairs | Decide disputed orders: Admin → *Disputes waiting for you* | Two wallet prompts, *approve* then *pay*; rejecting the first looks like a failure |
| 6 | Market · sealed-bid auction | Pairs | | **Losing the bid salt.** It lives in the browser; say so before anyone bids |
| 7 | College · certificates | Pairs | | Issuing a certificate to themselves, which the contract refuses |
| 8 | College · event tickets | Pairs | | An organiser has no *Buy* button on their own event: buy your partner's. Events start a week out, so proceeds are withdrawn next session |
| 9 | Housing · property deeds | | Certify a deed (the admin holds `CERTIFIER_ROLE`) | Expecting certification to survive a transfer |
| 10 | Housing · rent escrow | Pairs | Decide claimed deposits: Admin → *Disputes waiting for you* | Waiting out the term and claim window: use short ones |
| 11 | Council · multisig treasury | Groups of three | You are one of the owners: propose one small payment per group | Only owners can propose; the stamp goes to whoever presses *Execute*, once per payment |
| 12 | Council · DAO governance | Groups | | Wrapping tokens without delegating: zero votes, and a zero-weight vote earns no stamp. Voting opens a minute after proposing |
| 13 | Charity | Groups | Approve or reject milestones (the admin holds `ARBITER_ROLE`) | Two wallet prompts per pledge, as in module 5 |
| 14 | Insurer and oracle | | The reporter services must be running | Buying cover for the current period, which is refused. A policy settles after its period ends and the reports are in — it can be settled any time later from the same page |
| 15 | Exchange | | | Large swaps and slippage: that is the lesson, not a bug |
| 16 | Privacy Lab | Needs a module 7 certificate | | Posting from the account that enrolled; the page warns them |

## Timing

Suggested split across weekly sessions, adjusting to how fast the room moves:

| Session | Modules |
| --- | --- |
| 1 | Warm-up, 1–3 |
| 2 | 4–6 |
| 3 | 7–8, 9–10 |
| 4 | 11–12 |
| 5 | 13–14 |
| 6 | 15–16 |

The map shows each student's progress from their passport stamps, and *Continue* takes them
to their next unfinished module, so nobody needs to remember where they stopped.

## The explorer's Read and Write tabs

Several guides ask students to call a function "on the explorer". Those tabs exist only for
**verified** contracts, and verification on explorer.didlab.org is waiting on its
contract-verification service. Until then:

- Everything a student needs to *do* is on the site.
- Events and transactions are readable on the explorer as they are.
- To read a value directly, show it once from the front with `cast call`, for example
  `cast call <passport> "passportOf(address)(uint256)" <student> --rpc-url https://eth.didlab.org`.

## After class

Nothing to reset. Students' progress lives in their passports on chain, and the next session
starts wherever each of them stopped.
