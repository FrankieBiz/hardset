# Hardset: major product bets and strategic pivots

**Research date:** 9 November 2026
**Status:** The owner endorsed this direction on 9 November 2026 and requested continued planning. Detailed scope, prices and launch commitments remain proposals; no implementation is authorized by this document.
**Audience:** Product owner deciding what Hardset should become.

## Planning continuation

The direction has been developed into two decision documents:

- [Product blueprint](HARDSET_PRODUCT_BLUEPRINT.md): first-release scope, plan/workout semantics, equipment context, comparison rules and acceptance scenarios.
- [Business and validation](HARDSET_BUSINESS_AND_VALIDATION.md): free/paid boundaries, billing hypothesis, distribution, operating model, research protocol and explicit pivot/blocking conditions.

Read this document for the researched rationale; use those documents for the proposed decisions and next evidence-gathering work. They contain no claim that the proposed capabilities have shipped.

## The recommendation

**Build Hardset into the training workspace for self-directed lifters: bring your plan, adapt it to the gym in front of you, and see which results actually compare.**

Hardset already has a useful foundation: fast logging, explicit machine identity, local persistence, history, volume analysis and a cautious approach to claims. But those strengths currently describe how the software works more clearly than why someone would leave their existing app.

The larger opportunity is to connect **planning, real-world execution and review**. A lifter should be able to run the same training intention across different gyms, keep meaningful performance histories, understand changes over a training block, and choose what to do next without surrendering control of their program.

This is a proposed expansion from a logger into a decision-support product. It preserves the commitment against invented certainty. It also requires reconsidering the assumption that a useful logger should remain largely passive.

### The five big decisions

| Decision | Proposed change | Strategic purpose | Priority |
| --- | --- | --- | --- |
| Own the training plan | Add user-authored routines, training blocks and durable plan versions | Give users a reason to return before every workout | Foundation |
| Make equipment a first-class training context | Extend machine identity into personal setup records and gym-specific plan adaptations | Address a concrete problem that generic exercise names handle poorly | Main differentiation hypothesis |
| Turn history into a useful review | Explain comparable performance, changes in training exposure and missing information | Give accumulated data a purpose beyond charts | Main retention hypothesis |
| Offer explicit progression rules | Let users choose understandable rules and approve suggested changes | Save repeated decisions without pretending to know the optimal program | Conditional expansion |
| Make switching and ownership part of the product | Bring history and programs in, preserve provenance, and make leaving safe | Reduce the cost and anxiety of trying Hardset | Adoption requirement |

**Recommended order:** validate the equipment problem, then deliver a complete plan-to-workout experience with equipment continuity and migration. Add a useful review before investing heavily in progression automation. Do not launch five separate initiatives at once.

## 1. What the current product establishes—and what it does not

This assessment uses the repository's current code, not only the older README or competitive review.

| Present foundation | Strategic limitation |
| --- | --- |
| Sessions, set logging, recovery and rest-timer infrastructure | Reliable execution is essential, but reliability still needs physical-device proof |
| Exercise × machine performance history and gym management | Identity exists; a complete setup-and-substitution workflow does not yet exist |
| Volume reports, progression charts and saved workout receipts | These describe records but do not yet form a coherent training-block review |
| CSV import and CSV/JSON/SQLite export | Portability exists; guided mapping and a complete program migration experience remain opportunities |
| Optional lifetime purchase for the deep muscle map; logging, history and exports remain free | The current paid benefit is narrow; willingness to pay has not been established |
| Repeat-workout implementation on the feature branch | It is a starting point, not a routine system, training strategy or proven differentiator |

Repository anchors: [root composition](../Packages/HardsetKit/Sources/HardsetFeature/HardsetRootView.swift), [machine-separated progress](../Packages/HardsetKit/Sources/HardsetCore/Progression.swift), [data transfer](../Packages/HardsetKit/Sources/HardsetStore/DataTransferStore.swift), [current purchase promise](../Packages/HardsetKit/Sources/HardsetFeature/LifetimePurchaseSection.swift), and [repeat-workout proposal](PRODUCT_DIRECTION.md).

