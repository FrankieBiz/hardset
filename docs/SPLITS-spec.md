# Hardset — splits, and re-dealing what you already train

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
- **Converting a split day into a live session.** A real feature and a small one, but it touches
  `SessionCoordinator`, the most load-bearing type in the app. It deserves its own pass rather than
  riding along with a schema change.
- **Per-movement set targets of the lifter's own.** Additive later if asked for; see §3.
