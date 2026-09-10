# Device verification gate — Phase 0

Everything here is device-only. None of it can be checked in the simulator or by the unit suite,
and Phase 0 stays **open** until every box passes. Record failures inline rather than re-running
until green.

Prerequisites: an iPhone on iOS 26.1 or later and an Apple Developer account for signing. A local-only
build works with a free account; CloudKit verification also requires a paid team and iCloud sign-in.
Set a bundle identifier your team can sign before starting.

---

## A. Building and launching the app — DONE, and what it cost

The app target now builds and runs on the iOS 26.4 simulator. It had never compiled before, for
four independent reasons; see the `fix(app)` commit. Two are worth remembering:

* Anything behind `#if canImport(AlarmKit)` is **invisible to the host suite** — `HardsetAlarm` had
  a hard compile error that no `swift test` run could ever have caught. Treat "the package tests
  pass" as saying nothing about iOS-only code.
* `GENERATE_INFOPLIST_FILE` is `NO` here, so every `CFBundle*` identity key must be spelled out in
  `Info.plist`. Without `CFBundleIdentifier` the bundle builds and cannot be installed.

- [x] Builds for the simulator via headless `xcodebuild` (the Simulator MCP `build` tool passes
      `-skipMacroValidation`, which also bypasses the macro trust prompt).
- [ ] Open `Hardset.xcodeproj` in Xcode once and click **Trust & Enable** for each macro. Only
      needed for building inside Xcode; the headless path passes `-skipMacroValidation` and never
      prompts, which is why this box can sit unchecked while the app builds and ships fine.

      Four packages, confirmed from the actual Xcode issue list (an earlier version of this line
      named `swift-syntax`, which does not appear — it is a transitive dependency, not a macro
      target the project uses directly):

      * `DependenciesMacrosPlugin` — swift-dependencies
      * `PerceptionMacros` — swift-perception
      * `StructuredQueriesMacros` — swift-structured-queries
      * `StructuredQueriesSQLiteMacros` — swift-structured-queries

      Xcode reports them as four warnings *and* three errors, which is one issue reported twice at
      different severities, not seven problems. Trust persists in
      `~/Library/org.swift.swiftpm/security/macros.json`, keyed by fingerprint — so it is a
      once-per-machine step that a package version bump will ask about again.
- [x] Build and launch on a **physical device**. Verified 2026-08-25 with a signed local-only
      Release build on `iFone` (iPhone 18,3, iOS 26.6): the app and widget embedded successfully,
      installation succeeded, and `devicectl` launched `com.francisbisignano.hardset`. This proves
      the build/install boundary only; it does not close any AlarmKit checks in §B.

      **Regenerate before opening Xcode, and never commit the result.** The Team ID is the
      certificate subject's `OU`, not the parenthesized suffix printed by `find-identity`:

      ```
      security find-certificate -c "Apple Development" -p \
        | openssl x509 -noout -subject -nameopt multiline \
        | sed -n 's/^[[:space:]]*organizationalUnitName[[:space:]]*=[[:space:]]*//p'

      HARDSET_TEAM_ID=<the OU above> python3 Tools/generate_project.py --local
      ```

      Two failures happen without it, and they look like one:

      * `DEVELOPMENT_TEAM = 7R2SW36YX3` was **committed** to the project on 2026-08-24, against this
        script's own rule that a team identifier is account-specific and a checked-in one is wrong
        for everybody except its owner. On any other machine Xcode reports *"No Account for Team
        7R2SW36YX3"* on all six build configurations. Fixed: the committed project now carries no
        team at all, and supplying one is a local step.
      * Selecting a team in Xcode's UI writes it into the two **app-target** configurations only —
        the ones that also carry `CODE_SIGN_ENTITLEMENTS`. The widget, tests and project-level
        configurations keep whatever was there, so the project ends up with two different team IDs
        and half the errors appear to be fixed. Regenerating is what makes all six agree.

      `--local` is not optional on a free account: the entitlements request CloudKit and
      `aps-environment`, and a personal team cannot grant either, so Xcode refuses to create a
      profile at all rather than degrading. Dropping them costs sync and nothing a gym session
      touches. `UIBackgroundModes: remote-notification` stays in `Info.plist` and is inert without
      the entitlement — harmless, and not worth a second Info.plist to strip.

      Leave at least 4 GB free before a clean Release build. Hardset's DerivedData reached 2.8 GB;
      at 103 MB free, SwiftPM emitted `databaseFull` and code signing failed with an opaque internal
      error. Both were storage failures, not source or provisioning failures.

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
- [x] **AX5 Dynamic Type pass** (`simctl ui <udid> content_size accessibility-extra-extra-extra-large`).
      Three defects found by looking, none of which any test could see:
      * `SetRowView` collapsed. "Last time" broke to one character per line ("Las / t / tim / e"),
        the unit suffixes split mid-word ("-k / g", "-re / p / s"), and one set row grew to ~600 pt.
        The most-used screen in the app was unusable at the sizes that exist for people who need
        them. Fixed with a stacked layout at accessibility sizes and a `@ScaledMetric` ordinal
        gutter, which had been a hard 28 pt -- narrower than a single AX5 digit.
      * `ExercisePickerView` truncated the muscle attribution to "also Fro..." and the equipment
        label to "Ma-". That line is the reason the picker beats a list of names, so truncating it
        threw away the differentiator to save height. Fixed: no line limit on the attribution, and
        the row stacks at accessibility sizes.
      * The picker sheet's large title truncated to "Add movem...". Large titles truncate rather
        than wrap; it is inline now.
      Verified after the fix: each label holds one line, the attribution renders in full, and the
      log control spans the row. The Volume screen and the start screen already passed unchanged.
