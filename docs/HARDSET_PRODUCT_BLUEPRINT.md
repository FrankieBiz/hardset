# Hardset product blueprint

**Date:** 9 November 2026
**Status:** Recommended product decisions following the owner's endorsement of the [strategic direction](HARDSET_STRATEGIC_PLAN.md). Planning only; capabilities below are not claims about shipped behavior.
**Purpose:** Define a coherent product and a bounded first release before turning the strategy into implementation work.

## 1. The product we are choosing

**Hardset helps a self-directed lifter run their own training plan through real-world changes and understand the resulting record.**

The everyday product is one connected experience: choose the next planned session, adapt it to available equipment, record what actually happened, and prepare the next session using understandable evidence. A plan editor, gym inventory and analytics dashboard are useful only insofar as they support that experience.

We will not try to win by having the longest feature list. We will test whether people can keep their program and equipment history straight with less work than their current method.

### Decisions to use as planning defaults

| Area | Decision | Reason |
| --- | --- | --- |
| Audience | Self-directed lifters first; include coach-written plans without becoming the coach | Matches the current product's restraint and strengths |
| Organizing object | A personal plan with reusable session templates | Gives preparation, logging and review a shared context |
| Scheduling | Session sequence first; calendar dates optional | A missed Monday should not break the program |
| Equipment | Remember physical setups when they matter; avoid mandatory inventory | Captures useful context without turning logging into administration |
| Comparison | Show the basis and exclusions of comparisons | Preserves meaning when equipment and training change |
| Guidance | Describe first; execute user-selected rules later | Establishes useful records before automation |
| First release | One complete plan-to-review experience | Tests the product hypothesis rather than disconnected features |
| Business | Keep the core experience usable without payment | Users must experience the proposed advantage before evaluating paid depth |

These are choices we can make now. Whether users value the choices enough to switch remains an empirical question.

## 2. What the first release must let a person do

A lifter should be able to bring a familiar upper/lower split, prepare the next session, train at either of two gyms, substitute an occupied station, finish a shorter session without corrupting the plan, and later recognize which results compare.

The first useful release includes:

- A manually authored plan with named routines, ordering, working sets, optional rep ranges and rest preferences.
- A route from a past workout into a routine, with an explicit preview of intended versus completed work.
- A sequence that survives missed days and deliberate skips.
- Gym-specific equipment choices for routine movements and remembered setup notes.
- A one-day substitution that preserves the original plan unless the user chooses otherwise.
- A restrained comparison with prior matching work, including clear missing-information states.
- Supported history import with a review of ambiguous data; exporting remains available.
- Reliable save, correction, recovery and sync behavior, verified on the actual target platform.

It does **not** include an adaptive program generator, automatic progression, public gym database, social feed, public program marketplace, nutrition system, Android app or Apple Watch app. Multi-week authoring and elaborate block analytics can follow the first coherent experience. The review itself must appear in the first release; otherwise we have only proved a routine builder.

A release may be delivered in internal slices, but a user-facing pilot should not be asked to imagine the missing half of the value.

## 3. Define training intention separately from training facts

The following are product concepts, not a proposed database schema.

| Concept | Meaning | What changing it should affect |
| --- | --- | --- |
| Movement | A recognizable exercise in the person's library | Search, labels and references, without merging distinct histories |
| Routine position | A movement's role in a particular session, such as an early heavy press versus later back-off work | That role's planned work and eventual progression rule |
| Setup | Equipment identity and meaningful user-recorded conditions | Future suggestions and the explanation of comparisons |
| Routine | Reusable intended work for one session | Future sessions, after an explicit save |
| Plan | Ordered routines and the person's current place in that sequence | What is offered next |
| Plan version | A saved definition of intention at a point in time | Future use; historical sessions retain their original context |
| Workout | The session the person actually performed | Logged facts and descriptive summaries |
| Block | An optional period labeled by the user with an emphasis | Review grouping; no biological promise or automatic duration |
| Review | A reproducible explanation of selected training facts | Recomputed summaries, with the comparison basis visible |

Two occurrences of the same exercise must remain distinct when they have different roles. Exercise identity alone is insufficient to decide which prescription or rule to apply. At the same time, ordinary exercise history should remain discoverable across those occurrences.

**Decision:** preserve a session's starting plan and its actual deviations. Never infer the intended plan solely from the final logged sets. Otherwise a rushed workout can silently become the user's new program.

