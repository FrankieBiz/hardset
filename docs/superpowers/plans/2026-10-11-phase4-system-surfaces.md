# Phase 4 — System Surfaces Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** a rest shows on the Lock Screen and in the Dynamic Island as a ring with the machine's
name, and can be paused, resumed and skipped there without the app losing track; Siri, Spotlight,
the Action button and Control Center can start a workout or a rest of a length the lifter chose,
and none of them can log a set; a finished workout can go to Apple Health, opt-in and write-only,
as strength training with its real start and end; two widgets show the last time on a machine and
the last workout from a file the app writes; two tips point at two features; the launch screen is
the app's own background; and the privacy manifests say exactly what the code does.

**Architecture:** every decision lands in `HardsetCore` (pure values) or `HardsetStore` (GRDB),
test-first, verified by `Tools/linux-test.sh`:
- *Core:* the Live Activity's content and its guarded date range; rest durations asked for from
  outside the app, rest commands and their outcomes; the Start-workout policy and the request
  inbox; the Rest control's state; the Apple Health export policy and copy; the widget snapshot,
  its file and its text; the two tips and when they may show
- *Store:* the Health opt-in, the device-local record of what went to Health (one additive
  table), and the widget snapshot read from finished workouts only
- *Resources, tested on Linux:* the launch colour against the palette, both privacy manifests,
  the entitlements and the Health usage string, read as files by `AppResourcesTests`

App Intents, controls, the Live Activity, widgets, HealthKit, TipKit and the icon cannot compile
here. Their tasks only render those values and wire them, and each adds `docs/MAC-VERIFICATION.md`
entries under `## Phase 4` and `DEVICE-CHECKLIST.md` lines.

**Tech Stack:** Swift 6.2 (Swift 6 language mode, `NonisolatedNonsendingByDefault`), Swift Testing,
GRDB 7 / SQLiteData 1.x (StructuredQueries), Observation; on the Mac: SwiftUI, WidgetKit,
ActivityKit and AlarmKit (iOS 26), App Intents (`LiveActivityIntent`, `AppShortcutsProvider`,
`ControlConfigurationIntent`, `IntentModes`), HealthKit (`HKWorkoutBuilder`), TipKit, Icon Composer.
`Tools/generate_project.py` owns `Hardset.xcodeproj`. The Mac's `./test.sh` also builds HardsetUI,
HardsetFeature and HardsetAlarm for macOS 15.

**Spec:** `docs/superpowers/specs/2026-10-10-hardset-ada-polish-design.md` §10 (Phase 4, items
4.1–4.8), under the §3 direction, the §4 non-negotiables and the §5 verification strategy. Builds
on the Phase 1, 2 and 3 plans in `docs/superpowers/plans/`; their Produces blocks are existing code
once merged (see Scheduling for which are).

## Global Constraints

- **Every invariant in `HANDOFF.md` §5 and every refusal in §6.** No target, goal, streak, program
  or coaching on any surface, including tips, widgets and Siri's replies. **No default rest:** a
  rest started from outside the app has the length the lifter said or configured, or none.
- **"No set is ever logged from outside the app UI: not from Siri, widgets, controls or the Action
  button. The lifter must see the numbers being saved"** (spec §4). No intent, control or widget
  takes a weight or a rep count, and `SystemRequest` has one case, `.startWorkout`
  (`DECISIONS.md` §26, Task 1).
- **Schema changes are additive only, and each needs a `DECISIONS.md` entry first.** The one new
  table, `deviceHealthExports`, is device-local (§24, Task 1, before Task 5). `bodyweightEntries`
  stays unsynced. A task that finds it needs any other schema change stops and asks.
- **The widget never opens the database** (spec 4.5): `SyncEngine`'s triggers live in the app
  process. It reads `WidgetSnapshotFile` from the App Group container (§25).
- **No shared `UserDefaults` suite.** So `1C8F.1` is not declared; `AppResourcesTests` fails if a
  `UserDefaults(suiteName:` appears in shipped code (spec 4.5 says "1C8F.1 for the shared
  defaults"; there are none, see reading 9). Device-local settings use `.standard` (CA92.1).
- **Apple Health is opt-in and write-only:** `requestAuthorization(toShare: [workoutType], read: [])`,
  `.traditionalStrengthTraining`, start and end from `SessionTimeline`, **no energy burned** and no
  other quantity, implausible lengths skipped, never twice, and only for a workout finished on this
  device at the moment it is finished.
- **Never edit these:** `ExerciseCatalog.swift`; methodology text pinned by tests.
  **`HardsetApp.swift` stays wiring only:** each task that touches it adds construction and
  registration lines, nothing a test could cover.
- **`Hardset.xcodeproj` is generated.** Every new app, widget or shared file is added to
  `Tools/generate_project.py`, then `python3 Tools/generate_project.py` is run twice and the
  second run must leave `git diff --stat Hardset.xcodeproj` unchanged. Never hand-edit the pbxproj.
- **`GENERATE_INFOPLIST_FILE = NO`:** every Info.plist key is typed into `Hardset/Info.plist` or
  `HardsetWidget/Info.plist`.
- **Copy:** Phase 4's Core copy is plain English string literals, in the `…Copy` enums and
  functions shown, and moves through `localized(_:comment:)` in Task 16 once Phase 3 Task 11 is
  merged (`DECISIONS.md` §23: nothing is built on Core's catalog before its Mac gate).
- **Isolation:** Core types are `nonisolated` by module default; `SystemRequestInbox` is
  `@MainActor @Observable`. Store types that touch the database, and the setting protocol and its
  classes, are explicitly `nonisolated`, as `RestPreferenceStore` is. HealthKit and AlarmKit
  objects that are not `Sendable` are created and consumed inside one `nonisolated` function
  (`DECISIONS.md` §3).
- **Store tests build databases with `Configuration.forTesting()`**, never `Configuration()`, with
  `foreignKeysEnabled = true`.
- **Verification:**
  - Core, Store and resource tasks: `Tools/linux-test.sh` (optionally `--filter '<Suite>|<Suite>'`)
    passes in full before commit.
  - Mac-only tasks: entries under `## Phase 4` in `docs/MAC-VERIFICATION.md` (create the heading
    once, at the end, if absent; the ledger merges by union) and lines in `DEVICE-CHECKLIST.md`.
- **API discipline for Mac-only code:**
  - Every Apple API not already used here is confirmed against developer.apple.com by fetching
    `https://developer.apple.com/tutorials/data/documentation/<path>.json` (the HTML renders
    client-side; WebFetch returns only titles). The human URL goes in the commit body. Each
    Mac-only task lists the URLs checked on 2026-10-11, with availability.
  - Anything newer than iOS 26.1 needs `#available`. The package also builds for macOS 15:
    HealthKit's workout builder does not exist on macOS (`HKWorkoutBuilder`: "macOS –"), so
    HardsetHealth is `#if os(iOS)`; WidgetKit's controls are macOS 26, and live only in the
    widget extension, which is iOS-only.
  - `openAppWhenRun` is deprecated in iOS 26 and "generates an error if the app intent runs in an
    app extension"; use `supportedModes` (iOS 26.0, so no `#available` at a 26.1 floor).
  - SF Symbol names cannot be checked here. Each new one is listed in its task's ledger entry.
- **Commits:** messages explain *why* and end with `Co-Authored-By: <your model's trailer>`. Never
  `git push`.

## Review Focus

- **The Lock Screen drawn after the deadline.** The old widget built `Date.now...fireDate`, which
  traps once the deadline passes; a clock change or a zero-length alarm reverses it too. The range
  must never be reversed, never read the clock, and a resumed rest's ring must include the time
  before the pause. Pinned in Task 2 (`renderAfterDeadlineNeverReverses`, `zeroLengthCountdown`,
  `nonFiniteTotal`, `resumedAlarmRingCoversWholeRest`, `pausedFractionClamped`).
- **A rest asked for in words or configured in a control.** "A ten second rest", 45 minutes, zero,
  a negative or not-a-number value, or a control added without choosing a length. Each is refused
  with a sentence, never clamped and never defaulted; an unconfigured control starts nothing.
  Pinned in Task 3 (`outOfRangeRefusedNotClamped`, `floatingNoiseIsWholeSeconds`,
  `unconfiguredControlStartsNothing`).
- **"Start a workout" when one already exists.** Said mid-workout, with a workout that could not
  be reopened, or on a cold launch before the open workout has been read. Never a second session on
  top of the first; the request waits and is acted on once. Pinned in Task 3
  (`openWorkoutIsShownNotReplaced`, `resumeFailureBlocksStart`, `requestWaitsForLaunch`).
- **A workout that must not reach Health as recorded.** Left open overnight, finished with the
  clock moved back, or the same workout again after a sign-out and sign-in re-downloads it under
  the same id. Never an invented length, never twice. Pinned in Task 4
  (`implausiblyLongIsSkipped`, `endsInFutureIsSkipped`) and Task 5
  (`exportSurvivesSessionDeletion`, `secondExportIsSkipped`).
- **The widget refreshed mid-workout, or reading a bad file.** An open workout's half-done sets,
  warm-ups, one movement on machines that share a name, a machine archived since, a torn file, a
  file from a newer build. "Last time" comes from finished working sets only, keeps each machine
  apart and named, and a bad file is a calm empty state. Pinned in Task 6
  (`openWorkoutNeverLastTime`, `warmupsExcluded`, `machinesStayApart`, `archivedMachineStillNamed`,
  `unreadableFileIsEmptyNotCrash`, `newerVersionIsIgnored`).

## How this plan reads the spec

Each resolution is binding for the tasks, and pinned by a test where it is behaviour.

1. **4.1 "stop" is Skip.** The Lock Screen's third button ends the rest exactly as the in-app Skip
   does, and is titled "Skip" (`forward.end.fill`) so one action has one name. The intent is
   `StopRestIntent`, as 4.2 names it. All three buttons are `LiveActivityIntent`s, which "the
   system launches your app process without opening the app" to perform, so the app pauses its own
   alarm and keeps the remainder: the reason Phase 1 removed AlarmKit's system pause.
2. **The alert keeps no secondary button.** Spec 1.4 removed "Skip" from the *alert* and said
   Phase 4 "adds real intents". When the alert sounds the rest is already over, so skipping means
   nothing there; the real intents are on the countdown. `AlarmConfiguration` is unchanged.
3. **The ring is the alarm's whole countdown** (`fireDate − totalCountdownDuration` to `fireDate`).
   The app replaces its alarm on ±15 s and on resume, so after one of those the ring starts again
   from the new alarm's length. Showing the original total would need it stored, a change to
   `RestTimerState` and `deviceRestTimer`; that is out of scope and recorded as a ledger residual.
4. **A rest may start with no workout open.** It logs nothing, and it is titled "Rest", because
   no set started it. During a workout the in-app bar then shows no stale caption (Task 10 reads
   the caption from the timer, not from the coordinator's last request).
5. **An intent first reconciles.** A `LiveActivityIntent` can launch the app in the background,
   where the controller reads idle until it has looked at AlarmKit, and the system may suspend the
   app as soon as `perform()` returns. So `RestTimerController.perform(_:)` reconciles, applies
   `RestCommandPlan`, then waits for its AlarmKit commit (`settle()`).
6. **Start workout uses an in-process inbox, not a URL.** `OpenURLIntent` is documented for
   universal links, which Hardset has none of. `StartWorkoutIntent` declares
   `supportedModes = .foreground`, runs in the app, posts `.startWorkout` to `SystemRequestInbox`,
   and the root acts on it through `StartWorkoutPolicy`. The first-run screen comes first; the
   request then starts the workout once Start is tapped.
7. **The Rest control is configured when added** (`promptsForUserConfiguration()`), with an
   optional length. Unconfigured, or holding a length no longer allowed, it reads "Rest · Choose"
   and opens Hardset (`OpenHardsetIntent`); it never starts a rest nobody chose.
8. **Apple Health gets only a workout finished on this iPhone, when it is finished.** No backfill
   and no export of sessions that arrive by sync (the device that finished them exports its own).
   `HKMetadataKeyExternalUUID` carries the session id. No energy, distance, heart rate or indoor
   flag: nothing measures them. The opt-in is off until the lifter turns it on and Health allows
   it. **Shipping is blocked on a privacy policy URL** (spec §12.1); building is not.
9. **"1C8F.1 for the shared defaults."** The snapshot is a file in the App Group container, and
   nothing reads `UserDefaults(suiteName:)`, so there are no shared defaults and 1C8F.1 would be a
   false declaration. Both manifests say why, and a test fails the day a shared suite appears.
   "Plus a widget manifest" is met: the widget's own `PrivacyInfo.xcprivacy`, declaring nothing,
   because it calls no required-reason API (the snapshot carries `writtenAt`, so no file dates are
   read).
10. **"Last time on this machine"** is the most recently trained movements-on-machines, from
    finished workouts: one in the small widget, three in the medium, one on the Lock Screen. A
    configurable machine picker would need the widget to query, which it must not. Dates are
    shown as dates ("Tue 7 Oct"); a relative date is a "days since" count.
11. **TipKit:** two tips, `FeatureTip.machineChip` and `.movementHistory`. Core decides when each
    may show (never over the keypad; the machine tip only where a chip exists; the history tip only
    where history exists); TipKit shows each once, ends it when the feature is used, and shows at
    most one a day (`.displayFrequency(.daily)`).
12. **4.8 launch background** is `Palette.backgroundLight` / `backgroundDark`, the colour the first
    screen draws, so launch does not flash `systemBackground`.
13. **4.6 is a design task.** Task 15 delivers a brief and SVG layer drafts; the final artwork is
    the user's (spec §12.2), finished in Icon Composer on the Mac.

## Scheduling (for the controller)

**Preconditions:**
- Phase 3 Task 10 is merged (at `5d9fb52`, the commit this plan was read and compiled at). Line
  numbers below are anchors at that commit; symbol names are authoritative.
- **Still in flight:** Phase 2 Tasks 18 and 19 (`LiveSessionScreen`, `HardsetRootView`,
  `HistoryScreen`) and Phase 3 Mac-only Tasks 12–19 (`CertaintyBadge`, `MethodologySheet`,
  `VolumeReportView`, `WorkoutSummaryView`, `HistoryView`, `ProgressionChartView`, `SetRowView`,
  `NumericPad`, `ExerciseSectionView`, `SessionView`, `RestBarView`, `HardsetRootView` and its split
  into `HardsetEnvironment.swift`, `StartWorkoutView.swift`, `GymPickerSheet.swift`,
  `LiveSessionAccessory.swift`, plus `HistoryScreen`, `SessionDetailView`, `FirstRunView`,
  `GymsScreen`, `SettingsSheet`). **No Phase 4 task edits any of those files before its owner
  merges:**
  - Task 10 starts only after Phase 2 **Task 19** and Phase 3 **Tasks 16–19** merge. It edits
    `HardsetRootView.swift`, `LiveSessionScreen.swift` and `LiveSessionAccessory.swift`.
  - Tasks 12 and 13 follow Task 10 (root and environment edits, one at a time). Task 13 also needs
    Phase 3 **Task 13** (`WorkoutSummaryView`) and **Task 19** (`SettingsSheet`).
  - Task 14 starts only after Phase 3 **Task 15** merges (`ExerciseSectionView`, `SessionView`).
- Tasks 1–9 and 15 touch none of those files and may run now.

Every Core, Store and resource code block in Tasks 2–8 (and the resource tests Tasks 12 and 13
add) was compiled and run in the `hardset-swift-linux:6.2` container against a copy of the
package at `5d9fb52`, with the mount of Task 8's `linux-test.sh`: with all of them applied the
full suite is 660 tests in 88 suites, all passing. Every generator change in Tasks 8–13 was applied
to a copy of `Tools/generate_project.py` and run twice: the output is identical and no object id
collides.

Tasks with disjoint files may run in parallel, each in its own worktree branched from the tip of
`FrankieBiz/perfect-app-polish-agents`, merged back one at a time, rebased, with
`Tools/linux-test.sh` rerun after each merge. `docs/MAC-VERIFICATION.md` is union-merged and is not
an ownership conflict; `DEVICE-CHECKLIST.md` is not, so its edits follow the waves below. Paths are
relative to `Packages/HardsetKit/Sources/` and `Packages/HardsetKit/Tests/` unless they start with
a top-level folder.

| Task | Files owned | Depends on |
|---|---|---|
| 1 Three decisions of record (docs) | DECISIONS.md | — |
| 2 The Lock Screen rest's content (Core) | HardsetCore/RestActivityContent.swift, HardsetCoreTests/RestActivityContentTests.swift | — |
| 3 Requests from outside the app (Core) | HardsetCore/SystemRequests.swift, HardsetCoreTests/SystemRequestsTests.swift | 1 |
| 4 The Apple Health policy and opt-in (Core, Store) | HardsetCore/HealthExport.swift, HardsetStore/HealthExportSetting.swift, HardsetCoreTests/HealthExportTests.swift, HardsetStoreTests/HealthExportSettingTests.swift | — |
| 6 The widget snapshot (Core, Store) | HardsetCore/WidgetSnapshot.swift, HardsetStore/WidgetSnapshotStore.swift, HardsetCoreTests/WidgetSnapshotTests.swift, HardsetStoreTests/WidgetSnapshotStoreTests.swift | 1 |
| 7 Two feature tips (Core) | HardsetCore/FeatureTips.swift, HardsetCoreTests/FeatureTipsTests.swift | — |
| 8 Launch colour and manifests, pinned (resources) | Hardset/Assets.xcassets/LaunchBackground.colorset/Contents.json (new), Hardset/Info.plist, Hardset/PrivacyInfo.xcprivacy, HardsetWidget/PrivacyInfo.xcprivacy (new), Tools/linux-test.sh, Tools/generate_project.py, Hardset.xcodeproj, HardsetCoreTests/AppResourcesTests.swift (new) | 1 |
| 15 App icon brief and SVG layer drafts (design) | Design/AppIcon/ (new) | — |
| 5 The Apple Health record, a device-local table (Store) | HardsetStore/Migrations.swift, HardsetStore/Schema.swift, HardsetStore/HealthExportStore.swift, HardsetStoreTests/HealthExportStoreTests.swift | 1, 4 |
| 9 The Lock Screen rest, crafted; rest intents (Mac-only) | HardsetAlarm/RestTimerController.swift, HardsetAlarm/RestAlarmService.swift (comments), HardsetWidget/HardsetWidgetBundle.swift, HardsetIntents/RestIntents.swift (new), HardsetIntents/IntentDependencies.swift (new), Hardset/HardsetApp.swift, Tools/generate_project.py, Hardset.xcodeproj, DEVICE-CHECKLIST.md | 2, 3, 8 |
| 10 Start a workout from Siri, Spotlight and the Action button (Mac-only) | HardsetIntents/WorkoutIntents.swift (new), HardsetIntents/HardsetShortcuts.swift (new), HardsetIntents/IntentDependencies.swift, Hardset/HardsetApp.swift, HardsetFeature/HardsetRootView.swift, HardsetFeature/LiveSessionScreen.swift, HardsetFeature/LiveSessionAccessory.swift, Tools/generate_project.py, Hardset.xcodeproj, DEVICE-CHECKLIST.md | 3, 9, **Phase 2 Task 19**, **Phase 3 Tasks 16–19** |
| 11 Control Center controls (Mac-only) | HardsetWidget/HardsetControls.swift (new), HardsetWidget/HardsetWidgetBundle.swift, Tools/generate_project.py, Hardset.xcodeproj, DEVICE-CHECKLIST.md | 3, 9, 10 |
| 12 Widgets: last time on a machine, the last workout (Mac-only) | HardsetWidget/HistoryWidgets.swift (new), HardsetWidget/HardsetWidget.entitlements (new), HardsetWidget/HardsetWidgetBundle.swift, Hardset/Hardset.entitlements, HardsetFeature/WidgetSnapshotWriter.swift (new), HardsetFeature/HardsetEnvironment.swift, HardsetFeature/HardsetRootView.swift, HardsetCoreTests/AppResourcesTests.swift, Tools/generate_project.py, Hardset.xcodeproj, DEVICE-CHECKLIST.md | 6, 8, 11 |
| 13 Apple Health, opt-in and write-only (Mac-only; **shipping blocked**) | Package.swift, HardsetHealth/HealthWorkoutWriter.swift (new), HardsetFeature/HealthExportHooks.swift (new), HardsetFeature/HardsetEnvironment.swift, HardsetFeature/HardsetRootView.swift, HardsetFeature/SettingsSheet.swift, HardsetUI/WorkoutSummaryView.swift, Hardset/HardsetApp.swift, Hardset/Info.plist, Hardset/Hardset.entitlements, HardsetCoreTests/AppResourcesTests.swift, Tools/generate_project.py, Hardset.xcodeproj, DEVICE-CHECKLIST.md | 4, 5, 8, 12, **Phase 3 Tasks 13, 19** |
| 14 The two tips in the logger (Mac-only) | HardsetUI/FeatureTipViews.swift (new), HardsetUI/ExerciseSectionView.swift, HardsetUI/SessionView.swift, Hardset/HardsetApp.swift | 7, 13, **Phase 3 Task 15** |
| 16 Phase 4's copy through the seam (Core) | the five Core files of Tasks 2, 3, 4, 6 and 7, HardsetCoreTests/LocalizedTests.swift | 2–7, **Phase 3 Task 11 merged** |

**Waves:**
- Wave 0: Task 1 (docs only; it is the "decision entry first" for Tasks 3, 5 and 6, and keeps
  `DECISIONS.md` out of the parallel waves).
- Wave 1: 2, 3, 4, 6, 7, 8 and 15, in parallel.
- Wave 2: 5 and 9, in parallel.
- **After Phase 2 Task 19 and Phase 3 Tasks 16–19 merge:** 10, then 11, then 12, then 13, one at a
  time: they share `HardsetApp.swift`, the generator, the widget bundle, the root and
  `DEVICE-CHECKLIST.md`.
- **After Phase 3 Task 15 merges, and after Task 13:** Task 14.
- **After Phase 3 Task 11 merges:** Task 16.

**Rule:** no task may leave a caller of an API it changed uncompiled. A task that changes a
signature updates every call site in the same task, even in files another task owns later, and
names each one. Task 9's `RestTimerController.start(duration:metadata: RestMetadata?)` is source
compatible (its one caller, in `HardsetApp.swift`, passes a non-optional). Task 10's new
`RestTimerHooks.metadata` defaults, so previews compile unchanged. Task 13's
`WorkoutSummaryView(healthLine:)` and `SettingsSheet(health:)` default to `nil`.

---

### Task 1: Three decisions of record (docs)

Spec §4: "Schema changes are additive only, and each needs a `DECISIONS.md` entry first." This
task writes that entry for the one new table, and two more that later tasks argue from, before any
code. It changes nothing else.

**Files:**
- Modify: `DECISIONS.md` (append §24, §25, §26 after §23)

**Interfaces:**
- Consumes: nothing.
- Produces: `DECISIONS.md` §24 (cited by Tasks 5, 8, 13), §25 (Tasks 6, 8, 12), §26 (Tasks 3,
  9–11).

- [ ] **Step 1: Check the numbering**

Run: `rg -n '^### ' DECISIONS.md | tail -2`
Expected: the last entry is `### 23. Core's copy goes through one seam…`. If a later number exists,
renumber the three below from the next free number and update every `§24`/`§25`/`§26` in this
plan's later tasks before they start.

- [ ] **Step 2: Append the entries**

```markdown
### 24. What went to Apple Health is a device-local table, and the export is opt-in and write-only

Phase 4.4 sends a finished workout to Apple Health. Two facts must be remembered per session: that
it was sent, so it is never sent twice, and the HealthKit object it became. They live in a new
table, `deviceHealthExports` (`id`, `sessionID`, `healthWorkoutID`, `exportedAt`), added by an
additive migration `v2-deviceHealthExports`. Nothing in v1 changes.

- **Device-local, never synced.** A HealthKit object id means nothing on another device, and what
  was sent to Health is health information, which guideline 5.1.3(ii) keeps out of iCloud (§5).
  The `device` prefix puts it under `SchemaTests`' existing assertion.
- **`sessionID` is not a foreign key**, like `deviceRestTimer.sessionID`. A sign-out wipe (§1) or a
  deletion arriving from another device removes the session row; with `ON DELETE CASCADE` the
  record would go with it, and the same session downloaded again under the same id would reach
  Health a second time.
- **Not `deviceHealthSamples`.** That table is for values read *from* HealthKit, with a different
  shape, and Hardset reads nothing.

The export itself: opt-in and off by default (a device-local `UserDefaults` flag, CA92.1);
write-only (`read: []`); `.traditionalStrengthTraining`; start and end are the session's own
`startedAt`/`finishedAt`; no energy burned, distance or heart rate, because nothing here measures
them; a length the app would withhold on screen (§21) is withheld from Health; only for a workout
finished on this device, at the moment it is finished, never by backfill and never for a session
that arrived by sync. Shipping it needs a privacy policy URL (spec §12.1); building it does not.

### 25. The widgets read a file the app writes, never the database or a shared defaults suite

`SyncEngine` installs triggers on every synchronized table that call a function living in the
app process (`HardsetDatabase.makeSyncEngine`; `DEVICE-CHECKLIST.md` §A2). A widget extension that opened
the database would fail every write and could read mid-migration. So the app writes one JSON file,
`widget-snapshot.json`, atomically into the App Group container `group.com.hardset.app`, after
launch, after a workout ends and when the unit changes; the widget only reads it, and shows a calm
empty state when it is missing, torn or from a newer build. The snapshot holds finished workouts
only, working sets only, kilograms with the unit beside them, and instants rather than relative
dates (spec 4.5: no "days since" counts).

No `UserDefaults(suiteName:)` exists, so the privacy manifests do not declare `1C8F.1`; the widget
extension gets its own manifest, which declares no required-reason API. `AppResourcesTests` fails
if a shared suite appears, so the declaration cannot be forgotten.

### 26. Nothing outside the app logs a set

Spec §4: "No set is ever logged from outside the app UI: not from Siri, widgets, controls or the
Action button. The lifter must see the numbers being saved." So the system surfaces can do exactly
this: start a workout (in the app, on screen, through `StartWorkoutPolicy`, which never starts one
over an open or unreadable workout), and start, pause, resume or end a rest (a timer, which writes
no training data). No intent, control or widget takes a weight or a rep count, and the request type
the app accepts from outside, `SystemRequest`, has the single case `.startWorkout`. A rest started
from outside has the length the lifter said or configured, validated like a typed one, and never a
default (`HANDOFF.md` §6).
```

- [ ] **Step 3: Commit**

```bash
git add DECISIONS.md
git commit -m "docs: decide the Health record, the widget file, and that nothing outside logs a set

Spec 4 asks for a decision entry before any schema change. Phase 4 adds one
device-local table, for which workouts went to Apple Health, and two rules the
system-surface tasks argue from: the widget reads a file the app writes because
SyncEngine's triggers live in the app process, and no Siri phrase, control or
widget can log a set.

Co-Authored-By: <your model's trailer>"
```

---

### Task 2: The Lock Screen rest's content (Core)

**Files:**
- Create: `Packages/HardsetKit/Sources/HardsetCore/RestActivityContent.swift`
- Test: `Packages/HardsetKit/Tests/HardsetCoreTests/RestActivityContentTests.swift`

**Interfaces:**
- Consumes: `RestMetadata` (`exerciseName`, `setLabel`, `machineName`), `Duration.clockString`.
- Produces, for Task 9:
  - `public struct RestActivityContent: Hashable, Sendable` with `title: String`,
    `detail: String?`, `phase: Phase`, `controls: [Control]`, `statusText: String?`
  - `public enum RestActivityContent.Mode` — `.countdown(total: TimeInterval, previouslyElapsed:
    TimeInterval, startDate: Date, fireDate: Date)`, `.paused(total:previouslyElapsed:)`,
    `.alerting`
  - `public enum RestActivityContent.Phase` — `.counting(range: ClosedRange<Date>)`,
    `.paused(remaining: Duration, fractionRemaining: Double)`, `.finished`
  - `public enum RestActivityContent.Control: String, CaseIterable` — `.pause`, `.resume`, `.stop`,
    each with `title`, `symbolName`, `spokenLabel`
  - `static func make(mode: Mode, metadata: RestMetadata?) -> RestActivityContent`

Rules (each a test): the counting range ends at the deadline, starts at `fireDate − total` (so a
resumed rest keeps its elapsed part), and is never reversed whatever the inputs, including a
start after the deadline, a zero total, NaN or infinity; nothing reads the clock; paused shows the
remainder clamped to 0…total and a fraction in 0…1; counting offers Pause and Skip, paused offers
Resume and Skip, alerting offers nothing (the system's alert has its own stop); the movement leads,
then "Set 2 of 4 · Hammer Strength Leg Press"; with no metadata, or a blank name, the title is
"Rest".

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing

@testable import HardsetCore

@Suite("The Lock Screen rest never draws a range it cannot hold, and names what it is resting for")
struct RestActivityContentTests {
  let t = Date(timeIntervalSince1970: 50_000_000)
  let legPress = RestMetadata(
    exerciseName: "Leg Press", setOrdinal: 2, plannedSets: 4,
    machineName: "Hammer Strength Leg Press")

  private func range(_ content: RestActivityContent) throws -> ClosedRange<Date> {
    guard case .counting(let range) = content.phase else {
      Issue.record("expected a countdown, got \(content.phase)")
      throw CancellationError()
    }
    return range
  }

  @Test("A fresh countdown runs from its start to its deadline, with Pause and Skip")
  func freshCountdown() throws {
    let content = RestActivityContent.make(
      mode: .countdown(total: 120, previouslyElapsed: 0, startDate: t, fireDate: t + 120),
      metadata: legPress)
    #expect(try range(content) == t...(t + 120))
    #expect(content.controls == [.pause, .stop])
    #expect(content.statusText == nil)
  }

  /// Review Focus: the old widget built `Date.now...fireDate`, which traps once the deadline has
  /// passed. Nothing here reads the clock, and a start after the deadline (a clock change, a total
  /// of zero) still yields a valid range that ends at the deadline.
  @Test("A start after the deadline never reverses the range")
  func renderAfterDeadlineNeverReverses() throws {
    let content = RestActivityContent.make(
      mode: .countdown(total: 0, previouslyElapsed: 0, startDate: t + 300, fireDate: t),
      metadata: nil)
    let r = try range(content)
    #expect(r.lowerBound <= r.upperBound)
    #expect(r.upperBound == t)
  }

  @Test("A zero-length countdown is a single instant, not a crash")
  func zeroLengthCountdown() throws {
    let content = RestActivityContent.make(
      mode: .countdown(total: 0, previouslyElapsed: 0, startDate: t, fireDate: t), metadata: nil)
    #expect(try range(content) == t...t)
  }

  @Test("A total that is not a number falls back to the start date")
  func nonFiniteTotal() throws {
    let content = RestActivityContent.make(
      mode: .countdown(total: .nan, previouslyElapsed: .infinity, startDate: t, fireDate: t + 60),
      metadata: nil)
    #expect(try range(content) == t...(t + 60))
  }

  @Test("After a resume the ring still covers the whole rest, elapsed part included")
  func resumedAlarmRingCoversWholeRest() throws {
    // 120 s rest, paused after 30 s, resumed at t: AlarmKit reports startDate t, fire t + 90.
    let content = RestActivityContent.make(
      mode: .countdown(total: 120, previouslyElapsed: 30, startDate: t, fireDate: t + 90),
      metadata: legPress)
    #expect(try range(content) == (t - 30)...(t + 90))
  }

  @Test("Paused shows what is left and how much of the ring remains, with Resume and Skip")
  func pausedRemainder() {
    let content = RestActivityContent.make(
      mode: .paused(total: 120, previouslyElapsed: 30), metadata: legPress)
    #expect(content.phase == .paused(remaining: .seconds(90), fractionRemaining: 0.75))
    #expect(content.controls == [.resume, .stop])
    #expect(content.statusText == "Paused, 1:30 left")
  }

  @Test("A paused remainder stays between nothing and the whole rest")
  func pausedFractionClamped() {
    let over = RestActivityContent.make(mode: .paused(total: 120, previouslyElapsed: 150), metadata: nil)
    #expect(over.phase == .paused(remaining: .zero, fractionRemaining: 0))
    let under = RestActivityContent.make(mode: .paused(total: 120, previouslyElapsed: -10), metadata: nil)
    #expect(under.phase == .paused(remaining: .seconds(120), fractionRemaining: 1))
    let empty = RestActivityContent.make(mode: .paused(total: 0, previouslyElapsed: 0), metadata: nil)
    #expect(empty.phase == .paused(remaining: .zero, fractionRemaining: 0))
  }

  @Test("An alerting rest is finished and offers nothing; the system's alert has its own stop")
  func alertingIsFinished() {
    let content = RestActivityContent.make(mode: .alerting, metadata: legPress)
    #expect(content.phase == .finished)
    #expect(content.controls.isEmpty)
    #expect(content.statusText == "Rest over")
  }

  @Test("The movement leads, then the set and the machine")
  func namesTheMachine() {
    let content = RestActivityContent.make(mode: .alerting, metadata: legPress)
    #expect(content.title == "Leg Press")
    #expect(content.detail == "Set 2 of 4 · Hammer Strength Leg Press")
  }

  @Test("Without a machine the set alone; without a set at all, just Rest")
  func fallbacks() {
    let free = RestMetadata(exerciseName: "Squat", setOrdinal: 1)
    #expect(RestActivityContent.make(mode: .alerting, metadata: free).detail == "Set 1")
    let bare = RestActivityContent.make(mode: .alerting, metadata: nil)
    #expect(bare.title == "Rest")
    #expect(bare.detail == nil)
    let blank = RestMetadata(exerciseName: "   ", setOrdinal: 3, machineName: " ")
    #expect(RestActivityContent.make(mode: .alerting, metadata: blank).title == "Rest")
    #expect(RestActivityContent.make(mode: .alerting, metadata: blank).detail == "Set 3")
  }

  @Test("Every control has a title, a glyph and words for VoiceOver")
  func controlsAreLabelled() {
    for control in RestActivityContent.Control.allCases {
      #expect(!control.title.isEmpty)
      #expect(!control.symbolName.isEmpty)
      #expect(control.spokenLabel.lowercased().contains("rest"))
    }
    #expect(RestActivityContent.Control.stop.title == "Skip")
  }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `Tools/linux-test.sh --filter RestActivityContentTests`
Expected: compile failure, `cannot find 'RestActivityContent' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// What the Lock Screen and the Dynamic Island show for a rest, decided where a test can see it.
///
/// A mirror of AlarmKit's presentation state rather than the type itself, because AlarmKit exists
/// only in the iPhoneOS SDK. The widget maps `AlarmPresentationState.Mode` into `Mode` and draws
/// what comes back, so the rules that can crash or mislead live here:
///
/// - A `ClosedRange<Date>` traps when its lower bound is after its upper. The widget used to build
///   `Date.now...fireDate`, which traps whenever the system renders the activity after the
///   deadline. `Phase.counting` never holds a reversed range, and its bounds do not depend on now.
/// - The ring covers the alarm's whole countdown, including time that elapsed before a pause, so a
///   resumed rest does not restart the ring from full.
public struct RestActivityContent: Hashable, Sendable {
  /// AlarmKit's `AlarmPresentationState.Mode`, reduced to plain values.
  public enum Mode: Hashable, Sendable {
    /// `Mode.Countdown`: `totalCountdownDuration`, `previouslyElapsedDuration`, `startDate`,
    /// `fireDate`.
    case countdown(
      total: TimeInterval, previouslyElapsed: TimeInterval, startDate: Date, fireDate: Date)
    /// `Mode.Paused`: `totalCountdownDuration` and `previouslyElapsedDuration`. No dates exist.
    case paused(total: TimeInterval, previouslyElapsed: TimeInterval)
    /// `Mode.Alert`: the rest is over and the system is sounding it.
    case alerting
  }

  public enum Phase: Hashable, Sendable {
    /// Counting down to `range.upperBound`. The ring (`ProgressView(timerInterval:)`) and the
    /// clock (`Text(timerInterval:)`) both take this one range.
    case counting(range: ClosedRange<Date>)
    /// Frozen, with `fractionRemaining` in 0...1 for a still ring.
    case paused(remaining: Duration, fractionRemaining: Double)
    case finished
  }

  /// A button the activity offers. Each one runs a `LiveActivityIntent` in the app's process, so
  /// the app pauses, resumes or ends its own rest and always knows what is left.
  public enum Control: String, Hashable, Sendable, CaseIterable {
    case pause
    case resume
    /// Ends the rest now, as the in-app Skip does. `StopRestIntent` performs it.
    case stop

    public var title: String {
      switch self {
      case .pause: "Pause"
      case .resume: "Resume"
      case .stop: "Skip"
      }
    }

    public var symbolName: String {
      switch self {
      case .pause: "pause.fill"
      case .resume: "play.fill"
      case .stop: "forward.end.fill"
      }
    }

    /// For VoiceOver, which has no countdown beside the button to explain it.
    public var spokenLabel: String {
      switch self {
      case .pause: "Pause rest"
      case .resume: "Resume rest"
      case .stop: "Skip rest"
      }
    }
  }

  /// The movement, or "Rest" for a rest that no set started (Siri, a control).
  public let title: String
  /// "Set 2 of 4 · Hammer Strength Leg Press", or nil when nothing more is known.
  public let detail: String?
  public let phase: Phase
  public let controls: [Control]

  public init(title: String, detail: String?, phase: Phase, controls: [Control]) {
    self.title = title
    self.detail = detail
    self.phase = phase
    self.controls = controls
  }

  /// A line for the paused and finished states, where no system clock speaks for itself.
  public var statusText: String? {
    switch phase {
    case .counting: nil
    case .paused(let remaining, _): "Paused, \(remaining.clockString) left"
    case .finished: "Rest over"
    }
  }

  public static func make(mode: Mode, metadata: RestMetadata?) -> RestActivityContent {
    let phase: Phase
    let controls: [Control]
    switch mode {
    case .countdown(let total, _, let startDate, let fireDate):
      phase = .counting(range: countingRange(total: total, startDate: startDate, fireDate: fireDate))
      controls = [.pause, .stop]
    case .paused(let total, let elapsed):
      let total = max(0, finite(total))
      let remaining = min(total, max(0, total - finite(elapsed)))
      phase = .paused(
        remaining: .seconds(remaining), fractionRemaining: total > 0 ? remaining / total : 0)
      controls = [.resume, .stop]
    case .alerting:
      // The system draws the alert and its own stop button. Nothing here would mean anything.
      phase = .finished
      controls = []
    }
    return RestActivityContent(
      title: title(for: metadata), detail: detail(for: metadata), phase: phase, controls: controls)
  }

  /// From the moment the whole countdown would have begun to the deadline.
  ///
  /// `fireDate - total` rather than `startDate`, because after a system resume `startDate` is the
  /// resume and the elapsed part would vanish from the ring. With no usable total the start date
  /// stands in, and the lower bound is never later than the deadline either way.
  static func countingRange(total: TimeInterval, startDate: Date, fireDate: Date) -> ClosedRange<
    Date
  > {
    let total = finite(total)
    let start = total > 0 ? fireDate.addingTimeInterval(-total) : startDate
    return min(start, fireDate)...fireDate
  }

  private static func finite(_ value: Double) -> Double { value.isFinite ? value : 0 }

  private static func title(for metadata: RestMetadata?) -> String {
    let name = metadata?.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return name.isEmpty ? "Rest" : name
  }

  private static func detail(for metadata: RestMetadata?) -> String? {
    guard let metadata else { return nil }
    let machine = metadata.machineName?.trimmingCharacters(in: .whitespacesAndNewlines)
    return [metadata.setLabel, machine].compactMap { $0 }.filter { !$0.isEmpty }
      .joined(separator: " · ")
  }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `Tools/linux-test.sh --filter RestActivityContentTests`, then `Tools/linux-test.sh`.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/HardsetKit/Sources/HardsetCore/RestActivityContent.swift \
  Packages/HardsetKit/Tests/HardsetCoreTests/RestActivityContentTests.swift
git commit -m "feat(core): the Lock Screen rest, decided where a test can see it

The widget built Date.now...fireDate, which traps whenever the system draws the
activity after the deadline. The content is now a Core value: a range that never
reverses and never reads the clock, a ring that keeps the time before a pause,
the movement and the machine by name, and Pause, Resume and Skip only where each
means something.

Co-Authored-By: <your model's trailer>"
```

---

### Task 3: Requests from outside the app (Core)

**Files:**
- Create: `Packages/HardsetKit/Sources/HardsetCore/SystemRequests.swift`
- Test: `Packages/HardsetKit/Tests/HardsetCoreTests/SystemRequestsTests.swift`

**Interfaces:**
- Consumes: `RestPlan.allowedRange`, `RestPlan.validated(_:)`, `RestTimerState`,
  `Duration.clockString`; `DECISIONS.md` §26 (Task 1).
- Produces, for Tasks 9, 10 and 11:
  - `public enum RestRequestError: Error, Hashable, Sendable` — `.notANumber`, `.notPositive`,
    `.outOfRange`
  - `public enum RestRequest` with
    `static func duration(seconds: Double) -> Result<Duration, RestRequestError>` and
    `static var refusal: String` ("A rest can be from 0:15 to 30:00.")
  - `public enum RestCommand: Hashable, Sendable` — `.start(Duration)`, `.pause`, `.resume`, `.stop`
  - `public enum RestCommandOutcome: Hashable, Sendable` — `.perform(RestCommand)`, `.nothing(String)`
  - `public enum RestCommandPlan` with
    `static func outcome(for: RestCommand, state: RestTimerState, now: Date) -> RestCommandOutcome`,
    `static func confirmation(for: RestCommand) -> String`, `static let noRest`
  - `public struct WorkoutLaunchState` (`isReady`, `hasOpenWorkout`, `resumeFailed`, `showsFirstRun`)
  - `public enum StartWorkoutAction` — `.wait`, `.startEmptyWorkout`, `.showOpenWorkout`,
    `.showResumeFailure`; `public enum StartWorkoutPolicy` with
    `static func action(for: WorkoutLaunchState) -> StartWorkoutAction`
  - `public enum SystemRequest: Hashable, Sendable` — `.startWorkout` only
  - `@MainActor @Observable public final class SystemRequestInbox` with `pending: SystemRequest?`,
    `post(_:)`, `take() -> SystemRequest?`
  - `public enum RestControlState: Hashable, Sendable` — `.ready(Duration)`, `.needsChoice`, with
    `static func make(configuredSeconds: Double?) -> RestControlState` and `title: String`

Rules (each a test): a requested rest is rounded to whole seconds (floating-point noise only), then
refused outside 0:15–30:00, at zero or below, or when not finite, never clamped and never
defaulted; Start always replaces a rest whose length is allowed; Pause needs a rest still counting,
Resume a paused one, Stop any rest; each "nothing" carries its sentence; Start workout waits until
the launch read has run, shows a workout that could not be reopened rather than starting one,
shows an open workout rather than replacing it, waits for the first-run screen, and otherwise
starts an empty workout; the inbox holds one request until taken, and taking it twice yields it
once; the Rest control without a valid configured length asks for a choice.

`import Observation` is explicit for Linux, as in `SessionCoordinator.swift`. It is part of the
Swift toolchain, not a platform framework, so Core stays Foundation-and-stdlib only.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing

@testable import HardsetCore

@Suite("Requests from outside the app start timers and workouts, never sets, and never guess")
struct SystemRequestsTests {
  let now = Date(timeIntervalSince1970: 60_000_000)

  private func rest(_ seconds: Double) -> Duration? {
    try? RestRequest.duration(seconds: seconds).get()
  }

  @Test("A rest in range comes back in whole seconds")
  func inRange() {
    #expect(rest(90) == .seconds(90))
    #expect(rest(15) == .seconds(15))
    #expect(rest(1800) == .seconds(1800))
  }

  /// 0.1 h is 360.00000000000006 s and 1.5 min is 90 s after conversion; neither may be refused.
  @Test("Floating-point noise from a unit conversion is whole seconds")
  func floatingNoiseIsWholeSeconds() {
    #expect(rest(0.1 * 3600) == .seconds(360))
    #expect(rest(1.5 * 60) == .seconds(90))
  }

  /// Review Focus: Siri hears "a ten second rest", a shortcut is given 45 minutes, a control
  /// carries a stale value. Each is refused with a sentence, never clamped to the nearest limit
  /// and never replaced by a default.
  @Test("Out of range, zero, negative or not a number is refused, not clamped")
  func outOfRangeRefusedNotClamped() {
    #expect(RestRequest.duration(seconds: 10) == .failure(.outOfRange))
    #expect(RestRequest.duration(seconds: 14.4) == .failure(.outOfRange))
    #expect(RestRequest.duration(seconds: 1801) == .failure(.outOfRange))
    #expect(RestRequest.duration(seconds: 1e300) == .failure(.outOfRange))
    #expect(RestRequest.duration(seconds: 0) == .failure(.notPositive))
    #expect(RestRequest.duration(seconds: -60) == .failure(.notPositive))
    #expect(RestRequest.duration(seconds: .nan) == .failure(.notANumber))
    #expect(RestRequest.duration(seconds: .infinity) == .failure(.notANumber))
    #expect(RestRequest.refusal == "A rest can be from 0:15 to 30:00.")
  }

  @Test("Start always replaces the rest, if its length is allowed")
  func startReplaces() {
    let running = RestTimerState.running(endsAt: now + 60)
    #expect(RestCommandPlan.outcome(for: .start(.seconds(120)), state: running, now: now)
      == .perform(.start(.seconds(120))))
    #expect(RestCommandPlan.outcome(for: .start(.seconds(5)), state: .idle, now: now)
      == .nothing(RestRequest.refusal))
  }

  @Test("Pause needs a rest that is still counting")
  func pause() {
    #expect(RestCommandPlan.outcome(for: .pause, state: .running(endsAt: now + 60), now: now)
      == .perform(.pause))
    #expect(RestCommandPlan.outcome(for: .pause, state: .running(endsAt: now - 1), now: now)
      == .nothing("That rest is already over."))
    #expect(RestCommandPlan.outcome(for: .pause, state: .paused(remaining: .seconds(30)), now: now)
      == .nothing("The rest is already paused."))
    #expect(RestCommandPlan.outcome(for: .pause, state: .idle, now: now) == .nothing("No rest is running."))
  }

  @Test("Resume needs a paused rest")
  func resume() {
    #expect(RestCommandPlan.outcome(for: .resume, state: .paused(remaining: .seconds(30)), now: now)
      == .perform(.resume))
    #expect(RestCommandPlan.outcome(for: .resume, state: .running(endsAt: now + 9), now: now)
      == .nothing("The rest is already running."))
    #expect(RestCommandPlan.outcome(for: .resume, state: .idle, now: now) == .nothing("No rest is running."))
  }

  @Test("Stop ends any rest, even one whose deadline just passed, and says so when there is none")
  func stop() {
    #expect(RestCommandPlan.outcome(for: .stop, state: .running(endsAt: now - 1), now: now) == .perform(.stop))
    #expect(RestCommandPlan.outcome(for: .stop, state: .paused(remaining: .seconds(5)), now: now) == .perform(.stop))
    #expect(RestCommandPlan.outcome(for: .stop, state: .idle, now: now) == .nothing("No rest is running."))
  }

  @Test("Siri confirms in plain words")
  func confirmations() {
    #expect(RestCommandPlan.confirmation(for: .start(.seconds(150))) == "Resting for 2:30.")
    #expect(RestCommandPlan.confirmation(for: .pause) == "Rest paused.")
    #expect(RestCommandPlan.confirmation(for: .resume) == "Rest resumed.")
    #expect(RestCommandPlan.confirmation(for: .stop) == "Rest skipped.")
  }

  private func state(
    ready: Bool = true, open: Bool = false, failed: Bool = false, firstRun: Bool = false
  ) -> WorkoutLaunchState {
    WorkoutLaunchState(isReady: ready, hasOpenWorkout: open, resumeFailed: failed, showsFirstRun: firstRun)
  }

  @Test("With nothing open, Start workout starts an empty one")
  func startsEmpty() {
    #expect(StartWorkoutPolicy.action(for: state()) == .startEmptyWorkout)
  }

  /// Review Focus: "Start a workout" said mid-workout, or with a workout that failed to reopen,
  /// must never put a second session on top of the first.
  @Test("An open workout is shown, never replaced")
  func openWorkoutIsShownNotReplaced() {
    #expect(StartWorkoutPolicy.action(for: state(open: true)) == .showOpenWorkout)
    #expect(StartWorkoutPolicy.action(for: state(open: true, firstRun: true)) == .showOpenWorkout)
  }

  @Test("A workout that could not be reopened blocks the start, as the Start button is blocked")
  func resumeFailureBlocksStart() {
    #expect(StartWorkoutPolicy.action(for: state(failed: true)) == .showResumeFailure)
    #expect(StartWorkoutPolicy.action(for: state(open: true, failed: true)) == .showResumeFailure)
  }

  /// Review Focus: on a cold launch the intent runs before the open workout has been read. The
  /// request waits in the inbox, and is acted on once, after the read.
  @Test("Before the launch read, the request waits; it is taken once")
  @MainActor
  func requestWaitsForLaunch() {
    let inbox = SystemRequestInbox()
    inbox.post(.startWorkout)
    inbox.post(.startWorkout)
    #expect(StartWorkoutPolicy.action(for: state(ready: false)) == .wait)
    #expect(inbox.pending == .startWorkout)
    #expect(StartWorkoutPolicy.action(for: state(open: true)) == .showOpenWorkout)
    #expect(inbox.take() == .startWorkout)
    #expect(inbox.take() == nil)
  }

  @Test("The first-run screen is seen before a requested workout starts")
  func firstRunFirst() {
    #expect(StartWorkoutPolicy.action(for: state(firstRun: true)) == .wait)
  }

  /// Review Focus: a control added without choosing a length starts nothing.
  @Test("An unconfigured or stale Rest control asks for a choice instead of starting a rest")
  func unconfiguredControlStartsNothing() {
    #expect(RestControlState.make(configuredSeconds: nil) == .needsChoice)
    #expect(RestControlState.make(configuredSeconds: 5) == .needsChoice)
    #expect(RestControlState.make(configuredSeconds: 3600) == .needsChoice)
    #expect(RestControlState.make(configuredSeconds: 120) == .ready(.seconds(120)))
    #expect(RestControlState.make(configuredSeconds: 120).title == "Rest · 2:00")
    #expect(RestControlState.needsChoice.title == "Rest · Choose")
  }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `Tools/linux-test.sh --filter SystemRequestsTests`
