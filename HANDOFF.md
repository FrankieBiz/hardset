# Hardset — handoff

You are taking over an iOS 26 hypertrophy-logging app mid-build. This file is the whole briefing.
Read it before touching anything. Everything it claims is verifiable from the repo.

---

## 0. Where the code lives

`/Users/frankbisignano/dev/hardset`, on a git remote at `github.com/FrankieBiz/hardset`. An earlier
version of this file opened with a rescue procedure for a repo sitting in a session temp directory;
that move happened long ago and the instruction is gone. If you ever do find this repo under
`/private/tmp/` again, `rsync -a` it out before touching anything.

Work happens on feature branches. `main` is well behind — check `git log --oneline main..HEAD`
before assuming anything about it.

---

## 1. What this is

A single-purpose hypertrophy logger for intermediate lifters who read the training literature.
Three differentiators, in priority order:

1. **Calibrated honesty.** Every number carries a certainty and a source, and the app says
   "unevaluated" rather than inventing a value it cannot justify. This is enforced by types, not by
   discipline.
2. **Machine-level awareness.** Load history is keyed to exercise × *specific machine*. 80 kg on a
   Hammer Strength leg press is tracked separately from 80 kg on a Cybex.
3. **Logging craft.** One tap per set, a rest timer that survives Focus and force-quit.

Not a coach, not a social network, no feed, no streaks, no nutrition. No Apple Watch app in v1.

There is an ancestor app at `/Users/frankbisignano/dev/elos/apps/elos-mobile/Elos/Elos` — **read
only, never edit it.** It is the design ancestor and the source of most of the cautionary tales
below.

---

## 2. Build and test

```bash
cd Packages/HardsetKit && swift test --disable-sandbox
```

Or `./test.sh` from the repo root, which also runs five tests that need isolated processes.
**Latest verified state (September 8, 2026): 774 tests passed.** `./test.sh` reports 769 in
its main run plus five isolated tests. Prefer `./test.sh` — a bare `swift test` occasionally fails the `SyncEngine` suites on
metadatabase contention, which is the whole reason the script exists.

### Compile-checking the iOS-only target from here

`HardsetAlarm` sits behind `#if canImport(AlarmKit)`, so on macOS the target compiles to *nothing*
and the suite says nothing whatever about it -- §7 is still right about that, and no test here can
run it. It can, however, be **compile-checked** from this sandboxed command line, which is worth
doing after every edit to it:

```bash
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
OUT=$TMPDIR/iosmod && mkdir -p "$OUT"
FLAGS=(-target arm64-apple-ios26.1-simulator -sdk "$SDK" -swift-version 6 \
  -enable-upcoming-feature NonisolatedNonsendingByDefault -disable-sandbox -package-name hardsetkit)
swiftc -emit-module -emit-module-path "$OUT/HardsetCore.swiftmodule" -module-name HardsetCore \
  "${FLAGS[@]}" $(find Packages/HardsetKit/Sources/HardsetCore -name '*.swift')
swiftc -c -wmo -module-name HardsetAlarm "${FLAGS[@]}" -default-isolation MainActor \
  -warnings-as-errors -I "$OUT" -o "$OUT/HardsetAlarm.o" \
  $(find Packages/HardsetKit/Sources/HardsetAlarm -name '*.swift')
```

Three details are load-bearing, and each one is why this looked impossible before:

- **`-disable-sandbox`.** Without it the Swift macro plugin server dies with
  `sandbox-exec: sandbox_apply: Operation not permitted` -- it cannot nest a sandbox inside this
  one -- and every `@Observable` member then reports `external macro implementation type
  'ObservationMacros.ObservableMacro' could not be found`. Two dozen identical errors that read
  exactly like a code defect and are not one. This is the flag `swift test --disable-sandbox`
  already passes, which is why the host suite never hit it.
- **`-package-name hardsetkit`.** Without it the compiler treats `HardsetCore` as a foreign module
  and warns that `extension RestMetadata: AlarmMetadata` needs `@retroactive` -- which
  `-warnings-as-errors` turns into a failure. The warning is an artefact of the invocation, not a
  defect; `RestMetadata+AlarmKit.swift` records why the attribute does not apply. Do not "fix" the
  code to satisfy a mis-configured compile.
- **No `-default-isolation MainActor` for `HardsetCore`.** It is deliberately nonisolated (see
  Package.swift), and forcing MainActor on it produces a cascade of bogus `IsolatedConformances`
  errors about types that are fine.

The full Xcode project now builds from the command line. On September 8, 2026, an unsigned generic
iOS Simulator Release build completed with Xcode 26.4, and two selected UI tests passed on the
iPhone 17 Pro simulator. The direct `swiftc` commands remain useful for a fast, isolated AlarmKit
compile check. Neither path proves an alarm fired; `DEVICE-CHECKLIST.md` §B remains that gate.

