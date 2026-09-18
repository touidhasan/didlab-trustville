import { useEffect } from 'react';

// A transaction in one module can change what another module shows — claiming the
// welcome grant stamps your passport, for example. Each module reloads on this signal.
const listeners = new Set();

export function emitRefresh() {
  listeners.forEach((fn) => {
    try {
      fn();
    } catch {
      /* one bad listener must not stop the others */
    }
  });
}

export function useRefresh(fn) {
  useEffect(() => {
    listeners.add(fn);
    return () => listeners.delete(fn);
  }, [fn]);
}
