# Hardset — splits, and re-dealing what you already train

## What the planner is for

A plan is a reusable weekly structure for movements the lifter already trains: named days, the
movements on each, optional set counts they chose, and preferred machines. It is not a program the
app writes for them. An empty plan makes the two starting points explicit: **Build it myself** adds
an editable first day, while **Start from training history** arranges movements from completed
workouts across the chosen number of days. Once a plan has movements, **Redistribute exercises**
only reshapes those existing movements. It never imports more history, changes logged workouts,
adds or removes movements, decides sets, or changes named machines.

A split in Hardset is **a partition of movements the lifter already does**, across a number of days
they choose. It is not a program, it does not prescribe, and it carries no set counts.

That sentence is the whole design. Everything below follows from it, and the schema is shaped so the
prescribing version is *unrepresentable* rather than merely discouraged — the same technique that
keeps a stored duration off `sessions`.

---

## 1. Why this shape, and not a generator

The obvious feature request is "build me a balanced split." The app may not do that, and the reason
is computed rather than asserted. `SplitCalibrationProbe` (commit `d12ba1c`) establishes four
numbers, and each one closes off a candidate quality axis:

| Candidate axis | Why it fails |
|---|---|
| A weekly set target per muscle | `VolumeAnalyzer.weeklyTarget` returns `.unevaluated` for **every** muscle, deliberately. A generator has nothing to optimise against. |
| Muscle coverage | Every conventional split leaves 6–8 muscles at zero, five common to all of them (forearms, abs, obliques, neck, hip abductors). A coverage score marks down a well-built PPL and a bro split identically, for not training necks. |
| Total weekly volume | A conventional PPL puts all six modelled muscles inside the studied range at 90 weekly sets; a perfectly reasonable 3-day full body does it at 42. Any formula treating volume as quality must call one of those worse, and neither is. |
| A composite grade | Only 6 of 22 muscles are `.modelled`. A whole-body grade would be two-thirds territory the dose-response model refuses to speak about. |

So: no target, no score, no generated prescription. **The word "balanced" does not appear in any
user-facing string, and a test asserts that.**

What *is* left is genuinely useful, and it is what this feature ships: the lifter already told the
app every movement they train and every machine they train it on. Re-dealing that set across a
different number of days is arithmetic over data they authored. No evidence is claimed, because none
is needed.

### The line, stated once

- The app **may** decide which day a movement the lifter already does lands on.
- The app **may not** decide how many sets of it they do, or introduce a movement they have never
  logged as a recommendation.

## 2. What the app may say about a plan

Two statements survive the probe, and only two:

1. **A muscle credited nothing.** "This arrangement never credits your hamstrings" is a fact about a
   partition and needs no target. Already implemented as
   `MuscleVolumeReport.untrainedMuscles(excluding:)`, and it already excludes tokens with no
   catalogue movement, so it does not blame the lifter for a content gap.
