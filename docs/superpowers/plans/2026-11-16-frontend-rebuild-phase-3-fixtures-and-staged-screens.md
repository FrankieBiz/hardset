# Front-end rebuild, Phase 3: Fixtures and staged screens — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (this phase is small and tightly coupled, so it is built inline in one checkout).

**Goal:** Give the first-launch tour something truthful to show: a staged in-memory app environment (`TourFixtures`), a frame that hosts a real screen as a scaled phone (`ScaledPhoneFrame`), and a snapshot of every staged screen rendered from those fixtures, so Phase 4 builds the tour on screens that already render and cannot lie about the product.

**Architecture:** `TourFixtures` lives in HardsetFeature (it needs the Store and the composition root, and Phase 4's onboarding calls it at run time). It builds a migrated in-memory database and fills it through the real write path (`SessionCoordinator` with an injected `now` clock), so records, volume, prefill and "Last time" are produced by the engine, not typed in. `ScaledPhoneFrame` lives in HardsetUI. Snapshot suites in `HardsetUISnapshotTests` render the real screens from the fixtures. No Core or Store logic changes.

**Tech Stack:** Swift 6.2 tools, Swift 6 language mode, `@MainActor` by default in HardsetUI and HardsetFeature, SwiftUI on iOS 26.1, Swift Testing, GRDB (already the locked storage engine; HardsetFeature gains the product dependency to build an in-memory `DatabaseQueue`).

**Spec:** `docs/superpowers/specs/2026-11-12-frontend-rebuild-design.md` (section "Screen 5: Tour", "Component kit", "Engine asks", "Delivery" item 3). **Previous phase:** `docs/superpowers/plans/2026-11-13-frontend-rebuild-phase-2-component-kit.md`; its Global Constraints, the `.agents/HANDOFF.md` Phase 2 entry and `.agents/handoffs/phase-2.md` carry the settled decisions and traps and are not repeated here.

## Global Constraints

- No Core or Store logic, schema or migration change. Where a fixture needs something the engine does not expose, stop and record an engine ask instead of reaching into private state.
- No new colour, type, radius, spacing or motion token. Kit-only token names; `ScaledPhoneFrame` uses `steel`, `edgeLight`, `Tokens.Radius.card` and `Tokens.Radius.control`.
- The Phase 2 gates still apply to every file this phase touches: no old alias names, every animation through `Tokens.Motion.adaptive`, no `.knurl()` overlay, no new `Shape` type, new snapshot suites wrapped whole in `#if canImport(UIKit)`, a file that names a HardsetCore type imports HardsetCore, public types have explicit `public init`s.
- Fixture dates derive from one `now` argument, never from the wall clock inside the fixture, so a test can pass a fixed instant and its PNGs are stable.
- Linux cannot compile SwiftUI or GRDB-backed Feature code. Gates: `hardset-check parse`, `python3 -B Tools/check_contrast.py`, the generator diff and `make check`. Compile is proven only by the macOS run (its early package-test compile step reports in about 6 minutes). Never claim a render passed without opening its PNG.
- Commits are authored by `FrankieBiz <frankabisignano@gmail.com>`, no trailer, no AI attribution, staged by name; no push to `main`; the feature branch is pushed only when a macOS result is needed and never while a run for it is in flight. Never stage `Packages/HardsetKit/Package.resolved`.

## Rulings

| Id | Decision |
| --- | --- |
| R44 | The fixture environment is built through the real write path with an injected clock; the live stage is then reopened with `SessionCoordinator.resume` (the call a relaunch makes) so the staged coordinator uses the real clock for any set the lifter logs in the tour, not the frozen fixture clock. |
| R45 | "One record" in the spec means the last finished workout and the live session each show at least one engine-detected record. The test asserts that a record exists, not an exact count, because the engine decides what counts. |
| R46 | Two spec screens are not staged here: the receipt (`WorkoutReceiptScreen` is internal to HardsetFeature and is rebuilt in Phase 6, which adds its staged render) and the keypad and rest bar as separate captures (the live-session capture shows the rest bar when rest is running; the keypad is the Phase 2 kit capture composed over a fixture draft in Phase 5). Phase 4's tour drives the real screens for those steps. |
| R47 | Staged live screens are rendered outside the tab view, as the existing live-session capture does, because the snapshot renderer cannot draw the tab bar's glass accessory. The start stage is rendered through the real `HardsetRootView`. |
| R48 | This phase is built inline in one checkout with no per-task review agents: the Phase 2 per-task reviews found no actionable defect in 13 of 13 tasks while CI, the PNG review and one whole-branch review found every real one. The gates are the early compile step, the PNG review of each run, and a single whole-branch review before delivery. |

## Review Focus

1. **Fixtures that lie.** A fixture value typed in instead of produced by the engine (a record, a volume bar, "Last time") would make the tour demonstrate something the product does not do. Pinned by Task 2's assertions reading the database and the coordinator, not constants.
2. **A staged phone the lifter can wander into.** Non-interactive frames must not be tappable or focusable by VoiceOver. Pinned by Task 1's `allowsHitTesting` and `accessibilityHidden` gates and read in code review; the pager and the tour's own controls sit outside the frame.
3. **A frozen clock.** A coordinator holding the fixture clock would stamp a lifter's tour taps with a 2026 instant. Pinned by R44 and Task 2's assertion that the live coordinator is the resumed one.
4. **Dynamic Type inside a scaled phone.** The content is laid out at phone size then scaled, so text scales with it by design; the frame itself never shrinks text below the scaled size. Checked from the framed captures at default size.
5. **Fixture drift.** `HistoryScreen`, `WeeklyVolumeScreen` and the live screen read the same database; an in-memory database that is not migrated exactly as the app's would hide a schema bug. Pinned by using `HardsetMigrations.migrator()` and the foreign-keys configuration the app uses.

---

### Task 1: `ScaledPhoneFrame`

**Files:**
- Create: `Packages/HardsetKit/Sources/HardsetUI/ScaledPhoneFrame.swift`
- Modify: `DESIGN.md` (one component entry)

**Interfaces:**
- Consumes: `Tokens.Color.steel`, `Tokens.Color.edgeLight`, `Tokens.Radius.card`, `Tokens.Radius.control`, `Tokens.Spacing.snug`, `Tokens.Stroke.hairline`.
- Produces: `public struct ScaledPhoneFrame<Content: View>: View` with `public static var phoneSize: CGSize` (402 by 874, the iPhone 17 logical size the staged screens are laid out at), `public static var screenWidthFraction: CGFloat` (0.78, the spec's share of the screen width the tour gives the frame; Phase 4 applies it), and `public init(isInteractive: Bool = false, @ViewBuilder content: () -> Content)`.

- [ ] **Step 1: Implement the frame.** It takes whatever width it is offered and keeps the phone's aspect ratio. Its content is laid out at `phoneSize`, clipped to the control radius, scaled to the offered width from the top leading corner, on a `steel` rounded rectangle (card radius, one `snug` of bezel) with a hairline `edgeLight` rim. When `isInteractive` is false the content gets `allowsHitTesting(false)` and `accessibilityHidden(true)`; when true both are left alone. No animation, no motion token.
- [ ] **Step 2: Document it** in `DESIGN.md` under Components as "Staged phone (`ScaledPhoneFrame`)": what it hosts, the 78% fraction, that a non-interactive frame is inert to touch and to VoiceOver, that it adds no token, and that it is where the tour shows real screens.
- [ ] **Step 3: Run the Linux gates and commit** `Add the scaled phone frame the first-launch tour stages screens in`.

### Task 2: `TourFixtures`

**Files:**
- Create: `Packages/HardsetKit/Sources/HardsetFeature/TourFixtures.swift`
- Modify: `Packages/HardsetKit/Package.swift` (add `.product(name: "GRDB", package: "GRDB.swift")` to the HardsetFeature target's dependencies, matching the test target's declaration)
- Create: `Packages/HardsetKit/Tests/HardsetUISnapshotTests/TourFixturesTests.swift` (unwrapped Swift Testing suite, no rendering)

**Interfaces:**
- Consumes: `HardsetEnvironment(database:)`, `HardsetMigrations.migrator()`, `CatalogSeeder.seed()` and `search(_:)`, `GymStore.createGym(name:now:)` and `createMachine(at:name:brand:stackIncrementKg:now:)`, `SessionCoordinator.start(store:gymID:title:plan:now:...)`, `resume`, `addExercise(_:machineID:machineName:machineIncrementKg:plannedSets:)`, `logSet`, `finish()`, `SetEntryDraft`.
- Produces: `@MainActor public enum TourFixtures` with `public static let gymName = "Downtown"`, `public enum Stage: Sendable { case start, liveSession }`, `public struct Staged` (public `environment: HardsetEnvironment`, `database: any DatabaseWriter`, `gymID: GymID`, `gymName: String`, `machines: [MachineRecord]`, `liveSession: SessionCoordinator?` which is nil at `.start`), and `public static func make(stage: Stage, now: Date = Date()) throws -> Staged`.

- [ ] **Step 1: Write `TourFixturesTests` first.** Using a fixed `now`, assert for `.start`: the gym is named "Downtown" and is the only gym; exactly three machines at it; twelve finished sessions and no open one; three of the twelve finished within the seven days before `now`; every logged set's `completedAt` is at or before `now`; the rolling-week volume report for `now` is not empty. Assert for `.liveSession`: one open session with exactly two exercises and three logged sets and one more unlogged slot; `liveSession` is non-nil. Assert records (R45): the last finished workout and the live session each have at least one record, read through the coordinator's `lastRecords` or the receipt store, not a constant.
- [ ] **Step 2: Implement `make`.** Build a foreign-keys-enabled in-memory `DatabaseQueue`, migrate it with `HardsetMigrations.migrator()`, build `HardsetEnvironment`, seed the catalogue, create the gym and three machines (named for movements in `ExerciseCatalog.v1`: "Leg Press", "Chest Press", "Lat Pulldown", each with a brand and a stack step). Write the twelve past workouts oldest first through a coordinator whose `now` is a local mutable clock advanced between sets (180 s per set, 120 s before finish), with a schedule that puts three workouts in the last seven days and lets the newest raise one movement's weight so the engine detects a record. For `.liveSession`, seed the open workout the same way (two exercises, three logged sets, the third beating history), drop that coordinator, and return `SessionCoordinator.resume(store:now:)` with the real clock (R44). Throw a descriptive error when `addExercise` or `logSet` returns false; never swallow.
- [ ] **Step 3: Run the Linux gates and commit** `Add the staged tour environment built through the real write path`.

### Task 3: Staged screens, snapshotted

**Files:**
- Create: `Packages/HardsetKit/Tests/HardsetUISnapshotTests/StagedScreensSnapshotTests.swift` (wrapped whole in `#if canImport(UIKit)`)

**Interfaces:**
- Consumes: `TourFixtures.make`, `ScaledPhoneFrame`, `HardsetRootView`, `LiveSessionScreen`, `WeeklyVolumeScreen`, `HistoryScreen`, `SettingsSheet`, `MachinePickerView` with `MachineOption`, `Snapshot.capture`.
- Produces: PNGs named `tour-<screen>-<appearance>[-framed]`: `tour-start` (real `HardsetRootView`, dark and light), `tour-start-framed-dark` (the same root inside `ScaledPhoneFrame` at 78% of a 402 pt window, to review the frame itself), `tour-live-dark` and `tour-live-light` (`LiveSessionScreen` outside the tab view, R47), `tour-machines-dark` (`MachinePickerView` built from the staged gym's machines, the staged exercise's machine selected), `tour-volume-dark` and `-light`, `tour-history-dark` and `-light`, `tour-settings-dark`. About 12 captures.

- [ ] **Step 1: Write the suite.** Each capture builds its own `Staged` with the suite's fixed `now`; framed and unframed roots must not share an environment instance across captures. Direct-root captures wear `.tint(Tokens.Color.plateBlue)` and a canvas background like the Phase 2 suites.
- [ ] **Step 2: Run the Linux gates and commit** `Snapshot every staged tour screen from the fixtures`.

### Task 4: Verify on macOS, review the renders, record

- [ ] **Step 1:** Run `make check`; push the feature branch once; watch the run (the early compile step reports in about 6 minutes; fix a compile error on the integration branch and push once the failed run has ended).
- [ ] **Step 2:** Open every new PNG. Check: "Downtown" and its three machines appear; History lists twelve sessions across more than one month; Volume is not empty and is scaled to the week's own maximum; the live session shows two exercises, three logged sets and a record banner; the framed root sits at about 78% width with a visible steel rim and nothing cropped; no `layer.render` end-line artefact is mistaken for a defect; light and dark agree.
- [ ] **Step 3:** One whole-branch review of the Phase 3 diff before delivery (compile across files, fixtures not typed in, the frozen-clock case, VoiceOver and hit testing of the frame), fix what it confirms in one commit, and re-run the gates.
- [ ] **Step 4:** Append a dated entry to `.agents/HANDOFF.md` (objective, branch, run id, `make check` line, PNGs reviewed and what was seen, rulings, what Phase 4 inherits), commit it with `[skip ci]`, and update the project memory.
