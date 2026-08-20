# Device verification gate — Phase 0

Everything here is device-only. None of it can be checked in the simulator or by the unit suite,
and Phase 0 stays **open** until every box passes. Record failures inline rather than re-running
until green.

Prerequisites: an iPhone on iOS 26.1 or later, signed into iCloud, and a free Apple Developer
account for signing. Set `PRODUCT_BUNDLE_IDENTIFIER` and the iCloud container to values your team
can sign before starting.

---

## A. Building the app — DONE, and what it cost

The app target now builds and runs on the iOS 26.4 simulator. It had never compiled before, for
four independent reasons; see the `fix(app)` commit. Two are worth remembering:

* Anything behind `#if canImport(AlarmKit)` is **invisible to the host suite** — `HardsetAlarm` had
  a hard compile error that no `swift test` run could ever have caught. Treat "the package tests
  pass" as saying nothing about iOS-only code.
* `GENERATE_INFOPLIST_FILE` is `NO` here, so every `CFBundle*` identity key must be spelled out in
  `Info.plist`. Without `CFBundleIdentifier` the bundle builds and cannot be installed.

- [x] Builds for the simulator via headless `xcodebuild` (the Simulator MCP `build` tool passes
      `-skipMacroValidation`, which also bypasses the macro trust prompt).
- [ ] Open `Hardset.xcodeproj` in Xcode once and click **Trust & Enable** for the macros from
      `swift-syntax`, `swift-structured-queries` and `swift-perception`. Only needed for building
      inside Xcode; the headless path does not prompt.
- [ ] Build and run on a **physical device** — still never done. Signing needs a team identifier
      the sandbox cannot supply.

## A2. Verified in the simulator (not a substitute for the device gate)

Walked end to end on iPhone 17 / iOS 26.4, with the database checked directly after each step:

- [x] Create a gym, name a machine at the rack, log 60 kg x 10 against it. The row lands with its
      `machineID` and `gymID` set — the differentiator works rather than merely existing.
- [x] Load history draws **one line per machine** and shows an 80 kg Epley estimate for 60 x 10.
- [x] Three presentation bugs found and fixed here that no test could see: an `.alert` `TextField`
      binding that always read empty, a second `.sheet` on one anchor that never presented, and an
      empty accessory pill above the tab bar.
- [x] One total-loss bug found here: the app discarded the `SyncEngine`, whose triggers then had a
      dead function behind them, so **every write to every synchronized table failed**. Nothing in
      the suite could have caught it.

## B. AlarmKit — the rest timer

The flagship feature, and the one competitors lose stars over. Test 4 is the single most important
line in this document: a rest timer silenced by Focus is the exact defect the positioning is built
on avoiding.

- [ ] **Authorization.** First schedule prompts for alarm permission. Grant it.
- [ ] **Denied path.** Reinstall, deny permission, schedule a rest timer. The app degrades to a
      local notification and tells the user plainly — it does not crash and does not silently
      no-op.
- [ ] **Locked screen.** Start a 30 s rest, lock the phone. The countdown renders on the Lock
      Screen and the alert fires.
- [ ] **Focus breakthrough.** Start a rest, enable Do Not Disturb, wait. The alert still fires
      audibly.
- [ ] **Silent switch.** Repeat with the ring/silent switch set to silent. Still audible.
- [ ] **Force-quit survival.** Start a rest, swipe the app away from the app switcher, wait. The
      alert still fires. *(This is the claim I flagged as resting on a developer-forum post rather
      than Apple documentation — this checkbox is where it actually gets verified.)*
- [ ] **Reboot survival.** Start a long rest, power the phone off and on, wait. The alert fires.
      If it does not, the persistence claim is wrong and the recovery path must reconcile against
      `AlarmManager.shared.alarms` on launch.
- [ ] **±15 s debounce.** Tap +15 s five times in under a second. Exactly one alarm is live
      (`AlarmManager.shared.alarms` has count 1), the deadline moved by exactly +75 s, and the
      on-screen countdown matches the alarm. This is the cancel-then-reschedule path; a race here
      shows up as two alarms or a drifted deadline.
- [ ] **Pause / resume.** Pause mid-rest. The paused UI shows a static remaining time — AlarmKit's
      paused presentation carries no dates, so this value must come from our own
      `pausedRemaining`. Resume; the new deadline is correct.
- [ ] **Live Activity fidelity.** The Dynamic Island and Lock Screen countdowns do not drift over
      two minutes. They are system-rendered from `fireDate`, so drift means we are pushing updates
      we should not be.
- [ ] **Thermals.** One continuous 45-minute session with the screen on. No thermal warning, no
      runaway battery drain.

## C. Two-device CloudKit sync — the replacement for Spike B

**Why this section exists.** The brief specified a `CKSyncEngine` conformance harness driving two
stores through all six documented sync scenarios. That is not achievable: SQLiteData's
`MockCloudContainer` is declared `package final class` in `Sources/SQLiteData/CloudKit/Internal/`,
so it is unreachable from application code. There is no public test double, and SQLiteData already
covers those six scenarios inside its own suite.

So Spike B is redefined honestly: we verify *our* schema and *our* delegate against a **real**
CloudKit container across two devices, and we rely on the library's own tests for the library's own
merge semantics. Use the iPhone plus a simulator signed into the same iCloud account.

- [ ] **Schema deploys.** The development schema deploys to CloudKit without error, and every
      synced table appears in the CloudKit console with the expected record types.
- [ ] **Send.** Create a gym on device A. It appears on device B.
- [ ] **Fetch.** Create a gym on B. It appears on A.
- [ ] **Offline queue.** Airplane mode on A, log 5 sets, re-enable networking. All 5 arrive on B
      **exactly once** — no duplicates. Count rows, do not eyeball the list.
- [ ] **Merge conflict.** Take B offline. Edit the same row's *different* columns on A and B.
      Reconnect. Both edits survive (SQLiteData merges per-column), and neither device loses data.
- [ ] **Delete propagation.** Delete a row on A. It disappears on B and does not resurrect after
      a restart of either app.
- [ ] **Sign-out preserves data — on real hardware.** Sign out of iCloud on A. Local rows survive
      and the app tells the user what happened. *(The unit suite proves our delegate runs; this
      proves it on a real account-change event, which is where a wrong `CKSyncEngine.Event` shape
      would show up.)*
- [ ] **Sign back in.** Previously-uploaded rows return. Anything created while signed out is
      still present and uploads.
- [ ] **Account switch.** Sign into a *different* iCloud account on A. Local rows survive and the
      user is told the data belongs to the previous account.
- [ ] **No health data in iCloud.** Add a bodyweight entry, then inspect the CloudKit console.
      `bodyweightEntries` must be absent — it is deliberately unregistered with the SyncEngine
      under Guideline 5.1.3(ii). If it appears, stop and fix before any external build.

## D. Before the first external TestFlight build

- [ ] Deploy the CloudKit schema to **production**. This is irreversible and additive-only, and it
      must happen before the first external build.
- [ ] Confirm `PrivacyInfo.xcprivacy` is present in the built app bundle **root**, not just in the
      source tree. A manifest that is not copied is functionally missing.
- [ ] Privacy policy URL live and reachable both in App Store Connect and from inside the app.
- [ ] Paid Applications Agreement signed; Small Business Program enrolment done; EU DSA trader
      details submitted and verified.

---

**Rule for reporting.** An unchecked box is not "probably fine." If a box cannot be tested — no
second device, no paid account — write *why* next to it. The point of this file is that nobody,
including a future session, can mistake unverified behaviour for verified behaviour.
