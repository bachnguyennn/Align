# AirPods head-motion feasibility (S-01)

Owner: Sensor agent. Status: desk research, written 2026-10-31. **Nothing in this document has
been tested on hardware yet.** Hardware results go in §9 after the user runs the protocol in §8
(task S-05).

Each statement is labelled:

- **[Doc]**: stated in Apple documentation, WWDC sessions or Apple support pages (linked).
- **[Community]**: reported by third-party developers, open-source projects or papers. Plausible
  but not authoritative.
- **[Unverified]**: our inference, or contradictory or missing evidence. **Must be tested on
  hardware.**

## 1. Summary

| Question | Answer | Confidence |
|---|---|---|
| API | `CMHeadphoneMotionManager` (Core Motion), iOS/iPadOS 14+, macOS 14+, watchOS 7+ | [Doc] |
| Our minimum | iOS 17 (D-004), so every API used here is available | [Doc] |
| Info.plist | `NSMotionUsageDescription` is required. Without it the app crashes when updates start | [Doc] |
| Supported headphones | AirPods Pro (all generations), AirPods Max, AirPods 3rd gen and later. Some Beats models are reported to work | [Doc] for AirPods, [Community] for Beats |
| Data | `CMDeviceMotion`: attitude, gravity, rotationRate, userAcceleration, sensorLocation, timestamp | [Doc] |
| Head-frame axes | +Z points up out of the head. X runs ear to ear and Y front to back. Which ear +X points at (and so the signs) is not stated in text | [Doc] picture only; signs [Unverified] |
| `HeadAxisConvention.airPodsDefault` | **At least one of its two signs must be wrong** if Apple's frame is right-handed with +Z up (§5.3) | Math; must test on hardware |
| Update rate | Reported as 25 Hz and cannot be configured. One third-party source claims about 100 Hz | [Community]; conflicting |
| Background or locked screen | No documented support and no background mode for motion. One forum report says updates stop in background | [Unverified]; plan for **foreground-only** |

## 2. API surface

Sources: [CMHeadphoneMotionManager][mgr], [CMHeadphoneMotionManagerDelegate][dlg],
[WWDC23 "What's new in Core Motion" (10179)][wwdc23].

- **[Doc]** `class CMHeadphoneMotionManager`. Availability: iOS 14.0, iPadOS 14.0, Mac Catalyst
  14.0, macOS 14.0, watchOS 7.0 (Apple doc metadata). It came to macOS in macOS 14 (WWDC23).
- **[Doc]** Availability check: instance property `var isDeviceMotionAvailable: Bool`, "whether the
  current device supports the headphone motion manager" ([doc][avail]). Also
  `isDeviceMotionActive` and `isConnectionStatusActive`.
- **[Unverified]** Whether `isDeviceMotionAvailable` depends on headphones being connected, or
  only on the phone and OS, is undocumented. Our provider treats `false` as
  `.unavailable(.motionNotSupported)`. Test this with the AirPods disconnected (§8, step 2).
- **[Doc]** Authorization: `class func authorizationStatus() -> CMAuthorizationStatus` ([doc][auth])
  returns `.notDetermined`, `.restricted`, `.denied` or `.authorized` ([CMAuthorizationStatus][authst]).
  There is no explicit request API. **[Community/Unverified]** The permission prompt appears
  when updates first start, as with other Core Motion APIs.
- **[Doc]** Updates: `startDeviceMotionUpdates()` (polling through `deviceMotion`) or
  `startDeviceMotionUpdates(to: OperationQueue, withHandler: @escaping (CMDeviceMotion?, Error?) -> Void)`
  ([doc][start]). Stop with `stopDeviceMotionUpdates()`. **No update-interval property exists**,
  unlike `CMMotionManager.deviceMotionUpdateInterval`.
- **[Doc]** Connection-only updates: `startConnectionStatusUpdates()` /
  `stopConnectionStatusUpdates()` ([doc][conn]). Apple's page has no discussion text. Not used in
  v1. It could show "AirPods connected" before monitoring starts.
- **[Doc]** Delegate: `protocol CMHeadphoneMotionManagerDelegate : NSObjectProtocol` with optional
  `headphoneMotionManagerDidConnect(_:)` and `headphoneMotionManagerDidDisconnect(_:)`
  ([doc][dlg]). Because it inherits `NSObjectProtocol`, the delegate must be an `NSObject`.
