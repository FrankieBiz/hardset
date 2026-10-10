# Phase 1 — Trust Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** fix the correctness defects that make the app untrustworthy before any polish:
- the rest timer can start, per exercise, remembered from the lifter's own choice
- the timer survives a force-quit and a Lock Screen change
- what you see is what is saved
- kilograms never leak into pounds mode
- the wording never overstates confidence
- no failure is swallowed

**Architecture:** all behaviour lands in `HardsetCore` (pure) or `HardsetStore` (GRDB), test-first,
verified by `Tools/linux-test.sh`. UI, Feature and Alarm tasks only render or wire those types.
They cannot compile on Linux, so each adds an entry to `docs/MAC-VERIFICATION.md`.

**Tech Stack:** Swift 6.2 (Swift 6 language mode, `NonisolatedNonsendingByDefault`), Swift
Testing, GRDB/SQLiteData, SwiftUI (iOS 26.1), AlarmKit.

**Spec:** `docs/superpowers/specs/2026-10-10-hardset-ada-polish-design.md` §7 (Phase 1), with §4
non-negotiables and §5 verification.

## Global Constraints

- No default rest. A rest duration exists for an exercise only after the lifter picks one, and
  nothing is preselected.
- Persist before claiming. Nothing is marked logged, started or announced until the write it
  depends on has succeeded (`HANDOFF.md` §5.4).
- A set that is not complete cannot be written. There is no `?? 0` anywhere (`HANDOFF.md` §5.1).
- Kilograms are canonical. Conversion happens only through `WeightUnit`, and display goes through
  `WeightFormatter` (Task 3) only.
- No schema change in this phase. `deviceRestTimer` already exists and is device-local.
- Never edit `ExerciseCatalog.swift`, and never edit methodology text pinned by tests.
- `HardsetApp.swift` stays wiring only.
- Core types are `nonisolated` by module default. Store types that touch the database are
  explicitly `nonisolated`. `@Observable` coordinators are `@MainActor`.
- Store tests build databases with `Configuration.forTesting()` (Phase 0), never
  `Configuration()`.
- Verification:
  - Core and Store tasks: `Tools/linux-test.sh` (optionally `--filter <Suite>`) must pass.
  - UI, Feature and Alarm tasks: add a `docs/MAC-VERIFICATION.md` entry under a `## Phase 1`
    heading, naming the commit's subject, what to build or run, and what must be true.
- Every new Apple API used in Mac-only code must be confirmed against developer.apple.com (use
  WebFetch). Put the URL in the commit message body. Anything newer than iOS 26.1 needs
  `#available`.
- Commit messages explain *why*. Never `git push`.

## Review Focus

- **Rest preference for an exercise added mid-session.** Picking a rest on a movement added
  through the picker must persist and apply to its next set exactly as for a planned one.
  Covered in Task 4.
- **Two blocks of the same movement in one session.** The preference is per `ExerciseID`, so
  both blocks share it and changing one changes both. Expected, and pinned by a test in Task 4.
- **A paused alarm whose remainder cannot be read.** It must be cancelled and shown idle, never
  displayed with a guessed remainder. Covered in Task 2.
- **Locale with a comma decimal separator (de_DE).** Every read-only weight renders "62,5 kg",
  and "kg" never appears when the unit is pounds. Covered in Task 3.
- **A corrupt `deviceRestTimer` row (both columns set).** Loading must throw rather than prefer
  one column, and the controller then clears it. Covered in Task 5.

## Scheduling (for the controller)

Tasks touching disjoint files may run in parallel, each in its own git worktree branched from the
current tip of `FrankieBiz/porgy`. They merge back one at a time, rebased on the tip, with
`Tools/linux-test.sh` rerun after each merge.

