# Hardset master plan

Decided 2026-11-11 after a whole-app review covering product direction, HardsetCore,
HardsetStore, HardsetUI and HardsetFeature, repository tooling, and verification honesty.
This document is the single authority on what is in scope, what is frozen, and in what order
work happens. It replaces `docs/GPT_HANDOUT.md`, `docs/MODEL_HANDOUT.md` and
`docs/GPT_HANDOUT_PROGRESS.md`. Edit it when a decision changes; never append logs here.
Progress lives in `.agents/HANDOFF.md` as a short current-state file.

Standing decision recorded here: the Apple Developer Program purchase is deferred. Until it
happens, builds expire every seven days, there is no iCloud, no push, no TestFlight, and the
app is local-only. Every stage before Stage 6 is planned around that constraint.

## Contents

1. Verdict and evidence
2. Rules for every stage
3. Frozen list
4. Stage 0: Clear the deck
5. Stage 1: Data safety under the seven-day cliff
6. Stage 2: Honesty correctness
7. Stage 3: Daily-use core loop
8. Stage 4: Structural refactors
9. Stage 5: Device evidence and three weeks of real use
10. Stage 6: Decision gate for strangers
11. Stage 7: Conditional: first external release
12. Appendix A: verification commands
13. Appendix B: how work is dispatched
14. Appendix C: decision log

## 1. Verdict and evidence

Grades from the review, with the reasons that survived verification against the source.

| Area | Grade | Reason |
| --- | --- | --- |
| HardsetCore | B+ | Real Foundation-only seam, behavioural tests, but certainty is ignored in record comparison and the load tolerance equals the keypad resolution |
| HardsetStore | B | Append-only migrations, 16-variant first-release upgrade test, atomic writes; no in-app restore, about 350 lines of unreachable CloudKit code, dead tables |
| HardsetUI and Feature | B+ | Enforced tokens, deep accessibility; `SessionView` at 1,299 lines and `LiveSessionScreen` with 26 state fields; rest always costs a second tap |
| Repository hygiene | C | About a quarter of tracked text is process material; test counts wrong in four files; schema suites run in no automated gate |
| Product direction | Coherent but thin | Machine-level history is a real wedge; no user besides the author; no routines, notes, or saved-set edits |

Ground truth on commit `e24bc5f` (main at review time):

| Gate | Result |
| --- | --- |
| Linux `make check` | exit 0 |
| Core tests | 232 in 29 suites |
| Store tests (portable) | 297 in 30 suites |
| Query-plan and contrast checks | passed |
| macOS CI run 43114752712 (readiness branch) | green, 35 min |

Verified defects, each with the line that proves it:

- `PersonalRecords.swift` around line 157 picks `previousEstimates.max()` with no certainty filter, so a low-certainty 12-rep estimate can claim a one-rep-max record and can block a genuine 130x3 record.
- `PersonalRecords.swift` line 73 sets `loadMatchingTolerance = 0.01` while the keypad accepts two decimals, so load equality sits on floating-point bits.
- `ExerciseLogState.swift` around line 358 numbers prefill rows after a machine change by counting sets logged on the previous machine. Decide whether that is intended before changing it.
- `VolumeReportView.swift` line 184 hard-codes `level: .moderate` while `MuscleHeatmapView` computes its level from credited muscles.
- `HardsetApp.swift` line 138 passes `restAfterSet: nil`, so rest is never automatic.
- No file in `Packages/HardsetKit/Sources` mentions a routine, template, or notes entry.
- `WorkoutCSVImport.swift` parses Strong and Hevy only; Hardset cannot re-import its own JSON or SQLite export.
- `README.md` lines 3, 11, 14 and 44 claim CloudKit sync, "never compiled", and two different test counts.
- `origin/FrankieBiz/app-readiness-review` holds three unmerged commits (`f2b1c3a`, `cc8245c`, `1a0029c`) with a green CI run.

## 2. Rules for every stage

- One stage at a time. A stage opens only when the previous stage's exit criteria are met and
  recorded in `.agents/HANDOFF.md`.
- Every behaviour change ships with a test that was seen red against the old code and green
  against the new. Record the red run in the handoff.
- `make check` must exit 0 on Linux before any commit that touches Swift. macOS CI must be green
  before anything reaches main. A cancelled CI run is not a green run.