Everything with behaviour lives in `Packages/HardsetKit` and builds on macOS. That is deliberate —
see §7.

---

## 3. Locked decisions — implement these, do not re-litigate

| Area | Decision |
|---|---|
| Min deployment | iOS 26.1 (the non-deprecated `AlarmPresentation.Alert` init is 26.1-only) |
| Concurrency | Swift 6, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, approachable concurrency on. `HardsetCore` is deliberately `nonisolated` |
| Local store | GRDB + SQLiteData (not SwiftData) |
| Sync | CloudKit private database via `CKSyncEngine`. **No backend for user data in v1** |
| Accounts | None required. Sign in with Apple only at second-device/restore |
| Payments | StoreKit 2 + RevenueCat; on-device `currentEntitlements` primary |
| Rest timer | AlarmKit |
| Watch | Not in v1. `SessionEngine` seam kept so it is additive later |
| Price | $3.99/mo founding (grandfathered) → $8.99 standing; $29.99/yr founding |
| Exercise art | None per-exercise. One commissioned body outline, muscles highlighted from our own data |
| Experience level | Inferred, default intermediate, with a visible "assumes intermediate" correction chip |

Two decisions the user has **not** made, so do not assume either way: whether the founding-price
structure ships, and who authors the ~240-exercise catalogue.

---

## 4. Architecture

```
Hardset.xcodeproj            generated by Tools/generate_project.py — do not hand-edit
Hardset/HardsetApp.swift     ~136 lines, pure wiring, compiled for simulator and device (see §7)
HardsetWidget/               widget extension (required: AlarmAttributes is an ActivityAttributes)
Packages/HardsetKit/
  HardsetCore     Foundation-only, nonisolated. Engine, taxonomy, value types. Tests on host.
  HardsetAlarm    iOS-only. AlarmKit conformance + rest-timer controller.
  HardsetStore    GRDB/SQLiteData. Schema, migrations, sync, all queries.
  HardsetUI       Design tokens + every view. Depends on Core ONLY, never on Store.
  HardsetFeature  Composition root. Depends on Core + Store + UI + SQLiteData.
docs/SPLITS-spec.md          plans: what they are, and the four quality axes that do not exist
docs/SUPERSETS-spec.md       supersets and drop sets: one rest rule, and why a drop adds no set
Tools/generate_icon.py       the app icon, derived from the locked palette rather than drawn
Tools/seed_history.py        twenty weeks of training, for judging any progress surface (#45)
docs/GYM-TEST.md             how to sign, install and what to actually test on a real phone
docs/MACHINES-spec.md        your own machines and movements: what already works, and the 5 gaps
docs/MuscleTaxonomy-spec.md  the taxonomy specification, implemented
docs/research/               the full research corpus (~1.2MB) — grep it, do not read it whole
DECISIONS.md                 21 numbered decisions of record. READ THIS.
DEVICE-CHECKLIST.md          the on-device gate. Nothing here has run on a device.
```

---

## 5. Invariants — these are load-bearing, and each one is a bug the ancestor shipped

Break any of these and you reintroduce a defect that reached real users.

1. **A set that is not complete cannot be written.** `LoggerStore.logSet` takes a `SetEntryDraft`
   and goes through `resolved()`. There is no overload accepting a bare weight. The ancestor
   accepted an empty weight field and persisted 0 kg, so a row visibly reading "60" contributed no
   volume. Zero *added load* with real reps is valid — bodyweight work is a real set.
2. **Duration is derived, never stored.** Sessions carry immutable `startedAt`/`finishedAt`.
   `SessionTimeline` refuses to re-finish or to finish before the start. The ancestor recomputed
   duration from `Date()` at render time and shipped 9,749-minute workouts.
3. **The logger does zero database work per render.** History is hoisted into one immutable
   `PriorPerformanceSnapshot` at session start. It holds no database handle, so per-render querying
   is unrepresentable. The ancestor ran ~30 unbounded queries per second.
4. **Persist before claiming.** `SessionCoordinator.logSet` marks a row logged and starts rest
   *only after* the write succeeds. A check mark on an unsaved set is a lie about someone's training.
5. **Records must beat something by a real margin.** The greater of 2.5% and one plate increment.
   The ancestor fired on `>=`, so repeating last week announced a PR.
6. **No neutral fallback, ever.** `Claim<Value>` cannot hold a value while claiming
   `.unevaluated`. The ancestor's scorers returned 70 when they recognised nothing, so three
   unknown lifts composed into a confident "78/100 — Dialed in".
