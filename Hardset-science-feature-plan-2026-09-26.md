# Hardset science feature decision — 26 September 2026

**Status:** Product planning and research. No implementation authorized or started.

## Decision

Build **Progression Guide** as the next substantial feature. It should turn Hardset's existing exercise-and-machine history into a small, optional decision aid at the moment a lifter is about to do a set. The first version uses a lifter-authored rep range, recent comparable working sets, and the real load increment available on that machine. Every suggestion says why it appeared and can be ignored or edited. No training data is silently rewritten.

This is a product recommendation, not a claim that a particular algorithm has been clinically validated to maximize hypertrophy. The evidence supports tracking relevant training variables and progressively challenging training over time; the exact increase rule is a transparent coaching heuristic that must be evaluated with users.

## What is already present

Hardset already logs work/warm-up/drop sets, optional RPE, specific physical machines, past-set prefills, personal records, per-machine charts, seven-day fractional muscle volume, plan coverage, and methodology disclosures. A plan entry can also hold an optional user-authored set count in the current working tree. These are sound foundations, but the user must connect them mentally: a prefilled last set or a chart does not answer what to attempt today. The research explanation is usually behind a separate sheet.

## Why this feature first

| Approach | Benefit | Main weakness | Decision |
| --- | --- | --- | --- |
| More science dashboards and scores | Immediately visible; can reuse current volume data | A score invites unjustified thresholds and is easy to ignore during training | Make existing facts easier to find, but do not lead with a new score |
| Full automatic coach, program generator, fatigue and deload engine | Big marketing story | Needs many inputs and unvalidated personal response assumptions; high release and trust risk | Defer |
| Transparent progression at the set | Solves a repeated gym decision using history Hardset already owns | Requires careful comparison rules and a user-defined intent | **Build first** |