Expected: compile failure, `cannot find 'RestRequest' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation
// Explicit: on Apple platforms `@Observable` arrives transitively, on Linux it does not.
import Observation

// What Siri, Shortcuts, Spotlight, the Action button, Control Center and the Lock Screen may ask
// of Hardset, and what each request does. None of them can log a set: the lifter must see the
// numbers being saved (spec §4). They can start a workout (in the app, on screen), and start,
// pause, resume or end a rest. Nothing here takes a weight or a rep count.

/// Why a rest asked for from outside the app was refused.
public enum RestRequestError: Error, Hashable, Sendable {
  case notANumber
  case notPositive
  case outOfRange
}

/// Turns a duration a person said or configured into a rest, or refuses it.
public enum RestRequest {
  /// The rest asked for, in whole seconds, if it lies in `RestPlan.allowedRange`.
  ///
  /// Required, never defaulted: there is no rest the app may assume (`HANDOFF.md` §6). Rounded to
  /// the nearest second only to absorb floating-point noise from unit conversion (0.1 h is
  /// 360.00000000000006 s); outside the range it is refused, not clamped, as a typed rest is.
  public static func duration(seconds: Double) -> Result<Duration, RestRequestError> {
    guard seconds.isFinite else { return .failure(.notANumber) }
    let whole = seconds.rounded()
    guard whole > 0 else { return .failure(.notPositive) }
    let range = RestPlan.allowedRange
    // Compared as Doubles first, so a huge value never reaches an integer conversion.
    guard whole >= range.lowerBound.seconds, whole <= range.upperBound.seconds,
      let rest = RestPlan.validated(.seconds(Int64(whole)))
    else { return .failure(.outOfRange) }
    return .success(rest)
  }

  /// What Siri says, or a shortcut shows, when a rest is refused.
  public static var refusal: String {
    "A rest can be from \(RestPlan.allowedRange.lowerBound.clockString) "
      + "to \(RestPlan.allowedRange.upperBound.clockString)."
  }
}

/// Something done to the rest timer from outside the app.
public enum RestCommand: Hashable, Sendable {
  case start(Duration)
  case pause
  case resume
  /// Ends the rest now, as the in-app Skip does.
  case stop
}

public enum RestCommandOutcome: Hashable, Sendable {
  case perform(RestCommand)
  /// Nothing to do, and the sentence that says why.
  case nothing(String)
}

/// Decides what a rest command does to the rest that is really running.
///
/// The caller must have reconciled the timer first: an intent can launch the app in the
/// background, where the controller reads idle until it has looked at AlarmKit.
public enum RestCommandPlan {
  public static let noRest = "No rest is running."

  public static func outcome(
    for command: RestCommand, state: RestTimerState, now: Date
  ) -> RestCommandOutcome {
    switch command {
    case .start(let duration):
      // A new rest replaces the current one: the lifter asked for it by name.
      return RestPlan.validated(duration) == nil ? .nothing(RestRequest.refusal) : .perform(command)
    case .pause:
      switch state {
      case .idle: return .nothing(noRest)
      case .paused: return .nothing("The rest is already paused.")
      case .running: return state.hasElapsed(at: now) ? .nothing("That rest is already over.") : .perform(command)
      }
    case .resume:
      switch state {
      case .idle: return .nothing(noRest)
      case .running: return .nothing("The rest is already running.")
      case .paused: return .perform(command)
      }
    case .stop:
      return state == .idle ? .nothing(noRest) : .perform(command)
    }
  }

  /// What Siri says once a command has been carried out.
  public static func confirmation(for command: RestCommand) -> String {
    switch command {
    case .start(let duration): "Resting for \(duration.clockString)."
    case .pause: "Rest paused."
    case .resume: "Rest resumed."
    case .stop: "Rest skipped."
    }
  }
}

/// What the app knows, at the moment a "Start workout" request arrives.
public struct WorkoutLaunchState: Hashable, Sendable {
  /// The launch read (resume an open workout) has run. Before it, nothing is known.
  public var isReady: Bool
  public var hasOpenWorkout: Bool
  /// A workout may be open but could not be read.
  public var resumeFailed: Bool
  public var showsFirstRun: Bool

  public init(isReady: Bool, hasOpenWorkout: Bool, resumeFailed: Bool, showsFirstRun: Bool) {
    self.isReady = isReady
    self.hasOpenWorkout = hasOpenWorkout
    self.resumeFailed = resumeFailed
    self.showsFirstRun = showsFirstRun
  }
}

public enum StartWorkoutAction: Hashable, Sendable {
  /// Keep the request until the app can act on it.
  case wait
  case startEmptyWorkout
  case showOpenWorkout
  case showResumeFailure
}

/// "Start a workout" from Siri, Spotlight, the Action button or Control Center.
///
/// It never starts a second workout over the first. A workout that could not be reopened blocks it
/// exactly as it blocks the Start button (Phase 1: an open session must never look like "no
/// workout"), and the first-run screen is seen before anything starts.
public enum StartWorkoutPolicy {
  public static func action(for state: WorkoutLaunchState) -> StartWorkoutAction {
    guard state.isReady else { return .wait }
    if state.resumeFailed { return .showResumeFailure }
    if state.hasOpenWorkout { return .showOpenWorkout }
    if state.showsFirstRun { return .wait }
    return .startEmptyWorkout
  }
}

/// A request that needs the app's screen.
///
/// One case on purpose. Rest commands go straight to the timer; nothing that logs, edits or
/// finishes a workout may arrive from outside the app.
public enum SystemRequest: Hashable, Sendable {
  case startWorkout
}

/// Holds a request from outside the app until the root view can act on it.
///
/// An intent can run before any view exists (a cold launch), so the request waits here rather than
/// being handed to a view that is not there. One slot: asking twice starts one workout.
@MainActor
@Observable
public final class SystemRequestInbox {
  public private(set) var pending: SystemRequest?

  public init() {}

  public func post(_ request: SystemRequest) {
    pending = request
  }

  /// The pending request, removed. Call only when acting on it; a request the app must wait on
  /// stays where it is.
  public func take() -> SystemRequest? {
    defer { pending = nil }
    return pending
  }
}

/// The Rest control in Control Center, from the duration the lifter configured when adding it.
public enum RestControlState: Hashable, Sendable {
  case ready(Duration)
  /// Not configured, or configured with a duration that is no longer allowed. Tapping it opens the
  /// app; it never starts a rest of a length nobody chose.
  case needsChoice

  public static func make(configuredSeconds: Double?) -> RestControlState {
    guard let configuredSeconds,
      case .success(let rest) = RestRequest.duration(seconds: configuredSeconds)
    else { return .needsChoice }
    return .ready(rest)
  }

  /// The control's label, in the same words as the rest chip.
  public var title: String {
    switch self {
    case .ready(let rest): "Rest · \(rest.clockString)"
    case .needsChoice: "Rest · Choose"
    }
  }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `Tools/linux-test.sh --filter SystemRequestsTests`, then `Tools/linux-test.sh`.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/HardsetKit/Sources/HardsetCore/SystemRequests.swift \
  Packages/HardsetKit/Tests/HardsetCoreTests/SystemRequestsTests.swift
git commit -m "feat(core): what Siri and Control Center may ask, and what each request does

A rest asked for in words is refused outside 0:15 to 30:00, never clamped and
never defaulted, and a control nobody configured starts nothing. Start workout
never puts a second session on top of an open or unreadable one, and waits out a
cold launch in an inbox. Nothing here can log a set (DECISIONS 26).

Co-Authored-By: <your model's trailer>"
```