7. **Muscle raw values are permanent.** Adding a token is cheap; renaming or removing one is
   impossible once a build reaches a second device. A test pins all 22.
8. **Grip and bracing are `stabilizer`, weight 0.** Never `indirect`. I got this wrong first time
   and it would have invented ~5 sets of forearm work per 12 sets of pulling.
9. **Group volume counts sets once; it never sums members.** Summing fractional credits across a
   group triple-counts a bench press.
10. **Machine series are never merged.** One line through two different leg presses draws progress
    the lifter did not make.
11. **A drop set adds no set, and every count agrees about that.** A drop is counted as part of the
    set it continues; its load and reps still count in full toward tonnage. The trap is that a
    *row* count and a *set* count are no longer the same number, and three surfaces got it wrong
    before anyone noticed — see §8d. `SetKind.countsAsWorkingSet` is the one predicate; use
    `loggedWorkingSetCount`, never `loggedCount`, wherever the word "set" reaches the screen.
12. **Drops never reach history, records or the chart.** A drop is the lightest load of the session
    by construction, so a drop in `priorPerformanceSnapshot` makes next week's opening row lighter
    every time the lifter trains hard. Excluded in SQL in all three queries.

---

## 6. Three refusals that will look like missing features

Do not "fix" these. Each is the app declining to assert something unsupported, and each is tested.

- **No weekly set targets.** `VolumeAnalyzer.weeklyTarget` returns `.unevaluated` for every muscle.
  No per-muscle weekly target is established: the literature gives a dose-response relationship for
  eight measured sites, not targets; the ancestor's bands were uncited practitioner numbers; and the
  ~4-fractional-set figure often quoted as a minimum is the volume at which modelled gain first
  exceeds the smallest detectable effect size — a detectability artefact, not a biological floor.
  The function exists so future warning code can only iterate *evaluated* targets, which makes
  "warn with no target" unrepresentable.
- **No default rest duration**, and it cannot be learned either. `restAfterSet` is nil unless a
  caller supplies one. A 2026 teardown proposed learning one from the lifter's own median rest,
  which would have been sound -- except the app does not record rest. `loggedSets` carries only
  `completedAt`, so the one derivable interval is finish-to-finish, which is `rest + work(N+1)`;
  the set itself is 25-40 s against a 60-180 s rest, so that median overstates rest by a fifth to a
  third and a timer set to it fires after the lifter would have finished the next set. DECISIONS
  #27 has the arithmetic. The underlying defect is still real and still open: `restSeconds`
  defaults to `0` and lives only in Settings, so the flagship feature does not start itself.
- **No default program.** "Start workout" starts empty. There is no generator, and inventing a
  plan would assert a prescription the app does not have.

Also: the 0.5 indirect-set credit is an **adopted convention, not an inherited finding**. Pelland
et al. fixed it a priori and compared three fixed schemes; their own discussion calls it "an
assumption" and "a heuristic". `SetCounting.source.methodology` says so in the text App Review
reads, and a test asserts it keeps saying so. Never claim entitlement to the number.

---

## 7. What remains unverified — be honest about this

**A signed Release build now runs on a physical device.** On 2026-08-25 the local-only app and widget
built, installed, and launched on an iPhone 18,3 running iOS 26.6. That proves compilation, signing,
embedding, installation and process launch. It does not prove the product claim: no AlarmKit alarm
has yet been observed firing on hardware, and the local-only build omits CloudKit and push
entitlements, so no CloudKit sync has happened. `DEVICE-CHECKLIST.md` remains the gate; its
force-quit and Focus-breakthrough lines are where the flagship feature actually gets proven.

**The app target builds for both simulator and device.** It had never compiled until commit
`6531c44`; see `DEVICE-CHECKLIST.md` §A for the original four causes. The verified hardware path is
a Release `xcodebuild` with automatic provisioning after generating a local signing configuration.
Use `docs/GYM-TEST.md`; in particular, read the Team ID from the certificate subject's `OU` and
leave enough disk space for a clean build.

Consequence that still holds: everything real was deliberately put in package targets.
`HardsetApp.swift` is ~136 lines of wiring with no logic. **Keep it that way** — anything you add
there that a test could cover belongs in the package. And `HardsetTests` (the app-target test bundle)
still cannot be compiled here at all, because the MCP tool builds for running, not testing.

**Anything behind `#if canImport(AlarmKit)` is invisible to the host suite.** `HardsetAlarm` once
carried a hard compile error that no `swift test` run could ever have caught. Treat "the package
tests pass" as saying nothing whatsoever about iOS-only code.

**Run the app.** Nearly every real defect in this repo was found by driving a screen, not by reading
one — see §8's splits entry for five more. Seed the simulator database directly (python3 + sqlite3,
registering a `uuid()` function first, since the table defaults call GRDB's) to get realistic history
on screen in seconds.

