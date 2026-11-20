# Saved workouts, Progress tab and body-part library: design

Date: 2026-11-18. Owner: FrankieBiz. Status: approved direction, written for the implementation plan.

## Why

Hardset logs sets well, but every workout starts empty and progress is buried. The only chart
for an exercise is reachable from inside a live workout or from an old receipt. Lifters open a
gym app to see whether they are getting stronger. This work makes progress the centre of the app
and makes starting a planned day one tap.

The owner's words, condensed: "Click start Upper Day A, then I'll have an Upper Day B, and in
those I put how many reps and sets I do. A tab of progress with graphs of the exercises I do.
When I made a movement called Nautilus lever row and last time I did 90 lb and now 100 lb, I want
to see that on a graph. The library sorted by body part, with how many exercises for each at the
bottom. Really focused around progress, because that's what gym-goers care about. I want it to
feel fun and enjoyable, and I want innovation."

## Goals

1. **Saved workouts.** Named workouts ("Upper A", "Upper B") made of movements, each with an
   optional machine, a set count, a rep range and an optional rest. They start in one tap.
2. **Progress tab.** A fourth tab listing every trained movement grouped by body part, each with a
   trend. Tapping one opens a graph that rewards both heavier weight and more reps.
3. **Library by body part.** Every movement grouped by body part with a count per group. Custom
   movements get a body part when they are created, and existing untagged ones can be tagged.
4. **Fun that is earned.** Satisfying moments come from real progress: beating last time, setting
   a record, finishing a workout that went up. Nothing celebrates fake progress.

## Non-goals

- Auto-generated programmes, AI coaching, social features, streak guilt or confetti.
- Merging different machines into one line. Each exercise-on-a-machine stays its own series, as
  it is today.
- Changing how a set is logged. One tap per set remains the core interaction.
- Weekly scheduling or calendars. Workouts rotate; they are not tied to weekdays.

## Anti-goals (a failure even if it technically works)

- The graph or a target shows a number the engine cannot justify (an estimate from a 20-rep set,
  a target invented without a rep range or history).
- A "+1 rep" mark, record or "Stalled" flag that is wrong, for example comparing against another
  machine without saying so.
- Starting a saved workout takes more than one tap from the Train tab, or editing a saved workout
  rewrites the history of workouts already done.
- Any saved workout, movement or set is lost or rewritten by a migration.

## Constraints (from the repository)

- Architecture: Core is Foundation-only and nonisolated; Store owns GRDB/SQLiteData persistence;
  UI is `@MainActor` SwiftUI with tokens from `DesignTokens.swift`; Feature is the composition
  root. Follow `AGENTS.md`, `CODEX.md` and `DESIGN.md`.
- Schema rules (`Migrations.swift:13-29`, `SchemaRules.swift`): a TEXT UUID primary key, no
  UNIQUE apart from it, no CHECK, STRICT tables, NOT NULL columns with defaults, `ON DELETE` only
  CASCADE, SET NULL or SET DEFAULT, no reserved CloudKit names, never drop or rename. Each new
  synced table is registered in `HardsetMigrations.syncedTableNames` and in the `SyncEngine`
  table list in `Database.swift`. Migration names continue from `v10_importLedgerDigests` as
  `v11_…`.
- Weights are stored in kilograms. Pounds are a display conversion only.
- Honesty rules: `StrengthMath` estimates only 1 to 12 reps and attaches certainty;
  `PersonalRecordDetector` requires a real margin and never fires on a first session. New logic
  reuses these rather than redefining them.
- Linux can run the Core and Store tests and the parse check. SwiftUI rendering, Dynamic Type and
  device feel are verified on the Mac lane and the macOS CI screenshot job.

## What was decided with the owner

### The progress formula

Both heavier weight and more reps must count as progress. The formula has two parts.

1. **The graph's main line is the estimated max**, using the existing Epley estimate
   `weight × (1 + reps ÷ 30)` in `StrengthMath`. Each session contributes one point per machine:
   that session's best evaluable working set. 90 lb × 10 gives 120, 90 × 12 gives 126 and
   100 × 10 gives 133, so both kinds of progress raise the line. Sets above 12 reps produce no
   estimate. Certainty (high for 2 to 6 reps, moderate for 7 to 10, low for 11 to 12) stays
   visible beside the number through `CertaintyBadge`.
