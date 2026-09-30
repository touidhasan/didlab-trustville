import { useCallback, useEffect, useState } from 'react';
import { trustvillePassportAbi } from './abi/generated.js';
import { contracts, publicClient } from './chain.js';
import { MODULE_NUMBERS } from './town.js';
import { useRefresh } from './refresh.js';

/**
 * Which modules this account has completed, read from its passport.
 *
 * Progress is not stored by the site. Every stamp is an on-chain record written by the
 * module's own contract when the student did the thing, so the map shows exactly what anyone
 * could check on the explorer — and a student cannot tick a box they did not earn.
 */
export function useStamps(account) {
  const [stamps, setStamps] = useState(() => new Set());
  const [hasPassport, setHasPassport] = useState(false);
  const passport = contracts.TrustvillePassport;

  const load = useCallback(async () => {
    if (!account || !passport) {
      setStamps(new Set());
      setHasPassport(false);
      return;
    }
    const id = await publicClient.readContract({
      address: passport,
      abi: trustvillePassportAbi,
      functionName: 'passportOf',
      args: [account],
    });
    setHasPassport(id > 0n);
    if (id === 0n) return setStamps(new Set());
    const list = await publicClient.readContract({
      address: passport,
      abi: trustvillePassportAbi,
      functionName: 'stampsOf',
      args: [account],
    });
    setStamps(new Set(list.map(Number)));
  }, [account, passport]);

  useEffect(() => {
    load().catch(() => {});
  }, [load]);
  useRefresh(useCallback(() => load().catch(() => {}), [load]));

  /** The lowest-numbered module not yet stamped, or null when all are done. */
  const nextModule = MODULE_NUMBERS.find((m) => !stamps.has(m)) ?? null;

  return { stamps, hasPassport, nextModule, done: MODULE_NUMBERS.filter((m) => stamps.has(m)).length };
}
