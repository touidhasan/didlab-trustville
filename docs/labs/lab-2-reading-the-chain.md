# Lab 2 · Reading the chain

**Deliverable:** a pull request adding a town activity feed · **Time:** two hours

Every dApp you will be paid to build shows "what happened recently". There is no database
behind it. The chain stores state — balances, owners, statuses — but *what changed and
when* lives only in event logs, and getting them out is a real engineering problem the
moment there is more than a handful.

## The job

Add a **Town activity** section to Trustville showing the most recent on-chain events
across the town, newest first, in language a resident would understand.

> `0x2Ed7…cd94` · `TicketsBought(1, 0x4F4c…9fA5, 2, 20000000000000000000)`

is not the deliverable. This is:

> **Two tickets sold** for the Harvest Festival · 20 TVD · 0x4F4c…9fA5 · 3 minutes ago

Cover at least six event types from at least four contracts — pick ones that tell a story
about the town.

## Acceptance criteria

- [ ] Shows the most recent 20 events, newest first, merged across contracts.
- [ ] Each row: what happened in plain language, who did it (shortened address), when
      (relative), and a link to the transaction on the explorer.
- [ ] Amounts formatted as token amounts, not raw wei.
- [ ] New events appear without a manual refresh.
- [ ] An empty chain shows an honest empty state, not a spinner forever.
- [ ] An RPC failure shows an error and recovers when the RPC returns — it does not wedge.
- [ ] Works on a chain with **no explorer configured** (the link is simply absent).
- [ ] Does not slow the first paint of the page. Say in the PR how you ensured that.
- [ ] CI green.

## Technical requirements

**Bounded queries.** `getLogs` from block 0 will work on your local chain and fail on
DIDLab, which has millions of blocks. Query a bounded window and say in your PR what
happens when the town has been quiet for longer than your window. There is no free answer
here; there is a decision, and you should be able to defend it.

**Batch, don't loop.** One `getLogs` call per contract with multiple event signatures beats
one call per event type. Count your RPC calls per refresh and put the number in the PR.

**Decode properly.** Use the generated ABIs and viem's `parseEventLogs`. Do not
hand-decode topics.

**Updating.** `watchContractEvent` or polling — your choice, but justify it. Polling every
500ms is a denial-of-service attack on your own RPC node; polling every five minutes is not
"live". Both are defensible; neither is defensible without a reason.

**Clean up.** A component that subscribes must unsubscribe when it unmounts. A leak here
shows up as the page getting slower the longer it is open, which is exactly the class of
bug nobody notices in a demo and everybody notices in production.

## What good looks like

The formatting layer is the interesting design problem. A map from event name to a render
function, kept apart from the fetching, is one good answer — a reviewer should be able to
add a seventh event type without touching the fetching code. If adding an event means
editing three places, the design is wrong.

## Common ways this goes wrong

- **Unbounded `fromBlock`.** Works locally, times out on DIDLab. Test against both.
- **A subscription per event type.** Twelve WebSocket subscriptions is twelve things to
  leak.
- **Assuming logs arrive in order.** They do not, across contracts. Sort by block number
  and log index.
- **`Date.now()` for "3 minutes ago".** The block has a timestamp; the browser's clock is
  not the chain's clock, and on a local chain where you time-travel they differ by hours.
- **Rendering raw BigInt.** `20000000000000000000` is not a price.

## Reality check

Real dApps do not do this. They run an indexer — a service that follows the chain, writes
events to a database, and serves them over an API. You are building the thing an indexer
replaces, once, so you understand what it is for.

In your PR description, answer in two or three sentences: **at what point would you stop
doing this in the browser and run an indexer, and what would that cost you?**

## Out of scope

No backend. No indexing service. No new dependencies beyond what is already in `app/`.

## Hand in

1. The PR, CI green, reviewed and approved.
2. Your review of someone else's PR — check their RPC call count and their cleanup.
3. An incident write-up if anything broke.
