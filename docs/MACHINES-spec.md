# Hardset — your own machines, and your own movements

**The problem, in the lifter's words:** "I use a specific Nautilus High Lever Row. I can't put that
in. And I press a different weight on one chest press than on another — I want the app to remember
each one separately. I want to add my own stuff."

**The honest starting point: most of that already works, and one part of it is a dead end.** This
spec separates the two, because the plan is much smaller than the request sounds — and the part that
is missing is not the part that looks missing.

---

## 1. What already exists, verified in source

| Capability | State |
|---|---|
| A machine is a named physical unit belonging to a gym | `machines` table, `GymStore.createMachine` |
| Load history keyed to **exercise × machine**, never merged | `ProgressionKey`, invariant #10, DECISIONS #20 |
| Prefills come from the machine you are standing at | `PriorPerformanceSnapshot.prior(for:)` |
| Moving machines mid-exercise re-prefills from the new one | `ExerciseLogState.changeMachine` |
| Per-machine stack increment, which gates record margins | `machines.stackIncrementKg`, `GymStore.setStackIncrement` |
| Rename / archive a machine, set its step | `MachinePickerView` menu |
| Create your own movement | `ExerciseStore.createExercise`, `NewExerciseSheet` |
| A machine named in a plan teaches the picker | `machineExercises`, `exercisesWithEquipment(at:)` |

So "remember a different weight on each chest press" **is already the app's central claim** and it
works. A 20-week seeded history renders one chart line per machine, and they never join.

The two-level model is deliberate and stays:

- An **exercise** is a movement — a pattern. `Chest Supported Row`.
- A **machine** is a physical unit at a place — `Nautilus High Lever Row, upstairs`.
- History belongs to the **pair**. That is the differentiator, and #10 forbids merging.

## 2. The five real gaps

### G1 — The planner's movement picker is a dead end (a bug, not a feature)

`ExercisePickerView` already has both create affordances: a `+` toolbar item and an
"Add it yourself" button on the empty state. **Both are gated on `onCreate`.**
`LiveSessionScreen` passes it. `SplitPlannerScreen` (line 229) **passes nothing**.

So building a plan and searching for a movement the catalogue lacks gives
"No movement found — Nothing in the catalogue matches "Lever"" and **no way forward**. Reproduced on
device. The same call site also omits `availableHere` and `gymName`, so the planner never shows the
"At *your gym*" relevance section the logger does.

This is the app's most-repeated defect shape: capability built, one caller forgets to wire it.

### G2 — A movement you create knows almost nothing about itself

`createExercise` takes exactly one muscle and writes exactly one contribution — `direct`, `low`
certainty, user source. Curated rows carry a full set: `Seated Cable Row` shows "also Rear delts,
Lats, Biceps".

So `Nautilus High Lever Row`, created by hand, credits **lats and nothing else**. Every weekly volume
figure that movement touches is then quietly short — upper back, biceps and rear delts get nothing.
For a lifter whose gym is mostly brand-specific machines, that is most of their training.

### G3 — Machines can only be created inside a workout

By design, and the design is mostly right: HANDOFF §8a records that equipment is "learned by naming
equipment at the rack rather than through a setup flow nobody completes", because the ancestor's
setup flow was never completed and every set logged against nothing.

But there is no way to **review** what you have named, fix a typo outside a session, set a stack
increment you learned later, or pre-load a gym you already know. There is no machine list anywhere
in the app.

### G4 — The same machine at a second gym is retyped from scratch

Correct that it is a *different machine* with its own history — two Nautilus chest presses are not
interchangeable, and #10 is right. But the lifter retypes the name, and a typo silently creates a
third machine with a third empty history.

### G5 — Nothing answers "what do I press on each of these?"

The exact question asked. The progression chart draws one line per machine, which shows it — but only
inside one movement's chart, and only if you find your way there (see `HANDOFF.md` §8e, gap 2). There
is no per-machine readout.

## 3. The plan

Ordered by value over cost. Phases 1 and 4 are hours; 2, 3 and 5 are the real work.

### Phase 1 — Wire the planner's picker (≈10 lines, do first)