- **[Doc, WWDC23]** "You'll get a disconnect event when the buds are taken out of ear, and a
  connect event when they're put back in". This depends on Automatic Ear Detection. Data
  is streamed **from one bud at a time**, and if the streaming bud is removed (with ear
  detection on), the other bud takes over ([wwdc23]).
- **[Unverified]** Which thread the delegate is called on is undocumented. Our provider hops to
  the main queue explicitly.
- **[Unverified]** Whether `didConnect` fires when updates start with AirPods *already*
  connected. There is no "is connected" property, so our provider starts in
  `.waitingForHeadphones` and switches to `.connected` on `didConnect` **or** on the first sample.

## 3. Supported hardware

- **[Doc]** Apple's support page on Spatial Audio and head tracking says: "AirPods 3, AirPods 4,
  AirPods 5, AirPods Pro, and AirPods Max use Spatial Audio and head tracking" ([Apple
  support 102469][support]). AirPods 1st and 2nd generation are not listed.
- **[Doc]** Apple's API page shows axis diagrams for **AirPods Max and AirPods Pro** ([mgr]).
  WWDC23 names "audio products that support spatial audio with dynamic head tracking, like
  AirPods Pro" ([wwdc23]).
- **[Community]** flutter_airpods: "Only AirPods (3. Generation), AirPods Pro, AirPods Max und
  Beats Fit Pro are supported" ([flutter_airpods]). The Scripting app docs list AirPods Pro, Max
  and 3 ([scripting]). The WorkWell posture app requires "AirPods Pro (2nd generation or later)"
  ([workwell]). One Apple forum reply reports it working with AirPods Pro 3 (search result, not
  reviewed in detail).
- **[Unverified]** Other Beats models with head tracking (e.g. Powerbeats Pro 2, Beats Studio
  Pro, Beats Solo 4) and AirPods 4 (non-ANC). In the app, rely on runtime behaviour (samples
  arrive), not on a model list. Do not hard-code model names. The compatibility screen can
  name "AirPods Pro, AirPods Max, AirPods (3rd generation or later)" as examples.
- **[Doc]** Also needed: an iPhone with iOS 14+ (our app needs iOS 17). The simulator has no
  headphone motion, so use `MockSensorProvider` there.

## 4. Data fields (`CMDeviceMotion`)

Sources: [CMDeviceMotion][dm], [gravity][grav], [sensorLocation][sloc], [CMLogItem.timestamp][ts].

| Field | Type | Meaning | Mapped to `MotionSample` |
|---|---|---|---|
| `timestamp` | `TimeInterval` | "the amount of time in seconds since the device booted" **[Doc]** | `timestamp` |
| `attitude` | `CMAttitude` (`.quaternion`, `.rotationMatrix`, roll/pitch/yaw) | Orientation relative to a reference frame. **[Community]** The heading reference recentres, e.g. when Spatial Audio playback starts ([forum 844940][yaw]) | `attitude` (x, y, z, w) |
| `gravity` | `CMAcceleration` (g) | "The gravity acceleration vector expressed in the device's reference frame" **[Doc]** | `gravity` |
| `rotationRate` | `CMRotationRate` (rad/s) | Rotation rate in the device frame **[Doc]** | `rotationRate` |
| `userAcceleration` | `CMAcceleration` (g) | Acceleration minus gravity **[Doc]** | `userAcceleration` |
| `sensorLocation` | `CMDeviceMotion.SensorLocation` (`.default`, `.headphoneLeft`, `.headphoneRight`) | Which bud produced the sample. iOS 14+ **[Doc]** | `sensorLocation` (`.default` → `.unknown`) |
| `magneticField`, `heading` | — | **[Unverified]** Probably not meaningful for headphones. Not mapped | — |

- **[Doc]** The headphone frame is the *device* frame of the headphones, so `gravity` is the
  head-frame gravity used by D-005 directly.
- **[Community]** The EarDA paper (AirPods Pro 2) says: "IMU signals from each earbud in a pair are fused
  together automatically in API to represent the motion signals of the head" ([EarDA]). That
  conflicts with WWDC23's "one bud at a time" with hand-off. **[Unverified]** Whether the
  head-frame axes stay the same when the stream switches from the left bud to the right bud
  is not documented. Test this (§8, step 4). A frame change on hand-off would shift
  gravity and could look like a sudden tilt.

