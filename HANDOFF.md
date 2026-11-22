# Hardset — handoff

Current as of 19 November 2026. This is the short briefing. The running log of every work wave,
with its evidence, is `.agents/HANDOFF.md` (append-only); where the two disagree, the log, the code
and `DECISIONS.md` win. Read this first, then `DECISIONS.md`.

Hardset is an iOS 26 hypertrophy logger for intermediate lifters: calibrated honesty, machine-level
load history, one tap per set. Not a coach, no feed, no streaks, no nutrition, no Apple Watch app
in v1.

---

## 1. Where work happens

- Linux (Fedora) is the development machine. The primary checkout is `/home/frankbiz/orca/hardset`
  and each task gets a worktree under `/home/frankbiz/orca/workspaces/hardset/`. Swift 6.2 runs
  natively; there is no Xcode, so the app, the widget and every SwiftUI view are compiled only by CI.
- macOS is reached two ways. GitHub Actions (`.github/workflows/ios-ui.yml`, `macos-26`, Xcode 26.6)
  builds the app and widget in Debug and Release, compiles and runs the package tests, renders every
  screen to PNG and drives the real app through its UI journeys in dark and light. It runs on a
  push to `main` or `FrankieBiz/**` only; it does not run on a pull request. A personal Mac
  (`ssh mac`, checkout `~/hardset`) installs onto the iPhone: `make mac-install` and `make mac-test`
  build whatever is pushed on the current branch.
- Linux evidence and macOS evidence are different claims. A green `make check` proves the Core and
  Store logic, the parse, the query plans and the palette. It does not prove the app compiles.

## 2. Build and test

```bash
make check
```

Counts from the integrated tree (branch `FrankieBiz/hardset-integration`, exit 0):

- 12 orchestration tests
- 245 Swift files parsed, 0 failures
- 379 Core tests in 44 suites
- 367 Store tests in 33 suites
- every query-plan gate (index use and fixture-preserving migration)
- 184 contrast pairs across 23 swatches

Notes that save time:

- `make check` runs `python3 Tools/hardset_check.py`. The `hardset-check` on `PATH` is a different
  script: it runs five hard-coded Store files and skips every newer test file, so do not trust it
  for Store.
- The CloudKit wiring and the Apple-only Store test files are excluded on Linux by design.
- `python3 Tools/generate_project.py` must leave no diff in `Hardset.xcodeproj`.
- `Packages/HardsetKit/Package.resolved` is rewritten by Linux tooling. Never stage it.

## 3. Layout

- `Hardset/`, `HardsetWidget/`, `HardsetTests/`, `HardsetUITests/`: thin app shell and widget. The
  project file is generated; do not hand-edit it.
- `Packages/HardsetKit/Sources/HardsetCore`: Foundation-only, nonisolated. Engine, taxonomy, value
  types, volume, records, progression.
- `HardsetStore`: GRDB and SQLiteData. Schema, migrations, every query, templates, import and
  export.
- `HardsetUI`: design tokens and every view. Depends on Core only, never on Store.
- `HardsetFeature`: composition root over Core, Store and UI. Depends on SQLiteData.
- `HardsetAlarm`: iOS-only AlarmKit seam and rest-timer controller.
- `DESIGN.md`: the visual system. `DECISIONS.md`: decisions of record. `DEVICE-CHECKLIST.md` and
  `docs/OWNER-DEVICE-CHECKLIST.md`: the device gates. `docs/APP_READINESS_REVIEW.md`: the publication
  gates. `docs/MAC-VERIFICATION.md`: what CI has proven and what still needs a Mac.
  `docs/MuscleTaxonomy-spec.md`: the taxonomy. `docs/research/`: the research corpus; grep it, do
  not read it whole.
- Orchestration and model rules for agents: `AGENTS.md` and `docs/ORCA_ORCHESTRATION.md`.

## 4. Locked decisions

| Area | Decision |
|---|---|
| Min deployment | iOS 26.1 |
| Concurrency | Swift 6, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, approachable concurrency on. `HardsetCore` is deliberately `nonisolated` |
| Local store | GRDB + SQLiteData, not SwiftData |
| Data location | Local to the phone. The current build is signed from a free personal team that cannot carry iCloud, so it runs local-only and says so in Settings. No backend for user data |
| Accounts | None |
| Rest timer | AlarmKit |
| Experience level | Inferred, default intermediate, with a visible "assumes intermediate" correction chip |