Pass `onCreate`, `availableHere` and `gymName` at `SplitPlannerScreen.swift:229`, and add the
`NewExerciseSheet` presentation the logger already has. Prefill the new movement's name from
`pickerQuery`, which the logger does and which is why a failed search costs no retyping.

Removes the dead end entirely. Nothing else in the plan is worth doing before this, because this is
the wall the lifter actually hits.

### Phase 2 — Movements created **from a template**

The fix for G2, and the centrepiece.

`NewExerciseSheet` gains an optional "Based on" picker. Choose `Chest Supported Row`, name it
`Nautilus High Lever Row`, and the new movement **inherits the template's muscle contributions** —
same muscles, same roles — with two changes made unconditionally:

- `sourceID` becomes the user source. The citation is **dropped**.
- Certainty is capped at `.low`.

That is the honest reading, and the honesty is load-bearing. The literature cited for a chest-
supported row is evidence about *that* movement; the lifter asserting a Nautilus lever row is like it
is one person's judgement. So the muscles carry over and the *provenance does not*. It is strictly
better than today's single guess and it never launders a citation.

Implementation notes:

- **No schema change required.** Contributions are copied into `secondaryMusclesJSON` at creation.
- Optional, and the only schema change in this spec if wanted: `exercises.basedOnSlug TEXT?` so the
  UI can say "your variant of Chest Supported Row". Additive, which DECISIONS #4 permits. Defer it —
  a column may be added at any time, so it costs nothing to wait until the label is actually wanted.
- Copying rather than referencing means a later catalogue correction does not propagate. That is the
  right default: it is the lifter's movement now, and a curated edit silently rewriting what their
  own movement trains is worse than it going slightly stale.
- Keep the freehand path for movements that resemble nothing. Template is an offer, not a gate.

### Phase 3 — A machine library

The fix for G3, and where "standardize my own stuff" lives.

A screen reached from Settings (and from the gym chip on Train): gyms → their machines. Per machine:
name, stack increment, which movements it is linked to, when it was last used, and the best set
recorded on it. Add, rename, archive, set the step — all of which `GymStore` already exposes.

Two rules that keep it from becoming the setup flow nobody completes:

- **It is a review surface, not an onboarding step.** Nothing prompts you to fill it in, nothing is
  blocked by it being empty, and naming at the rack stays the primary path.
- **Archive, never delete.** Sets logged against a machine keep their reference; #10 means deleting
  one would orphan a real series. `archiveMachine` already does the right thing.

### Phase 4 — Suggest names you have used before (small)

When adding a machine, offer machine names already used at *any* gym as autocomplete. Solves the
retyping in G4 and the typo-creates-a-ghost problem.

**It must say plainly that this creates a new machine with its own history.** One line under the
field: "A new machine at this gym. Its loads start empty — they are not shared with the one at
*other gym*." Anything vaguer and the feature reads as "merge my machines", which is the one thing
#10 forbids.

### Phase 5 — "Your best on each" (small, read-only)

The fix for G5. On `ExerciseProgressScreen`, under the chart, a short list: each machine, the best
estimated 1RM or heaviest load, when it was last trained, and the delta against the machine you use
most. Pure read over `ProgressionSeries`, which already groups exactly this way.

Say the delta the way `MachineChange.explanation` already does — a difference between machines, not
a change in strength. The number is interesting precisely because it is *not* progress.

## 4. What this must not break

- **Machine series never merge.** #10 and #20. No feature here may join two machines' history, and
  Phase 4 is the one most likely to be misread as doing so.
- **No prescription.** None of this recommends a machine, a movement or a load.
- **A custom movement must never claim curated provenance.** The source-and-citation swap is
  necessary and, on its own, **not sufficient** — see §7. This bullet originally read "Phase 2
  lives or dies on the source-and-citation swap", which an audit refuted before implementation.
- **Additive schema only.** #4. Phase 2's optional column is the only candidate, and it is deferred.
- **Attribution never comes from equipment metadata.** The ancestor's `bodyParts` field was
  untrusted for good reason; a machine's *name* is not evidence about muscles either. Phase 2 copies
  from a movement the lifter chose, never from a string match.

## 5. Refused