- Reinstall over the existing app on the phone. Never delete it first; that erases every workout.
- No new colour, typography, radius, spacing or motion token without a `DESIGN.md` edit in the
  same commit.
- No new table or column outside an appended migration. Existing migration bodies are never
  edited again.
- Keep Core Foundation-only and nonisolated. Keep all UI in HardsetUI on the main actor.
- Workers own disjoint paths. A worker reports diffs and actual command output, never a claim.
  The coordinator integrates and runs the finish protocol.
- Commit identity is FrankieBiz, no AI attribution lines, no model names in messages.
- Do not write new research or review documents. If a finding matters, it becomes a task here.

## 3. Frozen list

Frozen until Stage 6 decides otherwise. Frozen means: no new work, no refactors, no tests
added, no docs written. Existing code stays compiled and its tests keep running.

| Feature | Why frozen | Where it lives |
| --- | --- | --- |
| Muscle map and the StoreKit lifetime purchase | Only paid feature, zero users, needs App Store Connect | `MuscleHeatmapView.swift`, `LifetimeAccess.swift`, `LifetimePurchaseSection.swift` |
| Apple Health read and write | Needs entitlements and review justification; nothing in the core loop uses it | `HealthSettingsSection.swift`, `DeviceHealthStore.swift`, `HardsetHealth` |
| Receipt share image | Growth tooling for a product with no audience; text share stays | `WorkoutReceiptScreen.swift`, `WorkoutReceiptView.swift` |
| CloudKit sync | Unreachable without a paid team; the most expensive decision in `DECISIONS.md` | `SyncSetup.swift`, `SyncStatus.swift`, `SchemaRules.swift`, sync branch of `Database.swift` |
| Strong and Hevy import | Built against guessed CSV shapes with no real fixtures; the author's own Strong export is the only fixture worth keeping | `WorkoutCSVImport.swift`, `DataPortabilitySection.swift` |
| Exercise library growth beyond 50 | Custom movements cover the gap until a stranger asks | `ExerciseCatalog.swift` |
| Multi-model orchestration tooling | Ceremony; deleted in Stage 0 | `scripts/orchestrate.py` and related |
| New research documents | 3,723 lines already exist; findings become tasks here instead | `docs/research/` |

## 4. Stage 0: Clear the deck

Goal: remove everything that does not ship, make every number in the repo true, and close the
verification holes that cost one line each. Expected duration one to two days. No product
behaviour changes.

Exit criteria:

- `git ls-files | xargs wc -l` shows documentation and tooling below fifteen percent of tracked
  lines.
- No file in the repo quotes a test count. `hardset-check` prints real counts at run time.
- The macOS CI filter includes the four Apple-only Store suites and the workflow has a
  `pull_request` trigger.
- `.agents/HANDOFF.md` is a current-state file under 60 lines.
- `origin/FrankieBiz/app-readiness-review` is merged and remote branch count is under five.

### Task 0.1: Merge the readiness branch

- What: fast-forward or merge `origin/FrankieBiz/app-readiness-review` into main. It carries the
  relaunch UI test, purchase restoration visibility, and the explicit "Not recorded" gym pick.
- Acceptance: main contains `1a0029c`; CI on main is green; `make check` exits 0.
- Verification: `git log --oneline main | head -5`, `gh run list --repo FrankieBiz/hardset --limit 3`.
- Effort: under an hour.

### Task 0.2: Delete the orchestration layer

- What: remove `scripts/orchestrate.py`, `scripts/test_orchestrate.py`,
  `docs/ORCA_ORCHESTRATION.md`, `docs/GPT_HANDOUT.md`, `docs/MODEL_HANDOUT.md`,
  `docs/GPT_HANDOUT_PROGRESS.md`, `DEEPSEEK.md`, `Tools/render_interim_icon.py`, the
  `orchestrate-probe`, `orchestrate-stats`, `orchestrate-children` Makefile targets, and the
  `check-orchestration` prerequisite on `check`. Keep `scripts/orca-child.sh` only if Orca child
  worktrees are still used; otherwise delete it too.
- Acceptance: `make check` still exits 0 and no longer runs Python unit tests; `rg -l orchestrat`
  returns nothing outside `docs/history/`.