2. **Where a modelled muscle sits relative to the rest of this plan.** For the six `.modelled`
   muscles the dose-response relationship applies, so the *direction* is sayable — more sets tended
   to produce more growth, with diminishing returns. The *number* is not: there is no floor to be
   under. So the statement is comparative and within-plan ("the lowest-credited of the six muscles
   the literature covers"), never evaluative ("too low").

Explicitly **not** sayable, and asserted as such in tests: any absolute target, any grade, any
"below minimum", and any claim at all about the 16 `counted` muscles beyond zero-versus-nonzero.

`isBeyondStudiedRange` stays available and stays a *withholding*: above ~25 fractional sets the app
reports the count and declines to say what another set buys.

## 3. Schema

Three new tables, added to the **v1 migration** rather than a v2. Nothing has shipped, no build has
reached a device, and `eraseDatabaseOnSchemaChange` is on in DEBUG — so v1 is still the one designed
artefact it claims to be. This is the last cheap moment.

```
splits        id, name, isArchived, createdAt
splitDays     id, splitID → splits (CASCADE), name, position, createdAt
splitEntries  id, splitDayID → splitDays (CASCADE), exerciseID → exercises (CASCADE),
              machineID → machines (SET NULL), position, createdAt
```

All three synchronize: a plan is app data, not health data, and it should follow the lifter to a
second device.

### There is no `plannedSets` column, and that is the point

`sessionExercises` has one, because that is the lifter typing what they intend to do *today*. A
split is the surface where the app does the arranging, so a set-count column there is the hole a
prescription engine climbs through. Leaving it out makes "the app decided your volume"
unrepresentable at the storage layer.

Adding a column later is the permitted direction under DECISIONS #4, so if lifters ask to record
their own per-movement set targets, that is an additive change made deliberately — not a default
absorbed now.

### Constraint checklist

Each new table obeys the seven rules in `Migrations.swift` and is covered by the existing
`SchemaTests`: single non-compound TEXT primary key defaulting to `uuid()`, no UNIQUE outside the
primary key, no reserved CloudKit names, every foreign key declaring a supported `ON DELETE`,
`STRICT`, no `CHECK`, no self-reference. `splitEntries` carries three foreign keys, which puts it in
the set SQLiteData's own validator *skips* (it is gated on `foreignKeys.count == 1`) — so it is
covered only by `everyForeignKeyHasSupportedAction`, and that matters.

`columnInventoryIsPinned` must be updated by hand, which is the intended cost.

## 4. The dealer

`SplitDealer.deal(movements:across:attribution:)` in `HardsetCore`. Pure, Foundation-only, no
database handle — same rule as `PriorPerformanceSnapshot`.

Greedy multi-dimensional load balancing, largest-first:

1. Order movements by total credited weight descending, then by id ascending. The tiebreak is what
   makes the result deterministic, so re-dealing the same input twice cannot reshuffle a lifter's
   plan.
2. Place each movement on the day whose current credit for *that movement's* muscles is lowest.
   Tie-break on fewest movements, then lowest day index.

That is it. It minimises per-day, per-muscle imbalance of the lifter's own movements. It is not
optimal — optimal multi-dimensional partitioning is NP-hard and a better answer here would be
indistinguishable to a lifter — and it asserts nothing about recovery, ordering or frequency.

**Deliberately absent:** any rule about which muscles may share a day, or must not appear on
consecutive days. That would be a recovery claim, and the app has no such finding.

### Day names

Days are stored as "Day 1"…"Day N". The app does not name a day "Push" or "Upper", because that
labels the split as a *style* the app chose. `SplitPlanDay.dominantGroups` derives a descriptive
subtitle from what is actually on the day, for the UI to show beside a name the lifter can edit.

### Unattributed movements

A movement with no attribution credits nothing, so the load-balancing step cannot place it
meaningfully. It is dealt round-robin after the attributed ones and counted in the plan's own
coverage figure, so a plan built mostly from unattributed movements says so rather than looking
evenly balanced.

## 5. Machines join the library from the plan

When a split entry names a machine for a movement, that writes `machineExercises` — the same
association `GymStore.createMachine(forExercise:)` already records when equipment is named at the
rack, one step earlier in the lifter's week.

This is the payoff the join table was built for: `exercisesWithEquipment(at:)` unions "machines named
for a movement" with "movements logged here", and the first source exists precisely to make picker
relevance work at a gym before anything has been logged there. Planning a split before training
somewhere is exactly that case.

The link is idempotent (`GymStore.linkMachine(_:toExercise:)`, check-then-insert in one write) —
there can be no UNIQUE constraint to lean on.

## 6. Scope

**The UI ships in this pass.** An earlier draft of this spec deferred it behind the device gate,
reasoning from HANDOFF §8. That was wrong, and worth recording why: §8's argument is specifically
about *motion* — haptic-and-pixel co-timing and the 100 ms acknowledgement budget cannot be judged in
a simulator, so tuning them before the gate means tuning them twice. None of that applies to whether
a screen exists. Shipping the schema, the engine and the store with nothing able to reach them would
have produced, deliberately, this app's single commonest defect: capability built and never wired
(see `hardset-dead-capability-audit`). A `SplitStore` hanging off `HardsetEnvironment` with no
consumer is that defect exactly.

So the planner is a fourth tab, and it is verified in the simulator against a seeded database —
which is the only way most of this app's real defects have ever been found.

Still out of scope, and genuinely:

- **Motion.** The planner uses the existing token vocabulary and adds no new animation. The four
  hero moments in §5 of the guidelines stay where they are, behind the device gate.
- ~~**Converting a split day into a live session.**~~ **Shipped.** It was deferred as touching
  `SessionCoordinator`, but it turned out to need no change there at all: `SessionCoordinator.start`
  already takes `[PlannedExercise]`, and `PlannedExercise.plannedSets` is already `Int?`. So
  `SplitStore.plannedExercises(for:)` hands it a day with every `plannedSets` nil and the coordinator
  is untouched.

  Worth recording *why* it does not go through `RepeatableExercise`, the "do it again" currency: that
  type's `workingSets` is non-optional, because a past workout genuinely has a set count. A split day
  does not, so routing through it would have forced a number to be invented at precisely the boundary
  this feature exists to keep clean.
- ~~**Per-movement set targets of the lifter's own.**~~ **Shipped.** See §7.

---

## 7. What the lifter authors, and what the app must not lose

Everything in this section follows from one observation: a plan is not only an arrangement, it is a
set of *decisions the lifter made* — which machine, how many sets, what the day is called, what order
it reads in. The app may rearrange movements. It may not discard those decisions, and until this pass
it discarded most of them on one tap.

### 7.1 Intended set counts — `splitEntries.targetSets`

Additive, nullable, and **never written by the app**. §3 argued against a set-count column and the
argument was about the *dealer* being able to fill one: "a set-count column there is the hole a
prescription engine climbs through". That still holds. What changed is that §6 named this exact
extension and it was asked for.

The distinction the whole column rests on, and the only one that matters: **the app may record what
the lifter intends and may never author it.** No default, no derivation from their history, no
suggested figure in the menu. `nil` is a real answer and the default, and stays untouched until they
type a number. `weeklyTarget` remains `.unevaluated` for all 22 muscles, and nothing compares this
number to anything — it is a statement of intent, not a target.

The hop needed no new machinery: `PlannedExercise.plannedSets` was already `Int?` and
`sessionExercises.plannedSets` already existed, so a day with set counts opens the logger with that
many rows, and a day without still takes its rows from the lifter's history exactly as before.

Three guards, because the refusal is worth more than the feature:

- `splitsCarryNoPrescription` still bans every name the app could plausibly deal out
  (`plannedSets`, `sets`, `setCount`, `reps`, `weightKg`) and argues the exemption in its own doc
  comment rather than quietly dropping a list entry.
- `targetSetsIsNullableAndUndefaulted` proves the schema cannot supply a value. A
  `NOT NULL DEFAULT 3` would prescribe three sets to every movement anyone ever planned without a
  line of code.
- `appNeverAuthorsATargetSetCount` sweeps `Sources` and fails if any file assigns a literal to
  `targetSets`. Verified to fail, naming file and line, before being trusted. Comments are stripped
  first — a ban that trips on its own explanation is the trap HANDOFF §9 records.

### 7.2 A plan has no gym, and its machines have to be reconciled

**The defect, proven on device.** A machine belongs to one gym. A plan does not, and its entries were
chosen from whatever `lastUsedGym()` happened to be. `plannedExercises` took no gym, so starting a
plan built at Iron Works while standing in Downtown Barbell opened every row bound to *Iron Works*
machines and showed their load history as though it were the equipment in front of you — writing sets
into a machine series the lifter never touched. Machine-level tracking is differentiator #2; this
corrupted it silently. The logger's own picker has always been gym-scoped (`canPickMachines` requires
a gym), so the plan was the one path around it.

