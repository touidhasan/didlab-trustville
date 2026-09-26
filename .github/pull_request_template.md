## What this changes

<!-- One paragraph. What does a user of Trustville get that they did not have before? -->

## Why it is built this way

<!-- The decisions a reviewer cannot infer from the diff. What did you consider and
     reject? Where did you trade one thing for another? If you copied a pattern from
     elsewhere in the repo, say which and why it fits. -->

## How to check it

<!-- The exact steps a reviewer runs. Addresses, commands, what they should see. -->

```bash
cd contracts && FOUNDRY_PROFILE=test forge test --match-contract <YourTest> -vv
```

## What can go wrong

<!-- Every failure state you handled, and how the interface behaves in each. Rejected in
     the wallet, reverted on chain, wrong network, no funds, stale data, a second tab. -->

## Checklist

- [ ] Tests cover the happy path **and** each way the transaction can fail
- [ ] `forge fmt` clean, CI green
- [ ] `npm run sync-abi` run and committed, if a contract changed
- [ ] The UI shows something honest while a transaction is pending, and on failure
- [ ] Custom errors are decoded for the user, not printed raw
- [ ] No private key, mnemonic or `.env` anywhere in the diff
- [ ] Nothing personal written on chain