---

### Task 4: The Apple Health policy and opt-in (Core, Store)

**Files:**
- Create: `Packages/HardsetKit/Sources/HardsetCore/HealthExport.swift`
- Create: `Packages/HardsetKit/Sources/HardsetStore/HealthExportSetting.swift`
- Test: `Packages/HardsetKit/Tests/HardsetCoreTests/HealthExportTests.swift`
- Test: `Packages/HardsetKit/Tests/HardsetStoreTests/HealthExportSettingTests.swift`

**Interfaces:**
- Consumes: `SessionTimeline` (`startedAt`, `finishedAt`, `duration`, `isImplausible`), `SessionID`.
- Produces, for Tasks 5 and 13:
  - `public enum HealthActivity: String` — `.traditionalStrengthTraining` only
  - `public struct HealthWorkoutPlan: Hashable, Sendable` (`sessionID`, `activity`, `start`, `end`,
    `externalID: String`); no energy, distance or heart-rate field exists
  - `public enum HealthExportSkip: String, CaseIterable` — `.notEnabled`, `.alreadyExported`,
    `.stillOpen`, `.nothingLogged`, `.lengthUnknown`, `.implausiblyLong`, `.endsInFuture`
  - `public enum HealthExportDecision` — `.export(HealthWorkoutPlan)`, `.skip(HealthExportSkip)`
  - `public enum HealthExportPolicy` with `static func decide(sessionID:timeline:loggedSets:isEnabled:alreadyExported:now:) -> HealthExportDecision`
  - `public enum HealthExportOutcome` — `.saved`, `.failed`, `.skipped(HealthExportSkip)`
  - `public enum HealthExportCopy` — `settingTitle`, `settingFooter`, `accessDenied`,
    `summaryLine(for:) -> String?`
  - `public nonisolated protocol HealthExportSetting: AnyObject, Sendable` (`isEnabled`,
    `setEnabled(_:)`), `UserDefaultsHealthExportSetting(defaults:)` (key
    `hardset.healthExport.enabled`, false when missing), `InMemoryHealthExportSetting(isEnabled:)`

Rules (each a test): off beats everything and examines nothing; never twice; an open workout or
one with nothing logged is not exported; a zero or unknown length, one over
`SessionTimeline.plausibleLimit`, and one ending after now are skipped; otherwise strength training
from the session's own start to its own finish, with the session id as the external id; the
setting says what is sent, that no calories are, and that nothing is read; the summary says
"saved" only for `.saved` and stays silent for skips nobody needs; the opt-in is off on a fresh
install and survives a relaunch.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing

@testable import HardsetCore

@Suite("A workout reaches Apple Health only when asked, with its own times, and nothing invented")
struct HealthExportTests {
  let start = Date(timeIntervalSince1970: 70_000_000)
  let id = SessionID()

  private func decide(
    finishedAfter seconds: Double?, sets: Int = 6, enabled: Bool = true, exported: Bool = false,
    now: Date? = nil
  ) -> HealthExportDecision {
    let timeline = SessionTimeline(
      startedAt: start, finishedAt: seconds.map { start.addingTimeInterval($0) })
    return HealthExportPolicy.decide(
      sessionID: id, timeline: timeline, loggedSets: sets, isEnabled: enabled,
      alreadyExported: exported, now: now ?? start.addingTimeInterval(86_400))
  }

  @Test("A finished workout goes as strength training, from its start to its finish")
  func exportsTimeline() {
    let expected = HealthWorkoutPlan(
      sessionID: id, activity: .traditionalStrengthTraining, start: start,
      end: start.addingTimeInterval(3_000))
    #expect(decide(finishedAfter: 3_000) == .export(expected))
    #expect(expected.externalID == id.description)
  }

  /// When the lifter has not opted in, nothing else is examined, so no reason leaks.
  @Test("Off means off, whatever the workout")
  func offBeatsEverything() {
    #expect(decide(finishedAfter: nil, sets: 0, enabled: false, exported: true) == .skip(.notEnabled))
  }

  @Test("Never twice")
  func neverTwice() {
    #expect(decide(finishedAfter: 3_000, exported: true) == .skip(.alreadyExported))
  }

  @Test("An open workout, or one with nothing logged, is not a workout to record")
  func openOrEmpty() {
    #expect(decide(finishedAfter: nil) == .skip(.stillOpen))
    #expect(decide(finishedAfter: 3_000, sets: 0) == .skip(.nothingLogged))
  }

  /// Review Focus: a session left open overnight and finished in the morning is the ancestor's
  /// 9,749-minute workout. Health must not receive it, nor a zero-length one.
  @Test("An implausibly long or zero-length workout is skipped")
  func implausiblyLongIsSkipped() {
    #expect(decide(finishedAfter: 7 * 3_600) == .skip(.implausiblyLong))
    #expect(decide(finishedAfter: 6 * 3_600) != .skip(.implausiblyLong))
    #expect(decide(finishedAfter: 0) == .skip(.lengthUnknown))
  }

  /// Review Focus: the clock moved backwards after the workout, so its end is "in the future".
  @Test("A workout that ends after now is skipped")
  func endsInFutureIsSkipped() {
    #expect(decide(finishedAfter: 3_000, now: start.addingTimeInterval(1_000)) == .skip(.endsInFuture))
    #expect(decide(finishedAfter: 3_000, now: start.addingTimeInterval(3_000)) != .skip(.endsInFuture))
  }

  @Test("The setting says what is sent and what is not, and that nothing is read")
  func settingCopy() {
    #expect(HealthExportCopy.settingFooter.contains("strength training"))
    #expect(HealthExportCopy.settingFooter.contains("no calories"))
    #expect(HealthExportCopy.settingFooter.contains("never reads"))
  }

  @Test("The summary says saved only when it was, and stays quiet about skips nobody needs")
  func summaryLines() {
    #expect(HealthExportCopy.summaryLine(for: .saved) == "Saved to Apple Health as strength training.")
    #expect(HealthExportCopy.summaryLine(for: .failed)?.contains("still saved here") == true)
    #expect(HealthExportCopy.summaryLine(for: .skipped(.notEnabled)) == nil)
    #expect(HealthExportCopy.summaryLine(for: .skipped(.alreadyExported)) == nil)
    #expect(HealthExportCopy.summaryLine(for: .skipped(.implausiblyLong))?.contains("length is unknown") == true)
  }
}
```

```swift
import Foundation
import Testing

@testable import HardsetStore

@Suite("Saving to Apple Health is off until the lifter turns it on, and stays as they left it")
struct HealthExportSettingTests {
  private func defaults() -> UserDefaults {
    UserDefaults(suiteName: "hardset.tests.\(UUID().uuidString)")!
  }

  @Test("A fresh install is opted out")
  func offByDefault() {
    #expect(!UserDefaultsHealthExportSetting(defaults: defaults()).isEnabled)
    #expect(!InMemoryHealthExportSetting().isEnabled)
  }

  @Test("The choice survives a relaunch, both ways")
  func persists() {
    let suite = defaults()
    UserDefaultsHealthExportSetting(defaults: suite).setEnabled(true)
    #expect(UserDefaultsHealthExportSetting(defaults: suite).isEnabled)
    UserDefaultsHealthExportSetting(defaults: suite).setEnabled(false)
    #expect(!UserDefaultsHealthExportSetting(defaults: suite).isEnabled)
  }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `Tools/linux-test.sh --filter 'HealthExportTests|HealthExportSettingTests'`
Expected: compile failure, `cannot find 'HealthExportPolicy' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// The only kind of workout Hardset writes to Apple Health.
public enum HealthActivity: String, Hashable, Sendable {
  /// `HKWorkoutActivityType.traditionalStrengthTraining`: "strength training exercises primarily
  /// using machines or free weights".
  case traditionalStrengthTraining
}

/// One workout, as Apple Health will receive it.
///
/// Deliberately small. There is no energy, distance or heart-rate field, so none can be sent:
/// nothing in Hardset measures them, and an estimate written into Health becomes someone else's
/// "measurement" (spec 4.4). There is no indoor/outdoor flag either, because the app does not know.
public struct HealthWorkoutPlan: Hashable, Sendable {
  public let sessionID: SessionID
  public let activity: HealthActivity
  public let start: Date
  public let end: Date

  public init(sessionID: SessionID, activity: HealthActivity, start: Date, end: Date) {
    self.sessionID = sessionID
    self.activity = activity
    self.start = start
    self.end = end
  }

  /// Written as `HKMetadataKeyExternalUUID`, so a workout in Health can be traced to its session.
  public var externalID: String { sessionID.description }
}

/// Why a finished workout is not sent to Apple Health.
public enum HealthExportSkip: String, Hashable, Sendable, CaseIterable {
  /// The lifter has not turned it on. Checked first: when off, nothing else is looked at.
  case notEnabled
  case alreadyExported
  case stillOpen
  case nothingLogged
  /// The clock gives no length (it ran backwards, or start and end are the same instant).
  case lengthUnknown
  /// Longer than any real workout (`SessionTimeline.plausibleLimit`): a session left open.
  case implausiblyLong
  /// Ends after now: the device clock has moved, so the times cannot be trusted.
  case endsInFuture
}

public enum HealthExportDecision: Hashable, Sendable {
  case export(HealthWorkoutPlan)
  case skip(HealthExportSkip)
}

/// Decides whether a finished workout goes to Apple Health, and with which times.
///
/// Start and end are the session's own immutable instants (`SessionTimeline`), never "now" and
/// never the first and last set. A length the app would withhold on its own screens
/// (`DECISIONS.md` §21) is withheld from Health too.
public enum HealthExportPolicy {
  public static func decide(
    sessionID: SessionID,
    timeline: SessionTimeline,
    loggedSets: Int,
    isEnabled: Bool,
    alreadyExported: Bool,
    now: Date
  ) -> HealthExportDecision {
    guard isEnabled else { return .skip(.notEnabled) }
    guard !alreadyExported else { return .skip(.alreadyExported) }
    guard let end = timeline.finishedAt else { return .skip(.stillOpen) }
    guard loggedSets > 0 else { return .skip(.nothingLogged) }
    guard let length = timeline.duration, length > .zero else { return .skip(.lengthUnknown) }
    guard !timeline.isImplausible else { return .skip(.implausiblyLong) }
    guard end <= now else { return .skip(.endsInFuture) }
    return .export(
      HealthWorkoutPlan(
        sessionID: sessionID, activity: .traditionalStrengthTraining,
        start: timeline.startedAt, end: end))
  }
}

/// What became of one workout and Apple Health, for a line under the summary.
public enum HealthExportOutcome: Hashable, Sendable {
  case saved
  case failed
  case skipped(HealthExportSkip)
}

/// The words around the Apple Health setting and its results.
public enum HealthExportCopy {
  public static let settingTitle = "Save workouts to Apple Health"
  public static let settingFooter =
    "Each workout you finish on this iPhone is added to Health as strength training, with its "
    + "start and end time. Nothing else is sent: no calories, because nothing here measures them. "
    + "Hardset never reads your Health data."
  public static let accessDenied =
    "Hardset can't save to Health. Turn it on in Settings › Health › Data Access & Devices › Hardset."

  /// The line under the summary, or nil when there is nothing worth saying.
  public static func summaryLine(for outcome: HealthExportOutcome) -> String? {
    switch outcome {
    case .saved: return "Saved to Apple Health as strength training."
    case .failed: return "Couldn't save this workout to Apple Health. It is still saved here."
    case .skipped(let reason):
      switch reason {
      case .notEnabled, .alreadyExported, .stillOpen, .nothingLogged: return nil
      case .lengthUnknown, .implausiblyLong, .endsInFuture:
        return "Not sent to Apple Health, because its length is unknown."
      }
    }
  }
}
```

```swift
import Foundation
import Synchronization

/// Whether the lifter has asked for finished workouts to be saved to Apple Health. Off until they
/// turn it on.
///
/// Device-local, like rest choices: Health permission is granted per device, so the choice is too.
/// `UserDefaults` is already declared in the privacy manifest (CA92.1).
public nonisolated protocol HealthExportSetting: AnyObject, Sendable {
  var isEnabled: Bool { get }
  func setEnabled(_ enabled: Bool)
}

/// `UserDefaults` is documented as thread-safe, which is what makes `@unchecked` honest here.
public nonisolated final class UserDefaultsHealthExportSetting: HealthExportSetting, @unchecked Sendable {
  static let key = "hardset.healthExport.enabled"
  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  /// `bool(forKey:)` is false for a missing key, which is the opt-in default.
  public var isEnabled: Bool { defaults.bool(forKey: Self.key) }

  public func setEnabled(_ enabled: Bool) {
    defaults.set(enabled, forKey: Self.key)
  }
}

/// For tests and previews.
public nonisolated final class InMemoryHealthExportSetting: HealthExportSetting {
  private let storage: Mutex<Bool>

  public init(isEnabled: Bool = false) {
    storage = Mutex(isEnabled)
  }

  public var isEnabled: Bool { storage.withLock { $0 } }

  public func setEnabled(_ enabled: Bool) {
    storage.withLock { $0 = enabled }
  }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `Tools/linux-test.sh --filter 'HealthExportTests|HealthExportSettingTests'`, then
`Tools/linux-test.sh`.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/HardsetKit/Sources/HardsetCore/HealthExport.swift \
  Packages/HardsetKit/Sources/HardsetStore/HealthExportSetting.swift \
  Packages/HardsetKit/Tests/HardsetCoreTests/HealthExportTests.swift \
  Packages/HardsetKit/Tests/HardsetStoreTests/HealthExportSettingTests.swift
git commit -m "feat(core): what Apple Health may receive, decided off the device

Strength training, from the session's own start to its own finish, and nothing
else: no calories, because nothing here measures them. A workout left open
overnight, one finished with the clock moved back, or one already sent is not
sent. The opt-in is off until the lifter turns it on, and when it is off nothing
else is looked at.

Co-Authored-By: <your model's trailer>"
```

---

### Task 5: The Apple Health record, a device-local table (Store)

**Precondition:** Task 1 (`DECISIONS.md` §24) and Task 4 are merged.

**Files:**
- Modify: `Packages/HardsetKit/Sources/HardsetStore/Migrations.swift`
  (`deviceLocalTableNames`, line 52; a new migration before `return migrator`, line 318)
- Modify: `Packages/HardsetKit/Sources/HardsetStore/Schema.swift` (append after `DeviceRestTimer`)
- Create: `Packages/HardsetKit/Sources/HardsetStore/HealthExportStore.swift`
- Test: `Packages/HardsetKit/Tests/HardsetStoreTests/HealthExportStoreTests.swift`

**Interfaces:**
- Consumes: `HealthExportPolicy`, `HealthExportDecision`, `HealthWorkoutPlan` (Task 4);
  `LoggerStoreError.sessionNotFound`.
- Produces, for Task 13: `public nonisolated struct HealthExportStore` with `init(database:)`,
  `func decision(for: SessionID, isEnabled: Bool, now: Date = Date()) throws -> HealthExportDecision`,
  `func recordExport(of: SessionID, healthWorkoutID: UUID, at: Date = Date()) throws`,
  `func healthWorkoutID(for: SessionID) throws -> UUID?`.

The existing `SchemaTests` cover the new table without edits: `allTablesExist`,
`deviceTablesAreNotSynced` and `noReservedColumnNames` iterate
`HardsetMigrations.deviceLocalTableNames`, so adding the name there puts the table under every
assertion. `eraseDatabaseOnSchemaChange` (DEBUG only) compares already-applied migrations, so a new
migration does not erase a development database.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

@Suite("A workout goes to Apple Health once, from this device, with the times it really had")
struct HealthExportStoreTests {
  let now = Date(timeIntervalSince1970: 80_000_000)

  private func database(migrated: Bool = true) throws -> any DatabaseWriter {
    var configuration = Configuration.forTesting()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    if migrated { try HardsetMigrations.migrator().migrate(queue) }
    return queue
  }

  /// A seeded catalogue, one finished session of `length` seconds with `sets` working sets.
  private func workout(
    _ db: any DatabaseWriter, length: Double? = 3_000, sets: Int = 2
  ) throws -> SessionID {
    try CatalogSeeder(database: db).seed(now: now)
    let exercise = try #require(try db.read { try Exercise.fetchOne($0) })
    let logger = LoggerStore(database: db)
    let session = try logger.startSession(at: now)
    for index in 0..<sets {
      try logger.logSet(
        sessionID: session, exerciseID: ExerciseID(rawValue: exercise.id),
        draft: SetEntryDraft(weightKg: 100, reps: 8), at: now.addingTimeInterval(Double(index + 1) * 60))
    }
    if let length { try logger.finishSession(session, at: now.addingTimeInterval(length)) }
    return session
  }

  @Test("When off, nothing is read, not even a database that cannot be")
  func offReadsNothing() throws {
    let store = HealthExportStore(database: try database(migrated: false))
    #expect(try store.decision(for: SessionID(), isEnabled: false) == .skip(.notEnabled))
  }

  @Test("A finished workout is offered with its session's own start and finish")
  func finishedWorkoutIsExported() throws {
    let db = try database()
    let session = try workout(db)
    let decision = try HealthExportStore(database: db)
      .decision(for: session, isEnabled: true, now: now.addingTimeInterval(4_000))
    #expect(
      decision
        == .export(
          HealthWorkoutPlan(
            sessionID: session, activity: .traditionalStrengthTraining, start: now,
            end: now.addingTimeInterval(3_000))))
  }

  @Test("Once recorded, the same workout is never offered again")
  func secondExportIsSkipped() throws {
    let db = try database()
    let session = try workout(db)
    let store = HealthExportStore(database: db)
    let healthID = UUID()
    try store.recordExport(of: session, healthWorkoutID: healthID, at: now.addingTimeInterval(3_001))
    #expect(try store.healthWorkoutID(for: session) == healthID)
    #expect(
      try store.decision(for: session, isEnabled: true, now: now.addingTimeInterval(4_000))
        == .skip(.alreadyExported))
  }

  /// Review Focus: signing out of iCloud wipes the synced session rows; signing back in downloads
  /// the same session again, under the same id. It must not reach Health a second time.
  @Test("The record survives the session row, so a re-downloaded workout is not sent twice")
  func exportSurvivesSessionDeletion() throws {
    let db = try database()
    let session = try workout(db)
    let store = HealthExportStore(database: db)
    try store.recordExport(of: session, healthWorkoutID: UUID(), at: now.addingTimeInterval(3_001))

    let row = try #require(try db.read { db in
      try Session.where { $0.id.eq(session.rawValue) }.fetchOne(db)
    })
    try db.write { db in try Session.where { $0.id.eq(session.rawValue) }.delete().execute(db) }
    #expect(try store.healthWorkoutID(for: session) != nil)

    try db.write { db in
      try Session.insert {
        Session.Draft(
          id: row.id, gymID: nil, title: row.title, notes: row.notes, startedAt: row.startedAt,
          finishedAt: row.finishedAt)
      }
      .execute(db)
    }
    #expect(
      try store.decision(for: session, isEnabled: true, now: now.addingTimeInterval(4_000))
        == .skip(.alreadyExported))
  }

  @Test("An open workout, an empty one, and one left open overnight are not sent")
  func notWorkoutsToRecord() throws {
    let db = try database()
    let open = try workout(db, length: nil)
    let store = HealthExportStore(database: db)
    let later = now.addingTimeInterval(86_400)
    #expect(try store.decision(for: open, isEnabled: true, now: later) == .skip(.stillOpen))

    let logger = LoggerStore(database: db)
    let empty = try logger.startSession(at: now)
    try logger.finishSession(empty, at: now.addingTimeInterval(600))
    #expect(try store.decision(for: empty, isEnabled: true, now: later) == .skip(.nothingLogged))

    let overnight = try logger.startSession(at: now)
    try logger.logSet(
      sessionID: overnight,
      exerciseID: ExerciseID(rawValue: try #require(try db.read { try Exercise.fetchOne($0) }).id),
      draft: SetEntryDraft(weightKg: 60, reps: 10), at: now.addingTimeInterval(60))
    try logger.finishSession(overnight, at: now.addingTimeInterval(9 * 3_600))
    #expect(try store.decision(for: overnight, isEnabled: true, now: later) == .skip(.implausiblyLong))
  }

  @Test("An unknown session is an error, not a skip")
  func unknownSessionThrows() throws {
    let store = HealthExportStore(database: try database())
    #expect(throws: LoggerStoreError.sessionNotFound) {
      try store.decision(for: SessionID(), isEnabled: true)
    }
  }

  @Test("The table is device-local: named so, and never synchronized")
  func tableIsDeviceLocal() {
    #expect(HardsetMigrations.deviceLocalTableNames.contains("deviceHealthExports"))
    #expect(!HardsetMigrations.syncedTableNames.contains("deviceHealthExports"))
  }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `Tools/linux-test.sh --filter HealthExportStoreTests`
Expected: compile failure, `cannot find 'HealthExportStore' in scope`.

- [ ] **Step 3: Implement**

In `Migrations.swift`, add the table to the device-local list:

```swift
  public static let deviceLocalTableNames: [String] = [
    "deviceHealthSamples",
    "deviceRestTimer",
    "deviceHealthExports",
  ]
```

and register the migration after `v1`, immediately before `return migrator`:

```swift
    // MARK: v2 -- which sessions went to Apple Health (DECISIONS.md §24)
    //
    // Additive: one new device-local table, nothing in v1 touched. Device-local because a
    // HealthKit object id means nothing on another device, and because what was sent to Health is
    // health information that must not reach iCloud (guideline 5.1.3(ii)).
    //
    // `sessionID` is deliberately NOT a foreign key, like `deviceRestTimer.sessionID`. A sign-out
    // wipe or a deletion arriving from another device removes the session row; with a cascade the
    // record of the export would go with it, and the same session downloaded again would be sent
    // to Health a second time.
    migrator.registerMigration("v2-deviceHealthExports") { db in
      try #sql(
        """
        CREATE TABLE "deviceHealthExports" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "sessionID" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "healthWorkoutID" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "exportedAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now', 'subsec'))
        ) STRICT
        """
      )
      .execute(db)
      try #sql(
        """
        CREATE INDEX "deviceHealthExports_on_sessionID" ON "deviceHealthExports"("sessionID")
        """
      )
      .execute(db)
    }
```

Append to `Schema.swift`:

```swift
/// Which sessions were saved to Apple Health, and as which HealthKit object (`DECISIONS.md` §24).
@Table("deviceHealthExports")
nonisolated struct DeviceHealthExport: Hashable, Identifiable, Sendable {
  let id: UUID
  /// Not a foreign key, on purpose: the record outlives the session row (see the migration).
  var sessionID: UUID
  var healthWorkoutID: UUID
  var exportedAt = Date(timeIntervalSince1970: 0)
}
```

Create `HealthExportStore.swift`:

```swift
import Foundation
import HardsetCore
import SQLiteData

/// Remembers which workouts went to Apple Health, so none goes twice, and decides whether one may.
///
/// Called for one session, at the moment it is finished on this device. There is deliberately no
/// way to ask for "every session": a workout that arrives by sync was finished on another device,
/// which sent it to Health itself if its owner asked, and a backfill would send sessions nobody
/// chose to share when the setting was off.
public nonisolated struct HealthExportStore {
  private let database: any DatabaseWriter

  public init(database: any DatabaseWriter) {
    self.database = database
  }

  /// When the lifter has not opted in, nothing is read at all.
  public func decision(
    for sessionID: SessionID, isEnabled: Bool, now: Date = Date()
  ) throws -> HealthExportDecision {
    guard isEnabled else { return .skip(.notEnabled) }
    return try database.read { db in
      guard let session = try Session.where({ $0.id.eq(sessionID.rawValue) }).fetchOne(db) else {
        throw LoggerStoreError.sessionNotFound
      }
      let sets = try LoggedSet.where { $0.sessionID.eq(sessionID.rawValue) }.fetchCount(db)
      let exported =
        try DeviceHealthExport.where { $0.sessionID.eq(sessionID.rawValue) }.fetchCount(db) > 0
      return HealthExportPolicy.decide(
        sessionID: sessionID,
        timeline: SessionTimeline(startedAt: session.startedAt, finishedAt: session.finishedAt),
        loggedSets: sets, isEnabled: true, alreadyExported: exported, now: now)
    }
  }

  /// Written only after HealthKit has saved the workout: persist before claiming.
  public func recordExport(of sessionID: SessionID, healthWorkoutID: UUID, at now: Date = Date())
    throws
  {
    try database.write { db in
      try DeviceHealthExport.insert {
        DeviceHealthExport.Draft(
          sessionID: sessionID.rawValue, healthWorkoutID: healthWorkoutID, exportedAt: now)
      }
      .execute(db)
    }
  }

  /// The HealthKit workout a session became, if it was sent.
  public func healthWorkoutID(for sessionID: SessionID) throws -> UUID? {
    try database.read { db in
      try DeviceHealthExport.where { $0.sessionID.eq(sessionID.rawValue) }.fetchOne(db)?
        .healthWorkoutID
    }
  }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `Tools/linux-test.sh --filter 'HealthExportStoreTests|SchemaTests'`, then `Tools/linux-test.sh`.
Expected: PASS. `SchemaTests` now also checks `deviceHealthExports`.

- [ ] **Step 5: Commit**

```bash
git add Packages/HardsetKit/Sources/HardsetStore/Migrations.swift \
  Packages/HardsetKit/Sources/HardsetStore/Schema.swift \
  Packages/HardsetKit/Sources/HardsetStore/HealthExportStore.swift \
  Packages/HardsetKit/Tests/HardsetStoreTests/HealthExportStoreTests.swift
