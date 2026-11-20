# Saved Workouts, Progress Tab and Body-Part Library Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One-tap saved workouts with double-progression targets, a Progress tab that rewards both heavier weight and more reps, and a movement library grouped by body part.

**Architecture:** The rules live in pure HardsetCore value types (overload targets, set comparison, records, trends, scorecard, split balance, library sections), each unit-tested on Linux. HardsetStore adds two synced tables (`workoutTemplates`, `templateExercises`) and two nullable columns, then exposes `TemplateStore`, a progress board read and a receipt scorecard. HardsetUI renders Core values only, and HardsetFeature wires the stores into a new Progress tab and an extended Train tab.

**Tech Stack:** Swift 6.2 (strict concurrency, `NonisolatedNonsendingByDefault`), SwiftUI, Swift Charts, GRDB plus SQLiteData 1.9 (CloudKit sync), Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-18-workouts-progress-library-design.md`. Read it before any task. Where this plan and the spec disagree, the spec wins; stop and report.

## Model assignment and waves

The owner splits the work between **DeepSeek v4.1 Flash** (OpenCode, free model) and **Claude Sonnet 5.5**. DeepSeek takes the self-contained Core tasks, where the test cases below pin every rule. Sonnet takes persistence, integration and SwiftUI. Before a DeepSeek task is integrated, Sonnet or the coordinator reviews its diff and re-runs `hardset-check core`. A worker owns only the files listed in its task, does not delegate further and does not push.

| Wave | Tasks | Model | Can run in parallel |
| --- | --- | --- | --- |
| 1 | 1 | DeepSeek | no (everything depends on it) |
| 2 | 2, 3, 4, 5, 6, 7 | DeepSeek | yes, the file sets are disjoint |
| 3 | 8 | DeepSeek | after 4 and 5 |
| 4 | 9 → 10 → 11 → 12 → 13 → 14 → 15 | Sonnet | no, in order |
| 5 | 16 → 17 → 18 → 19 → 20 | Sonnet | no, in order |

Work happens on branch `FrankieBiz/saved-workout-templates-2`, which starts at `main` (`9aa498b`). Commit after every task. Do not push until the owner chooses the delivery (AGENTS.md requests a push to `main`; the global rules default to a PR, so ask).

## Global Constraints

- Core is Foundation-only and `nonisolated`. HardsetUI depends on HardsetCore only, so every value a view renders must be a Core type. Every HardsetUI view is `@MainActor`.
- Weights are stored in kilograms. Pounds are display only, through `WeightUnit`, so there is no new conversion constant.
- Load comparisons use `PersonalRecordDetector.loadMatchingTolerance` (0.01 kg).
- Estimates come only from `StrengthMath.estimatedOneRepMax`: 1 to 12 reps, certainty high for 2 to 6 reps, moderate for 7 to 10, low for 11 to 12. Nothing estimates above 12 reps or for bodyweight work (`ExerciseModality.estimatesOneRepMax == false`).
- Each exercise on each machine (`ProgressionKey`) is its own series. Different machines are never merged.
- Schema rules (`Migrations.swift:13-29`):
  - one TEXT UUID primary key `NOT NULL ON CONFLICT REPLACE DEFAULT (uuid())`
  - no UNIQUE and no CHECK constraints, `STRICT` tables
  - NOT NULL columns carry defaults
  - `ON DELETE` is only CASCADE or SET NULL
  - never drop or rename a column or table; never edit `v1`
  - `createdAt` is the creation column
- New synced tables go in `HardsetMigrations.syncedTableNames` and in the `SyncEngine` `tables:` list in `Database.swift`.
- Every new query must pass `python3 Tools/check_query_performance.py --require-indexes`.
- Design: follow DESIGN.md tokens only.
  - No new colour, radius, type role or motion token.
  - `Motion.stamp` stays reserved for the log check.
  - Messages and marks arrive through `hardsetArrival()`.
  - Logger targets are at least 56 pt, others at least 44 pt.
  - Weights, reps and rest use `.monospacedDigit()` roles.
  - `CertaintyBadge` sits beside every estimated figure.
- Copy is sentence case, with no exclamation marks. Exact strings quoted in this plan are fixed.
- Commits are authored by `FrankieBiz <frankabisignano@gmail.com>`, with no AI names and no co-author trailers. Do not hand-edit `Hardset.xcodeproj`.
- Verification per task is `hardset-check core` (Core), `hardset-check store` (Store), and `hardset-check parse` (any file). `make check` must pass before the branch is offered. UI tasks cannot render on Linux; they are verified by the macOS CI screenshot job and `make mac-test`. Report UI as "not visually verified" until that runs.

## Review Focus

1. **A machine from another gym in a saved workout.** Starting must not throw `machineGymMismatch`. Expected: the movement uses the machine last used at this gym, or none. Pinned in Task 13.
2. **A target computed from another machine's history.** Expected: no target and today's prefill, because borrowed history is not this machine's. Pinned in Task 12.
3. **Unit switch between sessions.** A kg lifter whose machine has no saved step must get a 2.5 kg step, and a lb lifter 5 lb, never 2.268 kg shown as "42.27". Pinned in Task 3 and Task 12.
4. **Editing or archiving a saved workout after using it.** Past sessions, scorecards and targets must not change, because they read session rows and not the template. Pinned in Task 10 and Task 14.
5. **Resuming a killed workout started from a template.** The rep range and targets must survive the restart. Pinned in Task 13.

---

### Task 1: Template value types, rep range and rotation (DeepSeek)

**Files:**
- Modify: `Packages/HardsetKit/Sources/HardsetCore/Identifiers.swift`: add `TemplateID`, a copy of `GymID`'s pattern.
- Create: `Packages/HardsetKit/Sources/HardsetCore/WorkoutTemplate.swift`
- Test: `Packages/HardsetKit/Tests/HardsetCoreTests/WorkoutTemplateTests.swift`

**Interfaces:**
- Produces:
  - `public struct TemplateID: HardsetID`
  - `public struct RepRange: Hashable, Sendable, Codable`, with:
    - `public let lower: Int`, `public let upper: Int`
    - `public init?(lower: Int, upper: Int)`, which returns nil unless `1 <= lower <= upper <= 50`
    - `public var label: String`
  - `public struct TemplateExercise: Hashable, Sendable, Identifiable`, with:
    - `id: UUID`, `exerciseID: ExerciseID`, `exerciseName: String`
    - `machineID: MachineID?`, `machineName: String?`
    - `plannedSets: Int`, clamped to 1...10 in `init`
    - `repRange: RepRange?`
    - `restSeconds: Int?`, where a non-positive value is stored as nil
    - a memberwise `init` with defaults: `id: UUID = UUID()`, machine nil, `repRange` nil, `restSeconds` nil
  - `public struct WorkoutTemplate: Hashable, Sendable, Identifiable`, with:
    - `id: TemplateID`, `name: String`, `position: Int`
    - `exercises: [TemplateExercise]`, `lastDoneAt: Date?`
  - `public enum WorkoutRotation` with `public static func upNextOrder(_ templates: [WorkoutTemplate]) -> [WorkoutTemplate]`

- [ ] **Step 1: Write the failing tests**

```swift
@Suite("Saved workouts and their rotation")
struct WorkoutTemplateTests {
  @Test func repRangeRejectsImpossibleRanges() {
    #expect(RepRange(lower: 12, upper: 8) == nil)
    #expect(RepRange(lower: 0, upper: 5) == nil)
    #expect(RepRange(lower: 8, upper: 51) == nil)
    #expect(RepRange(lower: 8, upper: 12)?.label == "8–12")   // en dash
    #expect(RepRange(lower: 10, upper: 10)?.label == "10")
  }
  @Test func plannedSetsAndRestAreClamped() {
    let low = TemplateExercise(exerciseID: ExerciseID(), exerciseName: "Row", plannedSets: 0, restSeconds: 0)
    let high = TemplateExercise(exerciseID: ExerciseID(), exerciseName: "Row", plannedSets: 14, restSeconds: 90)
    #expect(low.plannedSets == 1); #expect(low.restSeconds == nil)
    #expect(high.plannedSets == 10); #expect(high.restSeconds == 90)
  }
  @Test func upNextIsNeverDoneThenOldestThenPosition() {
    // a: position 0, done day 10; b: position 1, done day 3; c: position 2, never; d: position 3, done day 3
    // expected order: c, b, d, a
  }
  @Test func upNextOfEmptyIsEmpty() { #expect(WorkoutRotation.upNextOrder([]).isEmpty) }
}
```

- [ ] **Step 2: Run `hardset-check core`.** Expected: a compile FAIL naming `RepRange`.
- [ ] **Step 3: Implement the types and `upNextOrder`.** The order is: never-done templates first, by `position`; then by `lastDoneAt` ascending; ties broken by `position`.
- [ ] **Step 4: Run `hardset-check core`.** Expected: all Core tests pass.
- [ ] **Step 5: Commit** with `Add saved workout value types and rotation order`.

### Task 2: "Most weight for this many reps" record (DeepSeek)

**Files:**
- Modify: `Packages/HardsetKit/Sources/HardsetCore/PersonalRecords.swift`. Add case `loadAtReps` after `repsAtLoad`, its label, and the rule inside `records(for:history:increment:estimatesOneRepMax:)` after the reps-at-load block. Update the type's rule list doc comment.
- Modify: `Packages/HardsetKit/Sources/HardsetUI/SessionView.swift:788-815`. Add the `describe` case.
- Test: `Packages/HardsetKit/Tests/HardsetCoreTests/PersonalRecordsTests.swift`

**Interfaces:**
- Produces: `PersonalRecordKind.loadAtReps`, with label `"Most weight for this many reps"`. A `.loadAtReps` record carries `previousWeightKg` = the beaten load and `previousReps` = the beaten set's reps.

Rule:
- Take the earlier working sets with `reps >= candidate.reps`. Let `best` be the largest load among them.
- The candidate is a record when `candidate.weightKg + loadMatchingTolerance >= best + max(best * relativeThreshold, step)`.
- No such set means no record.
- Do not emit it when `.heaviestLoad` was emitted for the same candidate, so a heaviest-ever set is announced once.
- It applies at every rep count and for bodyweight work.

- [ ] **Step 1: Write the failing tests.** Use the suite's `history(_:)` helper. The increment is `2.5` unless stated.

```swift
@Test func heavierAtSameRepsIsALoadAtRepsRecord() {
  let r = PersonalRecordDetector.records(for: .init(weightKg: 42.5, reps: 10), history: history([(50, 5), (40, 10)]), increment: 2.5)
  #expect(r.map(\.kind).contains(.loadAtReps)); #expect(!r.map(\.kind).contains(.heaviestLoad))
  let rec = r.first { $0.kind == .loadAtReps }
  #expect(rec?.previousWeightKg == 40); #expect(rec?.previousReps == 10)
}
@Test func loadAtRepsNeedsTheMargin() {
  let r = PersonalRecordDetector.records(for: .init(weightKg: 41, reps: 10), history: history([(50, 5), (40, 10)]), increment: 2.5)
  #expect(!r.map(\.kind).contains(.loadAtReps))
}
@Test func loadAtRepsComparesAgainstSetsWithAtLeastAsManyReps() {
  let r = PersonalRecordDetector.records(for: .init(weightKg: 42.5, reps: 10), history: history([(50, 5), (40, 12)]), increment: 2.5)
  #expect(r.first { $0.kind == .loadAtReps }?.previousReps == 12)
}
@Test func noLongerEarlierSetMeansNoLoadAtRepsRecord() {
  let r = PersonalRecordDetector.records(for: .init(weightKg: 42.5, reps: 10), history: history([(50, 5)]), increment: 2.5)
  #expect(!r.map(\.kind).contains(.loadAtReps))
}
@Test func loadAtRepsWorksAboveTwelveReps() {
  let r = PersonalRecordDetector.records(for: .init(weightKg: 32.5, reps: 15), history: history([(50, 5), (30, 15)]), increment: 2.5)
  #expect(r.map(\.kind) == [.loadAtReps])
}
@Test func heaviestEverIsNotAlsoALoadAtRepsRecord() {
  let r = PersonalRecordDetector.records(for: .init(weightKg: 45, reps: 10), history: history([(40, 10)]), increment: 2.5)
  #expect(r.map(\.kind).contains(.heaviestLoad)); #expect(!r.map(\.kind).contains(.loadAtReps))
}
```

- [ ] **Step 2: Run `hardset-check core`.** Expected: FAIL, `loadAtReps` is not a member.
- [ ] **Step 3: Implement the rule and the `SessionView.describe` case.** The case's text is `"\(weight) for \(record.reps) reps, up from \(previous) \(unit.abbreviation)"`. When there is no previous load it is `"\(weight) for \(record.reps) reps"`. Format the previous weight with the same `trim` helper.
- [ ] **Step 4: Run `hardset-check core` and `hardset-check parse`.** Expected: PASS. Existing record tests still pass unchanged.
- [ ] **Step 5: Commit** with `Record the most weight lifted for a rep count`.

### Task 3: Double-progression targets (DeepSeek)

**Files:**
- Create: `Packages/HardsetKit/Sources/HardsetCore/OverloadTarget.swift`
- Test: `Packages/HardsetKit/Tests/HardsetCoreTests/OverloadTargetTests.swift`

**Interfaces:**
- Consumes: `RepRange` (Task 1), `PriorSetRecord`, `WeightUnit`.
- Produces:
  - `public struct SetTarget: Hashable, Sendable`, with:
    - `weightKg: Double`, `reps: Int`, `rule: Rule`
    - `public enum Rule: Hashable, Sendable { case addRep, holdTop, addLoad(stepKg: Double, isAssumedStep: Bool) }`
    - `public var explanation: String`
  - `public enum OverloadTarget` with `public static func targets(lastSets: [PriorSetRecord], range: RepRange, setCount: Int, incrementKg: Double?, unit: WeightUnit, addsLoad: Bool) -> [SetTarget?]`. It returns exactly `setCount` elements.

Rules (from the spec):
- If `lastSets` is empty, every element is nil.
- The base for row `i` is `lastSets[i]`, or `lastSets.last` past the end.
- **All at top:** `addsLoad`, every last set has `reps >= range.upper`, and every load is within 0.01 kg of the heaviest. Then every row is `(heaviest + step, range.lower, .addLoad)`.
  - `step = incrementKg` when it is non-nil and positive.
  - Otherwise `step = unit.toKilograms(unit.plateIncrement)` with `isAssumedStep: true`.
- **Otherwise, when `addsLoad`:** if `base.reps >= range.upper`, the row is `(base.weightKg, range.upper, .holdTop)`. Else it is `(base.weightKg, base.reps + 1, .addRep)`.
- **When `!addsLoad` (bodyweight):** the row is `(base.weightKg, base.reps + 1, .addRep)`, not capped.
- Explanations, fixed copy:
  - `.addRep`: "One more rep than last time"
  - `.holdTop`: "Top of your range; hold it"
  - `.addLoad` with a known step: "Every set hit the top of your range: add one step"
  - `.addLoad` with an assumed step: "Every set hit the top of your range: add one plate (assumed step)"

- [ ] **Step 1: Write the failing tests.** Let `r = RepRange(lower: 8, upper: 12)!`. Sets are `PriorSetRecord(weightKg:reps:completedAt: .distantPast)`.

```swift
@Test func belowTopAddsOneRepPerSet()        // last 40×10, 40×9, 40×8; count 3; inc 2.5 → 40×11, 40×10, 40×9, all .addRep
@Test func allAtTopAddsTheMachineStep()      // last 40×12 ×3 → each 42.5×8, rule .addLoad(stepKg: 2.5, isAssumedStep: false)
@Test func unknownStepUsesOnePlateInTheLiftersUnit() // last 40×12 ×2, inc nil, .pounds → weight == 40 + 2.26796185 (±1e-6), isAssumedStep true; .kilograms → 42.5
@Test func aSetAlreadyAtTopHolds()           // last 40×12, 40×11 → 40×12 .holdTop, 40×12 .addRep
@Test func mixedLoadsAtTopDoNotAddLoad()     // last 40×12, 37.5×12 → 40×12 .holdTop, 37.5×12 .holdTop
@Test func noHistoryMeansNoTargets()         // last [] ; count 3 → [nil, nil, nil]
@Test func extraRowsReuseTheLastSet()        // last 40×10, 40×9, 40×8; count 4 → 4th is 40×9 .addRep
@Test func bodyweightOnlyAddsRepsUncapped()  // last 0×12, 0×12; addsLoad false → 0×13 .addRep twice
@Test func explanationsAreFixedCopy()        // check the four strings above
```

- [ ] **Step 2: Run `hardset-check core`.** Expected: FAIL.
- [ ] **Step 3: Implement `OverloadTarget.targets` and `SetTarget.explanation`.**
- [ ] **Step 4: Run `hardset-check core`.** Expected: PASS.
- [ ] **Step 5: Commit** with `Add double-progression set targets`.

### Task 4: Beat-last-time comparison (DeepSeek)

**Files:**
- Create: `Packages/HardsetKit/Sources/HardsetCore/SetComparison.swift`
- Test: `Packages/HardsetKit/Tests/HardsetCoreTests/SetComparisonTests.swift`

**Interfaces:**
- Produces: `public enum SetComparison: Hashable, Sendable` with:
  - `case beat(addedKg: Double, addedReps: Int)` and `case matched`
  - `public static func compare(weightKg: Double, reps: Int, against previous: PriorSetRecord?, repFloor: Int?) -> SetComparison?`
  - `public func label(in unit: WeightUnit) -> String`

Rules (spec, "Beating last time, precisely"). Let `dW = weightKg - previous.weightKg`, and treat loads as equal when `|dW| < 0.01`.
- `previous == nil` gives nil.
- Equal load and equal reps give `.matched`.
- More reps, with equal load or `dW > 0`, gives `.beat(addedKg: equal ? 0 : dW, addedReps: reps - previous.reps)`.
- `dW > 0` with `reps >= (repFloor ?? previous.reps)` gives `.beat(addedKg: dW, addedReps: reps - previous.reps)`. `addedReps` may be negative.
- Anything else gives nil.

Label:
- The weight part is `"+\(x) \(unit.abbreviation)"`, where `x = StrengthMath.displayRounded(addedKg, in: unit)`. Print a whole number without a decimal, otherwise one decimal. Show it only when `x > 0`.
- The reps part is `"+N rep"` or `"+N reps"`. Show it only when `addedReps > 0`.
- Join both parts with `" · "`.
- `.matched` is `"Matched"`.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func moreRepsSameLoad()      // 40×10 → 40×11: .beat(0, 1), label(.kilograms) "+1 rep"; 40×12 → "+2 reps"
@Test func moreLoadSameReps()      // 40×10 → 42.5×10: label "+2.5 kg"
@Test func moreOfBoth()            // 40×10 → 42.5×11: "+2.5 kg · +1 rep"
@Test func loadJumpWithinRange()   // 40×12 → 42.5×8, floor 8: .beat(2.5, -4), label "+2.5 kg"
@Test func loadJumpBelowFloor()    // 40×12 → 42.5×7, floor 8: nil
@Test func loadJumpWithoutRange()  // 40×12 → 42.5×8, floor nil: nil
@Test func matchedWithinTolerance()// 40×10 → 40.005×10: .matched, "Matched"
@Test func fewerRepsIsNothing()    // 40×10 → 40×9: nil ; previous nil: nil
@Test func poundsLabel()           // 40.8233133×10 → 45.359237×10: label(.pounds) "+10 lb"
```

- [ ] **Step 2: Run `hardset-check core`.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `hardset-check core`.** Expected: PASS.
- [ ] **Step 5: Commit** with `Compare a set with the same set last time`.

### Task 5: Movement trends, records per session and stalls (DeepSeek)

**Files:**
- Create: `Packages/HardsetKit/Sources/HardsetCore/ProgressTrend.swift`
- Test: `Packages/HardsetKit/Tests/HardsetCoreTests/ProgressTrendTests.swift`

**Interfaces:**
- Consumes: `ProgressionSample`, `ProgressionKey`, `PersonalRecordDetector`, `StrengthMath`.
- Produces:
  - `public enum TrendMetric: String, Hashable, Sendable { case estimatedMax, heaviestLoad, repsAtTopLoad }`
  - `public struct MovementTrend: Hashable, Sendable, Identifiable`, with:
    - `key: ProgressionKey` (also its `id`), `metric: TrendMetric`
    - `sparkline: [Double]`: oldest first, at most 12 values, kilograms or reps
    - `sixWeekChange: Double?`: a fraction, so 0.08 means +8%
    - `sessionCount: Int`
    - `stalledSessions: Int?`: non-nil means stalled
    - `latestDate: Date`
  - `public enum ProgressTrendAnalyzer`, with:
    - `public static let stallRun = 3`, `public static let minimumSessionsForStall = 4`
    - `public static func trend(key: ProgressionKey, samples: [ProgressionSample], incrementKg: Double?, estimatesOneRepMax: Bool) -> MovementTrend?`, which returns nil for no samples
    - `public static func recordSessionIDs(samples: [ProgressionSample], incrementKg: Double?, estimatesOneRepMax: Bool, lastSessions: Int? = nil) -> Set<SessionID>`
    - `public static func mostImproved(_ trends: [MovementTrend], limit: Int = 3) -> [MovementTrend]`

Rules:
- **Sessions.** Group samples by `sessionID`. A session's date is its earliest `completedAt`. Sort sessions by date, then by `sessionID.rawValue.uuidString`.
- **Metric.**
  - `!estimatesOneRepMax` uses `.repsAtTopLoad`: the most reps at the session's heaviest load, within 0.01 kg.
  - Otherwise, if the latest session has an evaluable estimate, use `.estimatedMax`: the session's best `StrengthMath` estimate. Sessions with no estimate are skipped for the sparkline and the change.
  - Otherwise use `.heaviestLoad`.
- **Six-week change.** Let `d` be the latest session's date. The base is the largest metric value among sessions dated in `[d - 49 days, d - 35 days]`. The change is `latest / base - 1`. It is nil when that window has no session or `base <= 0`.
- **Records.** Replay sessions in order. The first session only adds to history. For every later session, each set (in `completedAt` order) is a candidate against all earlier sets, including earlier sets of the same session (the `ReceiptStore` rule). A session is in the set when any candidate gets a non-empty `PersonalRecordDetector.records`. With `lastSessions: n`, only the last `n` sessions are tested, but history still includes everything before each candidate.
- **Stall.** When `sessionCount >= 4` and the trailing run of sessions with no record is at least 3, `stalledSessions` is that run's length. Otherwise it is nil. Compute it with `lastSessions: sessionCount - 1`, which is everything after the first session.
- **mostImproved.** Keep trends with `sixWeekChange > 0`. Sort by change descending, then `latestDate` descending. Take the first `limit`.

- [ ] **Step 1: Write the failing tests.** Use a helper `s(day: Int, session: Int, kg: Double, reps: Int)` that builds a sample with a fixed `SessionID` per session number, `completedAt = epoch + day days + order seconds` and machine nil.

```swift
@Test func estimatedMaxChangeOverSixWeeks()   // day 0 40×10, day 42 45×10 → metric .estimatedMax, sixWeekChange == 0.125 (±1e-9)
@Test func noSessionInWindowMeansNoChange()   // days 0 and 20 → sixWeekChange nil
@Test func highRepWorkTrendsOnHeaviestLoad()  // all sets 15 reps → metric .heaviestLoad
@Test func bodyweightTrendsOnReps()           // estimates false, 0×10 then 0×12 → .repsAtTopLoad, sparkline [10, 12]
@Test func sparklineKeepsTwelveNewest()       // 15 sessions → sparkline.count == 12, last value is newest
@Test func flatFourSessionsStall()            // 4 sessions of 40×10, inc 2.5 → stalledSessions == 3
@Test func aRecordInTheLastThreeIsNotAStall() // 4th session 42.5×10 → stalledSessions nil
@Test func threeSessionsCannotStall()         // 3 flat sessions → nil
@Test func firstSessionIsNeverARecord()       // recordSessionIDs of one session → empty
@Test func recordSessionsFound()              // sessions 40×10, 40×11, 40×11 → contains only session 2
@Test func mostImprovedOrdersByChange()       // changes 0.05, 0.2, nil, -0.1, 0.1 → [0.2, 0.1, 0.05]
```

- [ ] **Step 2: Run `hardset-check core`.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `hardset-check core`.** Expected: PASS.
- [ ] **Step 5: Commit** with `Add movement trends, record sessions and stall detection`.

### Task 6: Best at each weight, and split balance (DeepSeek)

**Files:**
- Create: `Packages/HardsetKit/Sources/HardsetCore/RepMaxLedger.swift`
- Create: `Packages/HardsetKit/Sources/HardsetCore/SplitBalance.swift`
- Test: `Packages/HardsetKit/Tests/HardsetCoreTests/RepMaxLedgerTests.swift` and `SplitBalanceTests.swift`

**Interfaces:**
- Consumes: `WorkoutTemplate` (Task 1), `VolumeAnalyzer.report(sets:attribution:)`, `CountableSet`, `AttributionIndex`, `MuscleVolumeReport`.
- Produces:
  - `public struct BestAtWeight: Hashable, Sendable, Identifiable { weightKg: Double; reps: Int; achievedAt: Date; id: Double { weightKg } }`
  - `public enum RepMaxLedger { public static func bests(from samples: [ProgressionSample]) -> [BestAtWeight] }`. The caller passes one key's samples.
  - `public struct SplitBalance: Hashable, Sendable { report: MuscleVolumeReport; emptyGroups: [MuscleGroup] }`
  - `public enum SplitBalanceAnalyzer { public static func balance(templates: [WorkoutTemplate], attribution: AttributionIndex) -> SplitBalance }`

Rules:
- **Ledger.** Loads within 0.01 kg are one weight; the first-seen value is used. Keep the most reps. `achievedAt` is the earliest `completedAt` that reached those reps. Sort by weight descending.
- **Balance.** Each template exercise contributes `plannedSets` copies of `CountableSet(exerciseID:isWarmup: false)`. Pass them all to `VolumeAnalyzer.report`. `emptyGroups` is `MuscleGroup.allCases` minus `.neck`, keeping those with no entry in `setsTouchingGroup`, in declaration order.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func ledgerKeepsMostRepsAndWhenFirstReached()
// samples (kg×reps@day): 40×10@1, 40×12@2, 40×12@3, 45×8@3, 40.004×11@4
// → [BestAtWeight(45, 8, day3), BestAtWeight(40, 12, day2)]
@Test func emptyLedger() { #expect(RepMaxLedger.bests(from: []).isEmpty) }

@Test func splitBalanceCountsPlannedSets()
// attribution: X → [chest direct, triceps indirect]; Y → [lats direct, biceps indirect]
//   (MuscleContribution(_:role:certainty:source:) with .moderate, .convention)
// templates: A = [X × 3 sets], B = [Y × 4 sets, Z × 2 sets] where Z is not in the index
// → setsTouchingGroup: chest 3, arms 7, back 4
// → fractionalSets: chest 3, triceps 1.5, lats 4, biceps 2
// → unattributedHardSets 2; emptyGroups == [.shoulders, .core, .legs, .glutes]
```

- [ ] **Step 2: Run `hardset-check core`.** Expected: FAIL.
- [ ] **Step 3: Implement both.**
- [ ] **Step 4: Run `hardset-check core`.** Expected: PASS.
- [ ] **Step 5: Commit** with `Add best-at-each-weight ledger and split balance`.

### Task 7: Library sections by body part (DeepSeek)

**Files:**
- Create: `Packages/HardsetKit/Sources/HardsetCore/LibraryIndex.swift`
- Test: `Packages/HardsetKit/Tests/HardsetCoreTests/LibraryIndexTests.swift`

**Interfaces:**
- Consumes: `CatalogEntry`, `MuscleFilterCategory`, `MuscleKey`.
- Produces:
  - `public struct LibrarySection: Hashable, Sendable, Identifiable { public enum Kind: Hashable, Sendable { case needsBodyPart, category(MuscleFilterCategory) }; kind: Kind; entries: [CatalogEntry]; id: Kind }`
  - `public enum LibraryIndex`, with:
    - `public static func sections(_ entries: [CatalogEntry]) -> [LibrarySection]`
    - `public static func counts(_ entries: [CatalogEntry]) -> [(category: MuscleFilterCategory, count: Int)]`

Rules:
- `.needsBodyPart` holds entries whose `MuscleFilterCategory.category(for: primaryMuscle)` is nil. It comes first and is omitted when empty.
- Category sections follow in `allCases` order. Empty categories are omitted.
- Entries are sorted by name with `localizedStandardCompare`.
- `counts` lists every category in `allCases` order, zeros included. Unattributed entries are not counted.

- [ ] **Step 1: Write the failing tests:** `untaggedComeFirst`, `sectionsFollowCategoryOrderAndSkipEmpty`, `entriesSortedByName` ("Lat pulldown" sorts before "lever row", ignoring case), and `countsIncludeZeros` (`counts.count == MuscleFilterCategory.allCases.count`). Build entries with `CatalogEntry(id:name:slug: nil, isCurated: false, modality: .machine, primaryMuscle:contributions: [])`, using `MuscleKey(.lats)`, `MuscleKey(.chest)` and `MuscleKey(stored: "unknown")`.
- [ ] **Step 2: Run `hardset-check core`.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `hardset-check core`.** Expected: PASS.
- [ ] **Step 5: Commit** with `Group the movement library by body part`.

### Task 8: Workout scorecard (DeepSeek, after Tasks 4 and 5)

**Files:**
- Create: `Packages/HardsetKit/Sources/HardsetCore/WorkoutScorecard.swift`
- Test: `Packages/HardsetKit/Tests/HardsetCoreTests/WorkoutScorecardTests.swift`

**Interfaces:**
- Consumes: `SetComparison` (Task 4), `TrendMetric` (Task 5), `RepRange` (Task 1).
- Produces:
  - `public struct ScorecardInput: Hashable, Sendable`, with:
    - `key: ProgressionKey`, `exerciseName: String`
    - `currentSets: [PriorSetRecord]` and `previousSets: [PriorSetRecord]`: working sets in performed order, where an empty `previousSets` means first time
    - `repRange: RepRange?`, `setRecord: Bool`, `estimatesOneRepMax: Bool`
  - `public struct WorkoutScorecard: Hashable, Sendable`, with:
    - `entries: [Entry]`, `beatenCount: Int`, `comparedCount: Int`, `recordMovementCount: Int`, `biggestGain: Gain?`
    - `public var headline: String`
    - `public struct Entry: Hashable, Sendable, Identifiable { key; exerciseName; outcome: Outcome; id: ProgressionKey }`
    - `public enum Outcome: Hashable, Sendable { case beat(SetComparison?), matched, notBeaten, firstTime }`
    - `public struct Gain: Hashable, Sendable { key; exerciseName; fraction: Double; metric: TrendMetric }`
    - `public static func make(_ inputs: [ScorecardInput]) -> WorkoutScorecard`

Rules (spec, "The scorecard counts movements"):
- Inputs with empty `currentSets` are dropped.
- Empty `previousSets` gives `.firstTime`, which is not counted in either number.
- Pair sets by index and use `SetComparison.compare(..., repFloor: repRange?.lower)`.
  - Any `.beat`, or `setRecord`, gives `.beat(best)`. `best` is the beating comparison with the largest `addedKg`, then the largest `addedReps`, or nil when only `setRecord` applies.
  - Otherwise any `.matched` gives `.matched`, else `.notBeaten`.
- `beatenCount` counts `.beat` entries. `comparedCount` counts non-first-time entries. `recordMovementCount` counts inputs with `setRecord`.
- **Gain.**
  - For each compared input where `estimatesOneRepMax` holds and both sides have an evaluable best estimate, use `.estimatedMax`.
  - Otherwise use `.heaviestLoad` when the previous heaviest is above 0.
  - `fraction = current / previous - 1`. Keep the largest positive fraction; ties go to the earlier input. With no positive fraction, it is nil.
- **Headline.** `"Beat last time on \(beatenCount) of \(comparedCount)"`. When `comparedCount == 0` it is `"First time on every movement"`.

- [ ] **Step 1: Write the failing tests:**
  - `countsMovementsNotSets`: 3 inputs (beat, matched, notBeaten) plus 1 first time gives the headline "Beat last time on 1 of 3".
  - `recordWithoutBeatingPairStillBeats`
  - `loadJumpIsABeat`: prev 40×12, cur 42.5×8, range 8–12.
  - `biggestGainUsesEstimatedMax`: A goes 40×10 → 42.5×10, about +6.25%; B goes 40×10 → 40×12, about +3.75%. Expect A, `.estimatedMax`.
  - `biggestGainFallsBackToHeaviestLoad`: 15-rep sets.
  - `allFirstTimeHeadline`
  - `emptyCurrentSetsDropped`
- [ ] **Step 2: Run `hardset-check core`.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `hardset-check core`.** Expected: PASS.
- [ ] **Step 5: Commit** with `Summarise a workout against last time`.

### Task 9: Review the DeepSeek wave (Sonnet)

- [ ] **Step 1:** Read the diffs of Tasks 1–8 against this plan and the spec. Check:
  - every rule above is implemented as written
  - there is no `import` beyond Foundation in Core
  - public types are `Sendable`
  - no test was weakened
- [ ] **Step 2:** Run `hardset-check core` and `hardset-check parse`. Expected: PASS, with the Core test count above the 232 baseline by the number of tests added.
- [ ] **Step 3: Check the cost of replaying records.** `ProgressTrendAnalyzer.trend` calls `recordSessionIDs(lastSessions: sessionCount - 1)`, which replays the detector over the whole history, so the cost grows with the square of the set count. The progress board does this for every movement.
  - Add a Core test that builds one key with 2,000 sets over 400 sessions and times `trend`.
  - If it takes more than 50 ms on Linux, cap the replay: test only the last `stallRun + 1` sessions and report a run of at least 3 as `stallRun`. Then the label always reads "Stalled · 3 sessions", which the spec allows. Keep the full replay for the single-exercise detail screen.
- [ ] **Step 4:** Fix findings in place with tests, then commit with `Tighten the progress rules after review`. Skip the commit when there is nothing to fix.

### Task 10: Schema v11 for saved workouts (Sonnet)

**Files:**
- Modify: `Packages/HardsetKit/Sources/HardsetStore/Migrations.swift`. Add `v11_savedWorkouts` after `v10_importLedgerDigests`, and add both tables to `syncedTableNames`.
- Modify: `Packages/HardsetKit/Sources/HardsetStore/Schema.swift`. Add `@Table("workoutTemplates") StoredTemplate` and `@Table("templateExercises") StoredTemplateExercise`, plus `templateID: UUID?` on `Session` and `repRangeLower: Int?` and `repRangeUpper: Int?` on `SessionExercise`.
- Modify: `Packages/HardsetKit/Sources/HardsetStore/Database.swift:121-130`. Register both tables with `SyncEngine`, parent before child.
- Modify: `Packages/HardsetKit/Tests/HardsetStoreTests/SchemaTests.swift`. Extend the synced-table expectations. This is Mac-only.
- Test: `Packages/HardsetKit/Tests/HardsetStoreTests/SavedWorkoutSchemaTests.swift`

**Interfaces:**
- Produces: the tables below and the Swift records named above.

```sql
CREATE TABLE "workoutTemplates" (
  "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
  "name" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
  "position" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
  "isArchived" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
  "createdAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now', 'subsec'))
) STRICT;
CREATE TABLE "templateExercises" (
  "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
  "templateID" TEXT NOT NULL REFERENCES "workoutTemplates"("id") ON DELETE CASCADE,
  "exerciseID" TEXT NOT NULL REFERENCES "exercises"("id") ON DELETE CASCADE,
  "machineID" TEXT REFERENCES "machines"("id") ON DELETE SET NULL,
  "position" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
  "plannedSets" INTEGER,
  "repRangeLower" INTEGER,
  "repRangeUpper" INTEGER,
  "restSeconds" INTEGER,
  "createdAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now', 'subsec'))
) STRICT;
CREATE INDEX "templateExercises_on_template" ON "templateExercises"("templateID", "position");
-- Plain TEXT, deliberately not a foreign key (the loggedSets.sessionExerciseID precedent):
-- adding a reference to an already-synced table is avoided, and templates are archived, not deleted.
ALTER TABLE "sessions" ADD COLUMN "templateID" TEXT;
CREATE INDEX "sessions_on_templateStartedAt" ON "sessions"("templateID", "startedAt" DESC) WHERE "templateID" IS NOT NULL;
ALTER TABLE "sessionExercises" ADD COLUMN "repRangeLower" INTEGER;
ALTER TABLE "sessionExercises" ADD COLUMN "repRangeUpper" INTEGER;
```

`templateExercises` has three foreign keys, so the library skips its ON DELETE check. Add a comment recording the manual audit:
- every action is CASCADE or SET NULL
- every target is a synced table
- there is no cycle or self-reference

- [ ] **Step 1: Write the failing Store tests:**
  - `migratesToV11`: the last migration identifier is `"v11_savedWorkouts"`.
  - `templateExercisesCascadeWithTemplate`
  - `deletingMachineNullsTemplateMachine`
  - `sessionTemplateIDDefaultsToNull`
  - `existingSessionsSurviveMigration`: migrate to v10, insert a session and a sessionExercise, finish migrating, and both rows are intact with null new columns. Use `migrator.migrate(queue, upTo: "v10_importLedgerDigests")`.
- [ ] **Step 2: Run `hardset-check store`.** Expected: FAIL.
- [ ] **Step 3: Implement the migration, the records and the registration.**
- [ ] **Step 4: Run `hardset-check store`, then `python3 Tools/check_query_performance.py --require-indexes`.** Expected: both PASS.
- [ ] **Step 5: Commit** with `Add saved workout tables and session template columns`.

### Task 11: TemplateStore (Sonnet)

**Files:**
- Create: `Packages/HardsetKit/Sources/HardsetStore/TemplateStore.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetFeature/HardsetRootView.swift:13-41`. Add `templates: TemplateStore` to `HardsetEnvironment`.
- Test: `Packages/HardsetKit/Tests/HardsetStoreTests/TemplateStoreTests.swift`

**Interfaces:**
- Consumes: Task 1 types, Task 10 records.
- Produces: `public nonisolated struct TemplateStore: Sendable` with:
  - `init(database: any DatabaseWriter)`
  - `func loadTemplates() async throws -> [WorkoutTemplate]`: non-archived, by `position`, with names and machine names resolved. `lastDoneAt` is the max `startedAt` of finished sessions with that `templateID`.
  - `func save(_ template: WorkoutTemplate) async throws`: upserts the template row and replaces all its `templateExercises` rows in one transaction.
  - `func archive(_ id: TemplateID) async throws`
  - `func reorder(_ ids: [TemplateID]) async throws`
  - `func draft(fromSession id: SessionID, name: String) async throws -> WorkoutTemplate`: movements in `sessionExercises` order; `plannedSets` is the count of working sets logged (clamped 1...10); machine kept; `repRange` from the session row; new `TemplateID`; not saved.
  - `func lastFinishedSession(for id: TemplateID) async throws -> SessionID?`
  - `public enum TemplateStoreError: Error, Equatable, Sendable { case blankName, noExercises, unknownExercise, notFound }`

- [ ] **Step 1: Write the failing tests:**
  - `saveAndLoadRoundTrip`
  - `saveReplacesExercises`
  - `blankNameRejected`
  - `emptyTemplateRejected`
  - `archivedTemplatesHidden`
  - `lastDoneAtIgnoresOpenSessions`
  - `draftFromSessionCountsWorkingSetsOnly`: 1 warm-up and 3 working sets give `plannedSets == 3`.
  - `editingTemplateDoesNotTouchPastSessions`: save, start a session with that `templateID`, edit the template, and the session's `sessionExercises` are unchanged.
- [ ] **Step 2: Run `hardset-check store`.** Expected: FAIL.
- [ ] **Step 3: Implement.** Copy `ProgressionStore`'s async `database.read`/`write` style and its `Task.checkCancellation()` placement.
- [ ] **Step 4: Run `hardset-check store` and the index check.** Expected: PASS.
- [ ] **Step 5: Commit** with `Store saved workouts`.

### Task 12: Targets and beat marks in the exercise state (Sonnet)

**Files:**
- Modify: `Packages/HardsetKit/Sources/HardsetCore/PriorPerformance.swift`. `SetEntryDraft` gains `public let target: SetTarget?` and `public init(target: SetTarget, suggestion: PriorSetRecord?)`, which seeds `weightKg`/`reps` from the target. Existing inits default `target` to nil.
- Modify: `Packages/HardsetKit/Sources/HardsetCore/ExerciseLogState.swift`. Changes:
  - `build` and `resume` gain `repRange: RepRange? = nil`, `weightUnit: WeightUnit = .kilograms` and `addsLoad: Bool = true`.
  - Add stored `public private(set) var repRange: RepRange?`.
  - `changeMachine` recomputes targets for unlogged rows.
  - Add `public func comparison(forSlotID id: UUID) -> SetComparison?`.
- Test: `Packages/HardsetKit/Tests/HardsetCoreTests/ExerciseLogStateTests.swift` and `ResumeTests.swift`

**Interfaces:**
- Consumes: `OverloadTarget` (Task 3), `SetComparison` (Task 4).
- Produces: the members named above.

Rules:
- Targets apply only when `repRange != nil` and the prior came from this exact key (not the other-machine fallback, so `priorNote == nil`). Otherwise rows are prefilled exactly as today.
- On `resume`, open rows get targets for their working index. Logged rows are untouched.
- `comparison` returns nil unless all of these hold:
  - the slot is logged and not a warm-up
  - the prior is this key's
  - `slot.loggedMachineID == machineID`

  It then compares the slot's resolved values with `previousSet(forSlotID:)`, using `repFloor: repRange?.lower`.

- [ ] **Step 1: Write the failing tests:**
  - `rangeWithHistoryPrefillsTargets`: last 40×10, 40×9 and range 8–12 give drafts 40×11 and 40×10, each with a non-nil `target`.
  - `otherMachineHistoryGivesNoTargets`
  - `noRangeKeepsTodaysPrefill`
  - `resumeTargetsOnlyOpenRows`
  - `changeMachineRecomputesTargets`
  - `comparisonAfterLogging`: log 40×11 against last 40×10, giving `.beat(addedKg: 0, addedReps: 1)`.
  - `warmupHasNoComparison`
  - `assumedStepFollowsUnit`: no machine step, all at top. `.kilograms` gives 42.5 and `.pounds` gives 40 + 2.26796185.
- [ ] **Step 2: Run `hardset-check core`.** Expected: FAIL.
- [ ] **Step 3: Implement.** The rest of Core must keep compiling with defaulted parameters, and every existing test passes unchanged.
- [ ] **Step 4: Run `hardset-check core`.** Expected: PASS.
- [ ] **Step 5: Commit** with `Prefill set targets and compare with last time`.

### Task 13: Start, resume and repeat from saved workouts (Sonnet)

**Files:**
- Modify: `Packages/HardsetKit/Sources/HardsetStore/SessionCoordinator.swift`. Changes:
  - `PlannedExercise` gains `repRange: RepRange? = nil`.
  - `start` gains `templateID: TemplateID? = nil` and `weightUnit: WeightUnit = .kilograms`.
  - `start` and `resume` pass `repRange`, `weightUnit` and `addsLoad` (from the exercise's modality) to `ExerciseLogState`.
  - Add `public func comparison(forSlotID:inExercise:) -> SetComparison?` passthrough.
- Modify: `Packages/HardsetKit/Sources/HardsetStore/LoggerStore.swift:41-89, 627-674`. `startSession` gains `templateID` and writes the rep range columns. `PlannedExerciseRecord` gains `repRange`. Add `func modalities(for: [ExerciseID]) throws -> [ExerciseID: ExerciseModality]`.
- Modify: `Packages/HardsetKit/Sources/HardsetStore/WorkoutRootModel.swift`. Add `public func startWorkout(from template: WorkoutTemplate, unit: WeightUnit, rest: RestPreferences) throws` and `public func repeatLastWorkout(unit: WeightUnit) throws`.
- Test: `Packages/HardsetKit/Tests/HardsetStoreTests/SessionCoordinatorTests.swift`, `SessionRecoveryTests.swift` and `WorkoutRootModelTests.swift`

Rules (spec, "Gyms", "Rest"):
- **Machine.** For each template exercise, keep `machineID` when that machine's `gymID` equals the workout's gym. Otherwise use `LoggerStore.mostRecentMachine(for:at:)` at this gym. Otherwise use nil.
- **Title and rest.** The title is the template name. Before starting, call `rest.remember(.seconds(restSeconds), for:)` for each exercise that has `restSeconds`.
- **Repeat last workout.** Use the most recent finished session's `sessionExercises`, with machines resolved the same way, its `templateID`, its rep ranges and its title. `plannedSets` is that session's working-set count per row.
- With no saved workouts, `startWorkout()` (empty) behaves exactly as today.

- [ ] **Step 1: Write the failing tests:**
  - `startFromTemplatePersistsTemplateAndRange`
  - `machineFromOtherGymIsReplacedByRecentHere`
  - `machineFromOtherGymWithNoHistoryIsDropped`
  - `restSecondsAreRemembered`: `RestPreferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)`.
  - `resumeRebuildsTargets`: start, log one set, rebuild through the recovery path, and the open rows still carry `target`.
  - `repeatLastWorkoutCopiesPlan`
  - `emptyStartUnchanged`
- [ ] **Step 2: Run `hardset-check store`.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `hardset-check store`, `hardset-check core` and the index check.** Expected: PASS.
- [ ] **Step 5: Commit** with `Start, resume and repeat workouts from saved plans`.

### Task 14: Records query, progress board and exercise detail data (Sonnet)

**Files:**
- Modify: `Packages/HardsetKit/Sources/HardsetStore/LoggerStore.swift:314-366` (`recordComparisonSets`). Append the heaviest earlier working set with `reps >= candidate.reps`. This query runs for every candidate, including bodyweight and sets above 12 reps.
- Modify: `Packages/HardsetKit/Sources/HardsetStore/VolumeStore.swift:145-260`. `ProgressionHistory` gains `recordSessionIDs: [ProgressionKey: Set<SessionID>]` and `bestAtWeight: [ProgressionKey: [BestAtWeight]]`, computed in `analyze` per series key with that machine's step.
- Create: `Packages/HardsetKit/Sources/HardsetCore/ProgressBoard.swift`
- Create: `Packages/HardsetKit/Sources/HardsetStore/ProgressBoardStore.swift`
- Test: `Packages/HardsetKit/Tests/HardsetStoreTests/RecordDetectionTests.swift`, `ProgressionStoreTests.swift` and new `ProgressBoardStoreTests.swift`

**Interfaces:**
- Produces:
  - `public struct ProgressBoard: Hashable, Sendable`, with:
    - `sections: [Section]` and `mostImproved: [Row]`
    - `public struct Section: Hashable, Sendable, Identifiable { category: MuscleFilterCategory?; rows: [Row]; id }`, where nil means "Needs a body part"
    - `public struct Row: Hashable, Sendable, Identifiable { trend: MovementTrend; exerciseName: String; machineName: String?; id: ProgressionKey }`
    - `static let empty`
  - `public nonisolated struct ProgressBoardStore: Sendable { init(database:); func loadBoard() async throws -> ProgressBoard }`

Rules:
- Read every working set with columns `exerciseID`, `machineID`, `sessionID`, `weightKg`, `reps` and `completedAt`. Group by `ProgressionKey`. Call `ProgressTrendAnalyzer.trend` with the machine's `stackIncrementKg` and the exercise modality.
- Imported-only movements (notes prefix `CatalogSeeder.importedNotesPrefix`) and archived exercises are excluded.
- Sections follow `MuscleFilterCategory.allCases` order, then the untagged section last. Rows within a section are sorted by `latestDate` descending.
- `mostImproved = ProgressTrendAnalyzer.mostImproved(allTrends)`, mapped to rows.

- [ ] **Step 1: Write the failing tests:**
  - `liveLoadAtRepsRecordAboveTwelveReps`: through `LoggerStore.logSet`, an earlier session with 30×15 and this session's 32.5×15 on a 2.5 step announces `.loadAtReps`.
  - `historyCarriesRecordSessionsAndLedger`
  - `boardGroupsByBodyPart`
  - `boardKeepsMachinesSeparate`: one exercise on two machines gives two rows.
  - `boardExcludesImportedAndArchived`
  - `boardMostImprovedLimitedToThree`
  - `emptyDatabaseGivesEmptyBoard`
- [ ] **Step 2: Run `hardset-check store`.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `hardset-check store` and `python3 Tools/check_query_performance.py --require-indexes`.** Expected: PASS. If the new `reps >=` query needs an index, add it in a `v12_…` migration and say so in the commit message; never edit v11 after it is committed.
- [ ] **Step 5: Commit** with `Read the progress board and per-machine records`.

### Task 15: Receipt scorecard and custom movement attribution (Sonnet)

**Files:**
- Modify: `Packages/HardsetKit/Sources/HardsetCore/WorkoutReceipt.swift`. Add `public let scorecard: WorkoutScorecard?` with init default nil.
- Modify: `Packages/HardsetKit/Sources/HardsetStore/ReceiptStore.swift:15-78`. Build `ScorecardInput`s and pass `WorkoutScorecard.make` to the receipt. An imported session gets nil.
- Create: `Packages/HardsetKit/Sources/HardsetCore/CustomAttribution.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetStore/CatalogSeeder.swift:110-145`
- Test: `Packages/HardsetKit/Tests/HardsetStoreTests/ReceiptStoreTests.swift` and `CustomExerciseTests.swift`, and `Packages/HardsetKit/Tests/HardsetCoreTests/CustomAttributionTests.swift`

**Interfaces:**
- Produces:
  - `public struct CustomAttribution: Hashable, Sendable`, with:
    - `primary: Muscle`, `secondary: [Muscle]`, `modality: ExerciseModality?`
    - `public init?(primary:secondary:modality:)`, which is nil when there are more than 3 secondaries, a secondary repeats, or a secondary equals the primary
    - `public var contributions: [MuscleContribution]`: the primary `.direct`, secondaries `.indirect`, all `.moderate` with source `.user`
  - On `CatalogSeeder`:
    - `public func createCustomExercise(named: String, attribution: CustomAttribution?, now: Date = Date()) throws -> CatalogEntry`. The old `createCustomExercise(named:now:)` forwards with nil. An existing name match is returned unchanged.
    - `public func updateCustomExercise(_ id: ExerciseID, name: String, attribution: CustomAttribution) throws -> CatalogEntry`
    - New `CatalogSeederError` cases `curatedNotEditable` and `duplicateName`.

Scorecard input per `ProgressionKey`, in first-performed order:
- `currentSets` are this session's working sets.
- `previousSets` are the working sets of the most recent earlier session that has working sets on that key, taken from the `prior` rows already read and grouped by `sessionID`.
- `repRange` comes from this session's `sessionExercises` row for the key.
- `setRecord` is true when any line for the key has records.
- `estimatesOneRepMax` comes from the modality.

- [ ] **Step 1: Write the failing tests:**
  - `receiptScorecardComparesWithPreviousSessionOnSameMachine`
  - `receiptScorecardFirstTime`
  - `importedReceiptHasNoScorecard`
  - `customAttributionRejectsDuplicates`
  - `createWithAttributionStoresPrimaryAndSecondaries`: `primaryMuscle == "lats"`, and the decoded contributions are lats direct and biceps indirect.
  - `updateRetagsCustomMovement`
  - `updateRefusesCurated`
  - `updateRefusesDuplicateName`
  - `volumeCountsNewlyTaggedMovement`: tag an untagged movement with logged sets, and `VolumeStore`'s weekly report now attributes them.
- [ ] **Step 2: Run `hardset-check store` and `hardset-check core`.** Expected: FAIL.
- [ ] **Step 3: Implement.** Encode with `MuscleColumn.encode`.
- [ ] **Step 4: Run both.** Expected: PASS.
- [ ] **Step 5: Commit** with `Score workouts against last time and tag custom movements`.

### Task 16: Movement library and body-part tagging UI (Sonnet)

**Files:**
- Create: `Packages/HardsetKit/Sources/HardsetUI/LibraryView.swift`. It renders `[LibrarySection]` plus a `StatLedger`-style footer of `LibraryIndex.counts`.
- Create: `Packages/HardsetKit/Sources/HardsetUI/MovementEditorSheet.swift`. It has:
  - a name field (`entryFieldChrome`)
  - body part chips (`HardsetChip`, `MuscleFilterCategory.allCases`)
  - selection rows for the specific muscle, shown when the category has more than one member
  - an optional multi-select of up to 3 secondary muscles
  - an equipment `HardsetSegmentedControl` (machine, cable, barbell, dumbbell, bodyweight)
  - a primary "Save" button

  It returns `(name: String, attribution: CustomAttribution)`.
- Create: `Packages/HardsetKit/Sources/HardsetFeature/LibraryScreen.swift`. It loads with `SnapshotLoader`, and failures go through a native alert as in DESIGN.md.
- Modify: `Packages/HardsetKit/Sources/HardsetUI/ExercisePickerView.swift` and `HardsetFeature/LiveSessionScreen.swift:183-205, 455`. The picker's create flow opens `MovementEditorSheet` prefilled with the typed name.
- Modify: `DESIGN.md`. Add "Library" and "Movement editor" entries under Components and states.
- Test: a new `Packages/HardsetKit/Tests/HardsetUISnapshotTests/LibrarySnapshotTests.swift` (macOS), following `ExercisePickerSnapshotTests.swift`.

- [ ] **Step 1:** Write the snapshot tests, covering:
  - an untagged section
  - three categories
  - footer counts
  - the editor at the default size and at accessibility XXL
- [ ] **Step 2:** Implement the views. The "Needs a body part" header uses `warning` with its symbol (`exclamationmark.triangle`), and tapping an untagged row opens the editor. Curated rows show "Curated" as a `HardsetTag` and do not open the editor.
- [ ] **Step 3:** Run `hardset-check parse` and `make check`. Expected: PASS. Snapshots run on the Mac lane; record them there.
- [ ] **Step 4:** Commit with `Add the body-part movement library and tagging`.

### Task 17: Saved workouts on the Train tab (Sonnet)

**Files:**
- Create: `Packages/HardsetKit/Sources/HardsetUI/WorkoutCardsView.swift`:
  - an up-next card in `hardsetCard`, with a `primary` `logger`-size button reading "Start \(name)"
  - a context line: "Up next · last done 4 days ago" plus, when the last session's scorecard has `comparedCount > 0`, "· beat \(beatenCount) of \(comparedCount) last time"
  - the other templates as cards with a `secondary` start button
  - "New workout" and "Repeat last workout" as `secondary` buttons
- Create: `Packages/HardsetKit/Sources/HardsetUI/WorkoutEditorView.swift`:
  - a name field and movement rows (sets stepper 1–10, rep range as two keypad fields, rest picker, machine chip)
  - reorder and delete
  - "Add movement" (dashed slot) opening `ExercisePickerView`
  - the split balance section: each `MuscleGroup` with "\(n) sets touch it", and "Nothing planned" in `warning` for each empty group
- Create: `Packages/HardsetKit/Sources/HardsetFeature/WorkoutEditorScreen.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetFeature/HardsetRootView.swift`. With no open workout, the Train tab shows `WorkoutCardsView` above the existing empty start, and the header gains a "Library" trailing action that pushes `LibraryScreen`.
- Modify: `DESIGN.md`. Add entries for workout cards, the workout editor and split balance.
- Test: `HardsetUISnapshotTests/WorkoutCardsSnapshotTests.swift` (macOS), plus a Store test in `WorkoutRootModelTests.swift`: `upNextUsesRotation`.

- [ ] **Step 1:** Write the tests.
- [ ] **Step 2:** Implement. One tap on "Start Upper A" calls `startWorkout(from:unit:rest:)`; there is no confirmation sheet. A failed start shows the existing retry banner.
- [ ] **Step 3:** Run `hardset-check store`, `hardset-check parse` and `make check`. Expected: PASS.
- [ ] **Step 4:** Commit with `Start saved workouts from the Train tab`.

### Task 18: Targets and beat marks in the set row (Sonnet)

**Files:**
- Modify: `Packages/HardsetKit/Sources/HardsetUI/SetRowView.swift`:
  - When the draft has a `target` and the row is unlogged, a provenance line reads "Target · \(target.explanation)" in `chalkDim` (`provenance` role).
  - Once logged, a `HardsetTag`-shaped mark shows `comparison.label(in:)` in `plateGreen` on `plateGreenSurface`, arriving with `hardsetArrival()`. "Matched" uses `chalkDim`.
- Modify: `Packages/HardsetKit/Sources/HardsetUI/ExerciseSectionView.swift` and `SessionView.swift`. Thread the comparisons from `SessionCoordinator.comparison(forSlotID:inExercise:)`.
- Modify: `DESIGN.md`. Add "Target line" and "Beat mark" under the set row. Neither adds motion beyond `Motion.reveal`.
- Test: extend `SetRowCatalogSnapshotTests.swift` (macOS) with a target row, a beat mark and a matched mark.

- [ ] **Step 1:** Write the tests.
- [ ] **Step 2:** Implement. The row's VoiceOver label appends ", target 11 reps" for an unlogged row and ", plus 1 rep on last time" for a logged one. The logger hit regions stay at 56 pt.
- [ ] **Step 3:** Run `hardset-check parse` and `make check`. Expected: PASS.
- [ ] **Step 4:** Commit with `Show set targets and beat-last-time marks`.

### Task 19: Progress tab and exercise detail (Sonnet)

**Files:**
- Create: `Packages/HardsetKit/Sources/HardsetUI/ProgressBoardView.swift`:
  - a "Most improved" strip with up to 3 compact rows: name, machine, "+8% in 6 weeks"
  - sections by body part, each row with a Swift Charts sparkline in `plateBlue` and its change (or "Not enough history" in `chalkDim`)
  - "Stalled · 3 sessions" in `warning` with its symbol
  - the empty state: "Log a workout and your progress shows up here."
- Create: `Packages/HardsetKit/Sources/HardsetFeature/ProgressScreen.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetFeature/HardsetRootView.swift:211-246, 866`. Add `RootTab.progress`, using `Tab("Progress", systemImage: "chart.line.uptrend.xyaxis", value: RootTab.progress)` between Train and Volume, and update the tour's `staging.tab` switch.
- Modify: `Packages/HardsetKit/Sources/HardsetUI/ProgressionChartView.swift`:
  - the default metric becomes estimated max (heaviest when `hasNoEstimates`)
  - record sessions are drawn as `plateYellow` point marks with the `star.fill` symbol
  - a "Best at each weight" table (`StatLedger`-style rows: weight, reps, date) sits under the chart
- Modify: `Packages/HardsetKit/Sources/HardsetFeature/ExerciseProgressScreen.swift`. Pass the new `ProgressionHistory` fields.
- Modify: `DESIGN.md`. Add entries for the progress board and record marks, and update the chart description.
- Test: `HardsetUISnapshotTests/ProgressBoardSnapshotTests.swift` (macOS), and an extended `TourFixturesTests.swift` so the tour still reaches every step.

- [ ] **Step 1:** Write the tests.
- [ ] **Step 2:** Implement. The six-week figure is labelled with its metric ("Estimated max +8% in 6 weeks"), and `CertaintyBadge` sits beside every estimated-max figure.
- [ ] **Step 3:** Run `hardset-check parse` and `make check`. Expected: PASS.
- [ ] **Step 4:** Commit with `Add the Progress tab`.

### Task 20: Finish scorecard, save as workout, and branch verification (Sonnet)

**Files:**
- Modify: `Packages/HardsetKit/Sources/HardsetUI/WorkoutReceiptView.swift`. A scorecard block at the top contains:
  - the headline in the `readout` role
  - a records count on `plateYellowSurface` when above 0
  - "Biggest gain: \(name) +6%" with the metric word
  - per-movement marks
  - "First time on this machine" rows in `chalkDim`
- Modify: `Packages/HardsetKit/Sources/HardsetFeature/WorkoutReceiptScreen.swift` and `LiveSessionScreen.swift`:
  - Finishing a workout navigates to its receipt. If it already does, keep it.
  - The receipt gains "Save as workout", which uses `NameEntrySheet`, then `TemplateStore.draft(fromSession:name:)`, then `WorkoutEditorScreen`.
- Modify: `.agents/HANDOFF.md`. Append a section for this feature using the existing protocol.
- Test: `ReceiptStoreTests` already covers the data, and the scorecard gets snapshots in `ScreenSnapshotTests.swift` (macOS).

- [ ] **Step 1:** Write the snapshot test.
- [ ] **Step 2:** Implement. The share text (`WorkoutReceipt.text`) starts with the headline line.
- [ ] **Step 3:** Run `make check`. Expected: all targets PASS, including the contrast check and the query index check. Record the actual Core and Store test counts.
- [ ] **Step 4:** Run `/code-review` (or a fresh reviewer) over the branch diff against `main`, fix confirmed findings with tests, and re-run `make check`.
- [ ] **Step 5:** Commit with `Show the workout scorecard and save workouts from receipts`. Report to the owner:
  - Linux results
  - that UI is not visually verified until `make mac-test` and the macOS CI screenshot job run
  - the delivery question: a PR, or a push to `main` per AGENTS.md
