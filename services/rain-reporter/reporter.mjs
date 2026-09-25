#!/usr/bin/env node
/**
 * Trustville rain reporter — one oracle node.
 *
 * This is the piece that makes module 14 honest: a contract cannot look out of the
 * window, so something off chain has to look for it. That something is this script, and
 * everything interesting about oracles is visible in how unremarkable it is.
 *
 * Run three of these with three different keys and three different --station names. Each
 * reads its own "gauge", they disagree by a millimetre or two the way real instruments do,
 * and the contract takes the median. Then run one with --lie and watch the median absorb
 * it; then run two with --lie and watch it stop absorbing it.
 *
 * Usage:
 *   PRIVATE_KEY=0x... node reporter.mjs --station north
 *   PRIVATE_KEY=0x... node reporter.mjs --station east --lie 9000
 *   PRIVATE_KEY=0x... node reporter.mjs --station west --drought --once
 *
 * Flags:
 *   --station <name>   which gauge this node reads (changes its small local error)
 *   --lie <mm>         report this instead of the gauge — a dishonest reporter
 *   --drought          make the simulated weather dry, so policies pay out
 *   --once             report the last finished period and exit (for cron)
 *   --rpc <url>        default https://eth.didlab.org
 *   --oracle <addr>    default: read from deployments/252501.json
 *
 * The key this uses is a HOT key: it sits on a machine, unlocked, signing automatically.
 * Give it gas and the reporter role and nothing else. That tiering — a hot key that can
 * only say what the weather was, a cold key that owns the town — is the real lesson of
 * running one of these.
 */
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createPublicClient, createWalletClient, defineChain, http } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';

const HERE = dirname(fileURLToPath(import.meta.url));

/* ----------------------------------------------------------------------- arguments */

const argv = process.argv.slice(2);
const flag = (name, fallback = null) => {
  const i = argv.indexOf(`--${name}`);
  if (i === -1) return fallback;
  const next = argv[i + 1];
  return next && !next.startsWith('--') ? next : true;
};

const RPC = flag('rpc', process.env.RPC_URL || 'https://eth.didlab.org');
const STATION = String(flag('station', process.env.STATION || 'north'));
const LIE = flag('lie', process.env.LIE || null);
const DROUGHT = Boolean(flag('drought', process.env.DROUGHT === '1'));
const ONCE = Boolean(flag('once', false));

const PRIVATE_KEY = process.env.PRIVATE_KEY;
if (!PRIVATE_KEY) {
  console.error('PRIVATE_KEY is not set. Never pass a key on the command line — it lands in your shell history.');
  process.exit(1);
}

const oracleAddress =
  flag('oracle', process.env.ORACLE) ||
  JSON.parse(readFileSync(join(HERE, '../../deployments/252501.json'), 'utf8')).contracts.RainOracle;

if (!oracleAddress) {
  console.error('No oracle address: pass --oracle 0x… or deploy module 14 first.');
  process.exit(1);
}

/* -------------------------------------------------------------------------- chain */

const didlab = defineChain({
  id: 252501,
  name: 'DIDLab',
  nativeCurrency: { name: 'Trust', symbol: 'TRUST', decimals: 18 },
  rpcUrls: { default: { http: [RPC] } },
});

const account = privateKeyToAccount(PRIVATE_KEY);
const publicClient = createPublicClient({ chain: didlab, transport: http(RPC) });
const wallet = createWalletClient({ account, chain: didlab, transport: http(RPC) });

