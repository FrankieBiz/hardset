# Plan 1 — Progress and import correctness

Baseline: `main` after PR #4. Source of the defects: the 2026-11-18 "Saved workouts, Progress tab and body-part library" entry in `.agents/HANDOFF.md` (open and owner decisions) plus the 2026-11-19 review entry.

## Objective
A lifter who imports their history sees it on Progress, and the Progress tab is fast, consistent with the scorecard, and never ranks things that cannot be ranked.

## Why this is first
The Progress tab is the surface we just merged and nobody has used. The import gap is the worst possible first impression: a lifter arrives with two years of training in Strong, imports it, opens Progress, and sees nothing. That is a credibility failure in the one area the product claims to be honest about.

## Non-goals
- No new Progress features, no new chart types, no tour step for Progress.
- No change to the 0.5 indirect-set convention, the record tolerance, or any `DECISIONS.md` invariant.
- No touching `HANDOFF.md` or `.agents/HANDOFF.md`.

## P1. Imported history appears on Progress
**Investigate first, then implement.** Reproduce with a fixture CSV shaped like a Strong export: three movements, two whose names match catalogue entries and one that does not.

Today the importer creates a brand-new custom movement for every imported name, so imported sets belong to movements the user has never logged normally, and equipment is deliberately left without a machine identity.

Required behaviour:
- Match an imported movement name to an existing catalogue or custom movement by exact normalised name before creating one. Only create when nothing matches.
- Imported sets keep machine identity unknown. They form their own series, labelled in the UI as imported history with no machine. **Never merge an imported series into a machine series** (`DECISIONS.md` §20).
- Progress must state what it is showing for that movement: a real machine series, or "imported · machine not recorded".

Acceptance:
- The fixture import produces sets on the two matched movements and one new movement for the third.
- A Progress render for a matched movement shows the imported sets, with the not-recorded label.
- A test asserts that importing the same CSV twice stays idempotent (it already does; do not regress it).
- A test asserts two machines plus imported history produce three distinct series.

## P2. Record stars must not replay the whole history
`LoggerStore` record stars still replay every session for a movement: about 0.8 s per 2,000 sets of one machine in a debug build. The trends path already solved this by bounding the replay.

Acceptance: a written measurement before and after on 2,000 sets of one movement; the after must be under 50 ms in a debug build, matching the precedent set for the stall check. Recorded in the PR with the command used.

## P3. One rule for "the earlier session we compare against"
The live set row and the receipt scorecard currently pick the earlier session by different rules. Move the rule into Core so both call it.

Acceptance: one implementation, both call sites, a test that pins the rule, and the PR states which rule won and why. No date-based tie left to dictionary order.

## P4. The Progress badge reports the weaker of the two estimates
The six-week change is computed from two estimates; the badge currently shows the latest one's certainty while the scorecard takes the weaker. Make the badge take the weaker.

Acceptance: a test with a high-certainty prior and a low-certainty current asserts the badge reads low; the scorecard and the badge agree by construction.

## P5. "Most improved" must not rank different metrics together
Ranking a percentage improvement in estimated volume against a percentage improvement in load is not a comparison. Either rank within one metric and name it, or present them as separate groups.

Acceptance: a test with mixed metrics; the UI never puts two incomparable percentages in one ordering; the label states the metric.

## P6. A machine movement with no machine says so
A movement whose logged sets carry no machine currently shows no series and no explanation.

Acceptance: the board renders an explicit "no machine recorded" state for that movement instead of nothing, and a test covers it.

## Verification
- `make check` exit 0 with counts quoted.
- Native CI green on the pushed commit, run ID quoted. A cancelled run is not green.
- The Progress board and the movement chart change, so the macOS render suite must run and at least one new PNG per changed state must be looked at and described in the PR.
- Run `python3 Tools/check_query_performance.py --require-indexes`; any new query must use an index.

## Risks
- P1 touches import, which is the one path that writes a stranger's data into the database. Import must stay atomic and idempotent; a partial import is worse than no import.
- The Progress board reads per movement. Do not introduce a per-render query (`HANDOFF.md` invariant 3); hoist into the snapshot the screen already loads.
- Do not "fix" P1 by inventing a machine name from another gym's history.

## Owner decisions this plan needs
- None. P1's default (match by name, keep machine unknown, label it) is the decision unless the owner overrides.
