# Align — Privacy review (initial, pre-implementation)

Owner: QA / Security agent (task Q-04). Status: **initial review of the design**, written before
the app code exists. Everything below is a requirement or a check to run; nothing here has been
verified against a build yet. Re-run the checks in sections 3 and 7 once `ios/AlignApp` lands (F-06/F-09) and update
this file with real results.

Sources: `docs/agents/architecture.md`, `data-contracts.md`, `sensor-contracts.md`,
`api-contracts.md`, decisions D-007 (no raw motion persisted), D-008 (no backend in Phase 1),
D-010 (foreground-only MVP).

## 1. Summary

- Phase 1 design is **on-device only**: no backend, no network code, no third-party SDKs.
- Raw head motion is processed in memory and **not persisted** by default (D-007). Only
  aggregates (sessions) and sustained-tilt episodes are stored, in SwiftData on the phone.
- Head-posture history is health-adjacent data. It never leaves the device in Phase 1, except
  inside the user's own device/iCloud backups (Apple-operated, not collected by us).
- If the build matches the design, the App Store privacy label is **Data Not Collected** and
  **No tracking**.
- Action items before release: a privacy manifest declaring two required-reason APIs (§4.3), a
  clear motion purpose string (§4.1), delete-all coverage of every store (§5), and the checks in §3 and §7.

## 2. Data inventory

| Data | Source | Stored where | Retention | Leaves device? | Purpose | Sensitivity |
|---|---|---|---|---|---|---|
| Raw `MotionSample` (attitude, gravity, rotation rate, user acceleration, timestamp, earbud) | AirPods via `CMHeadphoneMotionManager` | **Memory only** (pipeline, live view, Diagnostics) | Until the next sample / screen closes | No | Tilt estimation | Medium: continuous motion can reveal activity patterns |
| Diagnostic motion recording (opt-in, D-017 (d); implemented in F-11, see §10) | Same, plus the baseline, configuration, calibration actions, app version, iPhone model identifier, the user's note | Memory while recording, then one file in the app's temporary folder | Until the user leaves Diagnostics, starts another recording, or relaunches the app | Only if the user shares it via the share sheet | Tuning on real data | Medium (see §10, R-03) |
| `NeutralBaseline` (mean gravity vector, `capturedAt`, sample count, version) | Calibration | UserDefaults (JSON) | Until recalibration or delete-all | No | Reference posture | Low |
| `PostureConfiguration`, sensitivity preset, reminder/sound/haptic flags, demo-mode flag | User settings | UserDefaults (JSON / scalars) | Until changed or delete-all | No | Behavior | Low |
| `MonitoringSession` (start/end, monitored/within-threshold/sustained seconds, reminder count, calibration version, sensor status) | Computed | SwiftData store in app sandbox | Until the user deletes it (no automatic expiry in v1) | No | History, daily summaries | Medium: daily posture/usage history |
| `PostureEvent` (start/end, direction, duration, peak degrees, reminder triggered) | Computed from `PostureEpisode` | SwiftData (cascade from session) | Same as session | No | History, analytics | Medium |
| `DailySummary` | Computed on demand | Not stored | — | No | Charts | — |
| Local notification content | `ReminderNotifier` | Notification Center (system) | Until dismissed | No (local notification, no push) | Reminder | Low, but visible on the lock screen (see R-06) |
| Connection / authorization state, sample-rate diagnostics | Core Motion | Memory | Session | No | Status UI | Low |

Not collected by design: name, email, account, contacts, location, advertising identifier,
device identifiers, Bluetooth device names/addresses, audio, HealthKit data, crash/analytics SDK
data.

## 3. On-device-only guarantees to verify

| ID | Guarantee | How to verify (once the app exists) |
|---|---|---|
| G-01 | No network code in Phase 1 | The grep below returns nothing except comments. |
| G-02 | No third-party SDKs | `ios/project.yml` lists only the local `AlignKit` package; no `Package.resolved` with remote packages; no CocoaPods/Carthage. |
| G-03 | No contact with any server at runtime | Device test O-02: Settings → Privacy & Security → App Privacy Report shows no network domains for Align after a day of use. |
| G-04 | Raw motion never persisted (D-007) | Code review of `Persistence/` and `MonitoringController`: no `MotionSample` / `SensorEvent` written to SwiftData, UserDefaults or files outside the developer toggle. After a 10-min session, inspect the app container (Xcode → Devices → Download Container): only the SwiftData store and preferences plist, sizes in KB. |
| G-05 | No raw values in logs | No `print`/`Logger` of motion values in release builds; any `Logger` interpolation of user data uses the default `.private` privacy. |
| G-06 | No cloud sync entitlements | Generated entitlements contain no iCloud/CloudKit, App Groups, HealthKit or Associated Domains; SwiftData `ModelConfiguration` uses `cloudKitDatabase: .none` (or the default with no CloudKit entitlement). |
| G-07 | No Bluetooth permission | No `NSBluetoothAlwaysUsageDescription` and no `CoreBluetooth` import; headphone motion does not need it. |
| G-08 | Foreground only (D-010) | No `UIBackgroundModes` in Info.plist; device tests N-03/N-04/B-03 show no background activity. |
| G-09 | No tracking | No `NSUserTrackingUsageDescription`, no AdSupport / AppTrackingTransparency import. |