const abi = [
  { type: 'function', name: 'currentPeriod', inputs: [], outputs: [{ type: 'uint32' }], stateMutability: 'view' },
  { type: 'function', name: 'periodSeconds', inputs: [], outputs: [{ type: 'uint32' }], stateMutability: 'view' },
  { type: 'function', name: 'quorum', inputs: [], outputs: [{ type: 'uint32' }], stateMutability: 'view' },
  {
    type: 'function',
    name: 'hasReported',
    inputs: [{ type: 'uint32' }, { type: 'address' }],
    outputs: [{ type: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'reading',
    inputs: [{ type: 'uint32' }],
    outputs: [{ type: 'bool' }, { type: 'uint32' }, { type: 'uint32' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'reporterCount',
    inputs: [{ type: 'uint32' }],
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'report',
    inputs: [{ type: 'uint32' }, { type: 'uint32' }],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'finalize',
    inputs: [{ type: 'uint32' }],
    outputs: [{ type: 'uint32' }],
    stateMutability: 'nonpayable',
  },
];

const read = (functionName, args = []) =>
  publicClient.readContract({ address: oracleAddress, abi, functionName, args });

/* ------------------------------------------------------------------------- gauge */

/** Deterministic pseudo-random byte from a label, so every node's weather agrees. */
const roll = (label) => createHash('sha256').update(label).digest()[0];

/**
 * The simulated gauge. The weather itself is a function of the period, so all honest
 * nodes see the same storm; the station adds its own small error, the way two real rain
 * gauges a mile apart never quite agree.
 */
function measure(period) {
  if (LIE && LIE !== true) return Number(LIE);
  const weather = DROUGHT ? roll(`dry:${period}`) % 4 : roll(`rain:${period}`) % 21;
  const localError = (roll(`${STATION}:${period}`) % 5) - 2;
  return Math.max(0, weather + localError);
}

/* -------------------------------------------------------------------------- work */

const send = async (functionName, args) => {
  // The DIDLab chain has no EIP-1559 fee market, so every transaction must be legacy.
  const gasPrice = await publicClient.getGasPrice();
  const hash = await wallet.writeContract({ address: oracleAddress, abi, functionName, args, gasPrice });
  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  return receipt;
};

async function tick() {
  const current = await read('currentPeriod');
  const period = Number(current) - 1; // only a finished period may be reported
  if (period < 0) return;

  const [finalized] = await read('reading', [period]);
  if (finalized) {
    const [, mm, count] = await read('reading', [period]);
    console.log(`period ${period}: already settled at ${mm}mm from ${count} reports`);
    return;
  }

  const mine = await read('hasReported', [period, account.address]);
  if (!mine) {
    const mm = measure(period);
    const note = LIE && LIE !== true ? '  ← LYING' : '';
    console.log(`period ${period}: ${STATION} gauge reads ${mm}mm — reporting${note}`);
    try {
      await send('report', [period, mm]);
    } catch (e) {
      console.error(`  report failed: ${short(e)}`);
      return;
    }
  }

  const [count, quorum] = [await read('reporterCount', [period]), await read('quorum')];
  if (Number(count) >= Number(quorum)) {
    try {
      await send('finalize', [period]);
      const [, mm, n] = await read('reading', [period]);
      console.log(`period ${period}: FINALISED at ${mm}mm — the median of ${n} reports`);
    } catch (e) {
      // Someone else finalised first. That is fine: the answer does not depend on who asks.
      if (!String(e).includes('AlreadyFinalized')) console.error(`  finalize failed: ${short(e)}`);
    }
  } else {
    console.log(`period ${period}: ${count} of ${quorum} reports in — waiting for the others`);
  }
}

/**
 * Keep the part of a viem error that says WHY. The custom error name lives several lines
 * into the message, so taking only the first line — as this did — throws away the answer
 * and leaves you staring at "reverted with the following signature:".
 */
const short = (e) => {
  const name = e?.cause?.data?.errorName || e?.data?.errorName;
  if (name) return name;
  const text = String(e?.shortMessage || e?.metaMessages?.join(' ') || e?.message || e);
  const line = text.split('\n').find((l) => /Error:|revert|0x[0-9a-f]{8}/i.test(l) && l.trim());
  return (line || text).trim().slice(0, 200);
};

/* -------------------------------------------------------------------------- main */

/**
 * Check the two things this node needs before it starts signing: the reporter role, and
 * gas. Both fail as an opaque revert deep in a loop otherwise, and a node that cannot work
 * should say so on the first line rather than once a minute for ever.
 */
async function preflight() {
  const problems = [];

  const REPORTER_ROLE = '0x3204c940063673962b481a0395619b3dbbd137589c419e993978c1c71bcf68ec';
  const appointed = await publicClient.readContract({
    address: oracleAddress,
    abi: [
      {
        type: 'function',
        name: 'hasRole',
        inputs: [{ type: 'bytes32' }, { type: 'address' }],
        outputs: [{ type: 'bool' }],
        stateMutability: 'view',
      },
    ],
    functionName: 'hasRole',
    args: [REPORTER_ROLE, account.address],
  });
  if (!appointed) {
    problems.push(
      `${account.address} does not hold REPORTER_ROLE. The town admin appoints it:\n` +
        `  cast send ${oracleAddress} "grantRole(bytes32,address)" \\\n` +
        `    ${REPORTER_ROLE} ${account.address} \\\n` +
        `    --rpc-url ${RPC} --legacy --interactive`,
    );
  }

  const balance = await publicClient.getBalance({ address: account.address });
  if (balance === 0n) {
    problems.push(`${account.address} has no TRUST for gas — send it some from the faucet.`);
  }

  if (problems.length) {
    console.error(`\ncannot report:\n\n${problems.join('\n\n')}\n`);
    process.exit(1);
  }
}

await preflight();

const periodSeconds = Number(await read('periodSeconds'));
console.log(
  `rain-reporter · station ${STATION} · ${account.address}\n` +
    `oracle ${oracleAddress} · period ${periodSeconds}s${LIE && LIE !== true ? ` · LYING ${LIE}mm` : ''}` +
    `${DROUGHT ? ' · drought mode' : ''}`,
);

await tick();
if (!ONCE) {
  // Check a few times per period: reporters that all wake at the same instant collide on
  // the same nonce-free chain quite happily, but staggering keeps the logs readable.
  const interval = Math.max(15, Math.floor(periodSeconds / 4)) * 1000;
  setInterval(() => {
    tick().catch((e) => console.error(short(e)));
  }, interval);
}
