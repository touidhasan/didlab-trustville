---
layout: home

hero:
  name: DIDLab
  text: Blockchain engineering, by shipping
  tagline: Six labs. You extend a working dApp, prove it with tests, and get it through review — the way the job actually works.
  actions:
    - theme: brand
      text: Start with lab 1
      link: /labs/lab-1-shipping-your-first-change
    - theme: alt
      text: Read the module guides
      link: /modules/
    - theme: alt
      text: Open Trustville
      link: https://dapp.didlab.org

features:
  - title: A real codebase, not exercises
    details: Twenty-two contracts and a React frontend, deployed and running. Every lab is a change to it — a spec, acceptance criteria, and a pull request that has to survive review.
  - title: Marked on how it fails
    details: A quarter of the grade is failure states. Rejected in the wallet, reverted on chain, wrong network, stale data. Anyone can write the happy path.
  - title: Honest about the limits
    details: Every module says where a plain database would have been better, and what it did not fix. One contract ships a deliberate vulnerability, with a test that exploits it.
---

## What this is

Trustville is a small town where each everyday trust problem is solved with a blockchain
feature — a registry, a soulbound passport, escrow, a sealed-bid auction, verifiable
certificates, deeds, a DAO treasury, an oracle-fed insurer, an exchange with lending.
Fifteen modules, live on a real chain.

You will use it once, in week one. After that it is the codebase you work in.

## The two questions behind every module

**When would a plain database have been better?** Most of these problems have a boring
solution that is faster and cheaper, and a good engineer can say which. Every module guide
argues both sides, because a developer who only knows when to reach for a chain is a
liability.

**What did this module not fix?** The chain can prove a certificate has not been altered.
It has no idea whether your degree is real. Knowing exactly where the guarantee stops is
most of the skill.

## Getting started

You need Node 20+, Foundry, git, and MetaMask with a wallet made for this course. Then:

```bash
git clone https://github.com/touidhasan/didlab-trustville
cd didlab-trustville
npm run local
```

That gives you a private Trustville on your own machine: your own chain, all 22 contracts,
the site pointed at it. No faucet, no permissions, nothing you do touches anyone else.

If that command does not give you a working town, stop and fix it — that is lab 0, and
nobody skips it.

## Where to read

The **[module guides](/modules/)** explain the town: one guide per module, each one taking
a trust problem apart and then saying what the contract failed to solve. Read the guide for
a module before you touch its code.

The **[labs](/labs/)** are the graded work. They assume you have read the guide.

[The module guides →](/modules/) · [The labs →](/labs/)
