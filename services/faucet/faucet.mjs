#!/usr/bin/env node
/**
 * Trustville TRUST faucet — a drip, not a tap.
 *
 * A student cannot do anything on DIDLab without gas, and gas costs TRUST. Handing it out
 * by hand does not scale past about six people, so this does it: a small amount, per
 * address, behind limits that make flooding it boring.
 *
 * Four independent limits, because any single one is easy to get around:
 *
 *   1. Per address  — one drip per cooldown, whatever else changes.
 *   2. Per IP       — a handful of addresses a day from one place.
 *   3. Global       — a daily ceiling on the whole faucet, so the worst case is bounded
 *                     even if the first two are defeated entirely.
 *   4. Already rich — an address holding enough gas is refused. The faucet exists to
 *                     unblock people, not to accumulate balances.
 *
 * Optionally a course code (FAUCET_CODE), which is the cheapest gate that actually works
 * for a class: students have it, the open internet does not, and rotating it each term
 * cancels last year's scripts. Cloudflare Turnstile is supported too if you want a
 * challenge instead.
 *
 * The key here is HOT: it signs automatically, unattended. Keep a small balance in it and
 * top it up; it can send TRUST and nothing else. This is the same tiering argument as the
 * rain reporters — what matters is not whether a key can leak, but what it can do if it
 * does.
 */
import { readFileSync, writeFileSync, renameSync, existsSync } from 'node:fs';
import { createServer } from 'node:http';
import { createPublicClient, createWalletClient, defineChain, formatEther, http, isAddress, parseEther } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';

/* ------------------------------------------------------------------------ config */

const env = (k, d) => process.env[k] ?? d;

const PORT = Number(env('PORT', 8080));
const RPC = env('RPC_URL', 'https://eth.didlab.org');
const EXPLORER = env('EXPLORER_URL', 'https://explorer.didlab.org');
const DRIP = env('DRIP_TRUST', '1');
const COOLDOWN_HOURS = Number(env('COOLDOWN_HOURS', 24));
const MAX_PER_IP_PER_DAY = Number(env('MAX_PER_IP_PER_DAY', 3));
const MAX_TRUST_PER_DAY = Number(env('MAX_TRUST_PER_DAY', 50));
const ENOUGH_TRUST = env('ENOUGH_TRUST', '0.5'); // above this, you do not need a drip
const CODE = env('FAUCET_CODE', '');
const TURNSTILE_SECRET = env('TURNSTILE_SECRET', '');
const STATE_FILE = env('STATE_FILE', '/var/lib/trustville-faucet/state.json');

const PRIVATE_KEY = process.env.PRIVATE_KEY;
if (!PRIVATE_KEY) {
  console.error('PRIVATE_KEY is not set. Put it in the service environment file, never on the command line.');
  process.exit(1);
}

const didlab = defineChain({
  id: 252501,
  name: 'DIDLab',
  nativeCurrency: { name: 'Trust', symbol: 'TRUST', decimals: 18 },
  rpcUrls: { default: { http: [RPC] } },
});

const account = privateKeyToAccount(PRIVATE_KEY);
const publicClient = createPublicClient({ chain: didlab, transport: http(RPC) });
const wallet = createWalletClient({ account, chain: didlab, transport: http(RPC) });

/* ------------------------------------------------------------------------- state */

const today = () => new Date().toISOString().slice(0, 10);
const empty = { addresses: {}, ips: {}, day: today(), sentToday: 0 };

function load() {
  try {
    if (existsSync(STATE_FILE)) return { ...empty, ...JSON.parse(readFileSync(STATE_FILE, 'utf8')) };
  } catch (e) {
    console.error('state unreadable, starting fresh:', e.message);
  }
  return { ...empty };
}

let state = load();

function save() {
  try {
    const tmp = `${STATE_FILE}.tmp`;
    writeFileSync(tmp, JSON.stringify(state));
    renameSync(tmp, STATE_FILE); // atomic: a crash mid-write never leaves a broken file
  } catch (e) {
    console.error('could not persist state:', e.message);
  }
}

/** A new day resets the per-IP and global counters; per-address cooldowns are absolute. */
function rollover() {
  if (state.day === today()) return;
  state.day = today();
  state.ips = {};
  state.sentToday = 0;
  const cutoff = Date.now() - COOLDOWN_HOURS * 3600_000;
  for (const [addr, at] of Object.entries(state.addresses)) if (at < cutoff) delete state.addresses[addr];
  save();
}

/* -------------------------------------------------------------------- the drip */

async function checkTurnstile(token, ip) {
  if (!TURNSTILE_SECRET) return true;
  try {
    const res = await fetch('https://challenges.cloudflare.com/turnstile/v0/siteverify', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ secret: TURNSTILE_SECRET, response: token, remoteip: ip }),
    });
    const body = await res.json();
    return body.success === true;
  } catch {
    return false;
  }
}

