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
- [ ] **Lock Screen controls.** Start a 2:00 rest, lock. The Lock Screen shows the ring, the
      movement, "Set N of M · <machine>", the countdown, and Pause and Skip. Tap Pause: the
      countdown freezes, the button becomes Resume, and unlocking shows the app paused with the
      same remainder. Tap Resume: the countdown continues from it, and the alarm still sounds at
      the end. Tap Skip: the activity ends, no alarm sounds, and the app shows no rest.
- [ ] **Controls after a force-quit.** Start a rest, force-quit, then Pause from the Lock Screen.
      The app was launched in the background to do it: reopening shows the same paused remainder.
      Repeat with Skip.
- [ ] **After the deadline.** Let a rest alert, dismiss it, and leave the Lock Screen up for a
      minute: no crash report in Settings › Privacy › Analytics for HardsetWidget.
- [ ] **Dynamic Island.** On a Dynamic Island iPhone: compact shows the ring and the countdown;
      long-press shows the movement, the machine, the ring and the buttons; each button works.
- [ ] **No button that does nothing.** The paused Lock Screen view shows our Resume only. If the
      system still draws AlarmKit's own Resume beside it (the `Paused(resumeButton:)` it requires),
      note where; tapping it must not leave the app showing a different state after the next
      reconcile.
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

## E. System surfaces — Siri, Spotlight, the Action button, Control Center, widgets

- [ ] **Siri, cold.** Force-quit Hardset. "Hey Siri, start a workout in Hardset": the app opens on
      Train with an empty workout. Say it again: the same workout is shown, not a second one.
- [ ] **Siri mid-workout, from another tab.** With a workout open, go to History and say it: the
      app switches to Train and shows that workout, with every logged set still there.
- [ ] **Siri, with a workout open that cannot be read.** (Debug throw in `resume`.) "Start a
      workout in Hardset": "Workout unavailable" shows; no new workout is started.
- [ ] **Siri on a fresh install.** The first-run screen shows first. Tap Start: the workout starts.
- [ ] **A rest by voice.** "Start a rest in Hardset": Siri asks how long. "Two minutes": a 2:00
      rest starts and shows on the Lock Screen titled "Rest". "Ten seconds": Siri says "A rest can
      be from 0:15 to 30:00." and nothing starts.
- [ ] **A rest by voice, app never opened since install.** Note whether the alarm permission
      prompt can appear, and what Siri says. The rest must not be silently alarm-less with no word.
- [ ] **Skip by voice.** With a rest running, "Skip my rest in Hardset" ends it. With none, Siri
      says "No rest is running."
- [ ] **Action button.** Assign Start workout; press it: as the first check.
- [ ] **Start workout control.** Add it to Control Center. Tap it with no workout open: Hardset
      opens on Train with an empty workout. Tap it again: the same workout.
- [ ] **Rest control, configured.** Add Rest; the system asks for a length; choose 2 minutes. The
      control reads "Rest · 2:00". Tap it from the Lock Screen's Control Center: a 2:00 rest starts
      without opening the app, and its Lock Screen activity is titled "Rest".
- [ ] **Rest control, not configured.** Add Rest and dismiss the length prompt. The control reads
      "Rest · Choose"; tapping it starts nothing.
- [ ] **Rest control after a force-quit.** Force-quit Hardset, tap the configured control: the
      rest starts, and opening Hardset shows the same countdown.

---

**Rule for reporting.** An unchecked box is not "probably fine." If a box cannot be tested — no
second device, no paid account — write *why* next to it. The point of this file is that nobody,
including a future session, can mistake unverified behaviour for verified behaviour.