**A plan still has no gym, deliberately.** Adding `splits.gymID` would force a lifter who runs one
arrangement at two gyms to keep two plans. Instead the machine is reconciled at the one moment the
gym is known, by `plannedExercises(for:at:)`:

| Case | Result |
|---|---|
| Machine is at this gym | Kept |
| Different gym, a same-named machine exists here | Resolved to *that* machine |
| Different gym, no counterpart here | Dropped; the row opens unbound |
| No gym chosen at all | Dropped — a session with no gym can only log `machineID == nil` |

Name resolution is scoped to *this* gym and matches the way `existingMachine(named:at:)` does, so
DECISION #39 and invariant #10 both hold: nothing is created, and no two machines' histories merge.
The planner also says so up front — a row whose machine is elsewhere reads "Not at the gym you are
training at next", rather than letting the lifter find out mid-workout.

The planner's gym is now the root's `selectedGym`, passed in. It used to resolve its own with
`lastUsedGym()` in three places, which is a different question from "where am I training next": after
switching gyms the planner went on offering the old gym's machines while its own button would start a
workout somewhere else.

### 7.3 Re-dealing rearranges; it does not reset

`replace` wrote `machineID: nil` for every entry and took its day names from the dealer, so one tap of
"Deal" discarded every machine the lifter had named and renamed "Push / Pull / Legs" to
"Day 1 / Day 2 / Day 3". No undo. The confirmation said only "This replaces the current arrangement.
Your logged workouts are not affected" — true, and materially incomplete.

Now carried across: **machines and intended set counts, by movement** (queued, so a movement planned
twice keeps both of its machines) and **day names, by position**. The confirmation names what it
keeps, because agreeing to a dialogue that omits the loss is not agreement.

### 7.4 Order is the lifter's, in both directions

- **Within a day.** `moveEntry` has always taken a target position; the only interaction that reached
  it passed a day and dropped the position, so what the lifter does first when fresh was unorderable.
- **Between days.** There was no `moveDay` at all. Day order is the order the plan reads in *and* the
  tie-break `SplitRotation.longestSinceTrained` uses, so a plan whose days cannot be reordered has an
  arrangement the lifter cannot correct.

Both are menus rather than drags, for the reason already recorded for moving between days: a drag has
no discoverable affordance and no VoiceOver equivalent.

### 7.5 Days credited — a readout the app already computed and never showed

`SplitPlanAssessment.creditingDays` existed with no consumer. Its own note says why it may be shown
and how: "the app has no registered finding about training frequency, so a UI may show this and may
**not rank it**."

So `modelledDayCredits` is a readout, and three properties keep it honest: ordered by
`Muscle.allCases` (ordering by count would be the ranking the note forbids), restricted to the six
`.modelled` muscles (§2 permits no claim about the other 16 beyond zero-versus-nonzero, and a per-day
count is such a claim), and omitting muscles nothing credits (already stated by
`uncreditedMuscles(excluding:)`, and a row of zero invites reading the list as a scoreboard). The
footer says it on the face of it: "A count of this arrangement, not a target… these are not ranked
and none is better than another."

### 7.6 A movement the lifter retired

Archiving is a soft delete, so a retired movement stays in the plan while the picker stops offering
it — the plan went on starting a movement the app would no longer let you add. `retiredMovements(in:)`
reports them and the row says "Retired — still starts, no longer offered".

Reported, **not filtered out**. Dropping the row would be the app quietly editing someone's plan; the
plan is theirs and the app's job is to tell them what it knows.