## 8. Next steps, in order

**Items 1-4 of the previous list have shipped** — machine selection is wired into the workout, gyms
and machines have screens, `ProgressionChartView` is reachable through `ExerciseProgressScreen`, and
the unit picker exists. `DEVICE-CHECKLIST.md` §A2 records the simulator walkthrough that proved it.

The live sequence:

1. **The device interaction gate.** The Release build, signing, install and launch portion of §A is
   closed. Work §B on the phone next. Nothing about AlarmKit is proven until those checks close: no
   alarm has yet been observed firing on hardware.
2. **DONE — a post-workout summary screen.** `SessionSummaryView` plus `SessionSummaryScreen`,
   with `SessionOutcome` in the engine. Finishing used to only clear the coordinator, so a workout
   ended in silence. Read-only over existing tables, so no schema risk.

   One correction worth recording: an earlier version of this list claimed
   `PersonalRecordDetector` was referenced by no view and that nobody had ever seen a record. That
   was wrong — `SessionView` has rendered per-set records all along. The claim came from a grep
   piped through `head`, read as if it were exhaustive. What was genuinely missing was
   session-level aggregation (`SessionCoordinator.sessionRecords`) and any summary at all.
3. **DONE — history opens a workout.** `HistoryStore.sets(in:)`, `SessionDetailView`,
   `SessionDetailScreen`. `HistoryView` had always taken an `onSelect` and nothing passed one, so
   every row was a disabled button and the app could tell you a session happened but not what was
   in it. The row's hit area was also only its glyphs, with no `contentShape`.

4. **DONE — supersets and drop sets.** The logger's two missing shapes, and the largest
   functional gap against Strong and Hevy. `docs/SUPERSETS-spec.md` is the spec; DECISIONS #25 and
   #26 record why they are permissible in an app that refuses to prescribe (they change *when rest
   is armed*, nothing else) and why a drop adds no set. Two additive columns in the v1 migration,
   `SetKind` and `SupersetRest` in Core, and one letter chip plus one button in the UI.

   Three things worth carrying forward. **The research corpus said defer drop sets and its reason
   does not apply here** — it cites the Alpha Progression complaint that auto-advance blocks them,
   and this app has no auto-advance. **The corpus also proposed pre-modelling `amrap`/`backoff`;
   that was refused** as speculative, because #4 lets a column be added at any time and never
   removed, so an unbuilt case defers for free. And **three surfaces reported drops as sets** — see
   §8d, which is the pattern, not a one-off.

5. **DONE — plans.** A split in this app is a *partition of movements the lifter already trains*
   across days they chose, not a program. `docs/SPLITS-spec.md` is the spec; read its §1 before
   entertaining any request for a "balanced split" or a plan rating, because the four candidate
   quality axes are each closed off by a number in `SplitCalibrationProbe`. Three tables (added to
   the v1 migration, deliberately with **no** set-count column), `SplitDealer` and
   `SplitPlanAssessment` in Core, `SplitStore`, and a fourth tab.

   Two things worth carrying forward. **A plan has no set counts, so it has no volume** — plan-level
   figures count *movements* and *days*, and `MuscleVolumeReport` stays for logged weeks; running a
   plan through `VolumeAnalyzer` would require inventing a set count per movement. And **naming a
   machine in a plan writes `machineExercises`**, which is what lets the picker know a gym has
   equipment for a movement before anything is logged there.

   A day starts as today's workout (`SplitStore.plannedExercises(for:)` -> the existing
   `SessionCoordinator.start`), which is what keeps the planner from being a document. Every
   `plannedSets` is nil; the rows the logger opens with come from the lifter's own history, not from
   the plan.

   Five defects were found by running the screen and none by the suite: an empty plan whose own copy
   promised to deal your logged movements while the button read from the empty plan and did nothing;
   "1 days"; day subtitles ranked by group touches so a chest day read "Arms · Legs · Shoulders";
   an unscoped "Fewest movements" label; and a machine sheet filing the whole gym under "You've used
   these". This is the pattern, not a one-off.