## 5. Head-frame axes and `HeadAxisConvention`

### 5.1 What Apple documents

**[Doc]** The API page says "To interpret attitude data, you need to know the orientation of
the device's coordinate axes" and shows an illustration (alt text: "AirPods Max and AirPods Pro
with labels representing the positive x-axis, positive y-axis, and positive z-axis") ([mgr]).
From the illustration (our reading of the picture, not text):

- **+Z points up**, out of the top of the head (AirPods Max headband / top of each earbud).
- **X runs along the AirPods Max headband**, so ear to ear.
- **Y is perpendicular to the headband** and horizontal, so front to back.
- The picture does not let us say for certain **which ear +X points toward**, or whether +Y
  points to the nose or the back of the head. **[Unverified]**

### 5.2 Community reports on signs

- **[Community]** WorkWell (AirPods posture app) defines pitch as "Rotation around the lateral axis
  (head nodding up/down)" and uses a forward-tilt threshold of "−22°", which suggests **pitch is
  negative when looking down** ([workwell]).
- **[Community]** The MacPaw headphone-accessibility prototype treats pitch above a positive
  threshold as "up" and below a negative threshold as "down" ([macpaw]). This agrees with
  WorkWell.
- Both use `CMAttitude.pitch` (an Euler angle about X), not gravity. Near a neutral reference
  its sign matches the sign of the head's rotation about +X.
- No usable community report on the roll (ear-to-shoulder) sign was found.

### 5.3 Consequence for `HeadAxisConvention.airPodsDefault` (important)

`airPodsDefault` is `forwardAxis = +X` (positive rotation = chin down) and
`lateralAxis = +Y` (positive rotation = right ear to right shoulder).

Physically, with right = r, nose = f, up = u:

- Chin-down is a positive (right-hand rule) rotation about the **left-pointing** axis (−r).
- Right-ear-down is a positive rotation about the **nose-pointing** axis (+f).
- So `forwardAxis × lateralAxis = (−r) × f = −u` (**down**). We checked this numerically.

Apple's frame is right-handed with +Z up when worn, so `+X × +Y = +Z` (**up**). **So
`airPodsDefault` cannot be right for both axes.** Exactly one sign has to change. With +Z up,
the two consistent options are:

| Hypothesis | +X points to | +Y points to | forwardAxis | lateralAxis | Evidence |
|---|---|---|---|---|---|
| **H1** | right ear | nose | (−1, 0, 0) | (0, +1, 0) | Matches both community reports (pitch < 0 looking down) |
| **H2** | left ear | back of head | (+1, 0, 0) | (0, −1, 0) | Keeps the current forwardAxis |

H1 is the better-supported guess, but **neither is verified**. The S-05 protocol (§8) settles
it from gravity alone. Rule of thumb: the convention must satisfy
`forwardAxis × lateralAxis ≈ (0, 0, −1)` (the head-frame down direction at neutral).

### 5.4 How to read the axes off hardware (no Euler angles needed)

For a head rotation by +θ about head axis **a**, head-frame gravity rotates by −θ about **a**.
With neutral gravity `g0` and gravity after a deliberate movement `g1`:

```
a = normalize(g1 × g0)
forwardAxis = normalize(g_chinDown × g_neutral)
lateralAxis = normalize(g_rightEarDown × g_neutral)
```

Example under the current default: a +20° chin-down about +X gives
`g1 = (0, −sin 20°, −cos 20°)`, and `g1 × g0 = (+sin 20°, 0, 0)`, so the axis is +X. The mock
(`MockMotionGenerator`) produces exactly this, and `MockMotionGeneratorTests` checks it.

During the movement, the sign of `rotationRate` along the axis should match. That is a second,
independent check.

## 6. Update rate

- **[Doc]** There is no rate setting on `CMHeadphoneMotionManager` ([mgr]). WWDC23 gives rates
  only for `CMMotionManager` and `CMBatchedSensorManager`, not for headphones ([wwdc23]).
- **[Community]** EarDA (AirPods Pro 2): "The sampling rate of Airpods was set to the highest
  value allowed by API, which is 25 Hz" ([EarDA]).