Never recommend deleting the app as troubleshooting: local-only means deletion erases training
history. Reinstall over it.

## 5. Decisions that changed in November

- **Lifetime-only monetization.** There is no subscription and no founding-price structure. One
  non-consumable, `com.hardset.app.lifetime`, with an explicit restore action even when storefront
  product information is unavailable. The older $3.99/$8.99/$29.99 pricing table and the open
  "founding price" question are dead.
- **v1 ships the 50-movement seed catalogue.** The ~240-movement authored catalogue is not a v1
  gate. The five muscle tokens with no authored direct credit (`rotatorCuff`, `obliques`,
  `adductors`, `hipAbductors`, `neck`; `ExerciseCatalog.unauthoredDirectTokens`) are disclosed in
  the Volume screen as counted but not modelled, never shown as silently empty and never excluded
  from the vocabulary.
- **Feature freeze** until the device checklist and the publication gates close. Only fixes, the
  merged saved-workout and progress surfaces, and gate work.

## 6. Open work, in order

1. **Device checklist.** Run `docs/OWNER-DEVICE-CHECKLIST.md` (first launch, the daily app, press
   feel, haptics, glare) and `DEVICE-CHECKLIST.md` (AlarmKit with the phone locked, force-quit and
   Focus; HealthKit permission paths) on a physical iPhone. Nothing has run on a device yet. No
   alarm has ever fired in the real world.
2. **App Store publication gates** (full table in `docs/APP_READINESS_REVIEW.md`): a hosted privacy
   policy and support page (drafts in `docs/release/`) and their links in Settings and App Store
   Connect; the Lifetime product configured and tested against a signed release (purchase, cancel,
   pending, restore, refund, offline launch); the privacy questionnaire and final privacy manifest;
   screenshots and age rating; the final icon; the signed archive; accessibility reports that CI
   cannot settle.
3. **Saved workouts, Progress tab and Library** (merged from `review-workouts-progress-library`):
   read the new snapshot images from the macOS run, then decide the open items listed in the
   2026-11-18 entry of `.agents/HANDOFF.md`. Notably imported Strong or Hevy history does not appear
   on Progress, a hand-built workout cannot pin a machine, and single-exercise history replays every
   session for record stars.
4. **Review leftovers** (2026-11-19 entry): UI-test data shared between journeys, four `.sheet`
   modifiers on one anchor needing a device look, the staged tour's VoiceOver behaviour.
5. **Branch triage.** Many older branches and worktrees remain. They belong to the owner to triage;
   do not merge, rebase or delete them as part of other work.

Deliberately not next: the progression prescription engine, the full catalogue, iCloud sync (needs a
paid team, entitlements, a local-only backfill review and two-device testing).

## 7. Invariants — load-bearing, each one is a bug the ancestor app shipped

1. **A set that is not complete cannot be written.** `LoggerStore.logSet` takes a `SetEntryDraft`
   and goes through `resolved()`. There is no overload accepting a bare weight. Zero added load
   with real reps is valid.
2. **Duration is derived, never stored.** Sessions carry immutable `startedAt` and `finishedAt`.
   `SessionTimeline` refuses to re-finish or to finish before the start.
3. **The logger does zero database work per render.** History is hoisted into one immutable
   `PriorPerformanceSnapshot` at session start, which holds no database handle.
4. **Persist before claiming.** `SessionCoordinator.logSet` marks a row logged and starts rest only
   after the write succeeds.
5. **Records must beat something by a real margin.** The greater of 2.5% and one plate increment.
   Repeating last week is not a record.
6. **No neutral fallback, ever.** `Claim<Value>` cannot hold a value while claiming `.unevaluated`.
7. **Muscle raw values are permanent.** Adding a token is cheap; renaming or removing one is
   impossible once a build reaches a second device. A test pins all 22.
8. **Grip and bracing are `stabilizer`, weight 0.** Never `indirect`.
9. **Group volume counts sets once; it never sums members.**
10. **Machine series are never merged.** One line through two different leg presses draws progress
    the lifter did not make.
