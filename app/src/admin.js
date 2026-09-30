import { useCallback, useEffect, useState } from 'react';
import { contracts, publicClient } from './chain.js';
import { useRefresh } from './refresh.js';

const DEFAULT_ADMIN_ROLE = `0x${'0'.repeat(64)}`;
const hasRoleAbi = [
  {
    type: 'function',
    name: 'hasRole',
    stateMutability: 'view',
    inputs: [
      { name: 'role', type: 'bytes32' },
      { name: 'account', type: 'address' },
    ],
    outputs: [{ type: 'bool' }],
  },
];

/**
 * Whether the connected account holds the town's admin role.
 *
 * Used only to decide whether to SHOW admin links. It is not a security boundary and never
 * can be: every admin function is guarded inside its contract, and anyone can call them from
 * any tool. Hiding the link just keeps the page tidy for the people who cannot use it.
 */
export function useIsAdmin(account) {
  const [isAdmin, setIsAdmin] = useState(false);
  const registry = contracts.ResidentRegistry;

  const load = useCallback(async () => {
    if (!account || !registry) return setIsAdmin(false);
    const held = await publicClient.readContract({
      address: registry,
      abi: hasRoleAbi,
      functionName: 'hasRole',
      args: [DEFAULT_ADMIN_ROLE, account],
    });
    setIsAdmin(Boolean(held));
  }, [account, registry]);

  useEffect(() => {
    load().catch(() => setIsAdmin(false));
  }, [load]);
  useRefresh(useCallback(() => load().catch(() => {}), [load]));

  return isAdmin;
}