- **[Community, conflicting]** A third-party sensor framework (AWARE, AirPods module) is
  reported to state about 100 Hz "controlled by the AirPods firmware". This came from a search
  summary. We did not read or verify it.
- **[Unverified]** The real rate, jitter and gaps (e.g. during bud hand-off or Bluetooth
  congestion). The posture pipeline must not assume a fixed rate. It uses timestamps,
  `maxProcessingRateHz` and `maxSampleGap`. `SampleRateMeter` reports the delivered rate and
  the largest gap on the Diagnostics screen.

## 7. Background and locked-screen behaviour

**Plan for foreground-only monitoring. We do not claim that background monitoring works.**

- **[Doc]** iOS has no background mode for motion. The documented `UIBackgroundModes` values are
  audio, bluetooth-central, bluetooth-peripheral, external-accessory, fetch, location,
  nearby-interaction, network-authentication, newsstand-content, processing, push-to-talk,
  remote-notification, screen-capture and voip ([UIBackgroundModes][bgmodes]). None of them
  covers headphone motion.
- **[Doc]** App Review Guideline 2.5.4: "Multitasking apps may only use background services for
  their intended purposes: VoIP, audio playback, location, task completion, local
  notifications, etc." ([guidelines]). Declaring `audio` and playing silence only to keep
  motion streaming is **not** an intended purpose and is a rejection risk.
- **[Community]** An Apple forum post reports that headphone motion data stops when the app goes
  to the background ([forum 715100][bg]). The only reply suggests a "Motion & Fitness"
  background mode, which **does not exist** in Xcode's Background Modes list. Treat the reply
  as wrong.
- **[Unverified]** Whether updates continue for a short time after backgrounding, while the
  screen is locked with the app in front, or while *another* app plays audio. Whether
  `beginBackgroundTask` (about 30 s of task completion) keeps updates flowing. All of these go
  to §8.
- **[Unverified]** Whether a legitimate `audio` background session (e.g. if the app played real
  audio cues) would keep headphone motion streaming. Even if it did, using it only for posture
  monitoring breaks 2.5.4. Out of scope for the MVP.

Product implications for the MVP:

1. Monitoring runs while Align is in the foreground. The UI says so plainly ("Keep Align open
   while monitoring").
2. Optional user setting: keep the screen awake while monitoring
   (`UIApplication.shared.isIdleTimerDisabled = true`, foreground only), with a battery note.
3. On `scenePhase` → `.background`: call `provider.stop()` and `PostureMonitor.interrupt(at:)`.
   This closes any open episode honestly. On `.active`: restart.
4. Reminders: in-app banner plus haptics while in the foreground. Local notifications cannot be
   triggered by posture detection in the background, because no samples arrive.

## 8. Hardware test protocol (S-05) for the user

**Equipment:** iPhone on iOS 17+, AirPods Pro (note the generation and firmware: Settings →
Bluetooth → ⓘ), Align debug build with the Diagnostics screen (F-02). The Diagnostics screen
should show: connection state, authorization, `sensorLocation`, gravity (x, y, z to three
decimals), rotationRate, attitude quaternion, `SampleRateMeter.samplesPerSecond` and
`largestGap`, plus an event log with timestamps. Ideally add a "capture" button that logs the
current mean gravity over 1 s.

**Record:** iPhone model, iOS version, AirPods model and firmware, whether Automatic Ear
Detection is on, and the Spatial Audio / head-tracking setting in Control Centre.

1. **Permission.** Fresh install, start streaming. Note when the prompt appears and its text.
   Deny it. Expect state `.unavailable(.notAuthorized)` (or `.failed`: note which, and the
   message). Re-enable in Settings → Privacy & Security → Motion & Fitness, then return to the
   app.
2. **Availability.** With the AirPods in the case (lid closed), start streaming. Note
   `isMotionAvailable` and the state (`.waitingForHeadphones` expected). Repeat with Bluetooth
   off.
3. **Axes and signs (most important).** Sit upright, look straight ahead, both buds in.
   1. Capture **g_neutral** (hold still 3 s). Expected about (0, 0, −1) if +Z is up.
   2. Slowly nod **chin to chest** about 30°, hold, capture **g_chinDown**. While moving, note
      the sign of rotationRate x, y and z.
   3. Return to neutral. Tilt the **right ear to the right shoulder** about 20°, hold, capture
      **g_rightEarDown**. Note the rotationRate signs while moving.
   4. Return to neutral. **Turn the head right** about 45° (look over the right shoulder).
      Gravity should barely change (heading exclusion check).
   5. Compute `forwardAxis = normalize(g_chinDown × g_neutral)` and
      `lateralAxis = normalize(g_rightEarDown × g_neutral)`. Expect values close to ±unit X / ±unit Y.
      Check that `forwardAxis × lateralAxis ≈ (0, 0, −1)`.
   6. Quick sign table (if X/Y are as in §5.1): chin-down makes gravity.y **negative** →
      forwardAxis = +X, **positive** → −X. Right-ear-down makes gravity.x **positive** →
      lateralAxis = +Y, **negative** → −Y.
   7. Repeat 3.1–3.3 three times and with a second person if possible.
4. **Per bud.** Remove the right bud and repeat step 3 with the left only (note
   `sensorLocation`). Then right only. Are the axes and signs identical? Does gravity jump at
   the moment of hand-off?
5. **Sample rate.** Stream for 60 s holding still, then 60 s moving naturally. Record
   `samplesPerSecond` and `largestGap`. Repeat while playing music with Spatial Audio
   head-tracked, and with Spatial Audio off.
6. **Disconnects.** While streaming, (a) remove the bud that is streaming, (b) remove both buds,
   (c) put both back, (d) put the buds in the case and close the lid, (e) take them out again,
   (f) let the AirPods auto-switch to another Apple device, (g) turn Bluetooth off and on.
   For each, record: delegate events (state changes), the gap until samples resume, and any
   `.failed` message.
7. **Spatial Audio interaction.** While streaming and holding still, start playback of a
   Spatial Audio track. Does the attitude quaternion jump (reported yaw recentring)? Does
   gravity stay steady? (It should.)
8. **Screen lock.** While streaming in the foreground, press the side button. Wait 60 s, then
   unlock. Did samples continue (check the timestamps and `largestGap` in the log)? Repeat
   while music plays from the Music app.
9. **Background.** While streaming, go to the Home Screen for 10 s, 60 s and 5 min. Return.
   Record the gap and whether the stream resumed by itself or needed a restart, plus any errors.
10. **Long session and battery.** Stream for 30 min in the foreground (screen on). Record
    battery % (phone and AirPods) at the start and end, and compare the start and end neutral
    gravity (drift in degrees).

Write the results into §9, including raw captured vectors. Then update
`HeadAxisConvention.airPodsDefault` through the Lead (decisions.md), and remove the
"UNVERIFIED" note only for what was actually measured.

## 9. Hardware results

_Not run yet (blocked on X-02: needs the user's iPhone and AirPods Pro)._

| Step | Result | Date / device |
|---|---|---|
| 3 axes | — | — |
| 4 per bud | — | — |
| 5 rate | — | — |
| 6 disconnects | — | — |
| 8 lock | — | — |
| 9 background | — | — |

## 10. Recommended app configuration (for the Frontend agent)

- **Info.plist, required:** `NSMotionUsageDescription`. Suggested text: "Align uses your
  AirPods' motion sensors to notice when your head stays tilted forward or sideways, so it can
  remind you to reset your posture. Motion data stays on your iPhone." **[Doc]** Without it the
  system terminates the app when updates start ([mgr]).
- **`UIBackgroundModes`: none** for the MVP. Do not add `audio`, `location` or `processing` for
  monitoring (§7, Guideline 2.5.4).
- No `UIRequiredDeviceCapabilities` entry for headphones (none exists). Detect support at runtime
  with `isMotionAvailable`, the authorization state and whether samples arrive.
- Use `MockSensorProvider` in the simulator and in SwiftUI previews (`#if targetEnvironment(simulator)`
  or a debug setting). `RealAirPodsSensorProvider` exists only on iOS (`#if os(iOS)`).
- Lifecycle: stop the provider on `.background`, restart on `.active`, and call
  `PostureMonitor.interrupt(at:)` on every `.waitingForHeadphones`, `.failed` or stop.
- Wording: wellness and "reminders", never "diagnosis" or "treatment" (App Review 1.4.1 covers
  medical claims).

## Sources

- [mgr]: https://developer.apple.com/documentation/coremotion/cmheadphonemotionmanager
- [avail]: https://developer.apple.com/documentation/coremotion/cmheadphonemotionmanager/isdevicemotionavailable
- [auth]: https://developer.apple.com/documentation/coremotion/cmheadphonemotionmanager/authorizationstatus()
- [authst]: https://developer.apple.com/documentation/coremotion/cmauthorizationstatus
- [start]: https://developer.apple.com/documentation/coremotion/cmheadphonemotionmanager/startdevicemotionupdates(to:withhandler:)
- [conn]: https://developer.apple.com/documentation/coremotion/cmheadphonemotionmanager/startconnectionstatusupdates()
- [dlg]: https://developer.apple.com/documentation/coremotion/cmheadphonemotionmanagerdelegate
- [dm]: https://developer.apple.com/documentation/coremotion/cmdevicemotion
- [grav]: https://developer.apple.com/documentation/coremotion/cmdevicemotion/gravity
- [sloc]: https://developer.apple.com/documentation/coremotion/cmdevicemotion/sensorlocation-swift.property
- [ts]: https://developer.apple.com/documentation/coremotion/cmlogitem/timestamp
- [wwdc23]: https://developer.apple.com/videos/play/wwdc2023/10179/ (transcript: https://nonstrict.eu/wwdcindex/wwdc2023/10179/)
- [support]: https://support.apple.com/en-us/102469
- [guidelines]: https://developer.apple.com/app-store/review/guidelines/ (2.5.4, 1.4.1)
- [bgmodes]: https://developer.apple.com/documentation/bundleresources/information-property-list/uibackgroundmodes
- [bg]: https://developer.apple.com/forums/thread/715100
- [yaw]: https://developer.apple.com/forums/thread/844940
- [EarDA]: https://arxiv.org/html/2406.16943v1
- [workwell]: https://github.com/wizenheimer/workwell
- [macpaw]: https://research.macpaw.com/publications/headphones-accessibility
- [flutter_airpods]: https://pub.dev/documentation/flutter_airpods/latest/
- [scripting]: https://scriptingapp.github.io/TestFlight/guide/Utilities/HeadphoneMotionManager

[mgr]: https://developer.apple.com/documentation/coremotion/cmheadphonemotionmanager
[avail]: https://developer.apple.com/documentation/coremotion/cmheadphonemotionmanager/isdevicemotionavailable
[auth]: https://developer.apple.com/documentation/coremotion/cmheadphonemotionmanager/authorizationstatus()
[authst]: https://developer.apple.com/documentation/coremotion/cmauthorizationstatus
[start]: https://developer.apple.com/documentation/coremotion/cmheadphonemotionmanager/startdevicemotionupdates(to:withhandler:)
[conn]: https://developer.apple.com/documentation/coremotion/cmheadphonemotionmanager/startconnectionstatusupdates()
[dlg]: https://developer.apple.com/documentation/coremotion/cmheadphonemotionmanagerdelegate
[dm]: https://developer.apple.com/documentation/coremotion/cmdevicemotion
[grav]: https://developer.apple.com/documentation/coremotion/cmdevicemotion/gravity
[sloc]: https://developer.apple.com/documentation/coremotion/cmdevicemotion/sensorlocation-swift.property
[ts]: https://developer.apple.com/documentation/coremotion/cmlogitem/timestamp
[wwdc23]: https://developer.apple.com/videos/play/wwdc2023/10179/
[support]: https://support.apple.com/en-us/102469
[guidelines]: https://developer.apple.com/app-store/review/guidelines/
[bgmodes]: https://developer.apple.com/documentation/bundleresources/information-property-list/uibackgroundmodes
[bg]: https://developer.apple.com/forums/thread/715100
[yaw]: https://developer.apple.com/forums/thread/844940
[EarDA]: https://arxiv.org/html/2406.16943v1
[workwell]: https://github.com/wizenheimer/workwell
[macpaw]: https://research.macpaw.com/publications/headphones-accessibility
[flutter_airpods]: https://pub.dev/documentation/flutter_airpods/latest/
[scripting]: https://scriptingapp.github.io/TestFlight/guide/Utilities/HeadphoneMotionManager
