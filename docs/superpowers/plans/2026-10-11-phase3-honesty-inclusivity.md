# Phase 3 — Honesty as a Visual Language, and Inclusivity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** every derived number says how sure it is and where it came from, in a glyph and a word,
one tap from its source; the chart says what changed on one machine and VoiceOver hears the same
chart; the logger works with VoiceOver and at accessibility text sizes; a first-time lifter gets one
honest screen; history opens into a past workout; gyms and machines can be renamed and archived;
Core's copy is ready for a second language; and the root view and the certainty mirror are gone.

**Architecture:** behaviour lands in `HardsetCore` (pure values) or `HardsetStore` (GRDB), test-first,
verified by `Tools/linux-test.sh`:
- *Core:* certainty marks and caveats, "In short" summaries, the DOI link and the credit scheme,
  per-number certainty, the chart's headline, scrub readout and VoiceOver description, every spoken
  sentence, locale decimals, equipment names, first-run copy and unit inference, the session-detail
  grouping, muscle names, and the localization seam
- *Store:* distinct series labels, gym and machine rename, the first-run decision, and the session
  detail reader

`HardsetUI` and `HardsetFeature` tasks only render those values and wire callbacks. They cannot
compile on Linux, so each adds `docs/MAC-VERIFICATION.md` entries under `## Phase 3`. There is no
schema change.

**Tech Stack:** Swift 6.2 (Swift 6 language mode, `NonisolatedNonsendingByDefault`), Swift Testing,
GRDB 7 / SQLiteData 1.x (StructuredQueries), SwiftUI and Swift Charts for iOS 26.1, the
Accessibility framework (`AXChartDescriptor`). The Mac's `./test.sh` also builds HardsetUI and
HardsetFeature for macOS 15.

**Spec:** `docs/superpowers/specs/2026-10-10-hardset-ada-polish-design.md` §9 (Phase 3, items
3.1–3.9), under the §3 direction, the §4 non-negotiables and the §5 verification strategy. This plan
builds on `docs/superpowers/plans/2026-10-10-phase1-trust.md` and
`docs/superpowers/plans/2026-10-10-phase2-core-loop.md`; their Produces blocks are treated as
existing code once merged (see Scheduling for which are).

## Global Constraints

- **Every invariant in `HANDOFF.md` §5 and every refusal in §6.** No target, goal, streak, program
  or questionnaire anywhere, including the first-run screen. No default rest. Machine series are
  never merged (`DECISIONS.md` §20), in a chart, a headline, a VoiceOver description or a session
  detail.
- **The methodology text pinned by tests is never edited** (spec §4). `methodology`, `validRange`
  and `citation` stay byte-identical. Plain-language summaries are the *new* field
  `EvidenceSource.summary`. The 0.5 indirect credit is an adopted convention, not a finding, and no
  new copy may say it was fitted or that the app is entitled to it (`DECISIONS.md` §17).
- **Certainty is a glyph and a word, never colour alone.** Every badge shows `CertaintyMark.word`
  or `.shortWord` beside `CertaintyMark.symbolName`. A caveat (lower bound, other machine, length
  unknown) is the tested grey with a calm glyph, never orange and never an `exclamationmark.*` or
  `xmark.*` symbol (spec §3, item 2).
- **Certainty and source come from Core.** The UI never derives a certainty or picks a source; it
  reads `MuscleVolumeReport.certainty(for:)`, `WorkoutSummary.MuscleLine.certainty`,
  `ProgressionPoint.bestEstimateCertainty`, `PersonalRecord.estimateCertainty` and the
  `EvidenceSource` constants.
- **Units are spoken in full.** Every VoiceOver string for a weight goes through
  `WeightFormatter.spoken(kilograms:)` or `spokenTotal(kilograms:)`, never `abbreviation`.
- **Numbers follow the lifter's locale.** Decimals go through `WeightFormatter.text`, `CountText`,
  `WorkoutSummary.MuscleLine.countText(locale:)` or `NumericEntryBuffer.displayText(locale:)`.
  No `String(format: "%.1f")` reaches a screen.
- **Kilograms are canonical.** Conversion goes through `WeightUnit` only, display through
  `WeightFormatter` only.
- **No schema change.** Rename uses the existing `gyms.name`, `machines.name` and `machines.brand`
  columns. The first-run flag is device-local `UserDefaults`, already declared (CA92.1). A task that
  finds it needs a schema change stops and asks for a `DECISIONS.md` entry first.
- **Never edit these:** `ExerciseCatalog.swift`; methodology text pinned by tests.
  `HardsetApp.swift` stays wiring only; no task in this phase touches it.
- **No set is ever logged from outside the app UI.** The set row's VoiceOver default action logs
  only what the row shows, through the same `onLog` the check mark calls.
- **Persist before claiming.** The first-run flag is set only after its optional gym is written. A
  rename is shown only after the write succeeds.
- **Motion honours Reduce Motion, always.** Any new animation uses `Tokens.Motion`.
- **Localization (`DECISIONS.md` §23, added by Task 10):** Core copy goes through
  `localized(_:comment:)` in `HardsetCore/Localized.swift`, never `String(localized:)` directly,
  because the Linux Foundation has neither `String(localized:)` nor `LocalizedStringResource`
  (checked in the swift:6.2 container on 2026-10-11). Interpolate only `String` and `Int` into a
  `localized` literal. Nothing may depend on Core's String Catalog until Task 10's ledger entry is
  checked on the Mac (spec 3.8, "verified on the Mac before anything is built on top of it").
- **Isolation:**
  - Core types are `nonisolated` by module default.
  - Store types that touch the database are explicitly `nonisolated`.
  - Store protocols and their classes (`FirstRunFlag`) are `nonisolated`, as `RestPreferenceStore` is.
- **Store tests build databases with `Configuration.forTesting()`**, never `Configuration()`, with
  `foreignKeysEnabled = true`.
- **Verification:**
  - Core and Store tasks: `Tools/linux-test.sh` (optionally `--filter '<Suite>|<Suite>'`) must
    pass, in full, before commit.
  - UI and Feature tasks: add `docs/MAC-VERIFICATION.md` entries under a `## Phase 3` heading
    (create it once, at the end of the file, if absent). The ledger merges by union
    (`.gitattributes`), so parallel tasks may all append.
- **API discipline for Mac-only code:**
  - Every Apple API not already used in this codebase is confirmed against developer.apple.com.
    Fetch `https://developer.apple.com/tutorials/data/documentation/<path>.json`, because the HTML
    pages render client-side and WebFetch returns only their titles. Put the human URL in the
    commit body. Each Mac-only task lists the URLs, already checked on 2026-10-11 with their
    availability.
  - Anything newer than iOS 26.1 needs `#available`.
  - The package is also built for macOS 15, so any API first available in macOS 26 needs
    `if #available(iOS 26.0, macOS 26.0, *)` or `#if os(iOS)`. `fullScreenCover` is iOS-only, which
    is why the first-run screen replaces the tabs instead of covering them.
  - SF Symbol names cannot be checked off a Mac. Each new name is listed in its task's ledger entry
    to confirm in the SF Symbols app; a missing one renders blank.
- **Commits:** messages explain *why*, and end with `Co-Authored-By: <your model's trailer>`.
  Never `git push`.

## Review Focus

- **Two machines that share a name.** Two unbranded "Leg Press" stacks, or one model at two gyms,
  were labelled alike, and the chart keys a line by its label, so it drew one line through two
  machines. Each machine must keep its own line and its own label. Pinned in Task 4
  (`sameNamedMachinesStayApart`, `brandLeads`).
- **A chart across a machine switch.** 110 kg on the Hammer, then 90 kg on the Cybex, is not
  "−20 kg". The headline must describe the machine used last, from its own first session to its
  own last, and VoiceOver's description must keep one series per machine. In pounds the change must
  be the difference of the two numbers on screen. Pinned in Task 4 (`headlineNeverSpansMachines`,
  `descriptionKeepsSeriesApart`, `deltaMatchesDisplayedNumbers`).
- **First run for someone who already trains.** An update reaches lifters with history and a flag
  that never existed, and some with a workout left open. Neither may be greeted as a stranger, and
  an open workout must never hide behind a welcome. Pinned in Task 7
  (`existingHistorySkipsFirstRun`, `openWorkoutSkipsFirstRun`).
- **Blank or padded names.** An optional gym field left as spaces, or a rename to "  ", must create
  or write nothing, and leave the old name. "  Iron   Temple " is stored as "Iron Temple". Pinned in
  Task 6 (`renameToBlankLeavesName`, `blank`) and Task 7 (`blankGymNameCreatesNoGym`).
- **One movement on two machines in a past workout.** The detail must show the Hammer sets and the
  Cybex sets as two blocks, each named, and a machine archived since must keep its name rather than
  turning into free weight. Pinned in Task 8 (`sameExerciseTwoMachinesTwoBlocks`,
  `archivedMachineStillNamed`).

## How this plan reads the spec

The spec leaves these points open. Each resolution is binding for the tasks, and pinned by a test
where it is behaviour.

1. **`String(localized:)` does not compile on Linux.** The swift:6.2 container's Foundation has
   neither `String(localized:)` (any overload) nor `LocalizedStringResource` nor
   `AttributedString(localized:)`; `Bundle.localizedString(forKey:value:table:)`, `String(format:)`
   and `.xcstrings` resources (copied, not compiled) do work. So "Core copy moves to
   `String(localized:)`" is met through one internal seam, `localized(_:comment:)`, whose Apple
   branch is `String(localized: text, bundle: .module, comment:)` with `text` a
   `String.LocalizationValue`, and whose Linux branch returns the English. The same copy tests run
   on both platforms, so they pin both branches. Recorded as `DECISIONS.md` §23 (Task 10).
2. **The String Catalog is Core's, and the risky step is isolated.** Task 10 adds
   `defaultLocalization: "en"`, a resource to HardsetCore only, and the seam, and nothing else.
   Its fallback, if the Mac's resource step fails, changes only `Package.swift`, the catalog file
   and the two Apple branches in `Localized.swift`. Task 11, which routes Core's copy through the
   seam, waits for Task 10's ledger entry to be checked on the Mac. Catalogs for HardsetUI and
   HardsetFeature are **not** added: SwiftUI `Text("…")` looks up `Bundle.main`, so a package
   catalog would need `bundle: .module` on every literal, a sweeping edit with no effect in an
   English-only build. UI literals are already `LocalizedStringKey`s; where their catalog lives is
   decided when a second language is actually added. Store's `FailureCopy` stays English for the
   same reason (its own resource bundle would be a second risky step).
3. **"Per-muscle certainty replaces the global 'Moderate' header."** Each muscle row on the Volume
   tab and in the summary carries its own compact badge; "How sets are counted" opens the sheet
   with no certainty header (`certainty: nil`); tapping a row's badge opens it with that row's
   certainty. `MuscleVolumeReport.highestCertainty` stays (it is tested API) but loses its caller.
4. **Which numbers are "derived".** Estimated 1RMs (chart, records on the row, in the summary and
   in the session detail) and fractional set counts (Volume tab, summary, lower bounds) get badges.
   Measured loads, rep counts, and session totals do not: they are what was lifted, not estimates.
   An unrecognised muscle token's count is `.low`, never `.unevaluated`, because a figure is shown.
5. **The lower bound** keeps its "≥" in the number (it is the caveat, said in the number) and gets
   the calm `CaveatMark.lowerBound` glyph instead of `exclamationmark.circle`. Low certainty's glyph
   moves from `exclamationmark.triangle` to `circle.dashed` for the same reason: a low-confidence
   figure is a caveat, not an error.
6. **`AssumptionChip` and `UnevaluatedReadout` get real uses.** No `Claim` carries assumptions
   today, so the chip is used where the app genuinely guessed: loads borrowed from another machine
   (correction: choose the machine) and the unit inferred from the region on the first-run screen
   (correction: change it). `UnevaluatedReadout` replaces the chart's plain "No estimate" caveat.
7. **"Plain titles" on the methodology sheet** means plain section headings ("In short", "How it
   works", "Where it holds, and where it does not", "Source") and an inline navigation title.
   `EvidenceSource.title` is part of the disclosure record and is not renamed.
8. **The chart headline** is "Label: +5 kg over N sessions" for loads and "Label: about +6 kg over
   N sessions" for estimates, for the series used most recently; N counts sessions that have a
   value for the metric. A single session reads "Label: 100 kg, 1 session"; equal ends read "no
   change". Values are compared as displayed (two decimals for loads, `displayRounded` for
   estimates), so the delta is the difference of the numbers on screen.
9. **Scrubbing** shows the logged session nearest the finger, on its own machine, never an
   interpolated value.
10. **First run** shows only when the flag is unset *and* no session exists, open or finished. It
    replaces the tabs (no cover, which is iOS-only). Start completes it; the gym is optional; the
    unit is the region's guess, shown as an `AssumptionChip` beside a kg/lb picker that writes the
    existing `hardset.useImperial` key. The flag defaults to `UserDefaultsFirstRunFlag` through
    `HardsetEnvironment`, so `HardsetApp.swift` is untouched.
11. **History rows "not dimmed"** was fixed in Phase 1 (`HistoryView.selectable`); Task 17 makes
    them buttons and its ledger re-checks it. **Rest buttons "reachable"** was fixed by Phase 2
    Task 15 for the expanded accessory; Task 15 here adds the same actions to the collapsed
    (`.inline`) accessory, where the buttons are not drawn.
12. **"Rename and archive, using the existing GymStore APIs."** Archive exists; rename does not, so
    Task 6 adds `renameGym` and `renameMachine` beside it. `createGym` and `createMachine` are not
    changed (no drive-by); callers normalise with `EquipmentName` first.
13. **Session detail** reuses `WorkoutSummary` for length, totals and records, and adds blocks by
    movement and machine. Returning to a machine later in the workout joins its block; another
    machine is another block.

## Scheduling (for the controller)

**Preconditions:**
- Phase 1 is fully merged (it is, at `782531a`).
- Phase 2 Tasks 1–13 and 15–17 are merged (they are, at `40fc33b`). Phase 2 Tasks **14, 18 and 19
  are still in flight** and own `SetRowView`, `ExerciseSectionView`, `SessionView`, `NumericPad`,
  `LiveSessionScreen`, `HardsetRootView` and `HistoryScreen`. Phase 3 never edits those files
  before the owning Phase 2 task merges:
  - Task 15 (logger accessibility) starts only after Phase 2 **Task 14** merges. It builds on
    Task 14's `SetRowView(records:recordPulse:…)`, its record caption, and the
    `.onChange(of: feedback)` announcement in `SessionView`.
  - Tasks 16–19 start only after Phase 2 **Task 19** merges (which follows Task 18). They build on
    `TabView(selection:)`, the `RestBarView` accessory, `HardsetEnvironment.summaries` and
    `.shortcuts`, and `HistoryScreen(store:unit:onRepeat:)`.
  - No Phase 3 task edits `LiveSessionScreen.swift`.
- Core and Store tasks (1–11) and the Mac-only Tasks 12–14 touch none of those files and may run now.

Line numbers below were read at commit `40fc33b`. They are anchors; the symbol names are
authoritative. Every Core and Store code block in Tasks 1–10 was compiled and run in the swift:6.2
container against a copy of the package at that commit: with Tasks 1–10 applied together the full
suite is 588 tests in 79 suites, all passing.

Tasks with disjoint files may run in parallel, each in its own worktree branched from the current
tip of `FrankieBiz/perfect-app-polish-agents`. They merge back one at a time, rebased on the tip,
with `Tools/linux-test.sh` rerun after each merge. `docs/MAC-VERIFICATION.md` is union-merged, so it
is not an ownership conflict. Paths are relative to `Packages/HardsetKit/Sources/` (sources) and
`Packages/HardsetKit/Tests/` (tests).

| Task | Files owned | Depends on |
|---|---|---|
| 1 Certainty marks and caveats (Core) | HardsetCore/CertaintyMark.swift, HardsetCoreTests/CertaintyMarkTests.swift | — |
| 2 "In short", the DOI link, the credit scheme (Core) | HardsetCore/Certainty.swift, HardsetCore/MuscleTaxonomy.swift, HardsetCore/MuscleVolume.swift, HardsetCore/StrengthMath.swift, HardsetCore/Progression.swift, HardsetCoreTests/EvidenceSummaryTests.swift | — |
| 5 Spoken words and locale decimals (Core) | HardsetCore/AccessibleText.swift, HardsetCore/WeightFormatter.swift, HardsetCore/SetEntryKeypad.swift, HardsetCoreTests/AccessibleTextTests.swift | — |
| 6 Equipment names; rename (Core, Store) | HardsetCore/EquipmentName.swift, HardsetStore/GymStore.swift, HardsetStore/FailureCopy.swift, HardsetCoreTests/EquipmentNameTests.swift, HardsetStoreTests/GymRenameTests.swift, HardsetStoreTests/FailureCopyTests.swift | — |
| 8 Session detail (Core, Store) | HardsetCore/SessionDetail.swift, HardsetStore/SessionDetailStore.swift, HardsetCoreTests/SessionDetailTests.swift, HardsetStoreTests/SessionDetailStoreTests.swift | — |
| 9 Muscle names in Core | HardsetCore/MuscleNames.swift, HardsetCoreTests/MuscleNamesTests.swift | — |
| 10 Localization seam and String Catalog (Core; Mac gate) | Package.swift, HardsetCore/Localized.swift, HardsetCore/Resources/Localizable.xcstrings, HardsetCoreTests/LocalizedTests.swift, DECISIONS.md | — |
| 3 A certainty for every derived number (Core) | HardsetCore/MuscleVolume.swift, HardsetCore/WorkoutSummary.swift, HardsetCore/Progression.swift, HardsetCore/PersonalRecords.swift, HardsetCoreTests/DerivedCertaintyTests.swift | 2 |
| 7 First run (Core, Store) | HardsetCore/FirstRun.swift, HardsetStore/FirstRunStore.swift, HardsetCoreTests/FirstRunTests.swift, HardsetStoreTests/FirstRunStoreTests.swift | 6 |
| 4 The chart's words; distinct labels (Core, Store) | HardsetCore/ProgressionChartModel.swift, HardsetStore/VolumeStore.swift, HardsetUI/ProgressionChartView.swift (mechanical), HardsetCoreTests/ProgressionChartModelTests.swift, HardsetStoreTests/ProgressionChartSeriesTests.swift | 3 |
| 12 Badges and the sheet; the mirrors removed (Mac-only) | HardsetUI/CertaintyBadge.swift, HardsetUI/MethodologySheet.swift, HardsetUI/DesignTokens.swift, HardsetUI/ExercisePickerView.swift, plus one-line `displayName` edits in HardsetUI/VolumeReportView.swift and HardsetUI/WorkoutSummaryView.swift | 1, 2, 9 |
| 13 Volume figures carry their certainty (Mac-only) | HardsetUI/VolumeReportView.swift, HardsetUI/WorkoutSummaryView.swift, HardsetUI/HistoryView.swift, HardsetFeature/WeeklyVolumeScreen.swift | 3, 5, 12 |
| 14 The chart, crafted (Mac-only) | HardsetUI/ProgressionChartView.swift, HardsetFeature/ExerciseProgressScreen.swift | 4, 12 |
| 11 Core copy through the seam (Core) | every HardsetCore file with user-facing copy (listed in the task), HardsetCore/Resources/Localizable.xcstrings, HardsetCoreTests/LocalizedTests.swift | 10 **checked on the Mac**, and 1–9 merged |
| 15 The logger with VoiceOver and large text (Mac-only) | HardsetUI/SetRowView.swift, HardsetUI/NumericPad.swift, HardsetUI/ExerciseSectionView.swift, HardsetUI/SessionView.swift, HardsetUI/RestBarView.swift | 1, 3, 5, 12, **Phase 2 Task 14** |
| 16 Split the root (Mac-only) | HardsetFeature/HardsetRootView.swift, HardsetFeature/HardsetEnvironment.swift (new), HardsetFeature/StartWorkoutView.swift (new), HardsetFeature/GymPickerSheet.swift (new), HardsetFeature/LiveSessionAccessory.swift (new) | **Phase 2 Task 19** |
| 17 A past workout, opened (Mac-only) | HardsetUI/SessionDetailView.swift (new), HardsetFeature/HistoryScreen.swift, HardsetFeature/HardsetEnvironment.swift, plus the `HistoryScreen(` call in HardsetFeature/HardsetRootView.swift | 5, 8, 12, 14, 16 |
| 18 The first-run screen (Mac-only) | HardsetUI/FirstRunView.swift (new), HardsetFeature/HardsetRootView.swift, HardsetFeature/HardsetEnvironment.swift | 1, 7, 16, 17 |
| 19 Gyms and machines (Mac-only) | HardsetFeature/GymsScreen.swift (new), HardsetFeature/SettingsSheet.swift, plus the `SettingsSheet(` call in HardsetFeature/HardsetRootView.swift | 6, 16, 18 |

**Waves:**
- Wave 1: 1, 2, 5, 6, 8, 9 and 10, in parallel.
- Wave 2: 3 and 7, in parallel.
- Wave 3: 4 and 12, in parallel.
- Wave 4: 13 and 14, in parallel.
- **Mac gate:** push nothing; when the user next builds on the Mac, check Task 10's ledger entry.
  Then Task 11 (Core only, Linux-verified).
- **After Phase 2 Task 14 merges:** Task 15. It may run alongside 16–19, whose files are disjoint.
- **After Phase 2 Task 19 merges:** 16, then 17, then 18, then 19, one at a time: each edits
  `HardsetRootView.swift` and most edit `HardsetEnvironment.swift`.

**Rule:** no task may leave a caller of an API it changed uncompiled. A task that changes a
signature updates every call site in the same task, even in files another task owns later. Those
edits are mechanical, nothing more, and each is named in its task. Task 4's edit to
`ProgressionChartView.swift` and Task 12's edits to `VolumeReportView.swift` and
`WorkoutSummaryView.swift` are of this kind, which is why 13 and 14 follow them.

---

### Task 1: Certainty marks and caveats (Core)

**Files:**
- Create: `Packages/HardsetKit/Sources/HardsetCore/CertaintyMark.swift`
- Test: `Packages/HardsetKit/Tests/HardsetCoreTests/CertaintyMarkTests.swift`

**Interfaces:**
- Consumes: `Certainty`, `Assumption`, `Palette.Role`, `WeightUnit`.
- Produces, for Tasks 12–15 and 18:
  - `public struct CertaintyMark: Hashable, Sendable` with `certainty`, `symbolName`, `word`,
    `shortWord`, `role: Palette.Role`, and `static func of(_ certainty: Certainty) -> CertaintyMark`
  - `extension Certainty { public var mark: CertaintyMark }`
  - `public struct CaveatMark: Hashable, Sendable` with `symbolName`, `word`, `role`, and the
    constants `.lowerBound`, `.otherMachine`, `.lengthUnknown`, plus `static let all`
  - `extension Assumption`: `static let borrowedFromOtherMachine` and
    `static func unitFromRegion(_ unit: WeightUnit) -> Assumption`

Rules (each a test below): every level has its own glyph and its own word; the words are the badge's
existing words ("High confidence", "Moderate confidence", "Low confidence", "Not evaluated"); each
level takes its own certainty colour role; no certainty or caveat uses an error glyph; caveats are
the tested grey (`.certaintyUnevaluated`, which is what `Tokens.Color.caveat` already uses).

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing

@testable import HardsetCore

@Suite("Certainty reads as a glyph and a word, and a caveat never looks like an error")
struct CertaintyMarkTests {
  @Test("Each level has its own glyph and its own word, so colour is never the only signal")
  func distinct() {
    let marks = Certainty.allCases.map(\.mark)
    #expect(Set(marks.map(\.symbolName)).count == Certainty.allCases.count)
    #expect(Set(marks.map(\.word)).count == Certainty.allCases.count)
    #expect(Set(marks.map(\.shortWord)).count == Certainty.allCases.count)
    for mark in marks {
      #expect(!mark.symbolName.isEmpty)
      #expect(!mark.word.isEmpty)
    }
  }

  @Test("The words are the ones the badge has always shown")
  func words() {
    #expect(Certainty.high.mark.word == "High confidence")
    #expect(Certainty.moderate.mark.word == "Moderate confidence")
    #expect(Certainty.low.mark.word == "Low confidence")
    #expect(Certainty.unevaluated.mark.word == "Not evaluated")
    #expect(Certainty.moderate.mark.shortWord == "Moderate")
  }

  @Test("Each level takes its own certainty colour, never a semantic one")
  func roles() {
    #expect(Certainty.high.mark.role == .certaintyHigh)
    #expect(Certainty.moderate.mark.role == .certaintyModerate)
    #expect(Certainty.low.mark.role == .certaintyLow)
    #expect(Certainty.unevaluated.mark.role == .certaintyUnevaluated)
    for certainty in Certainty.allCases {
      #expect(![.success, .record, .caution, .critical].contains(certainty.mark.role))
      #expect(certainty.mark.certainty == certainty)
    }
  }

  @Test("No certainty or caveat borrows an error's glyph")
  func noErrorGlyphs() {
    let glyphs = Certainty.allCases.map(\.mark.symbolName) + CaveatMark.all.map(\.symbolName)
    for glyph in glyphs {
      #expect(!glyph.hasPrefix("exclamationmark"))
      #expect(!glyph.hasPrefix("xmark"))
    }
  }

  @Test("Caveats are the tested grey, never orange")
  func caveatsAreGrey() {
    for caveat in CaveatMark.all {
      #expect(caveat.role == .certaintyUnevaluated)
      #expect(!caveat.word.isEmpty)
    }
    #expect(Set(CaveatMark.all.map(\.symbolName)).count == CaveatMark.all.count)
  }

  @Test("An inferred unit is stated in words, with its correction")
  func unitAssumption() {
    let pounds = Assumption.unitFromRegion(.pounds)
    #expect(pounds.label == "Weights in pounds, from your region")
    #expect(pounds.correctionPrompt == "Change the unit")
    #expect(Assumption.unitFromRegion(.kilograms).label == "Weights in kilograms, from your region")
    #expect(Assumption.borrowedFromOtherMachine.correctionPrompt == "Choose the machine you're on")
  }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `Tools/linux-test.sh --filter CertaintyMarkTests`
Expected: compile failure, `value of type 'Certainty' has no member 'mark'`.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// How a certainty looks and reads: a glyph and a word, never colour alone.
///
/// Certainty is a visual system (spec §3, item 2). The words and glyphs used to live in
/// `HardsetUI` as `CertaintyLevel`, a mirror of `Certainty` that no test could reach. They are
/// decided here instead, so the claim "each level has its own shape and its own word" is checked on
/// every run, and the UI only draws what this says.
public struct CertaintyMark: Hashable, Sendable {
  public let certainty: Certainty
  /// An SF Symbol. Each level has its own shape, so the level reads with colour turned off.
  public let symbolName: String
  /// The badge text: "Moderate confidence".
  public let word: String
  /// For dense rows, where the full word would repeat down a list: "Moderate".
  public let shortWord: String
  /// The colour role. A second carrier of the level, never the only one.
  public let role: Palette.Role

  public static func of(_ certainty: Certainty) -> CertaintyMark {
    switch certainty {
    case .high:
      CertaintyMark(
        certainty: .high, symbolName: "checkmark.seal", word: "High confidence",
        shortWord: "High", role: .certaintyHigh)
    case .moderate:
      CertaintyMark(
        certainty: .moderate, symbolName: "circle.lefthalf.filled", word: "Moderate confidence",
        shortWord: "Moderate", role: .certaintyModerate)
    case .low:
      // A dashed circle, not a warning triangle: a low-confidence figure is a caveat about a
      // number, and a warning glyph made it read as an error (spec §3, item 2).
      CertaintyMark(
        certainty: .low, symbolName: "circle.dashed", word: "Low confidence",
        shortWord: "Low", role: .certaintyLow)
    case .unevaluated:
      // Stated plainly rather than hidden: the app's claim is that it says when it does not know.
      CertaintyMark(
        certainty: .unevaluated, symbolName: "questionmark.circle", word: "Not evaluated",
        shortWord: "Not evaluated", role: .certaintyUnevaluated)
    }
  }
}

extension Certainty {
  /// The glyph and word for this level.
  public var mark: CertaintyMark { .of(self) }
}

/// A caveat on a number: true, worth saying, and not an error.
///
/// Each one is grey text with a calm glyph. The lower bound used to be orange with an exclamation
/// mark, which made "at least this much" read as a failure (spec §3, item 2).
public struct CaveatMark: Hashable, Sendable {
  public let symbolName: String
  /// Shown beside the glyph.
  public let word: String
  /// The colour role. The palette's tested neutral, never a warning colour.
  public let role: Palette.Role

  /// "≥ 8 sets": some sets could not be attributed, so the figure is a floor.
  public static let lowerBound = CaveatMark(
    symbolName: "greaterthan.circle", word: "At least", role: .certaintyUnevaluated)
  /// The suggested loads came from another machine's history.
  public static let otherMachine = CaveatMark(
    symbolName: "arrow.triangle.branch", word: "From another machine", role: .certaintyUnevaluated)
  /// A session left open longer than any real workout (`DECISIONS.md` §21).
  public static let lengthUnknown = CaveatMark(
    symbolName: "clock.badge.questionmark", word: "Length unknown", role: .certaintyUnevaluated)

  public static let all: [CaveatMark] = [.lowerBound, .otherMachine, .lengthUnknown]
}

extension Assumption {
  /// The suggested loads were borrowed from the same movement on a different machine, because
  /// this machine has no history. The correction is choosing the machine the lifter is on.
  public static let borrowedFromOtherMachine = Assumption(
    id: "prefill.otherMachine",
    label: "From another machine",
    correctionPrompt: "Choose the machine you're on"
  )