- [x] **The planner, end to end.** Against a seeded three-week upper/lower history (12 movements,
      108 sets): created a plan, dealt it across 3 days (4/5/3), named a machine on a movement, and
      confirmed in the database that the entry carried its `machineID` **and** that
      `machineExercises` gained the library row — so a gym answers "I can do this here" with no set
      ever logged on that machine. The coverage panel named seven uncredited muscles, inside the 6-8
      `SplitCalibrationProbe` says every conventional split leaves.

      Five defects found by looking, none visible to the 571-test suite: an empty plan whose own copy
      promised to deal your logged movements while the button read from the empty plan and did
      nothing; "1 days" in two places; day subtitles ranked by group touches, so a day of rows,
      bench, leg press and leg curls read "Arms · Legs · Shoulders"; a "Fewest movements" label that
      never said out of what; and a machine sheet filing every machine in the gym under "You've used
      these", with no check mark on the one already chosen.
- [x] **AX5 Dynamic Type on the planner** — clean, no defects. Movement names, the muscle attribution
      line, day headers with their menu button, the day-count stepper and the deal button all wrap
      without truncation. Designed against the three AX5 defects §A2 already records, so the fixes
      were free rather than found.
- [x] One crash found here, on the first tap that animated a colour: `Tokens.Color.dynamic` builds a
      `UIColor` dynamic provider, and `HardsetUI` compiles with `defaultIsolation(MainActor)`, so the
      provider closure was inferred `@MainActor`. SwiftUI resolves colours **off** the main actor
      while updating the view graph (`resolvedHDRColor` under `updateOutputsAsync`), and Swift 6
      traps in `dispatch_assert_queue`. Fixed by marking the helper `nonisolated`. Latent since the
      helper was written; routing every colour through it is what made it reachable. **Not
      unit-testable** — it needs the app running, which is the whole argument for this section.

## B. AlarmKit — the rest timer

The flagship feature, and the one competitors lose stars over. Test 4 is the single most important
line in this document: a rest timer silenced by Focus is the exact defect the positioning is built
on avoiding.