git commit -m "feat(store): remember which workouts went to Apple Health, on this device only

One additive, device-local table (DECISIONS 24). Its session id is deliberately
not a foreign key: a sign-out wipe deletes the session row, and signing back in
downloads the same session under the same id, which must not reach Health twice.
The decision is made from the database, and when the opt-in is off nothing is
read at all.

Co-Authored-By: <your model's trailer>"
```

---

### Task 6: The widget snapshot (Core, Store)

**Precondition:** Task 1 (`DECISIONS.md` §25) is merged.

**Files:**
- Create: `Packages/HardsetKit/Sources/HardsetCore/WidgetSnapshot.swift`
- Create: `Packages/HardsetKit/Sources/HardsetStore/WidgetSnapshotStore.swift`
- Test: `Packages/HardsetKit/Tests/HardsetCoreTests/WidgetSnapshotTests.swift`
- Test: `Packages/HardsetKit/Tests/HardsetStoreTests/WidgetSnapshotStoreTests.swift`

**Interfaces:**
- Consumes: `WeightFormatter` (`load`, `total`, `spoken`), `CountText`, `Duration.clockString`,
  `HistoryStore.recentSessions(limit:)`, `MachineRecord.displayName`, `ProgressionKey`.
- Produces, for Task 12:
  - `public struct WidgetSnapshot: Codable, Hashable, Sendable` (`version`, `writtenAt`, `unit`,
    `lastWorkout: LastWorkout?`, `lastTimes: [LastTime]`, `formatter`), `currentVersion = 1`,
    `lastTimeLimit = 3`, `static func dayText(_:locale:timeZone:) -> String`
  - `WidgetSnapshot.LastWorkout` (`startedAt`, `finishedAt`, `lengthSeconds: Double?`,
    `workingSets`, `volumeKg`, `movementCount`, `totalsText(formatter:)`, `lengthText`)
  - `WidgetSnapshot.LastTime: Identifiable` (`exerciseID`, `machineID`, `exerciseName`,
    `machineName`, `performedAt`, `sets: [SetLine]`, `equipmentText`,
    `lines(formatter:limit:) -> [String]`, `spokenSummary(formatter:) -> String`)
  - `public enum WidgetSnapshotReading` — `.snapshot(WidgetSnapshot)`, `.nothingYet`, `.unreadable`
  - `public enum WidgetCopy` — `nothingYet`, `unreadable`, `lastTimeTitle`, `lastWorkoutTitle`
  - `public struct WidgetSnapshotFile` with `appGroupIdentifier = "group.com.hardset.app"`,
    `fileName = "widget-snapshot.json"`, `init(url:)`, `init?(containerURL: URL?)`,
    `write(_:) throws`, `read() -> WidgetSnapshotReading`, `static func decode(_:) -> WidgetSnapshotReading`
  - `public nonisolated struct WidgetSnapshotStore` with `init(database:)` and
    `func snapshot(unit: WeightUnit, now: Date = Date()) throws -> WidgetSnapshot`

Rules (each a test): the file round-trips; no file is "nothing yet"; a torn, empty or newer-version
file is "unreadable", never a crash; sets read in the lifter's unit and a long list ends "+2 more
sets"; free weight is named; VoiceOver hears units in full; a date is a date and never "ago",
"today", "yesterday" or "days"; the empty states count nothing and blame no one. From the
database: an open workout is never last time nor the last workout; warm-ups are excluded; one
movement on three machines is three entries, and two machines named alike are labelled apart,
numbered by machine id as the chart is; an archived machine keeps its name; most recently trained
first, each from its own last session, at most three; an overnight workout has no length.

`Date.FormatStyle` with `.weekday().day().month()` works in the swift:6.2 container (the test
asserts the parts, not the punctuation, because ICU's order varies by locale and version).

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing

@testable import HardsetCore

@Suite("The widget's file says what was done last, in the lifter's unit, and never counts days")
struct WidgetSnapshotTests {
  let t = Date(timeIntervalSince1970: 90_000_000)

  private func lastTime(sets: [(Double, Int)], machine: String? = "Hammer Strength Leg Press")
    -> WidgetSnapshot.LastTime
  {
    WidgetSnapshot.LastTime(
      exerciseID: ExerciseID(), machineID: machine == nil ? nil : MachineID(),
      exerciseName: "Leg Press", machineName: machine, performedAt: t,
      sets: sets.map { WidgetSnapshot.SetLine(weightKg: $0.0, reps: $0.1) })
  }

  private func snapshot(unit: WeightUnit = .kilograms) -> WidgetSnapshot {
    WidgetSnapshot(
      writtenAt: t, unit: unit,
      lastWorkout: .init(
        startedAt: t, finishedAt: t + 3_130, lengthSeconds: 3_130, workingSets: 18, volumeKg: 9_400,
        movementCount: 5),
      lastTimes: [lastTime(sets: [(100, 8), (100, 8), (95, 7)])])
  }

  private func temporaryFile() -> WidgetSnapshotFile {
    WidgetSnapshotFile(
      url: FileManager.default.temporaryDirectory
        .appendingPathComponent("hardset-widget-\(UUID().uuidString).json"))
  }

  @Test("Written and read back unchanged")
  func roundTrip() throws {
    let file = temporaryFile()
    let original = snapshot()
    try file.write(original)
    #expect(file.read() == .snapshot(original))
  }

  /// Review Focus: no file yet, a torn or corrupt file, a file from a newer build. Each is a calm
  /// state, never a crash and never someone else's numbers.
  @Test("No file is nothing yet; a corrupt or newer file is unreadable")
  func unreadableFileIsEmptyNotCrash() throws {
    #expect(temporaryFile().read() == .nothingYet)
    #expect(WidgetSnapshotFile.decode(Data("{\"version\":1,".utf8)) == .unreadable)
    #expect(WidgetSnapshotFile.decode(Data()) == .unreadable)
  }

  @Test("A file from a newer build is not half-understood")
  func newerVersionIsIgnored() throws {
    let newer = WidgetSnapshot(
      version: WidgetSnapshot.currentVersion + 1, writtenAt: t, unit: .kilograms, lastWorkout: nil,
      lastTimes: [])
    let data = try JSONEncoder().encode(newer)
    #expect(WidgetSnapshotFile.decode(data) == .unreadable)
  }

  @Test("No App Group container, no file")
  func noContainer() {
    #expect(WidgetSnapshotFile(containerURL: nil) == nil)
    let url = URL(fileURLWithPath: "/tmp/group")
    #expect(WidgetSnapshotFile(containerURL: url)?.url.lastPathComponent == "widget-snapshot.json")
  }

  @Test("Sets read in the lifter's unit, and a long list says how many more")
  func lines() {
    let five = lastTime(sets: [(100, 8), (100, 8), (95, 7), (95, 6), (90, 6)])
    let kg = WeightFormatter(unit: .kilograms, locale: Locale(identifier: "en_US_POSIX"))
    #expect(five.lines(formatter: kg, limit: 3) == ["100 kg × 8", "100 kg × 8", "95 kg × 7", "+2 more sets"])
    let lb = WeightFormatter(unit: .pounds, locale: Locale(identifier: "en_US_POSIX"))
    #expect(lastTime(sets: [(100, 8)]).lines(formatter: lb, limit: 3) == ["220.46 lb × 8"])
  }

  @Test("Free weight is named, and VoiceOver hears units in full")
  func spoken() {
    let free = lastTime(sets: [(60, 10)], machine: nil)
    #expect(free.equipmentText == "Free weight")
    let kg = WeightFormatter(unit: .kilograms, locale: Locale(identifier: "en_US_POSIX"))
    #expect(free.spokenSummary(formatter: kg) == "Leg Press on Free weight: 60 kilograms for 10 reps")
  }

  @Test("The last workout's totals and length")
  func lastWorkout() throws {
    let workout = try #require(snapshot().lastWorkout)
    let kg = WeightFormatter(unit: .kilograms, locale: Locale(identifier: "en_US_POSIX"))
    #expect(workout.totalsText(formatter: kg) == "18 sets · 9400 kg")
    #expect(workout.lengthText == "52:10")
    let unknown = WidgetSnapshot.LastWorkout(
      startedAt: t, finishedAt: t, lengthSeconds: nil, workingSets: 1, volumeKg: 100,
      movementCount: 1)
    #expect(unknown.lengthText == "Length unknown")
    #expect(unknown.totalsText(formatter: kg) == "1 set · 100 kg")
  }

  /// Spec 4.5: no "days since" counts. A relative date is one.
  @Test("Dates are dates, never days ago")
  func dayTextIsAbsolute() {
    let text = WidgetSnapshot.dayText(
      t, locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "UTC")!)
    // 90,000,000 s after 1970 is Tuesday 7 November 1972.
    #expect(text.contains("7"))
    #expect(text.contains("Nov"))
    #expect(text.contains("Tue"))
    for word in ["ago", "today", "yesterday", "days", "since"] {
      #expect(!text.lowercased().contains(word))
    }
  }

  @Test("The empty states are calm and count nothing")
  func copy() {
    for line in [WidgetCopy.nothingYet, WidgetCopy.unreadable] {
      for word in ["error", "failed", "streak", "days", "since"] {
        #expect(!line.lowercased().contains(word), "\(line)")
      }
    }
  }
}
```

```swift
import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

@Suite("The widget shows the last finished time on each machine, and nothing still being done")
struct WidgetSnapshotStoreTests {
  let now = Date(timeIntervalSince1970: 95_000_000)

  private struct Fixture {
    let db: any DatabaseWriter
    let logger: LoggerStore
    let gyms: GymStore
    let gym: GymID
    let exercises: [ExerciseID]
    let store: WidgetSnapshotStore
  }

  private func fixture() throws -> Fixture {
    var configuration = Configuration.forTesting()
    configuration.foreignKeysEnabled = true
    let db = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(db)
    try CatalogSeeder(database: db).seed(now: now)
    let exercises = try db.read { try Exercise.limit(4).fetchAll($0) }.map { ExerciseID(rawValue: $0.id) }
    let gyms = GymStore(database: db)
    let gym = try gyms.createGym(name: "Iron Temple", now: now)
    return Fixture(
      db: db, logger: LoggerStore(database: db), gyms: gyms, gym: gym, exercises: exercises,
      store: WidgetSnapshotStore(database: db))
  }

  /// One session at `start`, logging `sets` as (exercise, machine, kg, reps, warm-up), finished
  /// unless `open`.
  @discardableResult
  private func session(
    _ f: Fixture, at start: Date, open: Bool = false,
    _ sets: [(ExerciseID, MachineID?, Double, Int, Bool)]
  ) throws -> SessionID {
    let id = try f.logger.startSession(gymID: f.gym, at: start)
    for (index, set) in sets.enumerated() {
      try f.logger.logSet(
        sessionID: id, exerciseID: set.0, machineID: set.1,
        draft: SetEntryDraft(weightKg: set.2, reps: set.3), isWarmup: set.4,
        at: start.addingTimeInterval(Double(index + 1) * 90))
    }
    if !open { try f.logger.finishSession(id, at: start.addingTimeInterval(3_000)) }
    return id
  }

  @Test("With nothing finished, the snapshot is empty")
  func nothingYet() throws {
    let f = try fixture()
    let snapshot = try f.store.snapshot(unit: .kilograms, now: now)
    #expect(snapshot.lastWorkout == nil)
    #expect(snapshot.lastTimes.isEmpty)
    #expect(snapshot.unit == .kilograms)
    #expect(snapshot.version == WidgetSnapshot.currentVersion)
  }

  @Test("The last workout carries its totals and its honest length")
  func lastWorkoutTotals() throws {
    let f = try fixture()
    try session(f, at: now, [(f.exercises[0], nil, 60, 10, true), (f.exercises[0], nil, 100, 8, false),
      (f.exercises[0], nil, 100, 8, false)])
    let workout = try #require(try f.store.snapshot(unit: .pounds, now: now).lastWorkout)
    #expect(workout.workingSets == 2)
    #expect(workout.volumeKg == 1_600)
    #expect(workout.lengthSeconds == 3_000)
    #expect(workout.movementCount == 1)
  }

  /// Review Focus: the widget refreshes while a workout is open. Its half-done sets are not "last
  /// time", and it is not the last workout.
  @Test("An open workout is never last time, nor the last workout")
  func openWorkoutNeverLastTime() throws {
    let f = try fixture()
    let press = try f.gyms.createMachine(at: f.gym, name: "Leg Press", brand: "Hammer Strength", now: now)
    try session(f, at: now, [(f.exercises[0], press, 100, 8, false)])
    try session(f, at: now.addingTimeInterval(86_400), open: true,
      [(f.exercises[0], press, 120, 5, false), (f.exercises[1], nil, 40, 12, false)])

    let snapshot = try f.store.snapshot(unit: .kilograms, now: now.addingTimeInterval(90_000))
    #expect(snapshot.lastTimes.map(\.sets) == [[WidgetSnapshot.SetLine(weightKg: 100, reps: 8)]])
    #expect(snapshot.lastWorkout?.startedAt == now)
  }

  @Test("Warm-ups are not last time")
  func warmupsExcluded() throws {
    let f = try fixture()
    try session(f, at: now, [(f.exercises[0], nil, 40, 10, true), (f.exercises[0], nil, 100, 8, false)])
    let lastTime = try #require(try f.store.snapshot(unit: .kilograms, now: now).lastTimes.first)
    #expect(lastTime.sets == [WidgetSnapshot.SetLine(weightKg: 100, reps: 8)])
    #expect(lastTime.machineName == nil)
  }

  /// Review Focus: one movement on two machines, two of which share a name, are three entries,
  /// each with its own sets and a label of its own.
  @Test("Each machine keeps its own entry and its own label")
  func machinesStayApart() throws {
    let f = try fixture()
    let hammer = try f.gyms.createMachine(at: f.gym, name: "Leg Press", brand: "Hammer Strength", now: now)
    let plainA = try f.gyms.createMachine(at: f.gym, name: "Leg Press", now: now)
    let plainB = try f.gyms.createMachine(at: f.gym, name: "Leg Press", now: now)
    try session(f, at: now, [(f.exercises[0], hammer, 110, 8, false), (f.exercises[0], plainA, 90, 8, false),
      (f.exercises[0], plainB, 80, 8, false)])

    let lastTimes = try f.store.snapshot(unit: .kilograms, now: now).lastTimes
    #expect(lastTimes.count == 3)
    #expect(Set(lastTimes.map(\.machineID)) == [hammer, plainA, plainB])
    let labels = Set(lastTimes.compactMap(\.machineName))
    #expect(labels == ["Hammer Strength Leg Press", "Leg Press", "Leg Press (2)"])
    let hammerSets = lastTimes.first { $0.machineID == hammer }?.sets
    #expect(hammerSets == [WidgetSnapshot.SetLine(weightKg: 110, reps: 8)])
  }

  @Test("A machine archived since keeps its name")
  func archivedMachineStillNamed() throws {
    let f = try fixture()
    let press = try f.gyms.createMachine(at: f.gym, name: "Leg Press", brand: "Cybex", now: now)
    try session(f, at: now, [(f.exercises[0], press, 100, 8, false)])
    try f.gyms.archiveMachine(press)
    #expect(try f.store.snapshot(unit: .kilograms, now: now).lastTimes.first?.machineName == "Cybex Leg Press")
  }

  @Test("Most recently trained first, each from its own last session, at most three")
  func mostRecentFirstAndLimited() throws {
    let f = try fixture()
    try session(f, at: now, [(f.exercises[0], nil, 100, 8, false), (f.exercises[1], nil, 50, 10, false)])
    try session(f, at: now.addingTimeInterval(86_400),
      [(f.exercises[2], nil, 30, 12, false), (f.exercises[3], nil, 20, 15, false)])
    try session(f, at: now.addingTimeInterval(2 * 86_400), [(f.exercises[0], nil, 105, 6, false)])

    let lastTimes = try f.store.snapshot(unit: .kilograms, now: now).lastTimes
    #expect(lastTimes.map(\.exerciseID) == [f.exercises[0], f.exercises[3], f.exercises[2]])
    #expect(lastTimes.first?.sets == [WidgetSnapshot.SetLine(weightKg: 105, reps: 6)])
  }

  @Test("A workout left open overnight and finished has no length")
  func implausibleLengthUnknown() throws {
    let f = try fixture()
    let id = try f.logger.startSession(at: now)
    try f.logger.logSet(
      sessionID: id, exerciseID: f.exercises[0], draft: SetEntryDraft(weightKg: 60, reps: 10),
      at: now.addingTimeInterval(60))
    try f.logger.finishSession(id, at: now.addingTimeInterval(10 * 3_600))
    #expect(try f.store.snapshot(unit: .kilograms, now: now).lastWorkout?.lengthSeconds == nil)
  }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `Tools/linux-test.sh --filter 'WidgetSnapshotTests|WidgetSnapshotStoreTests'`
Expected: compile failure, `cannot find 'WidgetSnapshot' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// What the widgets show, written by the app into the App Group container.
///
/// The widget never opens the database: `SyncEngine`'s triggers call into the app process, so a
/// write from the widget would fail and a read could race a migration. The app writes this file
/// after launch and after each workout ends; the widget only reads it (`DECISIONS.md` §25).
///
/// Weights stay in kilograms with the lifter's unit beside them, so the widget formats with the
/// same `WeightFormatter` as every screen. Dates are instants; the widget shows them as dates,
/// never as "3 days ago" (spec 4.5: no "days since" counts).
public struct WidgetSnapshot: Codable, Hashable, Sendable {
  public static let currentVersion = 1
  /// Movements kept for "last time": what fits the medium widget.
  public static let lastTimeLimit = 3

  public struct LastWorkout: Codable, Hashable, Sendable {
    public let startedAt: Date
    public let finishedAt: Date
    /// Nil when the length is unknown (`DECISIONS.md` §21).
    public let lengthSeconds: Double?
    public let workingSets: Int
    public let volumeKg: Double
    public let movementCount: Int

    public init(
      startedAt: Date, finishedAt: Date, lengthSeconds: Double?, workingSets: Int, volumeKg: Double,
      movementCount: Int
    ) {
      self.startedAt = startedAt
      self.finishedAt = finishedAt
      self.lengthSeconds = lengthSeconds
      self.workingSets = workingSets
      self.volumeKg = volumeKg
      self.movementCount = movementCount
    }

    /// "18 sets · 9400 kg"
    public func totalsText(formatter: WeightFormatter) -> String {
      "\(CountText.sets(workingSets)) · \(formatter.total(kilograms: volumeKg))"
    }

    /// "52:10", or "Length unknown".
    public var lengthText: String {
      lengthSeconds.map { Duration.seconds($0).clockString } ?? "Length unknown"
    }
  }

  public struct SetLine: Codable, Hashable, Sendable {
    public let weightKg: Double
    public let reps: Int

    public init(weightKg: Double, reps: Int) {
      self.weightKg = weightKg
      self.reps = reps
    }
  }

  /// The last finished session on one movement and one machine.
  public struct LastTime: Codable, Hashable, Sendable, Identifiable {
    public let exerciseID: ExerciseID
    public let machineID: MachineID?
    public let exerciseName: String
    /// The machine's display name, numbered when two in the snapshot share one. Nil for free weight.
    public let machineName: String?
    public let performedAt: Date
    /// Working sets only, in the order they were done.
    public let sets: [SetLine]

    public init(
      exerciseID: ExerciseID, machineID: MachineID?, exerciseName: String, machineName: String?,
      performedAt: Date, sets: [SetLine]
    ) {
      self.exerciseID = exerciseID
      self.machineID = machineID
      self.exerciseName = exerciseName
      self.machineName = machineName
      self.performedAt = performedAt
      self.sets = sets
    }

    public var id: ProgressionKey { ProgressionKey(exerciseID: exerciseID, machineID: machineID) }

    /// "Free weight" rather than blank, as the chart names it.
    public var equipmentText: String { machineName ?? "Free weight" }

    /// "100 kg × 8" per set, at most `limit` of them, then "+2 more sets".
    public func lines(formatter: WeightFormatter, limit: Int) -> [String] {
      let shown = sets.prefix(max(0, limit)).map {
        "\(formatter.load(kilograms: $0.weightKg)) × \($0.reps)"
      }
      let hidden = sets.count - shown.count
      guard hidden > 0 else { return shown }
      return shown + ["+\(hidden) more \(hidden == 1 ? "set" : "sets")"]
    }

    /// For VoiceOver: "Leg Press on Hammer Strength Leg Press: 100 kilograms for 8 reps, …".
    public func spokenSummary(formatter: WeightFormatter) -> String {
      let sets = sets.map { "\(formatter.spoken(kilograms: $0.weightKg)) for \(CountText.reps($0.reps))" }
      return "\(exerciseName) on \(equipmentText): \(sets.joined(separator: ", "))"
    }
  }

  public let version: Int
  public let writtenAt: Date
  public let unit: WeightUnit
  public let lastWorkout: LastWorkout?
  /// Most recently trained first.
  public let lastTimes: [LastTime]

  public init(
    version: Int = WidgetSnapshot.currentVersion, writtenAt: Date, unit: WeightUnit,
    lastWorkout: LastWorkout?, lastTimes: [LastTime]
  ) {
    self.version = version
    self.writtenAt = writtenAt
    self.unit = unit
    self.lastWorkout = lastWorkout
    self.lastTimes = lastTimes
  }

  public var formatter: WeightFormatter { WeightFormatter(unit: unit) }

  /// "Tue 7 Oct" in the lifter's locale: a date, never a count of days.
  ///
  /// Takes no "now", so it cannot become relative.
  public static func dayText(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current)
    -> String
  {
    var style = Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, timeZone: timeZone)
    style = style.weekday(.abbreviated).day().month(.abbreviated)
    return date.formatted(style)
  }
}

/// What the widget found in the App Group container.
public enum WidgetSnapshotReading: Hashable, Sendable {
  case snapshot(WidgetSnapshot)
  /// No file yet: no workout has been finished on this device since install.
  case nothingYet
  /// A file that cannot be read, or one written by a newer build. Shown calmly, never as an error.
  case unreadable
}

/// The calm words a widget shows when it has nothing to show.
public enum WidgetCopy {
  public static let nothingYet = "Your last workout shows here once you finish one."
  public static let unreadable = "Open Hardset to bring this up to date."
  public static let lastTimeTitle = "Last time"
  public static let lastWorkoutTitle = "Last workout"
}

/// The snapshot file, written whole and atomically so the widget never reads half of one.
public struct WidgetSnapshotFile: Sendable {
  /// Also in both targets' entitlements (`com.apple.security.application-groups`).
  public static let appGroupIdentifier = "group.com.hardset.app"
  public static let fileName = "widget-snapshot.json"

  public let url: URL

  public init(url: URL) {
    self.url = url
  }

  /// `containerURL(forSecurityApplicationGroupIdentifier:)` is nil when the group is not in the
  /// entitlements; the file is then simply not written, and the widget says "nothing yet".
  public init?(containerURL: URL?) {
    guard let containerURL else { return nil }
    self.init(url: containerURL.appendingPathComponent(Self.fileName))
  }

  public func write(_ snapshot: WidgetSnapshot) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(snapshot).write(to: url, options: .atomic)
  }

  public func read() -> WidgetSnapshotReading {
    guard FileManager.default.fileExists(atPath: url.path) else { return .nothingYet }
    guard let data = try? Data(contentsOf: url) else { return .unreadable }
    return Self.decode(data)
  }

  public static func decode(_ data: Data) -> WidgetSnapshotReading {
    guard let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data),
      snapshot.version == WidgetSnapshot.currentVersion
    else { return .unreadable }
    return .snapshot(snapshot)
  }
}
```

```swift
import Foundation
import HardsetCore
import SQLiteData

