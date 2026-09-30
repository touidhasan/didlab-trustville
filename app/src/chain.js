import { createPublicClient, defineChain, http } from 'viem';

/**
 * Which chain this build talks to.
 *
 * Defaults to DIDLab, so `npm run build` with no configuration produces the public site.
 * Override with a .env file (see app/.env.example) to point a fork at a local anvil chain
 * or at your own deployment — that is what makes the repo forkable rather than merely
 * readable.
 */
const env = import.meta.env;
const num = (v, fallback) => (v === undefined || v === '' ? fallback : Number(v));

export const CHAIN_ID = num(env.VITE_CHAIN_ID, 252501);
const RPC_URL = env.VITE_RPC_URL || 'https://eth.didlab.org';
const CHAIN_NAME = env.VITE_CHAIN_NAME || 'DIDLab';
const CURRENCY = env.VITE_CURRENCY_SYMBOL || 'TRUST';
const CURRENCY_NAME = env.VITE_CURRENCY_NAME || 'Trust';

export const didlab = defineChain({
  id: CHAIN_ID,
  name: CHAIN_NAME,
  nativeCurrency: { name: CURRENCY_NAME, symbol: CURRENCY, decimals: 18 },
  rpcUrls: { default: { http: [RPC_URL] } },
  blockExplorers: env.VITE_EXPLORER_URL
    ? { default: { name: `${CHAIN_NAME} Explorer`, url: env.VITE_EXPLORER_URL } }
    : CHAIN_ID === 252501
      ? { default: { name: 'DIDLab Explorer', url: 'https://explorer.didlab.org' } }
      : undefined,
});

export const CHAIN_ID_HEX = '0x' + didlab.id.toString(16);

/** A local chain has no faucet and no explorer; the UI hides those rather than lying. */
export const FAUCET_URL =
  env.VITE_FAUCET_URL !== undefined
    ? env.VITE_FAUCET_URL
    : CHAIN_ID === 252501
      ? 'https://faucet.didlab.org'
      : '';

export const EXPLORER = didlab.blockExplorers?.default.url ?? '';

/**
 * Where the module guides live.
 *
 * `npm run build` publishes the guides inside the site at /labs/, so by default every copy
 * of the town links to the guides it carries itself. Set VITE_DOCS_BASE to point elsewhere
 * (the repository on GitHub, for a development server that has no /labs/).
 */
export const DOCS_BASE = env.VITE_DOCS_BASE || '/labs/modules';

export const guideUrl = (slug) => {
  // GitHub shows the Markdown source; the built guides are .html files, and the modules'
  // README.md is served as index.html.
  if (DOCS_BASE.includes('github.com')) return `${DOCS_BASE}/${slug}.md`;
  return `${DOCS_BASE}/${slug === 'README' ? 'index' : slug}.html`;
};

export const explorerTx = (hash) => (EXPLORER ? `${EXPLORER}/tx/${hash}` : '');
export const explorerAddress = (addr) => (EXPLORER ? `${EXPLORER}/address/${addr}` : '');

// Params for MetaMask's wallet_addEthereumChain (EIP-3085).
export const addChainParams = {
  chainId: CHAIN_ID_HEX,
  chainName: CHAIN_NAME,
  nativeCurrency: didlab.nativeCurrency,
  rpcUrls: didlab.rpcUrls.default.http,
  ...(EXPLORER ? { blockExplorerUrls: [EXPLORER] } : {}),
};

export const publicClient = createPublicClient({ chain: didlab, transport: http() });

/**
 * Addresses come from deployments/<chainId>.json. Every deployments file is bundled at
 * build time and the right one is picked by chain id, so switching chains is a matter of
 * configuration rather than a code edit — and a deployment file that does not exist yet
 * simply means no contracts, which every module already renders as "not deployed yet".
 */
const files = import.meta.glob('../../deployments/*.json', { eager: true });
const entry = files[`../../deployments/${CHAIN_ID}.json`];

if (!entry && import.meta.env.DEV) {
  console.warn(
    `No deployments/${CHAIN_ID}.json — deploy the contracts for this chain, then run ` +
      '"npm run sync-abi". Every stop will show as not deployed until then.',
  );
}

export const contracts = entry?.contracts ?? entry?.default?.contracts ?? {};
