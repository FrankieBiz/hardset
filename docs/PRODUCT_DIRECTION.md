# Hardset: make personal history useful before the next set

## Product judgment

Hardset exists for intermediate lifters who already make training decisions. Its
advantage is a trustworthy record of what happened, attached to the actual equipment,
with very little work between sets. The implementation now has logging, recovery,
receipts, progression, volume, import/export and native UI verification. Older README
and initial handoff claims are not an accurate inventory of today's code.

The largest workflow gap is that accumulated history does not help assemble the next
workout: every start is empty. A lifter repeating a split must repeatedly reconstruct
work the app already knows. This is a product-level gap, not a visual styling problem.

## Decisions

1. **Make history a starting point.** Train now offers a completed-workout chooser,
   explicit preview and atomic start. Repeat completed working-set counts and movement
   order, preserving repeated occurrences and splitting equipment changes. Do not copy
   logged facts, timestamps, records, warm-ups or uncompleted planned sets.
2. **Keep equipment identity stronger than convenience.** Retain only active machines
   in the selected gym. Unknown or unavailable equipment gets blank drafts. Exact-machine
   suggestions use latest history, not stale source-workout weights. Persist that policy
   through recovery using additive migration v10; old sessions retain their behavior.
3. **Keep authorship with the lifter.** Repetition is an explicit choice, not a default
   program or volume prescription. The preview discloses exclusions and allows backing
   out without saving anything. Users can add movements, sets and warm-ups in the logger.

## Delivered scope and acceptance

- Choose from the newest 50 completed sessions and inspect a preview before creating one.
- Keep distinct occurrences, working-set counts and eligible physical equipment.
- Disclose archived movement exclusions; reject empty or unfinished sources.
- Preserve recovery gating, atomic writes, immutable history snapshots and original facts.
- Test unknown-equipment safety through relaunch and a v9-to-v10 migration.

## Next major investments

These are directions, not implemented features or commitments to invented coaching:

- **User-authored routines:** names, editable order, set counts and explicit equipment
  alternatives. Build on the repeat workflow after observing real use; avoid a parallel
  routine engine before the interaction is established.
- **Comparable progress reviews:** answer whether recorded performance changed on the
  same equipment, separating changes in reps, load and completed sets. Explain insufficient
  evidence instead of compressing it into a readiness or hypertrophy score.
- **Physical-device release proof:** validate signed CloudKit and AlarmKit behavior and
  gym-floor readability. Simulator success does not establish these behaviors.

## Verification limits

`make check` compiles and tests portable Core/Store code, parses SwiftUI, checks query
plans and checks token contrast. Native SwiftUI compilation and the expanded UI journey
must pass Apple CI. Physical-device interaction, sync, alarm delivery and performance
remain separate checks. No new competitive or scientific claims were needed for this work.