  /// The unit was guessed from the device's region, not chosen (spec 3.5).
  public static func unitFromRegion(_ unit: WeightUnit) -> Assumption {
    let name =
      switch unit {
      case .kilograms: "kilograms"
      case .pounds: "pounds"
      }
    return Assumption(
      id: "unit.fromRegion",
      label: "Weights in \(name), from your region",
      correctionPrompt: "Change the unit"
    )
  }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `Tools/linux-test.sh --filter CertaintyMarkTests`, then `Tools/linux-test.sh`.
Expected: PASS (6 tests), and the full suite green.

- [ ] **Step 5: Commit**

```bash
git add Packages/HardsetKit/Sources/HardsetCore/CertaintyMark.swift \
  Packages/HardsetKit/Tests/HardsetCoreTests/CertaintyMarkTests.swift
git commit -m "feat(core): certainty as a glyph and a word, decided where a test can see it

The badge's words and glyphs lived in HardsetUI as CertaintyLevel, a mirror of
Certainty nothing could test. They move to Core as CertaintyMark, with the rule
that each level has its own shape and word, so colour is never the only signal.
Low confidence trades its warning triangle for a dashed circle, and the three
caveats (at least, from another machine, length unknown) get calm grey glyphs:
a lower bound is a true statement, not an error.

Co-Authored-By: <your model's trailer>"
```

---

### Task 2: "In short", the DOI link, and the credit scheme (Core)

**Files:**
- Modify: `Packages/HardsetKit/Sources/HardsetCore/Certainty.swift:42-63` (`EvidenceSource`)
- Modify: `Packages/HardsetKit/Sources/HardsetCore/MuscleTaxonomy.swift:353-389`
  (`SetCounting.source`, after `certaintyCeiling`)
- Modify: `Packages/HardsetKit/Sources/HardsetCore/MuscleVolume.swift:180-248` (two sources)
- Modify: `Packages/HardsetKit/Sources/HardsetCore/StrengthMath.swift:18-37` (two sources)
- Modify: `Packages/HardsetKit/Sources/HardsetCore/Progression.swift:209-224` (one source)
- Test: `Packages/HardsetKit/Tests/HardsetCoreTests/EvidenceSummaryTests.swift`

**Interfaces:**
- Consumes: `WeightFormatter.text(_:fractionDigits:locale:)` (internal, same module),
  `MuscleRole.allCases`, `SetCounting.weight(_:)`.
- Produces, for Tasks 12–14 and 17:
  - `EvidenceSource.summary: String?`, and `init(id:title:methodology:citation:validRange:summary:)`
    with `summary` defaulting to nil, so every existing call compiles
  - `EvidenceSource.doiURL: URL?`
  - `static var EvidenceSource.shipped: [EvidenceSource]`
  - `SetCounting.creditScheme(locale: Locale = .current) -> [CreditTier]`
  - `public struct CreditTier: Hashable, Sendable, Identifiable` with `role`, `credit`,
    `creditText`, `meaning`, `basis`, `id: MuscleRole`

`EvidenceSource` is `Codable`; the synthesised decoder reads a missing optional `summary` as nil, so
nothing previously encoded stops decoding (nothing encodes it today).

- [ ] **Step 1: Write the failing test**

The two "unchanged, character for character" tests hold the pinned text exactly as it is at
`40fc33b`. They are the guard Task 11 relies on when it wraps the same text in `localized(…)`.

```swift
import Foundation
import Testing

@testable import HardsetCore

@Suite("Every source says it in short, links its DOI, and keeps its methodology word for word")
struct EvidenceSummaryTests {
  @Test("Every shipped source has a one-sentence summary", arguments: EvidenceSource.shipped)
  func summaryIsOneSentence(source: EvidenceSource) throws {
    let summary = try #require(source.summary)
    #expect(!summary.isEmpty)
    #expect(summary.count <= 200)
    #expect(summary.hasSuffix("."))
    // One sentence: no full stop followed by a space anywhere before the end.
    #expect(!summary.dropLast().contains(". "))
  }

  @Test("No summary claims the weights were fitted or that the app is entitled to them")
  func summariesDoNotOverclaim() {
    for source in EvidenceSource.shipped {
      let summary = (source.summary ?? "").lowercased()
      #expect(!summary.contains("fitted"))
      #expect(!summary.contains("entitled"))
      #expect(!summary.contains("proven"))
    }
    let counting = SetCounting.source.summary ?? ""
    #expect(counting.contains("convention"))
    #expect(!counting.lowercased().contains("finding"))
  }

  @Test("Shipped sources have distinct ids")
  func distinctIDs() {
    #expect(Set(EvidenceSource.shipped.map(\.id)).count == EvidenceSource.shipped.count)
  }

  /// The methodology is what App Review reads, and spec §4 forbids editing it. A summary is a new
  /// field; this holds the old text to the character.
  @Test("The fractional-counting disclosure is unchanged, character for character")
  func countingTextUnchanged() {
    #expect(
      SetCounting.source.methodology == """
        A completed working set credits 1.0 set to each muscle labelled direct on the movement, \
        0.5 to each labelled indirect, and 0 to each labelled stabilising. The 1.0/0.5 split \
        follows the fractional scheme that best fitted 67 training studies in Pelland et al. \
        (2025). Those authors fixed the 0.5 weight in advance rather than estimating it from the \
        data, and describe it as an assumption and a heuristic; Hardset adopts it as a stated \
        convention. The 0 weight for stabilising and gripping muscles is Hardset's own convention \
        and is not part of the scheme that was tested.
        """)
    #expect(
      SetCounting.source.citation == """
        Pelland JC, Remmert JF, Robinson ZP, Hinson SR, Zourdos MC. Sports Med 2025. \
        DOI 10.1007/s40279-025-02344-w, PMID 41343037.
        """)
    #expect(
      SetCounting.source.validRange == """
        The scheme was compared against studies measuring eight sites: quadriceps and knee \
        extensors, rectus femoris, hamstrings and posterior thigh, pectoralis major, anterior \
        deltoid, trapezius, triceps brachii and elbow extensors, biceps brachii and elbow flexors. \
        Applying it to any other muscle is an extrapolation. Few studies examined more than about \
        25 fractional weekly sets, so counts above that fall outside the fitted range. No isometric \
        or stabilising contribution appears anywhere in the classification.
        """)
  }

  @Test("The other methodologies are unchanged, character for character")
  func otherTextsUnchanged() {
    #expect(
      VolumeAnalyzer.doseResponseSource.methodology == """
        Weekly fractional sets per muscle are placed against the dose-response relationship fitted \
        across 67 training studies. The best-fit form showed diminishing returns rather than an \
        inverted-U, but the credible intervals widen with volume and few studies examined more than \
        about 25 fractional weekly sets, so above that the app reports the count and declines to \
        say what an additional set buys.
        """)
    #expect(
      VolumeAnalyzer.targetSource.methodology == """
        Hardset does not publish a weekly set target for any muscle, because no such target is \
        established. What the literature supports is a dose-response relationship for eight \
        measured sites and a general finding that higher volumes tended to produce more growth. \
        The app therefore shows what you did and where it is empty, and does not tell you what \
        number you should have hit.
        """)
    #expect(
      StrengthMath.measuredSource.methodology
        == "A completed single at this load is reported directly. No estimation is involved.")
    #expect(
      StrengthMath.epleySource.methodology
        == "Estimated from a completed set as weight x (1 + reps / 30). This is a plan-structure "
        + "heuristic for comparing loads over time, not a measurement of maximal strength. "
        + "Accuracy falls as repetitions rise, so certainty is reduced above 6 repetitions "
        + "and no estimate is produced above 12.")
    #expect(
      ProgressionAnalyzer.source.methodology == """
        Each point is your best work in one session on one specific machine: the heaviest load you \
        moved, and where the rep counts allow it, the best estimated one-rep max. Sessions on \
        different machines are drawn as separate lines and never merged, because the same number on \
        different equipment is not the same effort.
        """)
  }

  @Test("The DOI links to doi.org, without the comma that follows it")
  func doiStopsAtPunctuation() {
    #expect(
      SetCounting.source.doiURL?.absoluteString == "https://doi.org/10.1007/s40279-025-02344-w")
    // Here the DOI ends the sentence, so it is followed by a full stop.
    #expect(
      VolumeAnalyzer.targetSource.doiURL?.absoluteString
        == "https://doi.org/10.1007/s40279-025-02344-w")
    let wrapped = EvidenceSource(
      id: "t", title: "t", methodology: "t", citation: "Someone (doi:10.1234/ab.cd)."
    )
    #expect(wrapped.doiURL?.absoluteString == "https://doi.org/10.1234/ab.cd")
  }

  @Test("A citation without a DOI gets no link")
  func noDOINoLink() {
    #expect(StrengthMath.epleySource.doiURL == nil)
    #expect(ProgressionAnalyzer.source.doiURL == nil)
    let version = EvidenceSource(
      id: "t", title: "t", methodology: "t", citation: "Version 10.2 of the manual, p. 3/4.")
    #expect(version.doiURL == nil)
  }

  @Test("The credit picture reads its numbers from the counting itself")
  func creditScheme() {
    let posix = Locale(identifier: "en_US_POSIX")
    let tiers = SetCounting.creditScheme(locale: posix)
    #expect(tiers.map(\.role) == [.direct, .indirect, .stabilizer])
    #expect(tiers.map(\.credit) == MuscleRole.allCases.map(SetCounting.weight))
    #expect(tiers.map(\.creditText) == ["1", "0.5", "0"])
    #expect(SetCounting.creditScheme(locale: Locale(identifier: "de_DE"))[1].creditText == "0,5")
  }

  /// `DECISIONS.md` §17: the 0.5 is an adopted convention, not an inherited finding.
  @Test("The half credit is called a convention, and the zero is Hardset's own")
  func creditBasisIsHonest() {
    let tiers = SetCounting.creditScheme(locale: Locale(identifier: "en_US_POSIX"))
    #expect(tiers[1].basis.contains("convention"))
    #expect(tiers[1].basis.contains("in advance"))
    #expect(!tiers[1].basis.lowercased().contains("fitted"))
    #expect(tiers[2].basis.contains("Hardset's own convention"))
    for tier in tiers {
      #expect(!tier.meaning.isEmpty)
    }
  }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `Tools/linux-test.sh --filter EvidenceSummaryTests`
Expected: compile failure, `type 'EvidenceSource' has no member 'shipped'`.

- [ ] **Step 3: Implement**

In `Certainty.swift`, replace the end of `EvidenceSource` from `public let validRange: String?`
through its closing brace with:

```swift
  public let validRange: String?
  /// One plain sentence, shown first as "In short".
  ///
  /// A new field rather than a rewrite of `methodology`: the methodology is the text App Review
  /// reads and tests pin it, so it is never edited (spec §4). This only summarises it, and may not
  /// claim more than it does.
  public let summary: String?

  public init(
    id: String, title: String, methodology: String,
    citation: String? = nil, validRange: String? = nil, summary: String? = nil
  ) {
    self.id = id
    self.title = title
    self.methodology = methodology
    self.citation = citation
    self.validRange = validRange
    self.summary = summary
  }