| Task | Files owned | Depends on |
|---|---|---|
| 1 Rest plan | Core/RestPlan.swift, CoreTests/RestPlanTests.swift | — |
| 2 Rest reconciler | Core/RestReconciler.swift, CoreTests/RestReconcilerTests.swift | — |
| 3 Weight formatter and copy helpers | Core/WeightFormatter.swift, Core/Progression.swift, Core/MuscleVolume.swift, CoreTests (new file and ProgressionTests), StoreTests/ProgressionStoreTests.swift | — |
| 5 Rest timer persistence | Store/RestTimerStore.swift, StoreTests/RestTimerStoreTests.swift | 2 |
| 6 Failure copy | Store/FailureCopy.swift, StoreTests/FailureCopyTests.swift | — |
| 9 Set row: displayed = saved, logged = locked | UI/SetRowView.swift | — |
| 4 Rest preferences and coordinator | Store/RestPreferences.swift, Store/SessionCoordinator.swift, StoreTests/RestPreferencesTests.swift, StoreTests/SessionCoordinatorTests.swift, plus the mechanical call-site rename in Feature/LiveSessionScreen.swift, Feature/HardsetRootView.swift and Hardset/HardsetApp.swift | 1 |
| 7 Alarm controller | HardsetAlarm/*.swift | 2, 5 |
| 8 Formatter adoption in UI | UI/SessionView.swift, UI/ExerciseSectionView.swift, UI/MachinePickerView.swift, UI/HistoryView.swift, UI/ProgressionChartView.swift, UI/VolumeReportView.swift, plus the one `MachinePickerView(` call site in Feature/LiveSessionScreen.swift | 3, 4, 9 |
| 10 Rest chip | UI/ExerciseSectionView.swift, UI/SessionView.swift, UI/RestBarView.swift | 4, 8 |
| 11 Live session wiring | Feature/LiveSessionScreen.swift, Hardset/HardsetApp.swift, HardsetTests/AppSmokeTests.swift | 4, 6, 7, 10 |
| 12 Root and screen wiring | Feature/HardsetRootView.swift, Feature/WeeklyVolumeScreen.swift, Feature/HistoryScreen.swift | 3, 6, 11 |

Wave 1: 1, 2, 3, 6 and 9 in parallel, then 5 once 2 lands. Wave 2: 4 and 7 in parallel, then 8
once 4 lands (they share LiveSessionScreen.swift). Wave 3: 10. Wave 4: 11, then 12.

**Rule:** no task may leave a caller of an API it changed uncompiled. A task that changes a
signature updates every call site in the same task, even in files another task owns later. Those
edits are mechanical, nothing more.

---

### Task 1: Rest plan (Core)

**Files:**
- Create: `Packages/HardsetKit/Sources/HardsetCore/RestPlan.swift`
- Test: `Packages/HardsetKit/Tests/HardsetCoreTests/RestPlanTests.swift`

**Interfaces:**
- Consumes: `Duration.clockString` (existing, in Core; `"1:36"`-style). `Duration.seconds`
  (existing extension returning `Double`).
- Produces:
  - `public enum RestPlan`
  - `static let presets: [Duration]`
  - `static let allowedRange: ClosedRange<Duration>`
  - `static func validated(_ duration: Duration) -> Duration?`
  - `static func restAfterLogging(isWarmup: Bool, choice: Duration?) -> Duration?`
  - `static func label(for choice: Duration?) -> String`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing

@testable import HardsetCore

@Suite("Rest is the lifter's choice, never the app's")
struct RestPlanTests {
  @Test("With no choice, nothing is requested — there is no default rest")
  func noChoiceNoRest() {
    #expect(RestPlan.restAfterLogging(isWarmup: false, choice: nil) == nil)
  }

  @Test("A chosen rest is requested after a working set")
  func choiceIsRequested() {
    #expect(RestPlan.restAfterLogging(isWarmup: false, choice: .seconds(120)) == .seconds(120))
  }

  @Test("A warm-up never starts a rest, even with a choice")
  func warmupNeverRests() {
    #expect(RestPlan.restAfterLogging(isWarmup: true, choice: .seconds(120)) == nil)
  }

  @Test("Presets are offered as choices; none of them is a default")
  func presetsAreChoicesOnly() {
    #expect(RestPlan.presets == [60, 90, 120, 180, 240, 300].map { Duration.seconds($0) })
    // The refusal is structural: there is no `default` member to reach for.
    #expect(RestPlan.restAfterLogging(isWarmup: false, choice: nil) == nil)
  }

  @Test(
    "Out-of-range choices are refused, not clamped",
    arguments: [0, 5, 14, 1801, 7200]
  )
  func outOfRangeRefused(seconds: Int) {
    #expect(RestPlan.validated(.seconds(seconds)) == nil)
  }

  @Test("In-range choices pass through unchanged", arguments: [15, 61, 120, 1800])
  func inRangeAccepted(seconds: Int) {
    #expect(RestPlan.validated(.seconds(seconds)) == .seconds(seconds))
  }

  @Test("The chip reads Off or a clock time")
  func labels() {
    #expect(RestPlan.label(for: nil) == "Off")
    #expect(RestPlan.label(for: .seconds(90)) == "1:30")
    #expect(RestPlan.label(for: .seconds(120)) == "2:00")
  }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `Tools/linux-test.sh --filter RestPlanTests`
Expected: compile failure, `cannot find 'RestPlan' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Rest between sets, as the lifter chose it.
///
/// There is deliberately no default. A rest prescription is a training decision, and an app that
/// starts a 90-second timer nobody asked for is asserting something it has no basis for
/// (`HANDOFF.md` §6). The presets below are choices offered in a menu; none is preselected, and
/// `restAfterLogging` returns nil until the lifter has picked one.
public enum RestPlan {
  /// What the rest menu offers. A list to choose from, not a recommendation.
  public static let presets: [Duration] = [60, 90, 120, 180, 240, 300].map { .seconds($0) }

  /// The range a custom rest may take. Outside it the value is refused rather than clamped, so a
  /// typo never becomes a silently different rest.
  public static let allowedRange: ClosedRange<Duration> = .seconds(15) ... .seconds(1800)

  /// `duration` if it lies in `allowedRange`, otherwise nil.
  public static func validated(_ duration: Duration) -> Duration? {
    allowedRange.contains(duration) ? duration : nil
  }

  /// The rest to request after a set is logged, or nil to start nothing.
  ///
  /// Warm-ups never rest: the lifter is still warming up.
  public static func restAfterLogging(isWarmup: Bool, choice: Duration?) -> Duration? {
    guard !isWarmup else { return nil }
    return choice
  }

  /// "Off", or the clock time, for the exercise's rest chip.
  public static func label(for choice: Duration?) -> String {
    choice?.clockString ?? "Off"
  }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `Tools/linux-test.sh --filter RestPlanTests`
Expected: all of `RestPlanTests` passes. Then `Tools/linux-test.sh` passes in full.

- [ ] **Step 5: Commit**

```bash
git add Packages/HardsetKit/Sources/HardsetCore/RestPlan.swift \
  Packages/HardsetKit/Tests/HardsetCoreTests/RestPlanTests.swift
git commit -m "feat(core): rest as the lifter's choice, with no default

The rest timer could never start because the only rest source was a nil the app
passed in. The fix must not invent a default, so the rule lives here as a pure
function: nil until chosen, never after a warm-up, refused rather than clamped when
out of range.

Co-Authored-By: <your model's trailer>"
```

---

### Task 2: Rest reconciler (Core)

**Files:**
- Create: `Packages/HardsetKit/Sources/HardsetCore/RestReconciler.swift`
- Test: `Packages/HardsetKit/Tests/HardsetCoreTests/RestReconcilerTests.swift`

**Interfaces:**
- Consumes: `RestTimerState` (existing: `.idle`, `.running(endsAt:)`, `.paused(remaining:)`).
- Produces:
  - `public struct AlarmSnapshot: Hashable, Sendable`, with `id: UUID`, `mode: Mode`, and
    `init(id:mode:)`. `Mode` is `.countdown(fireDate: Date?)`, `.paused(remaining: Duration?)` or
    `.alerting`.
  - `public struct PersistedRest: Hashable, Sendable`, with `state: RestTimerState`,
    `alarmID: UUID?`, and `init(state:alarmID:)`.
  - `public struct RestReconciliation: Hashable, Sendable`, with `state: RestTimerState`,
    `alarmID: UUID?` and `staleAlarmIDs: [UUID]`.
  - `public enum RestReconciler`, with
    `static func reconcile(persisted: PersistedRest?, alarms: [AlarmSnapshot], now: Date) -> RestReconciliation`.

The rules, each a test below:

| | Situation | Result |
|---|---|---|
| R1 | Nothing persisted, no alarms | idle |
| R2 | A matching alarm in countdown with a fire date | running until that date; the alarm is the truth, since the Lock Screen may have paused and resumed it |
| R3 | Matching countdown, no fire date | running until the persisted end time |
| R4 | Matching alarm paused with a known remainder | paused with that remainder |
| R5 | Matching alarm paused, remainder unknown | paused with the persisted remainder if the persisted state is paused; otherwise cancel it and go idle. Never guess. |
| R6 | Matching alarm alerting | idle, not stale; the system is showing the alert |
| R7 | Persisted running or paused, no matching alarm | idle; nothing backs the countdown |
| R8 | Nothing persisted (or idle), exactly one alarm in countdown with a fire date | adopt it; the app died before persisting |
| R9 | Any other alarm | stale |

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing

@testable import HardsetCore

@Suite("The rest timer reconciles with the alarms that actually exist")
struct RestReconcilerTests {
  let now = Date(timeIntervalSince1970: 1_000_000)
  let ours = UUID()
  let other = UUID()

  private func persisted(_ state: RestTimerState, alarm: UUID?) -> PersistedRest {
    PersistedRest(state: state, alarmID: alarm)
  }

  @Test("R1: nothing persisted and no alarms is idle")
  func nothingIsIdle() {
    let result = RestReconciler.reconcile(persisted: nil, alarms: [], now: now)
    #expect(result == RestReconciliation(state: .idle, alarmID: nil, staleAlarmIDs: []))
  }

  @Test("R2: a counting-down alarm's fire date wins over the persisted deadline")
  func alarmDeadlineWins() {
    let fire = now.addingTimeInterval(75)
    let result = RestReconciler.reconcile(
      persisted: persisted(.running(endsAt: now.addingTimeInterval(30)), alarm: ours),
      alarms: [AlarmSnapshot(id: ours, mode: .countdown(fireDate: fire))],
      now: now
    )
    #expect(result.state == .running(endsAt: fire))
    #expect(result.alarmID == ours)
    #expect(result.staleAlarmIDs.isEmpty)
  }

  @Test("R3: a countdown with no readable fire date keeps the persisted deadline")
  func unknownFireDateKeepsPersisted() {
    let endsAt = now.addingTimeInterval(40)
    let result = RestReconciler.reconcile(
      persisted: persisted(.running(endsAt: endsAt), alarm: ours),
      alarms: [AlarmSnapshot(id: ours, mode: .countdown(fireDate: nil))],
      now: now
    )
    #expect(result.state == .running(endsAt: endsAt))
    #expect(result.alarmID == ours)
  }

  @Test("R4: an alarm paused from the Lock Screen is shown paused")
  func pausedElsewhere() {
    let result = RestReconciler.reconcile(
      persisted: persisted(.running(endsAt: now.addingTimeInterval(40)), alarm: ours),
      alarms: [AlarmSnapshot(id: ours, mode: .paused(remaining: .seconds(25)))],
      now: now
    )
    #expect(result.state == .paused(remaining: .seconds(25)))
    #expect(result.alarmID == ours)
  }

  @Test("R5: an unreadable pause keeps a persisted pause")
  func unreadablePauseKeepsPersistedPause() {
    let result = RestReconciler.reconcile(
      persisted: persisted(.paused(remaining: .seconds(50)), alarm: ours),
      alarms: [AlarmSnapshot(id: ours, mode: .paused(remaining: nil))],
      now: now
    )
    #expect(result.state == .paused(remaining: .seconds(50)))
    #expect(result.alarmID == ours)
  }

  @Test("R5: an unreadable pause over a running record is cancelled, never guessed")
  func unreadablePauseIsNotGuessed() {
    let result = RestReconciler.reconcile(
      persisted: persisted(.running(endsAt: now.addingTimeInterval(40)), alarm: ours),
      alarms: [AlarmSnapshot(id: ours, mode: .paused(remaining: nil))],
      now: now
    )
    #expect(result.state == .idle)
    #expect(result.alarmID == nil)
    #expect(result.staleAlarmIDs == [ours])
  }

  @Test("R6: an alerting alarm ends the rest but is left for the system to show")
  func alertingIsIdleNotStale() {
    let result = RestReconciler.reconcile(
      persisted: persisted(.running(endsAt: now.addingTimeInterval(-1)), alarm: ours),
      alarms: [AlarmSnapshot(id: ours, mode: .alerting)],
      now: now
    )
    #expect(result.state == .idle)
    #expect(result.alarmID == nil)
    #expect(result.staleAlarmIDs.isEmpty)
  }

  @Test("R7: a persisted countdown with no alarm behind it is idle")
  func missingAlarmIsIdle() {
    let result = RestReconciler.reconcile(
      persisted: persisted(.running(endsAt: now.addingTimeInterval(60)), alarm: ours),
      alarms: [],
      now: now
    )
    #expect(result == RestReconciliation(state: .idle, alarmID: nil, staleAlarmIDs: []))
  }

  @Test("R8: a lone countdown alarm is adopted when nothing was persisted")
  func loneAlarmAdopted() {
    let fire = now.addingTimeInterval(90)
    let result = RestReconciler.reconcile(
      persisted: nil,
      alarms: [AlarmSnapshot(id: other, mode: .countdown(fireDate: fire))],
      now: now
    )
    #expect(result.state == .running(endsAt: fire))
    #expect(result.alarmID == other)
    #expect(result.staleAlarmIDs.isEmpty)
  }

  @Test("R8: two unexplained alarms are both stale, not adopted")
  func twoUnexplainedAreStale() {
    let result = RestReconciler.reconcile(
      persisted: nil,
      alarms: [
        AlarmSnapshot(id: ours, mode: .countdown(fireDate: now.addingTimeInterval(10))),
        AlarmSnapshot(id: other, mode: .countdown(fireDate: now.addingTimeInterval(20))),
      ],
      now: now
    )
    #expect(result.state == .idle)
    #expect(Set(result.staleAlarmIDs) == [ours, other])
  }

  @Test("R9: alarms other than ours are stale")
  func othersAreStale() {
    let fire = now.addingTimeInterval(30)
    let result = RestReconciler.reconcile(
      persisted: persisted(.running(endsAt: fire), alarm: ours),
      alarms: [
        AlarmSnapshot(id: ours, mode: .countdown(fireDate: fire)),
        AlarmSnapshot(id: other, mode: .countdown(fireDate: now.addingTimeInterval(500))),
      ],
      now: now
    )
    #expect(result.state == .running(endsAt: fire))
    #expect(result.staleAlarmIDs == [other])
  }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `Tools/linux-test.sh --filter RestReconcilerTests`
Expected: compile failure, `cannot find 'RestReconciler' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// What AlarmKit reports about one alarm, reduced to what reconciliation needs.
///
/// A mirror rather than AlarmKit's own type, because AlarmKit exists only in the iPhoneOS SDK and
/// this logic must be testable off-device. Optional details are optional on purpose: when the
/// framework does not expose a value, the reconciler is told so rather than handed a guess.
public struct AlarmSnapshot: Hashable, Sendable {
  public enum Mode: Hashable, Sendable {
    case countdown(fireDate: Date?)
    case paused(remaining: Duration?)
    case alerting
  }

  public let id: UUID
  public let mode: Mode

  public init(id: UUID, mode: Mode) {
    self.id = id
    self.mode = mode
  }
}

/// The rest timer as it was last written to the device.
public struct PersistedRest: Hashable, Sendable {
  public let state: RestTimerState
  public let alarmID: UUID?

  public init(state: RestTimerState, alarmID: UUID?) {
    self.state = state
    self.alarmID = alarmID
  }
}

/// The corrected rest state, and the alarms nothing on screen accounts for.
public struct RestReconciliation: Hashable, Sendable {
  public let state: RestTimerState
  public let alarmID: UUID?
  /// Alarms to cancel. Leaving them would ring for a rest the app no longer shows.
  public let staleAlarmIDs: [UUID]

  public init(state: RestTimerState, alarmID: UUID?, staleAlarmIDs: [UUID]) {
    self.state = state
    self.alarmID = alarmID
    self.staleAlarmIDs = staleAlarmIDs
  }
}

/// Decides what the rest timer really is, from what was persisted and what alarms exist.
///
/// Runs at launch and on every AlarmKit update. Without it a force-quit relaunched the app idle
/// while an alarm still counted down, and a pause from the Lock Screen left the app showing a
/// deadline that no longer existed. The rule throughout: the alarm is the truth when it can be
/// read, the persisted record fills only what the alarm cannot say, and nothing is guessed.
public enum RestReconciler {
  public static func reconcile(
    persisted: PersistedRest?,
    alarms: [AlarmSnapshot],
    now: Date
  ) -> RestReconciliation {
    let matched = persisted?.alarmID.flatMap { id in alarms.first { $0.id == id } }

    guard let alarm = matched else {
      return adoptOrDiscard(persisted: persisted, alarms: alarms)
    }
    let others = alarms.map(\.id).filter { $0 != alarm.id }

    switch alarm.mode {
    case .countdown(let fireDate?):
      return RestReconciliation(
        state: .running(endsAt: fireDate), alarmID: alarm.id, staleAlarmIDs: others)
    case .countdown(nil):
      // The alarm exists and is counting; only the persisted deadline says when it ends.
      guard case .running = persisted?.state else {
        return RestReconciliation(state: .idle, alarmID: nil, staleAlarmIDs: [alarm.id] + others)
      }
      return RestReconciliation(
        state: persisted!.state, alarmID: alarm.id, staleAlarmIDs: others)
    case .paused(let remaining?):
      return RestReconciliation(
        state: .paused(remaining: remaining), alarmID: alarm.id, staleAlarmIDs: others)
    case .paused(nil):
      // A remainder we cannot read is never invented from a deadline.
      if case .paused = persisted?.state {
        return RestReconciliation(
          state: persisted!.state, alarmID: alarm.id, staleAlarmIDs: others)
      }
      return RestReconciliation(state: .idle, alarmID: nil, staleAlarmIDs: [alarm.id] + others)
    case .alerting:
      // The rest is over and the system is presenting the alert. Cancelling it here would
      // silence the very alert the lifter is waiting for.
      return RestReconciliation(state: .idle, alarmID: nil, staleAlarmIDs: others)
    }
  }

  /// No persisted alarm matched. Adopt a single explicable countdown, discard the rest.
  private static func adoptOrDiscard(
    persisted: PersistedRest?, alarms: [AlarmSnapshot]
  ) -> RestReconciliation {
    let persistedIsIdle = persisted == nil || persisted?.state == .idle
    if persistedIsIdle, alarms.count == 1, case .countdown(let fireDate?) = alarms[0].mode {
      // The app died between scheduling and persisting. One countdown is explicable; it is ours.
      return RestReconciliation(
        state: .running(endsAt: fireDate), alarmID: alarms[0].id, staleAlarmIDs: [])
    }
    return RestReconciliation(state: .idle, alarmID: nil, staleAlarmIDs: alarms.map(\.id))
  }
}
```

Note R6's alerting branch: an alerting alarm that did *not* match falls through
`adoptOrDiscard`, where it is cancelled as stale. Only the matched one is left to ring.

- [ ] **Step 4: Run to verify pass**

Run: `Tools/linux-test.sh --filter RestReconcilerTests`, then `Tools/linux-test.sh`.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/HardsetKit/Sources/HardsetCore/RestReconciler.swift \
  Packages/HardsetKit/Tests/HardsetCoreTests/RestReconcilerTests.swift
git commit -m "feat(core): reconcile the rest timer with the alarms that exist

The app never read AlarmKit back, so after a force-quit it relaunched idle while an
alarm still rang, and a Lock Screen pause left it showing a deadline that no longer
existed. The rules are pure so they can be tested here: the alarm is the truth when
readable, the persisted record fills only what it cannot say, and a remainder is
never guessed.

Co-Authored-By: <your model's trailer>"
```

---

### Task 3: Weight formatter and honest copy helpers (Core)

**Files:**
- Create: `Packages/HardsetKit/Sources/HardsetCore/WeightFormatter.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetCore/Progression.swift:109-121` (`MachineChange`)
- Modify: `Packages/HardsetKit/Sources/HardsetCore/MuscleVolume.swift` (add
  `MuscleVolumeReport.highestCertainty`)
- Create: `Packages/HardsetKit/Tests/HardsetCoreTests/WeightFormatterTests.swift`
- Modify: `Packages/HardsetKit/Tests/HardsetCoreTests/ProgressionTests.swift:131-163`
  (`explanation` → `explanation(in:)`)
- Modify: `Packages/HardsetKit/Tests/HardsetStoreTests/ProgressionStoreTests.swift:91`

**Interfaces:**
- Consumes: `WeightUnit.fromKilograms`, `WeightUnit.abbreviation`,
  `StrengthMath.displayRounded(_:in:)`, `SetCounting.certaintyCeiling(for:fractionalSets:)`,
  `MuscleKey` (read `Sources/HardsetCore/MuscleTaxonomy.swift` for how a key yields its
  `Muscle`, if known).
- Produces:
  - `public struct WeightFormatter: Hashable, Sendable`, with `init(unit:locale:)`,
    `func load(kilograms:) -> String` ("62.5 kg"), `func number(kilograms:) -> String`
    ("62.5"), `func estimate(kilograms:) -> String` ("about 80 kg"), and
    `func spoken(kilograms:) -> String` ("62.5 kilograms").
  - `public enum CountText`, with `static func sets(_:) -> String` and
    `static func reps(_:) -> String`.
  - `MachineChange.explanation(in unit: WeightUnit, locale: Locale = .current) -> String`.
    This replaces the `explanation` property.
  - `MuscleVolumeReport.highestCertainty: Certainty?`.

Rules:
- `load` and `number` show what was logged: up to two fraction digits, trailing zeros trimmed,
  with the locale's decimal separator and no grouping.
- `estimate` is for derived values. It rounds through `StrengthMath.displayRounded` (kg to 0.5,
  lb to 1), because a derived number must not look like a measurement.
- `spoken` uses the full unit name ("kilograms"/"pounds"; "kilogram"/"pound" for exactly 1).

- [ ] **Step 1: Write the failing tests**

`WeightFormatterTests.swift`:

```swift
import Foundation
import Testing

@testable import HardsetCore

@Suite("Weights render in the lifter's unit, and only in it")
struct WeightFormatterTests {
  let posix = Locale(identifier: "en_US_POSIX")
  let german = Locale(identifier: "de_DE")

  @Test("Kilograms render as logged, trailing zeros trimmed")
  func kilograms() {
    let f = WeightFormatter(unit: .kilograms, locale: posix)
    #expect(f.load(kilograms: 60) == "60 kg")
    #expect(f.load(kilograms: 62.5) == "62.5 kg")
    #expect(f.load(kilograms: 61.25) == "61.25 kg")
    #expect(f.number(kilograms: 60) == "60")
  }

  @Test("Pounds are converted, and 'kg' never appears")
  func pounds() {
    let f = WeightFormatter(unit: .pounds, locale: posix)
    // 135 lb typed, stored as kilograms, read back: exactly 135.
    #expect(f.load(kilograms: WeightUnit.pounds.toKilograms(135)) == "135 lb")
    #expect(f.load(kilograms: 60) == "132.28 lb")
    #expect(!f.load(kilograms: 60).contains("kg"))
  }

  @Test("The locale's decimal separator is used")
  func localeSeparator() {
    let f = WeightFormatter(unit: .kilograms, locale: german)
    #expect(f.load(kilograms: 62.5) == "62,5 kg")
  }

  @Test("Large loads are not grouped, matching what the keypad accepts")
  func noGrouping() {
    let f = WeightFormatter(unit: .pounds, locale: posix)
    #expect(f.number(kilograms: WeightUnit.pounds.toKilograms(1100)) == "1100")
  }

  @Test("Estimates round to display precision and say they are estimates")
  func estimates() {
    #expect(WeightFormatter(unit: .kilograms, locale: posix).estimate(kilograms: 80.26) == "about 80.5 kg")
    #expect(WeightFormatter(unit: .pounds, locale: posix).estimate(kilograms: 80) == "about 176 lb")
  }

  @Test("VoiceOver hears the unit's name, not its abbreviation")
  func spoken() {
    #expect(WeightFormatter(unit: .kilograms, locale: posix).spoken(kilograms: 62.5) == "62.5 kilograms")
    #expect(WeightFormatter(unit: .kilograms, locale: posix).spoken(kilograms: 1) == "1 kilogram")
    #expect(WeightFormatter(unit: .pounds, locale: posix).spoken(kilograms: WeightUnit.pounds.toKilograms(1)) == "1 pound")
  }
}

@Suite("Counts agree with their nouns")
struct CountTextTests {
  @Test("Sets", arguments: [(0, "0 sets"), (1, "1 set"), (2, "2 sets")])
  func sets(count: Int, expected: String) { #expect(CountText.sets(count) == expected) }

  @Test("Reps", arguments: [(1, "1 rep"), (8, "8 reps")])
  func reps(count: Int, expected: String) { #expect(CountText.reps(count) == expected) }
}

@Suite("A report states the most any of its figures can claim")
struct HighestCertaintyTests {
  @Test("An empty report claims nothing")
  func emptyClaimsNothing() {
    let report = MuscleVolumeReport(
      fractionalSets: [:], hardSets: 0, unattributedHardSets: 0, setsTouchingGroup: [:])
    #expect(report.highestCertainty == nil)
  }

  @Test("Only counted muscles: low, never the old hardcoded moderate")
  func countedIsLow() {
    let counted = Muscle.allCases.first { $0.tier != .modelled }!
    let report = MuscleVolumeReport(
      fractionalSets: [MuscleKey(counted): 6], hardSets: 6, unattributedHardSets: 0,
      setsTouchingGroup: [:])
    #expect(report.highestCertainty == .low)
  }

  @Test("A modelled muscle in range lifts the ceiling to moderate, never high")
  func modelledIsModerate() {
    let modelled = Muscle.allCases.first { $0.tier == .modelled }!
    let report = MuscleVolumeReport(
      fractionalSets: [MuscleKey(modelled): 10], hardSets: 10, unattributedHardSets: 0,
      setsTouchingGroup: [:])
    #expect(report.highestCertainty == .moderate)
  }
}
```

In `ProgressionTests.swift`, replace each `change.explanation` with
`change.explanation(in: .kilograms, locale: Locale(identifier: "en_US_POSIX"))`, and add:

```swift
  @Test("The machine-change sentence speaks the lifter's unit")
  func machineChangeInPounds() {
    let change = MachineChange(
      date: Date(timeIntervalSince1970: 0), fromMachineID: nil, toMachineID: nil,
      heaviestLoadDeltaKg: WeightUnit.pounds.toKilograms(20))
    let text = change.explanation(in: .pounds, locale: Locale(identifier: "en_US_POSIX"))
    #expect(text.contains("20 lb higher"))
    #expect(!text.contains("kg"))
  }
```

In `ProgressionStoreTests.swift:91`, replace `.explanation` with
`.explanation(in: .kilograms, locale: Locale(identifier: "en_US_POSIX"))`.

- [ ] **Step 2: Run to verify failure**

Run: `Tools/linux-test.sh --filter "WeightFormatterTests|CountTextTests|HighestCertaintyTests|ProgressionTests"`
Expected: compile failures (`cannot find 'WeightFormatter'`, `'explanation(in:locale:)'`).

- [ ] **Step 3: Implement**

`WeightFormatter.swift`:

```swift
import Foundation

/// The one way a weight becomes text.
///
/// Six local `format(_:)` helpers had grown across the UI, and every one hard-coded "kg", so a
/// lifter who chose pounds still read kilograms in the PR banner, the machine picker and the
/// machine-change note. Conversion stays in `WeightUnit`; this owns only presentation.
public struct WeightFormatter: Hashable, Sendable {
  public let unit: WeightUnit
  public let locale: Locale

  public init(unit: WeightUnit, locale: Locale = .current) {
    self.unit = unit
    self.locale = locale
  }

  /// A logged or typed load: "62.5 kg". Up to two decimals, so 61.25 kg reads as entered.
  public func load(kilograms: Double) -> String {
    "\(number(kilograms: kilograms)) \(unit.abbreviation)"
  }

  /// The number alone, for fields that draw the unit separately.
  public func number(kilograms: Double) -> String {
    Self.text(unit.fromKilograms(kilograms), fractionDigits: 2, locale: locale)
  }

  /// A derived load: "about 80.5 kg". Rounded to display precision, because an estimate shown to
  /// 10 g reads as a measurement (guideline 1.4.1).
  public func estimate(kilograms: Double) -> String {
    let rounded = StrengthMath.displayRounded(kilograms, in: unit)
    return "about \(Self.text(rounded, fractionDigits: 1, locale: locale)) \(unit.abbreviation)"
  }

  /// For VoiceOver: "62.5 kilograms".
  public func spoken(kilograms: Double) -> String {
    let value = unit.fromKilograms(kilograms)
    let isOne = (value * 100).rounded() == 100
    let name: String
    switch unit {
    case .kilograms: name = isOne ? "kilogram" : "kilograms"
    case .pounds: name = isOne ? "pound" : "pounds"
    }
    return "\(Self.text(value, fractionDigits: 2, locale: locale)) \(name)"
  }

  static func text(_ value: Double, fractionDigits: Int, locale: Locale) -> String {
    value.formatted(
      .number
        .precision(.fractionLength(0...fractionDigits))
        .grouping(.never)
        .locale(locale)
    )
  }
}

/// Counts with the noun agreeing. "1 sets" reached the history screen.
public enum CountText {
  public static func sets(_ count: Int) -> String { count == 1 ? "1 set" : "\(count) sets" }
  public static func reps(_ count: Int) -> String { count == 1 ? "1 rep" : "\(count) reps" }
}
```

In `Progression.swift`, replace `public var explanation: String { … }` and `static func format`:

```swift
  /// The sentence the chart must show, in the lifter's unit. Deliberately refuses to characterise
  /// the change as progress or regression, because across a machine switch it is neither.
  public func explanation(in unit: WeightUnit, locale: Locale = .current) -> String {
    let direction = heaviestLoadDeltaKg >= 0 ? "higher" : "lower"
    let magnitude = abs(heaviestLoadDeltaKg)
    guard magnitude > 0 else {
      return "You changed machines here. The load happened to match, which is a coincidence, not a comparison."
    }
    let load = WeightFormatter(unit: unit, locale: locale).load(kilograms: magnitude)
    return "You changed machines here. The load is \(load) \(direction), which is a difference between the machines rather than a change in strength."
  }
```

In `MuscleVolume.swift`, add to `MuscleVolumeReport`:

```swift
  /// The most certainty any per-muscle figure in this report can claim, or nil when nothing was
  /// credited. The methodology sheet used to hard-code "Moderate", which overstated every counted
  /// muscle — 16 of the 22 cap at low.
  public var highestCertainty: Certainty? {
    fractionalSets.compactMap { key, sets in
      key.muscle.map { SetCounting.certaintyCeiling(for: $0, fractionalSets: sets) }
    }.max()
  }
```

`key.muscle` is a placeholder name. Use whatever `MuscleKey` exposes for its known `Muscle`
(read `MuscleTaxonomy.swift:213-250`). If it exposes none, add a minimal `public var muscle:
Muscle?` that returns `Muscle(rawValue: storedValue)`. `Certainty` is `Comparable` already
(`Certainty.swift:10`).

- [ ] **Step 4: Run to verify pass**

Run: `Tools/linux-test.sh`
Expected: PASS, including the updated progression tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/HardsetKit/Sources/HardsetCore Packages/HardsetKit/Tests
git commit -m "feat(core): one weight formatter, so pounds mode stops reading kilograms

The PR banner, machine picker, step chip and machine-change note all hard-coded kg.
Formatting now has one owner, aware of unit and locale, and the machine-change
sentence takes the unit. Adds the report's highest certainty so the methodology
sheet can stop claiming Moderate for muscles that cap at Low.

Co-Authored-By: <your model's trailer>"
```

---

### Task 4: Rest preferences and the coordinator (Store)

**Files:**
- Create: `Packages/HardsetKit/Sources/HardsetStore/RestPreferences.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetStore/SessionCoordinator.swift`
  - `init` (lines 64–80), `start` (85–143), `resume` (154–240): replace the parameter
    `restAfterSet: Duration?` with `restPreferences: any RestPreferenceStore`
  - `addExercise`: load the new exercise's choice
  - `logSet` rest block (lines 364–376): replace `if let restAfterSet …`
  - add `restChoices`, `activeRest`, `setRestChoice`, `startRest` and `endRest`
- Create: `Packages/HardsetKit/Tests/HardsetStoreTests/RestPreferencesTests.swift`
- Modify: `Packages/HardsetKit/Tests/HardsetStoreTests/SessionCoordinatorTests.swift` (the three
  `restAfterSet: .seconds(120)` call sites at 106, 140 and 167; `noRestByDefault`)
- Modify (call sites only, mechanical — see Step 5):
  - `Packages/HardsetKit/Sources/HardsetFeature/LiveSessionScreen.swift`: the
    `extension SessionCoordinator` convenience `start(...restAfterSet:hooks:now:)` takes
    `restPreferences: any RestPreferenceStore` instead.
  - `Packages/HardsetKit/Sources/HardsetFeature/HardsetRootView.swift`: the `restAfterSet` init
    parameter and stored property become
    `restPreferences: any RestPreferenceStore = InMemoryRestPreferences()`, passed at the
    `resume` and `start` call sites.
  - `Hardset/HardsetApp.swift`: delete the `restAfterSet: nil` argument and its comment. The
    default applies until Task 11 passes `UserDefaultsRestPreferences()`.
- Modify: `docs/MAC-VERIFICATION.md`

**Interfaces:**
- Consumes: `RestPlan.restAfterLogging(isWarmup:choice:)` and `RestPlan.validated` (Task 1).
- Produces:
  - `public protocol RestPreferenceStore: AnyObject, Sendable`, with
    `func rest(for exercise: ExerciseID) -> Duration?` and
    `func setRest(_ rest: Duration?, for exercise: ExerciseID)`.
  - `public final class UserDefaultsRestPreferences: RestPreferenceStore`, with
    `init(defaults: UserDefaults = .standard)`.
  - `public final class InMemoryRestPreferences: RestPreferenceStore`, with
    `init(_ initial: [ExerciseID: Duration] = [:])`.
  - On `SessionCoordinator`:
    - `public private(set) var restChoices: [ExerciseID: Duration]`
    - `public private(set) var activeRest: RestMetadata?`
    - `public func setRestChoice(_ rest: Duration?, forExercise stateID: UUID)`
    - `@discardableResult public func startRest(forExercise stateID: UUID) -> Bool`
    - `public func endRest()`
  - The parameter label `restPreferences:` on `init`, `start` and `resume`, defaulting to
    `InMemoryRestPreferences()`.

`UserDefaultsRestPreferences` stores an `Int` of whole seconds under
`"hardset.rest.\(exercise.rawValue.uuidString)"`, and removes the key for nil. It is device-local
and needs no schema change; UserDefaults is already declared as CA92.1. Mark the class
`nonisolated` and `@unchecked Sendable`, with a comment that `UserDefaults` is documented as
thread-safe. `InMemoryRestPreferences` guards its dictionary with a `Mutex` from the
`Synchronization` module, which `SyncSetup.swift` already imports.

HardsetStore defaults to MainActor isolation, so the protocol must not inherit it. Declare it
`public nonisolated protocol RestPreferenceStore` if the compiler accepts that; otherwise mark
each requirement `nonisolated`. The Linux build tells you which.

- [ ] **Step 1: Write the failing tests**

`RestPreferencesTests.swift`:

```swift
import Foundation
import HardsetCore
import Testing

@testable import HardsetStore

@Suite("A rest choice is remembered per exercise, on this device")
struct RestPreferencesTests {
  private func freshDefaults() -> UserDefaults {
    UserDefaults(suiteName: "hardset.tests.\(UUID().uuidString)")!
  }

  @Test("Nothing chosen reads as nil, not as a default")
  func nothingChosen() {
    let store = UserDefaultsRestPreferences(defaults: freshDefaults())
    #expect(store.rest(for: ExerciseID()) == nil)
  }

  @Test("A choice round-trips and is per exercise")
  func roundTrip() {
    let defaults = freshDefaults()
    let a = ExerciseID(), b = ExerciseID()
    UserDefaultsRestPreferences(defaults: defaults).setRest(.seconds(150), for: a)
    let reread = UserDefaultsRestPreferences(defaults: defaults)
    #expect(reread.rest(for: a) == .seconds(150))
    #expect(reread.rest(for: b) == nil)
  }

  @Test("Turning rest off forgets the choice")
  func offForgets() {
    let store = UserDefaultsRestPreferences(defaults: freshDefaults())
    let a = ExerciseID()
    store.setRest(.seconds(90), for: a)
    store.setRest(nil, for: a)
    #expect(store.rest(for: a) == nil)
  }
}
```

In `SessionCoordinatorTests.swift`, the three tests that pass `restAfterSet: .seconds(120)`
instead pass `restPreferences: InMemoryRestPreferences([exercise: .seconds(120)])`. The
assertions stay the same. Update `noRestByDefault` to pass `restPreferences:
InMemoryRestPreferences()` explicitly, keeping its assertion that no rest is requested. Then add
these tests to the suite:

```swift
  @Test("Choosing a rest persists it and applies it to the next working set")
  func choosingRestApplies() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    let prefs = InMemoryRestPreferences()
    let spy = RestSpy()
    let coordinator = try SessionCoordinator.start(
      store: store,
      plan: [PlannedExercise(exerciseID: exercise, exerciseName: "Leg Press", plannedSets: 2)],
      now: { self.start },
      restPreferences: prefs,
      onStartRest: { spy.requests.append(($0, $1)) }
    )
    let stateID = coordinator.exercises[0].id
    #expect(coordinator.restChoices[exercise] == nil)

    coordinator.setRestChoice(.seconds(150), forExercise: stateID)
    #expect(coordinator.restChoices[exercise] == .seconds(150))
    #expect(prefs.rest(for: exercise) == .seconds(150))

    coordinator.exercises[0].slots[0].draft = SetEntryDraft(weightKg: 100, reps: 8)
    #expect(coordinator.logSet(slotID: coordinator.exercises[0].slots[0].id, inExercise: stateID))
    #expect(spy.requests.map(\.0) == [.seconds(150)])
    #expect(coordinator.activeRest?.exerciseName == "Leg Press")
  }

  @Test("A remembered choice is loaded when the session starts")
  func rememberedChoiceLoads() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    let coordinator = try SessionCoordinator.start(
      store: store,
      plan: [PlannedExercise(exerciseID: exercise, exerciseName: "Leg Press")],
      now: { self.start },
      restPreferences: InMemoryRestPreferences([exercise: .seconds(90)])
    )
    #expect(coordinator.restChoices[exercise] == .seconds(90))
  }

  @Test("A movement added mid-session gets its remembered choice too")
  func addedExerciseLoadsChoice() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let first = try seedExercise(database, name: "Leg Press")
    let second = try seedExercise(database, name: "Leg Curl")
    let coordinator = try SessionCoordinator.start(
      store: store,
      plan: [PlannedExercise(exerciseID: first, exerciseName: "Leg Press")],
      now: { self.start },
      restPreferences: InMemoryRestPreferences([second: .seconds(60)])
    )
    coordinator.addExercise(
      CatalogEntry(id: second, name: "Leg Curl", primaryMuscle: nil, isCurated: false))
    #expect(coordinator.restChoices[second] == .seconds(60))
  }

  @Test("Two blocks of one movement share one choice")
  func blocksShareChoice() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    let coordinator = try SessionCoordinator.start(
      store: store,
      plan: [
        PlannedExercise(exerciseID: exercise, exerciseName: "Leg Press"),
        PlannedExercise(exerciseID: exercise, exerciseName: "Leg Press"),
      ],
      now: { self.start },
      restPreferences: InMemoryRestPreferences()
    )
    coordinator.setRestChoice(.seconds(120), forExercise: coordinator.exercises[1].id)
    #expect(coordinator.restChoices[exercise] == .seconds(120))
  }

  @Test("An out-of-range choice is refused and nothing is stored")
  func outOfRangeRefused() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    let prefs = InMemoryRestPreferences()
    let coordinator = try SessionCoordinator.start(
      store: store,
      plan: [PlannedExercise(exerciseID: exercise, exerciseName: "Leg Press")],
      now: { self.start },
      restPreferences: prefs
    )
    coordinator.setRestChoice(.seconds(5), forExercise: coordinator.exercises[0].id)
    #expect(coordinator.restChoices[exercise] == nil)
    #expect(prefs.rest(for: exercise) == nil)
  }

  @Test("Starting a rest by hand needs a choice, and records what is resting")
  func manualStart() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    let spy = RestSpy()
    let coordinator = try SessionCoordinator.start(
      store: store,
      plan: [PlannedExercise(exerciseID: exercise, exerciseName: "Leg Press", plannedSets: 3)],
      now: { self.start },
      restPreferences: InMemoryRestPreferences(),
      onStartRest: { spy.requests.append(($0, $1)) }
    )
    let stateID = coordinator.exercises[0].id
    // No choice yet: nothing to start, and nothing invented.
    #expect(!coordinator.startRest(forExercise: stateID))
    #expect(spy.requests.isEmpty)

    coordinator.setRestChoice(.seconds(90), forExercise: stateID)
    #expect(coordinator.startRest(forExercise: stateID))
    #expect(spy.requests.map(\.0) == [.seconds(90)])
    #expect(coordinator.activeRest?.exerciseName == "Leg Press")

    coordinator.endRest()
    #expect(coordinator.activeRest == nil)
  }

  @Test("A refused write starts no rest and sets no active rest")
  func refusedWriteNoActiveRest() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    let coordinator = try SessionCoordinator.start(
      store: store,
      plan: [PlannedExercise(exerciseID: exercise, exerciseName: "Leg Press")],
      now: { self.start },
      restPreferences: InMemoryRestPreferences([exercise: .seconds(120)])
    )
    let state = coordinator.exercises[0]
    #expect(!coordinator.logSet(slotID: state.slots[0].id, inExercise: state.id))
    #expect(coordinator.activeRest == nil)
  }
```

Check `addExercise`'s real signature and the `CatalogEntry` initialiser in
`SessionCoordinator.swift:~285` and `Sources/HardsetCore/CatalogEntry.swift`, and adjust the
`addedExerciseLoadsChoice` call to match. The assertion stays the same.

- [ ] **Step 2: Run to verify failure**

Run: `Tools/linux-test.sh --filter "RestPreferencesTests|SessionCoordinatorTests"`
Expected: compile failures for `UserDefaultsRestPreferences`, `restPreferences:` and `restChoices`.

- [ ] **Step 3: Implement**

`RestPreferences.swift`:

```swift
import Foundation
import HardsetCore
import Synchronization

/// Where the lifter's rest choice for each exercise is remembered.
///
/// Device-local on purpose. A rest preference is not training data, so it does not justify a
/// permanent synced column (`DECISIONS.md` §4: the schema is additive-only forever). And
/// `UserDefaults` is already declared in the privacy manifest (CA92.1).
public protocol RestPreferenceStore: AnyObject, Sendable {
  func rest(for exercise: ExerciseID) -> Duration?
  func setRest(_ rest: Duration?, for exercise: ExerciseID)
}

/// `UserDefaults` is documented as thread-safe, which is what makes `@unchecked` honest here.
public nonisolated final class UserDefaultsRestPreferences: RestPreferenceStore, @unchecked Sendable {
  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  public func rest(for exercise: ExerciseID) -> Duration? {
    let seconds = defaults.integer(forKey: Self.key(exercise))
    // `integer(forKey:)` returns 0 for a missing key, and 0 is never a valid rest.
    return seconds > 0 ? .seconds(seconds) : nil
  }

  public func setRest(_ rest: Duration?, for exercise: ExerciseID) {
    if let rest {
      defaults.set(Int(rest.components.seconds), forKey: Self.key(exercise))
    } else {
      defaults.removeObject(forKey: Self.key(exercise))
    }
  }

  private static func key(_ exercise: ExerciseID) -> String {
    "hardset.rest.\(exercise.rawValue.uuidString)"
  }
}

/// For tests and previews.
public nonisolated final class InMemoryRestPreferences: RestPreferenceStore {
  private let storage: Mutex<[ExerciseID: Duration]>

  public init(_ initial: [ExerciseID: Duration] = [:]) {
    storage = Mutex(initial)
  }

  public func rest(for exercise: ExerciseID) -> Duration? {
    storage.withLock { $0[exercise] }
  }

  public func setRest(_ rest: Duration?, for exercise: ExerciseID) {
    storage.withLock { $0[exercise] = rest }
  }
}
```

In `SessionCoordinator.swift`:
1. Replace `private let restAfterSet: Duration?` with
   `private let restPreferences: any RestPreferenceStore`.
2. Add the published state, with doc comments:
   ```swift
   /// The lifter's rest choice per exercise, loaded once at start so the chip renders without
   /// touching storage. Two blocks of one movement share an entry — the choice is per exercise.
   public private(set) var restChoices: [ExerciseID: Duration] = [:]
   /// What is resting right now, set only after the rest was actually requested.
   public private(set) var activeRest: RestMetadata?
   ```
3. In `init`, take `restPreferences: any RestPreferenceStore = InMemoryRestPreferences()` instead
   of `restAfterSet`. After assigning, build `restChoices`: for each exercise's `exerciseID` with a
   non-nil `restPreferences.rest(for:)`, store it.
4. In `start` and `resume`, rename the parameter the same way and pass it through.
5. In `addExercise`, after appending, call `loadRestChoice(for: entry.id)`. That helper reads the
   preference and stores it in `restChoices` if it is non-nil.
6. Replace the rest block in `logSet`:
   ```swift
      // Rest only if the lifter chose one for this exercise; never after a warm-up.
      if let rest = RestPlan.restAfterLogging(
        isWarmup: slot.isWarmup, choice: restChoices[exercise.exerciseID])
      {
        requestRest(rest, forExerciseAt: exerciseIndex, slotID: slotID)
      }
   ```
7. Add:
   ```swift
  // MARK: - Rest

  /// Persists the lifter's choice for this movement, or forgets it when `rest` is nil.
  /// Out-of-range values are refused rather than clamped.
  public func setRestChoice(_ rest: Duration?, forExercise stateID: UUID) {
    guard let exercise = exercises.first(where: { $0.id == stateID }) else {
      lastError = SessionCoordinatorError.unknownExercise
      return
    }
    let validated = rest.flatMap(RestPlan.validated)
    guard rest == nil || validated != nil else { return }
    restPreferences.setRest(validated, for: exercise.exerciseID)
    restChoices[exercise.exerciseID] = validated
  }

  /// Starts this exercise's chosen rest now. Returns false, and starts nothing, without a choice.
  @discardableResult
  public func startRest(forExercise stateID: UUID) -> Bool {
    guard let index = exercises.firstIndex(where: { $0.id == stateID }),
      let rest = restChoices[exercises[index].exerciseID]
    else { return false }
    requestRest(rest, forExerciseAt: index, slotID: nil)
    return true
  }

  /// The rest ended, was skipped, or the workout finished.
  public func endRest() { activeRest = nil }

  private func requestRest(_ rest: Duration, forExerciseAt index: Int, slotID: UUID?) {
    let exercise = exercises[index]
    let ordinal =
      slotID.flatMap { exercises[index].workingOrdinal(ofSlotID: $0) }
      ?? max(1, exercise.slots.filter { $0.isLogged && !$0.isWarmup }.count)
    let metadata = RestMetadata(
      exerciseName: exercise.exerciseName,
      setOrdinal: ordinal,
      plannedSets: exercises[index].workingSetCount,
      machineName: exercise.machineName
    )
    onStartRest(rest, metadata)
    activeRest = metadata
  }
   ```
   Check that `SetSlot` really exposes `isLogged` and `isWarmup` (`ExerciseLogState.swift:4-33`).
   Keep `requestRest` the only place `onStartRest` is called.

- [ ] **Step 4: Run to verify pass**

Run: `Tools/linux-test.sh`
Expected: PASS. The full suite matters here, because `resume` and `start` have many callers in
other store tests. Any call site still passing `restAfterSet:` fails to compile; update it to
`restPreferences: InMemoryRestPreferences([...])`, with the same exercise and duration.

- [ ] **Step 5: Rename the Feature and app call sites (mechanical)**

In the three files listed under Files, replace `restAfterSet` with `restPreferences` exactly as
described, with no other edits. Afterwards `rg -n restAfterSet Packages Hardset` must return
nothing.

These files cannot compile on Linux, so add to `docs/MAC-VERIFICATION.md` under `## Phase 1`:

```markdown
- [ ] (feat(store): remember each exercise's rest…) HardsetFeature and the app build after the
      restAfterSet → restPreferences rename.
```

- [ ] **Step 6: Commit**

```bash
git add Packages/HardsetKit/Sources Packages/HardsetKit/Tests/HardsetStoreTests \
  Hardset/HardsetApp.swift docs/MAC-VERIFICATION.md
git commit -m "feat(store): remember each exercise's rest, and publish what is resting

The rest timer was unreachable: the coordinator took one optional duration and the
app passed nil. Rest is now the lifter's per-exercise choice, remembered on this
device, loaded once at start so the chip renders without touching storage, and
requested only after a successful write. activeRest replaces a view-local field
that nothing ever set, which is why the rest bar's caption was always empty.

Co-Authored-By: <your model's trailer>"
```

---

### Task 5: Rest timer persistence (Store)

**Files:**
- Create: `Packages/HardsetKit/Sources/HardsetStore/RestTimerStore.swift`
- Test: `Packages/HardsetKit/Tests/HardsetStoreTests/RestTimerStoreTests.swift`

**Interfaces:**
- Consumes:
  - `PersistedRest` (Task 2)
  - `RestTimerState.storage` and
    `RestTimerState.init(endsAt:pausedRemainingSeconds:) throws` (existing)
  - the internal `@Table("deviceRestTimer") DeviceRestTimer` (`Schema.swift:130`)
- Produces: `public nonisolated struct RestTimerStore`, with
  - `init(database: any DatabaseWriter)`
  - `func load() throws -> PersistedRest?`, returning nil when there is no row or the row is idle
  - `func save(_ rest: PersistedRest, at now: Date) throws`; saving an idle state deletes the row
  - `func clear() throws`

One row, with a fixed id: `static let rowID = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!`.
Match the style of `GymStore`: a `nonisolated struct` holding the database, using `@Table`
queries, never returning the row type.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

@Suite("The rest timer survives the process that started it")
struct RestTimerStoreTests {
  private func migratedDatabase() throws -> any DatabaseWriter {
    var configuration = Configuration.forTesting()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return queue
  }

  let now = Date(timeIntervalSince1970: 2_000_000)

  @Test("Nothing saved loads as nil")
  func emptyIsNil() throws {
    #expect(try RestTimerStore(database: migratedDatabase()).load() == nil)
  }

  @Test("A running rest round-trips with its alarm")
  func runningRoundTrip() throws {
    let store = RestTimerStore(database: try migratedDatabase())
    let alarm = UUID()
    let rest = PersistedRest(state: .running(endsAt: now.addingTimeInterval(90)), alarmID: alarm)
    try store.save(rest, at: now)
    #expect(try store.load() == rest)
  }

  @Test("A paused rest round-trips")
  func pausedRoundTrip() throws {
    let store = RestTimerStore(database: try migratedDatabase())
    let rest = PersistedRest(state: .paused(remaining: .seconds(42)), alarmID: nil)
    try store.save(rest, at: now)
    #expect(try store.load() == rest)
  }

  @Test("Saving again replaces, so there is only ever one row")
  func singleRow() throws {
    let database = try migratedDatabase()
    let store = RestTimerStore(database: database)
    try store.save(PersistedRest(state: .paused(remaining: .seconds(5)), alarmID: nil), at: now)
    let later = PersistedRest(state: .running(endsAt: now.addingTimeInterval(30)), alarmID: UUID())
    try store.save(later, at: now)
    #expect(try store.load() == later)
    let count = try database.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM deviceRestTimer") }
    #expect(count == 1)
  }

  @Test("Saving idle, or clearing, leaves nothing to load")
  func idleClears() throws {
    let store = RestTimerStore(database: try migratedDatabase())
    try store.save(PersistedRest(state: .paused(remaining: .seconds(5)), alarmID: nil), at: now)
    try store.save(PersistedRest(state: .idle, alarmID: nil), at: now)
    #expect(try store.load() == nil)
    try store.save(PersistedRest(state: .paused(remaining: .seconds(5)), alarmID: nil), at: now)
    try store.clear()
    #expect(try store.load() == nil)
  }

  @Test("A corrupt row with both a deadline and a remainder throws rather than picking one")
  func corruptRowThrows() throws {
    let database = try migratedDatabase()
    try database.write { db in
      try db.execute(
        sql: """
          INSERT INTO deviceRestTimer (id, endsAt, pausedRemainingSeconds)
          VALUES (?, '2026-01-01 00:00:00.000', 10)
          """,
        arguments: [RestTimerStore.rowID.uuidString.lowercased()])
    }
    #expect(throws: RestTimerStateError.bothDeadlineAndRemainingSet) {
      try RestTimerStore(database: database).load()
    }
  }
}
```

The corrupt-row insert writes the date as text. Check how SQLiteData encodes `Date` and UUIDs
in `TEXT` columns (look at how another store test inserts raw rows). Adjust the literal so the
row decodes as far as the both-set check. The assertion must stay `bothDeadlineAndRemainingSet`.

- [ ] **Step 2: Run to verify failure**

Run: `Tools/linux-test.sh --filter RestTimerStoreTests`
Expected: compile failure, `cannot find 'RestTimerStore'`.

- [ ] **Step 3: Implement**

`RestTimerStore.swift`:
- `load()`: fetch `DeviceRestTimer` by `rowID`. If missing, return nil. Otherwise build
  `try RestTimerState(endsAt: row.endsAt, pausedRemainingSeconds: row.pausedRemainingSeconds)`,
  which throws for the corrupt row. Return nil when the state is `.idle`; otherwise return
  `PersistedRest(state:alarmID: row.alarmID)`.
- `save(_:at:)`: if the state is `.idle`, delete the row. Otherwise upsert `rowID` with
  `state.storage.endsAt`, `state.storage.pausedRemainingSeconds`, `alarmID` and
  `updatedAt: now`. `ON CONFLICT REPLACE` on the primary key makes a plain insert with the fixed
  id an upsert.
- `clear()`: delete the row.
- Doc comment: why one row (one rest timer per device), and why it is device-local (an alarm on
  this phone means nothing on another).

Wrap every assignment inside `.update {}` in `#bind(...)` (`DECISIONS.md` §9).

- [ ] **Step 4: Run to verify pass**

Run: `Tools/linux-test.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/HardsetKit/Sources/HardsetStore/RestTimerStore.swift \
  Packages/HardsetKit/Tests/HardsetStoreTests/RestTimerStoreTests.swift
git commit -m "feat(store): persist the rest timer in its device-local table

deviceRestTimer existed from the first migration and nothing ever wrote it, so a
relaunch could not know which alarm was its own. One row, device-local, and a corrupt
row is refused rather than half-read.

Co-Authored-By: <your model's trailer>"
```

---

### Task 6: Failure copy (Store)

**Files:**
- Create: `Packages/HardsetKit/Sources/HardsetStore/FailureCopy.swift`
- Test: `Packages/HardsetKit/Tests/HardsetStoreTests/FailureCopyTests.swift`

**Interfaces:**
- Consumes: `LoggerStoreError` (`.incompleteSet`, `.sessionNotFound`), `SessionTimelineError`
  (Core), `SessionCoordinatorError`.
- Produces: `public nonisolated enum FailureCopy`. It has a nested `enum Action: Sendable` with
  the cases `logSet`, `finishWorkout`, `resumeWorkout`, `prepareCatalogue`, `saveGym`,
  `saveMachine`, `loadHistory`, `loadVolume` and `scheduleRest`, and
  `static func message(for error: any Error, during action: Action) -> String`.

The copy, verbatim:

| Action | Error | Message |
|---|---|---|
| `logSet` | `.incompleteSet` | "Enter a weight and reps before logging this set." |
| `logSet` | `.sessionNotFound` | "This workout could not be found. Your logged sets are safe." |
| `logSet` | anything else | "That set could not be saved. It has not been logged — tap to try again." |
| `finishWorkout` | `SessionTimelineError.finishedBeforeStart` | "This workout could not be finished, so it is still open. Your sets are saved. Check your device's date and time, then try again." |
| `finishWorkout` | anything else | "This workout could not be finished, so it is still open. Your sets are saved. Try again." |
| `resumeWorkout` | — | "Your unfinished workout could not be reopened. Its sets are saved. Try again." |
| `prepareCatalogue` | — | "The movement list could not be prepared. Try again." |
| `saveGym` | — | "That gym could not be saved. Try again." |
| `saveMachine` | — | "That machine could not be saved. Try again." |
| `loadHistory` | — | "Your history could not be read. Your sets are safe. Try again." |
| `loadVolume` | — | "The last 7 days could not be read. Your sets are safe. Try again." |
| `scheduleRest` | — | "The rest alarm could not be set. The countdown on screen still runs." |

Check `SessionTimelineError`'s real case names in `Sources/HardsetCore/SessionTimeline.swift:51`.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import HardsetCore
import Testing

@testable import HardsetStore

@Suite("Failures are told in the lifter's words, never as an error dump")
struct FailureCopyTests {
  private struct Opaque: Error, CustomStringConvertible {
    var description: String { "Error Domain=NSSQLiteErrorDomain Code=19 secret-internal" }
  }

  @Test("Known logging errors keep their specific copy")
  func knownLoggingErrors() {
    #expect(
      FailureCopy.message(for: LoggerStoreError.incompleteSet, during: .logSet)
        == "Enter a weight and reps before logging this set.")
    #expect(
      FailureCopy.message(for: LoggerStoreError.sessionNotFound, during: .logSet)
        == "This workout could not be found. Your logged sets are safe.")
  }

  @Test("A clock that went backwards is named as the cause")
  func clockCause() {
    #expect(
      FailureCopy.message(for: SessionTimelineError.finishedBeforeStart, during: .finishWorkout)
        .contains("Check your device's date and time"))
  }

  @Test(
    "No action ever leaks the raw error",
    arguments: [
      FailureCopy.Action.logSet, .finishWorkout, .resumeWorkout, .prepareCatalogue, .saveGym,
      .saveMachine, .loadHistory, .loadVolume, .scheduleRest,
    ]
  )
  func neverLeaks(action: FailureCopy.Action) {
    let text = FailureCopy.message(for: Opaque(), during: action)
    #expect(!text.isEmpty)
    #expect(!text.contains("Domain"))
    #expect(!text.contains("secret-internal"))
  }

  @Test("A stranded workout is never described as gone")
  func resumeReassures() {
    let text = FailureCopy.message(for: Opaque(), during: .resumeWorkout)
    #expect(text.contains("sets are saved"))
  }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `Tools/linux-test.sh --filter FailureCopyTests`
Expected: compile failure.

- [ ] **Step 3: Implement**

`FailureCopy.swift` is a `switch action` returning the table's strings. Inside `logSet` and
`finishWorkout`, cast the error (`as? LoggerStoreError`, `as? SessionTimelineError`) to pick the
specific copy. The `Action` enum must be `CaseIterable` and `Sendable`. Doc comment: copy that
used to live in a view (`LiveSessionScreen.errorMessage`), moved here so it is tested, and a raw
`\(error)` must never reach the screen.

- [ ] **Step 4: Run to verify pass**

Run: `Tools/linux-test.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/HardsetKit/Sources/HardsetStore/FailureCopy.swift \
  Packages/HardsetKit/Tests/HardsetStoreTests/FailureCopyTests.swift
git commit -m "feat(store): one tested source for failure copy

Error text lived in views, untested, and one path printed a raw error to the user.
Several failures were swallowed outright because there was nothing to say. Each
user-visible action now has plain copy that never leaks the underlying error.

Co-Authored-By: <your model's trailer>"
```

---

### Task 7: Alarm controller — reconcile, persist, authorize (Mac-only)

**Files:**
- Modify: `Packages/HardsetKit/Sources/HardsetAlarm/RestTimerController.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetAlarm/RestAlarmService.swift`
- Modify: `docs/MAC-VERIFICATION.md`

**Interfaces:**
- Consumes: `RestReconciler`, `AlarmSnapshot` and `PersistedRest` (Task 2); `RestTimerStore`
  (Task 5).
- Produces, on `RestTimerController`:
  - `init(persistence: RestTimerStore? = nil)`
  - `func reconcile(now: Date = .now) async`
  - `func observeAlarms() async`, a long-running loop the app starts from a `.task`
  - `public private(set) var authorization: Authorization`, where
    `enum Authorization { case unknown, authorized, denied }`
  - `public private(set) var lastError: (any Error)?`, which already exists and is now kept
    up to date

This task cannot be compiled here. Before writing any AlarmKit call, read and cite (with WebFetch):
- https://developer.apple.com/documentation/alarmkit/alarmmanager (for `alarms`, `alarmUpdates`
  and `requestAuthorization`)
- https://developer.apple.com/documentation/alarmkit/alarm (for `Alarm.state` and what dates or
  durations it exposes)
- https://developer.apple.com/documentation/alarmkit/alarmpresentation/alert

If `Alarm` exposes no fire date or paused remainder, build `AlarmSnapshot` with `nil` for them.
The reconciler is designed for that. Do not compute one.

- [ ] **Step 1: Map AlarmKit to `AlarmSnapshot`**

Add a `nonisolated static func snapshot(of alarm: Alarm) -> AlarmSnapshot` in
`RestAlarmService`. It maps the documented `Alarm.State` cases:

| `Alarm.State` | `AlarmSnapshot` mode |
|---|---|
| countdown | `.countdown(fireDate:)` |
| paused | `.paused(remaining:)` |
| alerting | `.alerting` |
| scheduled | `.countdown(fireDate:)`, with whatever the docs say is available |

Add `@unknown default` mapping to `.countdown(fireDate: nil)`.

- [ ] **Step 2: Persist every state change**

In `RestTimerController`, add `private let persistence: RestTimerStore?` and a
`private func persist()`. It saves `PersistedRest(state: state, alarmID: alarmID)` and sets
`lastError` on failure. Call it at the end of `start`, `adjust`, `pause`, `resume` and `cancel`,
and after `commit` assigns the new `alarmID`.

- [ ] **Step 3: Reconcile**

```swift
  /// Brings the on-screen timer back in line with AlarmKit. Run at launch and on every update:
  /// a force-quit relaunched the app idle while its alarm still counted down.
  public func reconcile(now: Date = .now) async {
    let persisted: PersistedRest?
    do { persisted = try persistence?.load() } catch {
      // A corrupt record is discarded, not half-read. The alarms below are still the truth.
      try? persistence?.clear()
      persisted = nil
    }
    let alarms = ((try? RestAlarmService.currentAlarms()) ?? []).map(RestAlarmService.snapshot(of:))
    let result = RestReconciler.reconcile(persisted: persisted, alarms: alarms, now: now)
    for stale in result.staleAlarmIDs { try? RestAlarmService.cancel(id: stale) }
    commitTask?.cancel()
    state = result.state
    alarmID = result.alarmID
    persist()
  }

  /// Follows AlarmKit for the life of the app.
  public func observeAlarms() async {
    for await _ in RestAlarmService.alarmUpdates() { await reconcile() }
  }
```

`RestAlarmService.currentAlarms()` and `alarmUpdates()` are thin wrappers over
`AlarmManager.shared`. Write them in the documented shapes.

- [ ] **Step 4: Authorization at the first rest**

In `start`, before scheduling: if authorization is not determined, `await
RestAlarmService.requestAuthorization()` inside the commit task. Set `authorization` from the
result. When denied, keep the on-screen state, skip the alarm, and leave `lastError` nil. The
denial is shown by the UI (Task 11), and it is not an error.

Then fall back to a plain local notification (spec §7 item 1.3; `DEVICE-CHECKLIST.md` §B
"Denied path"):
- Request `UNUserNotificationCenter` authorization for `.alert` and `.sound`, once.
- Schedule a `UNNotificationRequest` with the fixed identifier `"hardset.rest"` and a
  `UNTimeIntervalNotificationTrigger` for the remaining time.
- `adjust` and `resume` replace it. `pause` and `cancel` remove it, using
  `removePendingNotificationRequests(withIdentifiers:)`.

Put these calls in a small `RestNotificationFallback` type in `HardsetAlarm`, so the controller
stays readable. Cite https://developer.apple.com/documentation/usernotifications/unusernotificationcenter.

- [ ] **Step 5: Remove the dead Skip button**

In `RestAlarmService.schedule`, the alert's secondary button is `.custom` with no intent, so it
does nothing. Use the documented 26.1 initialiser that has no secondary button, if one exists. If
not, check the docs for a secondary behaviour that works without an intent. Cite the URL. If
neither exists, keep the button but record the finding in `docs/MAC-VERIFICATION.md` for Phase 4
(intents).

- [ ] **Step 6: Ledger and commit**

Append to `docs/MAC-VERIFICATION.md` under `## Phase 1`:

```markdown
- [ ] (feat(alarm): …) Build HardsetAlarm for iOS. Then on device:
  - start a rest, force-quit, relaunch: the app shows the same countdown
  - pause from the Lock Screen, open the app: it shows paused with the right remainder
  - first rest ever: the permission prompt appears
  - deny it: the on-screen countdown still runs and the denial banner shows (with Task 11)
  - the alert has no button that does nothing
```

Commit with a why-message that cites the AlarmKit documentation URLs used.

---

### Task 8: Formatter adoption and copy in the UI (Mac-only)

**Files:**
- Modify: `Packages/HardsetKit/Sources/HardsetUI/SessionView.swift:163-185, 221` (PR copy, volume
  summary)
- Modify: `Packages/HardsetKit/Sources/HardsetUI/ExerciseSectionView.swift:127, 143-145`
- Modify: `Packages/HardsetKit/Sources/HardsetUI/MachinePickerView.swift:110, 131-133`
- Modify: `Packages/HardsetKit/Sources/HardsetUI/HistoryView.swift:132-135`
- Modify: `Packages/HardsetKit/Sources/HardsetUI/ProgressionChartView.swift:145`
- Modify: `Packages/HardsetKit/Sources/HardsetUI/VolumeReportView.swift:36, 54`
- Modify: `docs/MAC-VERIFICATION.md`

**Interfaces:**
- Consumes: `WeightFormatter`, `CountText` and `MachineChange.explanation(in:locale:)` (Task 3).

Changes:
1. **SessionView PR copy.** Build a `WeightFormatter(unit: unit)` and render:
   - weight records as `"\(f.load(kilograms: record.weightKg)), up from \(f.load(kilograms: previous))"`
   - rep records as `"\(CountText.reps(record.reps)) at \(f.load(kilograms: record.weightKg)), up from \(previousReps)"`
   - e1RM records as `"\(f.estimate(kilograms: new)), up from \(f.estimate(kilograms: previous))"`.
     The new value is now stated. Read `PersonalRecord` for the field holding the new estimate.
   Delete `trim`.
2. **ExerciseSectionView step chip.** `"· \(f.load(kilograms: increment)) steps"`. Delete
   `format`.
3. **MachinePickerView.** `"moves in \(f.load(kilograms: increment)) steps"`. Delete `format`.
   It needs a `unit` input. Add `unit: WeightUnit` to its initialiser with **no default**,
   because a default would silently show kilograms. Pass `unit: unit` at its one call site in
   `Feature/LiveSessionScreen.swift`.
4. **HistoryView.** Replace the hand-built set count with `CountText.sets(n)` and the volume
   string with `f.load(kilograms:)`.
5. **ProgressionChartView.** `Text(change.explanation(in: unit))`.
6. **VolumeReportView.** Every "This week" or "this week" becomes "Last 7 days" or "the last 7
   days". The window is rolling and not a calendar week (`VolumeStore.swift:55-58`).
   `VolumeReportView.format` (for fractional *sets*) stays; it is not a weight.

Run `rg -n '"kg"| kg|kg steps|This week|this week' Packages/HardsetKit/Sources/HardsetUI`
afterwards. Expected: no hits except comments.

Ledger entry: build HardsetUI. Then in the simulator with Settings set to lb, log a PR, open
the machine picker, and check every weight on the session screen reads lb.

Commit with a why-message.

---

### Task 9: Set row — displayed is saved, logged is locked (Mac-only)

**Files:**
- Modify: `Packages/HardsetKit/Sources/HardsetUI/SetRowView.swift`
- Modify: `docs/MAC-VERIFICATION.md`

Changes:
1. **Reseed whenever the draft changes from outside.** Next to `.onChange(of: unit)`, add
   `.onChange(of: draft) { if editing == nil { reseedBuffers() } }`. It reseeds only when not
   editing, so typing is never overwritten mid-keystroke. Add a comment that names the defect:
   after a machine change the coordinator rewrote the draft while the field kept the old
   number, and logging then saved a value the lifter never saw.
2. **Lock logged rows.** On both `valueField` buttons add `.disabled(isLogged)`, with
   `.accessibilityHint` cleared when logged. Add a comment that editing a logged set changed
   only the in-memory draft, never the database, so the row showed a check mark beside an
   unsaved value. Editing returns properly in Phase 2 (2.3).
3. **Use the shared formatter.** Replace this file's private `format(_:)` and the
   `"\(Self.format(weight)) \(unit.abbreviation)"` strings (lines 232–253) with
   `WeightFormatter(unit: unit).load(kilograms:)`. Use `.spoken(kilograms:)` inside the
   accessibility label so VoiceOver says "kilograms". `WeightFormatter` comes from Task 3; if
   Task 3 has not merged when this runs, do item 3 last, after rebasing.

Ledger entry, simulator:
- change machine on a prefilled row: the field shows the new machine's prefill
- log a set: its fields cannot be opened
- VoiceOver on a row says "kilograms"

---

### Task 10: The rest chip (Mac-only)

**Files:**
- Modify: `Packages/HardsetKit/Sources/HardsetUI/ExerciseSectionView.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetUI/SessionView.swift` (pass-through)
- Modify: `Packages/HardsetKit/Sources/HardsetUI/RestBarView.swift` (caption when `restMetadata`
  is set; no other change)
- Modify: `docs/MAC-VERIFICATION.md`

**Interfaces:**
- Consumes: `RestPlan.presets`, `RestPlan.label(for:)` and `RestPlan.allowedRange` (Task 1);
  `restChoices` from the coordinator (Task 4), passed in as plain values.
- Produces three new inputs, which Task 11 wires:
  - `ExerciseSectionView`: `restChoice: Duration? = nil`,
    `onChooseRest: ((Duration?) -> Void)? = nil`, `onStartRest: (() -> Void)? = nil`
  - `SessionView`: `restChoices: [ExerciseID: Duration] = [:]`,
    `onChooseRest: ((UUID, Duration?) -> Void)? = nil`, `onStartRest: ((UUID) -> Void)? = nil`

  The defaults keep existing callers compiling. When `onChooseRest` is nil the chip is hidden,
  the same rule as the optional machine chip.

Changes:
1. In `ExerciseSectionView`'s header row, next to the machine chip, add a `Menu` labelled
   `Label("Rest · \(RestPlan.label(for: restChoice))", systemImage: "timer")`. Style it like the
   machine chip.
2. Menu contents, in this order:
   - a `Picker` over `RestPlan.presets`, labelled with each `clockString`, with the selection bound
     to `restChoice`; **nothing is selected when nil**
   - "Custom…", which presents a small sheet with a minutes/seconds wheel limited to
     `RestPlan.allowedRange`
   - "Off" (`onChooseRest(nil)`), shown only when a choice exists
   - a `Divider`, then "Start rest now" (`onStartRest`), shown only when a choice exists
3. `accessibilityLabel`: "Rest after each set, \(restChoice?.clockString ?? "off")".
4. `SessionView` looks up `restChoices[state.exerciseID]` for each section and forwards the
   callbacks with the section's id.
5. `RestBarView` already accepts `restMetadata`. Confirm it renders `setLabel` and
   `exerciseName` when non-nil. If it already does, make no change.

Ledger entry, simulator:
- the chip reads "Rest · Off" on a fresh exercise
- choosing 2:00 then logging a working set starts a 2:00 rest and shows the caption
- a warm-up starts nothing
- Off hides "Start rest now"
- relaunching the app keeps the chip at 2:00

---

### Task 11: Live session wiring (Mac-only)

**Files:**
- Modify: `Packages/HardsetKit/Sources/HardsetFeature/LiveSessionScreen.swift`
- Modify: `Hardset/HardsetApp.swift`
- Modify: `HardsetTests/AppSmokeTests.swift`
- Modify: `docs/MAC-VERIFICATION.md`

**Interfaces:**
- Consumes:
  - `restChoices`, `activeRest`, `setRestChoice`, `startRest` and `endRest` (Task 4)
  - `FailureCopy` (Task 6)
  - `RestTimerController.authorization`, `reconcile()` and `observeAlarms()` (Task 7)
  - `RestTimerStore` (Task 5)
  - the Task 10 inputs
- Produces:
  - `RestTimerHooks` gains `authorizationDenied: () -> Bool` (default `{ false }`) and
    `lastErrorMessage: () -> String?` (default `{ nil }`)
  - the `SessionCoordinator.start(...hooks:)` convenience takes
    `restPreferences: any RestPreferenceStore` in place of `restAfterSet: Duration?`

Changes:
1. **LiveSessionScreen.**
   - Delete `@State private var restMetadata` and pass `coordinator.activeRest` to `SessionView`.
   - `onSkipRest` becomes `{ hooks.cancel(); coordinator.endRest() }`. `finish()` calls
     `coordinator.endRest()` where it cleared `restMetadata`.
   - Pass `restChoices: coordinator.restChoices`, `onChooseRest: coordinator.setRestChoice` and
     `onStartRest: { coordinator.startRest(forExercise: $0) }`.
2. **Error copy.** `errorMessage` uses `FailureCopy.message(for:during: .logSet)` and, when
   `finishFailed`, the `.finishWorkout` copy. Store the finish error in place of the `Bool` so
   the clock case keeps its specific sentence.
3. **`addMachine` catch.** Set `@State private var machineError: String?` to
   `FailureCopy.message(for: error, during: .saveMachine)` and show it as a footer `Text` in the
   machine picker sheet. The silent catch is gone.
4. **`MachinePickerView` unit.** Pass `unit: unit` (Task 8 added the input).
5. **Rest permission and alarm errors.** When `hooks.authorizationDenied()` and a rest is
   active, show one line above the rest bar: "Alarms are off for Hardset, so rest won't sound
   when the phone is locked." Add a "Settings" button that opens
   `UIApplication.openSettingsURLString` (cite
   https://developer.apple.com/documentation/uikit/uiapplication/opensettingsurlstring). When
   `hooks.lastErrorMessage()` is non-nil, show it in the same slot.
6. **HardsetApp.swift**, wiring only:
   - pass `RestTimerController(persistence: RestTimerStore(database: database))`
   - add `.task { await restTimer.reconcile(); await restTimer.observeAlarms() }` to `RootView`
   - set the hooks' `authorizationDenied: { restTimer.authorization == .denied }` and
     `lastErrorMessage: { restTimer.lastError.map { FailureCopy.message(for: $0, during: .scheduleRest) } }`
   - pass `restPreferences: UserDefaultsRestPreferences()` to `HardsetRootView`. The parameter
     has existed since Task 4.

   `RestTimerController` is created in `@State`, so construct it in `init()` once the database
   is available. If that needs a non-trivial restructuring of `HardsetApp`, keep it minimal and
   say so in the report.
7. **AppSmokeTests.** `RootView` is private and takes two arguments, so the test cannot compile.
   Replace the body with a construction of `HardsetRootView` from `HardsetFeature`, using an
   in-memory database:

   ```swift
   import GRDB
   import HardsetFeature
   import HardsetStore
   import Testing

   @Suite("App target builds and links")
   @MainActor
   struct AppSmokeTests {
     @Test("The root view is constructible against a migrated database")
     func rootViewExists() throws {
       let queue = try DatabaseQueue()
       try HardsetMigrations.migrator().migrate(queue)
       _ = HardsetRootView(environment: HardsetEnvironment(database: queue))
     }
   }
   ```

   Check whether `HardsetMigrations` is public, and whether the `uuid()` default matters for an
   empty database (it does not; nothing is inserted).

Ledger entry, simulator and device:
- the caption shows during rest
- Skip clears it
- with alarm permission denied, the banner and the Settings link appear
- a failed machine save shows its footer copy
- the `HardsetTests` target compiles and passes

---

### Task 12: Root and screen wiring (Mac-only)

**Files:**
- Modify: `Packages/HardsetKit/Sources/HardsetFeature/HardsetRootView.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetFeature/WeeklyVolumeScreen.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetFeature/HistoryScreen.swift`
- Modify: `docs/MAC-VERIFICATION.md`

**Interfaces:**
- Consumes: `FailureCopy` (Task 6) and `MuscleVolumeReport.highestCertainty` (Task 3). Task 4
  already did the `restPreferences` rename in this file, mechanically.

Changes:
1. **Resume failure** (line ~90). Replace `coordinator = try? SessionCoordinator.resume(...)`
   with a `do/catch`. On failure set `@State private var resumeError: String?` to
   `FailureCopy.message(for:during: .resumeWorkout)`, and show it in place of the start button
   with a "Try again" button that reruns the resume. **While `resumeError` is set, Start workout
   is not offered**, because a stranded open session must never look like "no workout".
2. **Catalogue seed** (line ~86). Replace `try? catalog.seed()` with a `do/catch` that sets
   `catalogueError` (`.prepareCatalogue` copy). Show it in the empty picker state with a retry.
3. **Raw error** (line ~337). Replace the `\(error)` text with
   `FailureCopy.message(for: error, during: .saveGym)`.
4. **Tab title** (line ~124). "This week" becomes "Last 7 days".
5. **WeeklyVolumeScreen.**
   - The methodology sheet's certainty becomes `report?.highestCertainty` (nil hides the badge).
   - The failure state's "Pull down to try again" becomes a `Button("Try again") { load() }`,
     because pull-to-refresh cannot fire outside a scroll view.
   - The failure text uses `.loadVolume` copy.
6. **HistoryScreen.** Same retry fix, with `.loadHistory` copy.

Ledger entry, simulator:
- with the database made unreadable (or a forced throw in a debug build), each screen shows its
  copy and a working Try again
- the Volume tab is titled "Last 7 days"
- the methodology badge reads Low when only counted muscles were trained

Commit with a why-message.
