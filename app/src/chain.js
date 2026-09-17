import { createPublicClient, defineChain, http } from 'viem';
import deployments from '../../deployments/252501.json';

// Single source of truth for the DIDLab network settings.
export const didlab = defineChain({
  id: 252501,
  name: 'DIDLab',
  nativeCurrency: { name: 'Trust', symbol: 'TRUST', decimals: 18 },
  rpcUrls: { default: { http: ['https://eth.didlab.org'] } },
  blockExplorers: { default: { name: 'DIDLab Explorer', url: 'https://explorer.didlab.org' } },
});

export const CHAIN_ID_HEX = '0x' + didlab.id.toString(16); // 0x3da55
export const FAUCET_URL = 'https://faucet.didlab.org';
export const EXPLORER = didlab.blockExplorers.default.url;

export const explorerTx = (hash) => `${EXPLORER}/tx/${hash}`;
export const explorerAddress = (addr) => `${EXPLORER}/address/${addr}`;

// Params for MetaMask's wallet_addEthereumChain (EIP-3085).
export const addChainParams = {
  chainId: CHAIN_ID_HEX,
  chainName: 'DIDLab',
  nativeCurrency: didlab.nativeCurrency,
  rpcUrls: didlab.rpcUrls.default.http,
  blockExplorerUrls: [EXPLORER],
};

export const publicClient = createPublicClient({ chain: didlab, transport: http() });

// Contract addresses come only from deployments/252501.json.
export const contracts = deployments.contracts || {};