- **A brand/model machine catalogue.** No licensed dataset of gym equipment exists that this project
  may ship, and guessing one is the free-exercise-db photo defect again — content shipped without a
  licence that covers it. Machine names stay the lifter's own free text.
- **Detecting that two machines are "the same model" and merging them.** Precisely invariant #10.
  Two Nautilus chest presses set up differently are not one series, and the app cannot know the
  difference.
- **Inferring muscles from a machine's name.** "High Lever Row" contains "row"; that is a string, not
  evidence. Phase 2 exists so the lifter supplies the answer instead.
- **A setup wizard.** The reason machines are learned at the rack is that the ancestor's setup flow
  went uncompleted and every set was logged against nothing.

## 6. What lands the user's request

Their three asks map cleanly:

| Ask | Where it is answered |
|---|---|
| "I can't put in a specific Nautilus High Lever Row" | Phase 1 (dead end) + Phase 2 (it knows what it trains) |
| "Remember what I did on *that* one" | **Already works.** Per-machine history, never merged |
| "Standardize it, add my own stuff" | Phase 3 (library) + Phase 4 (names) |
| "Different weight on one chest press than another" | **Already tracked**; Phase 5 makes it visible |

---

## 7. What was built, and where the plan changed

All five phases shipped. Three things differ from the plan above, and each is worth stating because
the plan was wrong rather than merely incomplete.

### Phase 1 — the planner's picker (as specced)

`SplitPlannerScreen` now passes `onCreate`, `availableHere` and `gymName`, and presents
`NewExerciseSheet` prefilled from the failed search. The two source reads that sat in the sheet's
ViewBuilder — `selectableExercises` and `loggedMovements` — were hoisted out; every keystroke in the
search field had been two table scans.

`AffordanceWiringTests` sweeps `HardsetFeature` for `ExercisePickerView(` call sites and fails when
one omits `onCreate` or the relevance arguments. The dead end existed because nothing checked, and
"capability built, one call site forgets the last hop" is this codebase's dominant defect shape.

### Phase 2 — the honesty mitigation was inert as specced

§4's claim that "Phase 2 lives or dies on the source-and-citation swap" was **backwards**. Nothing
outside the JSON encoder reads `.certainty`, `.sourceID` or `.citation`, so the swap alone changes
nothing the lifter sees — while silently inheriting would mint up to eight per-muscle arithmetic
facts they never endorsed. That is strictly worse than the single guess it replaced, because the
single guess under-claims.

Two changes make it real: the inherited muscles are **shown as rows that can be switched off**, and
only what is left on is written; and the provenance rewrite happens at the **store** boundary rather
than in the sheet, so no future caller can skip it. `SetCounting.certaintyCeiling` — dead since it
was written, while `doseResponse` re-implemented the same rule inline — is now the single definition
of that rule. See DECISIONS #38.

### Phase 3 — the library (as specced, plus unarchive)

`MachineLibraryScreen`, reached from Settings. Per machine: linked movements, best working set, last
used, stack step, and a "Put away" section. `archiveMachine` had no counterpart, so archiving from a
review screen would have been a one-way door; `setMachineArchived(_:for:)` adds the other direction.

### Phase 4 — the shape changed before any UI existed

As written, autocomplete could mint a second `MachineID` for one physical machine — unrecoverable,
because #10 forbids merging them back. The query is now **gym-partitioned**: a name already at this
gym resolves to that machine, a name from another gym creates a new one and says so. See
DECISIONS #39.

### Phase 5 — "your best on each" (as specced)

`MachineComparison` in Core, rendered under the chart. The machine with the most sessions is the
reference — the number the lifter actually knows — with ties broken on recency so the baseline does
not depend on the order series arrive in. Deltas are worded like `MachineChange.explanation`, and a
test asserts the wording contains none of "progress", "stronger", "weaker", "improve", "decline".

The section does not render for a single machine: one machine is not a comparison.

### What this cost that the plan did not predict

Writing `MachineLibrary.swift` hit a SIGTRAP with no message that took hours to diagnose and had
nothing to do with this feature — `HardsetStore` defaults declarations to `@MainActor`, and an
extension that omits `nonisolated` compiles silently and then traps. `IsolationContractTests` now
prevents a recurrence. See DECISIONS #40.
