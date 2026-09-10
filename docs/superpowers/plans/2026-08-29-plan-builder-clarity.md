# Plan Builder Clarity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make creating a plan from history and redistributing an existing plan two explicit,
plain-language actions.

**Architecture:** `SplitPlannerView` presents one action appropriate to the plan’s state and exposes
separate callbacks. `SplitPlannerScreen` selects the inputs: existing plan movements for
redistribution, logged movements only for the explicit history-start action. No storage shape,
migration, or completed-workout data changes.

**Tech Stack:** Swift, SwiftUI, Swift Testing, HardsetCore, HardsetStore, HardsetUI.

---

### Task 1: Pin the new user-facing language

**Files:**
- Modify: `Packages/HardsetKit/Tests/HardsetUITests/SplitCopyTests.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetUI/SplitPlannerView.swift`

- [ ] **Step 1: Write failing copy tests**

Assert a populated plan labels the tool “Redistribute exercises” and “Redistribute across 3 days”,
uses only the plan’s movements, leaves machines and intended sets alone, and does not affect
completed workouts. It must say it spreads similar-muscle work where possible and never adds or
removes movements or prescribes sets. Assert an empty-plan history action says “Start from training
history”, gives the count, says it uses movements from completed workouts, and promises not to alter
completed workouts. Pin the plain-language explanation of what a reusable plan is for.

- [ ] **Step 2: Run the focused tests to verify failure**

Run: `swift test --package-path Packages/HardsetKit --filter SplitCopyTests`

Expected: failing assertions for the old “Deal across” language or combined source model.

- [ ] **Step 3: Replace combined copy helpers with explicit action copy**

Keep plural helpers. Replace `dealButtonText`, `dealFootnote`, and `dealConfirmation` with helpers
that describe either `redistribution` or `historyStart`; do not select history implicitly from a
general-purpose “deal” helper.

- [ ] **Step 4: Run the focused tests to verify success**

Run: `swift test --package-path Packages/HardsetKit --filter SplitCopyTests`

Expected: all selected tests pass.

### Task 2: Make the empty and populated flows distinct in the SwiftUI surface

**Files:**
- Modify: `Packages/HardsetKit/Sources/HardsetUI/SplitPlannerView.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetFeature/SplitPlannerScreen.swift`
- Modify: `Packages/HardsetKit/Package.swift`
- Create: `Packages/HardsetKit/Tests/HardsetFeatureTests/PlanBuilderRoutingTests.swift`
- Test: `Packages/HardsetKit/Tests/HardsetUITests/AffordanceWiringTests.swift`

- [ ] **Step 1: Write a failing wiring contract**

Add focused tests for a small pure `PlanBuilderMode` decision type:

```swift
#expect(PlanBuilderMode(planMovementCount: 0, historyMovementCount: 12) == .empty(historyCount: 12))
#expect(PlanBuilderMode(planMovementCount: 5, historyMovementCount: 12) == .populated)
```

Add UI-contract assertions that empty mode offers both “Build it myself” and the history start,
with history unavailable at zero; populated mode offers redistribution and no history-start action.
Both automatic actions display a day-count selector and pass the selected count.

- [ ] **Step 2: Run the focused wiring test to verify failure**

Run: `swift test --package-path Packages/HardsetKit --filter AffordanceWiringTests`

Expected: failure until explicit mode and separate actions exist.

- [ ] **Step 3: Implement the separated actions**

In `SplitPlannerView`, choose the UI from the pure mode:

```swift
switch PlanBuilderMode(planMovementCount: days.flatMap(\.movements).count, historyMovementCount: historyCount) {
case .populated:
  redistributionSection
case .empty:
  emptyPlanSection
}
```

`emptyPlanSection` explains the purpose of a plan and exposes both visible routes:

```swift
Button("Build it myself") { onAddDay?() }
Button("Start from training history") { isConfirmingHistoryStart = true }
```