G-01 grep:

```bash
git grep -nE 'URLSession|URLRequest|NWConnection|import Network|WebSocket|https?://' -- ios/
```

## 4. Permissions, purpose strings and manifest

### 4.1 Motion & Fitness (required)

`CMHeadphoneMotionManager` requires `NSMotionUsageDescription`; without it the app is terminated
when it starts headphone motion updates. Proposed text (plain, specific, no medical claim):

> Align uses the head movement measured by your AirPods to notice when your head stays tilted
> and remind you to reset. Motion data is processed on this iPhone and is not sent anywhere.

Ask in context (when the user first starts monitoring or opens Diagnostics), not at launch.
Handle `denied` and `restricted` with an explanation and a link to Settings (device test D-03).

### 4.2 Notifications

No Info.plist string. Request authorization with `UNUserNotificationCenter` the first time the
user enables reminders, after explaining why. Reminders must still work in-app (banner/haptic)
if notifications are denied (device test N-01). No remote push, so no `aps-environment`
entitlement.

### 4.3 Privacy manifest (`PrivacyInfo.xcprivacy`) — required

Apple requires a privacy manifest declaring "required reason" APIs. From the design:

| API used | Category | Reason code to declare |
|---|---|---|
| `UserDefaults` (settings, baseline) | `NSPrivacyAccessedAPICategoryUserDefaults` | `CA92.1` (read/write data only accessible to the app itself) |
| `ProcessInfo.processInfo.systemUptime` (monotonic timestamp → `Date`, architecture.md "Time") | `NSPrivacyAccessedAPICategorySystemBootTime` | `35F9.1` (measure elapsed time between in-app events) |

Plus `NSPrivacyTracking = false`, empty `NSPrivacyTrackingDomains`, and empty
`NSPrivacyCollectedDataTypes`. Re-check the list against Apple's current required-reason API
documentation once the code exists (e.g. file timestamp or disk space APIs, if added).
Owner: Frontend (F-01/F-09); the Lead should add it to the task board.

## 5. Deletion

