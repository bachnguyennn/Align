import { createContext, useContext, useSyncExternalStore } from 'react';

export const SimContext = createContext(null);

export function useSimulation() {
  return useContext(SimContext);
}

/**
 * Subscribes to one derived value of the simulation. The component re-renders only when the
 * selected value changes, so return primitives (round numbers to what is displayed).
 */
export function useSim(selector) {
  const sim = useContext(SimContext);
  return useSyncExternalStore(sim.subscribe, () => selector(sim.getSnapshot()));
}
