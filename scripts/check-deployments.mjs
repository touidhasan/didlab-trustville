#!/usr/bin/env node
/**
 * Refuse to build a site that points at contracts this chain does not have.
 *
 *   node scripts/check-deployments.mjs          # runs first in `npm run build`
 *
 * On 2026-09-30 the rebuilt town went live with its very first stop, the Notice Board,
 * marked "Not open here": the board had never been recorded in deployments/252501.json.
 * The old one-page site had shown the same gap at the bottom of the page for two weeks and
 * nobody scrolled that far. A class would have found it in the first minute.
 *
 * The list of what the site needs is read from the site itself -- every `contracts.Name` the
 * app's code refers to -- so there is no second list here to fall out of step with it.
 */
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const SRC = join(ROOT, 'app/src');

// Which chain this build targets: the same rule as app/src/chain.js, including app/.env.
let chainId = process.env.VITE_CHAIN_ID;
const envFile = join(ROOT, 'app/.env');
if (!chainId && existsSync(envFile)) {
  const m = readFileSync(envFile, 'utf8').match(/^VITE_CHAIN_ID=(\d+)/m);
  if (m) chainId = m[1];
}
chainId = chainId || '252501';

const file = join(ROOT, 'deployments', `${chainId}.json`);
if (!existsSync(file)) {
  console.warn(`deployments/${chainId}.json does not exist: every stop will show as not open.`);
  console.warn('That is expected for a fresh fork. Deploy the contracts, then build again.');
  process.exit(0);
}
const deployed = JSON.parse(readFileSync(file, 'utf8')).contracts ?? {};

const files = [
  ...readdirSync(join(SRC, 'components')).map((f) => join(SRC, 'components', f)),
  ...readdirSync(SRC).filter((f) => f.endsWith('.js')).map((f) => join(SRC, f)),
].filter((f) => /\.(jsx?|mjs)$/.test(f));

const needed = new Map(); // name -> files that use it
for (const f of files) {
  for (const [, name] of readFileSync(f, 'utf8').matchAll(/contracts\.([A-Z][A-Za-z0-9]+)/g)) {
    if (!needed.has(name)) needed.set(name, new Set());
    needed.get(name).add(f.replace(`${ROOT}/`, ''));
  }
}

const missing = [...needed.keys()].filter((n) => !deployed[n]).sort();
if (missing.length) {
  console.error(`deployments/${chainId}.json is missing contracts the site uses:\n`);
  for (const n of missing) console.error(`  ${n.padEnd(22)} used by ${[...needed.get(n)].join(', ')}`);
  console.error('\nDeploy them (their script records the address), or remove the code that uses them.');
  console.error('Building anyway would publish stops that say "Not open here".');
  process.exit(1);
}
console.log(`deployments/${chainId}.json has all ${needed.size} contracts the site uses.`);