The manual route creates the first editable “Day 1”, after which the ordinary add-movement controls
are visible. The history button is disabled at zero history movements and has its own confirmation.
The same local `Stepper` day selector appears before the empty-plan history action and before
redistribution; it initializes to one for an empty plan, otherwise to the existing day count.
`redistributionSection` uses existing-plan count only and has its own confirmation. In
`SplitPlannerScreen`, `redistribute` reads only `splits.plan(for: selected).allMovements`;
`startFromHistory` reads only `splits.completedWorkoutMovements()`. Their distinct callbacks make
an implicit source fallback impossible. Pass counts from the screen’s reload data; do not query
either store from `body`.

Extract the action-to-input selection into a small internal `PlanBuilderRouting` helper in
`HardsetFeature`, taking explicit `planMovements` and `completedHistoryMovements` arrays. The
screen must invoke that helper for both actions. Add `HardsetFeatureTests` to `Package.swift`,
dependent on `HardsetFeature` and `HardsetCore`, so a focused test can prove each action returns
only its designated collection and the selected day count. This is deliberately not a source-text
scan: it exercises the composition boundary that decides what the dealer receives.

- [ ] **Step 4: Run the focused tests to verify success**

Run: `swift test --package-path Packages/HardsetKit --filter 'SplitCopyTests|AffordanceWiringTests|PlanBuilderRoutingTests'`

Expected: all selected tests pass.

### Task 3: Verify no plan data becomes collateral damage

**Files:**
- Modify: `Packages/HardsetKit/Tests/HardsetStoreTests/SplitStoreTests.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetStore/SplitStore.swift`
- Test: `Packages/HardsetKit/Tests/HardsetUITests/SplitCopyTests.swift`
- Test: `Packages/HardsetKit/Tests/HardsetFeatureTests/PlanBuilderRoutingTests.swift`

- [ ] **Step 1: Add or strengthen the preservation test**

Build an existing multi-day plan with named days, machine choices, intended set counts, and a
session linked to a retained day. Redistribute it and assert those authored details and the linked
session survive. Replace `loggedMovements()` with `completedWorkoutMovements()` implemented through
a `LoggedSet`/finished-`Session` read; add a fixture with one finished and one open session and
assert the open-session movement is excluded. In `SplitCopyTests`, use the public
`PlanBuilderMode` and action helpers to prove history start receives the completed-history input and
redistribution receives only current-plan input. In `PlanBuilderRoutingTests`, prove the
feature-layer helper passes the completed-history list only for history start and the current-plan
list only for redistribution, preserving the selected day count in both cases.

- [ ] **Step 2: Run the focused store test**

Run: `swift test --package-path Packages/HardsetKit --filter 'SplitStoreTests|PlanAuthoringTests|SplitCopyTests|PlanBuilderRoutingTests'`

Expected: all selected tests pass; if it fails, make the smallest store repair before proceeding.

### Task 4: Update product explanation and perform end-to-end verification

**Files:**
- Modify: `docs/SPLITS-spec.md`
- Modify: `README.md` only if it directly describes the planner action.

- [ ] **Step 1: Document the two flows**

State that a plan is a reusable workout structure; history-start creates a first arrangement from
movements actually logged, while redistribution reshapes only a current plan.

- [ ] **Step 2: Run package verification**

Run: `./test.sh`

Expected: exit 0 and `ALL SUITES PASSED`.

- [ ] **Step 3: Build the app target**

Run: `xcodebuild -quiet -skipMacroValidation -project Hardset.xcodeproj -scheme Hardset -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/HardsetPlanBuilderBuild CODE_SIGNING_ALLOWED=NO build`

Expected: exit 0.

- [ ] **Step 4: Run simulator journey tests**

Run: `xcodebuild test -project Hardset.xcodeproj -scheme Hardset -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:HardsetAppUITests`

Expected: all planner journeys pass.
