# Align demo website

A one-page site that presents Align and runs its detection pipeline in the browser.

```sh
npm install
npm run dev      # local preview
npm test         # fixture parity + simulation tests
npm run build    # static output in dist/
```

- `src/engine/pipeline.js` is a JavaScript port of `ios/AlignKit/Sources/PostureDetection`
  (and of the Java reference in `analytics/align-tools`). `src/engine/fixtures.test.js` replays
  every file in `shared/fixtures/motion` (14 today) and compares the result with each file's
  `reference` block: same outcomes, directions, state transitions and learned axes, timestamps to 1e-6 s,
  degrees to 1e-3.
- `src/sim/simulation.js` feeds that pipeline with simulated head motion (scripted or user-set
  pose, sway, sensor noise, an earbud mounting offset). Nothing on the page reads real AirPods.
- `src/content.js` holds every fact the page states, with the repo file it comes from, and the
  author links shown in the footer.

The build uses a relative base path, so `dist/` can be served from any folder.

## Deployment

`.github/workflows/pages.yml` tests, builds and publishes the site to GitHub Pages on every push
to `main` that touches `site/` or `shared/fixtures/motion/`, and can be run by hand from the
Actions tab. It needs Settings → Pages → Source set to "GitHub Actions" once. The site is then
at https://bachnguyennn.github.io/Align/.
