# rain-reporter — one oracle node

The contract in module 14 cannot look out of the window. This script looks for it.

Run three of them, with three different keys and three different station names. Each reads
its own simulated gauge, they disagree by a millimetre or two the way real instruments do,
and `RainOracle` takes the median of whatever arrives.

## Set up

```bash
cd services/rain-reporter
npm install
```

Each reporter needs its own key, and that key needs two things and no more: some TRUST for
gas, and `REPORTER_ROLE` on the oracle.

```bash
# make three throwaway keys — these are hot keys and are meant to be cheap to replace
for n in north east west; do
  cast wallet new | tee /tmp/$n.key
done
```

Fund each address from the faucet, then have the **admin** appoint them:

```bash
cast send <oracle> "grantRole(bytes32,address)" \
  $(cast keccak "REPORTER_ROLE") <reporter address> \
  --rpc-url https://eth.didlab.org --legacy --interactive
```

## Run

```bash
PRIVATE_KEY=0x... node reporter.mjs --station north
PRIVATE_KEY=0x... node reporter.mjs --station east
PRIVATE_KEY=0x... node reporter.mjs --station west
```

Each one reports the last finished period, then finalises once the quorum is in. Whoever
gets there first finalises; the others see `AlreadyFinalized` and carry on, because the
answer does not depend on who asks for it.

For a cron job instead of a long-running process:

```bash
*/5 * * * * cd /opt/rain-reporter && PRIVATE_KEY=0x... node reporter.mjs --station north --once
```

## The three demonstrations

**One liar.** Restart one node with `--lie 9000`. It reports nine metres of rain; the
median barely moves. Look at `reportsOf(period)` on the explorer afterwards — the lie is
there, permanently, next to the name of the address that told it.

**A majority of liars.** Now run two of the three with `--lie 0`. The median is zero, the
oracle reports a drought, and every policy pays out. Nothing in the contract stopped it.
M-of-N does not make an oracle honest; it makes dishonesty expensive, by requiring an
attacker to control more reporters than you do. That is an operational property, not a
cryptographic one, and it is the single most important idea in this module.

**Silence.** Stop all three. The period is never finalised, `reading()` keeps returning
`finalized = false`, and no policy can settle — not even one that clearly should pay. The
oracle has no way to compel anyone to speak. Liveness and honesty pull against each other:
a low quorum keeps answers coming and is easier to capture; a high one resists capture and
is easier to stall.

**Drought mode** (`--drought` on every node) makes the simulated weather dry, so a class
can watch a payout without waiting for the pseudo-random weather to cooperate. Use it for
the demo; use the normal mode when you want students to discover that most periods pay
nothing, which is what insurance mostly does.

## Keys, deliberately

This process holds an unlocked private key and signs without asking. That is what an oracle
node is. The design point is what the key can do: say what the rainfall was, and nothing
else. It cannot mint, cannot spend the pool, cannot change the trigger. If it leaks, you
revoke the role and appoint another.

Compare with the town admin key, which is kept in a wallet and used deliberately. Tiering
keys by blast radius — hot keys for things that must happen automatically, cold keys for
things that must not — is the habit worth taking away from this module.

Never commit a key. `PRIVATE_KEY` goes in the environment, not on the command line, where
it would land in your shell history.

## Replacing the gauge with real weather

`measure(period)` is the only function that decides what this node believes. Replace its
body with a call to a real weather API and the rest of the module is unchanged — which is
the point of the exercise in the module guide. When you do, notice what you have just
done: if all three nodes call the same API, you have three reporters and one source. The
median then protects you against a node lying, and not at all against the source being
wrong.

## Running them properly

Three terminals is fine for a demo and wrong for a term. When the terminals close, periods
stop being settled and no policy can pay — which is the "silence" failure above, arriving
by accident instead of on purpose.

```bash
cd services/rain-reporter/systemd
sudo ./install.sh north east west

sudo nano /etc/rain-reporter/north.env      # PRIVATE_KEY=0x...
sudo systemctl enable --now rain-reporter@north

journalctl -fu 'rain-reporter@*'            # all three at once
```

Each station gets its own root-owned env file at mode 600 holding one key, and the service
runs as an unprivileged user with the filesystem locked down — a hot key that signs
automatically deserves the smallest possible share of the machine.

To stage the demonstrations on a running system, edit one station's env file
(`LIE=9000`, or `DROUGHT=1` on all three) and `sudo systemctl restart rain-reporter@east`.