2. **Records are facts, not estimates**, and cover what the line cannot. The owner's rule is
   "more reps at the same weight, or more weight for the same reps". The existing
   `PersonalRecordDetector` is the single source of records and keeps its kinds and margins:
   heaviest weight ever, most reps at this exact weight (the "more reps" half), and best
   estimated max. This design adds one kind for the "more weight" half: **most weight for this
   many reps** (`loadAtReps`). A set is a `loadAtReps` record when its load beats, by the
   detector's existing margin, the heaviest earlier working set with the same number of reps or
   more. It works at any rep count, so 95 × 15 after 90 × 15 counts. The Store's comparison
   selection (`LoggerStore.recordComparisonSets`, currently best load per rep count 1 to 12) is
   extended to every rep count so the claim stays all-time. Records appear as marked points on
   the graph, and "set a record" everywhere in this design means "the detector returned at least
   one record".
3. Under the graph, a **best at each weight** table lists each weight used on that machine with
   its best reps and the date ("90 lb · 12 reps · Nov 4").
4. The graph opens on the estimated max. The existing "heaviest weight" metric stays as a toggle.

### Feature list the owner accepted

Saved workouts:
- A saved workout holds ordered movements. Each has an optional machine, a set count (1 to 10),
  an optional rep range (for example 8 to 12) and an optional rest length.
- The Train tab shows saved workouts as cards with their name, movement count and "last done 4
  days ago". One tap on the card's start button starts the workout with every movement, machine
  and set row ready.
- **Up next:** the workout done longest ago (or never) is shown first and largest, so Upper A
  and Upper B alternate without any setup.
- **Overload targets (double progression):** when a movement has a rep range and history on that
  machine, each set row is prefilled with a target, labelled "Target" with the rule as its source:
  - If every working set last time reached the top of the range at the same weight, the target
    adds one load step at the bottom of the range.
  - Otherwise it keeps the weight and adds one rep to that set's reps from last time, capped at
    the top of the range.
- **Beat-last-time marks:** when a logged set beats the same set from last time on this machine,
  the row shows "+1 rep" or "+10 lb". A set that matches shows "Matched". Nothing shows when it
  fell short. The precise rule is in "The builder's calls" below.
- "Save as workout" from a finished workout's receipt, and "Repeat last workout" on the Train tab.
- Editing a saved workout never changes past sessions.

Progress tab:
- A fourth tab, **Progress**, placed between Train and Volume. It lists every movement that has
  working sets, grouped by body part. Each row shows the movement, its machine, a small trend line
  of the estimated max (or heaviest weight when no estimate exists), and the change over the last
  six weeks, for example "+8% in 6 weeks".
- A **Most improved** strip at the top shows the three movements with the largest six-week gain.
- **Stalled flag:** a movement on a machine with at least four sessions, where none of the last
  three set a record, is labelled "Stalled · 3 sessions" in the warning colour. No advice is
  attached.
- Tapping a row opens the improved exercise progress screen (graph, record marks, best at each
  weight).

Library:
- A Library screen lists every selectable movement grouped by body part (the existing
  `MuscleFilterCategory` sections: chest, back, shoulders, arms, core, quads, hamstrings, glutes,
  hips, calves, neck), with a count per group in a footer ledger at the bottom.
- Movements with no body part are grouped first under "Needs a body part" so they can be tagged.
- Creating a movement asks for a name, a body part (with a specific muscle where the part has
  more than one), up to three optional secondary muscles and the equipment type. Custom movements
  can be edited later. Curated movements cannot be retagged. The lifter's choice is stored as the
  movement's attribution with source `user` at moderate certainty: primary direct, secondaries
  indirect. Nothing is inferred from the name.
- **Split balance:** the saved-workouts screen shows planned sets per body part across one full
  rotation (each saved workout done once). It reuses `VolumeAnalyzer.report` over the planned
  sets, so it obeys the taxonomy's rule that a group is never given a summed set total: each
  `MuscleGroup` shows the planned sets that touch it (each set counted once per group), and each
  muscle shows its fractional sets (direct 1, secondary 0.5). A group other than neck with zero
  planned sets is called out as "Nothing planned". It shows no target bands and makes no
  judgement.

### Making it fun (owner request, designed within DESIGN.md)