11. **A session copies its plan when it starts and never reads the template back,** so editing or
    archiving a saved workout cannot rewrite history.

## 8. Three refusals that look like missing features

Do not "fix" these. Each is the app declining to assert something unsupported, and each is tested.

- **No weekly set targets.** `VolumeAnalyzer.weeklyTarget` returns `.unevaluated` for every muscle.
  The literature gives a dose-response relationship, not targets.
- **No default rest duration.** Rest starts only from a length the lifter chose for that movement.
- **No default program.** "Start workout" starts empty; saved workouts are the lifter's own.

The 0.5 indirect-set credit is an adopted convention, not an inherited finding, and
`SetCounting.source.methodology` says so. Never claim entitlement to the number.

## 9. Traps that cost build cycles

- **`#expect` cannot take a `rethrows`, `try` or `await` call.** Hoist to a `let` first. A
  mutating call cannot sit inside `#expect`.
- **StructuredQueries needs `#bind`** around values assigned in `.update { }`, for literals and
  optional columns.
- **`swift build --target X` can report `complete!` having compiled nothing.** After adding files,
  confirm the compiler names them.
- **`swiftc -typecheck` gives false all-clears on concurrency.** Use `-c` or a real build.
- **Module default isolation leaks into extensions and function references.** `HardsetStore` and
  `HardsetUI` default to `MainActor`; mark storage-touching types `nonisolated`.
- **Public API must not return the `@Table` row types.** Their column names are frozen. Use the
  record types.
- **`ExerciseCatalog.swift` is machine-generated** and overwritten wholesale. Never hand-edit it;
  `CatalogEntry` lives in its own file for that reason.
- **iOS-only APIs need `#if os(iOS)`:** CI also builds the package for macOS, and SwiftUI compile
  errors surface only there.
- **The workflow cancels in-progress runs per ref.** A second push to the same branch cancels the
  first run; a cancelled run is not a green run.
- **The UI pass can fail on a "Busy" launch.** The simulator sometimes refuses the first launch while
  the app's install is finishing (run 44648846716). The workflow retries a failing UI test once
  (`-retry-tests-on-failure`); a test that fails both attempts is real.
- **A refused launch of the UI runner is waited out and retried.** "Application ...xctrunner is
  installing or uninstalling, and cannot be launched" (Busy) came from the simulator, not the app
  or the tests, and cost whole runs. `ui_xcodebuild` in `Tools/ui_launch.sh` lets the device settle
  before each `test-without-building`, and when that exact refusal comes back before any test of
  the invocation started it waits and launches the same invocation again, three attempts in all,
  printing one `::warning` line per retry that names the test. An invocation in which a test
  started is never retried by it, so an assertion failure stays one. `scripts/test_ui_launch.py`
  covers the logic offline; whether a real simulator stops refusing is shown only by a macOS run,
  and none has been seen yet. Count retries across runs with
  `gh run view <id> --log | rg -c "launch denied on attempt"`.
- **Each pass's result gates the job.** The dark and light checks at the end of the UI step were one
  `a && b` line, and under `bash -e` a failed first grep of such a line stops nothing, so once the
  reverse-order result followed it a dark pass that never succeeded failed no job. They are separate
  checks now (`PASSES_FAILED`).
- **`-retry-tests-on-failure` can turn a failing test green.** Runs 44969910828 and 44973199974 were
  green although `testCorrectionsAndDiscardDark` failed assertions in iteration 1 and passed in
  iteration 2. Left as it was; removing the flag is a decision about how strict the UI job is.
- **SourceKit reports "No such module" constantly.** It is noise; trust the build.

## 10. How to work

- Run `git status -s` and read this file and `.agents/HANDOFF.md` before editing. Treat unexplained
  changes as someone else's work.
- Commits are authored `FrankieBiz <frankabisignano@gmail.com>`, with no AI names and no co-author
  trailers. Delivery is a short-lived branch and a pull request, merged after the native run on the
  pushed commit is green. See `AGENTS.md` for the finish protocol and model tiers.
- Cite primary sources. In this project's research corpus about 32 of 56 audited claims were
  refuted, almost always by over-reading a real study. For Apple APIs read the SDK, not memory.
- Say plainly what you verified and what you did not.