/// Builds the widgets' snapshot from finished workouts only.
///
/// An open workout is still being done: its sets are not "last time" yet, and a half-finished
/// session is not the last workout. Warm-ups are not what a lifter means by last time either.
public nonisolated struct WidgetSnapshotStore {
  /// Finished sessions examined for "last time". Bounded, so years of history cost nothing.
  static let sessionWindow = 30

  private let database: any DatabaseWriter

  public init(database: any DatabaseWriter) {
    self.database = database
  }

  public func snapshot(unit: WeightUnit, now: Date = Date()) throws -> WidgetSnapshot {
    let last = try HistoryStore(database: database).recentSessions(limit: 1).first
    let lastWorkout = last.flatMap { summary -> WidgetSnapshot.LastWorkout? in
      guard let finishedAt = summary.timeline.finishedAt else { return nil }
      let length = summary.timeline.isImplausible ? nil : summary.timeline.duration
      return WidgetSnapshot.LastWorkout(
        startedAt: summary.timeline.startedAt, finishedAt: finishedAt,
        lengthSeconds: length.flatMap { $0 > .zero ? $0.seconds : nil },
        workingSets: summary.volume.workingSets, volumeKg: summary.volume.volumeKg,
        movementCount: summary.exerciseNames.count)
    }
    return WidgetSnapshot(
      writtenAt: now, unit: unit, lastWorkout: lastWorkout, lastTimes: try lastTimes())
  }

  /// The most recently trained movements-on-machines, each with its own last finished session.
  private func lastTimes() throws -> [WidgetSnapshot.LastTime] {
    try database.read { db in
      let sessions = try Session
        .where { $0.finishedAt.isNot(nil) }
        .order { $0.startedAt.desc() }
        .limit(Self.sessionWindow)
        .fetchAll(db)
      guard !sessions.isEmpty else { return [] }
      let sets = try LoggedSet
        .where { $0.sessionID.in(sessions.map(\.id)) }
        .where { !$0.isWarmup }
        .fetchAll(db)

      // Newest set first decides which key was trained most recently, and in which session.
      var order: [ProgressionKey] = []
      var latestSession: [ProgressionKey: UUID] = [:]
      for set in sets.sorted(by: { $0.completedAt > $1.completedAt }) {
        let key = ProgressionKey(
          exerciseID: ExerciseID(rawValue: set.exerciseID),
          machineID: set.machineID.map(MachineID.init(rawValue:)))
        if latestSession[key] == nil {
          latestSession[key] = set.sessionID
          order.append(key)
        }
      }
      let keys = Array(order.prefix(WidgetSnapshot.lastTimeLimit))
      guard !keys.isEmpty else { return [] }

      let exerciseIDs = Array(Set(keys.map(\.exerciseID.rawValue)))
      let names = try Exercise.where { $0.id.in(exerciseIDs) }.fetchAll(db)
        .reduce(into: [UUID: String]()) { $0[$1.id] = $1.name }
      let machineIDs = Array(Set(keys.compactMap(\.machineID?.rawValue)))
      let machines =
        machineIDs.isEmpty
        ? [:]
        : try Machine.where { $0.id.in(machineIDs) }.fetchAll(db)
          .reduce(into: [MachineID: String]()) {
            $0[MachineID(rawValue: $1.id)] = MachineRecord(row: $1).displayName
          }
      let labels = Self.distinctLabels(for: keys, names: machines)

      return keys.map { key in
        let own = sets
          .filter {
            $0.sessionID == latestSession[key] && $0.exerciseID == key.exerciseID.rawValue
              && $0.machineID == key.machineID?.rawValue
          }
          .sorted { ($0.completedAt, $0.setOrdinal) < ($1.completedAt, $1.setOrdinal) }
        return WidgetSnapshot.LastTime(
          exerciseID: key.exerciseID, machineID: key.machineID,
          exerciseName: names[key.exerciseID.rawValue] ?? "Unknown movement",
          machineName: labels[key], performedAt: own.last?.completedAt ?? .distantPast,
          sets: own.map { WidgetSnapshot.SetLine(weightKg: $0.weightKg, reps: $0.reps) })
      }
    }
  }

  /// Machine names, numbered when two in the snapshot share one, so the widget never shows two
  /// machines as if they were one (`DECISIONS.md` §20). Numbered by machine id, as the chart is,
  /// so a label does not change with habits.
  static func distinctLabels(
    for keys: [ProgressionKey], names: [MachineID: String]
  ) -> [ProgressionKey: String] {
    let machineKeys = keys.filter { $0.machineID != nil }
    let byName = Dictionary(grouping: machineKeys) { names[$0.machineID!] ?? "Unnamed machine" }
    var labels: [ProgressionKey: String] = [:]
    for (name, group) in byName {
      // Same machine, different movements, share a label; only different machines are numbered.
      let machines = Array(Set(group.compactMap(\.machineID))).sorted {
        $0.rawValue.uuidString < $1.rawValue.uuidString
      }
      for key in group {
        let index = machines.firstIndex(of: key.machineID!) ?? 0
        labels[key] = index == 0 ? name : "\(name) (\(index + 1))"
      }
    }
    return labels
  }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `Tools/linux-test.sh --filter 'WidgetSnapshotTests|WidgetSnapshotStoreTests'`, then
`Tools/linux-test.sh`.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/HardsetKit/Sources/HardsetCore/WidgetSnapshot.swift \
  Packages/HardsetKit/Sources/HardsetStore/WidgetSnapshotStore.swift \
  Packages/HardsetKit/Tests/HardsetCoreTests/WidgetSnapshotTests.swift \
  Packages/HardsetKit/Tests/HardsetStoreTests/WidgetSnapshotStoreTests.swift
git commit -m "feat(store): a file the widgets can read without touching the database

SyncEngine's triggers live in the app process, so the widget must never open the
database (DECISIONS 25). The app writes what the widgets show: the last workout
and the last finished time on each machine, working sets only, each machine
apart and named, in the lifter's unit, with dates rather than days-since. A file
that is missing, torn or newer is a calm empty state.

Co-Authored-By: <your model's trailer>"
```

---

### Task 7: Two feature tips (Core)

**Files:**
- Create: `Packages/HardsetKit/Sources/HardsetCore/FeatureTips.swift`
- Test: `Packages/HardsetKit/Tests/HardsetCoreTests/FeatureTipsTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces, for Task 14:
  - `public enum FeatureTip: String, CaseIterable` — `.machineChip`, `.movementHistory`, each with
    `title`, `message`, `symbolName`
  - `public struct FeatureTipFacts: Hashable, Sendable` (`sessionHasGym`, `hasMovementOnScreen`,
    `movementWithHistoryOnScreen`, `isEnteringNumbers`)
  - `public enum FeatureTipPlan` with `static func isEligible(_: FeatureTip, facts: FeatureTipFacts) -> Bool`

Rules (each a test): exactly two tips with distinct glyphs; each names its control; no tip
contains a coaching word (should, try, aim, goal, target, push, beat, improve, progress, more,
harder, heavier, record, streak, must, need); nothing shows while numbers are being typed; the
machine tip needs a gym and a movement (a chip to point at); the history tip needs history.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing

@testable import HardsetCore

@Suite("Two tips that point at features, and never a word of coaching")
struct FeatureTipsTests {
  private func facts(
    gym: Bool = true, movement: Bool = true, history: Bool = true, typing: Bool = false
  ) -> FeatureTipFacts {
    FeatureTipFacts(
      sessionHasGym: gym, hasMovementOnScreen: movement, movementWithHistoryOnScreen: history,
      isEnteringNumbers: typing)
  }

  @Test("There are exactly two, each with its own glyph")
  func two() {
    #expect(FeatureTip.allCases == [.machineChip, .movementHistory])
    #expect(Set(FeatureTip.allCases.map(\.symbolName)).count == 2)
  }

  @Test("Each names the control it points at")
  func pointsAtAControl() {
    #expect(FeatureTip.machineChip.message.contains("machine chip"))
    #expect(FeatureTip.movementHistory.message.contains("name"))
  }

  /// `HANDOFF.md` §6: no targets, no coaching. A tip is the easiest place for one to creep in.
  @Test("Nothing in a tip tells the lifter what to do with their training")
  func neverCoaching() {
    let refused: Set<String> = [
      "should", "try", "aim", "goal", "goals", "target", "targets", "push", "beat", "improve",
      "progress", "more", "harder", "heavier", "record", "streak", "must", "need",
    ]
    for tip in FeatureTip.allCases {
      for line in [tip.title, tip.message] {
        let words = line.lowercased().split { !$0.isLetter }.map(String.init)
        #expect(refused.isDisjoint(with: words), "\(line)")
      }
    }
  }

  @Test("Nothing covers the keypad")
  func notWhileTyping() {
    for tip in FeatureTip.allCases {
      #expect(!FeatureTipPlan.isEligible(tip, facts: facts(typing: true)))
    }
  }

  @Test("The machine tip needs a chip to point at")
  func machineTipNeedsAChip() {
    #expect(FeatureTipPlan.isEligible(.machineChip, facts: facts()))
    #expect(!FeatureTipPlan.isEligible(.machineChip, facts: facts(gym: false)))
    #expect(!FeatureTipPlan.isEligible(.machineChip, facts: facts(movement: false)))
  }

  @Test("The history tip needs history to open")
  func historyTipNeedsHistory() {
    #expect(FeatureTipPlan.isEligible(.movementHistory, facts: facts()))
    #expect(!FeatureTipPlan.isEligible(.movementHistory, facts: facts(history: false)))
  }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `Tools/linux-test.sh --filter FeatureTipsTests`
Expected: compile failure, `cannot find 'FeatureTip' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// The two things worth pointing out, once, and nothing else (spec 4.7).
///
/// Each names a control and what it does. None says what to lift, how much, or how often: a tip
/// that coaches is a target in disguise (`HANDOFF.md` §6), and a test holds the copy to that.
public enum FeatureTip: String, CaseIterable, Hashable, Sendable {
  /// The machine chip on a movement: loads are kept per machine.
  case machineChip
  /// A movement's name: it opens that movement's load history.
  case movementHistory

  public var title: String {
    switch self {
    case .machineChip: "Which machine?"
    case .movementHistory: "Its history"
    }
  }

  public var message: String {
    switch self {
    case .machineChip:
      "Tap the machine chip to pick the one you're on. Loads are kept per machine."
    case .movementHistory:
      "Tap a movement's name to see every load you've logged on it, machine by machine."
    }
  }

  public var symbolName: String {
    switch self {
    case .machineChip: "dumbbell"
    case .movementHistory: "chart.xyaxis.line"
    }
  }
}

/// What the live workout shows right now, as far as tips are concerned.
public struct FeatureTipFacts: Hashable, Sendable {
  /// A machine chip exists only when the workout has a gym.
  public var sessionHasGym: Bool
  public var hasMovementOnScreen: Bool
  /// A movement on screen has history to open.
  public var movementWithHistoryOnScreen: Bool
  /// The keypad is up. Nothing may cover the numbers being typed.
  public var isEnteringNumbers: Bool

  public init(
    sessionHasGym: Bool, hasMovementOnScreen: Bool, movementWithHistoryOnScreen: Bool,
    isEnteringNumbers: Bool
  ) {
    self.sessionHasGym = sessionHasGym
    self.hasMovementOnScreen = hasMovementOnScreen
    self.movementWithHistoryOnScreen = movementWithHistoryOnScreen
    self.isEnteringNumbers = isEnteringNumbers
  }
}

/// When a tip may appear. TipKit then shows each at most once, ends it when the feature is used,
/// and shows no more than one a day (`Tips.configure([.displayFrequency(.daily)])`).
public enum FeatureTipPlan {
  public static func isEligible(_ tip: FeatureTip, facts: FeatureTipFacts) -> Bool {
    guard !facts.isEnteringNumbers else { return false }
    switch tip {
    case .machineChip: return facts.sessionHasGym && facts.hasMovementOnScreen
    case .movementHistory: return facts.movementWithHistoryOnScreen
    }
  }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `Tools/linux-test.sh --filter FeatureTipsTests`, then `Tools/linux-test.sh`.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/HardsetKit/Sources/HardsetCore/FeatureTips.swift \
  Packages/HardsetKit/Tests/HardsetCoreTests/FeatureTipsTests.swift
git commit -m "feat(core): two tips that point at features, and never coach

The machine chip and a movement's history are the two things a new lifter may
not find. Each tip names its control and what it does, a test refuses any word
that would tell the lifter what to lift, and neither may cover the keypad.

Co-Authored-By: <your model's trailer>"
```

---

### Task 8: Launch colour and privacy manifests, pinned (resources)

The app and widget targets cannot build here, but their plists, manifests and colour sets are
files. This task fixes spec 4.8 and the manifest half of 4.5, and puts every claim those files
make under a test that runs on Linux and on the Mac.

**Files:**
- Create: `Hardset/Assets.xcassets/LaunchBackground.colorset/Contents.json`
- Modify: `Hardset/Info.plist` (the `UILaunchScreen` dict, line 27)
- Modify: `Hardset/PrivacyInfo.xcprivacy` (the CA92.1 comment only)
- Create: `HardsetWidget/PrivacyInfo.xcprivacy`
- Modify: `Tools/linux-test.sh` (the `podman run` lines)
- Modify: `Tools/generate_project.py` (`RESOURCES`, `group_children`); regenerate
  `Hardset.xcodeproj/project.pbxproj`
- Test: `Packages/HardsetKit/Tests/HardsetCoreTests/AppResourcesTests.swift`
- Modify: `docs/MAC-VERIFICATION.md`

**Interfaces:**
- Consumes: `Palette.backgroundLight`, `Palette.backgroundDark`, `PaletteColor`; `DECISIONS.md` §25.
- Produces, for Tasks 12 and 13: `AppResourcesTests` with the helpers `root`, `data(_:)` and
  `plist(_:)`, to which those tasks add one test each; the checkout mounted at `/repo` by
  `Tools/linux-test.sh`.

**Read and cite first** (checked 2026-10-11):
- https://developer.apple.com/documentation/bundleresources/information-property-list/uilaunchscreen/uicolorname
  (iOS 14): "If you don't set a color, the system uses a default of systemBackground".

Why the script changes: the container mounted only `Packages/HardsetKit`, so the app's files were
invisible to tests. It now mounts the checkout at `/repo` and works in
`/repo/Packages/HardsetKit`, so `#filePath` finds `Hardset/` exactly as it does on the Mac. The
`.build-linux` cache stays in the same host directory; SwiftPM rebuilds it once because the path
inside the container changed.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing

@testable import HardsetCore

/// The app target's resource files, checked where a test can read them.
///
/// The app and widget targets cannot be built here, but their plists, manifests and colour sets
/// are plain files. `Tools/linux-test.sh` mounts the whole checkout, so these run on Linux as
/// well as on the Mac.
@Suite("The app's launch colour, manifests and plists say what the code does")
struct AppResourcesTests {
  /// The checkout root: `Tests/HardsetCoreTests/<file>` → `Packages/HardsetKit` → the repo.
  static let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()

  private func data(_ path: String) throws -> Data {
    try Data(contentsOf: Self.root.appendingPathComponent(path))
  }

  private func plist(_ path: String) throws -> [String: Any] {
    let object = try PropertyListSerialization.propertyList(from: data(path), format: nil)
    return try #require(object as? [String: Any], "\(path) is not a dictionary plist")
  }

  private func components(_ entry: [String: Any]) throws -> PaletteColor {
    let color = try #require(entry["color"] as? [String: Any])
    let parts = try #require(color["components"] as? [String: String])
    func value(_ key: String) throws -> Double { try #require(parts[key].flatMap(Double.init)) }
    return PaletteColor(red: try value("red"), green: try value("green"), blue: try value("blue"))
  }

  private func close(_ a: PaletteColor, _ b: PaletteColor) -> Bool {
    abs(a.red - b.red) < 0.002 && abs(a.green - b.green) < 0.002 && abs(a.blue - b.blue) < 0.002
  }

  @Test("The launch screen is the app's background, light and dark")
  func launchBackgroundMatchesPalette() throws {
    let object = try JSONSerialization.jsonObject(
      with: data("Hardset/Assets.xcassets/LaunchBackground.colorset/Contents.json"))
    let colors = try #require((object as? [String: Any])?["colors"] as? [[String: Any]])
    let light = try #require(colors.first { $0["appearances"] == nil })
    let dark = try #require(colors.first { $0["appearances"] != nil })
    #expect(close(try components(light), Palette.backgroundLight))
    #expect(close(try components(dark), Palette.backgroundDark))
    let info = try plist("Hardset/Info.plist")
    let launch = try #require(info["UILaunchScreen"] as? [String: Any])
    #expect(launch["UIColorName"] as? String == "LaunchBackground")
  }

  @Test("The app declares its own defaults only, tracks nothing, collects nothing")
  func appManifest() throws {
    let manifest = try plist("Hardset/PrivacyInfo.xcprivacy")
    #expect(manifest["NSPrivacyTracking"] as? Bool == false)
    #expect((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty == true)
    let accessed = try #require(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
    #expect(accessed.count == 1)
    #expect(accessed.first?["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults")
    #expect(accessed.first?["NSPrivacyAccessedAPITypeReasons"] as? [String] == ["CA92.1"])
  }

  @Test("The widget has its own manifest, and it declares nothing it does not do")
  func widgetManifest() throws {
    let manifest = try plist("HardsetWidget/PrivacyInfo.xcprivacy")
    #expect(manifest["NSPrivacyTracking"] as? Bool == false)
    #expect((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty == true)
    #expect((manifest["NSPrivacyAccessedAPITypes"] as? [Any])?.isEmpty == true)
  }

  /// `DECISIONS.md` §25. 1C8F.1 is undeclared because no shared suite exists. Adding one without
  /// declaring it in both manifests is how an upload gets rejected, so this test fails first.
  @Test("No code opens a shared UserDefaults suite")
  func noSharedDefaultsSuite() throws {
    let folders = ["Hardset", "HardsetWidget", "HardsetIntents", "Packages/HardsetKit/Sources"]
    var offenders: [String] = []
    for folder in folders {
      let url = Self.root.appendingPathComponent(folder)
      guard let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
      else { continue }
      for case let file as URL in files where file.pathExtension == "swift" {
        let text = try String(contentsOf: file, encoding: .utf8)
        if text.contains("UserDefaults(suiteName:") { offenders.append(file.lastPathComponent) }
      }
    }
    #expect(offenders.isEmpty, "declare 1C8F.1 in both privacy manifests first: \(offenders)")
  }
}
```

Change `Tools/linux-test.sh`'s run so the tests can see the files:

```bash
# The whole checkout is mounted, not only the package: `AppResourcesTests` reads the app's and
# the widget's plists, manifests and colour sets, which live outside it. Mounted at /repo so
# `#filePath` finds them the same way it does on the Mac.
#
# `.build-linux`, not `.build`: a Mac checkout of the same tree must never pick up Linux
# artefacts from a shared cache directory.
podman run --rm \
  -v "$ROOT:/repo:Z" -w /repo/Packages/HardsetKit \
  "$IMAGE" \
  swift test --scratch-path /repo/Packages/HardsetKit/.build-linux "$@"
```

(The `Package.resolved` snapshot-and-restore above it is unchanged: the file is the same file.)

- [ ] **Step 2: Run to verify failure**

Run: `Tools/linux-test.sh --filter AppResourcesTests`
Expected: FAIL in `launchBackgroundMatchesPalette` (no such colour set) and `widgetManifest` (no
such file). `appManifest` and `noSharedDefaultsSuite` already pass: they pin what is true today.

- [ ] **Step 3: Implement**

`Hardset/Assets.xcassets/LaunchBackground.colorset/Contents.json` (0xF2F2F7 light; the palette's
dark 0.055/0.055/0.063):

```json
{
  "colors" : [
    {
      "color" : { "color-space" : "srgb", "components" : { "red" : "0.949", "green" : "0.949", "blue" : "0.969", "alpha" : "1.000" } },
      "idiom" : "universal"
    },
    {
      "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],
      "color" : { "color-space" : "srgb", "components" : { "red" : "0.055", "green" : "0.055", "blue" : "0.063", "alpha" : "1.000" } },
      "idiom" : "universal"
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

`Hardset/Info.plist`, replacing the empty `UILaunchScreen` dict:

```xml
	<!-- The launch screen is the app's own background, light and dark, so the first frame does
	     not flash the system background before Tokens.Color.background (Palette.background*)
	     replaces it. AppResourcesTests holds the colour set to the palette. -->
	<key>UILaunchScreen</key>
	<dict>
		<key>UIColorName</key>
		<string>LaunchBackground</string>
	</dict>
```

`Hardset/PrivacyInfo.xcprivacy`, replacing the comment inside the CA92.1 entry (the declaration
itself is unchanged):

```xml
			<!-- UserDefaults, for this app's own preferences only.
			     CA92.1 is the correct reason: access limited to information written by the app
			     itself. The app-group reason 1C8F.1 is NOT declared because nothing reads
			     UserDefaults(suiteName:): the widget receives the rest timer through AlarmKit's
			     AlarmAttributes and everything else through a JSON file in the App Group
			     container (DECISIONS.md §25), not through a shared defaults suite. If that ever
			     changes, ADD 1C8F.1 alongside CA92.1 (do not replace it) here and in
			     HardsetWidget/PrivacyInfo.xcprivacy. AppResourcesTests fails until you do. -->
```

`HardsetWidget/PrivacyInfo.xcprivacy`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<!-- The widget extension's own manifest: extensions are scanned separately from the app.
	     It tracks nothing and collects nothing; it reads one JSON file the app wrote into the App
	     Group container (DECISIONS.md §25) and renders the rest timer AlarmKit hands it.

	     No required-reason API is declared because none is called: no UserDefaults (the snapshot
	     is a file, not a shared suite), and no file timestamps (the snapshot carries its own
	     writtenAt, so the file's dates are never read). If either changes, declare it here:
	     1C8F.1 for a shared suite, C617.1 for timestamps of files in the App Group container. -->
	<key>NSPrivacyTracking</key>
	<false/>
	<key>NSPrivacyTrackingDomains</key>
	<array/>
	<key>NSPrivacyCollectedDataTypes</key>
	<array/>
	<key>NSPrivacyAccessedAPITypes</key>
	<array/>
</dict>
</plist>
```

`Tools/generate_project.py`: the widget's manifest is a resource of the widget target.

```python
RESOURCES = [
    ("PrivacyInfo.xcprivacy", "Hardset", APP),
    ("Assets.xcassets", "Hardset", APP),
    # Extensions are scanned separately, so the widget carries its own manifest.
    ("PrivacyInfo.xcprivacy", "HardsetWidget", WIDGET),
]
```

```python
    "HardsetWidget": ["HardsetWidgetBundle.swift", "Info.plist", "PrivacyInfo.xcprivacy"],
```

Regenerate, twice:

```bash
python3 Tools/generate_project.py && cp Hardset.xcodeproj/project.pbxproj /tmp/pbx.1 \
  && python3 Tools/generate_project.py && cmp Hardset.xcodeproj/project.pbxproj /tmp/pbx.1 \
  && git diff --stat Hardset.xcodeproj
```

Expected: `cmp` silent; the diff is four added lines (a `PBXBuildFile`, a `PBXFileReference`, the
group child and the widget's Resources phase entry), nothing removed. The colour set needs no
generator change: it is inside `Assets.xcassets`, already a resource.

Ledger, under `## Phase 4`:

```markdown
- [ ] (feat(app): launch in the app's own colour; a manifest for the widget) The `Hardset` scheme
      builds and archives. In the built `Hardset.app`, `PlugIns/HardsetWidget.appex/PrivacyInfo.xcprivacy`
      exists, and `PrivacyInfo.xcprivacy` is at the app bundle's root (DEVICE-CHECKLIST §D).
  - [ ] Cold-launch in light and in dark mode (kill the app first): the launch screen is the
        same grey as the first screen, with no white or black flash before it.
  - [ ] Xcode › Product › Archive › Generate Privacy Report: the app lists UserDefaults CA92.1
        only; the widget lists nothing.
```

- [ ] **Step 4: Run to verify pass**

Run: `Tools/linux-test.sh --filter AppResourcesTests`, then `Tools/linux-test.sh`.
Expected: PASS, and the full suite still passes under the new mount.

- [ ] **Step 5: Commit**

```bash
git add Hardset/Assets.xcassets/LaunchBackground.colorset/Contents.json Hardset/Info.plist \
  Hardset/PrivacyInfo.xcprivacy HardsetWidget/PrivacyInfo.xcprivacy Tools/linux-test.sh \
  Tools/generate_project.py Hardset.xcodeproj/project.pbxproj \
  Packages/HardsetKit/Tests/HardsetCoreTests/AppResourcesTests.swift docs/MAC-VERIFICATION.md
git commit -m "feat(app): launch in the app's own colour; a manifest for the widget

An empty UILaunchScreen falls back to systemBackground, which is not the grey the
first screen draws. The launch colour is now the palette's background, and a test
holds it there. The widget gets the manifest extensions need, declaring nothing
because it calls no required-reason API, and a test fails the day anything opens
a shared defaults suite without declaring 1C8F.1. The Linux harness now mounts
the checkout so those files are testable here.

https://developer.apple.com/documentation/bundleresources/information-property-list/uilaunchscreen/uicolorname

Co-Authored-By: <your model's trailer>"
```

---

### Task 9: The Lock Screen rest, crafted; pause, resume, skip and start as intents (Mac-only)

**Precondition:** Tasks 2, 3 and 8 are merged (Task 8 last touched the generator).

**Files:**
- Modify: `Packages/HardsetKit/Sources/HardsetAlarm/RestTimerController.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetAlarm/RestAlarmService.swift` (two comments only)
- Create: `HardsetIntents/RestIntents.swift` (app **and** widget targets)
- Create: `HardsetIntents/IntentDependencies.swift` (app target)
- Modify: `HardsetWidget/HardsetWidgetBundle.swift` (`RestTimerLiveActivity`, line 23 onward)
- Modify: `Hardset/HardsetApp.swift` (`init()`, one construction and one registration)
- Modify: `Tools/generate_project.py`; regenerate `Hardset.xcodeproj/project.pbxproj`
- Modify: `docs/MAC-VERIFICATION.md`, `DEVICE-CHECKLIST.md` (§B)

**Interfaces:**
- Consumes: `RestActivityContent` (Task 2); `RestCommand`, `RestCommandOutcome`, `RestCommandPlan`,
  `RestRequest` (Task 3).
- Produces, for Tasks 10 and 11:
  - `RestTimerController.start(duration: Duration, metadata: RestMetadata?, now: Date = .now)`
  - `RestTimerController.metadata: RestMetadata?` (now `public private(set)`)
  - `RestTimerController.perform(_ command: RestCommand, now: Date = .now) async -> RestCommandOutcome`
  - `RestTimerController.settle() async`
  - `struct StartRestIntent: LiveActivityIntent` with `init()` and `init(seconds: Double)`;
    `PauseRestIntent`, `ResumeRestIntent`, `StopRestIntent` (all `LiveActivityIntent`, `init()`)
  - `@MainActor func restReply(_: RestCommand, on: RestTimerController) async -> IntentDialog`
  - `enum IntentDependencies { @MainActor static func register(restTimer:) }`

**Read and cite first** (checked 2026-10-11):
- https://developer.apple.com/documentation/appintents/liveactivityintent (iOS 17): "the system
  launches your app process without opening the app, performs the intent".
- https://developer.apple.com/documentation/appintents/appdependencymanager (iOS 16),
  `add(key:dependency:)`; https://developer.apple.com/documentation/appintents/appdependency
  (`@propertyWrapper final class AppDependency<Value> where Value : Sendable`).
- https://developer.apple.com/documentation/appintents/intentparameter, the Measurements
  initialisers (`IntentParameter-Measurements`, `defaultUnit:`, `supportsNegativeNumbers:`,
  `requestValueDialog:`).
- https://developer.apple.com/documentation/appintents/intentdialog (`init(_:)`) and
  `IntentResult.result(dialog:)`.
- https://developer.apple.com/documentation/swiftui/progressview/init(timerinterval:countsdown:label:currentvaluelabel:)
  (iOS 16): takes a `ClosedRange<Date>`.
- https://developer.apple.com/documentation/alarmkit/alarmpresentationstate/mode-swift.enum/countdown
  (iOS 26): `totalCountdownDuration`, `previouslyElapsedDuration`, `startDate`, `fireDate`.
- `Button(intent:label:)` (SwiftUI, iOS 17) and `AppIntent.isDiscoverable` (iOS 16).

Changes:

1. **`RestTimerController`.**
   - `private var metadata: RestMetadata?` (line 62) becomes:

     ```swift
     /// What the running rest is for, as whoever started it said. Nil for a rest started from Siri
     /// or a control, which no set started, and for one adopted from AlarmKit after a relaunch.
     public private(set) var metadata: RestMetadata?
     ```

   - `start(duration:metadata:now:)` (line 78) takes `metadata: RestMetadata?`. The body is
     unchanged; `RestAlarmService.Request` already takes an optional, and the fallback body already
     maps it. The one caller (`HardsetApp.swift`'s `RestTimerHooks.start`) passes a non-optional,
     which still compiles.
   - Add, after `cancel()`:

     ```swift
     /// Carries out a rest command from outside the app: the Lock Screen, Siri, a control.
     ///
     /// Reconciles first: an intent can launch the app in the background, where no view has run
     /// `reconcile()` and this controller still reads idle. Then waits for AlarmKit to catch up,
     /// because the system may suspend the app as soon as `perform()` returns, and a debounced
     /// commit left pending would leave a rest written down with no alarm behind it.
     public func perform(_ command: RestCommand, now: Date = .now) async -> RestCommandOutcome {
       await reconcile(now: now)
       let outcome = RestCommandPlan.outcome(for: command, state: state, now: now)
       guard case .perform(let action) = outcome else { return outcome }
       switch action {
       case .start(let duration): start(duration: duration, metadata: nil, now: now)
       case .pause: pause(now: now)
       case .resume: resume(now: now)
       case .stop: cancel()
       }
       await settle()
       return outcome
     }

     /// Returns once no AlarmKit commit is pending. Bounded: each round waits out the commit that
     /// was current when it began, and a commit only replaces itself when the lifter acts again.
     public func settle() async {
       for _ in 0..<4 {
         guard let task = commitTask else { return }
         await task.value
       }
     }
     ```

2. **`RestAlarmService`.** In `schedule(_:)`, the two comments that say "Phase 4.1 brings Lock
   Screen pause back…" and "(a Phase 4.1 intent, too)" now say: Lock Screen pause, resume and skip
   are `LiveActivityIntent`s drawn by the widget (`HardsetIntents/RestIntents.swift`), which run
   in the app, so the app pauses its own alarm and keeps the remainder; the paused presentation's
   `resumeButton` stays only because the initialiser requires it. No code changes.

3. **`HardsetIntents/RestIntents.swift`** (new folder at the repo root, beside `Hardset/`):

   ```swift
   import AppIntents
   import Foundation
   import HardsetAlarm
   import HardsetCore

   // Compiled into the app AND the widget extension (Tools/generate_project.py). The Live
   // Activity's buttons and the Rest control name these types from the widget, and a
   // `LiveActivityIntent` is performed in the app's process, launched in the background if need
   // be, so `RestTimerController` is the app's own. None of them logs anything (DECISIONS.md §26).

   /// Carries out a command and says what happened, in Core's words.
   @MainActor
   func restReply(_ command: RestCommand, on timer: RestTimerController) async -> IntentDialog {
     switch await timer.perform(command) {
     case .perform(let done):
       IntentDialog(LocalizedStringResource(stringLiteral: RestCommandPlan.confirmation(for: done)))
     case .nothing(let why):
       IntentDialog(LocalizedStringResource(stringLiteral: why))
     }
   }

   /// "Start a rest" from Siri, Shortcuts, the Action button or the Rest control. The length is
   /// required and has no default: Siri asks for it.
   struct StartRestIntent: LiveActivityIntent {
     static let title: LocalizedStringResource = "Start a rest"
     static let description = IntentDescription(
       "Starts a rest timer of the length you say. It logs nothing.")

     @Parameter(
       title: "Length", defaultUnit: .minutes, supportsNegativeNumbers: false,
       requestValueDialog: IntentDialog("How long a rest?"))
     var length: Measurement<UnitDuration>

     @AppDependency private var restTimer: RestTimerController

     init() {}

     /// For the Rest control, which already knows its configured length.
     init(seconds: Double) {
       self.length = Measurement(value: seconds, unit: .seconds)
     }

     @MainActor
     func perform() async throws -> some IntentResult & ProvidesDialog {
       switch RestRequest.duration(seconds: length.converted(to: .seconds).value) {
       case .failure:
         return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: RestRequest.refusal)))
       case .success(let rest):
         return .result(dialog: await restReply(.start(rest), on: restTimer))
       }
     }
   }

   /// "Skip my rest": the Lock Screen's Skip, and a Siri phrase (Task 10).
   struct StopRestIntent: LiveActivityIntent {
     static let title: LocalizedStringResource = "Skip the rest"
     static let description = IntentDescription("Ends the rest timer now.")
     @AppDependency private var restTimer: RestTimerController
     init() {}

     @MainActor
     func perform() async throws -> some IntentResult & ProvidesDialog {
       .result(dialog: await restReply(.stop, on: restTimer))
     }
   }

   /// The Lock Screen's Pause. Not offered to Siri or Shortcuts.
   struct PauseRestIntent: LiveActivityIntent {
     static let title: LocalizedStringResource = "Pause the rest"
     static let isDiscoverable = false
     @AppDependency private var restTimer: RestTimerController
     init() {}

     @MainActor
     func perform() async throws -> some IntentResult & ProvidesDialog {
       .result(dialog: await restReply(.pause, on: restTimer))
     }
   }

   /// The Lock Screen's Resume. Not offered to Siri or Shortcuts.
   struct ResumeRestIntent: LiveActivityIntent {
     static let title: LocalizedStringResource = "Resume the rest"
     static let isDiscoverable = false
     @AppDependency private var restTimer: RestTimerController
     init() {}

     @MainActor
     func perform() async throws -> some IntentResult & ProvidesDialog {
       .result(dialog: await restReply(.resume, on: restTimer))
     }
   }
   ```

4. **`HardsetIntents/IntentDependencies.swift`** (app target only):

   ```swift
   import AppIntents
   import HardsetAlarm

   /// Hands the app's live objects to its App Intents.
   ///
   /// A file of its own so `HardsetApp.swift` need not import AppIntents: that file's
   /// `@Dependency(\.defaultDatabase)` is swift-dependencies' (through SQLiteData), and AppIntents
   /// brings a dependency property wrapper of its own.
   enum IntentDependencies {
     /// Called from `HardsetApp.init()`, which runs on every launch, including the background
     /// launch a Lock Screen button causes, before any intent is performed.
     @MainActor
     static func register(restTimer: RestTimerController) {
       AppDependencyManager.shared.add(dependency: restTimer)
     }
   }
   ```

5. **`HardsetApp.init()`.** Replace the `_restTimer = State(initialValue: …)` statement with:

   ```swift
   let timer = RestTimerController(persistence: database.map { RestTimerStore(database: $0) })
   _restTimer = State(initialValue: timer)
   // Before any intent can run: a Lock Screen button can launch the app in the background, and
   // its intent asks for this controller.
   IntentDependencies.register(restTimer: timer)
   ```

   Add one sentence to the type's doc comment: it also registers the rest timer for App Intents.

6. **The Live Activity** (`HardsetWidgetBundle.swift`). Replace `RestTimerLiveActivity` and its
   `countdown(for:)` with the following; keep the bundle and its doc comment.

   ```swift
   extension RestActivityContent {
     /// AlarmKit's state into Core's mirror. A mode a future SDK adds is shown as finished, which
     /// offers no button that could act on a rest this build does not understand.
     static func make(_ state: AlarmPresentationState, metadata: RestMetadata?) -> RestActivityContent {
       let mode: Mode
       switch state.mode {
       case .countdown(let countdown):
         mode = .countdown(
           total: countdown.totalCountdownDuration,
           previouslyElapsed: countdown.previouslyElapsedDuration,
           startDate: countdown.startDate, fireDate: countdown.fireDate)
       case .paused(let paused):
         mode = .paused(
           total: paused.totalCountdownDuration, previouslyElapsed: paused.previouslyElapsedDuration)
       case .alert:
         mode = .alerting
       @unknown default:
         mode = .alerting
       }
       return make(mode: mode, metadata: metadata)
     }
   }

   struct RestTimerLiveActivity: Widget {
     var body: some WidgetConfiguration {
       ActivityConfiguration(for: AlarmAttributes<RestMetadata>.self) { context in
         RestLockScreenView(
           content: .make(context.state, metadata: context.attributes.metadata)
         )
         .activityBackgroundTint(nil)
       } dynamicIsland: { context in
         let content = RestActivityContent.make(context.state, metadata: context.attributes.metadata)
         return DynamicIsland {
           DynamicIslandExpandedRegion(.leading) {
             RestRing(phase: content.phase).frame(width: 44, height: 44)
           }
           DynamicIslandExpandedRegion(.center) {
             RestTitle(content: content)
           }
           DynamicIslandExpandedRegion(.trailing) {
             RestClock(phase: content.phase).font(Tokens.Text.readout)
           }
           DynamicIslandExpandedRegion(.bottom) {
             RestControls(controls: content.controls)
           }
         } compactLeading: {
           RestRing(phase: content.phase).frame(width: 20, height: 20)
         } compactTrailing: {
           RestClock(phase: content.phase).monospacedDigit().frame(maxWidth: 52)
         } minimal: {
           RestRing(phase: content.phase)
         }
       }
     }
   }

   /// The ring. System-animated from the range, so nothing here ticks.
   struct RestRing: View {
     let phase: RestActivityContent.Phase

     var body: some View {
       Group {
         switch phase {
         case .counting(let range):
           ProgressView(timerInterval: range, countsDown: true) {
             EmptyView()
           } currentValueLabel: {
             EmptyView()
           }
         case .paused(_, let fractionRemaining):
           ProgressView(value: fractionRemaining)
         case .finished:
           Image(systemName: "checkmark.circle.fill")
         }
       }
       .progressViewStyle(.circular)
       .tint(Tokens.Color.accent)
       .accessibilityHidden(true)
     }
   }

   /// The countdown. `Text(timerInterval:)` is system-rendered from the same range as the ring.
   struct RestClock: View {
     let phase: RestActivityContent.Phase

     var body: some View {
       switch phase {
       case .counting(let range): Text(timerInterval: range, countsDown: true)
       case .paused(let remaining, _): Text(remaining.clockString)
       case .finished: Text("Done")
       }
     }
   }

   struct RestTitle: View {
     let content: RestActivityContent

     var body: some View {
       VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
         Text(content.title).font(.headline).lineLimit(1)
         if let detail = content.detail {
           Text(detail).font(Tokens.Text.caption).foregroundStyle(.secondary).lineLimit(1)
         }
         if let status = content.statusText {
           Text(status).font(Tokens.Text.caption)
         }
       }
     }
   }

   /// Pause, Resume and Skip, each a `LiveActivityIntent` performed in the app.
   struct RestControls: View {
     let controls: [RestActivityContent.Control]

     var body: some View {
       HStack(spacing: Tokens.Spacing.regular) {
         ForEach(controls, id: \.self) { control in
           button(for: control)
             .buttonStyle(.bordered)
             .tint(Tokens.Color.accent)
             .accessibilityLabel(control.spokenLabel)
         }
       }
     }

     @ViewBuilder private func button(for control: RestActivityContent.Control) -> some View {
       let label = Label(control.title, systemImage: control.symbolName)
         .frame(minWidth: Tokens.minimumTapTarget, minHeight: Tokens.minimumTapTarget)
       switch control {
       case .pause: Button(intent: PauseRestIntent()) { label }
       case .resume: Button(intent: ResumeRestIntent()) { label }
       case .stop: Button(intent: StopRestIntent()) { label }
       }
     }
   }

   struct RestLockScreenView: View {
     let content: RestActivityContent

     var body: some View {
       VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
         HStack(spacing: Tokens.Spacing.regular) {
           RestRing(phase: content.phase).frame(width: 44, height: 44)
           RestTitle(content: content)
           Spacer(minLength: 0)
           RestClock(phase: content.phase).font(Tokens.Text.readout).monospacedDigit()
         }
         if !content.controls.isEmpty {
           RestControls(controls: content.controls)
         }
       }
       .padding(Tokens.Spacing.loose)
     }
   }
   ```

   `import AppIntents` joins the file's imports (for `Button(intent:)`).

7. **Generator.** `SOURCES` gains, after `AppSmokeTests.swift`:

   ```python
       # App Intents the widget's buttons and controls name. Each is compiled into both targets;
       # `LiveActivityIntent` and foreground intents still run in the app's process.
       ("RestIntents.swift", "HardsetIntents", APP),
       ("RestIntents.swift", "HardsetIntents", WIDGET),
       ("IntentDependencies.swift", "HardsetIntents", APP),
   ```

   The root group's loop becomes `for g in ("Hardset", "HardsetWidget", "HardsetIntents", "HardsetTests"):`,
   and `group_children` gains
   `"HardsetIntents": ["RestIntents.swift", "IntentDependencies.swift"],`. The widget target already
   links `HardsetAlarm` and `HardsetCore` (`PRODUCTS[WIDGET]`). Regenerate twice; the second run
   changes nothing.

Check: `rg -n 'Date\.now\.\.\.' HardsetWidget` returns nothing.

Ledger, under `## Phase 4`:

```markdown
- [ ] (feat(widget): the rest on the Lock Screen, with pause, resume and skip that run in the app)
      The `Hardset` scheme builds (app and widget) with no new warnings, and HardsetAlarm builds
      for iOS. Written without a compiler; look first at:
  - [ ] `@AppDependency private var restTimer: RestTimerController` resolves. If not, use the
        spelling in Apple's samples, `@Dependency`; neither file imports SQLiteData, so there is
        no clash there.
  - [ ] `AppDependencyManager.shared.add(dependency: restTimer)` resolves to the autoclosure
        overload with `key` defaulted; if `key:` has no default, pass `key: nil`.
  - [ ] `@Parameter(title:defaultUnit:supportsNegativeNumbers:requestValueDialog:)` on
        `Measurement<UnitDuration>` resolves; if not, drop `supportsNegativeNumbers:` (Core refuses
        negatives anyway) and note the overload that did.
  - [ ] `@MainActor func perform()` satisfies `AppIntent` in a target whose default isolation is
        MainActor, in both the app and the widget, with no isolated-conformance diagnostic.
  - [ ] `RestControls.button(for:)`: three `Button(intent:)` branches in a `switch` inside
        `@ViewBuilder` build. `ProgressView(timerInterval:…)` with `.progressViewStyle(.circular)`
        animates in a Live Activity; if it is drawn static or linear, drop the circular style.
  - [ ] SF Symbols exist: `pause.fill`, `play.fill`, `forward.end.fill`, `checkmark.circle.fill`.
  Then on device (DEVICE-CHECKLIST §B):
  - [ ] Every Lock Screen and Dynamic Island check added to §B there.
  - Known residual: after ±15 s or a resume the ring starts again from the new alarm's length
    (reading 3). Record whether it reads as wrong in use.
```

`DEVICE-CHECKLIST.md` §B, after "Pause / resume":

```markdown
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
```

Commit, citing the URLs above, with a message that says the Lock Screen can pause, resume and skip
again, now through intents the app performs itself, so it never loses the remainder, and the
widget can no longer trap on a range drawn after the deadline.

---

### Task 10: Start a workout from Siri, Spotlight and the Action button (Mac-only)

**Precondition:** Tasks 3 and 9 are merged, and Phase 2 **Task 19** and Phase 3 **Tasks 16–19**
are merged (this task edits the split root: `HardsetRootView.swift`, `LiveSessionAccessory.swift`,
and `LiveSessionScreen.swift`). Read those files at the tip first; the symbol names below are the
ones those tasks produce (`selectedTab`, `RootTab.train`, `coordinator`, `resumeError`,
`showsFirstRun`, `startEmptyWorkout()`, the first-run `onStart`).

**Files:**
- Create: `HardsetIntents/WorkoutIntents.swift` (app **and** widget targets)
- Create: `HardsetIntents/HardsetShortcuts.swift` (app target)
- Modify: `HardsetIntents/IntentDependencies.swift`
- Modify: `Hardset/HardsetApp.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetFeature/HardsetRootView.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetFeature/LiveSessionScreen.swift` (`RestTimerHooks`,
  and the `restMetadata:` argument)
- Modify: `Packages/HardsetKit/Sources/HardsetFeature/LiveSessionAccessory.swift` (the
  `RestBarView(metadata:)` argument)
- Modify: `Tools/generate_project.py`; regenerate `Hardset.xcodeproj/project.pbxproj`
- Modify: `docs/MAC-VERIFICATION.md`, `DEVICE-CHECKLIST.md` (new §E)

**Interfaces:**
- Consumes: `SystemRequestInbox`, `SystemRequest`, `StartWorkoutPolicy`, `WorkoutLaunchState`,
  `StartWorkoutAction` (Task 3); `StartRestIntent`, `StopRestIntent`, `IntentDependencies`,
  `RestTimerController.metadata` (Task 9).
- Produces, for Task 11:
  - `struct StartWorkoutIntent: AppIntent` (`supportedModes = .foreground`) and
    `struct OpenHardsetIntent: AppIntent` (not discoverable), both `init()`
  - `IntentDependencies.register(restTimer:systemRequests:)` (replaces `register(restTimer:)`)
  - `HardsetRootView(…, systemRequests: SystemRequestInbox = SystemRequestInbox())`
  - `RestTimerHooks.metadata: () -> RestMetadata?`, defaulting to `{ nil }`

**Read and cite first** (checked 2026-10-11):
- https://developer.apple.com/documentation/appintents/appintent/supportedmodes (iOS 26.0) and
  https://developer.apple.com/documentation/appintents/intentmodes (`foreground`, `background`,
  `foreground(_:)` with `.immediate`, `.dynamic`, `.deferred`).
- https://developer.apple.com/documentation/appintents/appintent/openappwhenrun: deprecated, "use
  supportedModes instead", and an error "if the app intent runs in an app extension". Not used.
- https://developer.apple.com/documentation/appintents/appshortcutsprovider and
  https://developer.apple.com/documentation/appintents/appshortcut (iOS 16).
- https://developer.apple.com/documentation/appintents/openurlintent: universal links only, which
  is why the request goes through the inbox (reading 6).

Changes:

1. **`HardsetIntents/WorkoutIntents.swift`:**

   ```swift
   import AppIntents
   import HardsetCore

   /// "Start a workout": opens Hardset and starts an empty one, or shows the one already open
   /// (`StartWorkoutPolicy`). It never logs anything (DECISIONS.md §26).
   ///
   /// Compiled into the widget too, for the Control Center button (Task 11). `.foreground` makes
   /// the system bring the app forward and perform it there, so the inbox is the app's.
   struct StartWorkoutIntent: AppIntent {
     static let title: LocalizedStringResource = "Start a workout"
     static let description = IntentDescription(
       "Opens Hardset and starts an empty workout. If one is already open, it shows that one.")
     static let supportedModes: IntentModes = .foreground

     @AppDependency private var systemRequests: SystemRequestInbox

     init() {}

     @MainActor
     func perform() async throws -> some IntentResult {
       systemRequests.post(.startWorkout)
       return .result()
     }
   }

   /// Opens Hardset and does nothing else: the Rest control's action until a length is chosen.
   struct OpenHardsetIntent: AppIntent {
     static let title: LocalizedStringResource = "Open Hardset"
     static let isDiscoverable = false
     static let supportedModes: IntentModes = .foreground

     init() {}

     func perform() async throws -> some IntentResult { .result() }
   }
   ```

2. **`HardsetIntents/HardsetShortcuts.swift`** (app target only: the system reads App Shortcuts
   from the app bundle; they appear in Spotlight and Shortcuts, and in Settings › Action Button ›
   Shortcut, with no further work):

   ```swift
   import AppIntents

   /// Phrases for Siri, and the entries Spotlight and the Action button list. A workout and a
   /// rest, started and ended; nothing that logs (DECISIONS.md §26). Every phrase names the app,
   /// as App Shortcuts require.
   struct HardsetShortcuts: AppShortcutsProvider {
     static var appShortcuts: [AppShortcut] {
       AppShortcut(
         intent: StartWorkoutIntent(),
         phrases: [
           "Start a workout in \(.applicationName)",
           "Begin a workout in \(.applicationName)",
         ],
         shortTitle: "Start workout",
         systemImageName: "figure.strengthtraining.traditional")
       AppShortcut(
         intent: StartRestIntent(),
         phrases: [
           "Start a rest in \(.applicationName)",
           "Rest in \(.applicationName)",
         ],
         shortTitle: "Start rest",
         systemImageName: "timer")
       AppShortcut(
         intent: StopRestIntent(),
         phrases: [
           "Skip my rest in \(.applicationName)",
           "End my rest in \(.applicationName)",
         ],
         shortTitle: "Skip rest",
         systemImageName: "forward.end")
     }
   }
   ```

3. **`IntentDependencies`.** Replace `register(restTimer:)` with:

   ```swift
   @MainActor
   static func register(restTimer: RestTimerController, systemRequests: SystemRequestInbox) {
     AppDependencyManager.shared.add(dependency: restTimer)
     AppDependencyManager.shared.add(dependency: systemRequests)
   }
   ```

   and add `import HardsetCore`.

4. **`HardsetApp.swift`.**
   - Add `@State private var systemRequests: SystemRequestInbox`, documented: "Where a Start
     workout request from Siri or Control Center waits for the root view. Built in `init()` so the
     intent and the view share one."
   - In `init()`: `let requests = SystemRequestInbox()`, `_systemRequests = State(initialValue: requests)`,
     and the registration becomes
     `IntentDependencies.register(restTimer: timer, systemRequests: requests)`.
   - `RootView` gains `let systemRequests: SystemRequestInbox`, passed from `body`, and passes
     `systemRequests: systemRequests` to `HardsetRootView`.
   - In the `RestTimerHooks(…)` call, add `metadata: { restTimer.metadata },`.

5. **`RestTimerHooks`** (in `LiveSessionScreen.swift`). Add, with its init parameter defaulting to
   `{ nil }`:

   ```swift
   /// What the running rest is for, as the timer was told. Nil for a rest no set started (Siri, a
   /// control), so the bar never captions such a rest with an older set.
   public var metadata: () -> RestMetadata?
   ```

   Then every `restMetadata:` / `metadata:` argument that passes `coordinator.activeRest` to
   `SessionView` or `RestBarView` passes `hooks.metadata()` instead. Check:
   `rg -n 'activeRest' Packages/HardsetKit/Sources/HardsetFeature` returns nothing. (In-app rests
   are unchanged: the coordinator starts every one with the same metadata it used to keep.)

6. **`HardsetRootView`.**
   - Add `private let systemRequests: SystemRequestInbox`, an init parameter
     `systemRequests: SystemRequestInbox = SystemRequestInbox()` after `restPreferences`, and
     `@State private var launchReadDone = false`.
   - At the end of the launch `.task`, after the resume and the first-run decision:
     `launchReadDone = true` then `handleSystemRequest()`.
   - On the outermost view: `.onChange(of: systemRequests.pending) { handleSystemRequest() }`.
   - At the end of the first-run `onStart` success path: `handleSystemRequest()`.
   - Add:

     ```swift
     /// A Start workout request from Siri, Spotlight, the Action button or Control Center.
     /// `StartWorkoutPolicy` decides; a request it says to wait on stays in the inbox until the
     /// launch read has run or the first-run screen is done.
     private func handleSystemRequest() {
       guard systemRequests.pending == .startWorkout else { return }
       let state = WorkoutLaunchState(
         isReady: launchReadDone, hasOpenWorkout: coordinator != nil,
         resumeFailed: resumeError != nil, showsFirstRun: showsFirstRun)
       switch StartWorkoutPolicy.action(for: state) {
       case .wait:
         return
       case .startEmptyWorkout:
         _ = systemRequests.take()
         selectedTab = .train
         startEmptyWorkout()
       case .showOpenWorkout, .showResumeFailure:
         _ = systemRequests.take()
         selectedTab = .train
       }
     }
     ```

7. **Generator.** `SOURCES` gains
   `("WorkoutIntents.swift", "HardsetIntents", APP)`, `("WorkoutIntents.swift", "HardsetIntents", WIDGET)`
   and `("HardsetShortcuts.swift", "HardsetIntents", APP)`; `group_children["HardsetIntents"]` gains
   `"WorkoutIntents.swift", "HardsetShortcuts.swift"`. Regenerate twice; the second run changes
   nothing.

Ledger, under `## Phase 4`:

```markdown
- [ ] (feat(app): start a workout or a rest by voice, from Spotlight or the Action button) The
      `Hardset` scheme builds (app and widget), HardsetFeature builds for macOS 15 via `./test.sh`,
      and `AppSmokeTests` passes. Written without a compiler; look first at
      `static let supportedModes: IntentModes = .foreground` (if `IntentModes` wants a call, use
      `.foreground(.immediate)`), `AppShortcut(intent:phrases:shortTitle:systemImageName:)`, and
      `.onChange(of: systemRequests.pending)` (zero-argument closure form, iOS 17).
  - [ ] Shortcuts app › Hardset lists Start workout, Start rest and Skip rest, and no Pause, Resume
        or Open Hardset. No action anywhere takes a weight or reps.
  - [ ] Settings › Action Button › Shortcut › Hardset offers the same three.
  - [ ] Spotlight: typing "Hardset" shows Start workout.
  - [ ] Every check added to DEVICE-CHECKLIST §E.
```

`DEVICE-CHECKLIST.md`, a new section after §D:

```markdown
## E. System surfaces — Siri, Spotlight, the Action button, Control Center, widgets

- [ ] **Siri, cold.** Force-quit Hardset. "Hey Siri, start a workout in Hardset": the app opens on
      Train with an empty workout. Say it again: the same workout is shown, not a second one.
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
```

Commit, citing the URLs above, with a message that says a workout can be started from Siri,
Spotlight and the Action button without ever starting a second one, and that no phrase can log a
set.

---

### Task 11: Control Center controls (Mac-only)

**Precondition:** Tasks 3, 9 and 10 are merged.

**Files:**
- Create: `HardsetWidget/HardsetControls.swift`
- Modify: `HardsetWidget/HardsetWidgetBundle.swift` (`HardsetWidgetBundle.body`)
- Modify: `Tools/generate_project.py`; regenerate `Hardset.xcodeproj/project.pbxproj`
- Modify: `docs/MAC-VERIFICATION.md`, `DEVICE-CHECKLIST.md` (§E)

**Interfaces:**
- Consumes: `RestControlState` (Task 3); `StartRestIntent(seconds:)` (Task 9);
  `StartWorkoutIntent`, `OpenHardsetIntent` (Task 10).
- Produces: `StartWorkoutControl` and `RestControl` (`ControlWidget`), and
  `RestControlConfiguration: ControlConfigurationIntent` with `length: Measurement<UnitDuration>?`.

**Read and cite first** (checked 2026-10-11):
- https://developer.apple.com/documentation/widgetkit/controlwidgetbutton (iOS 18; macOS 26, so
  it stays in the iOS-only widget extension)
- https://developer.apple.com/documentation/widgetkit/appintentcontrolconfiguration (iOS 18)
- https://developer.apple.com/documentation/appintents/controlconfigurationintent (iOS 18): "The
  parameters of your intent define all of the configuration options for your control."
- `ControlWidgetConfiguration.promptsForUserConfiguration()` (iOS 18). Its doc JSON did not load on
  2026-10-11; confirm the name in the SDK before building (ledger).

Changes:

1. **`HardsetWidget/HardsetControls.swift`:**

   ```swift
   import AppIntents
   import HardsetCore
   import SwiftUI
   import WidgetKit

   /// Start workout, in Control Center, on the Lock Screen or the Action button. Opens Hardset,
   /// which starts an empty workout or shows the open one (`StartWorkoutPolicy`).
   struct StartWorkoutControl: ControlWidget {
     static let kind = "com.hardset.app.control.start-workout"

     var body: some ControlWidgetConfiguration {
       StaticControlConfiguration(kind: Self.kind) {
         ControlWidgetButton(action: StartWorkoutIntent()) {
           Label("Start workout", systemImage: "figure.strengthtraining.traditional")
         }
       }
       .displayName("Start workout")
       .description("Opens Hardset and starts an empty workout.")
     }
   }

   /// The length the lifter picks when adding the Rest control. Optional, with no default: a rest
   /// exists only once someone chooses it (`HANDOFF.md` §6).
   struct RestControlConfiguration: ControlConfigurationIntent {
     static let title: LocalizedStringResource = "Rest"

     @Parameter(title: "Length", defaultUnit: .minutes, supportsNegativeNumbers: false)
     var length: Measurement<UnitDuration>?

     init() {}
   }

   /// A rest of the configured length, started without opening the app. Until a valid length is
   /// chosen it reads "Rest · Choose" and opens Hardset instead (`RestControlState`).
   struct RestControl: ControlWidget {
     static let kind = "com.hardset.app.control.rest"

     var body: some ControlWidgetConfiguration {
       AppIntentControlConfiguration(kind: Self.kind, intent: RestControlConfiguration.self) {
         configuration in
         let state = RestControlState.make(
           configuredSeconds: configuration.length?.converted(to: .seconds).value)
         if case .ready(let rest) = state {
           ControlWidgetButton(action: StartRestIntent(seconds: rest.seconds)) {
             Label(state.title, systemImage: "timer")
           }
         } else {
           ControlWidgetButton(action: OpenHardsetIntent()) {
             Label(state.title, systemImage: "timer")
           }
         }
       }
       .displayName("Rest")
       .description("Starts a rest of the length you choose. It logs nothing.")
       .promptsForUserConfiguration()
     }
   }
   ```

2. **`HardsetWidgetBundle.body`:**

   ```swift
   var body: some Widget {
     RestTimerLiveActivity()
     StartWorkoutControl()
     RestControl()
   }
   ```

   Update the bundle's doc comment: the extension also carries the two controls.

3. **Generator.** `SOURCES` gains `("HardsetControls.swift", "HardsetWidget", WIDGET)`;
   `group_children["HardsetWidget"]` gains `"HardsetControls.swift"` after
   `"HardsetWidgetBundle.swift"`. Regenerate twice; the second run changes nothing.

Ledger, under `## Phase 4`:

```markdown
- [ ] (feat(widget): Start workout and Rest in Control Center) The widget extension builds.
      Written without a compiler; look first at `promptsForUserConfiguration()` (name and
      placement), `if case … else` inside the control template builder (if the builder rejects
      it, move the two branches into a `@ControlWidgetTemplateBuilder` helper `button(for:)` and
      record which form built), and `StaticControlConfiguration(kind:)`.
  - [ ] Every check added to DEVICE-CHECKLIST §E for controls.
```

`DEVICE-CHECKLIST.md` §E, appended:

```markdown
- [ ] **Start workout control.** Add it to Control Center. Tap it with no workout open: Hardset
      opens with an empty workout. Tap it again: the same workout.
- [ ] **Rest control, configured.** Add Rest; the system asks for a length; choose 2 minutes. The
      control reads "Rest · 2:00". Tap it from the Lock Screen's Control Center: a 2:00 rest starts
      without opening the app, and its Lock Screen activity is titled "Rest".
- [ ] **Rest control, not configured.** Add Rest and dismiss the length prompt. The control reads
      "Rest · Choose"; tapping it opens Hardset and starts nothing.
- [ ] **Rest control after a force-quit.** Force-quit Hardset, tap the configured control: the
      rest starts, and opening Hardset shows the same countdown.
```

Commit, citing the URLs above, with a message that says Control Center can start a workout and a
rest of the length the lifter chose, and that an unconfigured control starts nothing.

---

### Task 12: Widgets — last time on a machine, and the last workout (Mac-only)

**Precondition:** Tasks 6, 8 and 11 are merged (11 last touched the bundle and the generator).

**Files:**
- Create: `HardsetWidget/HistoryWidgets.swift`
- Create: `HardsetWidget/HardsetWidget.entitlements`
- Modify: `HardsetWidget/HardsetWidgetBundle.swift` (`body`)
- Modify: `Hardset/Hardset.entitlements`
- Create: `Packages/HardsetKit/Sources/HardsetFeature/WidgetSnapshotWriter.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetFeature/HardsetEnvironment.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetFeature/HardsetRootView.swift`
- Modify: `Packages/HardsetKit/Tests/HardsetCoreTests/AppResourcesTests.swift` (one test)
- Modify: `Tools/generate_project.py`; regenerate `Hardset.xcodeproj/project.pbxproj`
- Modify: `docs/MAC-VERIFICATION.md`, `DEVICE-CHECKLIST.md` (§E)

**Interfaces:**
- Consumes: `WidgetSnapshot`, `WidgetSnapshotFile`, `WidgetSnapshotReading`, `WidgetCopy`,
  `WidgetSnapshotStore` (Task 6); `AppResourcesTests.plist(_:)` (Task 8).
- Produces: `LastTimeWidget`, `LastWorkoutWidget`; `HardsetEnvironment.widgetSnapshots:
  WidgetSnapshotStore`; `struct WidgetSnapshotWriter` with `refresh(unit:)`.

**Read and cite first** (checked 2026-10-11):
- https://developer.apple.com/documentation/foundation/filemanager/containerurl(forsecurityapplicationgroupidentifier:)
  (iOS 7): "In iOS, the value is nil when the group identifier is invalid."
- https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.application-groups
- https://developer.apple.com/documentation/widgetkit/widgetcenter/reloadalltimelines() (iOS 14)

Changes:

1. **Entitlements.** `HardsetWidget/HardsetWidget.entitlements`:

   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
   	<!-- The one container the app writes the widget snapshot into (DECISIONS.md §25). The widget
   	     only reads it, and never opens the database. -->
   	<key>com.apple.security.application-groups</key>
   	<array>
   		<string>group.com.hardset.app</string>
   	</array>
   </dict>
   </plist>
   ```

   `Hardset/Hardset.entitlements`, after `aps-environment`:

   ```xml
   	<!-- Shared with the widget extension, for the snapshot file only (DECISIONS.md §25). -->
   	<key>com.apple.security.application-groups</key>
   	<array>
   		<string>group.com.hardset.app</string>
   	</array>
   ```

   Both need the App Group registered for the team (Developer Program, `HANDOFF.md` §11.2).

2. **`AppResourcesTests`**, one test inside the suite, after `noSharedDefaultsSuite`. It runs on
   Linux: `Tools/linux-test.sh --filter AppResourcesTests` must fail before the entitlements change
   (no `com.apple.security.application-groups` key) and pass after.

   ```swift
     /// Task 12. The app writes and the widget reads one file, so both must name the same group.
     @Test("App and widget share the one App Group the snapshot lives in")
     func appGroup() throws {
       for path in ["Hardset/Hardset.entitlements", "HardsetWidget/HardsetWidget.entitlements"] {
         let groups = try plist(path)["com.apple.security.application-groups"] as? [String]
         #expect(groups == [WidgetSnapshotFile.appGroupIdentifier], "\(path)")
       }
     }
   ```

3. **`HardsetFeature/WidgetSnapshotWriter.swift`:**

   ```swift
   import Foundation
   import HardsetCore
   import HardsetStore
   #if os(iOS)
     import WidgetKit
   #endif

   /// Writes the widgets' file and asks WidgetKit to redraw (`DECISIONS.md` §25).
   ///
   /// A failure is not shown: a widget one workout behind is not worth interrupting a lifter
   /// over, and it still shows its last file or "nothing yet". It is not swallowed silently either:
   /// a debug build stops on it.
   @MainActor
   struct WidgetSnapshotWriter {
     let store: WidgetSnapshotStore

     func refresh(unit: WeightUnit) {
       #if os(iOS)
         let container = FileManager.default.containerURL(
           forSecurityApplicationGroupIdentifier: WidgetSnapshotFile.appGroupIdentifier)
         guard let file = WidgetSnapshotFile(containerURL: container) else { return }
         do {
           try file.write(store.snapshot(unit: unit))
           WidgetCenter.shared.reloadAllTimelines()
         } catch {
           assertionFailure("The widget snapshot was not written: \(error)")
         }
       #endif
     }
   }
   ```

4. **`HardsetEnvironment`:** `public let widgetSnapshots: WidgetSnapshotStore`, set in `init` as
   `WidgetSnapshotStore(database: database)`.

5. **`HardsetRootView`:** `private var widgetWriter: WidgetSnapshotWriter { WidgetSnapshotWriter(store: environment.widgetSnapshots) }`,
   and `widgetWriter.refresh(unit: unit)`:
   - at the end of the launch `.task` (after Task 10's `handleSystemRequest()`), so a session that
     arrived by sync or an update is reflected;
   - in the `LiveSessionScreen` `onFinished` closure, for both `.finished` and `.discarded`;
   - in `.onChange(of: useImperial) { widgetWriter.refresh(unit: unit) }`.

6. **`HardsetWidget/HistoryWidgets.swift`:**

   ```swift
   import HardsetCore
   import HardsetUI
   import SwiftUI
   import WidgetKit

   struct SnapshotEntry: TimelineEntry {
     let date: Date
     let reading: WidgetSnapshotReading
   }

   /// Reads the app's file and nothing else: never the database (`DECISIONS.md` §25). One entry and
   /// no schedule, because the app reloads the timelines whenever it writes.
   struct SnapshotProvider: TimelineProvider {
     func placeholder(in context: Context) -> SnapshotEntry {
       SnapshotEntry(date: .now, reading: .nothingYet)
     }

     func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
       completion(entry())
     }

     func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
       completion(Timeline(entries: [entry()], policy: .never))
     }

     private func entry() -> SnapshotEntry {
       let container = FileManager.default.containerURL(
         forSecurityApplicationGroupIdentifier: WidgetSnapshotFile.appGroupIdentifier)
       return SnapshotEntry(
         date: .now, reading: WidgetSnapshotFile(containerURL: container)?.read() ?? .nothingYet)
     }
   }

   /// Shown for "nothing yet" and "unreadable": calm, counting nothing.
   struct SnapshotEmptyView: View {
     let reading: WidgetSnapshotReading

     var body: some View {
       Text(reading == .unreadable ? WidgetCopy.unreadable : WidgetCopy.nothingYet)
         .font(Tokens.Text.caption)
         .foregroundStyle(.secondary)
     }
   }

   /// The last finished time on the machines used most recently: one in the small widget and on
   /// the Lock Screen, three in the medium. Dates are dates (`WidgetSnapshot.dayText`).
   struct LastTimeWidget: Widget {
     static let kind = "com.hardset.app.widget.last-time"

     var body: some WidgetConfiguration {
       StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
         LastTimeView(reading: entry.reading)
           .containerBackground(Tokens.Color.surface, for: .widget)
       }
       .configurationDisplayName("Last time")
       .description("What you lifted last time on the machines you used most recently.")
       .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
     }
   }

   struct LastTimeView: View {
     let reading: WidgetSnapshotReading
     @Environment(\.widgetFamily) private var family

     var body: some View {
       if case .snapshot(let snapshot) = reading, !snapshot.lastTimes.isEmpty {
         let shown = family == .systemMedium ? snapshot.lastTimes : Array(snapshot.lastTimes.prefix(1))
         HStack(alignment: .top, spacing: Tokens.Spacing.regular) {
           ForEach(shown) { lastTime in
             LastTimeColumn(
               lastTime: lastTime, formatter: snapshot.formatter,
               lineLimit: family == .accessoryRectangular ? 2 : 3)
           }
         }
       } else {
         SnapshotEmptyView(reading: reading)
       }
     }
   }

   struct LastTimeColumn: View {
     let lastTime: WidgetSnapshot.LastTime
     let formatter: WeightFormatter
     let lineLimit: Int

     var body: some View {
       VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
         Text(lastTime.exerciseName).font(.headline).lineLimit(1)
         Text(lastTime.equipmentText).font(Tokens.Text.caption).foregroundStyle(.secondary).lineLimit(1)
         ForEach(lastTime.lines(formatter: formatter, limit: lineLimit), id: \.self) { line in
           Text(line).font(Tokens.Text.caption).monospacedDigit()
         }
         Text(WidgetSnapshot.dayText(lastTime.performedAt))
           .font(Tokens.Text.caption).foregroundStyle(.secondary)
       }
       .frame(maxWidth: .infinity, alignment: .leading)
       .accessibilityElement(children: .ignore)
       .accessibilityLabel(
         "\(WidgetCopy.lastTimeTitle), \(WidgetSnapshot.dayText(lastTime.performedAt)). "
           + lastTime.spokenSummary(formatter: formatter))
     }
   }

   /// The last finished workout: when, how many working sets, the volume, and its length or
   /// "Length unknown". No comparison and no count of days since.
   struct LastWorkoutWidget: Widget {
     static let kind = "com.hardset.app.widget.last-workout"

     var body: some WidgetConfiguration {
       StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
         LastWorkoutView(reading: entry.reading)
           .containerBackground(Tokens.Color.surface, for: .widget)
       }
       .configurationDisplayName("Last workout")
       .description("Your last finished workout, as it was saved.")
       .supportedFamilies([.systemSmall, .accessoryRectangular])
     }
   }

   struct LastWorkoutView: View {
     let reading: WidgetSnapshotReading

     var body: some View {
       if case .snapshot(let snapshot) = reading, let workout = snapshot.lastWorkout {
         VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
           Text(WidgetCopy.lastWorkoutTitle).font(Tokens.Text.caption).foregroundStyle(.secondary)
           Text(WidgetSnapshot.dayText(workout.finishedAt)).font(.headline)
           Text(workout.totalsText(formatter: snapshot.formatter)).font(Tokens.Text.caption)
           Text(workout.lengthText).font(Tokens.Text.caption).monospacedDigit()
         }
         .frame(maxWidth: .infinity, alignment: .leading)
         .accessibilityElement(children: .combine)
       } else {
         SnapshotEmptyView(reading: reading)
       }
     }
   }
   ```

7. **`HardsetWidgetBundle.body`** gains `LastTimeWidget()` and `LastWorkoutWidget()` after
   `RestControl()`.

8. **Generator.** `SOURCES` gains `("HistoryWidgets.swift", "HardsetWidget", WIDGET)`; the widget's
   `build_settings` gains `"CODE_SIGN_ENTITLEMENTS": "HardsetWidget/HardsetWidget.entitlements",`;
   the non-built file-reference tuple gains `("HardsetWidget.entitlements", "HardsetWidget")`;
   `group_children["HardsetWidget"]` gains `"HistoryWidgets.swift"` and
   `"HardsetWidget.entitlements"`. Regenerate twice; the second run changes nothing.

Checks: `rg -n 'style: \.(relative|offset|timer)|DatabaseQueue|HardsetStore|SQLiteData' HardsetWidget`
returns nothing (no relative date, and nothing in the widget can open the database).

Ledger, under `## Phase 4`:

