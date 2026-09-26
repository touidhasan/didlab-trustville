# Module 3 · The town currency

| | |
| --- | --- |
| **Contracts** | `TownToken.sol`, `TownBank.sol` |
| **Stop** | Bank |
| **Standard** | ERC-20 |
| **Stamp** | Module 3 |

## The problem

Trustville needs money — something to pay rent with, escrow, bid, donate, lend. And the
first question anyone should ask of any currency is: **who can create more of it, and what
stops them?**

That question has a bad answer in most student token projects. The deployer holds a
`mint` function, and the honest description of the token is "worth whatever the deployer
feels like".

## The idea

An ordinary ERC-20 with a hard supply cap, where the right to mint is held by a **contract**
rather than a person.

`TownBank` holds `MINTER_ROLE`. It mints in exactly one circumstance: a registered resident
claims their welcome grant, once. No human address can mint, including the town admin,
including the deployer. The rule is in the code, and anyone can check it in thirty seconds
on the explorer.

## Key terms

**ERC-20.** The fungible token standard: `balanceOf`, `transfer`, `approve`,
`transferFrom`, `allowance`, plus `Transfer` and `Approval` events. Every wallet and
exchange already speaks it, which is the entire reason to use a standard.

**Decimals.** ERC-20 balances are integers. `decimals() = 18` means the contract stores
`1000000000000000000` and interfaces display `1.0`. **The chain has no fractions.** Every
"1.5 TVD" you see is a display convention over an integer, and forgetting that produces the
commonest bug in dApp frontends.

**Allowance.** `transferFrom` lets a contract move your tokens, but only up to the amount
you approved. That is why paying into escrow is two transactions: `approve`, then the
action. Users find it confusing and it is not going away — it is what stops a contract
emptying your wallet.

**Role held by a contract.** `MINTER_ROLE` on an address that is a contract means the
minting rule is code, not discretion. This is the single most important idea in the module.

## How it works

**TownToken** — ERC-20 plus two things:

```solidity
uint256 public immutable maxSupply;

function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
    uint256 remaining = maxSupply - totalSupply();
    if (amount > remaining) revert MaxSupplyExceeded(amount, remaining);
    _mint(to, amount);
}
```

`immutable` means `maxSupply` is fixed at deployment and stored in the bytecode, not in
storage — cheaper to read, and impossible to change afterwards even by the admin. The cap
is a property of the contract, not a setting.

Anyone may `burn` their own tokens. Nobody may burn anyone else's.

**TownBank** — the only minter:

```solidity
function claimWelcomeGrant() external {
    if (!registry.isResident(msg.sender)) revert NotAResident();
    if (hasClaimed[msg.sender]) revert AlreadyClaimed();
    hasClaimed[msg.sender] = true;
    token.mint(msg.sender, grantAmount);
    // ... stamps module 3
}
```

Five lines that define the monetary policy of the town. The admin can change
`grantAmount` for future claims, but cannot mint directly and cannot make anyone claim
twice.

**Checks-effects-interactions.** Notice `hasClaimed` is set *before* `token.mint` is
called. The state change comes first, the external call second. That ordering is what makes
reentrancy attacks fail, and it is worth forming the habit here where nothing is at stake.

## The detail that matters

Look at who can mint, on the live contract:

```bash
cast call $TOKEN "hasRole(bytes32,address)(bool)" \
  $(cast keccak "MINTER_ROLE") $TOWN_ADMIN --rpc-url https://eth.didlab.org
```

`false`. The town admin — who deployed everything, who arbitrates disputes, who issues
certificates — cannot create a single TVD.

That is not politeness. `DeployTown.s.sol` grants `MINTER_ROLE` to the Bank contract and
nothing else, then renounces its own admin rights and **asserts** the result, so a botched
handover fails the deployment rather than shipping quietly.

## Walk through it

1. Claim your welcome grant at the Bank.
2. On the explorer, open the transaction. Two events: `Transfer` from the zero address
   (which is what minting looks like) and `WelcomeGrantClaimed`.
3. Call `totalSupply()` and `maxSupply()`. Note the headroom.
4. Ask who holds `MINTER_ROLE`. It is an address — look it up. It is the Bank.
5. Claim again. `AlreadyClaimed`.
6. Send some TVD to a classmate and watch the `Transfer` event.

## What actually happened on chain

```
Transfer(from: 0x0000…0000, to: 0x…, value: 1000000000000000000000)
WelcomeGrantClaimed(resident: 0x…, amount: 1000000000000000000000)
Stamped(tokenId: 1, moduleId: 3, by: 0x…)
```

Minting is a `Transfer` from the zero address; burning is a transfer *to* it. The ERC-20
standard has no separate mint event, which is why block explorers show supply changes as
transfers from nowhere.

## When a plain database is better

For points inside one application — loyalty points, game currency, course credits — a
database column is better in every way: free, instant, private, reversible.

An ERC-20 earns its place when the token must be **usable by software you did not write**.
Every wallet displays it, every exchange can list it, and any contract can accept it as
payment without asking permission. Trustville's escrow, auction, rent, insurance and
lending modules all take TVD without the token contract knowing they exist.

That composability is the real product. It is also why a mistake in a token contract is
permanent in a way a database migration is not.

## What this does not fix

- **A capped supply does not create value.** TVD is worth nothing; scarcity is not worth.
- **The cap does not stop concentration.** One address could hold everything.
- **Code does not stop policy.** The admin can set the grant to a billion for future
  claimants. The cap binds; the rate does not.

## Common mistakes

- **Handing `MINTER_ROLE` to a person.** The commonest flaw in student token projects, and
  the one that makes the token meaningless.
- **Assuming 18 decimals everywhere.** USDC uses 6. Always read `decimals()`.
- **Float arithmetic in the frontend.** `parseUnits` and `formatUnits`, never
  `Number(x) * 1e18`, which silently loses precision above 2^53.
- **Forgetting the approve step.** Users see a transaction they did not expect and assume
  something is wrong.
- **Infinite approvals for convenience.** Common in production, and it means a bug in that
  contract can take everything.

## Security checklist

- [ ] Who holds `MINTER_ROLE`? Is every holder a contract?
- [ ] Can the admin grant `MINTER_ROLE` to themselves? What would stop them?
- [ ] Is `maxSupply` enforced on every mint path?
- [ ] Can the welcome grant be claimed twice — from the same address, or by re-registering?
- [ ] Does any contract hold an unnecessary infinite allowance?

## Extend it

1. Make `setGrantAmount` callable only by the DAO from module 12, so monetary policy needs
   a vote. Then look at what governance costs in delay.
2. Add a faucet that tops residents up with a cooldown, and work out what stops someone
   draining it with new addresses. (`GrainToken` in module 15 does exactly this — compare.)
3. Add `ERC20Permit` so approvals can be signed off-chain instead of costing a transaction.
   Note that module 12's `VoteToken` already inherits it.

## Further reading

- [ERC-20](https://eips.ethereum.org/EIPS/eip-20)
- [OpenZeppelin ERC20](https://docs.openzeppelin.com/contracts/5.x/erc20)
- [ERC-2612 Permit](https://eips.ethereum.org/EIPS/eip-2612)

**Next:** [Module 4 · Product provenance →](04-product-provenance.md)