This is not a novel capability claim: Liftosaur documents program versions, and Boostcamp describes preserving the version a user saved. The reason to adopt the principle is correctness and user control. [Liftosaur program editor](https://www.liftosaur.com/features/program-editor), [Boostcamp builder](https://www.boostcamp.app/features/program-builder)

## 4. Settle the behavior of the plan

| Situation | Recommended behavior |
| --- | --- |
| A day is missed | Keep the next session in sequence. Do not advance from the clock |
| The user finishes a shortened workout | Save its actual work, show omissions, and advance to the next routine; provide an explicit option to repeat instead |
| A started workout has no logged sets and is abandoned | Do not consume the planned session |
| A session is deliberately skipped | Record the user's choice and move forward; do not record a completed workout |
| The user runs an extra or earlier session | Treat it as an additional session unless the user explicitly changes their place in the plan |
| The user changes equipment today | Save the session's actual setup; offer a separate choice to make it the default at that gym |
| The user changes sets or exercises today | Default to today only; “update routine” is a separate action |
| The user changes the plan during an active workout | The active workout keeps its starting version; apply the edit to future starts |
| A second device has a different plan edit | Preserve both versions and surface a resolution choice; do not silently merge incompatible prescriptions |
| The user replaces their active plan | Keep the old plan archived and its historical associations intact |

**Scope choice:** one active plan at a time for the first release, with multiple saved plans. This reduces sequence ambiguity while preserving travel or alternative plans. Parallel active plans are not required until real use demonstrates the need.

**Recovery choice:** a recovered session is the same session, not a new interpretation of today's plan. Its saved sets, source plan and known equipment context must survive restart. Unlogged drafts must never be represented as completed facts.

## 5. Make equipment useful without making it compulsory

The app should ask for the smallest amount of context needed for the current decision.

### Three supported situations

1. **Specific station:** a particular machine or cable station. It can have a personal name, gym, load steps and optional setup notes. Two identical-looking machines are not merged automatically.
2. **User-confirmed comparable setup:** for example, a standard barbell setup the lifter chooses to use across locations. This is a recording convention, not calibration or proof of equal execution.
3. **Unknown setup:** the person has not supplied enough context. Logging still works; comparisons disclose the limitation and automatic load suggestions remain conservative.

Do not require people to create separate records for every interchangeable dumbbell. Conversely, do not assume that equal labels on two machines mean equal resistance. The system needs both simplicity and a way to retain real distinctions.

### Loading conventions are part of the record

Distinguish total external load, load per side, machine display value, added bodyweight load and assistance. These categories can change the meaning or direction of a number. A larger assistance setting must not be celebrated as a heavier lift.

The first implementation should support only conventions it can represent faithfully. Unsupported work may be recorded explicitly without derived strength claims; it must not be coerced into an ordinary kilograms field merely to fit the interface. Canonical unit conversion remains useful, but it does not make different loading conventions comparable.

Optional photos and notes help identify a setup; they do not validate mechanics. A meaningful setup change can create a dated variation. Do not assume every changed note breaks a series—let the user state when the change matters and keep the history discoverable.

### Substitution policy

A substitute is an alternative the user accepts for a routine position. It can preserve the plan's broad intention while having its own performance history. It does not inherit the old station's load or records.

The first release offers user-approved alternatives and remembers them by gym. Automatic ranking by a claimed “equivalent hypertrophy stimulus” is outside scope. No conversion ratio between machines is invented.

## 6. Decide what a trustworthy comparison actually means

“Same machine” is necessary for some comparisons, but not sufficient. A warm-up, a drop set, an early working set and a fatigued late set can represent different work even on the same equipment.

**Decision:** start with a limited descriptive comparison that people can audit, and give every comparison a way to open its source sets.

### Initial comparison contract

- Select the same movement, routine role where known, recorded setup and load convention.
- Compare against the most recent eligible prior session by default, with the dates visible. Let users choose another period deliberately.
- Keep warm-ups and explicitly different set types separate. Unknown imported set types are disclosed rather than silently treated as identical.
- Show load and reps together. If one rises while the other falls, show the tradeoff without automatically declaring improvement.
- When comparing repeated working sets, state the matched count and order. Use the first common number of eligible sets; show unmatched sets and session totals separately. Do not select only the most favorable sets after seeing the result.
- Retain differences in rep targets, effort reports, ordering and rest as context. Absence of a recorded difference is not evidence that conditions were identical.
- Keep volume exposure and performance comparison separate. More logged sets describes more work, not necessarily better performance or more muscle growth.

This is a proposed product convention to validate for comprehension. It is not a scientifically validated strength test. If users' set structures make ordinal matching misleading, reduce the comparison to clearly labeled side-by-side sets until a better rule is established.

### The language of the review

| Evidence | Appropriate message | Avoid |
| --- | --- | --- |
| More reps at the same recorded load and setup | “More reps at this recorded load” | “You gained muscle” |
| More load with fewer reps | “Load increased; reps decreased” | “Stronger” without qualification |
| Different machine | “Different setup; shown separately” | A continuous progress line across the change |
| Optional effort rating | “You reported fewer reps in reserve” | A measured fatigue or recovery claim |
| Sparse history | “Not enough comparable sessions yet” | A neutral-looking default score |
| Higher fractional volume | “Recorded exposure increased under this counting method” | “You reached your optimal volume” |

**Review rhythm:** offer the previous comparable session during training and an optional period/block review outside it. Do not make every workout end in a questionnaire. The first useful review can be built from imported history, but its uncertainty must travel with it.

**No aggregate readiness grade:** a single score would hide which facts are known and which are inferred. Showing the actual tradeoffs is the feature.

## 7. Correct the record without silently rewriting decisions

Trustworthy history includes the ability to fix mistakes. The product must distinguish an intentional correction from a new workout and from a changed plan.

Recommended behavior:

- A corrected set updates relevant descriptive summaries and is visibly identified as corrected where provenance matters.
- A correction does not automatically replay previously accepted progression decisions or rewrite completed sessions.
- A setup correction lets users preview affected comparisons before reclassification.
- Undo is available for reversible edits. User-requested deletion must genuinely remove the requested data according to the eventual retention design; an audit trail is not a reason to retain everything forever.
- Imported facts retain their source association and mapping decisions. Mapping a name must not fabricate equipment identity.
- Existing immutable session instants and derived-duration rules remain architectural constraints. Any future correction mechanism for dates needs a separate design; this blueprint does not authorize mutating immutable timeline fields.

Liftosaur's history documentation explicitly distinguishes editing a past workout from rerunning program progression. That is a useful precedent for keeping recorded facts and future decisions separate. [History documentation](https://www.liftosaur.com/features/workout-history)

## 8. Resolve onboarding and navigation at the product level

### Onboarding

Offer three clear starts: use an existing plan, build a routine, or log a workout now. Do not block logging behind goals, body measurements, a gym inventory or a subscription question.

History import and program import are different tasks. A history file records completed work; it cannot reliably reconstruct all intended prescriptions. The app may propose a routine from history, but the user confirms it.

The first moment of value is the user's own next session ready to run—not an empty dashboard with sample progress. Equipment context can be added at the first relevant movement. Sample data, when used to explain a screen, must be visibly separate from personal records.

### Product surfaces

Organize around **Train, Plan and Review** as a working navigation model to test. History is accessible inside Review and from exercise context; equipment is accessible where a plan or set needs it. Settings holds preferences and data controls, not the primary migration invitation.

This is a proposed information architecture, not authorization for a visual redesign. Test whether people can find raw history as easily as today before changing navigation. Preserve the active-session access pattern so exploring a plan or review does not hide or lose the live workout.

## 9. Define the role of AI before it becomes a distraction

**Decision:** AI is not the main product surface and is not necessary for the first release.

A later bounded use could help interpret a user-provided plan or summarize an already-computed review. Every extracted prescription would have a preview; every summary would be constrained to supplied facts. Generating unreviewed training advice, silently changing a plan or converting machine loads is outside this direction.

Any external model integration would require a separate decision about personal-data transfer, consent, cost and evaluation. It must not become a requirement for offline logging. A deterministic comparison should not be replaced with a language model merely to sound more helpful.

## 10. Resolve the remaining engineering direction without prescribing code

Preserve the existing separation of pure training logic, persistence, UI and feature composition. Plan semantics and comparison rules should be testable independently of a screen. Save whole user decisions atomically. Read-only prepared snapshots should continue to support the logger without per-render database work.

New planning data must be additive and versioned. Sync-conflict behavior belongs in the product specification before implementation. Two devices must not silently turn one routine into a mixture of incompatible versions.

Performance must be evaluated using realistic multi-year histories and repeated equipment changes. “Local-first” is a behavior to verify under offline use, recovery and account changes, not a promise that every read is instant.

Do not rewrite the store or replace the native app stack to make room for this plan. Existing foundations should be reused unless measured evidence identifies a specific obstruction.

## 11. First-release acceptance scenarios

Use these as the common brief for a prototype, implementation and validation. Numbers here describe a test scenario, not training advice.

| Scenario | What the person must be able to establish |
| --- | --- |
| Own plan | Prepare their real next routine without accepting generated exercises |
| Missed day | Find the correct next session after an unscheduled gap |
| Two gyms | Keep the same routine intention with different machine histories |
| Occupied station | Make a one-day substitution and later return to the usual station |
| Short workout | Save completed work without reducing future planned set counts |
| Repeated exercise | Keep two roles of the same movement distinct |
| Unknown import | Recognize missing equipment information and avoid false comparisons |
| Correction | Fix a mistaken set without duplicating it or silently changing future prescriptions |
| Recovery | Relaunch with the same committed workout facts and plan context |
| Review | Explain the comparison's dates, included sets and exclusions |
| Accessibility | Complete the journey with larger text, VoiceOver and reduced motion |
| Exit | Export saved work without payment or an active network connection |

## 12. Where further product reasoning stops being productive

We can decide the semantics, scope and claim boundaries. We cannot decide from a desk whether setup management is worth its effort, whether users want a block review, or whether this connected experience beats their existing app.

The next product evidence is an observed end-to-end task with actual lifters and their plans. Until then, additional feature ideation has diminishing value. Continue with the broader operating decisions in [Business and validation](HARDSET_BUSINESS_AND_VALIDATION.md), then run the prepared research rather than enlarging the feature list.
