# Plan Builder Clarity Design

## Goal

Make the planner immediately understandable: it is a reusable structure for workouts the lifter
already does, not a training prescription. Separate creating a first plan from redistributing an
existing one.

## User model

- A plan contains named workout days and the movements available on each day.
- Starting a day opens that exact list as today's workout.
- The lifter owns every choice: movements, names, order, machines and any intended set counts.
- The app can arrange those movements across days, but never chooses additional movements or a
  volume target.

## Flow

### Empty plan

Show a short explanation: “Build a reusable weekly structure from exercises you already train.”
Show two explicit routes:

1. **Build it myself** — continue with the existing add-day/add-movement controls.
2. **Start from training history** — a deliberate, confirmed action that arranges movements found
   in completed workouts across the selected number of days. It is unavailable until history
   contains a movement. The day selector is shown before the action, just as it is for
   redistribution.

The history route says exactly what it will use and that it will not change completed workouts.

### Existing plan

Show an optional “Redistribute exercises” tool. It operates only on movements already in the plan,
with a chosen day count. It does not use workout history as an input.

Its copy says it spreads the current plan's movements across days to avoid grouping the same
trained muscles where possible. It explicitly says it does not add or remove movements, prescribe
sets, change named machines or alter completed workouts.

### Safety

The existing store replacement behavior remains: day identity/name (where the day remains), named
machines and intended set counts remain; reducing the number of days removes only the discarded
tail days and entries. Logged workouts are never deleted or edited.

## Terminology

Replace the playing-card metaphor “Deal across” and generic header “Rearrange” with direct
language:

| Current | New |
| --- | --- |
| Rearrange | Redistribute exercises |
| Deal across N days | Redistribute across N days |
| Deal | Redistribute |
| Empty-plan implicit history fallback | Start from training history |

## Technical design

`SplitPlannerScreen` keeps its two sources explicit:

- `redeal` is called only for a non-empty plan and passes `plan.allMovements` to `SplitDealer`.
- `buildFromHistory` is separately invoked from the empty-plan affordance and passes
  `splits.completedWorkoutMovements()` to `SplitDealer`.

`PlanDealSource` becomes an expression of the active action rather than a hidden fallback. The UI
gets separate callbacks for redistribution and history seeding, so it cannot accidentally make the
source decision in a closure that means something else.

No schema or migration changes are needed.

## Tests

- Copy tests lock the two distinct explanations and confirmations.
- Wiring tests prove an empty plan exposes only the explicit history route, while a populated plan
  exposes only redistribution.
- Store tests confirm redistribution preserves lifter-authored details and history seeding uses
  only the supplied history movements.
- Existing package and app UI suites validate regression safety.
