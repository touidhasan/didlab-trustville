import { useCallback, useEffect, useState } from 'react';
import { createWalletClient, custom } from 'viem';
import { addChainParams, CHAIN_ID_HEX, didlab, publicClient } from './chain.js';

const eth = () => (typeof window !== 'undefined' ? window.ethereum : undefined);

/** Minimal MetaMask hook built on raw EIP-1193 calls, so students can read every step. */
export function useWallet() {
  const [account, setAccount] = useState(null);
  const [chainId, setChainId] = useState(null);
  const [balance, setBalance] = useState(null);
  const [error, setError] = useState(null);
  const hasProvider = Boolean(eth());

  // Pick up an already-connected wallet without prompting.
  useEffect(() => {
    const p = eth();
    if (!p) return;
    p.request({ method: 'eth_accounts' }).then((a) => setAccount(a[0] || null)).catch(() => {});
    p.request({ method: 'eth_chainId' }).then((c) => setChainId(parseInt(c, 16))).catch(() => {});
    const onAccounts = (a) => setAccount(a[0] || null);
    const onChain = (c) => setChainId(parseInt(c, 16));
    p.on?.('accountsChanged', onAccounts);
    p.on?.('chainChanged', onChain);
    return () => {
      p.removeListener?.('accountsChanged', onAccounts);
      p.removeListener?.('chainChanged', onChain);
    };
  }, []);

  const onDidlab = chainId === didlab.id;

  // Poll the TRUST balance straight from eth.didlab.org.
  useEffect(() => {
    if (!account) return setBalance(null);
    let stop = false;
    const load = () =>
      publicClient
        .getBalance({ address: account })
        .then((b) => !stop && setBalance(b))
        .catch(() => {});
    load();
    const t = setInterval(load, 5000);
    return () => {
      stop = true;
      clearInterval(t);
    };
  }, [account]);

  const connect = useCallback(async () => {
    setError(null);
    try {
      const a = await eth().request({ method: 'eth_requestAccounts' });
      setAccount(a[0] || null);
    } catch (e) {
      setError(e.message);
    }
  }, []);

  const switchToDidlab = useCallback(async () => {
    setError(null);
    try {
      await eth().request({ method: 'wallet_switchEthereumChain', params: [{ chainId: CHAIN_ID_HEX }] });
    } catch (e) {
      // 4902 = chain not added to MetaMask yet
      if (e.code === 4902 || e?.data?.originalError?.code === 4902) {
        try {
          await eth().request({ method: 'wallet_addEthereumChain', params: [addChainParams] });
        } catch (e2) {
          setError(e2.message);
        }
      } else {
        setError(e.message);
      }
    }
  }, []);

  const walletClient =
    account && hasProvider
      ? createWalletClient({ account, chain: didlab, transport: custom(eth()) })
      : null;

  return { hasProvider, account, chainId, onDidlab, balance, error, connect, switchToDidlab, walletClient };
}