6. **DONE — the submittable pass.** An audit against the submission gates and against what an app
   of this kind is expected to have. Read `DEVICE-CHECKLIST.md` §E before doing any of it again:
   it is now split into what is blocked on the account holder (most of it), what is done, and what
   is still to build.

   Fixed here, and each was a real gap: **no app icon at all** (a hard upload blocker — now
   generated by `Tools/generate_icon.py`, DECISIONS #28); **the launch screen and system chrome
   were not dark**, so a dark-only app flashed white on any device in light mode (#29); **no data
   export** (#30); **no single place disclosing every derived number** (#31); and `AccentColor` was
   still Xcode's default blue, contradicting #22 outright.

   Two traps worth carrying. `PrivacyInfo.xcprivacy` is now **verified present at the built
   bundle's root**, not just in the source tree — checklist §D asked for that and nobody had
   looked. And nothing invents a legal URL: `LegalLinks.live` holds `nil`, rows render only when
   set, because App Review taps every link and a 404 is slower to recover from than a missing
   feature (#32).

7. **NEXT — finish the device interaction gate.** `docs/GYM-TEST.md` is the procedure. The
   local-only Release build is already installed and launches; work §5 of that doc on the phone.

   What is being proven is §B of `DEVICE-CHECKLIST.md` and nothing in this repo can substitute for
   it: **no AlarmKit alarm has ever fired on hardware**. The four that matter are fires-at-all,
   fires-backgrounded-and-locked, fires-through-silent-and-Focus, and survives-force-quit.

   The first-run rest prompt (#33) exists so this is testable at all — before it, a fresh install
   never asked for AlarmKit permission, so the timer could not have alerted even if everything
   else was right.

8. **Motion**, in the order the hero moments' hosts become stable: set-log recede, then the rest
   timer, then the summary choreography, then chart draw-on. `docs/UI-GUIDELINES.md` §5 specifies
   all four; `Tokens.Motion` already holds the vocabulary.

Deliberately **not** next, and why: motion before the device gate (haptic-and-pixel co-timing and
the 100 ms acknowledgement budget are unjudgeable in a simulator, so it would be tuned twice); the
rest-timer arc before AlarmKit is proven (do not decorate an unverified timer); subscriptions
(nothing to sell until the app runs on hardware); the 240-exercise catalogue (content work, and a
decision the user has not made).

One thing to cut rather than build: the glass morph from the set-log control into the rest bar. It
is the flashiest item in the guidelines, it is tunable only on a device, and it sits on the hottest
path in the app at forty times a session.

## 8a. Ideas taken from the ancestor, and ideas deliberately refused

The ancestor app at `~/dev/elos` is the design ancestor. Some of its ideas were genuinely good and
are worth carrying; several are incompatible with this app's refusals and must not be reintroduced
by a future session that finds them in the Elos code and assumes they were an oversight.

**Carried, and central.**
- **Per-machine load tracking.** The differentiator. 80 kg on a Hammer Strength is not 80 kg on a
  Cybex, and no series ever merges them.
- **Relevance in the exercise picker.** Elos called it smart sort, and its own research concluded
  the defensible version ranks by the equipment a gym actually has -- which needed a
  machine-to-exercise join Elos did not have. This app had the table from its first migration and
  had never written to it; it does now.
- **Muscle attribution as a precedence chain** with roles, certainty and a source per contribution,
  rather than a flat "works these muscles" list.
- **Design tokens as the theming seam.** Elos learned this the expensive way. Here it meant the
  entire palette landed as a one-file change across ~270 call sites.
- **One canonical unit, converted only at the edges.** Kilograms stored, display converted.
- **Gyms owning machines**, but learned by naming equipment at the rack rather than through a setup
  flow nobody completes.

**Refused, on purpose.**
- **A composite 0-100 quality or readiness score.** `Claim` makes it unrepresentable. Elos scored a
  session 78/100 "Dialed in" with three exercises it could not attribute at all.
- **Weekly per-muscle set targets and fatigue bands.** No such target is established; see
  DECISIONS #19. Bars are comparative, never evaluative.
- **Auto-fix and program generation.** There is no prescription engine and inventing one would
  assert what the app cannot support.
- **Bundled how-to photographs.** The free-exercise-db images Elos shipped are not licensed for it;
  the repo's Unlicense never covered the scraped photos.
- **Streaks, a feed, and social.**

**Known limit, deliberate.** Tonnage for a bodyweight set counts added load only, so a session of
pull-ups reports close to zero volume. Converting bodyweight into a load would need a per-exercise
fraction of the lifter's mass -- a pull-up is not a push-up -- and no such figure is established
here. Set counts and per-muscle volume are unaffected, and the summary's hero number is working
sets rather than tonnage, so nothing on screen is wrong; it is simply narrower than it looks.
Recording bodyweight (`bodyweightEntries` exists, deliberately unsynced per DECISIONS #5) is the
prerequisite if that ever changes.

**Worth taking later, in this order.**
1. **How-to text** -- instructions without the unlicensed imagery. Cheap, useful, and it needs a
   licence decision rather than engineering.
2. **Per-machine progression suggestion.** Only after the device gate proves the logger; a
   suggestion engine on an unverified foundation is the wrong order.

## 8b. The one place the app is not append-only

`LoggerStore.deleteSet` is the single mutation that removes user data, and
`SessionCoordinator.unlogSet` is its only caller. It exists because the alternative is worse: with
no way back, a mistyped 500 kg is a permanent personal record, a permanent spike in the progression
chart and a permanently wrong week, in an app whose entire claim is that its numbers can be trusted.

It deletes hard rather than flagging, because volume, tonnage, the chart, records and history are
all derived by *reading* those rows -- a flagged set keeps contributing unless every reader learns
about the flag, and one that forgets is a silent wrong number. SQLiteData propagates the deletion
through CloudKit as a tombstone.

It deletes **before** it forgets, mirroring `logSet` persisting before it claims. A row still in the
database with the check mark gone from the screen is the same class of disagreement.

**Known limit:** records already announced during a session are not retracted when a set is taken
back. They were computed against the history that existed at the time, and undoing one correctly
means recomputing every record in the session against a changed past. That is its own piece of work.
Everything read from the rows -- volume, tonnage, chart, history -- is correct again immediately.

## 8c. Dead schema columns, audited

Swept every column against its readers and writers. Two are genuinely dead and should either be
used or removed before the schema is frozen at ship -- remember DECISIONS #4: SQLiteData forbids
removing or renaming a column forever once a build reaches a second device.

**This list was stale in the repo's favour and has been corrected against the source.**
`machines.loadType` is **gone from the schema entirely** -- only a comment at `Schema.swift:49`
records that it existed. `exercises.notes` **is wired**, through `setExerciseNotes` and the
movement-note editor. `bodyweightEntries` **has a store and a screen** (`BodyweightStore`,
`BodyweightScreen`). `machines.stackIncrementKg` has a real input path at `GymStore.swift:101`.
What remains genuinely dead:
- **`machines.brand`** -- written as `""` and read once. In practice lifters type the brand into the
  name ("Hammer Strength"), which is why the field never earned its keep.
- **`deviceHealthSamples`** -- no code beyond the schema, and intentionally so. HealthKit is out
  of v1, and it must **stay** out of any synchronized table: App Review 5.1.3 forbids storing
  personal health information in iCloud, and CloudKit is the only sync transport here.

Fixed in this pass: **`sessions.title`** was read in 23 places and written in none, so every workout
was nameless and history could only show a date.

## 8d. A row count is not a set count, and three surfaces got it wrong

Found by seeding a database and driving the screen, not by the suite -- which stayed green through
all of it, because before drop sets existed the two numbers were always equal.

- **The live workout bar** summed `loggedCount` across movements, so a lifter who dropped twice
  watched "3 sets logged" become "5". The most visible number in a live workout, contradicting the
  app's own counting convention.
- **A past workout's headline** counted every non-warm-up row, so a drop chain read as three
  working sets on the history screen while the volume report for the same week said one.
- **A movement's progress line** counted logged *rows* against working *sets*, so one drop produced
  "4 of 3 logged" -- a progress figure overshooting its own total.

The rule that prevents the next one: `loggedCount` is a count of **records** and belongs only where
the question is how much data an action destroys. Anywhere the word "set" reaches a user, count with
`countsAsWorkingSet`.

**A fourth, older bug fell out of the same audit.** `ExerciseLogState.resume` compared written *rows*
against expected working *sets* (`max(state.slots.count, slots.count)` against `workingLogged`) --
two different units. Every warm-up already logged therefore added one phantom open row to a
recovered movement: log a warm-up and three working sets, force-quit, and the workout came back
asking for a fourth. That predates supersets and drops entirely and had been shipping since recovery
was written. `ResumeRowCountTests` pins both halves.

## 8e. The long-term audit: what a lifter sees after five months

Seeded 60 finished sessions across 20 weeks (3/week, an Upper/Lower split, real progressive
overload, machines at one gym) and drove every progress surface. The technique matters more than
the result: **none of these are visible with a week of data**, which is all anyone had ever put in
front of this app.

**What holds up.** The progression chart is the strongest thing in the app — twenty weeks of Leg
Press rendered as a clean stepped line with a month axis, a Heaviest-load / Est-1RM toggle, and
per-machine series. It reads `samples(for:limit: 2000)`, so it is **not** subject to the history
cap below. Session detail is exactly what "what did I do that session" needs: per movement, the
machine's name, and every set as load x reps x RPE. The split loop compounds properly — a day's
row count and prefills come from *history*, not the plan, so the same split gets more useful the
longer it is used.

**Fixed here: history truncated silently at fifty workouts.** `recentSessions()` defaulted to
`limit: 50` and `HistoryScreen` passed nothing. With 60 sessions written, **10 sessions and 75
logged sets were in the database and unreachable** — no footer, no count, no way back. At three
sessions a week that is the fourth month, and it looks exactly like data loss. Now paged:
`HistoryScreen.pageSize` = 50, a "Show older workouts" footer, and the footer is `nil` when a read
comes back short of a page, so its absence means "nothing older exists" rather than "we stopped".

**All three of the items this section left open are now closed.** See §8f.

## 8f. Closing 8e, and the four defects that closing it exposed

Seed with `Tools/seed_history.py` (DECISIONS #45) before judging any of this — it writes sixty
sessions across twenty weeks and re-resolves the container path each run. Everything below was found
by reading the screen, not by the suite, which stayed green throughout.

**§8e items 1 and 2 shipped.** The volume tab has a seven-day window navigator over
`report(in:)`/`SevenDayWindow`, and `ProgressionBrowserScreen` gives the chart a browse entry point
from History's toolbar, listing every movement with working-set history. Both also moved their reads
off the main actor (`readOffMain`), because a twenty-week report is not a transition-time query.

**§8e item 3 shipped, and needed a schema column after all.** That entry claimed rotation was
"derivable from `sessions` today". It is not, honestly: nothing linked a session to the day it came
from, so deriving it means matching movements back onto a plan, which is a guess. `startPlannedDay`
was also **dropping the day's identity one hop before the session** — the shape §8c warns about.
`sessions.splitDayID` is now written, and `SplitRotation` decides which day has waited longest.
DECISIONS #41.

**Four defects fell out of closing it, three of them only visible on screen:**

1. **"Last trained last week" for both a ten-day and a seven-day gap.** The system's named relative
   format collapses days 7–13, which is the exact range a weekly split lives in, so the two days a
   lifter chooses between read identically. `TrainingRecency` (#42) counts days to thirteen. The
   progression browser had the same phrasing and was moved onto it.
2. **The week navigator paged backwards forever** into empty windows, making "Nothing logged"
   ambiguous between a rest week and a week before you started. Bounded by
   `earliestCountableSet` (#43) — filtered exactly as `countableSets` is, because a floor counting
   warm-ups offered a window the screen could only render as "0 working sets".
3. **Every workout the app started was nameless.** `start` accepted a `title` and no caller passed
   one, so history could label a plan day only with its date (#44).
4. **`start` wrote the title to the row but not to the coordinator**, while `resume` reads it back —
   so a named workout showed "Name this workout" until a force-quit made the name appear. Latent
   while nothing passed a title. Found by writing the test for #44, not by the screen.

**Still open here**, and deliberately: starting a day directly from the Train tab. The tab now says
a plan exists and moves to it (`hasStartableDay`), because the day list would need *which plan is
selected* — today plain `@State` in `SplitPlannerScreen` — and copying that choice into a second
screen is how two screens come to disagree. Hoist that selection first, then the Train tab can offer
the days themselves.

## 8g. Perfecting the plan system

Read `docs/SPLITS-spec.md` §7 and DECISIONS #46–51. The pass took the planner from "an arrangement you
can edit" to "a record of decisions the app may rearrange but not discard". Everything below was found
by reading the screen against `Tools/seed_history.py --second-gym`, not by the suite.

**The severe one, proven on device: a plan's machines leaked across gyms.** A machine belongs to one
gym; a plan does not. `plannedExercises` took no gym, so starting a plan built at Iron Works while
standing in Downtown Barbell opened all four rows bound to *Iron Works* machines and showed their load
history as the equipment in front of you — four `MISMATCH`, silently writing into a machine series the
lifter never touched. Now reconciled per movement (#46), and it composes with the existing disclosure:
a resolved row reads "From another machine", so the prefill is never passed off as this machine's.

**Re-dealing was a reset, not a rearrangement** (#47). `replace` wrote `machineID: nil` and took day
names from the dealer, so one tap discarded every machine named and renamed Push/Pull/Legs to
Day 1/2/3, with no undo and a confirmation that mentioned neither.

**Shipped, each closing a gap the store already half-supported:** the lifter's own intended set counts
(#48) reaching the logger through machinery that already existed; ordering within a day *and* between
days (#49) — `moveEntry` had always taken a position and nothing passed one, and `moveDay` did not
exist; the days-credited readout (#49) from a `creditingDays` that had no consumer; and retired
movements reported rather than removed (#50).

**Two traps worth carrying.** Adding the retired marker exposed that the planner built rows only from
`selectableExercises()`, so a retired movement rendered as "Unknown movement / Not attributed" —
naming what is already there is a different question from offering something new. And **v1 is
immutable**: both new columns were first added by editing v1's `CREATE TABLE`, which only makes fresh
installs pass `SchemaTests` while an installed database never gets the column. See #51 — including that
an `ALTER TABLE` column sorts **last** in the pinned inventory.

## 9. Traps that cost me build cycles — do not rediscover these

- **`#expect` cannot take a `rethrows` call.** `#expect(xs.allSatisfy(...))` fails to compile.
  Hoist to a `let` first.
- **StructuredQueries needs `#bind`** around values assigned in `.update { }` — for literals *and*
  optional columns. Variables into non-optional columns are fine, which makes the rule easy to
  half-learn.
- **`swift build --target X` lies.** It reports `complete!` at `[0/1]` having compiled nothing.
  After adding files, `touch` the sources and confirm the compiler names them.
- **`swiftc -typecheck` gives false all-clears on concurrency.** Region-based isolation is enforced
  in SIL; use `-c` or a real build.
- **Module default isolation leaks into extensions and function references.** `HardsetStore` and
  `HardsetUI` default to `MainActor`, so passing `Type.init(row:)` as a function value into a
  nonisolated closure fails. Mark storage-touching types `nonisolated`.
- **Public API must not return the `@Table` row types.** They are internal and their column names
  are frozen. Use the record types (`SessionRecord`, `LoggedSetRecord`, `CatalogEntry`, …).
- **`ExerciseCatalog.swift` is machine-generated** and gets overwritten wholesale. Never hand-edit
  it; anything hand-written there is one regeneration from gone. `CatalogEntry` lives in its own
  file for exactly this reason.
- **The Simulator MCP's screenshots are in pixels; its taps are in points.** The tool reports the
  point space (e.g. 402x874) while the returned image is ~2.28x that. Tapping a coordinate read
  straight off the screenshot lands off-screen and looks exactly like a dead button. Divide by the
  ratio, or pass `scale` and do the arithmetic once.
- **`#expect` cannot take a rethrowing call, and `filter`/`allSatisfy`/`contains` are all rethrows.**
  Not just `allSatisfy` — hoist any of them to a `let` first.
- **A negation trips a substring ban.** A test banning the word "score" in user-facing copy fails on
  "no plan is graded or scored", which is the sentence App Review needs to read. Strip the known
  denials first, then scan the remainder, and assert the denial still exists so stripping cannot be
  a way to pass by deleting it.
- **SourceKit constantly reports "No such module 'HardsetCore'" and similar.** It is noise — the
  package builds clean. Trust `swift build`, not the editor. It also reports "cannot find type X in
  scope" for types in the *same* module in a newly created file; same noise, same answer.
- **`swift build` and an Xcode build fight over `.build/build.db`.** A `swift test` during an
  `xcodebuild` fails with "database is locked. Possibly there are two concurrent builds running in
  the same filesystem location." It is not a corrupted checkout — wait for the other build, or pass
  a separate `--scratch-path`.
- **A migrated column sorts last in `columnInventoryIsPinned`.** `ALTER TABLE` appends, so a column
  added by a migration is not in the position its `CREATE TABLE` neighbours suggest. The pin is the
  migration's fingerprint, not a preference.
- **Editing v1's `CREATE TABLE` is not how a column is added.** It passes every schema test, because
  they migrate a fresh database — and leaves every installed database without the column forever.
- **The bundle identifier is not `com.hardset.app` on this machine.** `generate_project.py` defaults
  to it, but `HARDSET_BUNDLE_ID` overrides it and the installed build is
  `com.francisbisignano.hardset`. Anything reaching into the container must read the identifier off
  the device (`simctl listapps`) rather than assume one.

---

## 10. How to work on this

The research corpus in `docs/research/` was produced by many agents and then attacked by
adversarial verifiers. **Across the whole effort, ~32 of 56 audited claims were refuted** — almost
always by *over-reading* a real study: an EMG activation result presented as a hypertrophy finding,
a detectability threshold presented as a cap, an underpowered null presented as evidence of no
effect, a population effect presented as a per-user model.

So: cite primary sources, and assume your own confident-sounding recollection is the most likely
thing to be wrong. For Apple APIs, read the on-disk SDK at
`/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.4.sdk`
rather than trusting memory. If something in this file contradicts the SDK or the code, they win —
tell the user rather than working around it.

Keep the suite green. Every commit in this repo has a message explaining *why*, not what; match
that. And when you finish something, say plainly what you verified and what you did not.

---

## 11. Questions the user still owes an answer to

1. **Who authors the catalogue?** ~240 exercises with attribution is 260–340 hours and gates the
   product's credibility. Author, buy, or narrow v1?
2. **Paid Apple Developer Program membership** — local device signing works, but paid membership is
   still needed for CloudKit/push provisioning, TestFlight, and EU trader-status paperwork.
3. **The founding-price structure** — $3.99 grandfathered with a $8.99 standing price, versus flat
   $3.99. Cannot be changed after the first sale.