  /// The citation's DOI as a link to doi.org, or nil when it has none.
  ///
  /// The DOI is the first word holding "10.<registrant>/<suffix>", with any punctuation that
  /// closes the sentence around it removed: "DOI 10.1007/s40279-025-02344-w, PMID …" links to
  /// the article, not to a DOI ending in a comma, which resolves to nothing.
  public var doiURL: URL? {
    guard let citation else { return nil }
    for word in citation.split(whereSeparator: \.isWhitespace) {
      guard let start = word.range(of: "10.") else { continue }
      var doi = word[start.lowerBound...]
      while let last = doi.last, ".,;:)]".contains(last) { doi = doi.dropLast() }
      let parts = doi.split(separator: "/", maxSplits: 1)
      guard parts.count == 2, parts[0].count > 3, parts[0].dropFirst(3).allSatisfy(\.isNumber),
        !parts[1].isEmpty
      else { continue }
      return URL(string: "https://doi.org/\(doi)")
    }
    return nil
  }
}

extension EvidenceSource {
  /// Every source the app shows. The methodology sheet's previews and the summary tests iterate
  /// this, so a source added without an "In short" line fails a test instead of shipping bare.
  public static var shipped: [EvidenceSource] {
    [
      SetCounting.source, VolumeAnalyzer.doseResponseSource, VolumeAnalyzer.targetSource,
      StrengthMath.measuredSource, StrengthMath.epleySource, ProgressionAnalyzer.source,
    ]
  }
}
```

In `MuscleTaxonomy.swift`, give `SetCounting.source` its summary. Replace the end of the
`validRange:` literal and the closing parenthesis:

```swift
      or stabilising contribution appears anywhere in the classification.
      """,
    summary: """
      A working set counts 1 for each muscle that drives it, 0.5 for each that assists and 0 for \
      bracing or gripping; the 0.5 is a stated convention, not a measured value.
      """
  )
```

Then, inside `enum SetCounting`, after `certaintyCeiling(for:fractionalSets:)` and before the
enum's closing brace, add `creditScheme`; and after the enum, add `CreditTier`:

```swift
  // Inside `enum SetCounting`, after `certaintyCeiling(for:fractionalSets:)`. The `}` below closes the enum.
  /// The 1.0 / 0.5 / 0 scheme as rows the methodology sheet can draw (spec 3.2).
  ///
  /// The credits are read from `weight(_:)`, never restated, so the picture cannot drift from the
  /// arithmetic. Each row says where its number comes from, and the 0.5 row says it is a
  /// convention: Pelland et al. fixed it in advance rather than estimating it (`DECISIONS.md` §17).
  public static func creditScheme(locale: Locale = .current) -> [CreditTier] {
    MuscleRole.allCases.map { role in
      let credit = weight(role)
      return CreditTier(
        role: role,
        credit: credit,
        creditText: WeightFormatter.text(credit, fractionDigits: 1, locale: locale),
        meaning: meaning(role),
        basis: basis(role)
      )
    }
  }

  private static func meaning(_ role: MuscleRole) -> String {
    switch role {
    case .direct: "Muscles that drive the movement"
    case .indirect: "Muscles that assist through a real range"
    case .stabilizer: "Muscles that only brace, grip or hold still"
    }
  }

  private static func basis(_ role: MuscleRole) -> String {
    switch role {
    case .direct: "From the scheme that best fitted 67 studies in Pelland et al. (2025)."
    case .indirect:
      "A convention. Pelland et al. fixed this weight in advance rather than estimating it."
    case .stabilizer: "Hardset's own convention. It is not part of the scheme that was tested."
    }
  }
}

/// One row of the fractional-credit picture.
public struct CreditTier: Hashable, Sendable, Identifiable {
  public let role: MuscleRole
  /// Sets credited per working set, from `SetCounting.weight(_:)`.
  public let credit: Double
  /// The credit in the lifter's locale: "1", "0.5", "0" (or "0,5").
  public let creditText: String
  public let meaning: String
  /// Where the number comes from, said honestly.
  public let basis: String

  public var id: MuscleRole { role }
}
```

In `MuscleVolume.swift`, add `summary:` as the last argument of the two sources:

```swift
    // doseResponseSource, after its validRange literal:
    summary: """
      For the eight muscles the studies measured, your weekly count is placed on a published \
      curve; past about 25 sets the app stops saying what another set buys.
      """

    // targetSource, after `validRange: "No muscle has an evaluated target in this version.",`
    summary: """
      No weekly set target is established for any muscle, so the app shows what you did and \
      never what you should have done.
      """
```

In `StrengthMath.swift`:

```swift
    // measuredSource, after `validRange: "Exactly 1 repetition.",`
    summary: "A single rep at a weight is reported as it is, with nothing estimated."

    // epleySource, after `validRange: "2-12 repetitions, sub-maximal to maximal effort.",`
    summary: """
      An estimate from a set of 2 to 12 reps, for comparing your own loads over time; it is not \
      a measured maximum.
      """
```

In `Progression.swift`, `ProgressionAnalyzer.source`, after its `validRange:` literal:

```swift
    summary: "Your best weight in each session, one line per machine, never merged across machines."
```

Each `validRange:` line that now precedes `summary:` gains a trailing comma. Do not touch any
`methodology:`, `validRange:` or `citation:` text.

- [ ] **Step 4: Run to verify pass**

Run: `Tools/linux-test.sh --filter 'EvidenceSummaryTests|MuscleTaxonomyTests|StrengthMathTests|ProgressionTests|MuscleVolumeTests'`,
then `Tools/linux-test.sh`.
Expected: PASS. If a "character for character" test fails, a pinned text was edited: revert that
edit, never the test.

- [ ] **Step 5: Commit**

```bash
git add Packages/HardsetKit/Sources/HardsetCore/Certainty.swift \
  Packages/HardsetKit/Sources/HardsetCore/MuscleTaxonomy.swift \
  Packages/HardsetKit/Sources/HardsetCore/MuscleVolume.swift \
  Packages/HardsetKit/Sources/HardsetCore/StrengthMath.swift \
  Packages/HardsetKit/Sources/HardsetCore/Progression.swift \
  Packages/HardsetKit/Tests/HardsetCoreTests/EvidenceSummaryTests.swift
git commit -m "feat(core): every source says it in short, and links its paper

The methodology sheet led with a paragraph written for App Review. Each source
gains a new one-sentence summary field instead of an edited methodology, which
spec §4 forbids, and a test now holds every pinned text to the character. The
fractional credits become rows the sheet can draw, read from the counting itself,
and the 0.5 row says it is a convention fixed in advance (DECISIONS §17). A DOI
becomes a doi.org link that stops before the comma that follows it.

Co-Authored-By: <your model's trailer>"
```

---

### Task 3: A certainty for every derived number (Core)

**Files:**
- Modify: `Packages/HardsetKit/Sources/HardsetCore/MuscleVolume.swift:92-99` (after
  `highestCertainty`) and before `enum VolumeAnalyzer` (line 120)
- Modify: `Packages/HardsetKit/Sources/HardsetCore/WorkoutSummary.swift:51` (inside `MuscleLine`)
- Modify: `Packages/HardsetKit/Sources/HardsetCore/Progression.swift:27-55` (`ProgressionPoint`)
  and `:154-171` (`ProgressionAnalyzer.point`)
- Modify: `Packages/HardsetKit/Sources/HardsetCore/PersonalRecords.swift:35`
- Test: `Packages/HardsetKit/Tests/HardsetCoreTests/DerivedCertaintyTests.swift`

**Interfaces:**
- Consumes: `SetCounting.certaintyCeiling(for:fractionalSets:)`,
  `StrengthMath.estimatedOneRepMax(weightKg:reps:)`, `WeightFormatter.text`.
- Produces, for Tasks 4, 13, 15 and 17:
  - `static func SetCounting.certainty(for key: MuscleKey, fractionalSets: Double) -> Certainty`
  - `MuscleVolumeReport.certainty(for muscle: Muscle) -> Certainty?` (nil when nothing credited)
  - `WorkoutSummary.MuscleLine.certainty: Certainty` and
    `MuscleLine.countText(locale: Locale = .current) -> String` ("≥ 2,5", no noun)
  - `ProgressionPoint.bestEstimateCertainty: Certainty?`, a new last init parameter defaulting to
    nil, forced to nil when there is no estimate
  - `PersonalRecord.estimateCertainty: Certainty?`

Rules (each a test below): certainty is per muscle, never the report's best case; a muscle with no
credit has none; the summary's muscle line agrees with the volume tab; an unrecognised token is
`.low`, never `.unevaluated`, because a figure is shown; a session's best estimate carries the
certainty of the set it came from, and an exact tie goes to the better-supported set; a measured
record carries no estimate certainty.

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing

@testable import HardsetCore

@Suite("Every derived number carries its own certainty")
struct DerivedCertaintyTests {
  private let day = Date(timeIntervalSince1970: 30_000_000)

  private func report(_ sets: [MuscleKey: Double], unattributed: Int = 0) -> MuscleVolumeReport {
    MuscleVolumeReport(
      fractionalSets: sets, hardSets: 10, unattributedHardSets: unattributed, setsTouchingGroup: [:])
  }

  @Test("Each muscle has its own certainty, not the report's best case")
  func perMuscle() {
    let weekly = report([MuscleKey(.chest): 12, MuscleKey(.forearms): 4, MuscleKey(.quadriceps): 30])
    // Chest is a modelled site: moderate at most.
    #expect(weekly.certainty(for: .chest) == .moderate)
    // Forearms are counted, not modelled: low.
    #expect(weekly.certainty(for: .forearms) == .low)
    // Past the studied range even a modelled site is low.
    #expect(weekly.certainty(for: .quadriceps) == .low)
    // The old single header would have said moderate for all three.
    #expect(weekly.highestCertainty == .moderate)
  }

  @Test("A muscle credited nothing has no figure, so no certainty")
  func nothingCredited() {
    #expect(report([MuscleKey(.chest): 3]).certainty(for: .lats) == nil)
  }

  @Test("A muscle line in the summary carries the same certainty as the volume tab")
  func summaryLineAgrees() {
    let weekly = report([MuscleKey(.chest): 12, MuscleKey(.forearms): 4])
    let lines = WorkoutSummary.muscleLines(from: weekly)
    let chest = lines.first { $0.muscle == MuscleKey(.chest) }
    let forearms = lines.first { $0.muscle == MuscleKey(.forearms) }
    #expect(chest?.certainty == weekly.certainty(for: .chest))
    #expect(forearms?.certainty == weekly.certainty(for: .forearms))
  }

  @Test("A token this version does not know is low, never unevaluated, because a figure is shown")
  func unrecognisedToken() {
    let line = WorkoutSummary.MuscleLine(
      muscle: MuscleKey(stored: "serratus"), fractionalSets: 2, isLowerBound: false)
    #expect(line.certainty == .low)
  }

  @Test("A count reads in the lifter's locale, with its lower bound")
  func countText() {
    let line = WorkoutSummary.MuscleLine(
      muscle: MuscleKey(.chest), fractionalSets: 2.5, isLowerBound: true)
    #expect(line.countText(locale: Locale(identifier: "en_US_POSIX")) == "≥ 2.5")
    #expect(line.countText(locale: Locale(identifier: "de_DE")) == "≥ 2,5")
    let whole = WorkoutSummary.MuscleLine(
      muscle: MuscleKey(.chest), fractionalSets: 12, isLowerBound: false)
    #expect(whole.countText(locale: Locale(identifier: "en_US_POSIX")) == "12")
  }

  private func sample(_ session: SessionID, _ weight: Double, _ reps: Int) -> ProgressionSample {
    ProgressionSample(
      sessionID: session, machineID: nil, weightKg: weight, reps: reps, completedAt: day)
  }

  @Test("A session's best estimate carries the certainty of the set it came from")
  func estimateCertainty() throws {
    let exercise = ExerciseID()
    let tens = SessionID()
    let fours = SessionID()
    let twenties = SessionID()
    let series = ProgressionAnalyzer.series(
      from: [
        sample(tens, 100, 10),
        sample(fours, 110, 4),
        sample(twenties, 60, 20),
      ], exerciseID: exercise)
    let points = try #require(series.first).points
    let byID = Dictionary(uniqueKeysWithValues: points.map { ($0.sessionID, $0) })
    #expect(byID[tens]?.bestEstimateCertainty == .moderate)
    #expect(byID[fours]?.bestEstimateCertainty == .high)
    // Nothing estimable, so neither an estimate nor a certainty.
    #expect(byID[twenties]?.bestEstimatedOneRepMaxKg == nil)
    #expect(byID[twenties]?.bestEstimateCertainty == nil)
  }

  @Test("When two sets estimate the same, the better-supported one speaks for the session")
  func tieGoesToTheBetterSupported() throws {
    // 90 × 10 and 100 × 6 both estimate exactly 120: the first at moderate (7...10 reps), the
    // second at high (2...6). The moderate one comes first, so a value-only maximum would keep it.
    let session = SessionID()
    let series = ProgressionAnalyzer.series(
      from: [sample(session, 90, 10), sample(session, 100, 6)], exerciseID: ExerciseID())
    let point = try #require(series.first?.points.first)
    #expect(point.bestEstimatedOneRepMaxKg == 120)
    #expect(point.bestEstimateCertainty == .high)
  }

  @Test("A point built with no estimate cannot carry a certainty")
  func noEstimateNoCertainty() {
    let point = ProgressionPoint(
      sessionID: SessionID(), machineID: nil, date: day, heaviestLoadKg: 100,
      bestEstimatedOneRepMaxKg: nil, workingSets: 3, bestEstimateCertainty: .high)
    #expect(point.bestEstimateCertainty == nil)
  }

  @Test("An estimated-1RM record carries its estimate's certainty; measured records carry none")
  func recordCertainty() {
    let estimate = PersonalRecord(kind: .estimatedOneRepMax, weightKg: 100, reps: 10)
    #expect(estimate.estimateCertainty == .moderate)
    let low = PersonalRecord(kind: .estimatedOneRepMax, weightKg: 100, reps: 12)
    #expect(low.estimateCertainty == .low)
    #expect(PersonalRecord(kind: .heaviestLoad, weightKg: 100, reps: 10).estimateCertainty == nil)
    #expect(PersonalRecord(kind: .repsAtLoad, weightKg: 100, reps: 10).estimateCertainty == nil)
  }
}
```

90 × 10 and 100 × 6 both estimate exactly 120.0 in IEEE doubles (checked), so the tie test does
exercise the tie-break and not a rounding accident.

- [ ] **Step 2: Run to verify failure**

Run: `Tools/linux-test.sh --filter DerivedCertaintyTests`
Expected: compile failure, `value of type 'MuscleVolumeReport' has no member 'certainty'`.

- [ ] **Step 3: Implement**

`MuscleVolume.swift`, after `highestCertainty` inside `MuscleVolumeReport`:

```swift
  /// How sure the app is of one muscle's figure, shown beside that figure (spec 3.1). Nil when the
  /// muscle was credited nothing, because there is then no figure to qualify.
  ///
  /// Per muscle, because one header for the whole report could only be the best case: 16 of the 22
  /// muscles cap at low.
  public func certainty(for muscle: Muscle) -> Certainty? {
    let sets = sets(for: muscle)
    guard sets > 0 else { return nil }
    return SetCounting.certainty(for: MuscleKey(muscle), fractionalSets: sets)
  }
```

and, immediately before `/// Counts fractional sets. Takes sets and attribution, and nothing else.`:

```swift
extension SetCounting {
  /// The certainty of a count credited to `key`.
  ///
  /// A token this version does not recognise has no tier, so it gets `.low`: the arithmetic is
  /// real, but what the muscle is, and so what the count means, is not known here. Never
  /// `.unevaluated`, because a figure is shown and `.unevaluated` means there is none.
  public static func certainty(for key: MuscleKey, fractionalSets: Double) -> Certainty {
    guard let muscle = key.muscle else { return .low }
    return certaintyCeiling(for: muscle, fractionalSets: fractionalSets)
  }
}
```

`WorkoutSummary.swift`, inside `MuscleLine`, immediately before `private func count(_ locale:)`:

```swift
    /// The number alone, for a row that draws its noun elsewhere: "12", "2.5", "≥ 2,5". Through the
    /// locale, so a German lifter reads "2,5"; the volume tab printed "%.1f" and always used ".".
    public func countText(locale: Locale = .current) -> String {
      "\(isLowerBound ? "≥ " : "")\(count(locale))"
    }

    /// How sure the app is of this figure (spec 3.1).
    public var certainty: Certainty {
      SetCounting.certainty(for: muscle, fractionalSets: fractionalSets)
    }
```

`Progression.swift`, `ProgressionPoint`: add the stored property after `workingSets`, the init
parameter last, and the assignment:

```swift
  public let workingSets: Int
  /// The certainty of `bestEstimatedOneRepMaxKg`, nil exactly when there is no estimate. A best
  /// estimate from a set of ten is moderate, from a set of four high (`StrengthMath`).
  public let bestEstimateCertainty: Certainty?

  public var id: SessionID { sessionID }

  public init(
    sessionID: SessionID,
    machineID: MachineID?,
    date: Date,
    heaviestLoadKg: Double,
    bestEstimatedOneRepMaxKg: Double?,
    workingSets: Int,
    bestEstimateCertainty: Certainty? = nil
  ) {
    self.sessionID = sessionID
    self.machineID = machineID
    self.date = date
    self.heaviestLoadKg = heaviestLoadKg
    self.bestEstimatedOneRepMaxKg = bestEstimatedOneRepMaxKg
    self.workingSets = workingSets
    self.bestEstimateCertainty = bestEstimatedOneRepMaxKg == nil ? nil : bestEstimateCertainty
  }
```

and in `ProgressionAnalyzer.point(sessionID:machineID:samples:)` replace from `let estimates =`
through the `return ProgressionPoint(…)` call with:

```swift
    let estimates = samples
      .map { StrengthMath.estimatedOneRepMax(weightKg: $0.weightKg, reps: $0.reps) }
      .filter(\.isEvaluated)
    // The best estimate, and when two sets estimate the same, the better-supported of them.
    let best = estimates.max { lhs, rhs in
      (lhs.value ?? 0, lhs.certainty) < (rhs.value ?? 0, rhs.certainty)
    }
    return ProgressionPoint(
      sessionID: sessionID,
      machineID: machineID,
      date: samples.map(\.completedAt).min() ?? .distantPast,
      heaviestLoadKg: heaviest,
      bestEstimatedOneRepMaxKg: best?.value,
      workingSets: samples.count,
      bestEstimateCertainty: best?.certainty
    )
```

Keep the comment above `let estimates` ("Only estimable sets contribute…").

`PersonalRecords.swift`, after `public var id: PersonalRecordKind { kind }`:

```swift
  /// The certainty of the estimate behind an estimated-1RM record, derived the one way the
  /// detector derived it. Nil for the other kinds, which are measured, not estimated.
  public var estimateCertainty: Certainty? {
    guard kind == .estimatedOneRepMax else { return nil }
    let claim = StrengthMath.estimatedOneRepMax(weightKg: weightKg, reps: reps)
    return claim.isEvaluated ? claim.certainty : nil
  }
```

- [ ] **Step 4: Run to verify pass**

Run: `Tools/linux-test.sh --filter 'DerivedCertaintyTests|ProgressionTests|WorkoutSummaryTests|MuscleVolumeTests'`,
then `Tools/linux-test.sh`.
Expected: PASS. Existing `ProgressionPoint(…)` calls (tests, the chart preview) compile unchanged
because the new parameter is last and defaulted.

- [ ] **Step 5: Commit**

```bash
git add Packages/HardsetKit/Sources/HardsetCore/MuscleVolume.swift \
  Packages/HardsetKit/Sources/HardsetCore/WorkoutSummary.swift \
  Packages/HardsetKit/Sources/HardsetCore/Progression.swift \
  Packages/HardsetKit/Sources/HardsetCore/PersonalRecords.swift \
  Packages/HardsetKit/Tests/HardsetCoreTests/DerivedCertaintyTests.swift
git commit -m "feat(core): every derived number carries its own certainty

The volume screen had one certainty for the whole report, which could only be
the best case and overstated 16 of 22 muscles. Each muscle's count, each summary
line, each session's best estimate and each estimated-1RM record now carries the
certainty of what produced it, so a badge can sit beside the number it
qualifies. An unrecognised token is low, not unevaluated, because a figure is
shown. Counts also gain a locale-aware text, replacing a %.1f that always
printed a full stop.

Co-Authored-By: <your model's trailer>"
```

---

### Task 4: The chart's words, and a label per machine (Core, Store)

**Files:**
- Create: `Packages/HardsetKit/Sources/HardsetCore/ProgressionChartModel.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetStore/VolumeStore.swift:98-109` (`machineNames`)
  and `:143` (after `ProgressionHistory.isEmpty`)
- Modify, mechanically: `Packages/HardsetKit/Sources/HardsetUI/ProgressionChartView.swift:5-16`
  (delete the UI's `ProgressionMetric`) and `:37-46` (`SeriesInput` becomes a typealias)
- Modify: `docs/MAC-VERIFICATION.md`
- Test: `Packages/HardsetKit/Tests/HardsetCoreTests/ProgressionChartModelTests.swift`
- Test: `Packages/HardsetKit/Tests/HardsetStoreTests/ProgressionChartSeriesTests.swift`

**Interfaces:**
- Consumes: `ProgressionPoint.bestEstimateCertainty` (Task 3), `WeightFormatter`,
  `StrengthMath.displayRounded(_:in:)`, `MachineRecord.displayName`.
- Produces, for Task 14 and Task 17:
  - `public enum ProgressionMetric` (moved from HardsetUI, same cases and `label`), plus
    `spokenLabel`, `isEstimate`, `kilograms(of:) -> Double?`, `displayValue(of:unit:) -> Double?`
  - `public struct ProgressionChartSeries: Identifiable, Hashable, Sendable` with `label`, `points`,
    `init(label:points:)`, `id: String` (the label)
  - `public struct ProgressionHeadline` with `text`, `spoken`, `certainty: Certainty?`,
    `static func current(in:metric:formatter:) -> ProgressionHeadline?` and
    `static func make(for:metric:formatter:) -> ProgressionHeadline?`
  - `public struct ProgressionSelection` with `seriesLabel`, `point`, `text`, `spoken`, and
    `static func nearest(to: Date, in: [ProgressionChartSeries], metric:formatter:) -> ProgressionSelection?`
  - `public struct ProgressionChartDescription` with `title`, `summary`, `valueAxisTitle`,
    `valueRange`, `dateRange`, `series: [Series]` (each `name`, `points: [Point]` of `date`,
    `value`, `spokenValue`), `func spokenValue(_ displayValue: Double) -> String`, and
    `static func make(exerciseName:series:metric:formatter:) -> ProgressionChartDescription?`
  - `ProgressionHistory.chartSeries() -> [ProgressionChartSeries]`: most recent first, labels unique
  - `ProgressionStore.machineNames(_:)` now returns `MachineRecord.displayName` (brand first)
  - In HardsetUI: `ProgressionChartView.SeriesInput` is `typealias SeriesInput = ProgressionChartSeries`

**Why the Store change belongs here.** `ProgressionChartView` keys each line by
`.value("Machine", input.label)`. `machineNames` returned the bare `name`, so "Hammer Strength Leg
Press" and "Cybex Leg Press" were both "Leg Press", and two unbranded machines always collided: the
chart drew one line through two machines. Brand-first names fix the common case; numbering fixes
the rest.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing

@testable import HardsetCore

@Suite("The chart says what changed on one machine, and VoiceOver hears the same chart")
struct ProgressionChartModelTests {
  private let day = Date(timeIntervalSince1970: 40_000_000)
  private let kilograms = WeightFormatter(unit: .kilograms, locale: Locale(identifier: "en_US_POSIX"))
  private let pounds = WeightFormatter(unit: .pounds, locale: Locale(identifier: "en_US_POSIX"))

  private func point(
    _ week: Int, _ load: Double, estimate: Double? = nil, certainty: Certainty? = nil
  ) -> ProgressionPoint {
    ProgressionPoint(
      sessionID: SessionID(), machineID: nil, date: day.addingTimeInterval(Double(week) * 604_800),
      heaviestLoadKg: load, bestEstimatedOneRepMaxKg: estimate, workingSets: 3,
      bestEstimateCertainty: certainty)
  }

  private func series(_ label: String, _ points: [ProgressionPoint]) -> ProgressionChartSeries {
    ProgressionChartSeries(label: label, points: points)
  }

  @Test("A rise in load reads as the spec's example")
  func rise() throws {
    let hammer = series("Hammer leg press", [point(0, 100), point(1, 102.5), point(2, 105)])
    let headline = try #require(ProgressionHeadline.make(for: hammer, metric: .heaviestLoad, formatter: kilograms))
    #expect(headline.text == "Hammer leg press: +5 kg over 3 sessions")
    #expect(headline.spoken == "Hammer leg press: up 5 kilograms over 3 sessions")
    // A load is measured, so it carries no certainty badge.
    #expect(headline.certainty == nil)
  }

  @Test("A fall is stated with a minus sign and spoken as down")
  func fall() throws {
    let hammer = series("Hammer leg press", [point(0, 105), point(1, 102.5)])
    let headline = try #require(ProgressionHeadline.make(for: hammer, metric: .heaviestLoad, formatter: kilograms))
    #expect(headline.text == "Hammer leg press: \u{2212}2.5 kg over 2 sessions")
    #expect(headline.spoken == "Hammer leg press: down 2.5 kilograms over 2 sessions")
  }

  @Test("No change, and a single session, say so plainly")
  func flatAndSingle() throws {
    let flat = series("Cybex", [point(0, 80), point(1, 80)])
    #expect(ProgressionHeadline.make(for: flat, metric: .heaviestLoad, formatter: kilograms)?.text
      == "Cybex: no change over 2 sessions")
    let single = series("Cybex", [point(0, 80)])
    let headline = try #require(ProgressionHeadline.make(for: single, metric: .heaviestLoad, formatter: kilograms))
    #expect(headline.text == "Cybex: 80 kg, 1 session")
    #expect(headline.spoken == "Cybex: 80 kilograms, 1 session")
  }

  @Test("An estimate is said with about, and carries its weaker end's certainty")
  func estimate() throws {
    let hammer = series(
      "Hammer leg press",
      [
        point(0, 100, estimate: 120, certainty: .high),
        point(1, 100, estimate: nil),
        point(2, 105, estimate: 126, certainty: .moderate),
      ])
    let headline = try #require(
      ProgressionHeadline.make(for: hammer, metric: .estimatedOneRepMax, formatter: kilograms))
    // The session with no estimate is not plotted, so it is not counted.
    #expect(headline.text == "Hammer leg press: about +6 kg over 2 sessions")
    #expect(headline.spoken == "Hammer leg press: up about 6 kilograms over 2 sessions")
    #expect(headline.certainty == .moderate)
  }

  /// Review Focus: the delta must be the difference of the numbers on screen, in the lifter's unit.
  @Test("In pounds the change is the difference of the two displayed loads")
  func deltaMatchesDisplayedNumbers() throws {
    let hammer = series("Hammer leg press", [point(0, 100), point(1, 102.5)])
    // 100 kg reads 220.46 lb and 102.5 kg reads 225.97 lb.
    #expect(pounds.number(kilograms: 100) == "220.46")
    #expect(pounds.number(kilograms: 102.5) == "225.97")
    let headline = try #require(ProgressionHeadline.make(for: hammer, metric: .heaviestLoad, formatter: pounds))
    #expect(headline.text == "Hammer leg press: +5.51 lb over 2 sessions")
  }

  @Test("A comma-decimal locale gets a comma")
  func germanDecimal() throws {
    let german = WeightFormatter(unit: .kilograms, locale: Locale(identifier: "de_DE"))
    let hammer = series("Hammer", [point(0, 100), point(1, 102.5)])
    #expect(ProgressionHeadline.make(for: hammer, metric: .heaviestLoad, formatter: german)?.text
      == "Hammer: +2,5 kg over 2 sessions")
  }

  /// Review Focus: a machine switch is not progress. 110 kg on the Hammer, then 90 kg on the Cybex,
  /// is not "−20 kg".
  @Test("The headline describes the machine used last and never spans two machines")
  func headlineNeverSpansMachines() throws {
    let hammer = series("Hammer", [point(0, 100), point(1, 110)])
    let cybex = series("Cybex", [point(2, 85), point(3, 90)])
    let headline = try #require(
      ProgressionHeadline.current(in: [hammer, cybex], metric: .heaviestLoad, formatter: kilograms))
    #expect(headline.text == "Cybex: +5 kg over 2 sessions")
    // Order of the input does not matter; recency does.
    #expect(
      ProgressionHeadline.current(in: [cybex, hammer], metric: .heaviestLoad, formatter: kilograms)
        == headline)
  }

  @Test("For estimates, the latest machine that has any estimate speaks")
  func estimateHeadlineSkipsUnestimableSeries() throws {
    let hammer = series("Hammer", [point(0, 100, estimate: 120, certainty: .high), point(1, 100, estimate: 123, certainty: .high)])
    let highReps = series("Cybex", [point(2, 60), point(3, 60)])
    let headline = try #require(
      ProgressionHeadline.current(in: [hammer, highReps], metric: .estimatedOneRepMax, formatter: kilograms))
    #expect(headline.text == "Hammer: about +3 kg over 2 sessions")
    #expect(ProgressionHeadline.current(in: [highReps], metric: .estimatedOneRepMax, formatter: kilograms) == nil)
  }

  @Test("Scrubbing picks the nearest logged session and names its own machine")
  func scrub() throws {
    let hammer = series("Hammer", [point(0, 100), point(1, 110)])
    let cybex = series("Cybex", [point(3, 90)])
    // Two and a half weeks in: nearer the Cybex session (week 3) than the Hammer one (week 1).
    let selection = try #require(
      ProgressionSelection.nearest(
        to: day.addingTimeInterval(2.6 * 604_800), in: [hammer, cybex], metric: .heaviestLoad,
        formatter: kilograms))
    #expect(selection.seriesLabel == "Cybex")
    #expect(selection.text == "Cybex: 90 kg")
    #expect(selection.spoken == "Cybex: 90 kilograms")
    #expect(ProgressionSelection.nearest(to: day, in: [], metric: .heaviestLoad, formatter: kilograms) == nil)
  }

  @Test("VoiceOver's description keeps one series per machine, as drawn")
  func descriptionKeepsSeriesApart() throws {
    let hammer = series("Hammer", [point(0, 100), point(1, 110)])
    let cybex = series("Cybex", [point(2, 85), point(3, 90)])
    let description = try #require(
      ProgressionChartDescription.make(
        exerciseName: "Leg Press", series: [cybex, hammer], metric: .heaviestLoad,
        formatter: kilograms))
    #expect(description.series.map(\.name) == ["Cybex", "Hammer"])
    #expect(description.series.map(\.points.count) == [2, 2])
    #expect(description.series[1].points.map(\.value) == [100, 110])
    #expect(description.series[1].points[0].spokenValue == "100 kilograms")
    #expect(description.valueRange == 85...110)
    #expect(description.dateRange.lowerBound == day)
    #expect(description.title == "Leg Press, heaviest load")
    #expect(description.valueAxisTitle == "Heaviest load in kilograms")
    #expect(description.summary == "Cybex: up 5 kilograms over 2 sessions")
  }

  @Test("A series with nothing to plot is left out, and one value still gives the axis a width")
  func descriptionEdges() throws {
    let estimated = series("Hammer", [point(0, 100, estimate: 116, certainty: .high)])
    let highReps = series("Cybex", [point(1, 60)])
    let description = try #require(
      ProgressionChartDescription.make(
        exerciseName: "Leg Press", series: [estimated, highReps], metric: .estimatedOneRepMax,
        formatter: kilograms))
    #expect(description.series.map(\.name) == ["Hammer"])
    #expect(description.valueRange == 115...117)
    #expect(description.spokenValue(116) == "about 116 kilograms")
    #expect(description.valueAxisTitle == "Estimated one-rep max in kilograms")
    #expect(
      ProgressionChartDescription.make(
        exerciseName: "Leg Press", series: [highReps], metric: .estimatedOneRepMax,
        formatter: kilograms) == nil)
  }

  @Test("Loads draw solid and estimates dashed")
  func estimateIsMarked() {
    #expect(!ProgressionMetric.heaviestLoad.isEstimate)
    #expect(ProgressionMetric.estimatedOneRepMax.isEstimate)
    #expect(ProgressionMetric.estimatedOneRepMax.label == "Est. 1RM")
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

@Suite("Every machine keeps its own line, even when two share a name")
struct ProgressionChartSeriesTests {
  let now = Date(timeIntervalSince1970: 41_000_000)

  private func fixture() throws -> (any DatabaseWriter, LoggerStore, ExerciseID, GymID) {
    var configuration = Configuration.forTesting()
    configuration.foreignKeysEnabled = true
    let database = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(database)
    let exercise = ExerciseID()
    let gym = GymID()
    try database.write { db in
      try Exercise.insert { Exercise.Draft(id: exercise.rawValue, name: "Leg Press") }.execute(db)
      try Gym.insert { Gym.Draft(id: gym.rawValue, name: "Gym") }.execute(db)
    }
    return (database, LoggerStore(database: database), exercise, gym)
  }

  private func machine(
    _ database: any DatabaseWriter, _ gym: GymID, id: String, name: String, brand: String = ""
  ) throws -> MachineID {
    let machine = MachineID(rawValue: UUID(uuidString: id)!)
    try database.write { db in
      try Machine.insert {
        Machine.Draft(id: machine.rawValue, gymID: gym.rawValue, name: name, brand: brand)
      }
      .execute(db)
    }
    return machine
  }

  private func session(
    _ logger: LoggerStore, _ exercise: ExerciseID, _ machine: MachineID, _ weight: Double,
    daysAgo: Double
  ) throws {
    let start = now.addingTimeInterval(-daysAgo * 86_400)
    let id = try logger.startSession(at: start)
    _ = try logger.logSet(
      sessionID: id, exerciseID: exercise, machineID: machine,
      draft: SetEntryDraft(weightKg: weight, reps: 8), at: start.addingTimeInterval(60))
    try logger.finishSession(id, at: start.addingTimeInterval(1_800))
  }

  /// Review Focus: two unbranded "Leg Press" stacks were one label, and the chart keys a line by
  /// its label, so it drew one line through two machines.
  @Test("Two machines that share a name get two labels, numbered in a fixed order")
  func sameNamedMachinesStayApart() throws {
    let (database, logger, exercise, gym) = try fixture()
    let first = try machine(database, gym, id: "00000000-0000-0000-0000-00000000000A", name: "Leg Press")
    let second = try machine(database, gym, id: "00000000-0000-0000-0000-00000000000B", name: "Leg Press")
    try session(logger, exercise, second, 120, daysAgo: 1)
    try session(logger, exercise, first, 100, daysAgo: 7)

    let lines = try ProgressionStore(database: database).history(for: exercise).chartSeries()
    #expect(lines.count == 2)
    #expect(Set(lines.map(\.label)).count == 2)
    // Most recent first, and numbered by machine id rather than by recency, so a label is stable.
    #expect(lines.map(\.label) == ["Leg Press (2)", "Leg Press"])
    #expect(lines[0].points.map(\.heaviestLoadKg) == [120])
  }

  @Test("A series is labelled brand first, as the machine is everywhere else")
  func brandLeads() throws {
    let (database, logger, exercise, gym) = try fixture()
    let hammer = try machine(
      database, gym, id: "00000000-0000-0000-0000-00000000000C", name: "Leg Press",
      brand: "Hammer Strength")
    let cybex = try machine(
      database, gym, id: "00000000-0000-0000-0000-00000000000D", name: "Leg Press", brand: "Cybex")
    try session(logger, exercise, hammer, 100, daysAgo: 7)
    try session(logger, exercise, cybex, 90, daysAgo: 1)

    let lines = try ProgressionStore(database: database).history(for: exercise).chartSeries()
    #expect(lines.map(\.label) == ["Cybex Leg Press", "Hammer Strength Leg Press"])
  }

  @Test("The machine used most recently leads, even when another was used more")
  func mostRecentFirst() throws {
    let (database, logger, exercise, gym) = try fixture()
    let hammer = try machine(database, gym, id: "00000000-0000-0000-0000-00000000000E", name: "Hammer")
    let cybex = try machine(database, gym, id: "00000000-0000-0000-0000-00000000000F", name: "Cybex")
    try session(logger, exercise, hammer, 100, daysAgo: 21)
    try session(logger, exercise, hammer, 105, daysAgo: 14)
    try session(logger, exercise, cybex, 80, daysAgo: 1)

    let history = try ProgressionStore(database: database).history(for: exercise)
    // The analyser orders by sessions logged; the chart orders by recency.
    #expect(history.label(for: history.series[0].key) == "Hammer")
    #expect(history.chartSeries().map(\.label) == ["Cybex", "Hammer"])
  }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `Tools/linux-test.sh --filter 'ProgressionChartModelTests|ProgressionChartSeriesTests'`
Expected: compile failure, `cannot find 'ProgressionChartSeries' in scope`.

- [ ] **Step 3: Implement**

Create `ProgressionChartModel.swift`:

```swift
import Foundation

/// What a load-history chart plots. Load is always available; the estimate is not.
///
/// In Core rather than in the chart view, because the headline, the scrub readout and the
/// VoiceOver description all depend on it and are tested here.
public enum ProgressionMetric: String, Sendable, CaseIterable, Hashable {
  case heaviestLoad
  case estimatedOneRepMax

  public var label: String {
    switch self {
    case .heaviestLoad: "Heaviest load"
    case .estimatedOneRepMax: "Est. 1RM"
    }
  }

  /// The label read aloud, without the abbreviation.
  public var spokenLabel: String {
    switch self {
    case .heaviestLoad: "Heaviest load"
    case .estimatedOneRepMax: "Estimated one-rep max"
    }
  }

  /// An estimate is drawn dashed and said with "about", so it never passes for a lift.
  public var isEstimate: Bool { self == .estimatedOneRepMax }

  /// The point's value for this metric, in kilograms, or nil when it has none.
  public func kilograms(of point: ProgressionPoint) -> Double? {
    switch self {
    case .heaviestLoad: point.heaviestLoadKg
    case .estimatedOneRepMax: point.bestEstimatedOneRepMaxKg
    }
  }

  /// The value as the lifter reads it: in their unit, a load to two decimals and an estimate to
  /// display precision (0.5 kg, 1 lb). Arithmetic on these agrees with the numbers on screen.
  public func displayValue(of point: ProgressionPoint, unit: WeightUnit) -> Double? {
    guard let kilograms = kilograms(of: point) else { return nil }
    if isEstimate { return StrengthMath.displayRounded(kilograms, in: unit) }
    return (unit.fromKilograms(kilograms) * 100).rounded() / 100
  }
}

/// One machine's line, with the label the chart and VoiceOver use for it.
public struct ProgressionChartSeries: Identifiable, Hashable, Sendable {
  public let label: String
  /// Oldest first.
  public let points: [ProgressionPoint]

  /// The chart keys a line by this, so two series must never share a label.
  /// `ProgressionHistory.chartSeries()` guarantees it.
  public var id: String { label }

  public init(label: String, points: [ProgressionPoint]) {
    self.label = label
    self.points = points
  }

  /// The points this metric can plot, with their display values, oldest first.
  func plotted(_ metric: ProgressionMetric, unit: WeightUnit) -> [(point: ProgressionPoint, value: Double)] {
    points.compactMap { point in metric.displayValue(of: point, unit: unit).map { (point, $0) } }
  }
}

/// The sentence over the chart: "Hammer leg press: +5 kg over 6 sessions" (spec 3.3).
///
/// It always describes one machine. A delta taken across a switch would report the difference
/// between two machines as progress or decline, which is exactly what a chart that never merges
/// series exists to refuse (`DECISIONS.md` §20).
public struct ProgressionHeadline: Hashable, Sendable {
  public let text: String
  /// The same sentence for VoiceOver, with units in full.
  public let spoken: String
  /// For an estimate, the weaker of its two ends. Nil for loads, which are measured.
  public let certainty: Certainty?

  /// The headline for the machine used most recently, which is the one the lifter means.
  public static func current(
    in series: [ProgressionChartSeries], metric: ProgressionMetric, formatter: WeightFormatter
  ) -> ProgressionHeadline? {
    let candidates = series.compactMap { line -> (ProgressionChartSeries, Date)? in
      guard let last = line.plotted(metric, unit: formatter.unit).last else { return nil }
      return (line, last.point.date)
    }
    guard let latest = candidates.max(by: { $0.1 < $1.1 }) else { return nil }
    return make(for: latest.0, metric: metric, formatter: formatter)
  }

  /// The headline for one series, from its first plotted session to its last.
  public static func make(
    for series: ProgressionChartSeries, metric: ProgressionMetric, formatter: WeightFormatter
  ) -> ProgressionHeadline? {
    let plotted = series.plotted(metric, unit: formatter.unit)
    guard let first = plotted.first, let last = plotted.last else { return nil }
    let label = series.label
    let sessions = plotted.count == 1 ? "1 session" : "\(plotted.count) sessions"
    let about = metric.isEstimate ? "about " : ""
    let ends = [first.point.bestEstimateCertainty, last.point.bestEstimateCertainty].compactMap { $0 }
    let certainty = metric.isEstimate && !ends.isEmpty ? Certainty.combine(ends) : nil
    let digits = metric.isEstimate ? 1 : 2

    guard plotted.count > 1 else {
      let value = WeightFormatter.text(last.value, fractionDigits: digits, locale: formatter.locale)
      return ProgressionHeadline(
        text: "\(label): \(about)\(value) \(formatter.unit.abbreviation), \(sessions)",
        spoken: "\(label): \(about)\(spoken(last.value, formatter)), \(sessions)",
        certainty: certainty
      )
    }

    let delta = ((last.value - first.value) * 100).rounded() / 100
    guard delta != 0 else {
      let text = "\(label): no change over \(sessions)"
      return ProgressionHeadline(text: text, spoken: text, certainty: certainty)
    }
    let sign = delta > 0 ? "+" : "\u{2212}"
    let magnitude = WeightFormatter.text(abs(delta), fractionDigits: 2, locale: formatter.locale)
    return ProgressionHeadline(
      text: "\(label): \(about)\(sign)\(magnitude) \(formatter.unit.abbreviation) over \(sessions)",
      spoken:
        "\(label): \(delta > 0 ? "up" : "down") \(about)\(spoken(abs(delta), formatter)) over \(sessions)",
      certainty: certainty
    )
  }

  /// A display-unit value read aloud: "5 kilograms".
  static func spoken(_ displayValue: Double, _ formatter: WeightFormatter) -> String {
    formatter.spoken(kilograms: formatter.unit.toKilograms(displayValue))
  }
}

/// What scrubbing the chart shows: the logged point nearest the finger, with its own machine.
///
/// Never an interpolated or combined value. The readout names one session on one machine.
public struct ProgressionSelection: Hashable, Sendable {
  public let seriesLabel: String
  public let point: ProgressionPoint
  /// "Hammer leg press: 102.5 kg".
  public let text: String
  public let spoken: String

  public static func nearest(
    to date: Date, in series: [ProgressionChartSeries], metric: ProgressionMetric,
    formatter: WeightFormatter
  ) -> ProgressionSelection? {
    var best: (label: String, point: ProgressionPoint, value: Double, distance: TimeInterval)?
    for line in series {
      for (point, value) in line.plotted(metric, unit: formatter.unit) {
        let distance = abs(point.date.timeIntervalSince(date))
        if best == nil || distance < best!.distance {
          best = (line.label, point, value, distance)
        }
      }
    }
    guard let best else { return nil }
    let about = metric.isEstimate ? "about " : ""
    let digits = metric.isEstimate ? 1 : 2
    let number = WeightFormatter.text(best.value, fractionDigits: digits, locale: formatter.locale)
    return ProgressionSelection(
      seriesLabel: best.label,
      point: best.point,
      text: "\(best.label): \(about)\(number) \(formatter.unit.abbreviation)",
      spoken: "\(best.label): \(about)\(ProgressionHeadline.spoken(best.value, formatter))"
    )
  }
}

/// The chart, described for VoiceOver's audio graph (`AXChartDescriptor`, spec 3.3).
///
/// The UI turns this into Accessibility types and adds nothing. One series per machine, as drawn.
public struct ProgressionChartDescription: Hashable, Sendable {
  public struct Point: Hashable, Sendable {
    public let date: Date
    /// In the lifter's unit, as plotted.
    public let value: Double
    public let spokenValue: String
  }

  public struct Series: Hashable, Sendable {
    public let name: String
    public let points: [Point]
  }

  /// "Leg Press, heaviest load".
  public let title: String
  /// The spoken headline, when there is one.
  public let summary: String?
  /// "Heaviest load in kilograms".
  public let valueAxisTitle: String
  public let valueRange: ClosedRange<Double>
  public let dateRange: ClosedRange<Date>
  public let series: [Series]
  private let formatter: WeightFormatter
  private let isEstimate: Bool

  /// A plotted value read aloud, for the value axis: "about 116 kilograms".
  public func spokenValue(_ displayValue: Double) -> String {
    (isEstimate ? "about " : "") + ProgressionHeadline.spoken(displayValue, formatter)
  }

  public static func make(
    exerciseName: String, series: [ProgressionChartSeries], metric: ProgressionMetric,
    formatter: WeightFormatter
  ) -> ProgressionChartDescription? {
    let about = metric.isEstimate ? "about " : ""
    let described = series.compactMap { line -> Series? in
      let points = line.plotted(metric, unit: formatter.unit).map { point, value in
        Point(
          date: point.date, value: value,
          spokenValue: about + ProgressionHeadline.spoken(value, formatter))
      }
      return points.isEmpty ? nil : Series(name: line.label, points: points)
    }
    let values = described.flatMap(\.points).map(\.value)
    let dates = described.flatMap(\.points).map(\.date)
    guard let low = values.min(), let high = values.max(), let first = dates.min(),
      let last = dates.max()
    else { return nil }
    let unitName =
      switch formatter.unit {
      case .kilograms: "kilograms"
      case .pounds: "pounds"
      }
    return ProgressionChartDescription(
      title: "\(exerciseName), \(metric.spokenLabel.lowercased())",
      summary: ProgressionHeadline.current(in: series, metric: metric, formatter: formatter)?.spoken,
      valueAxisTitle: "\(metric.spokenLabel) in \(unitName)",
      // A single value would give the axis no width, so it is widened by one unit each way.
      valueRange: low < high ? low...high : (low - 1)...(high + 1),
      dateRange: first...last,
      series: described,
      formatter: formatter,
      isEstimate: metric.isEstimate
    )
  }
}
```

In `VolumeStore.swift`, `ProgressionStore.machineNames(_:)`: extend the doc comment and use the
display name:

```swift
  /// Machine names, for labelling the series. A machine the user deleted resolves to `nil` and the
  /// series is labelled generically rather than dropped — the sets were still performed.
  ///
  /// The display name, brand first, as everywhere else: "Hammer Strength Leg Press" and "Cybex Leg
  /// Press" were both labelled "Leg Press", and the chart drew them as one line.
  public func machineNames(_ ids: [MachineID]) throws -> [MachineID: String] {
    guard !ids.isEmpty else { return [:] }
    let raws = ids.map(\.rawValue)
    return try database.read { db in
      try Machine
        .where { $0.id.in(raws) }
        .fetchAll(db)
        .reduce(into: [MachineID: String]()) {
          $0[MachineID(rawValue: $1.id)] = MachineRecord(row: $1).displayName
        }
    }
  }
```

and in `ProgressionHistory`, replace `public var isEmpty: Bool { series.isEmpty }` and the closing
brace with:

```swift
  public var isEmpty: Bool { series.isEmpty }

  /// The series as the chart draws them: most recently used first, so the machine the lifter is on
  /// now leads the legend and the headline, and each with a label no other series shares.
  ///
  /// Two machines can share a name: two unbranded "Leg Press" stacks, or the same model at two
  /// gyms. The chart keys a line by its label, so equal labels would draw one line through two
  /// machines, the one thing it must never do (`DECISIONS.md` §20). Duplicates are numbered in a
  /// fixed order, by machine id, so a label does not change as the lifter's habits do.
  public func chartSeries() -> [ProgressionChartSeries] {
    var used = Set<String>()
    var labels: [ProgressionKey: String] = [:]
    let groups = Dictionary(grouping: series.map(\.key), by: label(for:))
    for name in groups.keys.sorted() {
      let keys = (groups[name] ?? []).sorted {
        ($0.machineID?.rawValue.uuidString ?? "") < ($1.machineID?.rawValue.uuidString ?? "")
      }
      for (index, key) in keys.enumerated() {
        var candidate = index == 0 ? name : "\(name) (\(index + 1))"
        var next = index + 2
        while used.contains(candidate) {
          candidate = "\(name) (\(next))"
          next += 1
        }
        used.insert(candidate)
        labels[key] = candidate
      }
    }
    return series
      .map { ProgressionChartSeries(label: labels[$0.key] ?? label(for: $0.key), points: $0.points) }
      .sorted { lhs, rhs in
        let l = lhs.points.last?.date ?? .distantPast
        let r = rhs.points.last?.date ?? .distantPast
        return l != r ? l > r : lhs.label < rhs.label
      }
  }
}
```

The existing `ProgressionStoreTests` create machines with a name and no brand, so their labels
("Hammer Strength", "Cybex") are unchanged.

In `ProgressionChartView.swift` (mechanical, Mac-only, so it gets a ledger line):
- Delete lines 5–16, the `public enum ProgressionMetric … { … }` declaration. The Core enum has
  the same cases and `label`, and the file already imports HardsetCore.
- Replace the nested `public struct SeriesInput: Identifiable, Hashable, Sendable { … }` (lines
  37–46) with `public typealias SeriesInput = ProgressionChartSeries`. `ExerciseProgressScreen`'s
  `ProgressionChartView.SeriesInput(label:points:)` and the preview's `.init(label:points:)` compile
  unchanged against `ProgressionChartSeries.init(label:points:)`.

Check: `rg -n 'enum ProgressionMetric' Packages/HardsetKit/Sources` returns only
`HardsetCore/ProgressionChartModel.swift`.

Ledger, under `## Phase 3`:

```markdown
- [ ] (feat(core): the chart says what changed on one machine …) HardsetUI and HardsetFeature build
      (iOS, and macOS 15 via `./test.sh`) with `ProgressionMetric` now from HardsetCore and
      `ProgressionChartView.SeriesInput` a typealias of `ProgressionChartSeries`. The chart's
      metric picker still shows "Heaviest load" and "Est. 1RM". With two machines named alike
      (create two unbranded "Leg Press" machines and log on both), the exercise's chart shows two
      lines in the legend, "Leg Press" and "Leg Press (2)".
```

- [ ] **Step 4: Run to verify pass**

Run: `Tools/linux-test.sh --filter 'ProgressionChartModelTests|ProgressionChartSeriesTests|ProgressionStoreTests|ProgressionTests'`,
then `Tools/linux-test.sh`.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/HardsetKit/Sources/HardsetCore/ProgressionChartModel.swift \
  Packages/HardsetKit/Sources/HardsetStore/VolumeStore.swift \
  Packages/HardsetKit/Sources/HardsetUI/ProgressionChartView.swift \
  Packages/HardsetKit/Tests/HardsetCoreTests/ProgressionChartModelTests.swift \
  Packages/HardsetKit/Tests/HardsetStoreTests/ProgressionChartSeriesTests.swift \
  docs/MAC-VERIFICATION.md
git commit -m "feat(core): the chart says what changed on one machine, and VoiceOver hears it

The headline, the scrub readout and the audio-graph description are Core values,
so the rule that a machine switch is not progress is tested: the headline reads
the machine used last, from its own first session to its own last, and the
description keeps one series per machine. Series labels were bare machine names,
and the chart keys a line by its label, so two leg presses called Leg Press drew
one line; labels are now brand first and numbered when they still collide.

Co-Authored-By: <your model's trailer>"
```

---

### Task 5: Spoken words and locale decimals (Core)

**Files:**
- Create: `Packages/HardsetKit/Sources/HardsetCore/AccessibleText.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetCore/WeightFormatter.swift:41` (before `spoken`)
- Modify: `Packages/HardsetKit/Sources/HardsetCore/SetEntryKeypad.swift:93-99` (`composedText`)
- Test: `Packages/HardsetKit/Tests/HardsetCoreTests/AccessibleTextTests.swift`

**Interfaces:**
- Consumes: `WeightFormatter.spoken(kilograms:)`, `total(kilograms:)`, `CountText`,
  `RecordCopy.announcement(for:exerciseName:formatter:)`, `SetEntryKeypad`, `NumericEntryBuffer`.
- Produces, for Tasks 13, 15 and 17:
  - `enum SetRowSpeech` with `label(number:isWarmup:)`, `value(weightKg:reps:isLogged:formatter:)`,
    `previous(_:formatter:) -> String?`, `hint(isLoggable:isLogged:) -> String?` and
    `logAnnouncement(number:isWarmup:weightKg:reps:exerciseName:records:formatter:) -> String`
  - `enum SessionVolumeText` with `written(_:formatter:)` (byte-identical to today's
    `HistoryView.volumeText`) and `spoken(_:formatter:)`
  - `WeightFormatter.spokenTotal(kilograms:) -> String`
  - `NumericEntryBuffer.displayText(locale:) -> String`
  - `SetEntryKeypad.spokenValue(locale:) -> String` and `spokenStep(_:locale:) -> String`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing

@testable import HardsetCore

@Suite("VoiceOver hears units in full, and numbers read in the lifter's locale")
struct AccessibleTextTests {
  private let posix = Locale(identifier: "en_US_POSIX")
  private var kilograms: WeightFormatter { WeightFormatter(unit: .kilograms, locale: posix) }
  private var pounds: WeightFormatter { WeightFormatter(unit: .pounds, locale: posix) }

  @Test("A row is labelled by its number and valued by what it holds")
  func rowSpeech() {
    #expect(SetRowSpeech.label(number: 2, isWarmup: false) == "Set 2")
    #expect(SetRowSpeech.label(number: 0, isWarmup: true) == "Warm-up set")
    #expect(
      SetRowSpeech.value(weightKg: 100, reps: 8, isLogged: false, formatter: kilograms)
        == "100 kilograms, 8 reps")
    #expect(
      SetRowSpeech.value(weightKg: 100, reps: 1, isLogged: true, formatter: kilograms)
        == "100 kilograms, 1 rep, logged")
    #expect(
      SetRowSpeech.value(weightKg: nil, reps: nil, isLogged: false, formatter: kilograms)
        == "no values entered")
  }

  @Test("A half-entered row says which half is missing")
  func halfEntered() {
    #expect(
      SetRowSpeech.value(weightKg: 60, reps: nil, isLogged: false, formatter: kilograms)
        == "60 kilograms, reps not entered")
    #expect(
      SetRowSpeech.value(weightKg: nil, reps: 8, isLogged: false, formatter: kilograms)
        == "weight not entered, 8 reps")
  }

  @Test("Pounds are spoken as pounds")
  func poundsInFull() {
    #expect(
      SetRowSpeech.value(weightKg: 60, reps: 8, isLogged: false, formatter: pounds)
        == "132.28 pounds, 8 reps")
    let last = PriorSetRecord(weightKg: 60, reps: 8, completedAt: .distantPast)
    #expect(SetRowSpeech.previous(last, formatter: pounds) == "Last time 132.28 pounds for 8 reps")
    #expect(SetRowSpeech.previous(nil, formatter: pounds) == nil)
  }

  @Test("The hint says what a double tap does, and a logged row has none")
  func hints() {
    #expect(SetRowSpeech.hint(isLoggable: true, isLogged: false) == "Double tap to log this set.")
    #expect(SetRowSpeech.hint(isLoggable: false, isLogged: false) == "Enter a weight and reps to log.")
    #expect(SetRowSpeech.hint(isLoggable: true, isLogged: true) == nil)
  }

  @Test("A log is announced once, with any record in the same breath")
  func logAnnouncement() {
    #expect(
      SetRowSpeech.logAnnouncement(
        number: 2, isWarmup: false, weightKg: 100, reps: 8, exerciseName: "Leg Press",
        records: [], formatter: kilograms) == "Set 2 logged, 100 kilograms, 8 reps.")
    let record = PersonalRecord(kind: .heaviestLoad, weightKg: 105, reps: 8, previousWeightKg: 100)
    #expect(
      SetRowSpeech.logAnnouncement(
        number: 3, isWarmup: false, weightKg: 105, reps: 8, exerciseName: "Leg Press",
        records: [record], formatter: kilograms)
        == "Set 3 logged, 105 kilograms, 8 reps. New record on Leg Press. "
        + "Heaviest weight: 105 kilograms, up from 100 kilograms.")
  }

  @Test("A session's totals read the same on every screen, written and spoken")
  func sessionVolume() {
    let volume = SessionVolume(workingSets: 12, warmupSets: 2, volumeKg: 9_400, reps: 96)
    #expect(SessionVolumeText.written(volume, formatter: kilograms) == "12 sets · 96 reps · 9400 kg · 2 warm-up")
    #expect(
      SessionVolumeText.spoken(volume, formatter: kilograms)
        == "12 sets, 96 reps, 9400 kilograms, 2 warm-up sets")
    let one = SessionVolume(workingSets: 1, warmupSets: 1, volumeKg: 0, reps: 1)
    #expect(SessionVolumeText.written(one, formatter: kilograms) == "1 set · 1 rep · 1 warm-up")
    #expect(SessionVolumeText.spoken(one, formatter: kilograms) == "1 set, 1 rep, 1 warm-up set")
    let empty = SessionVolume(workingSets: 0, warmupSets: 0, volumeKg: 0, reps: 0)
    #expect(SessionVolumeText.written(empty, formatter: kilograms) == "No sets")
  }

  @Test("A total is spoken whole, in the lifter's unit")
  func spokenTotal() {
    #expect(pounds.spokenTotal(kilograms: 9_400) == "20723 pounds")
    #expect(kilograms.spokenTotal(kilograms: 9_400.4) == "9400 kilograms")
  }

  /// Review Focus: in a comma-decimal locale the row and the pad header both show "62,5".
  @Test("The typed value shows the locale's separator")
  func keypadDisplayUsesLocaleSeparator() {
    let german = Locale(identifier: "de_DE")
    let buffer = NumericEntryBuffer(value: 62.5)
    #expect(buffer.displayText(locale: german) == "62,5")
    #expect(buffer.displayText(locale: posix) == "62.5")
    let keypad = SetEntryKeypad(
      draft: SetEntryDraft(weightKg: 62.5, reps: 8), unit: .kilograms, machineIncrementKg: nil)
    #expect(keypad.composedText(locale: german) == "62,5 kg × 8")
  }

  @Test("The pad speaks the value being composed, with its field")
  func padSpeaks() {
    var keypad = SetEntryKeypad(
      draft: SetEntryDraft(weightKg: 62.5, reps: 8), unit: .kilograms, machineIncrementKg: nil)
    #expect(keypad.spokenValue(locale: posix) == "Weight, 62.5 kilograms")
    keypad.clear()
    #expect(keypad.spokenValue(locale: posix) == "Weight, empty")
    keypad.focus(.reps)
    #expect(keypad.spokenValue(locale: posix) == "Reps, 8")
  }

  @Test("The step keys say how far they move, in full")
  func stepLabels() {
    var keypad = SetEntryKeypad(
      draft: SetEntryDraft(weightKg: 60, reps: 8), unit: .pounds, machineIncrementKg: nil)
    #expect(keypad.spokenStep(.up, locale: posix) == "Add 5 pounds")
    #expect(keypad.spokenStep(.down, locale: posix) == "Subtract 5 pounds")
    keypad.focus(.reps)
    #expect(keypad.spokenStep(.up, locale: posix) == "One more rep")
    let machine = SetEntryKeypad(
      draft: SetEntryDraft(weightKg: 60, reps: 8), unit: .kilograms, machineIncrementKg: 2.5)
    #expect(machine.spokenStep(.down, locale: posix) == "Subtract 2.5 kilograms")
  }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `Tools/linux-test.sh --filter AccessibleTextTests`
Expected: compile failure, `cannot find 'SetRowSpeech' in scope`.

- [ ] **Step 3: Implement**

Create `AccessibleText.swift`:

```swift
import Foundation

/// What VoiceOver says about a set row, and after a log (spec 3.4).
///
/// Written here, not in `SetRowView`, so every sentence is tested. Units are always in full:
/// VoiceOver reads "kg" as "k g", and "lb" as "l b".
public enum SetRowSpeech {
  /// The row's label: "Set 2", or "Warm-up set". `number` is the working-set number the row shows.
  public static func label(number: Int, isWarmup: Bool) -> String {
    isWarmup ? "Warm-up set" : "Set \(number)"
  }

  /// The row's value: "100 kilograms, 8 reps", with ", logged" once it is saved. A half-entered
  /// row says which half is missing.
  public static func value(
    weightKg: Double?, reps: Int?, isLogged: Bool, formatter: WeightFormatter
  ) -> String {
    let weight = weightKg.map { formatter.spoken(kilograms: $0) }
    let count = reps.map(CountText.reps)
    let entry: String =
      switch (weight, count) {
      case let (weight?, count?): "\(weight), \(count)"
      case let (weight?, nil): "\(weight), reps not entered"
      case let (nil, count?): "weight not entered, \(count)"
      case (nil, nil): "no values entered"
      }
    return isLogged ? "\(entry), logged" : entry
  }

  /// "Last time 100 kilograms for 8 reps", or nil with no history.
  public static func previous(_ record: PriorSetRecord?, formatter: WeightFormatter) -> String? {
    record.map { "Last time \(formatter.spoken(kilograms: $0.weightKg)) for \(CountText.reps($0.reps))" }
  }

  /// What a double tap does. Nil on a logged row, which has nothing left to do.
  public static func hint(isLoggable: Bool, isLogged: Bool) -> String? {
    guard !isLogged else { return nil }
    return isLoggable ? "Double tap to log this set." : "Enter a weight and reps to log."
  }

  /// Said once, after the write succeeds: "Set 2 logged, 100 kilograms, 8 reps." A record follows
  /// in the same announcement, so VoiceOver does not read two at once and drop one.
  public static func logAnnouncement(
    number: Int, isWarmup: Bool, weightKg: Double, reps: Int, exerciseName: String,
    records: [PersonalRecord], formatter: WeightFormatter
  ) -> String {
    let logged =
      "\(label(number: number, isWarmup: isWarmup)) logged, "
      + "\(formatter.spoken(kilograms: weightKg)), \(CountText.reps(reps))."
    guard
      let record = RecordCopy.announcement(
        for: records, exerciseName: exerciseName, formatter: formatter)
    else { return logged }
    return "\(logged) \(record)"
  }
}

/// A session's totals as one line, written and spoken. The history row and the session detail
/// both use it, so they cannot disagree.
public enum SessionVolumeText {
  /// "12 sets · 96 reps · 9400 kg · 2 warm-up", or "No sets".
  public static func written(_ volume: SessionVolume, formatter: WeightFormatter) -> String {
    guard !volume.isEmpty else { return "No sets" }
    var parts = [CountText.sets(volume.workingSets), CountText.reps(volume.reps)]
    if volume.volumeKg > 0 { parts.append(formatter.total(kilograms: volume.volumeKg)) }
    if volume.warmupSets > 0 { parts.append("\(volume.warmupSets) warm-up") }
    return parts.joined(separator: " · ")
  }

  /// "12 sets, 96 reps, 9400 kilograms, 2 warm-up sets", or "No sets".
  public static func spoken(_ volume: SessionVolume, formatter: WeightFormatter) -> String {
    guard !volume.isEmpty else { return "No sets" }
    var parts = [CountText.sets(volume.workingSets), CountText.reps(volume.reps)]
    if volume.volumeKg > 0 { parts.append(formatter.spokenTotal(kilograms: volume.volumeKg)) }
    if volume.warmupSets > 0 {
      parts.append(volume.warmupSets == 1 ? "1 warm-up set" : "\(volume.warmupSets) warm-up sets")
    }
    return parts.joined(separator: ", ")
  }
}

extension NumericEntryBuffer {
  /// The typed text with the locale's decimal separator: "62,5" in German. The buffer always
  /// stores ".", so the row and the pad header must both substitute, and both call this.
  public func displayText(locale: Locale) -> String {
    text.replacingOccurrences(of: ".", with: locale.decimalSeparator ?? ".")
  }
}

extension SetEntryKeypad {
  /// What the pad's header says to VoiceOver as the value changes: "Weight, 62.5 kilograms",
  /// "Reps, 8", or "Weight, empty". Spoken in full, never "kg".
  public func spokenValue(locale: Locale = .current) -> String {
    switch field {
    case .weight:
      guard let value = weight.value else { return "Weight, empty" }
      let formatter = WeightFormatter(unit: unit, locale: locale)
      return "Weight, \(formatter.spoken(kilograms: unit.toKilograms(value)))"
    case .reps:
      guard let value = reps.value else { return "Reps, empty" }
      return "Reps, \(Int(value))"
    }
  }

  /// The ± keys' spoken labels: "Add 2.5 kilograms", "One fewer rep".
  public func spokenStep(_ direction: Direction, locale: Locale = .current) -> String {
    switch field {
    case .weight:
      let amount = WeightFormatter(unit: unit, locale: locale)
        .spoken(kilograms: unit.toKilograms(loadStep.amount))
      return direction == .up ? "Add \(amount)" : "Subtract \(amount)"
    case .reps:
      return direction == .up ? "One more rep" : "One fewer rep"
    }
  }
}
```

In `WeightFormatter.swift`, immediately before `/// For VoiceOver: "62.5 kilograms".`:

```swift
  /// A total for VoiceOver: "20723 pounds". Whole, as `total(kilograms:)` is.
  public func spokenTotal(kilograms: Double) -> String {
    let rounded = unit.fromKilograms(kilograms).rounded()
    return spoken(kilograms: unit.toKilograms(rounded))
  }
```

In `SetEntryKeypad.composedText(locale:)`, replace the first three lines of the body with the one
substitution rule, so the pad header and the row cannot disagree:

```swift
  public func composedText(locale: Locale = .current) -> String {
    let weightText = weight.isEmpty ? "—" : weight.displayText(locale: locale)
    let repsText = reps.isEmpty ? "—" : reps.displayText
    return "\(weightText) \(unit.abbreviation) × \(repsText)"
  }
```

- [ ] **Step 4: Run to verify pass**

Run: `Tools/linux-test.sh --filter 'AccessibleTextTests|SetEntryKeypadTests|WeightFormatterTests|NumericEntryBufferTests'`,
then `Tools/linux-test.sh`.
Expected: PASS; the existing `composedText` tests are unchanged.

- [ ] **Step 5: Commit**

```bash
git add Packages/HardsetKit/Sources/HardsetCore/AccessibleText.swift \
  Packages/HardsetKit/Sources/HardsetCore/WeightFormatter.swift \
  Packages/HardsetKit/Sources/HardsetCore/SetEntryKeypad.swift \
  Packages/HardsetKit/Tests/HardsetCoreTests/AccessibleTextTests.swift
git commit -m "feat(core): what VoiceOver says, written where a test can hear it

The set row's spoken label, the pad's value, the step keys, the log
announcement and a session's totals were assembled inside views, where the
history row said 'kg' to VoiceOver and a half-typed row said only 'no values'.
They are Core sentences now, units always in full, and a record joins the log
announcement instead of racing it. The typed value's decimal separator has one
rule, shared by the row and the pad header.

Co-Authored-By: <your model's trailer>"
```

---

### Task 6: Equipment names, and rename (Core, Store)

**Files:**
- Create: `Packages/HardsetKit/Sources/HardsetCore/EquipmentName.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetStore/GymStore.swift:41` (before the `GymStore` doc
  comment), `:74` (before `archiveGym`) and `:117` (before `archiveMachine`)
- Modify: `Packages/HardsetKit/Sources/HardsetStore/FailureCopy.swift:12-27` and `:98-100`
- Test: `Packages/HardsetKit/Tests/HardsetCoreTests/EquipmentNameTests.swift`
- Test: `Packages/HardsetKit/Tests/HardsetStoreTests/GymRenameTests.swift`
- Modify: `Packages/HardsetKit/Tests/HardsetStoreTests/FailureCopyTests.swift` (table rows)

**Interfaces:**
- Consumes: `Gym` and `Machine` rows, `#bind`.
- Produces, for Tasks 7 and 19:
  - `public enum EquipmentName { static func normalized(_ raw: String) -> String? }`
  - `public enum GymStoreError: Error, Equatable, Sendable { case blankName, gymNotFound, machineNotFound }`
  - `GymStore.renameGym(_ id: GymID, to name: String) throws`
  - `GymStore.renameMachine(_ id: MachineID, name: String, brand: String) throws`
  - `FailureCopy.Action` cases `.renameGym`, `.archiveGym`, `.renameMachine`, `.archiveMachine`

`createGym` and `createMachine` are unchanged; callers normalise first (Task 7, Task 19).

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing

@testable import HardsetCore

@Suite("A typed name is tidied, and a blank one is refused")
struct EquipmentNameTests {
  @Test("Spaces at the ends go, and runs inside collapse to one")
  func tidied() {
    #expect(EquipmentName.normalized("  Iron   Temple ") == "Iron Temple")
    #expect(EquipmentName.normalized("Leg Press") == "Leg Press")
    #expect(EquipmentName.normalized("Hammer\u{00A0}Strength") == "Hammer Strength")
  }

  @Test("Nothing but whitespace is no name at all")
  func blank() {
    #expect(EquipmentName.normalized("") == nil)
    #expect(EquipmentName.normalized("   ") == nil)
    #expect(EquipmentName.normalized("\n\t ") == nil)
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

@Suite("Gyms and machines can be renamed, and a blank name never reaches the database")
struct GymRenameTests {
  let now = Date(timeIntervalSince1970: 42_000_000)

  private func fixture() throws -> (any DatabaseWriter, GymStore) {
    var configuration = Configuration.forTesting()
    configuration.foreignKeysEnabled = true
    let database = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(database)
    return (database, GymStore(database: database))
  }

  @Test("A gym's new name is tidied and read back")
  func renameGym() throws {
    let (_, gyms) = try fixture()
    let gym = try gyms.createGym(name: "Home", now: now)
    try gyms.renameGym(gym, to: "  Iron   Temple ")
    #expect(try gyms.gyms().map(\.name) == ["Iron Temple"])
  }

  /// Review Focus: a name of only spaces would be a blank row in every picker.
  @Test("Renaming to a blank name is refused and the old name stays")
  func renameToBlankLeavesName() throws {
    let (_, gyms) = try fixture()
    let gym = try gyms.createGym(name: "Home", now: now)
    let machine = try gyms.createMachine(at: gym, name: "Leg Press", brand: "Cybex", now: now)

    #expect(throws: GymStoreError.blankName) { try gyms.renameGym(gym, to: "   ") }
    #expect(throws: GymStoreError.blankName) {
      try gyms.renameMachine(machine, name: "\n", brand: "Hammer Strength")
    }
    #expect(try gyms.gyms().map(\.name) == ["Home"])
    #expect(try gyms.machines(at: gym).map(\.displayName) == ["Cybex Leg Press"])
  }

  @Test("A machine's name and brand change together, and a blank brand means none")
  func renameMachine() throws {
    let (_, gyms) = try fixture()
    let gym = try gyms.createGym(name: "Home", now: now)
    let machine = try gyms.createMachine(at: gym, name: "Leg Press", brand: "Cybex", now: now)

    try gyms.renameMachine(machine, name: " Leg Press 45° ", brand: " Hammer  Strength ")
    #expect(try gyms.machines(at: gym).map(\.displayName) == ["Hammer Strength Leg Press 45°"])

    try gyms.renameMachine(machine, name: "Leg Press", brand: "  ")
    let renamed = try #require(try gyms.machines(at: gym).first)
    #expect(renamed.brand == "")
    #expect(renamed.displayName == "Leg Press")
  }

  @Test("Renaming something that is not there says so")
  func notFound() throws {
    let (_, gyms) = try fixture()
    #expect(throws: GymStoreError.gymNotFound) { try gyms.renameGym(GymID(), to: "Home") }
    #expect(throws: GymStoreError.machineNotFound) {
      try gyms.renameMachine(MachineID(), name: "Leg Press", brand: "")
    }
  }

  @Test("History follows the machine, so past sessions read the new name")
  func historyReadsNewName() throws {
    let (database, gyms) = try fixture()
    let exercise = ExerciseID()
    try database.write { db in
      try Exercise.insert { Exercise.Draft(id: exercise.rawValue, name: "Leg Press") }.execute(db)
    }
    let gym = try gyms.createGym(name: "Home", now: now)
    let machine = try gyms.createMachine(at: gym, name: "Leg Press", now: now)
    let logger = LoggerStore(database: database)
    let session = try logger.startSession(gymID: gym, at: now)
    _ = try logger.logSet(
      sessionID: session, exerciseID: exercise, machineID: machine,
      draft: SetEntryDraft(weightKg: 100, reps: 8), at: now.addingTimeInterval(60))
    try logger.finishSession(session, at: now.addingTimeInterval(600))

    try gyms.renameMachine(machine, name: "Leg Press", brand: "Hammer Strength")

    let summary = try WorkoutSummaryStore(database: database).summary(for: session)
    #expect(summary.machinesUsed == ["Hammer Strength Leg Press"])
  }

  @Test("An archived gym leaves the list, and its machines stay readable")
  func archive() throws {
    let (_, gyms) = try fixture()
    let gym = try gyms.createGym(name: "Old gym", now: now)
    _ = try gyms.createMachine(at: gym, name: "Leg Press", now: now)
    try gyms.archiveGym(gym)
    #expect(try gyms.gyms().isEmpty)
    #expect(try gyms.machines(at: gym).map(\.name) == ["Leg Press"])
  }
}
```

In `FailureCopyTests.swift`, append these rows to the `arguments:` array of `copyMatchesTable`
(after the last `CopyRow`). The parameterised `neverLeaks` test covers the new cases automatically
through `Action.allCases`.

```swift
      CopyRow(
        error: GymStoreError.blankName, action: .renameGym,
        expected: "Enter a name for this gym."),
      CopyRow(
        error: Opaque(), action: .renameGym,
        expected: "That gym could not be renamed. Try again."),
      CopyRow(
        error: Opaque(), action: .archiveGym,
        expected: "That gym could not be archived. It is still in your list — try again."),
      CopyRow(
        error: GymStoreError.blankName, action: .renameMachine,
        expected: "Enter a name for this machine."),
      CopyRow(
        error: Opaque(), action: .renameMachine,
        expected: "That machine could not be renamed. Try again."),
      CopyRow(
        error: Opaque(), action: .archiveMachine,
        expected: "That machine could not be archived. It is still in your list — try again."),
```

- [ ] **Step 2: Run to verify failure**

Run: `Tools/linux-test.sh --filter 'EquipmentNameTests|GymRenameTests|FailureCopyTests'`
Expected: compile failure, `cannot find 'EquipmentName' in scope`.

- [ ] **Step 3: Implement**

Create `EquipmentName.swift`:

```swift
import Foundation

/// The one rule for a gym or machine name the lifter typed.
public enum EquipmentName {
  /// The name as it will be stored: spaces at either end removed, runs of spaces inside it
  /// collapsed to one, and nil when nothing is left. A blank name would put an empty row in every
  /// picker, with nothing to tell it apart.
  public static func normalized(_ raw: String) -> String? {
    let words = raw.split(whereSeparator: \.isWhitespace)
    return words.isEmpty ? nil : words.joined(separator: " ")
  }
}
```

In `GymStore.swift`, before `/// Gyms and their machines.`:

```swift
/// Why a gym or machine change was refused.
public enum GymStoreError: Error, Equatable, Sendable {
  /// The name was empty, or only spaces.
  case blankName
  case gymNotFound
  case machineNotFound
}
```

Before `archiveGym`'s doc comment:

```swift
  /// Renames a gym. The name is tidied by `EquipmentName`, and a blank one is refused before
  /// anything is written, so the old name stays.
  public func renameGym(_ id: GymID, to name: String) throws {
    guard let name = EquipmentName.normalized(name) else { throw GymStoreError.blankName }
    try database.write { db in
      guard try Gym.where({ $0.id.eq(id.rawValue) }).fetchOne(db) != nil else {
        throw GymStoreError.gymNotFound
      }
      try Gym.where { $0.id.eq(id.rawValue) }.update { $0.name = #bind(name) }.execute(db)
    }
  }
```

Before `public func archiveMachine(_ id: MachineID) throws {`:

```swift
  /// Renames a machine and sets its brand. The name is required; an empty brand means unknown.
  ///
  /// History follows the machine, not the name: its sets are keyed by id, so every past session
  /// and chart reads the new name. That is right, because it is the same machine.
  public func renameMachine(_ id: MachineID, name: String, brand: String) throws {
    guard let name = EquipmentName.normalized(name) else { throw GymStoreError.blankName }
    let brand = EquipmentName.normalized(brand) ?? ""
    try database.write { db in
      guard try Machine.where({ $0.id.eq(id.rawValue) }).fetchOne(db) != nil else {
        throw GymStoreError.machineNotFound
      }
      try Machine
        .where { $0.id.eq(id.rawValue) }
        .update {
          $0.name = #bind(name)
          $0.brand = #bind(brand)
        }
        .execute(db)
    }
  }
```

In `FailureCopy.swift`, add the four cases after `case loadSummary`, and their messages after the
`.loadSummary` case of the switch:

```swift
    case renameGym
    case archiveGym
    case renameMachine
    case archiveMachine
```

```swift
    case .renameGym:
      if let gymError = error as? GymStoreError, gymError == .blankName {
        return "Enter a name for this gym."
      }
      return "That gym could not be renamed. Try again."

    case .archiveGym:
      return "That gym could not be archived. It is still in your list — try again."

    case .renameMachine:
      if let gymError = error as? GymStoreError, gymError == .blankName {
        return "Enter a name for this machine."
      }
      return "That machine could not be renamed. Try again."

    case .archiveMachine:
      return "That machine could not be archived. It is still in your list — try again."
```

Check: `rg -n 'switch .*action' Packages/HardsetKit/Sources` finds only `FailureCopy.message`, so
the new cases break no other exhaustive switch.

- [ ] **Step 4: Run to verify pass**

Run: `Tools/linux-test.sh --filter 'EquipmentNameTests|GymRenameTests|FailureCopyTests|GymStoreTests'`,
then `Tools/linux-test.sh`.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/HardsetKit/Sources/HardsetCore/EquipmentName.swift \
  Packages/HardsetKit/Sources/HardsetStore/GymStore.swift \
  Packages/HardsetKit/Sources/HardsetStore/FailureCopy.swift \
  Packages/HardsetKit/Tests/HardsetCoreTests/EquipmentNameTests.swift \
  Packages/HardsetKit/Tests/HardsetStoreTests/GymRenameTests.swift \
  Packages/HardsetKit/Tests/HardsetStoreTests/FailureCopyTests.swift
git commit -m "feat(store): rename a gym or a machine, and never to a blank

GymStore could create and archive but not rename, so a typo in a machine's name
lived in every chart and summary forever. Rename is added beside archive, and a
name of only spaces is refused before anything is written, because it would be
a blank row in every picker. One rule tidies typed names for every caller.

Co-Authored-By: <your model's trailer>"
```

---

### Task 7: First run — when it shows, what it promises, the unit it guesses (Core, Store)

**Files:**
- Create: `Packages/HardsetKit/Sources/HardsetCore/FirstRun.swift`
- Create: `Packages/HardsetKit/Sources/HardsetStore/FirstRunStore.swift`
- Test: `Packages/HardsetKit/Tests/HardsetCoreTests/FirstRunTests.swift`
- Test: `Packages/HardsetKit/Tests/HardsetStoreTests/FirstRunStoreTests.swift`

**Interfaces:**
- Consumes: `EquipmentName.normalized` and `GymStore.createGym(name:now:)` (Task 6),
  `Session` rows.
- Produces, for Task 18:
  - `public struct FirstRunPromise: Hashable, Sendable, Identifiable` (`id`, `symbolName`, `title`,
    `detail`)
  - `public enum FirstRunCopy` with `promises`, `privacy`, `start`, `gymFieldPrompt`, `gymFootnote`
  - `static func WeightUnit.inferred(from locale: Locale) -> WeightUnit`
  - `public nonisolated protocol FirstRunFlag: AnyObject, Sendable { var isComplete: Bool { get }; func markComplete() }`
  - `UserDefaultsFirstRunFlag(defaults: UserDefaults = .standard)` (key `hardset.firstRunComplete`)
    and `InMemoryFirstRunFlag(isComplete: Bool = false)`
  - `public nonisolated struct FirstRunStore` with `init(database:flag:)`,
    `func shouldShow() throws -> Bool` and
    `@discardableResult func complete(gymName: String, now: Date = Date()) throws -> GymID?`

Rules (each a test below): it shows only when the flag is unset and no session exists, open or
finished; Start hides it for good; a blank gym name creates no gym; a named gym is tidied and
returned so the root can select it; a gym that cannot be written leaves the screen unfinished
(persist before claiming); the flag survives a relaunch; the copy has three promises, the spec's
privacy line word for word, and no goal, target, program, plan, streak, coach or questionnaire.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing

@testable import HardsetCore

@Suite("The first screen promises three things and asks for nothing")
struct FirstRunTests {
  @Test("Three promises, each with its own glyph")
  func threePromises() {
    #expect(FirstRunCopy.promises.map(\.id) == ["honest", "machines", "fast"])
    #expect(Set(FirstRunCopy.promises.map(\.symbolName)).count == 3)
    for promise in FirstRunCopy.promises {
      #expect(!promise.title.isEmpty)
      #expect(!promise.detail.isEmpty)
    }
  }

  @Test("The privacy line is the spec's, word for word")
  func privacy() {
    #expect(FirstRunCopy.privacy == "No account. Your data stays on your devices and in your iCloud.")
  }

  /// `HANDOFF.md` §6: no targets, no program, no coaching. The first screen is where an app is
  /// most tempted to ask for a goal.
  @Test("Nothing on the screen asks for a goal, a target, a program or a streak")
  func asksForNothing() {
    let copy =
      FirstRunCopy.promises.flatMap { [$0.title, $0.detail] }
      + [FirstRunCopy.privacy, FirstRunCopy.start, FirstRunCopy.gymFieldPrompt, FirstRunCopy.gymFootnote]
    let refused: Set<String> = [
      "goal", "goals", "target", "targets", "program", "programme", "plan", "streak", "coach",
      "questionnaire",
    ]
    for line in copy {
      let words = line.lowercased().split { !$0.isLetter }.map(String.init)
      #expect(refused.isDisjoint(with: words), "\(line)")
    }
  }

  @Test("Naming a gym is offered as optional")
  func gymIsOptional() {
    #expect(FirstRunCopy.gymFieldPrompt.contains("optional"))
  }

  @Test("The unit is guessed from the region: pounds only for the US system")
  func inferredUnit() {
    #expect(WeightUnit.inferred(from: Locale(identifier: "en_US")) == .pounds)
    #expect(WeightUnit.inferred(from: Locale(identifier: "en_LR")) == .pounds)
    #expect(WeightUnit.inferred(from: Locale(identifier: "en_GB")) == .kilograms)
    #expect(WeightUnit.inferred(from: Locale(identifier: "de_DE")) == .kilograms)
    #expect(WeightUnit.inferred(from: Locale(identifier: "en_CA")) == .kilograms)
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

@Suite("The first screen shows once, only to someone new, and asks nothing it does not need")
struct FirstRunStoreTests {
  let now = Date(timeIntervalSince1970: 43_000_000)

  private func database(migrated: Bool = true) throws -> any DatabaseWriter {
    var configuration = Configuration.forTesting()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    if migrated { try HardsetMigrations.migrator().migrate(queue) }
    return queue
  }

  @Test("A fresh install shows it, and finishing it hides it for good")
  func freshInstall() throws {
    let store = FirstRunStore(database: try database(), flag: InMemoryFirstRunFlag())
    #expect(try store.shouldShow())
    try store.complete(gymName: "", now: now)
    #expect(try !store.shouldShow())
  }

  /// Review Focus: an update reaches people with years of history and a flag that never existed.
  @Test("Someone with history never sees it, though the flag is new to them")
  func existingHistorySkipsFirstRun() throws {
    let db = try database()
    let logger = LoggerStore(database: db)
    let session = try logger.startSession(at: now)
    try logger.finishSession(session, at: now.addingTimeInterval(600))
    #expect(try !FirstRunStore(database: db, flag: InMemoryFirstRunFlag()).shouldShow())
  }

  /// Review Focus: a workout left open is offered back first; a welcome must not hide it.
  @Test("A workout left open is never hidden behind it")
  func openWorkoutSkipsFirstRun() throws {
    let db = try database()
    _ = try LoggerStore(database: db).startSession(at: now)
    #expect(try !FirstRunStore(database: db, flag: InMemoryFirstRunFlag()).shouldShow())
  }

  /// Review Focus: an optional field left as spaces must not create a nameless gym.
  @Test("A blank gym name creates no gym")
  func blankGymNameCreatesNoGym() throws {
    let db = try database()
    let flag = InMemoryFirstRunFlag()
    #expect(try FirstRunStore(database: db, flag: flag).complete(gymName: "   ", now: now) == nil)
    #expect(try GymStore(database: db).gyms().isEmpty)
    #expect(flag.isComplete)
  }

  @Test("A named gym is created, tidied, and returned so it can be selected")
  func namedGym() throws {
    let db = try database()
    let id = try FirstRunStore(database: db, flag: InMemoryFirstRunFlag())
      .complete(gymName: " Iron   Temple ", now: now)
    let gyms = try GymStore(database: db).gyms()
    #expect(gyms.map(\.name) == ["Iron Temple"])
    #expect(gyms.first?.id == id)
  }

  @Test("A gym that cannot be saved leaves the first screen unfinished")
  func failedGymLeavesItOpen() throws {
    let flag = InMemoryFirstRunFlag()
    let store = FirstRunStore(database: try database(migrated: false), flag: flag)
    #expect(throws: (any Error).self) { try store.complete(gymName: "Home", now: now) }
    #expect(!flag.isComplete)
  }

  @Test("The flag survives a relaunch")
  func flagPersists() {
    let defaults = UserDefaults(suiteName: "hardset.tests.\(UUID().uuidString)")!
    #expect(!UserDefaultsFirstRunFlag(defaults: defaults).isComplete)
    UserDefaultsFirstRunFlag(defaults: defaults).markComplete()
    #expect(UserDefaultsFirstRunFlag(defaults: defaults).isComplete)
  }
}
```

`Locale.measurementSystem` works on Linux (checked in the container: `en_US` and `en_LR` are US,
`en_GB` and `my_MM` UK, `de_DE` and `en_CA` metric).

- [ ] **Step 2: Run to verify failure**

Run: `Tools/linux-test.sh --filter 'FirstRunTests|FirstRunStoreTests'`
Expected: compile failure, `cannot find 'FirstRunCopy' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// One of the three things the first screen promises (spec 3.5).
public struct FirstRunPromise: Hashable, Sendable, Identifiable {
  public let id: String
  public let symbolName: String
  public let title: String
  public let detail: String
}

/// The words on the one first-run screen.
///
/// Three promises, the privacy line, and Start. No questionnaire, no goals, no program: each of
/// those would ask the lifter for a commitment the app then grades them against, and the app
/// refuses to grade (`HANDOFF.md` §6). A test holds this copy to that.
public enum FirstRunCopy {
  public static let promises: [FirstRunPromise] = [
    FirstRunPromise(
      id: "honest", symbolName: "checkmark.seal", title: "Honest numbers",
      detail:
        "Every estimate says how sure it is and where it comes from. When the app does not know, "
        + "it says so."),
    FirstRunPromise(
      id: "machines", symbolName: "dumbbell", title: "Your machines",
      detail:
        "Loads are kept per machine, so the same number on two different leg presses is never "
        + "mixed up."),
    FirstRunPromise(
      id: "fast", symbolName: "hand.tap", title: "Fast logging",
      detail: "Last time's numbers are filled in. One tap logs a set."),
  ]

  /// Spec §3, item 6, word for word.
  public static let privacy = "No account. Your data stays on your devices and in your iCloud."
  public static let start = "Start"
  public static let gymFieldPrompt = "Gym name (optional)"
  public static let gymFootnote = "Machines are tracked per gym. You can add one later."
}

extension WeightUnit {
  /// The unit a lifter in this region most likely reads, from the locale's measurement system.
  ///
  /// A guess, shown as one (`Assumption.unitFromRegion`), with the correction beside it. Only the
  /// US system means pounds: the UK measurement system still weighs gym plates in kilograms.
  public static func inferred(from locale: Locale) -> WeightUnit {
    locale.measurementSystem == .us ? .pounds : .kilograms
  }
}
```

```swift
import Foundation
import HardsetCore
import SQLiteData
import Synchronization

/// Whether the lifter has been through the first screen. Device-local, like rest choices: it is
/// not training data, and `UserDefaults` is already declared in the privacy manifest (CA92.1).
public nonisolated protocol FirstRunFlag: AnyObject, Sendable {
  var isComplete: Bool { get }
  func markComplete()
}

/// `UserDefaults` is documented as thread-safe, which is what makes `@unchecked` honest here.
public nonisolated final class UserDefaultsFirstRunFlag: FirstRunFlag, @unchecked Sendable {
  static let key = "hardset.firstRunComplete"
  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  public var isComplete: Bool { defaults.bool(forKey: Self.key) }

  public func markComplete() {
    defaults.set(true, forKey: Self.key)
  }
}

/// For tests and previews.
public nonisolated final class InMemoryFirstRunFlag: FirstRunFlag {
  private let storage: Mutex<Bool>

  public init(isComplete: Bool = false) {
    storage = Mutex(isComplete)
  }

  public var isComplete: Bool { storage.withLock { $0 } }

  public func markComplete() {
    storage.withLock { $0 = true }
  }
}

/// Decides whether the first screen shows, and ends it (spec 3.5).
public nonisolated struct FirstRunStore {
  private let database: any DatabaseWriter
  private let flag: any FirstRunFlag

  public init(database: any DatabaseWriter, flag: any FirstRunFlag) {
    self.database = database
    self.flag = flag
  }

  /// True only for someone who has never finished the first screen and has no workout at all,
  /// open or finished.
  ///
  /// Someone updating with history has the flag unset, because it is new, and must not be greeted
  /// as a stranger. A workout left open must be offered back, not hidden behind a welcome.
  public func shouldShow() throws -> Bool {
    guard !flag.isComplete else { return false }
    let anySession = try database.read { db in
      try Session.order { $0.startedAt.desc() }.fetchOne(db)
    }
    return anySession == nil
  }

  /// Ends the first screen: creates the gym when a name was given, then marks it done.
  ///
  /// The name goes through `EquipmentName`, so "   " creates nothing. The flag is set only after
  /// the gym is written: if that write fails the screen stays, with the name still typed, rather
  /// than claiming a gym that does not exist.
  @discardableResult
  public func complete(gymName: String, now: Date = Date()) throws -> GymID? {
    let gym = try EquipmentName.normalized(gymName).map {
      try GymStore(database: database).createGym(name: $0, now: now)
    }
    flag.markComplete()
    return gym
  }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `Tools/linux-test.sh --filter 'FirstRunTests|FirstRunStoreTests'`, then `Tools/linux-test.sh`.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/HardsetKit/Sources/HardsetCore/FirstRun.swift \
  Packages/HardsetKit/Sources/HardsetStore/FirstRunStore.swift \
  Packages/HardsetKit/Tests/HardsetCoreTests/FirstRunTests.swift \
  Packages/HardsetKit/Tests/HardsetStoreTests/FirstRunStoreTests.swift
git commit -m "feat(store): a first screen that shows once, only to someone new

The decision is tested where it can be: the screen shows only when it has never
been finished and no workout exists, so an update never greets a lifter with
history as a stranger and a workout left open is never hidden behind a welcome.
Naming a gym stays optional, a blank name creates nothing, and the flag is set
only after the gym is written. The copy promises three things and asks for no
goal, target or program, and a test holds it to that.

Co-Authored-By: <your model's trailer>"
```

---

### Task 8: A past workout, read back (Core, Store)

**Files:**
- Create: `Packages/HardsetKit/Sources/HardsetCore/SessionDetail.swift`
- Create: `Packages/HardsetKit/Sources/HardsetStore/SessionDetailStore.swift`
- Test: `Packages/HardsetKit/Tests/HardsetCoreTests/SessionDetailTests.swift`
- Test: `Packages/HardsetKit/Tests/HardsetStoreTests/SessionDetailStoreTests.swift`

**Interfaces:**
- Consumes: `WorkoutSummaryStore.summary(for:)` (Phase 2 Task 8), `MachineRecord.displayName`,
  `LoggerStoreError.sessionNotFound`, `ProgressionKey`.
- Produces, for Task 17:
  - `public struct SessionDetail: Hashable, Sendable` with `summary: WorkoutSummary`,
    `blocks: [Block]`, and `static func blocks(from entries: [Entry]) -> [Block]`
  - `SessionDetail.Block` (`exerciseID`, `exerciseName`, `machineID`, `machineName: String?`,
    `sets: [SetLine]`, `id: ProgressionKey`)
  - `SessionDetail.SetLine` (`setID`, `weightKg`, `reps`, `isWarmup`, `records: [PersonalRecord]`,
    `id: SetID`)
  - `SessionDetail.Entry` (a set with its names, before grouping)
  - `public nonisolated struct SessionDetailStore` with `init(database:)` and
    `func detail(for sessionID: SessionID) throws -> SessionDetail`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing

@testable import HardsetCore

@Suite("A past workout groups by movement and machine, and never merges two machines")
struct SessionDetailTests {
  private let start = Date(timeIntervalSince1970: 44_000_000)
  private let press = ExerciseID()
  private let curl = ExerciseID()
  private let hammer = MachineID()
  private let cybex = MachineID()

  private func entry(
    _ exercise: ExerciseID, _ name: String, _ machine: MachineID?, _ machineName: String?,
    _ weight: Double, at minute: Double, ordinal: Int = 0
  ) -> SessionDetail.Entry {
    SessionDetail.Entry(
      line: SessionDetail.SetLine(setID: SetID(), weightKg: weight, reps: 8, isWarmup: false, records: []),
      exerciseID: exercise, exerciseName: name, machineID: machine, machineName: machineName,
      completedAt: start.addingTimeInterval(minute * 60), setOrdinal: ordinal)
  }

  @Test("A movement on two machines is two blocks, in the order they were first used")
  func twoMachinesTwoBlocks() {
    let blocks = SessionDetail.blocks(from: [
      entry(press, "Leg Press", cybex, "Cybex", 90, at: 20),
      entry(press, "Leg Press", hammer, "Hammer", 100, at: 1),
      entry(press, "Leg Press", hammer, "Hammer", 105, at: 4),
    ])
    #expect(blocks.map(\.machineName) == ["Hammer", "Cybex"])
    #expect(blocks[0].sets.map(\.weightKg) == [100, 105])
    #expect(blocks[1].sets.map(\.weightKg) == [90])
  }

  @Test("Coming back to a machine later adds to its block")
  func returningJoinsBlock() {
    let blocks = SessionDetail.blocks(from: [
      entry(press, "Leg Press", hammer, "Hammer", 100, at: 1),
      entry(curl, "Curl", nil, nil, 20, at: 10),
      entry(press, "Leg Press", hammer, "Hammer", 100, at: 30),
    ])
    #expect(blocks.map(\.exerciseName) == ["Leg Press", "Curl"])
    #expect(blocks[0].sets.count == 2)
    #expect(blocks[1].machineName == nil)
  }

  @Test("Sets logged in the same instant keep their ordinal order")
  func sameInstant() {
    let blocks = SessionDetail.blocks(from: [
      entry(press, "Leg Press", hammer, "Hammer", 110, at: 1, ordinal: 1),
      entry(press, "Leg Press", hammer, "Hammer", 100, at: 1, ordinal: 0),
    ])
    #expect(blocks[0].sets.map(\.weightKg) == [100, 110])
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

@Suite("A past workout reads back from storage, by movement and machine")
struct SessionDetailStoreTests {
  let now = Date(timeIntervalSince1970: 45_000_000)

  private struct Fixture {
    let database: any DatabaseWriter
    let logger: LoggerStore
    let gyms: GymStore
    let details: SessionDetailStore
    let press: ExerciseID
    let gym: GymID
  }

  private func fixture() throws -> Fixture {
    var configuration = Configuration.forTesting()
    configuration.foreignKeysEnabled = true
    let database = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(database)
    let press = ExerciseID()
    try database.write { db in
      try Exercise.insert { Exercise.Draft(id: press.rawValue, name: "Leg Press") }.execute(db)
    }
    let gyms = GymStore(database: database)
    return Fixture(
      database: database, logger: LoggerStore(database: database), gyms: gyms,
      details: SessionDetailStore(database: database), press: press,
      gym: try gyms.createGym(name: "Home", now: now))
  }

  private func log(
    _ f: Fixture, _ session: SessionID, _ machine: MachineID?, _ weight: Double,
    warmup: Bool = false, at minute: Double
  ) throws -> SetID {
    try f.logger.logSet(
      sessionID: session, exerciseID: f.press, machineID: machine,
      draft: SetEntryDraft(weightKg: weight, reps: 8), isWarmup: warmup,
      at: now.addingTimeInterval(minute * 60))
  }

  /// Review Focus: the lifter moved from the Hammer to the Cybex mid-exercise. Those are two
  /// different efforts, and the detail must show them apart.
  @Test("One movement on two machines reads as two blocks, each named")
  func sameExerciseTwoMachinesTwoBlocks() throws {
    let f = try fixture()
    let hammer = try f.gyms.createMachine(at: f.gym, name: "Leg Press", brand: "Hammer Strength", now: now)
    let cybex = try f.gyms.createMachine(at: f.gym, name: "Leg Press", brand: "Cybex", now: now)
    let session = try f.logger.startSession(gymID: f.gym, at: now)
    _ = try log(f, session, hammer, 100, at: 1)
    _ = try log(f, session, hammer, 100, at: 4)
    _ = try log(f, session, cybex, 80, at: 10)
    try f.logger.finishSession(session, at: now.addingTimeInterval(1_800))

    let detail = try f.details.detail(for: session)
    #expect(detail.blocks.count == 2)
    #expect(detail.blocks.map(\.machineName) == ["Hammer Strength Leg Press", "Cybex Leg Press"])
    #expect(detail.blocks.map(\.sets.count) == [2, 1])
    #expect(detail.blocks.allSatisfy { $0.exerciseName == "Leg Press" })
  }

  /// Review Focus: archiving a machine must not turn its past sets into free weight.
  @Test("An archived machine keeps its name in the past")
  func archivedMachineStillNamed() throws {
    let f = try fixture()
    let hammer = try f.gyms.createMachine(at: f.gym, name: "Leg Press", brand: "Hammer Strength", now: now)
    let session = try f.logger.startSession(gymID: f.gym, at: now)
    _ = try log(f, session, hammer, 100, at: 1)
    try f.logger.finishSession(session, at: now.addingTimeInterval(1_800))
    try f.gyms.archiveMachine(hammer)

    let detail = try f.details.detail(for: session)
    #expect(detail.blocks.first?.machineName == "Hammer Strength Leg Press")
    #expect(detail.blocks.first?.machineID == hammer)
  }

  @Test("A record sits on the set that earned it, and warm-ups are listed as warm-ups")
  func recordsAndWarmups() throws {
    let f = try fixture()
    let hammer = try f.gyms.createMachine(at: f.gym, name: "Leg Press", now: now)
    let before = try f.logger.startSession(gymID: f.gym, at: now.addingTimeInterval(-7 * 86_400))
    _ = try f.logger.logSet(
      sessionID: before, exerciseID: f.press, machineID: hammer,
      draft: SetEntryDraft(weightKg: 100, reps: 8), at: now.addingTimeInterval(-7 * 86_400 + 60))
    try f.logger.finishSession(before, at: now.addingTimeInterval(-7 * 86_400 + 1_800))

    let session = try f.logger.startSession(gymID: f.gym, at: now)
    let warmup = try log(f, session, hammer, 60, warmup: true, at: 1)
    let best = try log(f, session, hammer, 110, at: 5)
    try f.logger.finishSession(session, at: now.addingTimeInterval(1_800))

    let sets = try #require(try f.details.detail(for: session).blocks.first).sets
    #expect(sets.map(\.setID) == [warmup, best])
    #expect(sets[0].isWarmup)
    #expect(sets[0].records.isEmpty)
    #expect(sets[1].records.map(\.kind).contains(.heaviestLoad))
  }

  @Test("A session left open overnight has no length, only the words")
  func honestLength() throws {
    let f = try fixture()
    let session = try f.logger.startSession(at: now)
    _ = try log(f, session, nil, 100, at: 1)
    try f.logger.finishSession(session, at: now.addingTimeInterval(7 * 3_600))

    let detail = try f.details.detail(for: session)
    #expect(detail.summary.length == nil)
    #expect(detail.summary.lengthText == "Length unknown")
    #expect(detail.blocks.first?.machineName == nil)
  }

  @Test("A session that is not there says so")
  func missing() throws {
    let f = try fixture()
    #expect(throws: LoggerStoreError.sessionNotFound) { try f.details.detail(for: SessionID()) }
  }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `Tools/linux-test.sh --filter 'SessionDetailTests|SessionDetailStoreTests'`
Expected: compile failure, `cannot find 'SessionDetail' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// One past workout, opened from history (spec 3.6): what was done, grouped by movement and
/// machine, with its records and an honest length.
///
/// A value with no database handle, read by `SessionDetailStore`. The totals, records and length
/// are the finish summary's own (`WorkoutSummary`), so the two screens cannot disagree about the
/// same session.
public struct SessionDetail: Hashable, Sendable {
  /// One logged set, as the detail lists it.
  public struct SetLine: Hashable, Sendable, Identifiable {
    public let setID: SetID
    public let weightKg: Double
    public let reps: Int
    public let isWarmup: Bool
    /// Records this set earned, judged as the summary judges them.
    public let records: [PersonalRecord]

    public init(setID: SetID, weightKg: Double, reps: Int, isWarmup: Bool, records: [PersonalRecord]) {
      self.setID = setID
      self.weightKg = weightKg
      self.reps = reps
      self.isWarmup = isWarmup
      self.records = records
    }

    public var id: SetID { setID }
  }

  /// One movement on one machine. A movement done on two machines is two blocks, never one: the
  /// numbers on different equipment are not the same effort (`DECISIONS.md` §20).
  public struct Block: Hashable, Sendable, Identifiable {
    public let exerciseID: ExerciseID
    public let exerciseName: String
    public let machineID: MachineID?
    /// Nil for free-weight work.
    public let machineName: String?
    /// In the order they were logged.
    public let sets: [SetLine]

    public init(
      exerciseID: ExerciseID, exerciseName: String, machineID: MachineID?, machineName: String?,
      sets: [SetLine]
    ) {
      self.exerciseID = exerciseID
      self.exerciseName = exerciseName
      self.machineID = machineID
      self.machineName = machineName
      self.sets = sets
    }

    public var id: ProgressionKey { ProgressionKey(exerciseID: exerciseID, machineID: machineID) }
  }

  /// A logged set with the names it is shown under, before grouping.
  public struct Entry: Hashable, Sendable {
    public let line: SetLine
    public let exerciseID: ExerciseID
    public let exerciseName: String
    public let machineID: MachineID?
    public let machineName: String?
    public let completedAt: Date
    public let setOrdinal: Int

    public init(
      line: SetLine, exerciseID: ExerciseID, exerciseName: String, machineID: MachineID?,
      machineName: String?, completedAt: Date, setOrdinal: Int
    ) {
      self.line = line
      self.exerciseID = exerciseID
      self.exerciseName = exerciseName
      self.machineID = machineID
      self.machineName = machineName
      self.completedAt = completedAt
      self.setOrdinal = setOrdinal
    }
  }

  public let summary: WorkoutSummary
  public let blocks: [Block]

  public init(summary: WorkoutSummary, blocks: [Block]) {
    self.summary = summary
    self.blocks = blocks
  }

  /// Groups sets by movement and machine. Blocks are ordered by their first set, and sets within
  /// a block by when they were logged. Coming back to a machine later in the workout adds to its
  /// block; moving to a different machine starts another.
  public static func blocks(from entries: [Entry]) -> [Block] {
    let ordered = entries.sorted {
      ($0.completedAt, $0.setOrdinal, $0.line.setID.description)
        < ($1.completedAt, $1.setOrdinal, $1.line.setID.description)
    }
    var order: [ProgressionKey] = []
    var grouped: [ProgressionKey: [Entry]] = [:]
    for entry in ordered {
      let key = ProgressionKey(exerciseID: entry.exerciseID, machineID: entry.machineID)
      if grouped[key] == nil { order.append(key) }
      grouped[key, default: []].append(entry)
    }
    return order.compactMap { key in
      guard let entries = grouped[key], let first = entries.first else { return nil }
      return Block(
        exerciseID: first.exerciseID, exerciseName: first.exerciseName,
        machineID: first.machineID, machineName: first.machineName,
        sets: entries.map(\.line))
    }
  }
}
```

```swift
import Foundation
import HardsetCore
import SQLiteData

/// Reads one past workout for the session detail screen, from storage only.
///
/// The totals, records and length come from `WorkoutSummaryStore`, so the detail and the finish
/// summary cannot disagree. Archived machines and movements keep their names: archiving hides
/// equipment from pickers, it does not un-perform the sets.
public nonisolated struct SessionDetailStore {
  private let database: any DatabaseWriter

  public init(database: any DatabaseWriter) {
    self.database = database
  }

  public func detail(for sessionID: SessionID) throws -> SessionDetail {
    let summary = try WorkoutSummaryStore(database: database).summary(for: sessionID)
    var records: [SetID: [PersonalRecord]] = [:]
    for line in summary.records { records[line.setID, default: []].append(line.record) }

    let entries = try database.read { db in
      let sets = try LoggedSet.where { $0.sessionID.eq(sessionID.rawValue) }.fetchAll(db)
      let exerciseIDs = Array(Set(sets.map(\.exerciseID)))
      let names =
        exerciseIDs.isEmpty
        ? [:]
        : try Exercise
          .where { $0.id.in(exerciseIDs) }
          .fetchAll(db)
          .reduce(into: [UUID: String]()) { $0[$1.id] = $1.name }
      let machineIDs = Array(Set(sets.compactMap(\.machineID)))
      let machines =
        machineIDs.isEmpty
        ? [:]
        : try Machine
          .where { $0.id.in(machineIDs) }
          .fetchAll(db)
          .reduce(into: [UUID: String]()) { $0[$1.id] = MachineRecord(row: $1).displayName }
      return sets.map { set in
        let setID = SetID(rawValue: set.id)
        return SessionDetail.Entry(
          line: SessionDetail.SetLine(
            setID: setID, weightKg: set.weightKg, reps: set.reps, isWarmup: set.isWarmup,
            records: records[setID] ?? []),
          exerciseID: ExerciseID(rawValue: set.exerciseID),
          exerciseName: names[set.exerciseID] ?? "Unknown movement",
          machineID: set.machineID.map(MachineID.init(rawValue:)),
          // A machine id with no row left is still a machine, not free weight.
          machineName: set.machineID.map { machines[$0] ?? "Unnamed machine" },
          completedAt: set.completedAt,
          setOrdinal: set.setOrdinal)
      }
    }
    return SessionDetail(summary: summary, blocks: SessionDetail.blocks(from: entries))
  }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `Tools/linux-test.sh --filter 'SessionDetailTests|SessionDetailStoreTests'`, then
`Tools/linux-test.sh`.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/HardsetKit/Sources/HardsetCore/SessionDetail.swift \
  Packages/HardsetKit/Sources/HardsetStore/SessionDetailStore.swift \
  Packages/HardsetKit/Tests/HardsetCoreTests/SessionDetailTests.swift \
  Packages/HardsetKit/Tests/HardsetStoreTests/SessionDetailStoreTests.swift
git commit -m "feat(store): a past workout, by movement and machine, from the database

History rows led nowhere. A session detail is read from storage the way the
finish summary is, so the two cannot disagree, and grouped by movement and
machine: a leg press done on two machines is two blocks, because those numbers
are not the same effort. A machine archived since keeps its name, and a session
left open overnight still has no length.

Co-Authored-By: <your model's trailer>"
```

---

### Task 9: Muscle names in Core

**Files:**
- Create: `Packages/HardsetKit/Sources/HardsetCore/MuscleNames.swift`
- Test: `Packages/HardsetKit/Tests/HardsetCoreTests/MuscleNamesTests.swift`

**Interfaces:**
- Consumes: `Muscle`, `MuscleKey`.
- Produces, for Tasks 11, 12, 13 and 17: `Muscle.displayName: String` and
  `MuscleKey.displayName: String`. `ExercisePickerView.displayName(_:)` is removed by Task 12, which
  migrates its callers.

- [ ] **Step 1: Write the failing test**

The expected names are `ExercisePickerView.copy` at `40fc33b`, so nothing a lifter reads changes.

```swift
import Foundation
import Testing

@testable import HardsetCore

@Suite("Every muscle has a written name, and an unknown token is never shown raw")
struct MuscleNamesTests {
  @Test("The names are the ones the app has always shown")
  func names() {
    let expected: [Muscle: String] = [
      .chest: "Chest", .frontDelts: "Front delts", .sideDelts: "Side delts",
      .rearDelts: "Rear delts", .rotatorCuff: "Rotator cuff", .lats: "Lats",
      .upperBack: "Upper back", .traps: "Traps", .lowerBack: "Lower back",
      .biceps: "Biceps", .triceps: "Triceps", .forearms: "Forearms",
      .abs: "Abs", .obliques: "Obliques", .neck: "Neck",
      .quadriceps: "Quads", .hamstrings: "Hamstrings", .glutes: "Glutes",
      .adductors: "Adductors", .hipAbductors: "Hip abductors",
      .gastrocnemius: "Gastrocnemius", .soleus: "Soleus",
    ]
    #expect(expected.count == Muscle.allCases.count)
    for muscle in Muscle.allCases {
      #expect(muscle.displayName == expected[muscle])
    }
  }

  @Test("No two muscles share a name, and none is its raw token")
  func distinct() {
    let names = Muscle.allCases.map(\.displayName)
    #expect(Set(names).count == names.count)
    for muscle in Muscle.allCases where muscle.rawValue.contains(where: \.isUppercase) {
      #expect(muscle.displayName != muscle.rawValue)
    }
  }

  @Test("A key names its muscle, or says plainly that it has none")
  func keys() {
    #expect(MuscleKey(.quadriceps).displayName == "Quads")
    #expect(MuscleKey(stored: MuscleKey.notAttributedRawValue).displayName == "Not attributed")
    #expect(MuscleKey(stored: "serratusAnterior").displayName == "Not recognised")
  }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `Tools/linux-test.sh --filter MuscleNamesTests`
Expected: compile failure, `value of type 'Muscle' has no member 'displayName'`.

- [ ] **Step 3: Implement**

```swift
import Foundation

extension Muscle {
  /// The name a lifter reads.
  ///
  /// Moved here from `ExercisePickerView`, where it was a dictionary with a raw-value fallback: a
  /// muscle missing from it would have shown "rotatorCuff". A total switch cannot miss one, and a
  /// test pins every word. `displayNameKey` remains the String Catalog key for it.
  public var displayName: String {
    switch self {
    case .chest: "Chest"
    case .frontDelts: "Front delts"
    case .sideDelts: "Side delts"
    case .rearDelts: "Rear delts"
    case .rotatorCuff: "Rotator cuff"
    case .lats: "Lats"
    case .upperBack: "Upper back"
    case .traps: "Traps"
    case .lowerBack: "Lower back"
    case .biceps: "Biceps"
    case .triceps: "Triceps"
    case .forearms: "Forearms"
    case .abs: "Abs"
    case .obliques: "Obliques"
    case .neck: "Neck"
    case .quadriceps: "Quads"
    case .hamstrings: "Hamstrings"
    case .glutes: "Glutes"
    case .adductors: "Adductors"
    case .hipAbductors: "Hip abductors"
    case .gastrocnemius: "Gastrocnemius"
    case .soleus: "Soleus"
    }
  }
}

extension MuscleKey {
  /// The muscle's name, or a plain statement of why there is none. Never the raw token: a
  /// generated name looks authored and is not.
  public var displayName: String {
    if let muscle { return muscle.displayName }
    return isReservedSentinel ? "Not attributed" : "Not recognised"
  }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `Tools/linux-test.sh --filter MuscleNamesTests`, then `Tools/linux-test.sh`.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/HardsetKit/Sources/HardsetCore/MuscleNames.swift \
  Packages/HardsetKit/Tests/HardsetCoreTests/MuscleNamesTests.swift
git commit -m "feat(core): muscle names live with the muscles

The names were a dictionary in the exercise picker with a raw-value fallback, so
a muscle missing from it would have read 'rotatorCuff', and the volume screen
and summary reached into the picker for them. A total switch in Core cannot miss
one, and a test pins every word.

Co-Authored-By: <your model's trailer>"
```

---

### Task 10: The localization seam and Core's String Catalog (Core; Mac gate)

This is the spec's "known risk" (3.8): a package resource once broke the app's asset build step
(`Package.swift`'s HardsetUI comment, around lines 68–70). It is kept small and alone, and nothing
is built on it until its ledger entry is checked on the Mac.

**Files:**
- Modify: `Packages/HardsetKit/Package.swift` (the `HardsetCore` target, and `Package(name:…)`)
- Create: `Packages/HardsetKit/Sources/HardsetCore/Resources/Localizable.xcstrings`
- Create: `Packages/HardsetKit/Sources/HardsetCore/Localized.swift`
- Test: `Packages/HardsetKit/Tests/HardsetCoreTests/LocalizedTests.swift`
- Modify: `DECISIONS.md` (append §23)
- Modify: `docs/MAC-VERIFICATION.md`

**Interfaces:**
- Consumes: nothing.
- Produces, for Task 11 only:
  - internal `typealias CopyText` (`String.LocalizationValue` on Apple platforms, `String` on Linux)
  - internal `func localized(_ text: CopyText, comment: StaticString) -> String`
  - internal `func localized(key: StaticString, default text: CopyText, comment: StaticString) -> String`
  - `Bundle.module` for HardsetCore (generated by SwiftPM once the target has a resource)

**Read and cite first** (checked 2026-10-11):
- https://developer.apple.com/documentation/swift/string/init(localized:table:bundle:locale:comment:)
  (iOS 15, macOS 12)
- https://developer.apple.com/documentation/swift/string/localizationvalue (iOS 15, macOS 12)
- https://developer.apple.com/documentation/foundation/bundle/localizedstring(forkey:value:table:)
  (the Linux-safe call; not used here, named in §23 as the fallback's mechanism)

What was checked in the swift:6.2 container before writing this task: `String(localized:)` in every
overload, `LocalizedStringResource` and `AttributedString(localized:)` fail to compile; a target
with `resources: [.process("Resources")]` holding a `.xcstrings` builds, the file is copied
uncompiled, and `Bundle.module` resolves; `String(format:)` with `String` arguments works.

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing

@testable import HardsetCore

@Suite("Core copy goes through one door, and comes out as the same English on every platform")
struct LocalizedTests {
  @Test("A fixed sentence comes back as written")
  func fixed() {
    #expect(localized("Not evaluated", comment: "test") == "Not evaluated")
  }

  @Test("Interpolated words and counts come back in place")
  func interpolated() {
    let count = 3
    let total = 5
    #expect(localized("\(count) of \(total) logged", comment: "test") == "3 of 5 logged")
    let name = "Leg Press, 50%"
    #expect(localized("New record on \(name).", comment: "test") == "New record on Leg Press, 50%.")
  }

  @Test("A keyed lookup falls back to its English")
  func keyed() {
    #expect(localized(key: "muscle.chest", default: "Chest", comment: "test") == "Chest")
  }

  @Test("The catalog is valid, in English, and ships with Core")
  func catalog() throws {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Sources/HardsetCore/Resources/Localizable.xcstrings")
    let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    let catalog = try #require(object as? [String: Any])
    #expect(catalog["sourceLanguage"] as? String == "en")
    #expect(catalog["version"] as? String == "1.0")
    #expect(catalog["strings"] is [String: Any])
  }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `Tools/linux-test.sh --filter LocalizedTests`
Expected: compile failure, `cannot find 'localized' in scope`.

- [ ] **Step 3: Implement**

`Package.swift`: give HardsetCore its resource, and the package its development language.

```swift
  .target(
    name: "HardsetCore",
    resources: [.process("Resources")],
    swiftSettings: strictConcurrency
  ),
```

```swift
let package = Package(
  name: "HardsetKit",
  defaultLocalization: "en",
  // … platforms, products, dependencies, targets unchanged
```

Update the HardsetCore comment above the target ("Foundation-only, nonisolated, no platform
frameworks…") with one sentence: "Its one resource is the String Catalog for Core's copy
(`DECISIONS.md` §23)." Leave the HardsetUI "No resources on purpose" comment as it is: HardsetUI
still has none.

`Sources/HardsetCore/Resources/Localizable.xcstrings`, one manual entry so the Mac's compile step
has something to produce:

```json
{
  "sourceLanguage" : "en",
  "strings" : {
    "Not evaluated" : {
      "comment" : "Certainty word: the app has no basis for a value.",
      "extractionState" : "manual"
    }
  },
  "version" : "1.0"
}
```

`Sources/HardsetCore/Localized.swift`:

```swift
import Foundation

#if canImport(Darwin)
  /// What Core copy is written as. On Apple platforms a literal here is a
  /// `String.LocalizationValue`: an interpolated `Int` becomes `%lld` and a `String` `%@`, so the
  /// String Catalog can translate the sentence around them and vary it by plural.
  typealias CopyText = String.LocalizationValue
#else
  /// On Linux, where only the tests run, copy is plain English (`DECISIONS.md` §23).
  typealias CopyText = String
#endif

/// The one door Core's words go through on their way to a screen (spec 3.8).
///
/// `String(localized:)` and `LocalizedStringResource` do not exist in the Linux toolchain's
/// Foundation (swift:6.2, checked 2026-10-11), and Core's tests run there. So the call is made
/// here, once: Apple platforms look the text up in Core's String Catalog, and Linux returns the
/// English, which is the catalog's source language and the key. Both platforms therefore return
/// the same English, and every copy test pins both.
///
/// Interpolate only `String` and `Int`. A `Double` would become `%lf` on Apple platforms and print
/// six decimals there while printing "2.5" on Linux; format numbers first.
func localized(_ text: CopyText, comment: StaticString) -> String {
  #if canImport(Darwin)
    String(localized: text, bundle: .module, comment: comment)
  #else
    text
  #endif
}

/// The same, for copy that already has a stable key, such as `Muscle.displayNameKey`.
func localized(key: StaticString, default text: CopyText, comment: StaticString) -> String {
  #if canImport(Darwin)
    String(localized: key, defaultValue: text, bundle: .module, comment: comment)
  #else
    text
  #endif
}
```

`DECISIONS.md`, append:

```markdown
### 23. Core's copy goes through one seam, because Linux has no `String(localized:)`

Core's tests run on Linux (swift:6.2), whose Foundation has neither `String(localized:)` nor
`LocalizedStringResource` (checked 2026-10-11, every overload). So Core never calls them directly.
`localized(_:comment:)` in `HardsetCore/Localized.swift` takes a `String.LocalizationValue` on
Apple platforms and looks it up in Core's String Catalog (`bundle: .module`); on Linux it takes a
`String` and returns it. The English is the catalog's source language and its key, so both
platforms return the same English and the same copy tests pin both.

Only `String` and `Int` are interpolated into a `localized` literal. A `Double` would become `%lf`
on Apple platforms and print six decimals there, while printing "2.5" on Linux.

The catalog is HardsetCore's only resource. If the Mac's resource build step fails, the fallback is
contained: remove `resources:` and the catalog, and change the two Apple branches to
`String(localized: text, comment: comment)` and `String(localized: key, defaultValue: text,
comment: comment)` (the main bundle). Nothing else depends on `Bundle.module`.
```

Ledger, under `## Phase 3`:

```markdown
- [ ] **GATE for Task 11** (feat(core): one door for Core's words, and a String Catalog behind it)
      Core now has a resource bundle, the step that once broke the app build.
  - [ ] `./test.sh` passes on the Mac. `LocalizedTests` there exercise the Apple branch,
        `String(localized:bundle: .module)`, and must return the same English as on Linux.
  - [ ] The `Hardset` scheme builds for the iOS 26.4 simulator **and** archives (Product ›
        Archive), from the checkout's real path. If the checkout is normally opened through a
        symlink, build from that path too: the old actool failure was a write denied under a
        symlinked path.
  - [ ] The widget extension builds (it links HardsetCore).
  - [ ] In the built `Hardset.app`, `HardsetKit_HardsetCore.bundle` exists and contains a compiled
        `en.lproj/Localizable.strings` (or `.stringsdict`) with the "Not evaluated" entry.
  - [ ] Optional: with "Use Compiler to Extract Swift Strings" on, note whether Xcode extracts the
        `localized("…")` literals into the catalog. Record yes or no here; Task 11 adds manual
        entries only for keyed lookups either way.
  - [ ] If any of these fails: apply the fallback in `DECISIONS.md` §23, record the failure and
        the fallback here, and only then unblock Task 11.
```

- [ ] **Step 4: Run to verify pass**

Run: `Tools/linux-test.sh --filter LocalizedTests`, then `Tools/linux-test.sh`.
Expected: PASS. The build log shows no resource warning for HardsetCore.

- [ ] **Step 5: Commit**

```bash
git add Packages/HardsetKit/Package.swift \
  Packages/HardsetKit/Sources/HardsetCore/Localized.swift \
  Packages/HardsetKit/Sources/HardsetCore/Resources/Localizable.xcstrings \
  Packages/HardsetKit/Tests/HardsetCoreTests/LocalizedTests.swift \
  DECISIONS.md docs/MAC-VERIFICATION.md
git commit -m "feat(core): one door for Core's words, and a String Catalog behind it

Spec 3.8 asks for Core copy through String(localized:), which does not exist in
the Linux toolchain that runs Core's tests. One internal seam calls it on Apple
platforms against Core's own catalog and returns the English on Linux, so the
copy tests pin both. The catalog is Core's only resource, and a package resource
once broke the app build, so this lands alone and nothing uses it until the Mac
has built and archived it (DECISIONS §23 records the fallback).

https://developer.apple.com/documentation/swift/string/init(localized:table:bundle:locale:comment:)
https://developer.apple.com/documentation/swift/string/localizationvalue

Co-Authored-By: <your model's trailer>"
```

---

### Task 11: Core's copy through the seam (Core)

**Precondition:** Task 10's GATE entry in `docs/MAC-VERIFICATION.md` is checked on the Mac (or its
fallback applied and recorded), and Tasks 1–9 are merged, because they add copy this task moves.

**Files:**
- Modify (copy only, no logic): in `Packages/HardsetKit/Sources/HardsetCore/`,
  `CertaintyMark.swift`, `MuscleNames.swift`, `MuscleTaxonomy.swift`, `MuscleVolume.swift`,
  `StrengthMath.swift`, `Progression.swift`, `ProgressionChartModel.swift`, `WeightFormatter.swift`,
  `WeightUnit.swift`, `PersonalRecords.swift`, `RecordCopy.swift`, `WorkoutSummary.swift`,
  `SessionFlow.swift`, `RestPlan.swift`, `RestMetadata.swift`, `ExerciseLogState.swift`,
  `AccessibleText.swift`, `FirstRun.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetCore/Resources/Localizable.xcstrings`
- Modify: `Packages/HardsetKit/Tests/HardsetCoreTests/LocalizedTests.swift`

**Interfaces:**
- Consumes: `localized(_:comment:)` and `localized(key:default:comment:)` (Task 10).
- Produces: no new API. Every public signature is unchanged and every existing copy test passes
  unchanged, which is the proof that the English did not move.

Not localized, on purpose: `EvidenceSource.id` and `citation` (bibliographic records), SF Symbol
names, `UserDefaults` keys, `Muscle.rawValue`, and HardsetStore's copy (spec ambiguity 2).

- [ ] **Step 1: Write the failing test**

Append to `LocalizedTests.swift`:

```swift
@Suite("Every keyed lookup has its English in the catalog")
struct LocalizedCatalogTests {
  @Test("Each muscle name's key is in the catalog, with the English the code falls back to")
  func muscleKeysAreInCatalog() throws {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Sources/HardsetCore/Resources/Localizable.xcstrings")
    let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    let strings = try #require((object as? [String: Any])?["strings"] as? [String: Any])
    let keys =
      Muscle.allCases.map { ($0.displayNameKey, $0.displayName) }
      + [
        (MuscleKey(stored: MuscleKey.notAttributedRawValue).displayNameKey, "Not attributed"),
        (MuscleKey(stored: "unknown-token").displayNameKey, "Not recognised"),
      ]
    for (key, english) in keys {
      let entry = strings[key] as? [String: Any]
      let value =
        ((entry?["localizations"] as? [String: Any])?["en"] as? [String: Any])
        .flatMap { $0["stringUnit"] as? [String: Any] }?["value"] as? String
      #expect(value == english, "\(key)")
    }
  }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `Tools/linux-test.sh --filter LocalizedCatalogTests`
Expected: FAIL, one issue per muscle key (`value == english` with `nil`).

- [ ] **Step 3: Implement**

**3a. The catalog's keyed entries.** From the repository root:

```bash
python3 -I - <<'PY'
import json, pathlib
path = pathlib.Path("Packages/HardsetKit/Sources/HardsetCore/Resources/Localizable.xcstrings")
catalog = json.loads(path.read_text())
names = {
  "chest": "Chest", "frontDelts": "Front delts", "sideDelts": "Side delts",
  "rearDelts": "Rear delts", "rotatorCuff": "Rotator cuff", "lats": "Lats",
  "upperBack": "Upper back", "traps": "Traps", "lowerBack": "Lower back",
  "biceps": "Biceps", "triceps": "Triceps", "forearms": "Forearms", "abs": "Abs",
  "obliques": "Obliques", "neck": "Neck", "quadriceps": "Quads", "hamstrings": "Hamstrings",
  "glutes": "Glutes", "adductors": "Adductors", "hipAbductors": "Hip abductors",
  "gastrocnemius": "Gastrocnemius", "soleus": "Soleus",
  "notAttributed": "Not attributed", "notRecognised": "Not recognised",
}
for token, english in names.items():
    catalog["strings"][f"muscle.{token}"] = {
        "comment": "A muscle's name, as the volume tab, the summary and the picker show it.",
        "extractionState": "manual",
        "localizations": {"en": {"stringUnit": {"state": "translated", "value": english}}},
    }
path.write_text(json.dumps(catalog, indent=2, sort_keys=True, ensure_ascii=False) + "\n")
PY
```

**3b. The muscle names use their keys.** Replace `MuscleNames.swift` with this. Each case is a
keyed lookup whose key is that muscle's `displayNameKey`, so the String Catalog key the taxonomy has
always promised is the one used, and its default is the existing word:

```swift
import Foundation

extension Muscle {
  /// The name a lifter reads.
  ///
  /// Moved here from `ExercisePickerView`, where it was a dictionary with a raw-value fallback: a
  /// muscle missing from it would have shown "rotatorCuff". A total switch cannot miss one, and a
  /// test pins every word. `displayNameKey` remains the String Catalog key for it.
  public var displayName: String {
    switch self {
    case .chest: localized(key: "muscle.chest", default: "Chest", comment: Self.nameComment)
    case .frontDelts: localized(key: "muscle.frontDelts", default: "Front delts", comment: Self.nameComment)
    case .sideDelts: localized(key: "muscle.sideDelts", default: "Side delts", comment: Self.nameComment)
    case .rearDelts: localized(key: "muscle.rearDelts", default: "Rear delts", comment: Self.nameComment)
    case .rotatorCuff: localized(key: "muscle.rotatorCuff", default: "Rotator cuff", comment: Self.nameComment)
    case .lats: localized(key: "muscle.lats", default: "Lats", comment: Self.nameComment)
    case .upperBack: localized(key: "muscle.upperBack", default: "Upper back", comment: Self.nameComment)
    case .traps: localized(key: "muscle.traps", default: "Traps", comment: Self.nameComment)
    case .lowerBack: localized(key: "muscle.lowerBack", default: "Lower back", comment: Self.nameComment)
    case .biceps: localized(key: "muscle.biceps", default: "Biceps", comment: Self.nameComment)
    case .triceps: localized(key: "muscle.triceps", default: "Triceps", comment: Self.nameComment)
    case .forearms: localized(key: "muscle.forearms", default: "Forearms", comment: Self.nameComment)
    case .abs: localized(key: "muscle.abs", default: "Abs", comment: Self.nameComment)
    case .obliques: localized(key: "muscle.obliques", default: "Obliques", comment: Self.nameComment)
    case .neck: localized(key: "muscle.neck", default: "Neck", comment: Self.nameComment)
    case .quadriceps: localized(key: "muscle.quadriceps", default: "Quads", comment: Self.nameComment)
    case .hamstrings: localized(key: "muscle.hamstrings", default: "Hamstrings", comment: Self.nameComment)
    case .glutes: localized(key: "muscle.glutes", default: "Glutes", comment: Self.nameComment)
    case .adductors: localized(key: "muscle.adductors", default: "Adductors", comment: Self.nameComment)
    case .hipAbductors: localized(key: "muscle.hipAbductors", default: "Hip abductors", comment: Self.nameComment)
    case .gastrocnemius: localized(key: "muscle.gastrocnemius", default: "Gastrocnemius", comment: Self.nameComment)
    case .soleus: localized(key: "muscle.soleus", default: "Soleus", comment: Self.nameComment)
    }
  }
}

extension Muscle {
  static let nameComment: StaticString =
    "A muscle's name, as the volume tab, the summary and the picker show it."
}

extension MuscleKey {
  /// The muscle's name, or a plain statement of why there is none. Never the raw token: a
  /// generated name looks authored and is not.
  public var displayName: String {
    if let muscle { return muscle.displayName }
    return isReservedSentinel
      ? localized(key: "muscle.notAttributed", default: "Not attributed", comment: Muscle.nameComment)
      : localized(key: "muscle.notRecognised", default: "Not recognised", comment: Muscle.nameComment)
  }
}
```

**3c. Every other user-facing literal becomes `localized("…", comment: "…")`.** The English is
byte-identical; the comment tells a translator where it appears. Rules:
- A whole sentence is one call. Never splice a translated word into another translated sentence:
  `MachineChange.explanation`'s `direction` becomes two sentences.
- Interpolate only `String` and `Int`, never `Double`.
- Plurals keep their code-side `count == 1` choice between two keys ("1 set" / "\(count) sets"), so
  Linux, which has no compiled catalog, stays correct; the catalog may add plural variants to the
  "other" key later.
- `static let` copy (`FinishFlow.discardTitle`, the `EvidenceSource` constants) stays `static let`,
  initialised through `localized`.
- Methodology, valid-range and summary text is wrapped whole, with the comment
  `"Methodology disclosure (App Review 1.4.1). Translate exactly; do not soften."`. The Task 2
  "character for character" tests must still pass.

Worked examples, each compiled and run on Linux:

```swift
  // WeightFormatter.swift, CountText
  public static func sets(_ count: Int) -> String {
    count == 1
      ? localized("1 set", comment: "A count of exactly one working set.")
      : localized("\(count) sets", comment: "A count of working sets other than one.")
  }

  public static func reps(_ count: Int) -> String {
    count == 1
      ? localized("1 rep", comment: "A count of exactly one repetition.")
      : localized("\(count) reps", comment: "A count of repetitions other than one.")
  }
```

```swift
  // Progression.swift, MachineChange
  public func explanation(in unit: WeightUnit, locale: Locale = .current) -> String {
    let magnitude = abs(heaviestLoadDeltaKg)
    guard magnitude > 0 else {
      return localized(
        "You changed machines here. The load happened to match, which is a coincidence, not a comparison.",
        comment: "Under a load chart, at a machine switch where the heaviest load did not change.")
    }
    let load = WeightFormatter(unit: unit, locale: locale).load(kilograms: magnitude)
    // Two whole sentences, not one with "higher"/"lower" spliced in: a translation must be free to
    // put the direction where its grammar wants it.
    return heaviestLoadDeltaKg > 0
      ? localized(
        "You changed machines here. The load is \(load) higher, which is a difference between the machines rather than a change in strength.",
        comment: "Under a load chart, at a machine switch. The argument is a load such as 5 kg.")
      : localized(
        "You changed machines here. The load is \(load) lower, which is a difference between the machines rather than a change in strength.",
        comment: "Under a load chart, at a machine switch. The argument is a load such as 5 kg.")
  }
```

```swift
  // StrengthMath.swift, measuredSource
    title: localized("Measured single", comment: "Title of the methodology for a one-rep set."),
    methodology: localized(
      "A completed single at this load is reported directly. No estimation is involved.",
      comment: "Methodology disclosure (App Review 1.4.1). Translate exactly; do not soften."),
```

The full list of literals to convert, by file:
- `CertaintyMark.swift`: the four `word`s and four `shortWord`s; the three caveat `word`s; the
  `Assumption` labels and prompts (`unitFromRegion`'s becomes one sentence per unit, as above).
- `MuscleTaxonomy.swift`: `SetCounting.source` `title`, `methodology`, `validRange`, `summary`;
  `MuscleAdmissionGround.userFacingBasis` (both); `creditScheme`'s `meaning` and `basis` (all six).
- `MuscleVolume.swift`: both sources' `title`, `methodology`, `validRange`, `summary`.
- `StrengthMath.swift`: both sources' `title`, `methodology`, `validRange`, `summary`.
- `Progression.swift`: `MachineChange.explanation` (above); `ProgressionAnalyzer.source` `title`,
  `methodology`, `validRange`, `summary`.
- `ProgressionChartModel.swift`: `label`, `spokenLabel`; every headline, selection and description
  template, each as one whole sentence per case (rise, fall, no change, single session, each with
  and without "about"; "1 session" and "\(count) sessions").
- `WeightFormatter.swift`: `estimate`'s "about \(number) \(abbreviation)"; `spoken`'s four
  unit-name forms as whole templates ("\(number) kilogram", "\(number) kilograms", …); `CountText`.
- `WeightUnit.swift`: `abbreviation` ("kg", "lb").
- `PersonalRecords.swift`: the three `label`s.
- `RecordCopy.swift`: every sentence ("\(new), up from \(previous)", "\(reps) at \(load)", the two
  announcement leads, "estimated", "about \(…)").
- `WorkoutSummary.swift`: `lengthText`'s "Length unknown"; `setsText` and `spokenSetsText` as four
  whole templates (bound × singular/plural).
- `SessionFlow.swift`: `unloggedTitle` (both), `discardTitle`, `discardMessage`.
- `RestPlan.swift`: "Off". `RestMetadata.swift`: both `setLabel` forms.
  `ExerciseLogState.swift`: "From another machine".
- `AccessibleText.swift` and `FirstRun.swift`: every literal.

Check, after converting: this lists what is left, and each remaining hit must be an id, a symbol
name, a key, a citation, a comment, or a test-only string:

```bash
rg -n '"[A-Za-z][^"]* [^"]*"' Packages/HardsetKit/Sources/HardsetCore \
  -g '!ExerciseCatalog.swift' -g '!CatalogEntry.swift' -g '!Localized.swift' \
  | rg -v 'localized\(|comment:|symbolName|citation:|///'
```

- [ ] **Step 4: Run to verify pass**

Run: `Tools/linux-test.sh`
Expected: PASS, with every existing copy test unchanged. A failing copy test means a literal's
English changed while it was wrapped: restore it.

Ledger, under `## Phase 3`:

```markdown
- [ ] (feat(core): Core's words through the catalog …) `./test.sh` passes on the Mac, where every
      Core copy test now runs through `String(localized:bundle: .module)` and must return the same
      English as on Linux. A failure that appears only on the Mac is a literal whose Apple and
      Linux forms differ: look first for an interpolated `Double`, or a `%` in a literal.
  - [ ] In the simulator, a muscle name, a record line, the chart headline and the methodology
        sheet read exactly as before.
```

- [ ] **Step 5: Commit**

```bash
git add Packages/HardsetKit/Sources/HardsetCore Packages/HardsetKit/Tests/HardsetCoreTests/LocalizedTests.swift \
  docs/MAC-VERIFICATION.md
git commit -m "feat(core): Core's words go through the catalog, and say the same in English

Every sentence Core produces now goes through the one localization seam, as a
whole sentence a translator can reorder, so a second language is a catalog
change rather than a code change. The English is byte-identical, which every
existing copy test proves on Linux and the Mac proves through the catalog.
Muscle names use the keys the taxonomy always promised, and the catalog carries
their English.

Co-Authored-By: <your model's trailer>"
```

---

### Task 12: Badges and the methodology sheet; the mirrors removed (Mac-only)

**Files:**
- Modify: `Packages/HardsetKit/Sources/HardsetUI/CertaintyBadge.swift` (rewrite `CertaintyBadge`;
  `AssumptionChip` and `UnevaluatedReadout` unchanged)
- Modify: `Packages/HardsetKit/Sources/HardsetUI/MethodologySheet.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetUI/DesignTokens.swift:46-58` and `:206-232`
- Modify: `Packages/HardsetKit/Sources/HardsetUI/ExercisePickerView.swift:144-184`
- Modify, mechanically: `HardsetUI/VolumeReportView.swift` lines 129, 158, 179 and
  `HardsetUI/WorkoutSummaryView.swift` line 148 (`ExercisePickerView.displayName(…)` →
  `.displayName`)
- Modify: `docs/MAC-VERIFICATION.md`

**Interfaces:**
- Consumes: `CertaintyMark`, `Certainty.mark` (Task 1); `EvidenceSource.summary`, `.doiURL`,
  `SetCounting.creditScheme()` (Task 2); `Muscle.displayName`, `MuscleKey.displayName` (Task 9).
- Produces, for Tasks 13–15 and 17:
  - `CertaintyBadge(_ certainty: Certainty, source: EvidenceSource, style: CertaintyBadge.Style = .full)`,
    `Style` being `.full` (glyph + word) or `.compact` (glyph + short word). Tapping opens
    `MethodologySheet(source:certainty:)` as a sheet.
  - `MethodologySheet(source:certainty:)`, signature unchanged, now with a Done button.
  - `Tokens.Color.certainty(_ certainty: Certainty)`. Call sites written `.certainty(.low)` compile
    unchanged, because `Certainty` has the same case names.
  - `CertaintyLevel` is **deleted** (spec 3.9). `ExercisePickerView.displayName(_:)` and its `copy`
    table are **deleted**.

**Read and cite first** (checked 2026-10-11):
- https://developer.apple.com/documentation/swiftui/link (iOS 14, macOS 11)
- https://developer.apple.com/documentation/swiftui/environmentvalues/dismiss (iOS 15, macOS 12)

Changes:

1. **`CertaintyBadge`** (replace the struct; keep the file's other two views):

   ```swift
   import HardsetCore
   import SwiftUI

   /// Shows how much the app trusts the number next to it, and where that number came from.
   ///
   /// A glyph and a word, never colour alone (spec 3.1). Both come from `CertaintyMark` in Core,
   /// where they are tested. Tapping opens the source, which is what App Review guideline 1.4.1 asks
   /// for, attached to the number rather than buried in settings.
   public struct CertaintyBadge: View {
     public enum Style: Sendable { case full, compact }

     private let mark: CertaintyMark
     private let source: EvidenceSource
     private let style: Style
     @State private var isShowingSource = false

     public init(_ certainty: Certainty, source: EvidenceSource, style: Style = .full) {
       self.mark = certainty.mark
       self.source = source
       self.style = style
     }

     public var body: some View {
       Button {
         isShowingSource = true
       } label: {
         HStack(spacing: Tokens.Spacing.tight) {
           Image(systemName: mark.symbolName)
           Text(style == .full ? mark.word : mark.shortWord)
         }
         .font(Tokens.Text.caption)
         .foregroundStyle(Tokens.Color.certainty(mark.certainty))
         .frame(minHeight: Tokens.minimumTapTarget)
         .contentShape(Rectangle())
       }
       .buttonStyle(.plain)
       .accessibilityLabel(mark.word)
       .accessibilityHint("Shows how this was calculated")
       .sheet(isPresented: $isShowingSource) {
         MethodologySheet(source: source, certainty: mark.certainty)
       }
     }
   }
   ```

   Add `import HardsetCore` at the top of the file (it had none: `CertaintyLevel` was local).

2. **`MethodologySheet`.** Keep the type's doc comment and init. Replace `body` and `section`:
   - Add `@Environment(\.dismiss) private var dismiss`.
   - Order: the certainty header (now `Image(systemName: certainty.mark.symbolName)` +
     `Text(certainty.mark.word)`, coloured `Tokens.Color.certainty(certainty)`); then
     `section("In short", summary)` when `source.summary` is non-nil, in `Tokens.Text.label`
     weight `.semibold`; then the credit picture when `source.id == SetCounting.source.id`; then
     `section("How it works", source.methodology)`; `section("Where it holds, and where it does
     not", validRange)`; `section("Source", citation, monospaced: true)` followed by
     `Link("Open the paper at doi.org", destination: url)` when `source.doiURL` is non-nil.
   - Toolbar: `ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }`.
   - Under `#if os(iOS)`, `.navigationBarTitleDisplayMode(.inline)`; the title stays
     `source.title` (spec ambiguity 7).
   - The credit picture:

     ```swift
     private var creditScheme: some View {
       VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
         ForEach(SetCounting.creditScheme()) { tier in
           VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
             HStack(alignment: .firstTextBaseline) {
               Text(tier.meaning).font(Tokens.Text.label)
               Spacer(minLength: Tokens.Spacing.snug)
               Text(tier.creditText)
                 .font(Tokens.Text.label.weight(.semibold))
                 .monospacedDigit()
             }
             // The bar is the picture; the number beside it is what VoiceOver reads.
             GeometryReader { proxy in
               ZStack(alignment: .leading) {
                 Capsule().fill(Tokens.Color.surface)
                 Capsule().fill(Tokens.Color.accent).frame(width: proxy.size.width * tier.credit)
               }
             }
             .frame(height: 8)
             .accessibilityHidden(true)
             Text(tier.basis)
               .font(Tokens.Text.caption)
               .foregroundStyle(Tokens.Color.textSecondary)
           }
           .accessibilityElement(children: .combine)
         }
       }
     }
     ```

   - Delete `level(for:)`, `label(for:)` and `symbol(for:)` (lines 68–80); nothing else calls them.
   - Previews: keep "Fractional counting" (`certainty: .moderate`) and "No target exists"
     (`certainty: .unevaluated`), and add "Epley" (`StrengthMath.epleySource`, `certainty: .high`).

3. **`DesignTokens`.** `certainty(_ level: CertaintyLevel)` becomes `certainty(_ certainty:
   Certainty)` with the same body (`case .high: certaintyHigh` …). Delete `CertaintyLevel`
   (lines 206–232) and its doc comment. Update the comment above `certainty(_:)`: the word and glyph
   are `CertaintyMark`'s, tested in Core.

4. **`ExercisePickerView`.** Delete `displayName(_:)` and `copy` (lines 158–175). `sectionTitle`,
   `supportingText` and `spokenLabel` use `key.displayName` /
   `entry.primaryMuscle.displayName` / `$0.key.displayName`.

5. **Mechanical callers.** `VolumeReportView`: `ExercisePickerView.displayName(MuscleKey(row.muscle))`
   → `row.muscle.displayName` (lines 129, 158) and `ExercisePickerView.displayName(MuscleKey(muscle))`
   → `muscle.displayName` (line 179). `WorkoutSummaryView` line 148:
   `ExercisePickerView.displayName(line.muscle)` → `line.muscle.displayName`.

Check:
- `rg -n 'CertaintyLevel|ExercisePickerView.displayName' Packages/HardsetKit/Sources` returns nothing.
- `rg -n 'exclamationmark.triangle' Packages/HardsetKit/Sources/HardsetUI` returns no certainty use.

Ledger, under `## Phase 3`:

```markdown
- [ ] (feat(ui): a badge says how sure, and opens where from …) HardsetUI and HardsetFeature build
      (iOS, and macOS 15 via `./test.sh`) with `CertaintyLevel` and
      `ExercisePickerView.displayName` gone. Then in the simulator:
  - [ ] Volume tab › "How sets are counted": the sheet opens with "In short" first, the three
        credit bars (1, 0.5, 0) with their basis lines, then "How it works". Done closes it.
  - [ ] The Source section shows "Open the paper at doi.org"; it opens
        https://doi.org/10.1007/s40279-025-02344-w (no trailing comma).
  - [ ] The title is inline and reads "Fractional set counting".
  - [ ] SF Symbols render (not blank): `circle.dashed`, `greaterthan.circle`,
        `clock.badge.questionmark`, `checkmark.seal`, `circle.lefthalf.filled`,
        `questionmark.circle`. If one is missing, choose another non-error glyph in the SF Symbols
        app and change it in `CertaintyMark.swift` (Core tests do not pin names).
  - [ ] Increase Contrast on: badge text darkens (light) or lightens (dark).
  - [ ] VoiceOver on a badge: "Moderate confidence. Shows how this was calculated", and double tap
        opens the sheet. The credit rows each read as one element.
  - [ ] Muscle names in the picker, the Volume tab and the summary are unchanged ("Quads", …).
```

Commit, citing the two URLs, with a message that says the mirror is gone because the words and
glyphs are now tested in Core, and the sheet leads with the plain summary.

---

### Task 13: Every volume figure carries its certainty, and is read in full (Mac-only)

**Files:**
- Modify: `Packages/HardsetKit/Sources/HardsetUI/VolumeReportView.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetUI/WorkoutSummaryView.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetUI/HistoryView.swift:100-171`
- Modify: `Packages/HardsetKit/Sources/HardsetFeature/WeeklyVolumeScreen.swift:55-60`
- Modify: `docs/MAC-VERIFICATION.md`

**Interfaces:**
- Consumes: `MuscleVolumeReport.certainty(for:)`, `MuscleLine.certainty`, `.countText(locale:)`,
  `PersonalRecord.estimateCertainty` (Task 3); `SessionVolumeText` (Task 5); `CaveatMark` (Task 1);
  `CertaintyBadge` (Task 12).
- Produces: `HistoryView.volumeText(_:unit:)` and `spokenLabel(_:unit:)` keep their signatures
  (now delegating to `SessionVolumeText`), so nothing else changes.

Changes:

1. **`VolumeReportView`, each trained row** (spec 3.1, "per-muscle certainty replaces the global
   header"):
   - Build the row's figure from Core:
     `let line = WorkoutSummary.MuscleLine(muscle: MuscleKey(row.muscle), fractionalSets: row.sets, isLowerBound: report.isLowerBound)`.
   - The count `Text` becomes `Text(line.countText())`. Delete `static func format(_:)`
     (lines 192–194), whose `String(format: "%.1f")` ignored the locale.
   - After the bar, replace the `counted, not modelled` caption with an `HStack` of the badge and
     that caption:

     ```swift
     HStack(spacing: Tokens.Spacing.snug) {
       if let certainty = report.certainty(for: row.muscle) {
         CertaintyBadge(certainty, source: SetCounting.source, style: .compact)
       }
       if row.muscle.tier == .counted {
         Text("counted, not modelled")
           .font(Tokens.Text.caption)
           .foregroundStyle(Tokens.Color.textSecondary)
       }
     }
     ```

   - The row's `.accessibilityElement(children: .combine)` stays, so the badge's action becomes the
     row's: double tap opens the source. Set its label to
     `"\(row.muscle.displayName), \(line.spokenSetsText())"`; the badge's word joins it.
   - The lower-bound note's icon: `Image(systemName: CaveatMark.lowerBound.symbolName)` instead of
     `exclamationmark.circle`.

2. **`WeeklyVolumeScreen`.** `MethodologySheet(source: SetCounting.source, certainty: nil)`, with the
   comment updated: certainty is per muscle now, on each row.

3. **`WorkoutSummaryView`.**
   - `musclesSection`: after `Text(line.setsText())`, add
     `CertaintyBadge(line.certainty, source: SetCounting.source, style: .compact)`. Change the row's
     `.accessibilityElement(children: .ignore)` to `.combine` and drop its explicit label, so the
     badge's word and action are read with the row; set
     `.accessibilityLabel("\(line.muscle.displayName), \(line.spokenSetsText())")` only if the
     combined reading comes out garbled on the Mac.
   - `recordsSection`: in the `VStack`, after the detail line, add
     `if let certainty = line.record.estimateCertainty { CertaintyBadge(certainty, source: StrengthMath.epleySource, style: .compact) }`.
     The row is `.ignore` with a custom label; append `", \(certainty.mark.word)"` to that label
     when there is a certainty, and add
     `.accessibilityAction(named: Text("How this estimate is calculated")) { … }` by lifting the
     badge's sheet into a `@State private var explainedRecord: WorkoutSummary.RecordLine?` with
     `.sheet(item:)` on the section, because an `.ignore` element does not expose a child button.
   - `whenSection`: the length-unknown icon becomes `CaveatMark.lengthUnknown.symbolName`.
   - The footer's `info.circle` becomes `CaveatMark.lowerBound.symbolName`.
   - `totalsSection`: no change (totals are measured).

4. **`HistoryView`.** `volumeText` returns `SessionVolumeText.written(volume, formatter:
   WeightFormatter(unit: unit))`. `spokenLabel` uses `SessionVolumeText.spoken(…)` in place of
   `volumeText`, so a total is "9400 kilograms", never "kg". The length-unknown `Label` icon becomes
   `CaveatMark.lengthUnknown.symbolName`.

Check: `rg -n 'String\(format' Packages/HardsetKit/Sources/HardsetUI` returns nothing.

Ledger, under `## Phase 3`:

```markdown
- [ ] (feat(ui): every volume figure says how sure it is …) HardsetUI and HardsetFeature build. In
      the simulator:
  - [ ] Volume tab: each muscle row has a compact badge. Chest, quads and the other modelled sites
        read "Moderate"; forearms, abs and other counted muscles read "Low" beside "counted, not
        modelled". A muscle over 25 sets reads "Low".
  - [ ] "How sets are counted" opens the sheet with no certainty line at the top.
  - [ ] Tapping a row's badge opens the sheet with that row's certainty.
  - [ ] With a custom (unattributed) movement logged: counts read "≥ 12", the note's glyph is the
        grey ">" circle, not an exclamation mark, and VoiceOver reads "at least 12 sets".
  - [ ] Settings › General › Language & Region › German (or region Germany): a fractional count
        reads "6,5", not "6.5".
  - [ ] Summary sheet: each muscle line has its badge; an estimated-1RM record shows its
        certainty, and VoiceOver offers "How this estimate is calculated".
  - [ ] History, VoiceOver: a row reads "… 9400 kilograms …", never "kg"; pounds mode reads
        "pounds". Rows are not dimmed.
```

Commit, with a message that says the one global "Moderate" overstated most muscles, and every
figure now carries its own.

---

### Task 14: The chart, crafted (Mac-only)

**Files:**
- Modify: `Packages/HardsetKit/Sources/HardsetUI/ProgressionChartView.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetFeature/ExerciseProgressScreen.swift:44-76`
- Modify: `docs/MAC-VERIFICATION.md`

**Interfaces:**
- Consumes: `ProgressionMetric`, `ProgressionChartSeries`, `ProgressionHeadline`,
  `ProgressionSelection`, `ProgressionChartDescription`, `ProgressionHistory.chartSeries()`
  (Task 4); `CertaintyBadge` (Task 12); `UnevaluatedReadout` (existing).
- Produces: `ProgressionChartView(series:machineChanges:unit:exerciseName:onExplain:)`, the new
  `exerciseName: String = ""` placed before `onExplain`, used for VoiceOver's chart title. Existing
  callers compile unchanged.

**Read and cite first** (checked 2026-10-11):
- https://developer.apple.com/documentation/swiftui/view/chartxselection(value:) (iOS 17, macOS 14)
- https://developer.apple.com/documentation/charts/chartcontent/symbol(by:) (iOS 16, macOS 13)
- https://developer.apple.com/documentation/charts/chartcontent/linestyle(_:) (iOS 16, macOS 13)
- https://developer.apple.com/documentation/swiftui/view/accessibilitychartdescriptor(_:) (iOS 15, macOS 12)
- https://developer.apple.com/documentation/swiftui/axchartdescriptorrepresentable (iOS 15, macOS 12)
- https://developer.apple.com/documentation/accessibility/axchartdescriptor/init(title:summary:xaxis:yaxis:additionalaxes:series:)
- https://developer.apple.com/documentation/accessibility/axnumericdataaxisdescriptor/init(title:range:gridlinepositions:valuedescriptionprovider:)
- https://developer.apple.com/documentation/accessibility/axdataseriesdescriptor/init(name:iscontinuous:datapoints:)
- https://developer.apple.com/documentation/accessibility/axdatapoint (the `init(x: Double, y:
  Double?, additionalValues:label:)` overload)

Changes:

1. **Headline** (spec 3.3). Above the picker, when not empty:

   ```swift
   if let headline = ProgressionHeadline.current(in: series, metric: metric, formatter: formatter) {
     HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.snug) {
       Text(headline.text)
         .font(Tokens.Text.label.weight(.semibold))
         .accessibilityLabel(headline.spoken)
       if let certainty = headline.certainty {
         CertaintyBadge(certainty, source: StrengthMath.epleySource, style: .compact)
       }
     }
   }
   ```

   with `private var formatter: WeightFormatter { WeightFormatter(unit: unit) }`.

2. **Marks.** In `chart`, per series:
   - `LineMark(…)` keeps `.foregroundStyle(by:)` and gains
     `.symbol(by: .value("Machine", input.label))` and
     `.lineStyle(StrokeStyle(lineWidth: 2, dash: metric.isEstimate ? [5, 3] : []))`: each machine has
     its own shape as well as its own colour, and an estimate is dashed.
   - `PointMark(…)` gains the same `.symbol(by:)`.
   - Use `metric.displayValue(of: point, unit: unit)` for `y`, and `plottable` becomes
     `input.points.filter { metric.kilograms(of: $0) != nil }`. Delete the private `value(_:)`.
   - `series:` stays `.value("Machine", input.label)`. Labels are unique (Task 4), so lines never
     merge.

3. **Scrubbing.** Add `@State private var selectedDate: Date?` and, on the `Chart`,
   `.chartXSelection(value: $selectedDate)`. Inside the `Chart` builder, after the machine-change
   rules:

   ```swift
   if let selectedDate,
     let selection = ProgressionSelection.nearest(
       to: selectedDate, in: series, metric: metric, formatter: formatter)
   {
     RuleMark(x: .value("Selected", selection.point.date))
       .foregroundStyle(Tokens.Color.textSecondary)
       .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
         Text(selection.text)
           .font(Tokens.Text.caption.weight(.semibold))
           .padding(Tokens.Spacing.tight)
           .background(Tokens.Color.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.control))
       }
   }
   ```

   Check `annotation(position:overflowResolution:content:)` against
   https://developer.apple.com/documentation/charts/chartcontent/annotation(position:alignment:spacing:overflowresolution:content:)
   before using it; if it is unavailable at iOS 17 / macOS 14, drop `overflowResolution:`.

4. **No estimate.** Replace the caveat `Text("No estimate is available…")` with
   `UnevaluatedReadout(explanation: "A one-rep max is only estimated from sets of twelve reps or fewer, and none of these sessions qualify.")`.

5. **VoiceOver's audio graph.** Add, in this file:

   ```swift
   import Accessibility

   /// The chart as VoiceOver's audio graph hears it. Every value comes from Core's description;
   /// this only converts types.
   private struct ProgressionAudioGraph: AXChartDescriptorRepresentable {
     let description: ProgressionChartDescription

     func makeChartDescriptor() -> AXChartDescriptor {
       let dates = description.dateRange
       let xAxis = AXNumericDataAxisDescriptor(
         title: "Date",
         range: dates.lowerBound.timeIntervalSince1970...dates.upperBound.timeIntervalSince1970,
         gridlinePositions: []
       ) { Date(timeIntervalSince1970: $0).formatted(date: .abbreviated, time: .omitted) }
       let yAxis = AXNumericDataAxisDescriptor(
         title: description.valueAxisTitle, range: description.valueRange, gridlinePositions: []
       ) { [description] in description.spokenValue($0) }
       return AXChartDescriptor(
         title: description.title,
         summary: description.summary,
         xAxis: xAxis,
         yAxis: yAxis,
         additionalAxes: [],
         series: description.series.map { line in
           AXDataSeriesDescriptor(
             name: line.name, isContinuous: true,
             dataPoints: line.points.map {
               AXDataPoint(x: $0.date.timeIntervalSince1970, y: $0.value, label: $0.spokenValue)
             })
         })
     }
   }
   ```

   `ProgressionChartDescription.make` returns nil only when nothing is plotted, and then no chart
   is drawn, so the descriptor is attached through a small modifier rather than an invented empty
   description:

   ```swift
   private struct AudioGraph: ViewModifier {
     let description: ProgressionChartDescription?

     func body(content: Content) -> some View {
       if let description {
         content.accessibilityChartDescriptor(ProgressionAudioGraph(description: description))
       } else {
         content
       }
     }
   }
   ```

   and on the `Chart`, after `.frame(height: 220)`:

   ```swift
   .modifier(
     AudioGraph(
       description: ProgressionChartDescription.make(
         exerciseName: exerciseName, series: series, metric: metric, formatter: formatter)))
   ```

6. **`ExerciseProgressScreen`.** Delete `seriesInputs` (lines 64–76) and pass
   `series: history?.chartSeries() ?? []` and `exerciseName: exerciseName`. The sort and the labels
   now come from Store (Task 4), so the legend, the headline and VoiceOver agree on which machine is
   current.

Ledger, under `## Phase 3`:

```markdown
- [ ] (feat(ui): the chart says what changed …) HardsetUI and HardsetFeature build (iOS, and macOS
      15 via `./test.sh`). With two machines for one movement, in the simulator:
  - [ ] Over the chart: "Cybex Leg Press: +5 kg over 2 sessions" for the machine used last, never a
        delta across machines. In pounds the number is the difference of the two displayed loads.
  - [ ] Each machine has its own colour and its own point shape (circle, square, …); with colour
        filters on (Settings › Accessibility › Display › Color Filters › Grayscale) the lines are
        still told apart.
  - [ ] Est. 1RM: lines are dashed, the headline says "about" and carries a badge.
  - [ ] Drag across the chart: a rule and a label follow the nearest logged session, named by its
        machine.
  - [ ] A movement done only with 15-rep sets: Est. 1RM shows "Not evaluated" and the reason.
  - [ ] VoiceOver: focus the chart, swipe up to "Chart details" / "Play audio graph". The title is
        "<movement>, heaviest load", there is one series per machine, and values read "102.5
        kilograms".
  - [ ] Written without a compiler. If it fails, look first at the `.symbol(by:)` and
        `.lineStyle` modifiers on `LineMark`, `chartXSelection(value:)` with a `Date?` binding,
        the `RuleMark` inside an `if let` in the chart builder, and the `[description]` capture
        list.
```

Commit, citing the URLs above.

---

### Task 15: The logger with VoiceOver and large text (Mac-only)

**Precondition:** Phase 2 Task 14 is merged. This task edits the files it rewrote and assumes its
`SetRowView(records:recordPulse:isEditingSaved:onEdit:onDelete:)`, the record caption under the
row's values, and `SessionView`'s `.onChange(of: feedback)` record announcement.

**Files:**
- Modify: `Packages/HardsetKit/Sources/HardsetUI/SetRowView.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetUI/NumericPad.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetUI/ExerciseSectionView.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetUI/SessionView.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetUI/RestBarView.swift`
- Modify: `docs/MAC-VERIFICATION.md`

**Interfaces:**
- Consumes: `SetRowSpeech`, `SetEntryKeypad.spokenValue(locale:)`, `.spokenStep(_:locale:)`,
  `NumericEntryBuffer.displayText(locale:)` (Task 5); `CertaintyMark`, `CaveatMark`,
  `Assumption.borrowedFromOtherMachine` (Task 1); `PersonalRecord.estimateCertainty` (Task 3);
  `MethodologySheet` (Task 12); `AssumptionChip` (existing).
- Produces: no public signature changes.

**Read and cite first** (checked 2026-10-11):
- https://developer.apple.com/documentation/swiftui/view/accessibilityaction(_:_:) (iOS 13, macOS 10.15)
- https://developer.apple.com/documentation/swiftui/view/accessibilityaddtraits(_:) (iOS 14, macOS 11)
- https://developer.apple.com/documentation/swiftui/view/accessibilityhidden(_:) (iOS 14, macOS 11)
- https://developer.apple.com/documentation/swiftui/view/accessibilityactions(_:) (iOS 16, macOS 13)
- https://developer.apple.com/documentation/accessibility/accessibilitynotification/announcement (iOS 17, macOS 14)
- https://developer.apple.com/documentation/swiftui/environmentvalues/dynamictypesize (iOS 15, macOS 12)
  and https://developer.apple.com/documentation/swiftui/dynamictypesize/isaccessibilitysize
- https://developer.apple.com/documentation/swiftui/scaledmetric (iOS 14, macOS 11)

Changes:

1. **`SetRowView`: the default action logs, with value and traits** (spec 3.4).
   - Replace `spokenLabel` with Core's sentences:

     ```swift
     .accessibilityElement(children: .combine)
     .accessibilityLabel(SetRowSpeech.label(number: ordinal + 1, isWarmup: isWarmup))
     .accessibilityValue(spokenValue)
     .accessibilityHint(SetRowSpeech.hint(isLoggable: draft.isLoggable, isLogged: isLogged) ?? "")
     .accessibilityAddTraits(isLogged ? .isSelected : .isButton)
     // The default action: a double tap anywhere on the row logs what the row shows, through the
     // same `onLog` as the check mark. Nothing is logged that the lifter cannot see.
     .accessibilityAction {
       if !isLogged && draft.isLoggable { onLog() }
     }
     ```

     where `spokenValue` joins, with ", ": `SetRowSpeech.value(weightKg: draft.weightKg, reps:
     draft.reps, isLogged: isLogged, formatter: formatter)`, `SetRowSpeech.previous(previous,
     formatter: formatter)`, `priorNote`, and Task 14's `"record: …"` text. Keep the existing named
     "Log set", "Edit weight" and "Edit reps" actions and Task 14's Edit and Delete actions.
   - The focused value uses `keypad.weight.displayText(locale: .current)`; delete the private
     `decimalSeparator` and its `replacingOccurrences`.
   - **An estimated record's certainty.** Beside Task 14's record caption, when
     `let certainty = records.compactMap(\.estimateCertainty).min()`, show
     `Image(systemName: certainty.mark.symbolName)` and `Text(certainty.mark.shortWord)` in
     `Tokens.Text.caption`, `Tokens.Color.certainty(certainty)`, not a button (the row's taps
     belong to logging). Append `certainty.mark.word` to `spokenValue`, and add a named action
     `Button("How this estimate is calculated") { isExplainingEstimate = true }` with
     `.sheet(isPresented: $isExplainingEstimate) { MethodologySheet(source: StrengthMath.epleySource, certainty: certainty) }`.
   - **Accessibility text sizes.** Add `@Environment(\.dynamicTypeSize) private var typeSize`,
     `@ScaledMetric(relativeTo: .subheadline) private var ordinalWidth: CGFloat = 28` and
     `@ScaledMetric(relativeTo: .caption) private var lastTimeWidth: CGFloat = 78`, and use them in
     place of the literals 28 and 78. When `typeSize.isAccessibilitySize`, stack the row:

     ```swift
     if typeSize.isAccessibilitySize {
       VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
         HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.regular) {
           ordinalBadge
           lastTimeColumn
         }
         HStack(spacing: Tokens.Spacing.regular) {
           valueField(.weight, …)
           valueField(.reps, …)
           logButton
         }
       }
     } else {
       // the existing HStack, unchanged
     }
     ```

     Extract the "Last time" `VStack` into `private var lastTimeColumn: some View` so both layouts
     use it. Every control keeps at least `Tokens.minimumTapTarget`.

2. **`NumericPad`.**
   - The inert decimal key on reps: add `.accessibilityHidden(key == .disabledDecimal)` beside its
     `.opacity(0)`, so VoiceOver no longer lands on an invisible "Decimal point".
   - The header readout: `.accessibilityLabel(keypad.spokenValue())`, and post it as the value
     changes:

     ```swift
     .onChange(of: keypad.focused.text) {
       AccessibilityNotification.Announcement(keypad.spokenValue()).post()
     }
     ```

   - The step keys' labels become `keypad.spokenStep(.up)` / `keypad.spokenStep(.down)`, replacing
     the inline strings Phase 2 Task 13 wrote.

3. **`ExerciseSectionView`: the borrowed loads are an assumption with its correction.** Replace the
   `Label(note, systemImage: "arrow.triangle.branch")` block (around line 116) with:

   ```swift
   if state.priorNote != nil {
     let assumption = Assumption.borrowedFromOtherMachine
     if let onSelectMachine {
       AssumptionChip(
         label: assumption.label, correctionPrompt: assumption.correctionPrompt,
         onCorrect: onSelectMachine)
     } else {
       Label(assumption.label, systemImage: CaveatMark.otherMachine.symbolName)
         .font(Tokens.Text.caption)
         .foregroundStyle(Tokens.Color.caveat)
     }
   }
   ```

4. **`SessionView`: VoiceOver hears every log, once** (spec 3.4). Replace Task 14's
   record-only `.onChange(of: feedback)` handler with one that speaks logs and records together:

   ```swift
   .onChange(of: feedback) { _, pulse in
     guard let pulse, pulse.event == .log || pulse.event == .record, let slotID = pulse.slotID,
       let exercise = exercises.first(where: { $0.slots.contains { $0.id == slotID } }),
       let index = exercise.slots.firstIndex(where: { $0.id == slotID }),
       let resolved = exercise.slots[index].draft.resolved()
     else { return }
     let slot = exercise.slots[index]
     let number = exercise.slots[..<index].count { !$0.isWarmup } + 1
     AccessibilityNotification.Announcement(
       SetRowSpeech.logAnnouncement(
         number: number, isWarmup: slot.isWarmup, weightKg: resolved.weightKg,
         reps: resolved.reps, exerciseName: exercise.exerciseName,
         records: recordsBySlot[slotID] ?? [], formatter: WeightFormatter(unit: unit))
     ).post()
   }
   ```

   The number is the same working-set count `ExerciseSectionView.ordinal(of:)` shows.
   `SetEntryDraft.resolved()` returns `(weightKg: Double, reps: Int)?`, the value
   `LoggerStore.logSet` wrote, so the announcement states what was saved.

5. **`RestBarView`: rest controls are reachable when the accessory is collapsed.** In `.inline`
   placement −15, +15 and skip are not drawn, so VoiceOver could not reach them. On `readout`,
   when `isInline`:

   ```swift
   .accessibilityActions {
     if isInline {
       Button("Subtract 15 seconds") { adjustCount += 1; onAdjust(.seconds(-15)) }
       Button("Add 15 seconds") { adjustCount += 1; onAdjust(.seconds(15)) }
       Button("Skip rest", action: onSkip)
     }
   }
   ```

Check: `rg -n '"kg"|"lb"|abbreviation' Packages/HardsetKit/Sources/HardsetUI/SetRowView.swift Packages/HardsetKit/Sources/HardsetUI/NumericPad.swift`
shows no use inside an accessibility label.

Ledger, under `## Phase 3`:

```markdown
- [ ] (feat(ui): the logger with VoiceOver and large text …) HardsetUI builds (iOS, and macOS 15).
      In the simulator, VoiceOver on:
  - [ ] A prefilled row reads "Set 2, 100 kilograms, 8 reps, Last time …, button. Double tap to
        log this set." Double tap logs it, and VoiceOver then says "Set 2 logged, 100 kilograms, 8
        reps." once. A record set says the log and the record in one announcement.
  - [ ] A logged row reads "…, logged, selected" with no hint; double tap does nothing.
  - [ ] A half-typed row reads "60 kilograms, reps not entered".
  - [ ] On the reps pad, swiping never lands on an invisible decimal key. Typing on the weight pad
        speaks "Weight, 62.5 kilograms"; the step keys say "Add 2.5 kilograms" / "One more rep".
  - [ ] Scroll so the tab bar collapses during a rest: the accessory's countdown offers the
        actions "Subtract 15 seconds", "Add 15 seconds", "Skip rest".
  - [ ] Pounds mode: every weight is spoken "pounds".
  - [ ] Settings › Accessibility › Display & Text Size › Larger Text, the largest size: set rows
        stack (number and "Last time" above, fields and check below), nothing truncates the weight,
        and every control is at least 44 pt (Accessibility Inspector).
  - [ ] An estimated-1RM record on a row shows its certainty glyph and word, and the action "How
        this estimate is calculated" opens the Epley sheet.
  - [ ] Loads borrowed from another machine show the "From another machine" chip; tapping it opens
        the machine picker.
  - [ ] Written without a compiler. If it fails, look first at `.accessibilityAction { }` (the
        default-action overload), `.accessibilityAddTraits` with a ternary of `AccessibilityTraits`,
        `@ScaledMetric(relativeTo:)`, and the `if`-inside `.accessibilityActions { }` builder.
```

Commit, citing the URLs above.

---

### Task 16: Split the root (Mac-only)

**Precondition:** Phase 2 Task 19 is merged (so Task 18 is too). This task moves code it wrote.

**Files:**
- Modify: `Packages/HardsetKit/Sources/HardsetFeature/HardsetRootView.swift`
- Create: `Packages/HardsetKit/Sources/HardsetFeature/HardsetEnvironment.swift`
- Create: `Packages/HardsetKit/Sources/HardsetFeature/StartWorkoutView.swift`
- Create: `Packages/HardsetKit/Sources/HardsetFeature/GymPickerSheet.swift`
- Create: `Packages/HardsetKit/Sources/HardsetFeature/LiveSessionAccessory.swift`
- Modify: `docs/MAC-VERIFICATION.md`

**Interfaces:**
- Consumes: the post-Phase-2 `HardsetRootView` (tab selection, the `RestBarView` accessory, the
  glass Start, the summary sheet, Repeat).
- Produces, for Tasks 17–19 (all `internal` to HardsetFeature except `HardsetEnvironment`, which
  stays `public` with its init unchanged):
  - `HardsetEnvironment.swift`: the `HardsetEnvironment` struct, moved verbatim
  - `struct StartWorkoutView: View`: inputs `gymName: String?`, `startFailed: Bool`,
    `onChooseGym: () -> Void`, `onStart: () -> Void`; it draws the empty state, the gym row, the
    glass Start (with its `#available` guard) and the failure line, exactly as before
  - `struct GymPickerSheet: View`: inputs `gyms: [GymRecord]`, `selected: Binding<GymID?>`,
    `error: String?`, `onAddGym: (String) -> Void`, `onDone: () -> Void`; it contains the add-gym
    `NameEntrySheet` attached inside, as before (two sheets on one anchor never present)
  - `struct LiveSessionAccessory: View`: the accessory content (the `RestBarView` while resting,
    otherwise the logged-set count), with the inputs it reads today passed in
  - `HardsetRootView` keeps all `@State` and all store calls (`resumeOpenWorkout`,
    `prepareCatalogue`, `refreshGyms`, `addGym`, `startEmptyWorkout`, the summary and Repeat
    handling) and only composes the three views.

Changes (spec 3.9): a pure move. No copy, layout, modifier order or behaviour changes. Each
moved view keeps its doc comments; each `#if os(iOS)` guard moves with the code it guards. Where a
moved view read root `@State`, pass a value or a `Binding`; where it called a root method, pass a
closure.

Check:
- `wc -l Packages/HardsetKit/Sources/HardsetFeature/HardsetRootView.swift` is well under its
  previous length, and every new file is under 200 lines.
- `git diff --stat` shows no change outside `HardsetFeature/` and the ledger.

Ledger, under `## Phase 3`:

```markdown
- [ ] (refactor(feature): the root composes three views instead of drawing them) HardsetFeature
      and the app build (iOS, and macOS 15 via `./test.sh`); `AppSmokeTests` passes. In the
      simulator, nothing looks or behaves differently: start screen, gym row and sheet (including
      "Add a gym" inside it), glass Start, the accessory during a workout and a rest, Finish →
      summary, Repeat from history.
```

Commit with a message that says the root had grown to hold four screens' worth of drawing and is
now only composition and state.

---

### Task 17: A past workout, opened from history (Mac-only)

**Files:**
- Create: `Packages/HardsetKit/Sources/HardsetUI/SessionDetailView.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetFeature/HistoryScreen.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetFeature/HardsetEnvironment.swift` (one store)
- Modify, mechanically: the `HistoryScreen(` call in `HardsetFeature/HardsetRootView.swift`
- Modify: `docs/MAC-VERIFICATION.md`

**Interfaces:**
- Consumes: `SessionDetail`, `SessionDetailStore` (Task 8); `SessionVolumeText`, `SetRowSpeech`
  (Task 5); `CertaintyBadge` (Task 12); `RecordCopy`, `WeightFormatter`, `CaveatMark`;
  `ExerciseProgressScreen` (Task 14); `FailureCopy.Action.loadHistory`.
- Produces:
  - `public struct SessionDetailView: View` with
    `init(detail: SessionDetail, unit: WeightUnit, onShowProgress: ((ExerciseID, String) -> Void)? = nil)`
  - `HardsetEnvironment.sessionDetails: SessionDetailStore`
  - `HistoryScreen(store:details:progression:unit:onRepeat:)`, the two new parameters after
    `store`, non-optional

**Read and cite first** (checked 2026-10-11):
- https://developer.apple.com/documentation/swiftui/view/navigationdestination(item:destination:)
  (iOS 17, macOS 14)

Changes:

1. **`SessionDetailView`** (HardsetUI, no storage). A `List`:
   - **When:** the date (as `WorkoutSummaryView.whenSection` draws it) and `detail.summary.lengthText`;
     when `detail.summary.length == nil`, a `Label` with `CaveatMark.lengthUnknown.symbolName` in
     `Tokens.Color.caveat` (spec 3.6, "honest duration").
   - **Totals:** `Text(SessionVolumeText.written(detail.summary.volume, formatter: formatter))`,
     `.accessibilityLabel(SessionVolumeText.spoken(…))`.
   - **One `Section` per `detail.blocks`**, headed by the movement and, when present, the machine
     ("Leg Press · Hammer Strength Leg Press"). When `onShowProgress` is non-nil the header is a
     `Button` with the `chart.xyaxis.line` glyph and the label "<name>. Show load history." that
     calls `onShowProgress(block.exerciseID, block.exerciseName)` (spec 3.6, "exercise progress is
     reachable outside a live workout").
   - **Each set:** "W" or the working-set number, `formatter.load(kilograms:)` × reps, and for each
     record a `trophy` glyph in `Tokens.Color.record` with `RecordCopy.line(for:formatter:)`; an
     estimated-1RM record also shows `CertaintyBadge(certainty, source: StrengthMath.epleySource,
     style: .compact)`. Each set row is one element:
     `.accessibilityLabel(SetRowSpeech.label(number:isWarmup:))`,
     `.accessibilityValue(SetRowSpeech.value(weightKg:reps:isLogged: true, formatter:))` plus the
     record lines.
   - No comparison with a plan, no target, no streak.
   - A `#Preview` with two blocks for one movement on two machines, a warm-up and a record.

2. **`HistoryScreen`.**
   - Add `@State private var openedSession: SessionID?`, `@State private var detail: SessionDetail?`,
     `@State private var detailError: String?` and
     `@State private var progressTarget: ProgressTarget?`, where
     `private struct ProgressTarget: Hashable { let id: ExerciseID; let name: String }`.
   - Pass `onSelect: { openedSession = $0.id }` to `HistoryView` (rows become buttons, which also
     keeps them undimmed).
   - `.navigationDestination(item: $openedSession) { id in detailScreen(id) }`, where
     `detailScreen` shows `SessionDetailView(detail:unit:onShowProgress:)` once loaded, a
     `ProgressView` while loading, and on failure a `ContentUnavailableView` with
     `FailureCopy.message(for: error, during: .loadHistory)` and a "Try again" button. Load in
     `.task(id: id)` with `detail = try details.detail(for: id)`; reads happen in the task, never in
     a body (`HANDOFF.md` §5.3).
   - Inside the detail destination, `.navigationDestination(item: $progressTarget) { target in
     ExerciseProgressScreen(store: progression, exerciseID: target.id, exerciseName: target.name, unit: unit) }`.

3. **`HardsetEnvironment`.** Add `public let sessionDetails: SessionDetailStore`, set in `init` as
   `SessionDetailStore(database: database)`.

4. **Mechanical.** In `HardsetRootView`, the `HistoryScreen(store: environment.history, …)` call
   gains `details: environment.sessionDetails, progression: environment.progression`.

Ledger, under `## Phase 3`:

```markdown
- [ ] (feat(ui): a past workout opens from history …) HardsetUI and HardsetFeature build. In the
      simulator:
  - [ ] Tap a History row: the session opens, with its date and length ("Length unknown", grey with
        its glyph, for one left open overnight), its totals, and one section per movement and
        machine. A leg press done on two machines shows two sections.
  - [ ] Records sit on the sets that earned them; an estimated 1RM shows its badge.
  - [ ] Tap a section's header: that movement's load history opens, outside any workout.
  - [ ] Back returns to History with its scroll position; Repeat (context menu) still works.
  - [ ] VoiceOver: a History row is a button, not dimmed; a set reads "Set 2, 100 kilograms, 8
        reps, logged".
```

Commit, citing the URL above.

---

### Task 18: The first-run screen (Mac-only)

**Files:**
- Create: `Packages/HardsetKit/Sources/HardsetUI/FirstRunView.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetFeature/HardsetRootView.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetFeature/HardsetEnvironment.swift`
- Modify: `docs/MAC-VERIFICATION.md`

**Interfaces:**
- Consumes: `FirstRunCopy`, `FirstRunPromise`, `WeightUnit.inferred(from:)`, `FirstRunStore`,
  `FirstRunFlag`, `UserDefaultsFirstRunFlag` (Task 7); `Assumption.unitFromRegion(_:)` (Task 1);
  `AssumptionChip`; `FailureCopy.Action.saveGym`.
- Produces:
  - `public struct FirstRunView: View` with
    `init(useImperial: Binding<Bool>, inferredUnit: WeightUnit, gymName: Binding<String>, errorMessage: String?, onStart: @escaping () -> Void)`
  - `HardsetEnvironment.init(database: any DatabaseWriter, firstRunFlag: any FirstRunFlag = UserDefaultsFirstRunFlag())`
    and `public let firstRun: FirstRunStore`. The default is the real flag, so `HardsetApp.swift`'s
    `HardsetEnvironment(database:)` call is unchanged and the app persists the flag. (The rest
    preference's in-memory default once made the app forget every choice until the app passed the
    real store; this avoids that trap.)

Changes (spec 3.5):

1. **`FirstRunView`.** One `ScrollView`, centred, no navigation:
   - the three `FirstRunCopy.promises`, each an `HStack` of `Image(systemName: promise.symbolName)`
     (`.font(.title2)`, `Tokens.Color.accent`, `.accessibilityHidden(true)`) and a `VStack` of
     `title` (`Tokens.Text.label.weight(.semibold)`) and `detail` (`Tokens.Text.label`,
     `Tokens.Color.textSecondary`), combined for VoiceOver;
   - the unit: a segmented `Picker("Weight", selection: $useImperial)` with
     `WeightUnit.kilograms.abbreviation` / `.pounds.abbreviation` tags `false` / `true`, and above
     it, while `useImperial == (inferredUnit == .pounds)`, the guess stated as an
     `AssumptionChip(label: Assumption.unitFromRegion(inferredUnit).label, correctionPrompt: …,
     onCorrect: { useImperial.toggle() })`;
   - the gym: `TextField(FirstRunCopy.gymFieldPrompt, text: $gymName)` with
     `.textContentType(.organizationName)` under `#if os(iOS)`, and `FirstRunCopy.gymFootnote` as a
     caption;
   - `FirstRunCopy.privacy` in `Tokens.Text.caption`, `Tokens.Color.textSecondary`, with a
     `lock` glyph;
   - `errorMessage`, when non-nil, in `Tokens.Color.critical` with an `exclamationmark.circle`
     glyph (an error is an error);
   - the Start button, styled exactly as the post-Phase-2 glass Start (copy its
     `if #available(iOS 26.0, macOS 26.0, *) { .buttonStyle(.glassProminent) } else { … }` guard),
     labelled `FirstRunCopy.start`, calling `onStart`.
   - No questionnaire, no goal, no program, no page dots: one screen.
   - Previews: kilograms region, pounds region, and with an error.

2. **`HardsetEnvironment`.** Add the `firstRunFlag` init parameter and
   `self.firstRun = FirstRunStore(database: database, flag: firstRunFlag)`.

3. **`HardsetRootView`.**
   - `@State private var showsFirstRun = false`, `@State private var firstRunGymName = ""`,
     `@State private var firstRunError: String?`.
   - The `useImperial` `@AppStorage` default becomes
     `WeightUnit.inferred(from: .current) == .pounds` (same result, one rule).
   - In `.task`, after `resumeOpenWorkout()`:

     ```swift
     // Only when no workout is open and none failed to reopen: a workout left open is offered
     // first, and a database that cannot be read is reported by the resume path, not hidden
     // behind a welcome.
     if coordinator == nil && resumeError == nil {
       do {
         showsFirstRun = try environment.firstRun.shouldShow()
       } catch {
         showsFirstRun = false
       }
     }
     ```

   - `body`: `if showsFirstRun { FirstRunView(…) } else { tabs }`, keeping `.task` on the outer
     view. (`fullScreenCover` is iOS-only; this needs no guard.)
   - `onStart`:

     ```swift
     do {
       // Writing the shown unit keeps it, even if the region later changes.
       useImperial = useImperial
       let gym = try environment.firstRun.complete(gymName: firstRunGymName)
       refreshGyms()
       if let gym { selectedGym = gym }
       firstRunError = nil
       showsFirstRun = false
     } catch {
       firstRunError = FailureCopy.message(for: error, during: .saveGym)
     }
     ```

   - Alarm permission is not requested here: it stays at the first rest (Phase 1, spec 1.3).

Ledger, under `## Phase 3`:

```markdown
- [ ] (feat(ui): one honest first screen …) HardsetUI and HardsetFeature build; `AppSmokeTests`
      passes. In the simulator:
  - [ ] Erase the simulator, install, launch: one screen with three promises, the unit, an
        optional gym field, "No account. Your data stays on your devices and in your iCloud.", and
        Start. Nothing asks for a goal, a target, a program or experience.
  - [ ] Region United States: the unit reads lb with the chip "Weights in pounds, from your
        region"; tapping the chip switches to kg and the chip disappears. Region UK: kg.
  - [ ] Start with the gym field empty: the Train tab, no gym selected. Relaunch: the first screen
        does not return.
  - [ ] Erase, type "  Iron   Temple ", Start: the start screen's gym row reads "Iron Temple".
  - [ ] Install over a build that has history (or log a workout, then delete the
        `hardset.firstRunComplete` default): the first screen never appears.
  - [ ] Leave a workout open, delete the default, relaunch: the workout is offered back; no first
        screen.
  - [ ] No alarm permission prompt appears until the first rest.
  - [ ] VoiceOver reads each promise as one element, then the unit, the chip, the field, the
        privacy line and Start. Largest text size: everything scrolls, nothing truncates.
```

Commit, with a message that says a new lifter is told three promises and the privacy line and asked
for nothing, and an existing lifter never sees it.

---

### Task 19: Gyms and machines, renamed and archived (Mac-only)

**Files:**
- Create: `Packages/HardsetKit/Sources/HardsetFeature/GymsScreen.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetFeature/SettingsSheet.swift`
- Modify, mechanically: the `SettingsSheet(` call and its `.sheet` in
  `HardsetFeature/HardsetRootView.swift`
- Modify: `docs/MAC-VERIFICATION.md`

**Interfaces:**
- Consumes: `GymStore.gyms()`, `machines(at:)`, `renameGym(_:to:)`, `renameMachine(_:name:brand:)`,
  `archiveGym(_:)`, `archiveMachine(_:)`, `GymStoreError` and the `FailureCopy` actions
  `.renameGym`, `.archiveGym`, `.renameMachine`, `.archiveMachine` (Task 6); `NameEntrySheet`.
- Produces:
  - `struct GymsScreen: View` (internal) with `init(store: GymStore)`
  - `SettingsSheet(useImperial:gyms:onDone:)`, `gyms: GymStore? = nil` before `onDone`; nil hides
    the row, so the preview compiles unchanged.

**Read and cite first** (checked 2026-10-11):
- https://developer.apple.com/documentation/swiftui/view/swipeactions(edge:allowsfullswipe:content:)
  (iOS 15, macOS 12)
- https://developer.apple.com/documentation/swiftui/view/confirmationdialog(_:ispresented:titlevisibility:actions:message:)
  (iOS 15; already used by Phase 2 Task 18)

Changes (spec 3.7):

1. **`NameEntrySheet` needs a starting value for a rename.** It has none (`@State private var name
   = ""`). Do not edit it (it is shared and tested by use); write a private `RenameSheet` in
   `GymsScreen.swift` with `title`, `initialName`, optional `initialBrand` (machines only, a second
   `TextField("Brand (optional)")`), Cancel and Save, Save disabled while
   `EquipmentName.normalized(name) == nil`, and the field focused on appear.

2. **`GymsScreen`.** A `List`, loaded in `.task` and after every write:
   - One `Section` per gym from `store.gyms()`, headed by the gym's name, listing
     `store.machines(at:)` by `displayName`; an empty gym says "No machines yet. Add them from a
     movement's machine chip during a workout."
   - Swipe actions on a gym's header row and on each machine: "Rename" and "Archive"
     (`role: .destructive`), plus the same as a `.contextMenu` and as
     `.accessibilityActions`, so they are reachable without a swipe.
   - Archive asks first, with `confirmationDialog`: "Archive “<name>”?" and the message "It
     leaves your pickers. Every set logged on it stays in your history." Archive is the only
     destructive choice; nothing is deleted (`GymStore.archiveGym`'s comment).
   - Writes go through the store first and the list reloads after: persist before claiming. A
     failure shows `FailureCopy.message(for:during:)` with the matching action in the section
     footer, in `Tokens.Color.critical`, and the list is unchanged.
   - Navigation title "Gyms and machines".

3. **`SettingsSheet`.** Add the `gyms` parameter and, when non-nil, a second `Section` with
   `NavigationLink("Gyms and machines") { GymsScreen(store: gyms) }` and the footer "Rename a gym or
   machine, or archive one you no longer use. History keeps every set."

4. **Mechanical, `HardsetRootView`.** Pass `gyms: environment.gyms`, and present the sheet with
   `.sheet(isPresented: $isShowingSettings, onDismiss: refreshGyms)` so a gym renamed or archived
   there is reflected on the start screen; `refreshGyms` already clears a selected gym that is no
   longer listed.

Ledger, under `## Phase 3`:

```markdown
- [ ] (feat(feature): rename or archive a gym or a machine …) HardsetFeature builds (iOS, and
      macOS 15 via `./test.sh`). In the simulator:
  - [ ] Settings › Gyms and machines lists each gym with its machines.
  - [ ] Rename a machine to "Leg Press 45°" with brand "Hammer Strength": the list, a past
        session's detail and the movement's chart all read "Hammer Strength Leg Press 45°".
  - [ ] Rename to spaces: Save stays disabled.
  - [ ] Archive the selected gym, close Settings: the start screen no longer shows it; its sessions
        are still in History with their machines named.
  - [ ] Every action is reachable by swipe, by long press, and as a VoiceOver action.
```

Commit, citing the URLs above.

---

## Self-review

Run against the spec with the plan complete; issues found were fixed inline above.

**1. Spec coverage (§9).**

| Spec item | Where |
|---|---|
| 3.1 Badges beside every derived number (e1RM, volume, lower bounds); glyph + word; tap opens the source | Core: Tasks 1, 3. UI: Task 12 (badge), 13 (volume tab, summary), 14 (chart), 15 (row records), 17 (session detail) |
| 3.1 `UnevaluatedReadout` and `AssumptionChip` used | Task 14 (no estimate), Task 15 (borrowed loads), Task 18 (inferred unit) |
| 3.1 Per-muscle certainty replaces the global header | Task 3 (`certainty(for:)`), Task 13 (rows; sheet opened with `certainty: nil`) |
| 3.2 `EvidenceSource.summary` "In short" | Task 2 (field and six summaries), Task 12 (sheet) |
| 3.2 Visual of 1.0 / 0.5 / 0 | Task 2 (`creditScheme`), Task 12 (bars) |
| 3.2 DOI as a `Link`; Done; plain titles | Task 2 (`doiURL`), Task 12 |
| 3.3 Summary headline over the chart | Task 4 (`ProgressionHeadline`), Task 14 |
| 3.3 Scrubbing with `chartXSelection` | Task 4 (`ProgressionSelection`), Task 14 |
| 3.3 A symbol shape per machine; estimates dashed | Task 14 (`.symbol(by:)`, `.lineStyle`), Task 4 (`isEstimate`) |
| 3.3 `AXChartDescriptor` | Task 4 (`ProgressionChartDescription`), Task 14 (`ProgressionAudioGraph`) |
| 3.3 Series never merged | Task 4 (unique labels, headline per series, description per series) |
| 3.4 Set row default action logs, with value and traits; VoiceOver announces logs and records | Task 5 (`SetRowSpeech`), Task 15 |
| 3.4 Pad: dead decimal hidden; pad speaks the value | Task 5 (`spokenValue`, `spokenStep`), Task 15 |
| 3.4 Rest buttons reachable | Phase 2 Task 15 (expanded); Task 15 here (collapsed accessory) |
| 3.4 History rows not dimmed | Phase 1; re-checked in Tasks 13 and 17 |
| 3.4 Unit names spoken in full | Task 5 (`spokenTotal`, `SessionVolumeText.spoken`), Tasks 13, 14, 15, 17 |
| 3.4 Accessibility text sizes: stacked row, scaled metrics, 44 pt | Task 15 |
| 3.4 Nothing by colour alone | Task 1 (tests), Task 14 (shapes per machine), Global Constraints |
| 3.5 One screen: three promises, privacy line, Start | Task 7 (copy, tests), Task 18 |
| 3.5 Gym optional; alarm permission deferred | Task 7 (`complete(gymName:)`), Task 18 |
| 3.5 Unit inferred from locale, visibly correctable | Task 7 (`inferred(from:)`), Task 1 (`unitFromRegion`), Task 18 |
| 3.5 No questionnaire, goals or program | Task 7 (`asksForNothing`), Task 18 |
| 3.6 Tappable rows open a session detail (by exercise and machine, records, honest duration) | Task 8, Task 17 |
| 3.6 Exercise progress reachable outside a live workout | Task 17 (block header → `ExerciseProgressScreen`) |
| 3.7 Rename and archive | Task 6 (`renameGym`, `renameMachine`; archive existed), Task 19 |
| 3.8 String Catalogs and `defaultLocalization: "en"` | Task 10 (Core's catalog); UI catalogs deferred (reading 2) |
| 3.8 Core copy to `String(localized:)` | Task 10 (seam), Task 11 (migration) |
| 3.8 Locale-aware decimal separator | Task 3 (`countText`), Task 5 (`displayText(locale:)`), Task 13 (deletes `%.1f`) |
| 3.8 Verified on the Mac before anything builds on it | Task 10 GATE; Task 11 precondition |
| 3.9 Split `HardsetRootView` (start, gym picker, accessory) | Task 16 |
| 3.9 Muscle names into Core; remove the `CertaintyLevel` mirror | Task 9, Task 12 |

Gap found and fixed while writing: the chart's machine labels collided (`machineNames` returned the
bare name), so "series are never merged" was not actually true for same-named machines. Task 4
now owns that fix, and it is the first Review Focus item.

**2. Placeholder scan.** No "TBD", "TODO", "implement later", "similar to Task N", or test step
without code. Core and Store steps carry complete, compiled code. Mac-only steps carry exact
snippets for every new or changed construct, and name each pure move (Task 16) by its inputs and
outputs instead of repeating unchanged code. The one deliberately open item is Task 10's ledger
note on whether Xcode extracts `localized(…)` literals, which is an observation to record, not
work left undone.

**3. Type consistency.** Checked across tasks:
- `CertaintyBadge(_ certainty: Certainty, source: EvidenceSource, style:)` in Tasks 12, 13, 14, 17;
  Task 15 deliberately uses glyph + word without a button inside the row.
- `ProgressionChartSeries(label:points:)`, `ProgressionHistory.chartSeries()`,
  `ProgressionHeadline.current(in:metric:formatter:)`, `ProgressionSelection.nearest(to:in:metric:formatter:)`,
  `ProgressionChartDescription.make(exerciseName:series:metric:formatter:)` in Tasks 4 and 14.
- `SetRowSpeech.label(number:isWarmup:)`, `.value(weightKg:reps:isLogged:formatter:)`,
  `.logAnnouncement(number:isWarmup:weightKg:reps:exerciseName:records:formatter:)` in Tasks 5, 15, 17.
- `SessionVolumeText.written/spoken(_:formatter:)` in Tasks 5, 13, 17.
- `EquipmentName.normalized(_:)` in Tasks 6, 7, 19; `GymStoreError.blankName` in Tasks 6, 19.
- `FirstRunStore(database:flag:)`, `.shouldShow()`, `.complete(gymName:now:)` in Tasks 7, 18;
  `HardsetEnvironment.firstRun` and `.sessionDetails` in Tasks 17, 18.
- `SessionDetailStore.detail(for:)`, `SessionDetail.Block.id: ProgressionKey` in Tasks 8, 17.
- `localized(_:comment:)` and `localized(key:default:comment:)` in Tasks 10, 11.
- `Muscle.displayName` / `MuscleKey.displayName` in Tasks 9, 11, 12, 13, 17.

**4. Review Focus.** Each of the five lines is pinned by a named test in its owning task:
`sameNamedMachinesStayApart` and `brandLeads` (Task 4); `headlineNeverSpansMachines`,
`descriptionKeepsSeriesApart` and `deltaMatchesDisplayedNumbers` (Task 4);
`existingHistorySkipsFirstRun` and `openWorkoutSkipsFirstRun` (Task 7);
`renameToBlankLeavesName` and `blank` (Task 6) and `blankGymNameCreatesNoGym` (Task 7);
`sameExerciseTwoMachinesTwoBlocks` and `archivedMachineStillNamed` (Task 8). A comma-decimal
locale, the next most likely to bite, is covered by `keypadDisplayUsesLocaleSeparator` (Task 5),
`countText` (Task 3) and `germanDecimal` (Task 4).