- Verification: `make check`, `rg -il 'orchestrat|handout|deepseek' --glob '!docs/history/**'`.
- Effort: one to two hours.

### Task 0.3: Collapse the handoff layer

- What: move `.agents/HANDOFF.md`, `.agents/handoffs/*.md`, root `HANDOFF.md`,
  `docs/research/*`, `docs/CORE_STORE_ARCHITECTURE_REVIEW.md`,
  `docs/UI_TOKEN_ACCESSIBILITY_AUDIT.md`, `docs/COMPETITIVE_AND_PRODUCT_REVIEW.md` and
  `docs/LOADING_PERFORMANCE.md` to `docs/history/`. Write a new `.agents/HANDOFF.md` with:
  current stage, current task, branch and worktree, last green gate with date, open decisions,
  and the next concrete step. Nothing else.
- Acceptance: new handoff under 60 lines; `docs/history/README.md` lists what moved and why.
- Verification: `wc -l .agents/HANDOFF.md`.
- Effort: one to two hours.

### Task 0.4: Make every number true

- What: remove hard-coded test and file counts from `README.md`, `AGENTS.md`, `CODEX.md`,
  `CLAUDE.md`, and the `Tools/hardset_check.py` epilog and help text. Have `hardset_check`
  print "N portable Store files of M" and the suite and test counts it actually ran. Rewrite
  README lines 3, 11 and 14: the app is local-only, the app and widget are compiled in CI, and
  tests are counted by the tool. Delete `test.sh` and the `make test` target if `make mac-test`
  and CI cover the same ground; otherwise document the one case `test.sh` covers.
- Acceptance: `rg -n '[0-9]+ tests' README.md AGENTS.md CODEX.md CLAUDE.md docs/*.md` returns
  nothing outside `docs/history/`.
- Verification: the `rg` above, plus `make check`.
- Effort: one hour.

### Task 0.5: Trim the agent instructions

- What: in `AGENTS.md` and `CLAUDE.md`, remove the model-tier mandates, the "Models Used"
  response-format requirement, the Antigravity orchestrator description, and the pointer to the
  deleted orchestration doc. Keep: architecture summary, verification commands, the finish
  protocol, the no-diagrams and no-attribution rules, and the pointer to `DESIGN.md` and this
  roadmap. Record in Appendix C that direct push to main is the project's explicit standing
  authorization, since the global rules default to a branch and PR.
- Acceptance: `AGENTS.md` under 50 lines; `CLAUDE.md` under 30 lines; both reference
  `docs/ROADMAP.md`.
- Verification: read both files; `make check`.
- Effort: under an hour.

### Task 0.6: Close the one-line CI holes

- What: in `.github/workflows/ios-ui.yml` add `SchemaTests`, `SyncDelegateTests`,
  `SyncEngineRetentionTests`, `AccountChangePolicyTests` to the `swift test --filter` on line 48.
  Add `pull_request` to the triggers. Make the accessibility audit handler in
  `HardsetUITests/AppScreensUITests.swift` return `false` for any issue type not on a short,
  named allowlist, so the audit can fail a test.
- Acceptance: a CI run on a feature branch shows the four suites executing; a deliberately
  injected unlabeled button fails the audit step (verify once, then remove the injection).
- Verification: `gh run view <id> --log | rg 'SchemaTests|SyncDelegateTests'`.
- Effort: one hour plus one CI cycle.

### Task 0.7: Prune remote branches

- What: for each of the seventeen remote branches, confirm `git branch -r --merged origin/main`
  lists it, then delete it. Keep any branch with unmerged commits and list it in the handoff
  with a one-line reason.
- Acceptance: unmerged branches listed in the handoff; merged ones gone.
- Verification: `git branch -r | wc -l`.
- Effort: under an hour. Branch deletion is outward-facing; confirm with the user before running it.

## 5. Stage 1: Data safety under the seven-day cliff

Goal: make it very hard to lose workouts while the build still expires weekly. This stage is
first because the developer purchase is deferred, so the cliff stays for months. Expected
duration one week.

Exit criteria:

- A workout logged on the phone can be exported, the app deleted, reinstalled, and the export
  restored with every set, machine, gym and timestamp intact. Proven once on the phone and
  recorded in `DEVICE-CHECKLIST.md`.
