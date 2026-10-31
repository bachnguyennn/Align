# Try Align on your iPhone

A step-by-step guide for the first hardware test: install the app from Xcode, check that the
AirPods axes are right, and see a reminder fire. About **30 minutes** the first time.

The full protocol (every case, battery, offline, privacy) is in
[`docs/agents/test-plan.md`](docs/agents/test-plan.md). This page is the short version.

## What you need

- A Mac with **Xcode 16** (free from the App Store) and Homebrew
- An **iPhone on iOS 17+** and a USB cable (for the first install)
- **AirPods Pro** (1st or 2nd gen), AirPods Max, or AirPods 3rd gen or later
- An Apple ID. A free one works; the app then expires after 7 days and you just run it again.

## 1. Build and install (one time, ~10 min)

```sh
brew install xcodegen
git clone https://github.com/bachnguyennn/FixMySpine.git
cd FixMySpine/ios
xcodegen generate
open Align.xcodeproj
```

In Xcode:

1. **Xcode → Settings → Accounts** → **+** → sign in with your Apple ID.
2. In the left sidebar click **Align** (blue icon) → target **Align** → **Signing & Capabilities**
   → **Team**: pick your name (Personal Team).
   - If it says the bundle identifier is taken, change `com.bachnguyennn.align` to something
     unique, e.g. `com.bachnguyennn.align.dev`.
3. Plug in the iPhone and unlock it. Tap **Trust** if asked.
4. On the iPhone: **Settings → Privacy & Security → Developer Mode → On** (it restarts).
5. In Xcode's top bar, choose your iPhone as the run destination, then press **⌘R**.
6. The first time, iOS blocks the app: on the iPhone go to **Settings → General → VPN & Device
   Management** → your Apple ID → **Trust**. Press ⌘R again.

> `xcodegen generate` recreates the project, so you have to pick the Team again after running it.
> You only need to rerun it after pulling changes that add or remove files.

## 2. First launch (~2 min)

1. Put both AirPods in your ears and make sure they're connected to **this iPhone** (play a
   song for a second to be sure).
2. Open Align, go through the welcome screens, and **Allow** Motion & Fitness and notifications.
3. Turn off automatic switching so your Mac doesn't steal the AirPods mid-test:
   iPhone **Settings → [your AirPods] → Connect to This iPhone → When Last Connected to This iPhone**.

## 3. Axis check (~3 min): the most important step

Nothing else can be trusted until this passes. Go to **Settings → Diagnostics**.

1. Check **Sensor → Connection** says connected and **Sample rate** shows a number (write it down;
   we expect about 25 Hz).
2. Sit upright, look straight ahead, tap **Capture neutral gravity**.
3. Do each move, hold ~3 s, and write down the **Axis check** numbers:

| Move (about 20°) | Expected | You saw |
|---|---|---|
| Chin down toward chest | **Forward** ≈ +20 | |
| Look up at the ceiling | **Forward** ≈ −20 | |
| Right ear toward right shoulder | **Lateral** ≈ +20 | |
| Left ear toward left shoulder | **Lateral** ≈ −20 | |
| Turn head left / right (like saying "no") | both stay near 0 | |

Also write down the **Gravity (g)** line while sitting upright (three numbers).

If any sign is backwards or the wrong number moves, **stop here and report it**: it's a
one-line fix in the code.

## 4. Calibrate and try a reminder (~10 min)

To avoid waiting 5 minutes between reminders, first go to **Settings → Reminders → Spacing**
and set it to **2 minutes**. Keep **Sensitivity** on **Balanced** (15°, 30 s).

1. **Home → Calibrate → Start calibration.** Sit upright, look ahead, keep still for 10 s.
   Expected: progress fills and it succeeds.
2. **Home → Start monitoring**, then open **Live view**.
3. **Glance test:** look down at your lap for 3–5 s, then back up. Repeat a few times.
   Expected: it may briefly show "Tilting forward", but **no reminder**.
4. **Slouch test:** lean your head forward (like reading a phone on the desk) and **hold 45 s**.
   Expected: about **30 s** after you cross the line you get **one** reminder (haptic, plus a
   banner). Time it if you can.
5. **Keep holding** another minute. Expected: **no second reminder**.
6. **Sit back up.** Expected: back to neutral. **History** shows one forward tilt.
7. **Side test:** right ear toward right shoulder, hold 45 s (wait until 2 min after the last
   reminder). Expected: one reminder for a right tilt.

## 5. Disconnects and leaving the app (~5 min)

| Do this while monitoring | Expected | You saw |
|---|---|---|
| Take **one** AirPod out | Just observe: does it keep going? | |
| Take **both** out | Shows waiting/disconnected within ~1 s; no crash | |
| Put them back in | Resumes by itself, no recalibration | |
| Swipe home (leave the app) for 1 min, come back | Monitoring pauses while away, then resumes | |
| Lock the phone for 1 min, unlock, open Align | Same as above | |

Align only monitors while it's open on screen. That's expected for this version.

## 6. Report back

Open a GitHub issue using the **Hardware test report** template
([new issue](https://github.com/bachnguyennn/FixMySpine/issues/new?template=hardware-test.md))
and paste your tables. Screenshots of the Diagnostics screen help a lot. Or just paste the
results into our chat.

Things that are especially useful:

- The axis check table and upright gravity numbers
- Sample rate and largest gap from Diagnostics
- Seconds from slouching to the reminder
- Anything that felt wrong, confusing, or annoying

## Troubleshooting

| Problem | Fix |
|---|---|
| "Untrusted Developer" when opening the app | Settings → General → VPN & Device Management → Trust |
| Xcode: "Developer Mode disabled" | iPhone Settings → Privacy & Security → Developer Mode → On |
| Xcode: signing error / no Team | Xcode → Settings → Accounts, add your Apple ID, then pick the Team again |
| App stopped opening after a week | Free Apple ID builds expire after 7 days; press ⌘R in Xcode again |
| Stuck on "Waiting for your AirPods…" | Both buds in, connected to this iPhone (play audio once), reopen Align |
| "Motion access denied" | Settings → Privacy & Security → Motion & Fitness → Align on |
| No reminder banner | Settings → Notifications → Align → Allow; Focus/Do Not Disturb can hide it |
| Want to test without AirPods | Settings → Privacy & data → Demo mode (simulated head motion) |