```markdown
- [ ] (feat(widget): last time on a machine, and the last workout, from a file) The `Hardset`
      scheme builds; HardsetFeature builds for macOS 15. Written without a compiler; look first at
      the `TimelineProvider` methods (if the SDK declares `@Sendable` completions, match them
      exactly, or they are near-misses that are never called) and `.containerBackground(_:for:)`.
  - [ ] The app's and the widget's entitlements both carry `group.com.hardset.app`, and signing
        succeeds with the group registered for the team.
  - [ ] Every check added to DEVICE-CHECKLIST §E for widgets.
```

`DEVICE-CHECKLIST.md` §E, appended:

```markdown
- [ ] **Widgets, before any workout.** Add Last time and Last workout: each reads "Your last
      workout shows here once you finish one."
- [ ] **After a workout.** Finish one with a leg press on a branded machine: Last time shows the
      movement, "Hammer Strength Leg Press", the sets as "100 kg × 8", and a date ("Tue 7 Oct"),
      never "today" or "3 days ago". Last workout shows the date, "N sets · N kg" and the length.
- [ ] **Mid-workout.** Start a workout and log on the same machine: the widget still shows the
      last *finished* time, not today's half-done sets.
- [ ] **Units.** Switch to lb in Settings: both widgets read lb within a few seconds.
- [ ] **Lock Screen.** Add Last time as a rectangular Lock Screen widget: one movement, two set
      lines, legible.
- [ ] **VoiceOver.** Each widget is read as one element, units in full ("100 kilograms for 8
      reps").
```