Major competitors now offer next-set guidance, and sampled App Store reviews specifically praise taking the guesswork out of progression. That supports the category demand, but those reviews are self-selected; they do not prove Hardset's users will want this exact design. Hardset's credible distinction is that the guidance is tied to the **same exercise on the same physical machine** and explains its source. [Alpha Progression's current progression description](https://alphaprogression.com/en/glossary/progression-recommendations), [Hevy's feature guide](https://help.hevyapp.com/hc/en-us/articles/33106320824727-Everything-You-Need-to-Know-About-the-Hevy-App-2025-Features-Guide), [MacroFactor App Store reviews](https://apps.apple.com/us/app/macrofactor-workouts-tracker/id6737156524?platform=iphone&see-all=reviews).

## Proposed experience

1. **Plan:** The lifter may set a rep range for a planned movement, for example 8–12. Existing optional intended set count remains their choice. No range is auto-filled from an uncited exercise taxonomy. On an unplanned workout, the lifter can optionally set a range from the live exercise menu.
2. **Before the next set:** Put a short line next to the set row: “Last time on Cybex Leg Press: 160 lb × 12.” If there is enough comparable history and a user-authored range, offer “Option: try the next 5 lb step, aiming for your 8–12 range.” The card must say which session/set and machine produced it. If the current machine differs, show the other-machine history as reference only, never as an exact prescription.
3. **After the set:** Show a factual result: “Same load, +1 rep versus last time on this machine” or “First result on this machine.” Do not equate every PR with muscle growth. Let the lifter keep the load, change it, or dismiss guidance without a penalty.
4. **Why:** A tap reveals the logged comparison, the lifter's chosen range, the available increment, and a short evidence note. The product logic is labeled “rule based on your history”; broad training evidence is labeled separately. When confidence is poor, the app says “not enough comparable history” instead of inventing a target.

### Initial decision rule to test, not yet a final algorithm

Compare only completed **working** sets on the same exercise and machine. Exclude warm-ups, drops, invalid measurements, and an open session. Keep set position comparable and consider the previous two or three exposures, not just one outlier. If the lifter has reached the top of their chosen rep range at the current load in comparable recent sessions, offer the smallest load step actually available on that equipment. Otherwise offer repeating the load and pursuing another rep within the range. Never auto-increase after an incomplete or inconsistent record; never auto-decrease as a “fatigue diagnosis.” A manually selected next load always wins.

The exact threshold for offering an increase, and what to do after missed reps, need prototype and beta validation. The proposed rule should remain a simple, inspectable heuristic; it is not itself a finding from a resistance-training trial.

## Science and its limits

- The [2026 ACSM position stand summary](https://acsm.org/resistance-training-guidelines-update-2026/) emphasizes regular participation, effort, individual goals, and broadly higher volume for hypertrophy. It does not establish a universal ideal progression increment. A [2025/2026 dose-response meta-regression](https://link.springer.com/article/10.1007/s40279-025-02344-w) found higher volume associated with more hypertrophy and strength, with diminishing returns, and found a different frequency relationship for hypertrophy versus strength. Thus Hardset can show dose and trend, but should not turn a set count into “growth predicted.”
- [Load comparisons](https://pubmed.ncbi.nlm.nih.gov/33433148/) found similar hypertrophy across a range of loads when sets were taken to failure, while heavier loads improved maximal strength more. That argues for a lifter-selected rep range and goal rather than an app-wide “correct” weight. It also limits what this study says about sets stopped short of failure.
- A [2024 randomized trial in trained lifters](https://pubmed.ncbi.nlm.nih.gov/38393985/) found similar quadriceps hypertrophy at failure versus about 1–2 reps in reserve, with greater acute fatigue at failure. A [meta-regression](https://pubmed.ncbi.nlm.nih.gov/38970765/) explored proximity to failure, but its RIR estimates limit precision. Optional effort logging can contextualize performance; it should not become a compulsory score or a requirement to log a set. [RIR estimation itself has measurement error](https://pubmed.ncbi.nlm.nih.gov/38595310/).
- A [2024 rest-interval synthesis](https://www.frontiersin.org/journals/sports-and-active-living/articles/10.3389/fspor.2024.1429789/full) suggests a possible small benefit to longer rest compared with very short rest, with heterogeneity. Actual rest duration should be captured before interpreting a falling rep count as a recovery or progression signal. A timer setting is not an observed rest interval.
- [Volume-matched split versus full-body comparisons](https://pubmed.ncbi.nlm.nih.gov/38595233/) show no clear hypertrophy advantage to one structure. A plan-quality score based on split labels would overstate the evidence.

## Follow-on work, ranked

1. **Make existing science apparent.** Put one measured, machine-specific comparison on the live exercise and a concise “what changed” summary after a workout. Bring the source/uncertainty disclosure next to each insight. This can ship as the first slice of Progression Guide.
2. **Volume context, not volume grades.** Show this seven-day window against the lifter's own recent windows, indicate known versus unattributed sets, and distinguish direct from fractional credit. Present ACSM's approximate ten-set context as general education, not a red/green pass line or a personal optimal target. The current fractional method and the broad ACSM figure are not automatically interchangeable.
3. **Effort and rest context.** Make optional RPE history useful beside performance and record actual rest intervals if the user opts into the timer. Show associations as observations, not diagnoses. Add after the core comparison works reliably.
4. **Plan coverage in plain sight.** Surface the already-computed uncredited muscles and days trained on the Plan screen; do not label the plan “bad,” since exercise preference, goals, and volume matter.

## Do not build yet

No “hypertrophy score,” hard MRV/MEV bands, inferred recovery/readiness score, pain-based substitution, automatic deload trigger, or AI explanation that cites studies without a traceable link to the actual calculation. A [2024 deload trial](https://pubmed.ncbi.nlm.nih.gov/38274324/) did not establish a simple universal deload benefit. More data and user validation would be needed before those claims are credible.

## Validation before committing to the full feature

- Show a clickable prototype to 8–12 intermediate lifters who use at least two physical machines for one exercise. Ask what they would do next **before** revealing the guide, then see whether its explanation changes the decision and whether they trust it. Include people who do not already track RPE.
- In a private beta, measure opt-in guidance use and correction rate without adding third-party analytics or changing the app's privacy promise. Ask for voluntary feedback: was the suggested load feasible on the actual machine, and did the card slow logging?
- Technical acceptance for a future build: same-machine identity is preserved; missing history yields no recommendation; every suggestion has a reproducible reason; user edits always win; warm-ups/drops do not seed guidance; existing workout entry speed is not degraded.
- Keep current release gates separate: a new insight feature does not validate physical-device AlarmKit, production iCloud sync, signing, or privacy disclosures. Decide whether this is a 1.1 beta feature or a revised 1.0 scope only after prototype testing.

## Research method and confidence

Reviewed the current Hardset source and release audit, the 2026 ACSM position stand summary, systematic reviews/meta-regressions, selected controlled trials, official competitor feature descriptions, and sampled first-party App Store reviews. Confidence is **high** that users need easier access to logged context; **medium** that this particular progression guide will be preferred; **low** that any one automatic increase rule optimizes individual hypertrophy. The next evidence required is prototype behavior with Hardset's target lifters.
