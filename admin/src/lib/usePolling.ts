import { useEffect, useRef } from 'react';

/**
 * Re-runs `callback` every `intervalMs` for as long as the calling
 * component is mounted, so pages reflect changes made elsewhere (another
 * admin, a driver/commuter action) without the user having to hit
 * refresh. `callback` is captured in a ref rather than the effect's own
 * dependency array so a page's fetch function can be a plain inline
 * closure without needing `useCallback` to keep the interval stable.
 * Pauses while the tab is hidden so backgrounded tabs don't keep
 * hammering the API.
 */
export function usePolling(callback: () => void, intervalMs: number) {
  const savedCallback = useRef(callback);

  useEffect(() => {
    savedCallback.current = callback;
  }, [callback]);

  useEffect(() => {
    const id = setInterval(() => {
      if (document.visibilityState === 'visible') {
        savedCallback.current();
      }
    }, intervalMs);
    return () => clearInterval(id);
  }, [intervalMs]);
}