Commit, citing the URLs above, with a message that says the widgets show the last finished time on
a machine and the last workout from a file the app writes, never the database, and never a count
of days.

---

### Task 13: Apple Health, opt-in and write-only (Mac-only; shipping blocked)

> **Blocked for shipping, not for building:** App Review requires a privacy policy URL for any
> app with the HealthKit entitlement (spec §12.1, `DEVICE-CHECKLIST.md` §D). Build and verify this
> on the Mac now; it must not reach an external TestFlight build until the user has supplied the
> URL and it is live in App Store Connect and inside the app.

**Precondition:** Tasks 4, 5, 8 and 12 are merged, and Phase 3 **Task 13** (`WorkoutSummaryView`)
and **Task 19** (`SettingsSheet`) are merged. Read the root's finish path and `SettingsSheet` at
the tip first.

**Files:**
- Modify: `Packages/HardsetKit/Package.swift` (a `HardsetHealth` target and product, in the
  `#if !os(Linux)` branch)
- Create: `Packages/HardsetKit/Sources/HardsetHealth/HealthWorkoutWriter.swift`
- Create: `Packages/HardsetKit/Sources/HardsetFeature/HealthExportHooks.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetFeature/HardsetEnvironment.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetFeature/HardsetRootView.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetFeature/SettingsSheet.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetUI/WorkoutSummaryView.swift` (one optional input)
- Modify: `Hardset/HardsetApp.swift`, `Hardset/Info.plist`, `Hardset/Hardset.entitlements`
- Modify: `Packages/HardsetKit/Tests/HardsetCoreTests/AppResourcesTests.swift` (one test)
- Modify: `Tools/generate_project.py` (`PRODUCTS[APP]`); regenerate the pbxproj
- Modify: `docs/MAC-VERIFICATION.md`, `DEVICE-CHECKLIST.md` (new §F, and §D)

**Interfaces:**
- Consumes: `HealthWorkoutPlan`, `HealthExportDecision`, `HealthExportOutcome`, `HealthExportCopy`,
  `HealthExportSetting`, `UserDefaultsHealthExportSetting` (Task 4); `HealthExportStore` (Task 5).
- Produces:
  - `public enum HealthWorkoutWriter` (HardsetHealth, iOS only) with
    `static func isAvailable() -> Bool`, `static func requestAccess() async throws -> Bool`,
    `static func save(_ plan: HealthWorkoutPlan) async throws -> UUID`
  - `@MainActor public struct HealthExportHooks` (`isAvailable`, `requestAccess`, `save`) with an
    `.unavailable` default
  - `HardsetEnvironment.healthExports: HealthExportStore`, `.healthSetting: any HealthExportSetting`
    (init parameter `healthSetting: any HealthExportSetting = UserDefaultsHealthExportSetting()`)
  - `HardsetRootView(…, healthHooks: HealthExportHooks = .unavailable)`
  - `WorkoutSummaryView(…, healthLine: String? = nil)`; `SettingsSheet(…, health: HealthSettingInput? = nil, …)`

**Read and cite first** (checked 2026-10-11):
- https://developer.apple.com/documentation/healthkit/hkworkoutbuilder (iOS 12; **macOS: not
  available**, hence `#if os(iOS)`), `init(healthStore:configuration:device:)`,
  `beginCollection(at:) async throws`, `addMetadata(_:) async throws`, `endCollection(at:) async throws`,
  `finishWorkout() async throws -> HKWorkout?`
- https://developer.apple.com/documentation/healthkit/hkworkoutactivitytype/traditionalstrengthtraining
- https://developer.apple.com/documentation/healthkit/hkmetadatakeyexternaluuid
- https://developer.apple.com/documentation/healthkit/hkhealthstore/requestauthorization(toshare:read:) (iOS 15)
- https://developer.apple.com/documentation/healthkit/hkhealthstore/authorizationstatus(for:): "the
  app's authorization status for sharing"
- https://developer.apple.com/documentation/bundleresources/information-property-list/nshealthupdateusagedescription
- https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.healthkit

Changes:

1. **`Package.swift`** (non-Linux branch): product
   `.library(name: "HardsetHealth", targets: ["HardsetHealth"])`, and target:

   ```swift
   // iOS-only seam for HealthKit's workout builder, which macOS does not have. Write-only:
   // it saves one workout and reads nothing (DECISIONS.md §24). Depends on Core alone, like
   // HardsetAlarm, so the feature layer takes it as closures and still builds for macOS.
   .target(name: "HardsetHealth", dependencies: ["HardsetCore"], swiftSettings: mainActorByDefault),
   ```

2. **`HardsetHealth/HealthWorkoutWriter.swift`:**

   ```swift
   #if os(iOS)

     import Foundation
     import HardsetCore
     import HealthKit

     /// The Apple Health seam: one strength-training workout with its start and end, and nothing
     /// else. No energy, distance or heart-rate sample is ever added (spec 4.4).
     ///
     /// `HKHealthStore` and `HKWorkoutBuilder` are not documented as `Sendable`, so, as with
     /// AlarmKit's configuration (`DECISIONS.md` §3), each is created and consumed inside one
     /// `nonisolated` function and never crosses an isolation boundary.
     public enum HealthWorkoutWriter {
       public enum WriterError: Error { case notSaved }

       public nonisolated static func isAvailable() -> Bool {
         HKHealthStore.isHealthDataAvailable()
       }

       /// Asks to save workouts and to read nothing. True when saving is allowed. Sharing status is
       /// the one Health does report (`authorizationStatus(for:)`), so this is not a guess.
       public nonisolated static func requestAccess() async throws -> Bool {
         let store = HKHealthStore()
         try await store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [])
         return store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
       }

       public nonisolated static func save(_ plan: HealthWorkoutPlan) async throws -> UUID {
         let store = HKHealthStore()
         let configuration = HKWorkoutConfiguration()
         switch plan.activity {
         case .traditionalStrengthTraining: configuration.activityType = .traditionalStrengthTraining
         }
         let builder = HKWorkoutBuilder(
           healthStore: store, configuration: configuration, device: .local())
         try await builder.beginCollection(at: plan.start)
         try await builder.addMetadata([HKMetadataKeyExternalUUID: plan.externalID])
         try await builder.endCollection(at: plan.end)
         guard let workout = try await builder.finishWorkout() else { throw WriterError.notSaved }
         return workout.uuid
       }
     }

   #endif
   ```

3. **`HardsetFeature/HealthExportHooks.swift`:**

   ```swift
   import Foundation
   import HardsetCore

   /// Apple Health, as closures the app supplies. HealthKit's builder is iOS-only and this target
   /// also builds for macOS, so, like `RestTimerHooks`, the feature layer never imports it. The
   /// default is unavailable: a preview or a host build offers no Health setting at all.
   @MainActor
   public struct HealthExportHooks {
     public var isAvailable: () -> Bool
     /// Asks once; true when saving is allowed.
     public var requestAccess: () async -> Bool
     public var save: (HealthWorkoutPlan) async throws -> UUID

     public init(
       isAvailable: @escaping () -> Bool = { false },
       requestAccess: @escaping () async -> Bool = { false },
       save: @escaping (HealthWorkoutPlan) async throws -> UUID = { _ in throw CancellationError() }
     ) {
       self.isAvailable = isAvailable
       self.requestAccess = requestAccess
       self.save = save
     }

     public static var unavailable: HealthExportHooks { HealthExportHooks() }
   }
   ```

4. **`HardsetEnvironment`:** `public let healthExports: HealthExportStore` and
   `public let healthSetting: any HealthExportSetting`; `init` gains
   `healthSetting: any HealthExportSetting = UserDefaultsHealthExportSetting()` (the real one by
   default, so `HardsetApp.swift`'s call needs no new argument, as Phase 3 did with the first-run
   flag).

5. **`HardsetRootView`.**
   - `private let healthHooks: HealthExportHooks` (init parameter, default `.unavailable`),
     `@State private var healthLine: String?`, `@State private var healthEnabled = false`,
     `@State private var healthDenied = false`; in the launch `.task`,
     `healthEnabled = environment.healthSetting.isEnabled`.
   - In `LiveSessionScreen`'s `onFinished`, for `.finished(let id)` after setting `summaryTarget`:
     `healthLine = nil` then `Task { healthLine = await exportToHealth(id) }`.
   - Add:

     ```swift
     /// After the workout is closed and saved, and only for one finished here, now: Health is told
     /// about a workout that exists, once (`HealthExportStore`, `DECISIONS.md` §24).
     private func exportToHealth(_ id: SessionID) async -> String? {
       let decision: HealthExportDecision
       do {
         decision = try environment.healthExports.decision(
           for: id, isEnabled: environment.healthSetting.isEnabled)
       } catch {
         return HealthExportCopy.summaryLine(for: .failed)
       }
       switch decision {
       case .skip(let reason):
         return HealthExportCopy.summaryLine(for: .skipped(reason))
       case .export(let plan):
         let healthID: UUID
         do {
           healthID = try await healthHooks.save(plan)
         } catch {
           return HealthExportCopy.summaryLine(for: .failed)
         }
         do {
           try environment.healthExports.recordExport(of: id, healthWorkoutID: healthID)
         } catch {
           // Health has the workout, which is what the lifter asked for. The record only stops a
           // second save, and nothing ever retries this one, so it is not shown; a debug build
           // stops on it.
           assertionFailure("Saved to Health but not recorded: \(error)")
         }
         return HealthExportCopy.summaryLine(for: .saved)
       }
     }

     /// The toggle shows on only once Health allows saving: persist before claiming.
     private func setHealthExport(_ wanted: Bool) {
       guard wanted else {
         environment.healthSetting.setEnabled(false)
         healthEnabled = false
         return
       }
       Task {
         let allowed = await healthHooks.requestAccess()
         environment.healthSetting.setEnabled(allowed)
         healthEnabled = allowed
         healthDenied = !allowed
       }
     }
     ```

   - Pass `healthLine: healthLine` to the summary's `WorkoutSummaryView`, and to `SettingsSheet`
     pass `health: healthHooks.isAvailable() ? HealthSettingInput(isEnabled: Binding(get: { healthEnabled }, set: setHealthExport), accessDenied: healthDenied) : nil`.