Fun here comes from feedback that is true and immediate.
- **The finish scorecard.** Finishing a workout opens the receipt with a scorecard at the top:
  "Beat last time on 5 of 7", the records set (on the yellow record surface), and the movement
  with the biggest gain. It is shareable through the receipt's existing share sheet.
- **Records get their moment.** A record set already plays the log stamp and haptics, and shows
  the record banner. That stays as is, with the new `loadAtReps` kind described in plain words
  ("Most weight for 10 reps: 95 lb, beat 90 lb").
- **Beat marks arrive** with the existing `hardsetArrival()` reveal in `plateGreen`. They are the
  live "I'm winning" signal between sets.
- **Up-next card** reads like a coach's note: "Upper A · up next · last time you beat 4 of 6".
- No new motion token. Any use of `Motion.stamp` beyond the log check needs a DESIGN.md update
  first, and this design does not need one.

## The builder's calls (not discussed with the owner; change if wrong)

- **Prefill is the target.** When a target exists, the set row is prefilled with it, so a
  lifter who hits the target logs in one tap. The "Last time" column still shows what actually
  happened last time, and the target is labelled so it is never mistaken for history. Without a
  rep range or history, the prefill is unchanged from today.
- **Load step:** the target uses the machine's saved load step. When none is saved it uses one
  plate in the lifter's unit (2.5 kg, or 5 lb stored as 2.268 kg), and says "assumed step".
- **Bodyweight movements:** targets add reps only, and the trend line uses reps at the best
  added load, because the estimated max is not evaluated for bodyweight work.
- **The six-week change** compares the latest session's estimated max with the best estimated
  max from sessions 35 to 49 days earlier. With no session in that window it says "Not enough
  history" instead of picking another window.
- **The rotation** is the saved workouts in the order the lifter arranged them. "Up next" is the
  one with the oldest last-done date, ties broken by that order.
- **Storage:** two new synced tables, `workoutTemplates` and `templateExercises`. Sessions
  remember which template started them and each session movement remembers its rep range, so a
  resumed or later workout can compute targets and the scorecard without the template, which may
  since have been edited or deleted.
- **Beating last time, precisely.** Sets are paired by their position among working sets
  (warm-ups excluded) with the same exercise on the same machine last session. A set with no
  partner shows nothing. A set beats its partner when it has more reps at the same or more weight,
  or more weight with reps at or above the movement's rep-range floor (or, with no rep range,
  the same or more reps). So 95 × 8 after 90 × 12 beats it when the range is 8 to 12, which is
  exactly the double-progression step. The mark names what grew: "+5 lb", "+1 rep" or
  "+5 lb · +1 rep". Equal weight and reps show "Matched". Weights compare with the detector's
  0.01 kg tolerance.
- **The scorecard counts movements.** A movement is beaten when at least one of its working sets
  beat its partner or set a record. Movements with no previous session on that machine are listed
  as "First time on this machine" and left out of both numbers of "5 of 7". The biggest gain is
  the largest percentage change in the session's best estimated max against the previous
  session's best on the same machine; when neither side has an estimate, it uses heaviest weight.
  The up-next note reuses the same summary for that workout's last session.
- **Gyms.** Saved workouts are not tied to a gym. A movement's saved machine is used when it
  belongs to the gym the workout starts at. Otherwise the start uses the machine last used for
  that exercise at this gym (the same rule `addExercise` already applies), or no machine. Rotation
  and "Up next" count across all gyms.
- **Rest.** A saved workout's rest for a movement counts as the lifter's choice for that movement
  when that workout starts: it is written as the movement's remembered rest, so the existing rest
  flow starts it after a working set. Changing the rest mid-workout updates the remembered rest as
  today and does not edit the saved workout. Leaving it blank keeps today's behaviour.
- **Where things live.** The Train tab, when no workout is open, shows the up-next card, the other
  saved workouts, "New workout", "Repeat last workout" and a "Library" button in its header. The
  saved-workout editor and split balance open from there. The Library is also where movements are
  created and tagged. The exercise picker's "create movement" flow is extended with the same
  body-part step, so there is one way to create a movement.
- **Tabs:** Train, Progress, Volume, History. The onboarding tour's tab staging is updated, and
  no tour step points at the new tab yet.

## What is left to the builder

Exact component composition, file splits inside each target, copy beyond what is quoted above,
query shapes and indexes (each new query passes `Tools/check_query_performance.py
--require-indexes`), and test case selection beyond the cases the plan specifies.