| Store | Deleted by "Delete all data" (Privacy & Data, F-09) | Deleted by app removal |
|---|---|---|
| SwiftData sessions + events | Yes (delete all `MonitoringSession`; events cascade) | Yes |
| `NeutralBaseline` in UserDefaults | Yes | Yes |
| Settings in UserDefaults | Screen must say whether settings are kept or reset | Yes |
| Diagnostic motion recording (temporary file, §10) | Not needed: deleted on leaving Diagnostics, on a new recording and at launch | Yes |
| Pending/delivered notifications | Should be removed (`removeAllPendingNotificationRequests`, `removeAllDeliveredNotifications`) | Yes |
| Device / iCloud backups | No (outside the app's control; mention in privacy text) | No |

Checks: after delete-all, relaunch shows empty history and needs-calibration (P-01); the SwiftData
store does not retain old rows (verify by downloading the container: row counts zero; the SQLite
`-wal` file is checkpointed or small). No Keychain items are used, so nothing survives reinstall
(P-02).

## 6. App Store privacy "nutrition label" — draft

Valid only if checks G-01…G-09 pass.

| Question | Answer |
|---|---|
| Do you or your third-party partners collect data from this app? | **No — Data Not Collected** |
| Data used to track you | None |
| Data linked to you | None |
| Data not linked to you | None |

Rationale: Apple defines "collect" as transmitting data off the device in a way that lets the
developer or partners access it beyond real-time servicing of the request. Phase 1 stores
everything locally and sends nothing. Device backups are handled by Apple under the user's
account and are not developer collection.

**Phase 2 (optional sync, not started)** would change this. Expected categories if sessions/
events are uploaded: *Health & Fitness → Fitness* (posture episodes), *Usage Data → Product
Interaction* (sessions, reminders), *Identifiers → User ID* if accounts exist — "Linked to you"
if tied to an account, purpose *App Functionality*. Raw motion must still never be uploaded
(`api-contracts.md`). Sync needs explicit opt-in consent, a privacy policy, server-side deletion
endpoint, and an updated label before release.

## 7. Risks and checks to run once the app lands

| ID | Risk | Severity | Check / mitigation |
|---|---|---|---|
| R-01 | Network or analytics code added later without updating the label | High | CI or review grep (G-01, G-02); re-run O-02 on each release candidate. Consider adding the G-01 grep to the CI `hygiene` job once the app exists. |
| R-02 | Raw motion persisted for debugging and shipped | High | G-04 code review; developer recording compiled only under `#if DEBUG`; release-build container inspection. |
| R-03 | Developer fixture recordings committed to the public repo with a real person's motion | Medium | Fixtures in `shared/fixtures/motion` must be synthetic or recorded by the owner with consent; strip absolute timestamps; note provenance in `shared/fixtures/README.md`. |
| R-04 | Missing or incomplete privacy manifest → App Store rejection | Medium | §4.3; check the archive's privacy report in Xcode (Organizer → Generate Privacy Report). |
| R-05 | Purpose string missing → crash on first start of motion updates | High (functional) | Info.plist check in CI (grep generated Info.plist / `project.yml` for `NSMotionUsageDescription`); device test D-01. |
| R-06 | Lock-screen notification reveals posture/health information to bystanders | Low | Neutral copy ("Time for a quick posture reset"); no numbers or history in the notification. |
| R-07 | Health or medical claims in UI/App Store text ("fixes your spine", "prevents pain") | Medium (regulatory/review) | Copy review: wellness wording only, "not a medical device" in onboarding and About. |
| R-08 | History kept forever | Low | Offer delete-all (required) and consider a retention setting (e.g. 90 days) — product decision. |
| R-09 | Data readable when the device is locked | Low | SwiftData store uses at least the default `completeUntilFirstUserAuthentication` protection; since monitoring is foreground-only (D-010), `.complete` file protection is feasible — consider it. |
| R-10 | Data in device/iCloud backups | Low | Accept and disclose, or exclude the store from backup (`isExcludedFromBackup`) at the cost of losing history on device migration — Lead decision. |
| R-11 | CI secrets / supply chain in the public repo | Low | Workflow uses only `contents: read`, no secrets, no `pull_request_target`; third-party actions pinned to commit SHAs. Keep it that way. |
| R-12 | Settings JSON from an older version fails to decode after a field is added (data loss of settings/baseline) | Low (integrity) | `CodableTests` pins the JSON keys; add a migration or tolerant decoder before changing `PostureConfiguration`/`NeutralBaseline`. |

## 8. Open decisions for the Lead

1. Backups: keep the SwiftData store in backups (default) or exclude it (R-10)?
2. Retention: keep history indefinitely or add an automatic expiry (R-08)?
3. Should "Delete all data" also reset settings, or only sessions + baseline?
4. File protection level for the store (R-09).
5. Add `PrivacyInfo.xcprivacy` to the Frontend task list (§4.3).

## 9. Phase 2 sync server (`server/`, D-018) — what it would store

Added by the Backend agent. The server exists in the repo and is tested, but it is **not deployed
and the app does not call it**, so the Phase 1 label in §6 still holds. Before the app's opt-in
sync ships, the Lead must update §6, the privacy manifest and the App Store label.

| Data on the server | Content | Linked to |
|---|---|---|
| Device registration | Random server-generated UUID, SHA-256 hash of the bearer token, creation time | Nothing else: no account, email, Apple ID, name, device model, hardware id, IP or user agent is stored |
| Sessions | The `MonitoringSession` fields from data-contracts.md (start/end, monitored / within-threshold / sustained seconds, reminder count, calibration version, sensor status) + server created/updated times | The device UUID |
| Posture events | The `PostureEvent` fields (start/end, direction, duration, peak degrees, reminder triggered) | The device UUID and its session |
| Settings document | Reminder/sound/haptics/demo toggles and the tunable `PostureConfiguration` numbers | The device UUID |

Not accepted by any endpoint (unknown fields are rejected): raw `MotionSample`s, gravity or
attitude, the `NeutralBaseline`, learned axes, diagnostic motion recordings (D-007, D-017 d).

- **Identity**: anonymous per install. Whoever holds the token can read that device's data, so the
  app must keep it in the Keychain; losing it makes the data unreachable (and only erasable by an
  operator). No cross-device linking exists.
- **Retention**: until the user erases it. There is no automatic expiry in v1 (same open question
  as R-08). Database backups, when a deployment exists, must have a defined retention so erased
  data also ages out of backups.
- **Erase**: `DELETE /api/v1/devices/me` deletes events, sessions, settings and the registration in
  one transaction; the token stops working immediately (tested in `DeviceApiTest`). The app's
  "Delete all history" should call it when sync is on, or offer it separately.
- **Logs**: the server logs no request bodies, tokens or SQL parameters, and error responses do
  not echo submitted values (tested in `NoSecretsInLogsTest`). A reverse proxy in front of it must
  also not log the `Authorization` header.
- **Expected label once sync ships**: *Health & Fitness → Fitness* (posture events) and *Usage
  Data → Product Interaction* (sessions, reminders), purpose *App Functionality*, **not linked to
  identity** (no account) and no tracking — to be confirmed against Apple's definitions; the token
  is an app-scoped random identifier, not a device identifier.

| ID | Risk | Severity | Mitigation |
|---|---|---|---|
| R-13 | Token leaked from device or logs gives full access to that device's history | Medium | Keychain storage (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), TLS only, no logging; future token rotation endpoint |
| R-14 | Unauthenticated `POST /devices` abused to fill the database | Medium (availability) | Rate limiting / App Attest before any public deployment |
| R-15 | Erased data survives in database backups | Low | Short backup retention, documented in the privacy policy |

## 10. Diagnostic motion recording (D-017 (d), F-11)

Added by the Frontend agent. D-017 (d) makes a narrow, user-initiated exception to D-007 so the
algorithm can be tuned on real head motion. What the app does:

- **Only on an explicit action**: Settings → Diagnostics → Record motion → Start recording, for
  30 s, 1 min or 2 min. Before the button the screen says that raw head motion is recorded only
  for this export, stays on the iPhone unless the user shares it, is deleted when they leave the
  screen, and is never uploaded by Align. Nothing is ever recorded automatically.
- **Contents** (the recording JSON format in `shared/fixtures/README.md`): every `MotionSample`
  received while recording (timestamp, attitude, gravity, rotation rate; not user acceleration or
  the earbud side), the baseline (gravity, version, sample count, learned axes) and detection
  configuration at the start, the calibration actions taken during the recording (neutral
  calibration, nod, cancel, clear learned axes, cooldown reset, interrupts), and a `recording`
  block: app version, **hardware model identifier** (e.g. `iPhone16,1`, from `uname`; never the
  user-assigned device name), `headphones` = `"unknown"` (Core Motion does not name the model; the
  audio route's port name is user-assigned, e.g. "Alex's AirPods", so it is deliberately not
  read), an optional free-text note, and the creation time in UTC. No location, names, account or
  device identifiers.
- **Storage**: samples are kept in memory while recording (capped), then written once to
  `tmp/AlignMotionRecordings/<name>.json` with complete file protection. Nothing is written to
  SwiftData or UserDefaults (unit-tested).
- **Sharing**: only through the system share sheet (`ShareLink`), chosen by the user. The app has
  no network code (G-01 still holds).
- **Deletion**: the folder is deleted when the user leaves Diagnostics, starts a new recording,
  taps Delete recording, and at every app launch (in case the app was terminated while a file
  existed). Recording stops when the AirPods disconnect, the stream stops or the app goes to the
  background (whatever was captured can still be shared or deleted).
- **Release builds**: the recorder is not behind `#if DEBUG`; D-017 asks for it in Diagnostics
  for hardware testers. R-02's "compiled only under `#if DEBUG`" is replaced by the controls
  above — Lead to confirm before an App Store build (it could also be hidden behind a developer
  toggle there).
- **Privacy label**: unchanged ("Data Not Collected"): the developer receives a recording only if
  the user chooses to send it outside the app, which is not collection by the app.
- **Privacy manifest**: no new required-reason API. The recorder uses `ProcessInfo.systemUptime`
  (already declared, `35F9.1`, elapsed time), `FileManager` create/write/remove/`fileExists`
  (not file-timestamp APIs; no creation or modification dates are read) and `uname` (not on
  Apple's list). The sample watchdog uses `systemUptime` for elapsed time as well.
- **Shared recordings in the repo**: `shared/fixtures/recordings/README.md` (consent, no names in
  notes). This is R-03.