6. **`SettingsSheet`.** Add, public, in the same file:

   ```swift
   /// The Apple Health row's inputs. Nil hides the row: a device without Health offers nothing.
   public struct HealthSettingInput {
     public var isEnabled: Binding<Bool>
     public var accessDenied: Bool

     public init(isEnabled: Binding<Bool>, accessDenied: Bool) {
       self.isEnabled = isEnabled
       self.accessDenied = accessDenied
     }
   }
   ```

   an init parameter `health: HealthSettingInput? = nil` before `onDone`, and, when non-nil, a
   `Section` with `Toggle(HealthExportCopy.settingTitle, isOn: health.isEnabled)`, the footer
   `Text(HealthExportCopy.settingFooter)`, and, when `accessDenied`, a line
   `Text(HealthExportCopy.accessDenied)` in `Tokens.Color.textSecondary` with an `info.circle`
   glyph (a refusal is the lifter's choice, not an error).

7. **`WorkoutSummaryView`.** Add `healthLine: String? = nil` to its init, stored; when non-nil, a
   row in the "When" section: `Label(healthLine, systemImage: "heart.text.square")` in
   `Tokens.Text.caption`, `Tokens.Color.textSecondary`. Its previews compile unchanged.

8. **`HardsetApp.swift`.** `import HardsetHealth`; pass to `HardsetRootView`:

   ```swift
   healthHooks: HealthExportHooks(
     isAvailable: { HealthWorkoutWriter.isAvailable() },
     requestAccess: { (try? await HealthWorkoutWriter.requestAccess()) ?? false },
     save: { try await HealthWorkoutWriter.save($0) }
   ),
   ```

   (`try?` here is the one deliberate exception: a request Health refused to even show is the
   same, to the lifter, as a refusal, and the row then says how to turn it on.)

9. **`Hardset/Info.plist`**, before the remote-notifications comment:

   ```xml
   	<!-- Apple Health, opt-in and write-only (spec 4.4, DECISIONS.md §24). Only the save
   	     description: Hardset asks to read nothing, so NSHealthShareUsageDescription is absent.
   	     AppResourcesTests holds it to that. -->
   	<key>NSHealthUpdateUsageDescription</key>
   	<string>Hardset adds each workout you finish to Health as strength training, with its start and end time. It sends nothing else.</string>
   ```

   `Hardset/Hardset.entitlements`, before the App Group:

   ```xml
   	<!-- Apple Health, write-only and opt-in (spec 4.4). Needs the HealthKit capability on the
   	     App ID, which needs a paid team. -->
   	<key>com.apple.developer.healthkit</key>
   	<true/>
   ```

   No `UIRequiredDeviceCapabilities` `healthkit` entry: Health is optional here, and that key would
   hide the app from devices without it.

10. **`AppResourcesTests`**, one test inside the suite, after `appGroup`. It runs on Linux:
    `Tools/linux-test.sh --filter AppResourcesTests` fails before step 9 and passes after.

    ```swift
      /// Task 13. Write-only means a reason to save and no reason to read.
      @Test("Apple Health is write-only: a reason to save, none to read, and the entitlement")
      func healthKitWriteOnly() throws {
        let info = try plist("Hardset/Info.plist")
        let reason = info["NSHealthUpdateUsageDescription"] as? String
        #expect(reason?.contains("strength training") == true)
        #expect(info["NSHealthShareUsageDescription"] == nil)
        let entitlements = try plist("Hardset/Hardset.entitlements")
        #expect(entitlements["com.apple.developer.healthkit"] as? Bool == true)
      }
    ```

11. **Generator.** `PRODUCTS[APP]` gains `"HardsetHealth"` (the widget does not link it).
    Regenerate twice; the second run changes nothing.

Checks: `rg -n 'activeEnergy|HKQuantityType|HKQuantitySample|totalEnergy|distance' Packages/HardsetKit/Sources/HardsetHealth`
returns nothing; `rg -n 'read: \[\]' Packages/HardsetKit/Sources/HardsetHealth` finds the one
request.

Ledger, under `## Phase 4`:

```markdown
- [ ] (feat(health): a finished workout can go to Apple Health, opt-in and write-only)
      **Do not ship without the privacy policy URL** (DEVICE-CHECKLIST §D). The `Hardset` scheme
      builds; `./test.sh` builds HardsetHealth for macOS as an empty module. Written without a
      compiler; look first at the async `HKWorkoutBuilder` calls inside one `nonisolated static`
      function (no "sending … risks causing data races"), `HKDevice.local()`, and the
      `Binding(get:set:)` built in `HardsetRootView`.
  - [ ] Requesting access with `read: []` and only `NSHealthUpdateUsageDescription` does not raise
        "NSHealthShareUsageDescription must be set". If it does, add that key with "Hardset does
        not read your Health data." and record it here and in `AppResourcesTests`.
  - [ ] SF Symbols exist: `heart.text.square`, `info.circle`.
  - [ ] Every check in DEVICE-CHECKLIST §F.
```

`DEVICE-CHECKLIST.md`, a new section after §E:

```markdown
## F. Apple Health — opt-in, write-only (blocked for shipping on the privacy policy URL)

- [ ] **Off by default.** Fresh install: Settings shows "Save workouts to Apple Health", off.
      Finish a workout: Health has nothing from Hardset.
- [ ] **Turning it on.** Toggle on: Health's sheet lists only "Workouts" under "Allow Hardset to
      write" and nothing to read. Allow: the toggle stays on. Deny: it turns back off and the line
      says how to turn it on in Settings.
- [ ] **One workout.** Finish a 50-minute workout: the summary says "Saved to Apple Health as
      strength training." Health › Workouts shows one Traditional Strength Training workout with
      the session's start and end, and **no Active Energy or calories**.
- [ ] **Never twice.** Sign out of iCloud and back in so the session re-downloads, then relaunch:
      Health still has one workout for it.
- [ ] **Overnight.** Leave a workout open past six hours, then finish it: the summary says "Not
      sent to Apple Health, because its length is unknown.", and Health has nothing new.
- [ ] **Another device's workout.** A workout finished on a second device and synced here is not
      sent from this one.
- [ ] **Turning it off.** Off, then finish a workout: nothing new in Health; earlier workouts stay
      (Hardset never deletes from Health).
```

`DEVICE-CHECKLIST.md` §D, after the privacy policy line:

```markdown
- [ ] The HealthKit entitlement ships only with the privacy policy URL live (App Review requires
      one for HealthKit). Until then, keep it out of any external TestFlight build.
```

Commit, citing the URLs above, with a message that says a finished workout can go to Apple Health
as strength training with its real start and end and nothing else, only when the lifter asks, and
that shipping waits on a privacy policy URL.

---

### Task 14: The two tips in the logger (Mac-only)

**Precondition:** Tasks 7 and 13 are merged (13 last touched `HardsetApp.swift`), and Phase 3
**Task 15** is merged (it owns `ExerciseSectionView` and `SessionView`).

**Files:**
- Create: `Packages/HardsetKit/Sources/HardsetUI/FeatureTipViews.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetUI/ExerciseSectionView.swift` (the machine chip and
  the name button)
- Modify: `Packages/HardsetKit/Sources/HardsetUI/SessionView.swift` (computing the facts)
- Modify: `Hardset/HardsetApp.swift` (one call in `init()`)
- Modify: `docs/MAC-VERIFICATION.md`

**Interfaces:**
- Consumes: `FeatureTip`, `FeatureTipFacts`, `FeatureTipPlan` (Task 7);
  `ExerciseLogState.priorNote`.
- Produces: `struct MachineChipTip: Tip`, `struct MovementHistoryTip: Tip`, and
  `public enum HardsetTips { public static func configure(); static func update(_ facts: FeatureTipFacts) }`.

**Read and cite first** (checked 2026-10-11):
- https://developer.apple.com/documentation/tipkit/tip (iOS 17, macOS 14)
- https://developer.apple.com/documentation/tipkit/tips/configure(_:): "Call this function during
  app initialization."
- https://developer.apple.com/documentation/tipkit/tips/configurationoption/displayfrequency(_:):
  with `.daily`, "no new tips will be shown for at least 24 hours"
- https://developer.apple.com/documentation/swiftui/view/popovertip(_:arrowedge:action:) (iOS 17)

Changes:

1. **`HardsetUI/FeatureTipViews.swift`:**

   ```swift
   import HardsetCore
   import SwiftUI
   import TipKit

   /// The machine chip: loads are kept per machine. Words from `FeatureTip`, tested in Core.
   struct MachineChipTip: Tip {
     @Parameter static var isEligible: Bool = false
     var title: Text { Text(FeatureTip.machineChip.title) }
     var message: Text? { Text(FeatureTip.machineChip.message) }
     var image: Image? { Image(systemName: FeatureTip.machineChip.symbolName) }
     var rules: [Rule] { [#Rule(Self.$isEligible) { $0 == true }] }
   }

   /// A movement's name opens its load history.
   struct MovementHistoryTip: Tip {
     @Parameter static var isEligible: Bool = false
     var title: Text { Text(FeatureTip.movementHistory.title) }
     var message: Text? { Text(FeatureTip.movementHistory.message) }
     var image: Image? { Image(systemName: FeatureTip.movementHistory.symbolName) }
     var rules: [Rule] { [#Rule(Self.$isEligible) { $0 == true }] }
   }

   /// The app's two tips (spec 4.7): when each may show is Core's (`FeatureTipPlan`); TipKit shows
   /// each once, ends it when the feature is used, and shows at most one a day.
   public enum HardsetTips {
     /// From `HardsetApp.init()`. A store TipKit cannot open means no tips, which costs nothing.
     public static func configure() {
       do {
         try Tips.configure([.displayFrequency(.daily), .datastoreLocation(.applicationDefault)])
       } catch {
         assertionFailure("TipKit could not be configured: \(error)")
       }
     }

     static func update(_ facts: FeatureTipFacts) {
       MachineChipTip.isEligible = FeatureTipPlan.isEligible(.machineChip, facts: facts)
       MovementHistoryTip.isEligible = FeatureTipPlan.isEligible(.movementHistory, facts: facts)
     }
   }
   ```

2. **`SessionView`.** Compute, from what it already holds:

   ```swift
   private var tipFacts: FeatureTipFacts {
     FeatureTipFacts(
       sessionHasGym: onSelectMachine != nil,
       hasMovementOnScreen: !exercises.isEmpty,
       movementWithHistoryOnScreen: exercises.contains { $0.priorNote != nil },
       isEnteringNumbers: focus != nil)
   }
   ```

   where `focus` is the keypad's `@State private var focus: KeypadFocus?` (line 59 at `5d9fb52`;
   Phase 3 Task 15 may move it, so use whatever drives the pad's presence), and `onSelectMachine`
   is the input that already decides whether a chip is drawn. Attach
   `.onChange(of: tipFacts, initial: true) { HardsetTips.update(tipFacts) }` to the list.

3. **`ExerciseSectionView`.** On the machine chip, `.popoverTip(MachineChipTip())`, and in the
   chip's action, before opening the picker, `MachineChipTip().invalidate(reason: .actionPerformed)`.
   On the name button (present only when `onShowHistory != nil`),
   `.popoverTip(MovementHistoryTip())` and `MovementHistoryTip().invalidate(reason: .actionPerformed)`
   in its action. Add `import TipKit`. Only the first section shows a tip: pass a
   `showsTips: Bool` input from `SessionView` (true for the first exercise only) and apply both
   modifiers only when it is true, so one tip has one anchor.

4. **`HardsetApp.init()`**, first line: `HardsetTips.configure()` (`import HardsetUI` is added if
   not already present).

Ledger, under `## Phase 4`:

```markdown
- [ ] (feat(ui): two tips that point at the machine chip and a movement's history) HardsetUI
      builds for iOS and macOS 15. Written without a compiler; look first at
      `@Parameter static var isEligible` and `#Rule(Self.$isEligible)` (TipKit's macro spelling),
      and `.onChange(of:initial:_:)`.
  - [ ] Fresh install, a workout at a gym, one movement: the machine tip appears over the chip.
        Tap the chip: the tip goes for good. Next day, with a movement that has history, the
        history tip appears over its name; tapping the name ends it.
  - [ ] No tip appears while the keypad is up, nor without a gym (no chip), nor on a movement with
        no history. Never two tips on screen; never two in a day.
  - [ ] VoiceOver reads each tip; dismissing it with its close button works.
```

Commit, citing the URLs above, with a message that says two tips point at the two features a new
lifter may not find, once each, never over the keypad, and never with advice.

---

### Task 15: The app icon — a brief and SVG layer drafts (design)

Spec 4.6: "A design brief plus SVG layer drafts, to be finished in Icon Composer on the Mac. This
needs the user's design judgement and cannot be done here." So this task writes no code and
changes no target. It produces a brief the user can judge, and layer files Icon Composer can
import. **The final artwork is the user's decision** (spec §12.2).

**Files:**
- Create: `Design/AppIcon/BRIEF.md`
- Create: `Design/AppIcon/layers/01-stack.svg`
- Create: `Design/AppIcon/layers/02-pin.svg`
- Modify: `docs/MAC-VERIFICATION.md`

**Read and cite first** (checked 2026-10-11):
- https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer:
  1024 × 1024 canvas for iPhone; "Design your app icon in layers that the system renders in the
  z-plane from back to front"; "Give the layers meaningful names that include numbers"; "Remove
  blurs and shadows, and specular, opacity, and translucency settings"; "Remove background colors
  and gradients"; "choose the SVG format whenever possible"; "Don't export the canvas mask";
  convert text to outlines; at most four groups.

- [ ] **Step 1: Write the brief**

`Design/AppIcon/BRIEF.md`:

```markdown
# Hardset app icon — brief

**What it must say:** calm confidence. A logger for people who train on specific machines and want
the numbers to be honest. Not hype, not a reward.

**The idea:** a weight stack with its selector pin. It is the one object every machine lifter
touches before every set, it is literally "the set" the app records, and it is machine-specific,
which is the app's second promise. Read at a glance as plates and a pin, never as a dumbbell.

**Refused, because each conflicts with the product's refusals (HANDOFF §6):** flames, streak
marks, trophies, medals, stars, check marks as rewards, arrows pointing up, a flexed arm, any
number or letter, any text.

**Layers (back to front), 1024 × 1024, SVG, flat fills, no effects:**
1. `01-stack.svg` — five horizontal plates, evenly spaced, white. The plates carry no shading;
   Icon Composer adds depth.
2. `02-pin.svg` — the selector pin entering the fourth plate from the right: a shaft and a round
   pull knob, in the accent colour (#2E82F6, the app's AccentColor).

**Background:** set in Icon Composer, not in the SVGs (Apple: "Remove background colors and
gradients"). Suggested: the palette's dark background (0.055, 0.055, 0.063) for the default
appearance; let Icon Composer derive the tinted and clear appearances. Decide on the Mac.

**Checks the user should make in Icon Composer:** legible at the smallest Home Screen size;
plates still read as plates in the clear and tinted appearances; the pin is distinguishable
without colour (its shape and position, not its hue, say "selected"); nothing touches the mask
edge.

**Open for the user:** the final proportions, the background colour, whether the pin keeps the
accent colour or turns white with the plates tinted instead, and whether five plates or four read
better at small sizes.
```

- [ ] **Step 2: Write the layer drafts**

`Design/AppIcon/layers/01-stack.svg`:

```xml
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <!-- 01, back: five plates of a weight stack. Flat white; Icon Composer adds glass and depth. -->
  <rect x="272" y="284" width="480" height="72" rx="20" fill="#FFFFFF"/>
  <rect x="272" y="380" width="480" height="72" rx="20" fill="#FFFFFF"/>
  <rect x="272" y="476" width="480" height="72" rx="20" fill="#FFFFFF"/>
  <rect x="272" y="572" width="480" height="72" rx="20" fill="#FFFFFF"/>
  <rect x="272" y="668" width="480" height="72" rx="20" fill="#FFFFFF"/>
</svg>
```

`Design/AppIcon/layers/02-pin.svg`:

```xml
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <!-- 02, front: the selector pin in the fourth plate (centre y 608), shaft then pull knob. -->
  <rect x="640" y="596" width="184" height="24" rx="12" fill="#2E82F6"/>
  <circle cx="852" cy="608" r="44" fill="#2E82F6"/>
</svg>
```

- [ ] **Step 3: Check they are well-formed and on the canvas**

Run:

```bash
python3 -I -c '
import sys, xml.etree.ElementTree as ET
for p in sys.argv[1:]:
    root = ET.parse(p).getroot()
    assert root.get("viewBox") == "0 0 1024 1024", p
    assert not root.findall(".//{http://www.w3.org/2000/svg}text"), p
    print("ok", p)
' Design/AppIcon/layers/01-stack.svg Design/AppIcon/layers/02-pin.svg
```

Expected: `ok` for both. (No SVG renderer is installed here; open the files in a browser to see
them.)

- [ ] **Step 4: Ledger, and commit**

Ledger, under `## Phase 4`:

```markdown
- [ ] (docs(design): an icon brief and two layer drafts) **Needs the user's design judgement.**
      In Icon Composer (Xcode › Open Developer Tool › Icon Composer): import `01-stack.svg` and
      `02-pin.svg` from `Design/AppIcon/layers/`, set the background, check the default, dark,
      tinted and clear appearances and the smallest size, and save as `AppIcon.icon`.
  - [ ] Then, in a scratch copy of the project, add `AppIcon.icon` to the Hardset target in Xcode
        once and read the `lastKnownFileType` Xcode writes for it. Add
        `("AppIcon.icon", "Hardset", APP)` to `RESOURCES` in `Tools/generate_project.py`, teach
        its file-type switch that extension, add the file to `group_children["Hardset"]`, keep
        `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`, remove `AppIcon.appiconset`, regenerate
        twice, and build. Never hand-edit the pbxproj.
```

```bash
git add Design/AppIcon docs/MAC-VERIFICATION.md
git commit -m "docs(design): an icon brief and two SVG layer drafts for Icon Composer

The icon needs the user's judgement, so this is a brief to judge and layers to
start from: a weight stack and its selector pin, the object every machine lifter
touches before every set. Flat SVG layers, numbered back to front, with no
background or effects, as Icon Composer asks.

https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer

Co-Authored-By: <your model's trailer>"
```

---

### Task 16: Phase 4's copy through the seam (Core)

**Precondition:** Phase 3 **Task 11** is merged (which itself waited on the Mac gate for Phase 3
Task 10), and Tasks 2, 3, 4, 6 and 7 are merged. `localized(_:comment:)` and its rules are
`DECISIONS.md` §23's.

**Files:**
- Modify: `Packages/HardsetKit/Sources/HardsetCore/RestActivityContent.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetCore/SystemRequests.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetCore/HealthExport.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetCore/WidgetSnapshot.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetCore/FeatureTips.swift`

**Interfaces:** none change. Every public name and every returned English string stays the same,
which is what the existing Phase 4 suites pin, on both platforms.

- [ ] **Step 1: Run the suites that pin this copy**

Run: `Tools/linux-test.sh --filter 'RestActivityContentTests|SystemRequestsTests|HealthExportTests|WidgetSnapshotTests|FeatureTipsTests'`
Expected: PASS (the baseline).

- [ ] **Step 2: Route each literal**

Each literal below is wrapped in `localized(_:comment:)` with its text unchanged and the comment from the table, where
the interpolations stay as they are (they are all `String` or `Int`, as §23 requires).
`static let` copy becomes `static var` with a `get`-only body, because `localized` reads the
bundle at call time.

| File | Literal (as it reads today) | Comment |
|---|---|---|
| RestActivityContent | "Pause", "Resume", "Skip" | Lock Screen rest button |
| RestActivityContent | "Pause rest", "Resume rest", "Skip rest" | VoiceOver label for the Lock Screen rest button |
| RestActivityContent | "Paused, \(remaining.clockString) left" | Lock Screen, a paused rest's remainder, m:ss |
| RestActivityContent | "Rest over", "Rest" | Lock Screen rest status / title when no set started the rest |
| SystemRequests | "A rest can be from \(lower) to \(upper)." (`refusal`, with `lower` and `upper` bound to the two `clockString`s first) | Siri, a refused rest length |
| SystemRequests | "No rest is running.", "The rest is already paused.", "That rest is already over.", "The rest is already running." | Siri, a rest command with nothing to do |
| SystemRequests | "Resting for \(duration.clockString).", "Rest paused.", "Rest resumed.", "Rest skipped." | Siri, a rest command done |
| SystemRequests | "Rest · \(rest.clockString)", "Rest · Choose" | Control Center Rest control label |
| HealthExport | `settingTitle`, `settingFooter` (one literal, not concatenated), `accessDenied` | Settings, the Apple Health row |
| HealthExport | the three `summaryLine` sentences | Workout summary, what became of Apple Health |
| WidgetSnapshot | "Length unknown", "Free weight" | Widget, a workout with no length / a set with no machine |
| WidgetSnapshot | "\(load) × \(reps)" | Widget, one set: load times reps |
| WidgetSnapshot | `hidden == 1 ? "+1 more set" : "+\(hidden) more sets"` (two literals) | Widget, sets not shown |
| WidgetSnapshot | "\(exerciseName) on \(equipmentText): \(sets)" and "\(weight) for \(reps)" | VoiceOver, a widget's last time |
| WidgetSnapshot | the four `WidgetCopy` strings | Widget empty states and titles |
| FeatureTips | both titles and both messages | Tip pointing at a feature |

For example, `RestActivityContent.Control.title` becomes:

```swift
public var title: String {
  switch self {
  case .pause: localized("Pause", comment: "Lock Screen rest button")
  case .resume: localized("Resume", comment: "Lock Screen rest button")
  case .stop: localized("Skip", comment: "Lock Screen rest button")
  }
}
```

and `WidgetSnapshot.LastTime.lines(formatter:limit:)`'s last line becomes:

```swift
let more =
  hidden == 1
  ? localized("+1 more set", comment: "Widget, sets not shown")
  : localized("+\(hidden) more sets", comment: "Widget, sets not shown")
return shown + [more]
```

Do not route: SF Symbol names, `appGroupIdentifier`, `fileName`, Codable keys, or the `" · "`
separators that join two already-localized parts.

- [ ] **Step 3: Run to verify nothing changed**

Run: the Step 1 command, then `Tools/linux-test.sh`.
Expected: PASS, with no test edited. Check:
`rg -n '"[A-Z][a-z]' Packages/HardsetKit/Sources/HardsetCore/{RestActivityContent,SystemRequests,HealthExport,WidgetSnapshot,FeatureTips}.swift | rg -v 'localized\(|symbolName|systemImage|comment:'`
lists only symbol names and identifiers.

- [ ] **Step 4: Ledger, and commit**

Ledger, under `## Phase 4`:

```markdown
- [ ] (refactor(core): Phase 4's words through the localization seam) `./test.sh` passes on the
      Mac: the same Phase 4 suites now exercise the Apple branch of `localized` and must return the
      same English.
```

```bash
git add Packages/HardsetKit/Sources/HardsetCore/RestActivityContent.swift \
  Packages/HardsetKit/Sources/HardsetCore/SystemRequests.swift \
  Packages/HardsetKit/Sources/HardsetCore/HealthExport.swift \
  Packages/HardsetKit/Sources/HardsetCore/WidgetSnapshot.swift \
  Packages/HardsetKit/Sources/HardsetCore/FeatureTips.swift docs/MAC-VERIFICATION.md
git commit -m "refactor(core): Phase 4's words go through the localization seam

The Lock Screen, Siri's replies, the Health row, the widgets and the tips were
written in plain English while Core's catalog waited on its Mac gate. That gate
is passed, so they now go through the same door as the rest of Core's copy, and
the same tests pin the same English on both platforms.

Co-Authored-By: <your model's trailer>"
```

---

## Self-review

Run against the spec with the plan complete; issues found were fixed inline above.

**1. Spec coverage (§10).**

| Spec item | Where |
|---|---|
| 4.1 A progress ring, `ProgressView(timerInterval:)` | Task 2 (`Phase.counting(range:)`, the whole-countdown ring), Task 9 (`RestRing`) |
| 4.1 The machine name | Task 2 (`detail`: "Set 2 of 4 · Hammer Strength Leg Press"), Task 9 |
| 4.1 A guarded date range | Task 2 (never reversed, never reads the clock; first Review Focus item) |
| 4.1 Pause/resume and stop as `LiveActivityIntent`s | Task 3 (`RestCommandPlan`), Task 9 (`PauseRestIntent`, `ResumeRestIntent`, `StopRestIntent`, `perform`/`settle`) |
| 4.2 `StartWorkoutIntent` opens the app and starts an empty session | Task 3 (`StartWorkoutPolicy`, `SystemRequestInbox`), Task 10 |
| 4.2 `StartRestIntent` requires the duration | Task 3 (`RestRequest.duration`), Task 9 (required `Measurement<UnitDuration>`, Siri asks) |
| 4.2 `StopRestIntent` stops the rest | Task 3 (`.stop`), Task 9 |
| 4.2 Phrases for Siri, Spotlight and the Action button | Task 10 (`HardsetShortcuts`) |
| 4.3 Start workout, and Rest with a configured duration, in the widget extension | Task 3 (`RestControlState`), Task 11 |
| 4.4 `HKWorkoutBuilder`, `.traditionalStrengthTraining`, start and end from `SessionTimeline` | Task 4 (`HealthExportPolicy`), Task 13 (`HealthWorkoutWriter`) |
| 4.4 No energy burned | Task 4 (no field can carry it), Task 13 (`rg` check, device check) |
| 4.4 Skip implausible durations | Task 4 (`lengthUnknown`, `implausiblyLong`, `endsInFuture`) |
| 4.4 The export policy is pure Core, tested on Linux | Task 4 |
| 4.4 A new device-local table with a decision entry | Task 1 (§24), Task 5 |
| 4.4 Opt-in; blocked on a privacy policy URL | Task 4 (off by default), Task 13 (banner, DEVICE-CHECKLIST §D and §F) |
| 4.5 "Last time on this machine" and the last session | Task 6, Task 12 |
| 4.5 An App Group snapshot file; the widget never opens the database | Task 1 (§25), Task 6, Task 12 (entitlements, `rg` check) |
| 4.5 Privacy manifest 1C8F.1, plus a widget manifest | Task 8 (reading 9: no shared defaults, so not declared, and a test guards it; the widget manifest) |
| 4.5 No "days since" counts | Task 6 (`dayTextIsAbsolute`, `copy`), Task 12 (`rg` check) |
| 4.6 A design brief plus SVG layer drafts | Task 15 |
| 4.7 At most two tips, feature-pointing, never coaching | Task 7 (`two`, `neverCoaching`), Task 14 |
| 4.8 Launch background colour | Task 8 |
| 4.8 Privacy manifest updates | Task 8 (both manifests, pinned) |
| §4 No set logged from outside the app UI | Task 1 (§26), Task 3 (`SystemRequest` has one case), Task 10 (ledger: no action takes a weight or reps) |
| §4 No default rest | Task 3 (`outOfRangeRefusedNotClamped`, `unconfiguredControlStartsNothing`) |
| §4 `HardsetApp.swift` stays wiring only | Tasks 9, 10, 13, 14 add construction and registration lines only |
| §5 Ledger for every unverifiable commit | Tasks 8–16 |

Gaps found and fixed while writing:
- The existing widget's `Text(timerInterval: Date.now...countdown.fireDate)` traps when drawn
  after the deadline. Task 2 makes the range a Core value; Task 9's check forbids `Date.now...`.
- An intent can launch the app in the background, where the controller is idle until it
  reconciles, and the app can be suspended before the 400 ms debounced commit schedules the
  alarm. Task 9's `perform(_:)` reconciles first and `settle()`s last (reading 5).
- A rest started by Siri during a workout would have been captioned with the previous set's
  metadata, because the bar read `coordinator.activeRest`. Task 10 reads the timer's own metadata.
- A foreign key from the Health record to `sessions` would cascade on a sign-out wipe and let the
  re-downloaded session be exported twice. §24 and Task 5 (`exportSurvivesSessionDeletion`).
- `Tools/linux-test.sh` mounted only the package, so no test could see the app's plists. Task 8
  mounts the checkout.
- `openAppWhenRun` is deprecated in iOS 26 and errors in an extension, where the control's intent
  is compiled; Task 10 uses `supportedModes`.

**2. Placeholder scan.** No "TBD", "TODO", "implement later", "similar to Task N", or test step
without code. Core, Store and resource steps carry complete code that was compiled and run.
Mac-only steps carry exact Swift, plist and generator snippets. Where a Mac-only task edits code
another plan is still writing (Tasks 10, 12, 13, 14), it names the symbols that plan produces and
says to read the file at the tip first; the snippets are complete against those names. Task 16 is
a mechanical routing given as a complete table of every literal and its comment, with the two
non-trivial transformations written out.

**3. Type consistency.** Checked across tasks:
- `RestActivityContent.make(mode:metadata:)`, `.Phase.counting(range:)`, `.paused(remaining:fractionRemaining:)`,
  `.Control.pause/.resume/.stop` with `title`, `symbolName`, `spokenLabel` in Tasks 2 and 9; Task 9's
  `make(_ state: AlarmPresentationState, metadata:)` overload is widget-only.
- `RestCommand.start/.pause/.resume/.stop`, `RestCommandOutcome.perform/.nothing`,
  `RestCommandPlan.outcome(for:state:now:)` and `.confirmation(for:)`, `RestRequest.duration(seconds:)`
  and `.refusal` in Tasks 3, 9, 16.
- `RestTimerController.perform(_:now:)`, `settle()`, `metadata`, `start(duration:metadata: RestMetadata?)`
  in Tasks 9 and 10; `RestTimerHooks.metadata` in Task 10.
- `StartRestIntent(seconds:)`, `StopRestIntent()`, `StartWorkoutIntent()`, `OpenHardsetIntent()` in
  Tasks 9, 10, 11; `IntentDependencies.register(restTimer:systemRequests:)` in Task 10 replaces Task
  9's `register(restTimer:)` at its one call site.
- `SystemRequestInbox.pending/post/take`, `SystemRequest.startWorkout`, `WorkoutLaunchState(isReady:hasOpenWorkout:resumeFailed:showsFirstRun:)`,
  `StartWorkoutPolicy.action(for:)` in Tasks 3 and 10.
- `RestControlState.make(configuredSeconds:)`, `.ready`, `.needsChoice`, `.title` in Tasks 3 and 11.
- `HealthExportPolicy.decide(sessionID:timeline:loggedSets:isEnabled:alreadyExported:now:)`,
  `HealthWorkoutPlan(sessionID:activity:start:end:)`, `.externalID`, `HealthExportSkip`,
  `HealthExportCopy.summaryLine(for:)`, `HealthExportSetting.isEnabled/setEnabled(_:)` in Tasks 4,
  5, 13; `HealthExportStore.decision(for:isEnabled:now:)`, `recordExport(of:healthWorkoutID:at:)`,
  `healthWorkoutID(for:)` in Tasks 5 and 13.
- `WidgetSnapshot` (`lastWorkout`, `lastTimes`, `formatter`, `dayText`), `LastTime.lines(formatter:limit:)`,
  `spokenSummary(formatter:)`, `equipmentText`, `LastWorkout.totalsText(formatter:)`, `lengthText`,
  `WidgetSnapshotFile(containerURL:)`, `.read()`, `.appGroupIdentifier`, `WidgetSnapshotReading`,
  `WidgetCopy`, `WidgetSnapshotStore.snapshot(unit:now:)` in Tasks 6 and 12.
- `FeatureTip.machineChip/.movementHistory`, `FeatureTipFacts(sessionHasGym:hasMovementOnScreen:movementWithHistoryOnScreen:isEnteringNumbers:)`,
  `FeatureTipPlan.isEligible(_:facts:)` in Tasks 7 and 14.
- `AppResourcesTests.plist(_:)` in Tasks 8, 12, 13.
- `DECISIONS.md` §24 (Tasks 5, 8, 13), §25 (Tasks 6, 8, 12), §26 (Tasks 3, 9, 10).

**4. Review Focus.** Each of the five lines is pinned by named tests in its owning task:
`renderAfterDeadlineNeverReverses`, `zeroLengthCountdown`, `nonFiniteTotal`,
`resumedAlarmRingCoversWholeRest` and `pausedFractionClamped` (Task 2);
`outOfRangeRefusedNotClamped`, `floatingNoiseIsWholeSeconds` and `unconfiguredControlStartsNothing`
(Task 3); `openWorkoutIsShownNotReplaced`, `resumeFailureBlocksStart` and `requestWaitsForLaunch`
(Task 3); `implausiblyLongIsSkipped` and `endsInFutureIsSkipped` (Task 4),
`exportSurvivesSessionDeletion` and `secondExportIsSkipped` (Task 5); `openWorkoutNeverLastTime`,
`warmupsExcluded`, `machinesStayApart` and `archivedMachineStillNamed` (Task 6, Store),
`unreadableFileIsEmptyNotCrash` and `newerVersionIsIgnored` (Task 6, Core). The next most likely to
bite, a pounds-mode lifter reading the widget, is covered by `lines` (Task 6) and the unit-change
refresh in Task 12.
