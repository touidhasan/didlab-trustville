import { useEffect, useState } from 'react';

/**
 * A router small enough to read in one go.
 *
 * Addresses live after the `#` — `dapp.didlab.org/#/market` — so the site stays a folder of
 * static files: no server rewrite rule, nothing to configure on nginx, cPanel, a fork's
 * GitHub Pages or a client's private town. A library would add features this site does not
 * use and a dependency every student has to read past.
 *
 * `#start` and `#/start` are the same page, so links written before the router existed
 * still land where they meant to.
 */
const parse = () =>
  decodeURIComponent(window.location.hash.replace(/^#\/?/, ''))
    .split('/')
    .filter(Boolean);

export function useRoute() {
  const [parts, setParts] = useState(parse);

  useEffect(() => {
    const onChange = () => {
      setParts(parse());
      window.scrollTo(0, 0);
    };
    window.addEventListener('hashchange', onChange);
    return () => window.removeEventListener('hashchange', onChange);
  }, []);

  return parts;
}

/** `to('market')` → `#/market`. */
export const to = (...parts) => `#/${parts.filter(Boolean).join('/')}`;