- The app shows how many days remain before the signing expiry and what to do about it.
- A Store test proves a set survives a dropped connection on a file-backed database.

### Task 1.1: Restore from Hardset's own export

- What: extend `WorkoutCSVImport.swift` and `DataTransferStore.swift` so the import preview
  recognises Hardset's JSON export (all tables) and Hardset's SQLite export. Restore into an
  empty database is the primary path. Restore into a non-empty database must dedupe by row
  identity and report what it skipped. Reuse the existing `deviceImportBatches` digest so a
  file cannot be applied twice.
- Owned paths: `HardsetStore/DataTransferStore.swift`, `HardsetStore/WorkoutCSVImport.swift`,
  `HardsetStoreTests/DataTransferTests.swift`, `HardsetFeature/DataPortabilitySection.swift`.
- Acceptance: export then restore round-trips every row of every table on a fixture with two
  gyms, three machines, forty sets, warm-ups, custom movements and a rest journal; a second
  restore of the same file applies zero rows.
- Verification: red test first against current code; `make check`.
- Effort: two to three days.

### Task 1.2: Export reminder and expiry countdown

- What: store the install date at first launch after each install (a bundle-version plus
  first-run stamp in `RestPreferences`-style device storage). Show a banner on the start screen
  from day five: days remaining, "Reinstall over the app, never delete it", and an Export button.
  Also show an export reminder after every tenth finished session if no export happened since.
  Use `HardsetBanner` on `warningSurface`; no new tokens.
- Owned paths: `HardsetStore/AppStartup.swift` or a new `DeviceInstallStore.swift`,
  `HardsetFeature/HardsetRootView.swift`, `HardsetUI/Components.swift` only if a banner variant
  is missing, matching tests.
- Acceptance: banner appears at day five in a test with an injected clock; disappears after a
  fresh install stamp; export reminder fires at session ten and resets after export.
- Verification: `make check`; snapshot render of the start screen with the banner.
- Effort: one day.

### Task 1.3: Export from the startup-failure screen and a pre-migration copy

- What: before running migrations on a file-backed database, copy the file to
  `hardset-premigration.sqlite` beside it, keeping only the latest copy. On the startup-failure
  screen in `HardsetApp.swift`, add an "Export database" control that shares the raw file via the
  system share sheet without opening it. Keep the existing Try again.
- Owned paths: `HardsetStore/Database.swift`, `Hardset/HardsetApp.swift`,
  `HardsetStoreTests/HistoryStoreTests.swift`.
- Acceptance: a migration that throws leaves the pre-migration copy intact and byte-identical to
  the pre-upgrade fixture; the failure screen exposes the share control in a snapshot.
- Verification: `make check`; CI snapshot.
- Effort: one day.

### Task 1.4: File-backed kill-and-reopen test

- What: in `SessionRecoveryTests.swift`, open a `DatabasePool` on a temporary file, start a
  session, log one set, drop every reference without finishing, reopen the file, resume, and
  assert exactly one logged set with the same ID, machine and timestamp. Add a variant that
  crashes between the set insert and the record-comparison read using the existing SQL trace
  hook, and assert the set is present and no claim is published.
- Owned paths: `HardsetStoreTests/SessionRecoveryTests.swift`.
- Acceptance: both tests pass; the trace variant was seen to fail when the insert and the
  claim were deliberately reordered.
- Verification: `make check`.
- Effort: half a day.

### Task 1.5: Prove it on the phone

- What: run Task 1.1's round trip on the device: log a workout, export, delete the app, reinstall,
  restore, open History. Record the outcome and date in `DEVICE-CHECKLIST.md`. This is the one
  time deletion is allowed, and only after the export is confirmed readable on the Mac.
- Acceptance: checklist entry with the date, the build, and the row counts before and after.
- Effort: one hour on the Mac.

## 6. Stage 2: Honesty correctness

Goal: make the certainty system true everywhere it is shown. Expected duration one week.

Exit criteria:

- No record claim can be produced or suppressed by a low-certainty estimate.
- Load equality is defined in one place with one quantum, used by Core and Store.
- Every certainty badge on screen is computed, never hard-coded.
- Progression output is deterministic across runs.

### Task 2.1: Certainty-tiered record comparison