- [x] **Authorization.** First schedule prompts for alarm permission. Grant it.
      Done in the **simulator**, not on a device: scheduling now happens at all, the system prompt
      appears with our own usage string ("Hardset uses alarms so your rest timer still alerts you
      when the app is closed, silenced, or in Focus"), and granting it lets the bar run. This box
      was previously unreachable -- `restAfterSet` was hardcoded nil, so AlarmKit was never asked
      for anything. Everything below still needs a phone.
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
- [ ] Privacy policy URL live and reachable in App Store Connect and from the bundled in-app
      policy. The policy itself is already always readable offline from Settings.
- [ ] Paid Applications Agreement signed; Small Business Program enrolment done; EU DSA trader
      details submitted and verified.

---

## E. App Store submission gate

Everything below is required to *submit*, not to be good. Grouped by who can do it, because most of
what is left is not engineering.

### E1. Blocked on the account holder — nothing in the repo can advance these

- [ ] **Paid Apple Developer Program membership.** Local device signing is verified; paid
      membership still gates CloudKit/push provisioning, TestFlight, and the remaining submission
      work below.
- [ ] **Paid Applications Agreement** signed, banking and tax filled in. Required even for a free
      app if it ever sells anything.
- [ ] **EU DSA trader status** submitted and verified. This has a real queue and blocks EU
      availability; start it early rather than at submission.
- [ ] **Privacy policy page live** at a stable URL. Required by App Store Connect for every app.
      Then set `LegalLinks.live.privacyPolicy` — the always-present Settings policy links to it.
- [ ] **Terms of Use (EULA) page live**, and `LegalLinks.live.termsOfUse` set. Required *inside the
      binary* the moment an auto-renewable subscription ships (Guideline 3.1.2); Apple's standard
      EULA is acceptable if you do not want to write one.
- [ ] **Support URL**. Metadata in App Store Connect; the in-app row is a courtesy and appears once
      `LegalLinks.live.support` is set.
- [ ] **App Store Connect privacy questionnaire.** Note the trap already recorded in
      `PrivacyInfo.xcprivacy`: the SDK-inheritance rule that lets the manifest stay empty does
      **not** apply to the questionnaire. If RevenueCat ships, purchase history must be declared
      there by hand.
- [ ] **Screenshots** for every required device size, and the listing copy.
- [ ] **Age rating** questionnaire.

### E2. Done in the repo

- [x] **App icon.** 1024x1024, opaque RGB (iOS rejects an icon with an alpha channel), generated by
      the script recorded in `DECISIONS.md` #28. It is a placeholder in the sense that it is
      geometry rather than commissioned art, and it is deliberately in the locked palette so
      replacing it is a swap and not a redesign.
- [x] **Launch screen is dark**, and `UIUserInterfaceStyle` is `Dark`. Before this, a dark-only app
      opened with a white flash on any device in light mode, and system chrome followed the device.
- [x] **`ITSAppUsesNonExemptEncryption`** declared `false`, so App Store Connect stops asking on
      every upload.
- [x] **`AccentColor`** is the locked achromatic accent rather than Xcode's default blue.
- [x] **`PrivacyInfo.xcprivacy`** written and reasoned, including what is deliberately *not*
      declared and the `nm -u` check that would flip it.
- [x] **Privacy policy is always readable inside the app**, even before a network request can
      succeed. The public App Store URL remains an account-holder gate above.
- [x] **Live Activities are declared** with `NSSupportsLiveActivities`, matching the ActivityKit
      widget and AlarmKit countdown that already ship in the binary.
- [x] **The retained-v1 upgrade path is migrated and tested.** `v2-session-split-day` adds the plan
      link without rewriting v1 or losing an existing workout; it was also installed over the
      retained simulator database that originally exposed the missing-column failure.
- [x] **Data export.** CSV of every logged set, from Settings. "Data loss / no export" is one of
      this category's loudest review complaints.
- [x] **Methodology index.** One screen listing every derived number and its source, which is what
      to point Guideline 1.4.1 at.
- [x] **Version and build shown in Settings**, read from the bundle rather than duplicated.

### E3. Product decisions and physical-account verification still open

- [x] **Destructive migration fallback removed.** No build configuration enables
      `eraseDatabaseOnSchemaChange`; a migration failure now reaches the explicit unavailable-store
      UI instead of silently destroying history.
- [x] **Delete-all-my-data is built and transactionally tested.** It deletes local-only records,
      preserves the fixed curated exercise catalog, and produces CloudKit deletion tombstones for
      synchronized rows. The two-device production-CloudKit check remains required in §C because
      a package test cannot prove Apple's production container behavior.
- [ ] **Subscriptions**, if v1 is paid: StoreKit 2 + RevenueCat, a paywall, and **Restore
      Purchases**, which Guideline 3.1.1 requires and which is the single commonest IAP rejection.
      Nothing is built; `grep StoreKit` returns nothing.
- [ ] **Sign in with Apple**, if second-device restore ships. It brings Guideline 5.1.1(v) with it:
      an account that can be created in-app must be **deletable** in-app.
- [ ] **Decide the analytics question.** The app currently has no analytics of any kind, so every
      retention or "feels smart" benchmark in the research is unmeasurable. Adding an SDK after
      launch is a resubmission and costs the launch cohort. Decide before, or delete the
      benchmarks.

---

**Rule for reporting.** An unchecked box is not "probably fine." If a box cannot be tested — no
second device, no paid account — write *why* next to it. The point of this file is that nobody,
including a future session, can mistake unverified behaviour for verified behaviour.
