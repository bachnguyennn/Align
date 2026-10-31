# Real motion recordings (D-017 (d))

This folder is for **real** AirPods head-motion sessions recorded with the app's opt-in
diagnostic recorder (Diagnostics → record, then share). It is empty on purpose: there are no real
recordings yet, and synthetic data must never be placed here or presented as real. Synthetic
fixtures live in `../motion`.

## Format

The recording format is defined in `../README.md` ("Recordings"): the fixture schema with
`samples`, `sampleRateHz`, `startTimestamp`, optional `config`, `baseline` and `actions`, and a
`recording` block (`appVersion`, `device`, `headphones`, `notes`, `createdAt`). There is no
`expected`, `reference`, `truth` or `generator` block. Name files
`<yyyy-mm-dd>-<short-description>.json`, e.g. `2026-11-02-desk-laptop.json`.

## Adding a recording

1. The person who recorded it shares the file from the app (the app never uploads it) and agrees
   that it may be committed. A recording is raw head motion: treat it as personal data. Keep
   `notes` free of names or other identifying details.
2. Put the file here and replay it:

   ```sh
   cd analytics/align-tools
   ./mvnw -q compile exec:java@replay -Dexec.args="../../shared/fixtures/recordings/2026-11-02-desk-laptop.json"
   ```

   Check the sample rate and largest gap, the calibration and axis-calibration outcomes, the
   learned yaw (how far the earbud sits from the default axes) and the tilt percentiles against
   what the person remembers doing (`notes`).
3. Try other settings without editing the file, e.g.
   `-Dexec.args="--set forwardThresholdDegrees=12 --set calibrationSpreadQuantile=1.0 <file>"`.
4. Turning a recording into a regression test is not wired up yet: the fixture suites require
   every file in `../motion` to be a generator scenario. The plan is a separate folder of
   recorded fixtures with an `expected` block written by hand from the person's own account (not
   from the pipeline's output) and a `reference` block from `exec:java@rereference`, replayed by
   both test suites.

Large sessions: about 75 KiB per minute at 25 Hz. Prefer trimmed excerpts of a few minutes
around the events of interest.