- What: in `PersonalRecords.swift`, restrict the one-rep-max comparison to candidates and
  history with `.high` or `.moderate` certainty, and record the certainty of both sides on the
  `PersonalRecord`. In `Progression.swift` around line 193, pick the best estimate within the
  highest available tier. Make `estimatesOneRepMax` a required parameter derived from the
  movement's modality rather than defaulting to true.
- Owned paths: `HardsetCore/PersonalRecords.swift`, `HardsetCore/Progression.swift`,
  `HardsetCoreTests/PersonalRecordsTests.swift`, `HardsetCoreTests/ProgressionTests.swift`,
  Store call sites in `LoggerStore.swift` for the parameter change.
- Acceptance: the reference case passes: history 100 kg x 12 then candidate 130 kg x 3 claims a
  record; candidate 100 kg x 12 against history 130 kg x 3 does not. Both seen red first.
- Verification: `make check`.
- Effort: one day.

### Task 2.2: One load quantum

- What: introduce a Core `LoadGrams` integer comparison helper used for record matching, the
  Store's indexed comparison selection in `LoggerStore.swift`, and `SetEntryDraft` resolution.
  Keep display rounding separate and documented. Validate weight and rep ceilings in
  `SetEntryDraft.resolved()` using the `StrengthMath` constants.
- Owned paths: `HardsetCore/PersonalRecords.swift`, `HardsetCore/PriorPerformance.swift`,
  `HardsetCore/StrengthMath.swift`, `HardsetStore/LoggerStore.swift`, matching tests.
- Acceptance: boundary tests at 0.005 kg, 0.01 kg and the 100 lb to 45.359 kg round trip pass;
  the Store SQL-plan test still uses the `loggedSets_on_workingReps` index.
- Verification: `make check`.
- Effort: one day.

### Task 2.3: Deterministic progression

- What: add explicit tie-breaks (date, then machine ID string) in `ProgressionAnalyzer.series`
  and `machineChanges`; give `MachineChange` and `ProgressionPoint` identities that cannot
  collide across machines in one session; validate `SessionTimeline` on init and decode so a
  finish before a start throws.
- Owned paths: `HardsetCore/Progression.swift`, `HardsetCore/SessionTimeline.swift`, tests.
- Acceptance: a test with two machines of equal point counts and equal last dates produces the
  same order across 100 iterations; a decoded inverted timeline throws.
- Verification: `make check`.
- Effort: half a day.

### Task 2.4: Computed badges and borrowed-prefill marker

- What: compute the volume report level in `VolumeReportView.swift` the same way
  `MuscleHeatmapView` does, through one shared Core function. Show a per-row marker (the
  existing `provenance` text role, no new token) on any set row whose prefill came from another
  machine, driven by `priorNote` instead of leaving it nil. Grade chart points individually using
  the per-point certainty already on `ProgressionPoint`, with a distinct point symbol for low.
- Owned paths: `HardsetUI/VolumeReportView.swift`, `HardsetUI/MuscleHeatmapView.swift`,
  `HardsetUI/ExerciseSectionView.swift`, `HardsetUI/SetRowView.swift`,
  `HardsetUI/ProgressionChartView.swift`, `HardsetCore/MuscleVolume.swift`, snapshot tests.
- Acceptance: a fixture that yields low certainty on the map shows low on the report; a
  borrowed row renders its marker in a snapshot; a chart with mixed certainty shows two symbols.
- Verification: `make check`; CI snapshots reviewed.
- Effort: one to two days.

### Task 2.5: Decide the machine-switch ordinal

- What: write down in Appendix C whether, after two sets on machine A and a switch to B, the
  first row on B prefills from B's first or third historical set. Implement the decision in
  `changeMachine` and `appendSlot`, and decide whether typed-but-unlogged drafts survive a switch.
- Owned paths: `HardsetCore/ExerciseLogState.swift`, `HardsetCoreTests/ExerciseCorrectionTests.swift`.
- Acceptance: a test encodes the decision; the current behaviour was seen to fail it if the
  decision changes.
- Effort: half a day.

### Task 2.6: Lock Core mutation paths

- What: make `SetSlot.draft`, `isWarmup`, `loggedSetID` and `ExerciseLogState.slots` mutate only
  through methods; make `completedAt` optional instead of a 1970 sentinel; make `SessionVolume`
  read captured logged events rather than live drafts.
