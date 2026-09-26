# TRUST faucet

Students cannot do anything on DIDLab without gas, and gas costs TRUST. Handing it out by
hand stops scaling at about six people. This gives out a little, automatically, behind
limits that make flooding it boring.

## What a student sees

`https://faucet.didlab.org`, an address box, a course code if you set one, and a link to
the transaction. One drip is 1 TRUST — at 1 gwei that covers several hundred transactions,
so most students never come back.

Trustville links here with the address already filled in, so the usual path is: connect
MetaMask, see "you have no TRUST", click through, come back.

## Why four limits

Any single limit is easy to get around, so none of them is load-bearing on its own.

| Limit | Default | Defeated by | Caught by |
| --- | --- | --- | --- |
| Per address | 1 drip / 24h | making new addresses | the per-IP limit |
| Per IP | 3 addresses / day | a proxy or a phone network | the global budget |
| Global | 50 TRUST / day | nothing — it is a hard ceiling | — |
| Already funded | refuses above 0.5 TRUST | — | stops hoarding, not abuse |

The global budget is the one that matters. It means the worst case for a completely
defeated faucet is a bounded daily loss on a chain where the coin is not worth anything,
rather than a drained key and a lab that cannot run.

**The course code** (`FAUCET_CODE`) is the cheapest gate that actually works for a class.
Students have it, the open internet does not, and rotating it each term cancels last term's
scripts. It is not a secret worth defending — it is a speed bump aimed at drive-by
scripts, and it should be treated as public the moment it reaches a group chat.

**Cloudflare** is where per-IP rate limiting really belongs: the service's own counter is a
backstop for when a request gets past the edge, not the front line. Add a rate-limiting
rule on `faucet.didlab.org` for `POST /drip`.

## Install

```bash
cd services/faucet/systemd
sudo ./install.sh
sudo nano /etc/trustville-faucet.env       # PRIVATE_KEY, FAUCET_CODE
sudo systemctl enable --now trustville-faucet
curl -s localhost:8080/status
```

It listens on `127.0.0.1:8080` and does no TLS. Put nginx or a Cloudflare tunnel in front,
exactly as `dapp.didlab.org` is served.

## The key

The faucet holds a hot key that signs unattended. Two rules:

**Keep it small.** Fund it with a term's worth, not a lifetime's. `/status` shows the
balance, and the service warns in the log when it is nearly empty. Topping it up
occasionally is the price of not having a large unattended balance.

**Keep it narrow.** This key can send TRUST and nothing else. It holds no roles, cannot
mint, cannot touch any contract. If it leaks, you lose what is in it and you replace it —
which is the whole argument for tiering keys by what they can do rather than by how well
you think you can protect them.

Set against the town admin key, which owns every contract in Trustville and lives in
MetaMask, the contrast is worth drawing in class: same cryptography, completely different
consequences.

## Operating it

```bash
curl -s localhost:8080/status            # balance, today's usage, the limits in force
journalctl -fu trustville-faucet         # every drip is logged with address and IP
```

Out of budget mid-lab? Raise `MAX_TRUST_PER_DAY` in the env file and restart — it takes
seconds, and the ceiling exists to bound accidents, not to be inviolable.

## The honest alternative

On a permissioned chain you control, the other answer is to stop charging for gas at all:
`--min-gas-price=0` on the validators, and no faucet, no keys and no funding. That removes
this entire service and its failure modes, and replaces them with a chain where spamming
is free and only Cloudflare and the contracts' own rate limits stand in the way.

That trade — a price signal versus one less moving part — is a genuine design decision
rather than a settled one, and it is worth putting to students as an exercise. This
deployment keeps the price signal.