async function drip({ address, code, token, ip }) {
  rollover();

  if (!isAddress(address)) return { status: 400, error: 'That is not a valid address.' };
  if (CODE && code !== CODE) return { status: 403, error: 'Wrong course code. Ask your instructor.' };
  if (!(await checkTurnstile(token, ip))) return { status: 403, error: 'Challenge failed. Try again.' };

  const key = address.toLowerCase();
  const last = state.addresses[key] ?? 0;
  const waitMs = last + COOLDOWN_HOURS * 3600_000 - Date.now();
  if (waitMs > 0) {
    const hours = Math.ceil(waitMs / 3600_000);
    return { status: 429, error: `This address already had a drip. Try again in about ${hours}h.` };
  }

  const fromIp = state.ips[ip] ?? 0;
  if (fromIp >= MAX_PER_IP_PER_DAY) {
    return { status: 429, error: 'That is enough addresses from one place today.' };
  }

  if (state.sentToday + Number(DRIP) > MAX_TRUST_PER_DAY) {
    return { status: 503, error: 'The faucet has given out its budget for today. Ask your instructor.' };
  }

  const balance = await publicClient.getBalance({ address });
  if (balance >= parseEther(ENOUGH_TRUST)) {
    return {
      status: 400,
      error: `You already hold ${formatEther(balance)} TRUST, which is plenty of gas. The faucet is for getting started.`,
    };
  }

  const faucetBalance = await publicClient.getBalance({ address: account.address });
  if (faucetBalance < parseEther(DRIP) * 2n) {
    console.error(`faucet is nearly empty: ${formatEther(faucetBalance)} TRUST left`);
    return { status: 503, error: 'The faucet is empty. Please tell your instructor.' };
  }

  // Record BEFORE sending. A double-spend of the limit is worse than a lost drip: if the
  // send fails the student simply asks again after the cooldown, but a race that slips
  // through the counters is how a faucet gets drained.
  state.addresses[key] = Date.now();
  state.ips[ip] = fromIp + 1;
  state.sentToday += Number(DRIP);
  save();

  try {
    const gasPrice = await publicClient.getGasPrice(); // DIDLab has no EIP-1559
    const hash = await wallet.sendTransaction({ to: address, value: parseEther(DRIP), gasPrice });
    console.log(`${new Date().toISOString()} drip ${DRIP} TRUST -> ${address} (${ip}) ${hash}`);
    return { status: 200, hash };
  } catch (e) {
    console.error('send failed:', e.shortMessage || e.message);
    return { status: 502, error: 'The transaction did not go through. Try again in a few minutes.' };
  }
}

/* -------------------------------------------------------------------------- web */

