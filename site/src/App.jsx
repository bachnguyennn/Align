import { useEffect, useState } from 'react';
import { Simulation } from './sim/simulation.js';
import { SimContext } from './sim/useSim.js';
import Nav from './components/Nav.jsx';
import Hero from './components/Hero.jsx';
import Detector from './components/Detector.jsx';
import Evidence from './components/Evidence.jsx';
import Decisions from './components/Decisions.jsx';
import Hardware from './components/Hardware.jsx';
import Footer from './components/Footer.jsx';

export default function App() {
  const [sim] = useState(() => new Simulation());

  useEffect(() => {
    sim.start();
    // Show the detector at work on arrival, unless the visitor prefers reduced motion.
    const calm = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    if (!calm && sim.getSnapshot().scenario === null && sim.history.length < 50) sim.play('slouch');
    return () => sim.stop();
  }, [sim]);

  return (
    <SimContext.Provider value={sim}>
      <a className="skip" href="#detector">Skip to the detector</a>
      <Nav />
      <main>
        <Hero />
        <Detector />
        <Evidence />
        <Decisions />
        <Hardware />
      </main>
      <Footer />
    </SimContext.Provider>
  );
}
