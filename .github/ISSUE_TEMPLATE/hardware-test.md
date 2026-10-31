---
name: Hardware test report
about: Results from trying Align on an iPhone with AirPods (see TESTING.md)
title: "Hardware test: <iPhone model>, <AirPods model>"
labels: hardware-test
---

## Setup

- Date:
- App commit (`git rev-parse --short HEAD`):
- iPhone model / iOS version:
- AirPods model / firmware (Settings → AirPods → About):

## Axis check (Settings → Diagnostics)

Sample rate: ___ Hz · Largest gap: ___ ms
Upright gravity (g): ___ ___ ___

| Move (about 20°) | Expected | Saw |
|---|---|---|
| Chin down | Forward ≈ +20 | |
| Look up | Forward ≈ −20 | |
| Right ear down | Lateral ≈ +20 | |
| Left ear down | Lateral ≈ −20 | |
| Turn left / right | both near 0 | |

## Calibration and reminders

| Step | Expected | Saw |
|---|---|---|
| Calibrate | Succeeds after ~10 s | |
| Nod step (chin down 20–30° and back) | "All set" (tries: ___; any messages seen: ___) | |
| Diagnostics → Tilt axes in use | Axes "Learned from your nod"; learned yaw ___° | |
| Glance down 3–5 s, repeated | No reminder | |
| Hold forward tilt 45 s | One reminder ~30 s after crossing (seconds: ___) | |
| Keep holding 1 min | No second reminder | |
| Sit back up | Neutral; History shows one forward tilt | |
| Right ear down 45 s | One right reminder | |

## Disconnects and leaving the app

| Action | Expected | Saw |
|---|---|---|
| One AirPod out | Observe | |
| Both out | Waiting/disconnected within ~1 s | |
| Both back in | Resumes, no recalibration | |
| Leave the app 1 min | Pauses, resumes on return | |
| Lock phone 1 min | Pauses, resumes on return | |

Diagnostics → Stalls since launch at the end: ___

## Recordings (TESTING.md section 6)

Attach the shared `.json` files (zip them if the upload is refused). Only attach recordings you
agree may be used to tune Align; notes must not contain names.

- [ ] Sitting upright at a desk (2 min)
- [ ] Slouching at a desk (2 min)
- [ ] Looking down at a phone (2 min)

## Anything else

Bugs, confusing screens, things that felt wrong. Screenshots welcome.