const page = (prefill = '') => `<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Trustville faucet</title>
<style>
  :root { color-scheme: light dark; --bg:#fbfaf7; --fg:#1b1a17; --muted:#6c6862; --line:#e2ded6; --accent:#c8802a; }
  @media (prefers-color-scheme: dark) { :root { --bg:#17161a; --fg:#eceae6; --muted:#a09b93; --line:#302d35; } }
  * { box-sizing: border-box; }
  body { margin:0; background:var(--bg); color:var(--fg); font:16px/1.6 ui-sans-serif,system-ui,-apple-system,Segoe UI,Roboto,sans-serif;
         display:grid; place-items:center; min-height:100vh; padding:16px; }
  .card { width:100%; max-width:560px; border:1px solid var(--line); border-radius:14px; padding:28px; background:color-mix(in srgb,var(--bg) 92%,white); }
  h1 { margin:0 0 6px; font-size:24px; }
  p { color:var(--muted); margin:0 0 18px; }
  label { display:block; font-size:13px; color:var(--muted); margin:14px 0 6px; }
  input { width:100%; padding:11px 13px; font:inherit; font-family:ui-monospace,monospace; border:1px solid var(--line);
          border-radius:9px; background:var(--bg); color:var(--fg); }
  button { margin-top:18px; width:100%; padding:12px; font:inherit; font-weight:600; border:0; border-radius:9px;
           background:var(--accent); color:#fff; cursor:pointer; }
  button[disabled] { opacity:.55; cursor:default; }
  .msg { margin-top:16px; padding:12px 14px; border-radius:9px; border:1px solid var(--line); font-size:14px; display:none; }
  .msg.show { display:block; }
  .ok { border-color:#3f7d4e; } .bad { border-color:#a8442f; }
  a { color:var(--accent); }
  .foot { margin-top:22px; font-size:13px; color:var(--muted); border-top:1px solid var(--line); padding-top:14px; }
  code { font-family:ui-monospace,monospace; }
</style></head><body>
<div class="card">
  <h1>Trustville faucet</h1>
  <p>Gas for the DIDLab chain. ${DRIP} TRUST per address, once every ${COOLDOWN_HOURS} hours — enough for
     hundreds of transactions, so one drip usually lasts the whole course.</p>
  <form id="f">
    <label for="a">Your wallet address</label>
    <input id="a" name="address" placeholder="0x…" value="${prefill.replace(/[^0-9a-fA-Fx]/g, '')}" required>
    ${CODE ? '<label for="c">Course code</label><input id="c" name="code" placeholder="from your instructor" required>' : ''}
    <button id="b" type="submit">Send me TRUST</button>
  </form>
  <div id="m" class="msg"></div>
  <div class="foot">
    Already have gas? You do not need this. Check your balance on the
    <a href="${EXPLORER}">explorer</a>, or open <a href="https://dapp.didlab.org">Trustville</a>.
    <br>TRUST pays for gas only; the town's currency is TVD, which you get from the Bank in Trustville.
  </div>
</div>
<script>
  const f = document.getElementById('f'), m = document.getElementById('m'), b = document.getElementById('b');
  f.addEventListener('submit', async (e) => {
    e.preventDefault();
    b.disabled = true; b.textContent = 'Sending…';
    m.className = 'msg';
    const body = { address: f.address.value.trim(), code: f.code ? f.code.value.trim() : '' };
    try {
      const res = await fetch('/drip', { method:'POST', headers:{'content-type':'application/json'}, body: JSON.stringify(body) });
      const data = await res.json();
      if (res.ok) {
        m.className = 'msg show ok';
        m.innerHTML = 'Sent. <a href="${EXPLORER}/tx/' + data.hash + '">See the transaction</a> — it lands in a second or two.';
      } else {
        m.className = 'msg show bad';
        m.textContent = data.error || 'Something went wrong.';
      }
    } catch { m.className = 'msg show bad'; m.textContent = 'Could not reach the faucet.'; }
    b.disabled = false; b.textContent = 'Send me TRUST';
  });
</script>
</body></html>`;

const json = (res, status, body) => {
  res.writeHead(status, { 'content-type': 'application/json', 'cache-control': 'no-store' });
  res.end(JSON.stringify(body));
};

const clientIp = (req) =>
  (req.headers['cf-connecting-ip'] || // behind Cloudflare, this is the real client
    String(req.headers['x-forwarded-for'] || '').split(',')[0].trim() ||
    req.socket.remoteAddress ||
    'unknown').toString();

const server = createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');

  if (req.method === 'GET' && (url.pathname === '/' || url.pathname === '/index.html')) {
    res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
    return res.end(page(url.searchParams.get('address') ?? ''));
  }

  if (req.method === 'GET' && url.pathname === '/status') {
    rollover();
    const balance = await publicClient.getBalance({ address: account.address }).catch(() => 0n);
    return json(res, 200, {
      faucet: account.address,
      balance: formatEther(balance),
      drip: DRIP,
      cooldownHours: COOLDOWN_HOURS,
      sentToday: state.sentToday,
      dailyBudget: MAX_TRUST_PER_DAY,
      codeRequired: Boolean(CODE),
    });
  }

  if (req.method === 'POST' && url.pathname === '/drip') {
    let raw = '';
    for await (const chunk of req) {
      raw += chunk;
      if (raw.length > 4096) return json(res, 413, { error: 'Too much.' });
    }
    let body;
    try {
      body = JSON.parse(raw || '{}');
    } catch {
      return json(res, 400, { error: 'Bad request.' });
    }
    const result = await drip({
      address: String(body.address || '').trim(),
      code: String(body.code || '').trim(),
      token: String(body.token || ''),
      ip: clientIp(req),
    });
    return json(res, result.status, result.status === 200 ? { hash: result.hash } : { error: result.error });
  }

  json(res, 404, { error: 'Not found.' });
});

const balance = await publicClient.getBalance({ address: account.address });
console.log(
  `trustville-faucet on :${PORT}\n` +
    `  key      ${account.address} (${formatEther(balance)} TRUST)\n` +
    `  drip     ${DRIP} TRUST per address per ${COOLDOWN_HOURS}h\n` +
    `  limits   ${MAX_PER_IP_PER_DAY}/IP/day, ${MAX_TRUST_PER_DAY} TRUST/day total\n` +
    `  gate     ${CODE ? 'course code' : 'none'}${TURNSTILE_SECRET ? ' + turnstile' : ''}`,
);
if (balance === 0n) console.error('  WARNING: the faucet key has no TRUST — fund it before anyone asks.');

server.listen(PORT);