- Owned paths: `HardsetCore/ExerciseLogState.swift`, `HardsetCore/SessionVolume.swift`, every
  call site in UI and Store that assigned these directly, tests.
- Acceptance: compiles with no direct assignment outside Core; an edited draft after logging no
  longer changes session volume.
- Effort: one day.

## 7. Stage 3: Daily-use core loop

Goal: remove the taps and gaps that make the app annoying for eight weeks of real use.
Expected duration two weeks. Each task is a separate branch and CI run.

Exit criteria:

- A returning lifter can start yesterday's workout in two taps and log a repeated set in one.
- A typo in a saved set can be fixed without undoing later sets.
- Rest can start on its own after a working set when the lifter opts in.
- Session notes exist.

### Task 3.1: Repeat last workout

- What: on the start screen, next to Start workout, add "Repeat last workout" when a finished
  session exists for the chosen gym. It creates the plan from the last session's exercises,
  machines and set counts in one transaction, using `startSession` with a plan. Prefill comes
  from the existing prior-performance snapshot, so nothing new is invented. A second control
  "Start from recent movements" opens the picker with the last three sessions' movements pinned.
- Owned paths: `HardsetFeature/HardsetRootView.swift`, `HardsetStore/WorkoutRootModel.swift`,
  `HardsetStore/SessionCoordinator.swift`, `HardsetStore/LoggerStore.swift` only for a
  last-plan read, `HardsetUI/ExercisePickerView.swift`, matching tests and UI journey.
- Acceptance: a Store test builds a plan from a finished session with two machines and
  warm-ups and asserts order and machine IDs; the UI journey logs a repeated set in one tap
  after two taps from the start screen.
- Verification: `make check`; CI journey.
- Effort: two to three days.

### Task 3.2: Edit a saved set

- What: long-press or the row menu on a logged row opens the keypad on its saved values. Saving
  issues an edit command with its own command ID, validated and written in one transaction with
  the same session, exercise, machine and plan checks as logging. Records are re-evaluated
  against history excluding the edited set itself. Core's captured per-key prefill is refreshed
  explicitly, as the provenance note in `ExerciseLogState` requires.
- Owned paths: `HardsetStore/LoggerStore.swift`, `HardsetStore/SessionCoordinator.swift`,
  `HardsetCore/ExerciseLogState.swift`, `HardsetUI/SetRowView.swift`, `HardsetUI/SessionView.swift`,
  `HardsetStoreTests/LoggerCorrectionTests.swift`, `HardsetStoreTests/SessionCorrectionTests.swift`.
- Acceptance: editing set two of four leaves sets one, three and four untouched, updates the
  row, refreshes the next-set prefill, and withdraws a record that the old value had claimed.
- Verification: `make check`; CI corrections journey extended.
- Effort: two to three days.

### Task 3.3: Session notes

- What: a notes field on the finish sheet and in the History receipt, backed by the existing
  `notes` column on sessions. Plain text, no formatting, no per-set notes yet.
- Owned paths: `HardsetUI/SessionView.swift` finish controls, `HardsetUI/HistoryView.swift`,
  `HardsetStore/LoggerStore.swift` for the update, `HardsetStore/ReceiptStore.swift`, tests.
- Acceptance: a note typed at finish appears on the receipt and in the export.
- Effort: one day.

### Task 3.4: Opt-in automatic rest

- What: a per-movement setting, off by default, that starts the remembered rest when a working
  set is logged. Wire `restAfterSet` in `HardsetApp.swift` from that preference. Keep the
  explicit duration choice as the way the duration is first set, so no rest is ever invented.
- Owned paths: `HardsetStore/RestPreferences.swift`, `Hardset/HardsetApp.swift`,
  `HardsetFeature/RestTimerHooks.swift`, `HardsetUI/ExerciseSectionView.swift` for the toggle,
  tests in `RestPreferencesTests.swift` and `SessionCoordinatorTests.swift`.
- Acceptance: with the toggle on and a remembered 90 s, logging a working set schedules rest;
  with no remembered duration nothing starts and the row shows the existing Start rest control.
- Effort: one day.

### Task 3.5: Pounds through the real UI