**What is unknown:** actual retention, customer acquisition cost, willingness to pay, the prevalence of multi-gym training among prospective users, and whether people understand or value Hardset's certainty language. None of those should be filled in with plausible-looking numbers.

## 2. What fresh research changes

The earlier competitive review is useful historical context, but its broad superiority ratings and competitor limitations are not sufficient evidence for current positioning. This research found strong overlap with several proposed Hardset advantages.

### Current competitive reality

The capability column below records what vendors document, not an independent quality assessment. The implication column is our judgment.

| Product | Documented capabilities | Implication for Hardset |
| --- | --- | --- |
| Hevy | Reusable routines, routine/workout/pinned exercise notes, and copying a past workout | Repetition and memory are expected utilities, not a distinctive product thesis. [Routines](https://www.hevyapp.com/features/gym-routines/), [notes](https://help.hevyapp.com/hc/en-us/articles/36011779117591-How-do-the-exercise-notes-routine-and-workout-notes-work), [copying workouts](https://www.hevyapp.com/features/best-way-to-track-workouts/) |
| MacroFactor Workouts | Custom and generated programs, multiple gym profiles, automatic progression, exercise swaps and export | “Knows your equipment” is too broad. Hardset must demonstrate a specific improvement in physical-machine continuity and comparison. [Product documentation](https://macrofactor.com/workouts/) |
| Alpha Progression | Free manual plans; optional progression recommendations using history and available weights; multiple gyms and periodization in Pro | User control and equipment-aware suggestions already coexist elsewhere. Hardset needs unusually clear provenance and a better complete workflow. [Official guide](https://alphaprogression.com/en/blog/alpha-progression-guide) |
| Liftin’ | Per-exercise progression rules, custom programs, Apple Watch support, iCloud sync without a separate Liftin’ account, and a one-time purchase option | Apple-native craft, account-free sync and rule-based progression are competitive requirements, not exclusive advantages. [Official press kit](https://liftinapp.co/press/) |
| Liftosaur | Editable programs, configurable progression, a simulation playground, import previews and data/program export | “Programmable” and “portable” are occupied positions. Hardset should reduce the effort needed to use them. [Features](https://www.liftosaur.com/features), [import/export](https://www.liftosaur.com/features/import-export) |
| RP Hypertrophy | Custom mesocycles and adjustments informed by pump, soreness and workload feedback | Competing as another adaptive hypertrophy coach would require a broader coaching product and a new evidence burden. [Official product page](https://rpstrength.com/pages/hypertrophy-app) |
| Fitbod | Workouts generated around goals, equipment and history; recovery modeling; generated workouts usable offline | Offline logging alone is not a sufficient market distinction. A generator is also a major competing business direction. [Official FAQ](https://fitbod.me/faqs/) |
| Boostcamp | Multi-week program building on mobile/web and a large coach/community program library | A content marketplace or comprehensive program builder would put Hardset into an established, resource-intensive contest. [Builder](https://www.boostcamp.app/features/program-builder), [library](https://www.boostcamp.app/features/program-library) |

This does **not** establish that competitors lack physical-machine tracking. Public pages are not exhaustive and no paid hands-on comparison was performed. Before making an exclusivity claim, test the exact workflow in current releases—including Liftin’, whose developer has previously described custom equipment variations. [Developer account of equipment variations](https://www.reddit.com/r/AppleWatch/comments/cojh21/)

### A concrete problem worth investigating

In a MacroFactor community thread, users describe duplicating exercises to separate different gyms; one reports that maintaining those duplicates across three gyms and travel is burdensome. In an RP thread, users discuss handling different machine loads by renaming exercises or altering what they record. These are direct accounts of friction, not evidence of its prevalence or proof that the current apps cannot address it. [MacroFactor discussion](https://www.reddit.com/r/MacroFactor/comments/1vb5j5c/same_workout_different_gym/), [RP discussion](https://www.reddit.com/r/RPHypertrophy/comments/1mr113m/different_gym_different_weights/)

**Inference:** a promising initial audience is the self-directed lifter who already has a program and regularly encounters different equipment. Their problem is preserving the meaning of a plan and its records through those changes.

**Confidence:** moderate that this pain exists; low that it alone supports a sufficiently large paying audience. Research the second question before building a large equipment platform.

### Scientific evidence sets the boundary

A dose-response meta-analysis examined 67 studies and compared direct, total and fractional set counting. It found support for increasing gains with greater volume alongside diminishing returns. That supports careful discussion of training exposure; it does not identify an individual user's optimal weekly target. Turning population-level relationships into personal prescriptions would require additional validation. [Pelland et al., published online December 2025; journal issue February 2026](https://pubmed.ncbi.nlm.nih.gov/41343037/)

Effort reports should not be dismissed as useless either. A study of 24 resistance-trained participants found useful RIR prediction accuracy under specific bench-press conditions. That is narrower than validating an app's recovery score, every exercise, or every user. Optional self-reported effort can add context while remaining explicitly self-reported. [Refalo et al., 2024](https://pubmed.ncbi.nlm.nih.gov/37967832/)

**Product consequence:** clearly distinguish recorded performance, calculated summaries, user-selected rules and uncertain interpretations. Do not sell increased logged weight as proof of muscle growth.

## 3. Choose a narrower audience and a clearer promise

### Initial audience

Self-directed intermediate lifters who follow their own or a coach's plan, care about progression, and train with machines or variable setups. Start with people who use multiple gyms, travel, or substitute equipment frequently. This is a proposed initial segment, not a permanent eligibility rule.

Their three central questions are:

1. **What am I doing today, given the plan I chose and the equipment available?**
2. **What did I actually do last time on this setup?**
3. **What changed over this block, and what should I consider changing next?**

Proposed positioning to test: **“Your program. Your equipment. Progress you can trace.”** This is a message hypothesis, not approved marketing copy.

Lead with useful outcomes. Keep certainty and methodology visible when they affect a decision; do not make a new user learn an epistemology vocabulary before logging a set. Honesty should make decisions easier.

### Alternatives considered

| Direction | Benefit | Main cost | Recommendation |
| --- | --- | --- | --- |
| Remain an excellent minimal logger | Focus, low complexity, clear craft | Weak reason to switch from mature loggers | Preserve as the foundation, but expand the core experience |
| Become an adaptive AI hypertrophy coach | Larger promise and potential recurring value | Coaching validation, support burden, stronger competition; conflicts with current product boundaries | Do not choose now |
| Become a self-directed training workspace | Builds on machine identity and honest records; keeps user agency | Must solve planning and review without becoming cumbersome | Recommended |
| Build a coach/gym management platform | Potential business customers and distribution | Accounts, permissions, administration and a different buyer | Defer; test lightweight exchange first |

The recommendation is to expand the job Hardset performs, not simply increase the number of screens.

## 4. Bet one: make the training plan the organizing object

**Decision:** move from isolated workouts to a durable, user-authored training plan with routines and optional multi-week blocks.

A routine answers what belongs in a session. A training block answers what the lifter intends to emphasize over a period. A workout records what actually happened. Those are different objects: an interrupted workout should not silently rewrite next week's plan, and changing a plan should not rewrite history.

### The experience

A lifter brings an upper/lower split into Hardset. The app remembers the next session in the sequence even when the schedule shifts. At the gym, the lifter can adjust today's workout without changing the whole plan, or deliberately save a change for future sessions. At the end of a block, the prior version remains available for comparison.

Major capabilities:

- Named routines and a flexible sequence independent of rigid weekdays.
- User-selected rep ranges, set counts, optional effort targets and rest preferences.
- Explicit “today only” versus “update the plan” changes.
- Plan versions and optional block goals, including a user-planned easier week.
- Import or build from existing work; a blank start always remains available.

**Why it matters:** the app becomes useful before training, not only during data entry. The current repeat-workout feature belongs here as an entry path. It does not replace a durable plan: copying completed sets can reproduce an unusually short or improvised session.

**Tradeoff:** planning can overwhelm casual users. Begin with routines and sequence; reveal block structure only when requested. Do not start by matching every periodization feature in competitors.

**Proposed success test:** participants can bring their existing split, run its next session after a missed day, and distinguish a one-day change from a permanent edit without help.

**Reject or simplify if:** users continue relying on another app or spreadsheet to understand what comes next, or the plan editor takes longer than the preparation it replaces.

## 5. Bet two: make real equipment part of the plan

**Decision:** extend machine tracking into personal equipment and setup records that preserve context across gyms.

“Chest press” is a movement. The particular machine, seat setting, attachment and loading convention describe how it was performed. A list of equipment categories cannot capture all of that.

### The experience

At Gym A, the lifter uses a named chest-press station with a remembered seat setting and load increments. At Gym B, the same routine offers a user-approved alternative. Each machine has its own history. Back at Gym A, the relevant history returns without duplicate exercise names or manual searching.

Major capabilities:

- Private, reusable records for physical stations, with optional setup notes/photos.
- Clear load conventions: stack label, plates added, per-side load, assistance, or another explicitly supported convention.
- Gym-specific bindings from a routine movement to suitable equipment.
- User-approved alternatives for busy stations, travel and temporary substitutions.
- A record of equipment/setup changes when reviewing performance.

Treat free weights sensibly: do not require users to catalog every dumbbell. Offer a lightweight, user-confirmed comparable setup when physical-station identity is unnecessary. Unknown must remain distinct from confirmed comparable.

**Why it matters:** this could turn an existing internal distinction into a complete user benefit. The strategic value would be continuity with little administrative work, not simply having a machine ID in a database.

**Boundary:** do not normalize “80 kg on A” into “equivalent kg on B.” Recording separate series is supportable; claiming a reliable conversion is a different problem. Likewise, alternative exercises are user-approved options, not automatically equivalent stimuli.

**Tradeoff:** setup entry can consume the time it saves. Capture context progressively during real use. Do not require a whole gym inventory before the first workout.

**Proposed success test:** users alternate between two gyms over several sessions without duplicate movement names, unwanted load carryover or loss of their usual setup notes.

**Reject or narrow if:** setup maintenance exceeds the benefit, or users find existing competitor variations equally easy. In that case keep equipment continuity as a supporting feature and lead with planning/review instead.

## 6. Bet three: replace disconnected charts with a training review

**Decision:** organize analytics around questions and explicit comparisons across a selected block or period.

### The experience

At review time, Hardset distinguishes:

- Comparable performance on the same recorded setup.
- Work performed on a different setup that should stay separate.
- Changes in exercise selection and completed training volume.
- Too little or too inconsistent information to draw a useful comparison.

A useful review might say: “You completed more reps at the same recorded load on this machine. Two sessions used another machine and are shown separately.” That is more actionable than one upward line combining everything.

Major capabilities:

- Compare periods using explicit equipment, exercise and set-selection rules.
- Show reps and load together; do not let tonnage alone define progress.
- Connect volume changes to the user's chosen emphasis and plan adherence.
- Explain missing attribution, sparse history, changed setups and imported uncertainty.
- Let users record what they intend to change next and revisit that decision later.

**Why it matters:** the accumulated log becomes a decision aid. A weekly or block review can create a reason to stay that is stronger than storing old workouts.

**Boundary:** comparisons describe recorded performance under stated conditions. They do not prove hypertrophy, diagnose recovery or establish that a program change caused an outcome. A personal “try this and review it later” workflow is useful; calling it a controlled experiment would overstate what the data can show.

**Tradeoff:** matching every condition can leave few comparable sessions. Use clear tiers—same recorded setup, changed context, insufficient information—rather than pretending every pair is identical or making all history unusable.

**Proposed success test:** given a realistic review with a machine switch and missing effort data, users correctly explain what improved, what cannot be compared and why. Then observe whether they return for another review without prompting.

**Reject or simplify if:** users cannot translate the review into an informed decision, or routinely mistake its conclusions for measured muscle growth.

## 7. Bet four: add transparent, user-selected progression

**Decision:** investigate an optional rule engine after planning and comparable history work. Do not begin with autonomous coaching.

The current “not a coach” boundary deserves a precise interpretation: Hardset can execute a user's chosen rule without asserting that the rule is biologically optimal. Whether to expand that boundary is a product decision, not an implicit consequence of adding a button.

### The experience

The user selects a progression rule and can inspect a plain-language example. Before the next session, Hardset shows a proposed change, the saved sets that triggered it, the equipment increment it used, and what happens if the user keeps the current load instead.

An illustrative rule—not a universal training recommendation—might increase load after all planned working sets reach a user-chosen rep threshold on the same setup. Unavailable increments, changed equipment or incomplete sessions produce an explanation or a request for a choice, not an invented number.

Major capabilities:

- A small set of understandable progression patterns with user-editable conditions.
- Preview/simulation before activation.
- A visible reason for every suggestion and a history of accepted or overridden changes.
- Separate rules by movement context when the same exercise has different roles.
- Manual hold, reset and user-planned deload options.

**Why it matters:** reduce repeated arithmetic and remembering while maintaining control. Rules alone are not novel; Liftin’ and Liftosaur already demonstrate that category. Hardset's proposed advantage is the combination of ease, equipment context and traceability.

**Tradeoff:** a rule can still be poorly chosen. Avoid implied endorsement, do not quietly enable one, and measure whether users understand its behavior. Extra prompts must not slow ordinary logging.

**Proposed success test:** before accepting a suggestion, users can explain why it appeared and predict what their chosen rule would do after a changed-machine or incomplete session.

**Do not proceed if:** users primarily want the app to choose the optimal program for them. That demand points to the separate coaching pivot and requires a separate decision.

## 8. Bet five: make migration and ownership a complete experience

**Decision:** treat bringing an existing training life into Hardset as a primary product journey, not a settings utility.

Existing lifters already have history, custom names and programs elsewhere. Asking them to start over removes the very context Hardset wants to use. But CSV export alone is not a unique advantage: Strong documents export, and Liftosaur documents structured migration and backup workflows. [Strong export](https://help.strongapp.io/article/235-export-workout-data), [Liftosaur import/export](https://www.liftosaur.com/features/import-export)

### The experience

A prospective user brings a supported history file, sees what was recognized, confirms ambiguous exercise and equipment mappings, and starts their actual next workout. Missing machine identity stays missing. Later, exporting preserves the distinctions Hardset introduced rather than flattening them away.

Major capabilities:

- Supported imports prioritized from the target audience's real source apps.
- A review of dates, units, exercise names, duplicates and equipment uncertainty.
- Safe correction of mappings with provenance and an understandable reversal path.
- Portable routines/blocks as well as completed workout facts.
- A human-readable summary for a coach, plus structured export for other tools.

**Distribution hypothesis:** useful program and review exchange could bring Hardset into existing coach–lifter relationships without building a coach marketplace. Begin with deliberate file/share actions; avoid requiring a social profile or a new account system.

**Tradeoff:** source formats change, and ambiguous data can become a support burden. Start with a small supported set and a clear compatibility promise. Do not promise universal migration or invisible conversions.

**Proposed success test:** users can import their real records, identify a deliberately ambiguous machine mapping, begin their existing plan and export it again without losing source facts.

**Reject broader integrations if:** most qualified users are content to start fresh or the support cost exceeds observed adoption value.

## 9. Business-model decision: charge for a coherent benefit

The present code offers an optional lifetime purchase for a deep muscle map while retaining free logging, history, imports, exports and existing gym/machine logging. That is the current product promise, not the older handoff's proposed subscription pricing.

**Recommendation:** keep that ownership promise. Investigate a paid planning-and-review package only after demonstrating repeated use. The question is whether people will pay to run and understand their own training more easily, not whether another analytical visualization can be paywalled.

| Option | Appropriate if | Risk |
| --- | --- | --- |
| One-time purchase for defined advanced capabilities | Value is mostly delivered on-device and the maintenance model is sustainable | Ongoing support revenue may not cover a long-lived product |
| Subscription for sustained planning/review value | Retained users repeatedly rely on the service and its ongoing improvement | Users may see recurring payment as unjustified for a local utility |
| Coach-oriented package later | Repeated coach use and a distinct buyer emerge | Splits product focus and introduces administrative requirements |

Do not select a price from competitor averages or promise a founding lifetime deal yet. First test the same credible product proposition with alternative payment structures, then model support, content and maintenance costs. Respect any existing purchases; no entitlement or pricing change is authorized by this document.

Measure credible purchase behavior when a usable offer exists. Interview enthusiasm and hypothetical willingness to pay are early signals, not revenue forecasts.

## 10. Major directions to decline or defer

| Idea | Decision now | What would justify revisiting it |
| --- | --- | --- |
| Universal AI coach/chatbot | Defer; weak fit with current advantage and high inference burden | Validated demand for coaching plus a defined evidence and evaluation program |
| Automatic muscle recovery or “hypertrophy score” | Decline as a headline capability | Validation of a specifically defined estimate and demonstrated usefulness without misleading users |
| Large social feed and challenges | Decline for the proposed audience | Evidence that social interaction is central to retention for the chosen segment |
| Hundreds of newly authored exercise pages/videos | Expand only for observed coverage gaps | Repeated blocked workouts, suitable expertise and a sustainable content process |
| Public database of every gym and machine | Defer | Private equipment records prove valuable and users demonstrate demand for sharing them |
| Coach marketplace/business administration | Defer | Repeated exchange evolves into measurable coach workflow demand |
| Apple Watch-first redesign | Defer as a separate strategic bet | Observation shows phone interaction is the main barrier among otherwise-retained users |
| Broad Android/web parity | Defer while validating the iOS proposition | Repeated qualified demand makes platform exclusion the main growth constraint |
| Nutrition, rehabilitation or general wellness platform | Decline for this direction | An explicit decision to change the product and audience |

Reliability, accessibility, trustworthy recovery and physical-device release checks remain prerequisites throughout. They are not optional polish competing with the strategy.

## 11. Validate the strategy before authorizing a large build

### Discovery: test the audience, not a feature pitch

Recruit roughly 12–15 self-directed lifters as a practical discovery cohort, not a statistically representative sample. Include people with multiple gyms, people with several machine variants at one gym, single-gym users, and a few people who use a coach's plan. Balance against recruiting only people already enthusiastic about Hardset.

Ask them to show their last few workouts and their actual plan. Observe how they choose today's session, locate a previous result, handle an occupied machine and decide whether something improved. Ask about the last real occurrence before showing the proposed solution.

Collect evidence with permission: current workarounds, frequency and consequence of failures, time spent preparing, switching anxieties, and what they refuse to give up in their current app. Do not contact or recruit anyone automatically as part of this plan.

### Compare the alternatives in real tasks

Use current versions of Hevy, MacroFactor, Alpha Progression, Liftin’ and Liftosaur for the same small task set. This is follow-up work, not research already performed. Include:

- One exercise on two physical machines in the same gym.
- The same routine across two gyms.
- A one-day substitution that should not rewrite the plan.
- A missed day in a repeating split.
- A review spanning an equipment change.
- Import/export with unknown equipment and duplicate exercise names.

Record the complete workflow, not just whether a feature exists. If an existing app already solves these tasks cleanly, narrow Hardset's claim or change direction before building.

### Prototype the complete experience

Test one scenario from beginning to end: bring a plan, bind it to two gyms, run a modified session, inspect a comparison, and prepare the next session. Use an interactive prototype or supervised manual service before implementing every underlying system.

Measure preparation effort against each person's current method. Counterbalance which interface they try first where practical. Distinguish learning effects from lasting benefits.

### Pilot and decision gates

The following thresholds are **proposed management gates**, chosen to make decisions concrete. They are not published industry benchmarks or evidence of efficacy.

| Gate | Proposed evidence needed to proceed | Failure response |
| --- | --- | --- |
| Problem is worth owning | At least half of the discovery cohort demonstrates a recurring, consequential problem in planning/equipment continuity or review | Narrow the audience or pivot the proposition |
| Workflow is understandable | At least 8 of 10 prototype participants complete the main journey without assistance; all correctly distinguish copied plans from logged facts | Redesign before implementing automation |
| Equipment continuity is useful | Pilot users who actually train across setups use the context repeatedly without maintaining duplicate exercise names elsewhere | Reduce setup burden or demote it from the lead promise |
| Users return for the complete product | At least 6 of 10 eligible pilot users use Hardset as their primary logger for four training weeks, with reasons captured for every exit | Investigate missing essentials before adding more features |
| Review is trustworthy | Users correctly interpret a comparison containing an equipment change; any serious misleading interpretation blocks expansion | Change comparison rules or presentation |
| Reliability is acceptable | No unexplained lost/duplicated committed sets in the pilot and successful recovery/reconciliation tests | Pause rollout and diagnose; a small pilot cannot establish zero future defects |
| Monetization is credible | A real offer produces purchases among retained users, with support costs and cancellations understood | Reconsider packaging, price or business viability |

No universal “sets per week” or “workouts per week” metric should pressure users into training more. Evaluate return over their intended sessions and capture interruptions such as travel or illness.

## 12. Sequence the work by outcomes

| Phase | Product outcome | Included scope | Exit evidence |
| --- | --- | --- | --- |
| 0. Establish the need | A defensible audience and switching reason | Interviews, task-based competitor comparison, device reliability checks | Repeated observed problem and a clear segment |
| 1. Run my actual plan | A lifter can bring and repeat their chosen training | Routines, flexible sequence, basic migration, today-only changes | Independent completion and repeat use |
| 2. Keep context across gyms | The plan follows equipment changes without corrupting comparisons | Personal setup records, gym bindings, user-approved alternatives | Multi-setup pilot success |
| 3. Understand the block | Saved history supports a useful review | Comparable progress, exposure changes, explicit unknowns, next-block notes | Correct interpretation and voluntary repeat use |
| 4. Reduce repeated decisions | Users can safely delegate chosen rules | Optional rule previews, explanations, overrides | Comprehension and useful adoption |
| 5. Expand deliberately | A sustainable, differentiated product | Validated paid package; selective coach exchange or platform work | Retention, actual payment and support economics |

Phases 1 and 2 should be designed together even if delivered in slices. A routine system that ignores equipment would miss the central hypothesis. Phase 3 should be prototyped early with imported history so its value does not have to wait months to be assessed.

Do not attach delivery dates until the audience tests and technical discovery are complete. This plan establishes dependencies and decision gates, not a disguised implementation backlog.

## 13. Decisions to make before the next major implementation

1. **Audience:** choose self-directed lifters with equipment/context friction as the initial segment, or explicitly choose a broader coaching audience.
2. **Product boundary:** agree that plans and descriptive review fit Hardset; decide separately whether user-selected progression rules do.
3. **Lead promise:** choose continuity and understandable comparison as the proposition to test, with no claim of market uniqueness yet.
4. **Commercial promise:** retain access to saved training and current free capabilities; test paid incremental value before changing packaging.
5. **First investment:** authorize discovery and a complete prototype, not a collection of loosely related features.

My recommendation is to adopt the first four as working hypotheses and make the fifth the next piece of work. The earlier repeat-workout change can support the prototype, but it should not dictate the whole roadmap.

## Research method and limits

This is a qualitative desk-research plan combining repository inspection, official product/help pages, two illustrative community discussions and published research. All linked sources were consulted on 9 November 2026. Source publication dates vary; source websites can change.

Vendor pages support statements about advertised or documented capabilities, not independent assessments of reliability, ease of use or outcomes. Community accounts support the existence of reported friction, not market size, prevalence or current competitor limitations. Scientific studies inform claim boundaries, not the efficacy of any app described here.

No customer interviews, paid trials, instrumented usability study, market-size estimate, SEO dataset or willingness-to-pay study was performed. Those omissions are deliberate: they are the next validation work, not numbers to infer from web search. Broad market news and unverified platform announcements were not used to justify the recommendation.

This plan supersedes the earlier competitive review's unsupported strategic rankings for purposes of future planning. It does not overwrite permanent architectural decisions, authorize implementation, or establish that the repeat-workout feature has shipped to production.