- What: one UI journey that switches the unit to pounds, logs 135, and asserts the row label
  shows 135 lb, plus a Store assertion that the stored kilograms equal 61.235 within the load
  quantum from Task 2.2.
- Owned paths: `HardsetUITests/AppScreensUITests.swift`, `HardsetStoreTests/SetCommandTests.swift`.
- Effort: half a day.

## 8. Stage 4: Structural refactors

Goal: reduce regression risk in the two files every feature touches. These are done only when
a Stage 3 task needs them or after Stage 3 completes, never speculatively. Expected duration
one week. No behaviour change; snapshot and UI journeys are the regression net.

### Task 4.1: Live session model

- What: extract an `@Observable` `LiveSessionModel` from `LiveSessionScreen.swift` holding
  picker, machine, gym and error state, create-then-select orchestration, and error-to-sentence
  mapping. Replace the inline `catch { return false }` persistence with a typed result. Share
  the gym creation flow with `HardsetRootView` instead of duplicating it.
- Acceptance: `LiveSessionScreen` under 400 lines with fewer than ten `@State` fields; model
  logic covered by unit tests without a UI host.

### Task 4.2: Split the session view

- What: split `SessionView.swift` into keypad host, finish controls, records card and stale
  notice, and replace the roughly 33 callback parameters with one `SessionActions` struct.
  Merge `machineChip` and `gymChip` into one capsule button. Reuse `HardsetBanner` for the
  tinted cards.
- Acceptance: no file in HardsetUI over 700 lines; snapshot renders byte-identical except for
  intentional changes listed in the commit.

### Task 4.3: Token cleanup

- What: add `Tokens.Stroke.dash` and a banner border opacity token, fix the `spacing: 20` in
  `HardsetEmptyState.swift`, make `SetRowMetrics` widths `@ScaledMetric`, replace the system
  `ProgressView` in `MuscleHeatmapView` with the volume gauge, delete the unused `rowTitle` and
  `AssumptionChip`, and stop printing raw error descriptions in `HardsetRootView`. Document the
  two new tokens in `DESIGN.md` in the same commit.
- Acceptance: `rg -n 'dash: \[' Packages/HardsetKit/Sources/HardsetUI` finds only the token.

### Task 4.4: Store pruning

- What: stop referencing `deviceRestTimer` and `bodyweightEntries` in code and mark them inert
  in `Schema.swift`; append a migration dropping the three prefix indexes on `loggedSets` once
  the query-plan gate confirms every query still uses an index; move the CloudKit-only types
  behind a single `#if HARDSET_SYNC` or delete `AccountChangePolicy` and the always-false branch.
- Acceptance: `make check` and the query-plan gate pass; the four Apple-only suites still pass in CI.

## 9. Stage 5: Device evidence and three weeks of real use

Goal: find out whether the app is a daily driver and whether the machine wedge matters to its
one user. Expected duration three weeks of training plus one day of checklist work. No feature
work during this stage; only fixes for defects found on the floor, each with a test.

Exit criteria:

- `DEVICE-CHECKLIST.md` has dated results for: alarm when locked, alarm under Focus, lock-screen
  countdown, rest surviving process death, haptics, VoiceOver on the set row, Voice Control
  names, xxxLarge and AX3 layouts on the logger, 375 pt width.
- A written log of every friction point met on the floor, each turned into a task here or
  explicitly rejected in Appendix C.
- At least twelve finished sessions in the database.

### Task 5.1: Device checklist run

- What: install with `make mac-install` (reinstall over), run every item in `DEVICE-CHECKLIST.md`,
  record pass, fail or not testable with the date and build.
- Effort: half a day on the phone.

### Task 5.2: Floor log

- What: after each session, add one line per friction point to `.agents/HANDOFF.md` under a
  "Floor log" heading. At the end of the stage, convert each into a task in Stage 3 or 7, or a
  rejection in Appendix C.

### Task 5.3: Floor fixes

- What: fix only what the log reports as blocking logging, rest or recovery. Each fix is a
  separate branch with a red-then-green test.

## 10. Stage 6: Decision gate for strangers

Goal: decide, with evidence from Stage 5, whether Hardset goes to other lifters. This stage is a
decision, not work. The developer purchase happens here if the answer is yes.

Inputs:

- Stage 5 session count, floor log, and checklist results.
- Whether the machine-level history changed a training decision in those three weeks.
- Whether the author would reinstall it after losing it, which the seven-day cliff will test.

Outcomes:

- Yes: buy the developer membership, open Stage 7.
- Not yet: stay personal, keep the Stage 1 safety net, revisit after another month of use.
- No: keep it as a personal tool, archive the frozen features, stop here.

## 11. Stage 7: Conditional: first external release

Only if Stage 6 says yes. Rough order, to be planned in detail at that time:

1. Developer membership; CloudKit entitlement restored; a test for the transition from
   local-only rows to a synced database (metadata backfill), which does not exist today.
2. Onboarding: two screens explaining gyms and machines.
3. Exercise library to about 120 movements, with the taxonomy spec as the source.
4. Unfreeze import with real Strong and Hevy fixtures from at least two versions each.
5. Pricing decision between the $3.99 and $19.99 figures in the historical documents.
6. TestFlight to ten to twenty lifters with a two-week feedback window.
7. App Store review checklist: privacy manifest, Health justification if unfrozen, export and
   delete paths, StoreKit sandbox restore test.
8. Muscle map, receipt image and Health unfreeze only if TestFlight feedback asks for them.

## Appendix A: verification commands

| Purpose | Command | Where |
| --- | --- | --- |
| Linux gate | `make check` | Linux worktree |
| Core only | `python3 Tools/hardset_check.py core` | Linux |
| Store only | `python3 Tools/hardset_check.py store` | Linux |
| Query plans | `python3 Tools/check_query_performance.py --require-indexes` | Linux |
| Palette | `python3 Tools/check_contrast.py` | Linux |
| Project drift | `python3 Tools/generate_project.py && git diff --exit-code Hardset.xcodeproj` | Linux |
| Native tests | `make mac-test` | Mac via SSH |
| Install to phone | `make mac-install` | Mac via SSH, reinstall over |
| CI status | `gh run list --repo FrankieBiz/hardset --limit 5` | anywhere |
| CI log search | `gh run view <id> --log` | anywhere |

A task is done when its acceptance criteria are met, its verification commands exit 0, the CI
run on its branch is green, and the handoff records the red test run.

## Appendix B: how work is dispatched

- The coordinator reads this file and `.agents/HANDOFF.md`, picks the next task in the current
  stage, and creates one worktree and branch per task.
- Tasks in the same stage with disjoint owned paths may run in parallel. Tasks 2.1 and 2.2 both
  touch `PersonalRecords.swift`, so they run in sequence. Tasks 3.1 through 3.4 all touch
  `SessionCoordinator.swift` or `SessionView.swift`, so at most two run at once and the
  coordinator merges in order.
- A worker gets: the task text from this file, the owned paths, the verification commands, and
  the rule that it reports diffs and command output, not claims. A worker never dispatches.
- The coordinator runs `make check` on the merged tree, waits for green CI, and pushes to main
  per the finish protocol. Documentation-only changes still go through CI.
- Models: any current frontier model may do any task. There are no per-provider roles.

## Appendix C: decision log

| Date | Decision | Reason |
| --- | --- | --- |
| 2026-11-11 | Developer purchase deferred by the user; Stage 1 built around the seven-day cliff | User's call; data safety must not wait for it |
| 2026-11-11 | Freeze list in section 3 | Zero external users; every frozen item serves strangers or review |
| 2026-11-11 | Delete orchestration tooling and model handouts | Never shipped, gated the product check with tooling tests, counts drifted |
| 2026-11-11 | Direct push to main after green CI remains the project's standing authorization | Recorded here so it does not read as an accident against the global branch-and-PR default |
| 2026-11-11 | Keep GRDB and SQLiteData, the permanent schema rules, and the four-package split | Review found no reason to change them |
| 2026-11-11 | Certainty tiers for record comparison: high and moderate only | A low-certainty estimate must not claim or block a record |
| 2026-11-11 | Rest stays explicit by default; automatic rest is opt-in per movement | No invented durations, but a second tap per set is a real cost |
| pending | Machine-switch prefill ordinal (Task 2.5) | Decide before changing the code |
| pending | Pricing and whether the muscle map stays the paid feature (Stage 7) | Needs TestFlight evidence |
