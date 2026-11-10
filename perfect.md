# Hardset — implementation and deployment plan

**Updated:** 9 November 2026

**Purpose:** turn the endorsed product direction into a sequence that can be implemented, verified, distributed and maintained. “Perfect” is the requested filename, not a promise of zero defects.

**Current scope:** planning. This file defines future execution; it does not authorize an App Store release, production CloudKit changes, paid services, pricing changes or outreach. Existing authorization for ordinary branch delivery continues to apply.

## 1. The outcome

Ship a reliable iPhone product in which a self-directed lifter can:

1. Bring or author their training plan.
2. Prepare the next session despite missed days or a different gym.
3. Adapt equipment for today without silently rewriting the plan.
4. Save actual training with the correct context.
5. Review comparable work and understand exclusions.
6. Prepare the following session and export their records whenever needed.

Then extend that complete experience into optional multi-block planning, deeper reviews and explicit progression rules, contingent on observed use. Validate paid value and distribution after the core experience works.

The product sources remain [strategy](docs/HARDSET_STRATEGIC_PLAN.md), [product blueprint](docs/HARDSET_PRODUCT_BLUEPRINT.md) and [business/validation decisions](docs/HARDSET_BUSINESS_AND_VALIDATION.md). This document owns execution order, acceptance evidence and rollout. Product decisions should be updated in their source document and reflected here rather than duplicated inconsistently.

## 2. Baseline: distinguish existing code from releasable product

Snapshot inspected at commit `bfe79de8ff68ae056ef4bed6ea6ddb5baf30aaac`, branch `FrankieBiz/bobtail`:

| Area | Observed state | Consequence |
| --- | --- | --- |
| Working tree | Clean before planning | Preserve that baseline; stage only task-owned changes |
| Existing implementation | Logging, recovery, machines/gyms, volume/history, receipts, transfer and lifetime-purchase infrastructure | Extend the existing architecture |
| Repeat workout | Implemented on the feature branch with v10 policy migration and tests | Review and validate it as an early slice; do not equate it with the future routine system |
| Pull request | [Draft PR #1](https://github.com/FrankieBiz/hardset/pull/1), targeting main | It contains app changes as well as planning; merging it promotes both |
| Native feature run | [Run 42713517490](https://github.com/FrankieBiz/hardset/actions/runs/42713517490) failed | Real-app tests could not reach the start screen; root cause remains unproven |
| Most recent run at inspection | [Run 42729654582](https://github.com/FrankieBiz/hardset/actions/runs/42729654582) was in progress | Re-read its final result before acting; this snapshot is not a live status badge |
| Release tooling | Simulator CI and a local install script exist | There is no inspected, complete archive-to-App-Store release pipeline |
| Versioning | Generator currently emits version 1.0/build 1 | Add deliberate release-version inputs before uploading multiple candidates |
| Entitlements | Checked-in app entitlement file currently declares HealthKit only | Audit effective signed CloudKit/push entitlements and container configuration; missing declarations are an investigation lead, not a proven startup diagnosis |
| Physical verification | Device checklist contains open signing, alarm and sync gates | Obtain fresh candidate-build evidence on actual devices |

Do not inherit old README claims about native builds or handoff claims of green CI without checking the current commit. A documentation-only push can cancel a long-running branch workflow; preserve its artifacts and avoid repeated superseding runs while diagnosing a candidate.

**Immediate release status: held pending a verified native baseline.**

## 3. Execution rules and ownership

Use one active feature checkout per bounded milestone. The current workspace is already isolated. Start subsequent branches from a verified main, or explicitly record a dependency on in-progress work. Never stack unacknowledged dependencies or promote all branch contents merely to deliver a document.

Responsibility is assigned by role; one person may hold several roles. No additional workers are launched by this plan.

| Responsibility | Accountable role | Required output |
| --- | --- | --- |
| Product scope and claim boundaries | Product owner | Accepted scope and explicit decisions |
| Domain rules and persistence | Core/Store implementer | Tested behavior, additive migrations and compatibility evidence |
| Native interaction and accessibility | UI implementer | Complete user journey and reviewed native evidence |
| Integration and release | Release owner | Exact candidate commit, artifacts, gate results and rollout decision |
| Discovery and pilot synthesis | Research owner | Consented observations, contradictory findings and recommendation |
| Pricing, signing access and public distribution | Business/account owner | Actual offer/access decisions and authorized external actions |

Before implementation, replace role assignments with named responsibility in the milestone record. Do not announce dates before ownership, capacity and Apple validation access exist.

## 4. Dependency order and release boundaries

| Stage | Deliverable | Depends on | Exit gate |
| --- | --- | --- | --- |
| M0 | Trustworthy native baseline and release inventory | Current code | G0: app starts and saves on the candidate; failures diagnosed |
| M1 | Validated complete prototype and frozen first-release scope | Product documents; can run alongside M0 | G1: people understand and can complete the proposed journey |
| M2 | Plan/version/sequence foundation | M0, M1 | G2: semantics survive persistence and recovery |
| M3 | Equipment context, substitutions and guided migration | M2 | G3: identity and source facts survive all transitions |
| M4 | Basic comparable review and complete native journey | M2, M3 | G4: correctness, comprehension and accessibility |
| M5 | Internal signed candidate and external TestFlight pilot | M4, account/schema readiness | G5: reliability and observed repeated use |
| M6 | First public release of the free core experience | M5 | G6: release packet complete; explicit rollout decision |
| M7 | Deeper blocks/reviews and optional explicit progression | Pilot evidence; M6 not required for private experiments | G7: useful and understandable advanced capability |
| M8 | Paid package and selective distribution expansion | Retained value, commercial decisions, M7 | G8: entitlement, purchase and support evidence |

M2–M4 are internal implementation slices. The first product pilot needs the whole plan-to-review journey. Do not launch an unfinished editor and ask users to infer the missing value.

Research and release-readiness work may proceed independently. Same-code ownership must remain sequential unless explicit delegation assigns disjoint paths and integration responsibility.

## 5. M0 — make the current foundation releasable

### Work

- Resolve the latest CI outcome and retain the failed run's app logs, screenshots, crash reports and result bundles before artifact expiry.
- Reproduce the failure with the same commit, Xcode/runtime and launch configuration. Classify startup failure as migration, sync construction, signing/capability, runtime trap or another demonstrated cause.
- Compare checked-in capabilities, generated settings, provisioning and effective signed entitlements. Verify the actual iCloud container and production/development environment. Do not log credentials or private training records.
- Fix the cause with a focused regression test and a real-app startup test. A simulator-only stub must not conceal an app startup failure.
- Verify the application-lifetime database/sync ownership and the explicit non-destructive account-change delegate.
- Review the repeat-workout implementation, v10 migration and its recovery behavior. Preserve its useful functionality without treating historical performed work as the full intended routine.
- Establish a dated current-state record listing candidate commit, supported devices/OS, capabilities and verification status.

### Acceptance

The candidate starts, creates a gym, starts a workout, saves a set, survives relaunch and finishes the session on native CI and a signed device. Any unavailable sync/alarm capability has an honest, tested behavior; local logging remains usable according to the product contract.

Do not weaken tests, disable migrations or erase an existing database to obtain green startup. After two successive failed attempts at the same approach, record the error, causal hypothesis and a different investigation step.

**Likely touched areas:** [app startup](Packages/HardsetKit/Sources/HardsetStore/AppStartup.swift), [database lifecycle](Packages/HardsetKit/Sources/HardsetStore/Database.swift), [sync setup](Packages/HardsetKit/Sources/HardsetStore/SyncSetup.swift), [generator](Tools/generate_project.py), [entitlements](Hardset/Hardset.entitlements), [native CI](.github/workflows/ios-ui.yml). These are investigation boundaries, not a mandate to modify every file.

## 6. M1 — freeze the first experience using observation

Prepare the prototype and task scripts from the blueprint and business document. Use a small discovery cohort with contrasting single-setup, multiple-machine and multiple-gym behavior. Obtain consent before collecting private material. Recruitment or messages require their own authorized execution.

Test the complete experience: bring a real plan, miss a day, select another gym, substitute once, finish short, inspect a comparison and export. Record interventions and existing satisfactory workarounds. Compare current tools using the same task set; public feature pages alone cannot establish superiority.

Freeze these semantics before M2:

- One active plan; multiple saved plans.
- Sequence advances from explicit workout/skip choices, not elapsed days.
- Today-only changes are separate from future routine edits.
- Sessions retain starting plan/version and deviations.
- Physical setup, user-confirmed comparable setup and unknown setup are distinct.
- Comparisons describe recorded work; they do not measure hypertrophy or personal recovery.

**G1 proposal:** at least 8 of 10 prototype participants complete the main journey independently; any serious confusion between planned work and committed facts blocks implementation expansion. These are management targets to review, not statistical validation or industry benchmarks.

If the workflow provides no benefit over the participant's current method, revise the segment or proposition before expanding scope. Maintain raw consented material outside the public repository; commit only anonymized decisions and synthesis.

## 7. M2 — implement plans without rewriting history

### Domain and storage

Define typed concepts in Core for routine roles, plan versions, session sequence and deviations. Choose stable identifiers independently of display names. Define version creation, archive, duplicate, replacement, skip and extra-session behavior before the UI.

Use additive Store migrations and explicit public records; keep internal table types private. Persist a session's starting intention and its relationship to actual work. Save whole plan edits atomically. Protect committed set identity and existing immutable timeline behavior.

Specify a conflict policy before syncing plan edits: keep incompatible versions available and ask for a deliberate resolution. Do not merge two devices' prescriptions field-by-field into an unchosen plan. Existing exercise, set and machine raw identifiers remain permanent.

### Native feature

Implement basic routine authoring, flexible order, the next-session entry point and today-only editing. Convert a past workout into a proposed routine only after a user reviews the intended set counts. Blank workout starts remain available.

### Acceptance

Test missed days, deliberately skipped routines, partial finishes, no-set abandonment, extra sessions, repeated movement roles, editing during an active session and recovery after interruption. None may overwrite prior facts or silently consume the wrong planned session.

**Owned layers:** Core semantics; Store migrations/coordinator/root state; UI reusable editing components; Feature composition. Keep behavior out of the thin app shell. Candidate filenames/table names are deliberately deferred until implementation design; reserve no permanent schema token casually.

## 8. M3 — implement context and migration together

Add equipment context to routine roles and gym-specific bindings. Remember user-approved substitutions without changing the canonical movement library into duplicate names. Capture setup details progressively when they matter.

Represent supported loading conventions explicitly. Ordinary kilograms, per-side loads, assistance and machine display values cannot be silently treated as the same performance measure. Unsupported conventions retain their facts and suppress unsupported derived claims.

Extend guided import around supported formats: units, dates, exercise mappings, duplicate handling and unknown equipment. Preserve the original source association. A history import cannot reliably reconstruct a complete plan; show any inferred routine as a proposal.

Provide deliberate mapping corrections and reversible import actions where supported. Include new plan/context records in appropriate structured exports and round-trip fixtures. User control of data should work before exposure grows.

### Acceptance

Alternate a routine across two gyms; substitute an occupied station; return to the usual station; rename a setup; archive equipment; import ambiguous history; correct a mapping; export and reopen the result. The routine intention stays intact, equipment histories remain separate, unknown identities remain unknown and no source facts disappear.

Regression cases include identical manufacturer/model at different physical stations and user-confirmed interchangeable free weights. Do not invent cross-machine load conversions.

## 9. M4 — finish the review and the complete journey

Implement the blueprint's comparison contract as deterministic Core behavior. Store prepares explicit snapshots outside render loops; UI shows dates, selected facts and exclusions. Keep performance comparison, recorded exposure and plan adherence distinct.

Initial comparisons use matching movement role where known, setup and loading convention, with the most recent eligible prior session as the visible default. Show both load and reps and the chosen set-matching convention. Expose source sets and unmatched work. Do not cherry-pick favorable sets or turn missing effort/rest data into identical-condition claims.

Implement the connected native journey using existing design tokens and interaction conventions. Update [DESIGN.md](DESIGN.md) deliberately before extending components. Validate larger text, VoiceOver, reduced motion, light/dark and control states in the actual app. Measure a realistic long-history workload; avoid claiming physical-device performance from SQLite microbenchmarks.

### Acceptance

An actual person can complete the whole first-release scenario and correctly explain a review containing a changed machine, unmatched sets and unknown imported context. Correcting a prior set recomputes affected descriptions without silently replaying a progression decision. Their active session remains reachable while navigating.

G4 requires native compilation and the real-app journey, not only snapshot rendering or syntax parsing.

## 10. Data deployment and compatibility contract

For every new persistence change, create a migration note before merging:

| Required item | Evidence |
| --- | --- |
| Data location | Synced training data versus device-only journal/state |
| Schema change | Additions, defaults, indexes and table registration |
| Upgrade coverage | Relevant supported historical versions, including known edited-v1 variants and current v10 |
| Existing facts | Before/after values, identifiers, counts and foreign-key integrity |
| New defaults | Meaning of absent context in old records; no invented identity |
| Interrupted migration | Transaction rollback and retry behavior |
| Mixed versions | Old/new client read/write tests or an explicit restriction on supported coexistence |
| Cloud schema | Reviewed production diff and required query indexes |
| Recovery | Tested compatible remediation strategy |

Use the actual deployed migration history when numbering future migrations. Never modify a migration already shipped to a second device. No destructive reset, production schema deletion or implicit local-data erasure is a deployment technique.

Deploy tested additive CloudKit schema changes to the correct production container before exposing a distribution build that requires them. Verify signed distribution behavior separately from development builds. Apple's production schema model constrains removal of deployed types/fields; plan additions and compatibility accordingly. [CloudKit design](https://developer.apple.com/icloud/cloudkit/designing/), [schema deployment](https://developer.apple.com/documentation/CloudKit/deploying-an-icloud-container-s-schema)

A UI feature switch does not undo a migration or prevent an older client from encountering new synced data. Define compatibility at the read/write boundary. For changed semantics, preserve old fields until all supported clients can coexist; never overload an old field with a new meaning.

Before any app-managed database backup, use a consistent database snapshot that accounts for SQLite journaling. Copying an active `.sqlite` file alone is not a backup strategy. Do not overwrite users' current work with an old export during recovery.

## 11. Verification commands and evidence

### Existing Linux gate

From the repository root:

```bash
make check
python3 Tools/generate_project.py
git diff --exit-code -- Hardset.xcodeproj
git diff --check
```

`make check` covers orchestration contracts, Swift parsing, portable Core/Store tests, query-plan/results and palette contrast. Counts change as tests are added. It does not compile SwiftUI or prove AlarmKit, CloudKit, StoreKit or physical-device behavior.

When deliberately updating generated project settings, review and commit the generated diff; afterward, repeat generation must be idempotent. Never hand-edit the project to make the diff check pass.

### Existing Apple checks

On the selected Mac/Xcode environment:

```bash
swift build --package-path Packages/HardsetKit
./test.sh
xcodebuild build -project Hardset.xcodeproj -scheme Hardset \
  -destination 'generic/platform=iOS Simulator' \
  -skipMacroValidation -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO
xcodebuild test -project Hardset.xcodeproj -scheme Hardset \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -only-testing:HardsetTests \
  -skipMacroValidation -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO
```

Use the installed runtime/device actually recorded in the release manifest if the listed destination is unavailable. Compile and execute the signed real-app UI journey using the existing [workflow](.github/workflows/ios-ui.yml); that workflow's signing and environment steps matter. Require nonzero executed tests and inspect logs/results, not only a successful shell pipeline.

The existing `make mac-test` pulls main over SSH; it is unsuitable evidence for an arbitrary candidate branch. Use an isolated checkout of the exact candidate commit instead.

### Physical-device gate

Complete the relevant [device checklist](DEVICE-CHECKLIST.md) and [native verification](docs/MAC-VERIFICATION.md) against the candidate: offline save/relaunch, locked/background operation, permission denial, rest interruption/reconciliation, Focus behavior, account changes, two-device sync and duplicate prevention. Verify minimum-supported OS/device availability or explicitly record a release-blocking coverage gap.

Treat old claims in the checklist as hypotheses to inspect, including capability prerequisites and fallback behavior. A free account's local signing is not evidence of paid distribution access.

### Evidence record

For every gate, record commit SHA, test command/run link, toolchain/runtime, fixture origin, results, unresolved failures and reviewer. Retain candidate artifacts beyond CI's current 14-day artifact window in an approved private location if required for release support. Keep real user histories and signing material out of public artifacts.

## 12. Build the missing distribution pipeline before TestFlight

The current installer builds, installs and launches locally, with simulator fallback. It does not archive and distribute a release. Add a deliberately separate release workflow or documented operator procedure.

Required preparation:

- Confirm Apple Developer Program/App Store Connect access, actual team, app record, bundle IDs, capabilities, containers and provisioning for app and widget.
- Add reviewed version/build inputs to the generator and keep app/widget versions aligned. Build numbers must identify distinct uploaded candidates; do not leave every archive at build 1.
- Select an Apple-accepted release toolchain at execution time; CI's configured path is not proof of current upload eligibility.
- Prepare StoreKit test configuration and verify actual product availability before testing purchase behavior. Retain existing entitlements and free access promises.
- Review privacy declarations, permission wording, support/privacy links, release notes and screenshots against the actual candidate. Do not advertise unverified sync/alarm outcomes.
- Store signing and upload credentials only in the appropriate protected account/CI mechanism. Do not print or commit them.

### Candidate manifest

Every candidate must identify:

- Commit and clean source checkout; dependency lockfile hashes.
- Marketing version, build number, Xcode/SDK and archive identity.
- Minimum OS and supported configurations.
- Migration range and production CloudKit schema revision/diff.
- Entitlements/capabilities verified from the signed app and widget.
- Enabled product capabilities and their defaults.
- Linux, native, device and compatibility evidence.
- Known limitations, incident owner and remediation build strategy.
- Exact TestFlight group or App Store destination and authorization record.

Archive a Release build for generic iOS using the verified team and version inputs, validate it, and distribute through Xcode Organizer or a separately reviewed export/upload configuration. Retain the archive, symbols and manifest. Reconcile the uploaded build after Apple's processing; the source commit alone is not the distribution identity. [Apple build upload](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds)

Do not invent an export-options file or run an upload command until the real signing/distribution configuration is known. Preparing and reviewing that configuration is a concrete release task, not a reason to stop implementation prematurely.

## 13. M5–M6 — staged distribution runbook

### Internal candidate

1. Freeze a candidate commit after G4. Build and archive from that exact source.
2. Complete the manifest and migration compatibility checks.
3. Review the additive CloudKit production diff and obtain approval before applying it.
4. Validate and upload the archive only with distribution authorization.
5. Confirm the processed build identity and assign the intended internal TestFlight group.
6. Run fresh install and upgrade journeys through the distributed build, including offline use and production-container behavior.

A critical correction creates a new candidate and reruns affected gates. Do not substitute an untested archive under the same evidence packet.

### External pilot

Prepare beta information, feedback instructions and a small qualified tester group. External TestFlight distribution may require Beta App Review; complete that process before assuming people can install. Use actual build expiration in App Store Connect to plan refreshes and avoid losing pilot access. [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)

Start with a small supervised cohort, then the strategy's proposed 10-person repeated-use pilot once trust and comprehension hold. Observe intended sessions rather than daily opens. Keep consent and feedback separate from permission to upload personal workout content.

**Pilot gates:** no unresolved committed-data integrity incident; all critical journey tests pass; users can distinguish plans from saved facts and compare changed setups correctly. The strategy's proposed 6-of-10 primary-logger use over four training weeks is a learning gate, not proof of market fit. Document departures and insufficient exposure rather than hiding them in an average.

### Public release

Before release, establish whether this is the app's first public version or an update. Complete review metadata and choose manual release control. Obtain the final rollout decision using the candidate packet; a git push to main is a source integration event, not an App Store deployment.

For an eligible update, use Apple's phased automatic-update release after review. It progresses over seven days; users can still manually download the update. Pausing slows further automatic distribution but does not recall installed builds. First-release exposure should instead be bounded through the preceding beta and deliberate availability decisions. [Apple phased release](https://developer.apple.com/help/app-store-connect/update-your-app/release-a-version-update-in-phases/)

Check incidents and feedback at release, after the first day, through the rollout and after a complete user training cycle. Review rates with denominators and cohort context; a tiny sample can conceal defects. A new migration/capability change cannot bypass the candidate process because the UI looks unchanged.

## 14. Containment and recovery

| Incident | Immediate containment | Remediation |
| --- | --- | --- |
| Missing, duplicate or misattributed committed sets | Stop pilot expansion/automatic rollout; preserve evidence and safe export access | Reproduce, identify affected records, ship a repair preserving provenance; verify no repeated writes |
| Startup/migration failure | Hold new distribution; retain original database and failure details with consent | Forward-compatible hotfix; never reset the user's database |
| Mixed-client sync conflict | Stop exposure to the new writer behavior where feasible | Resolve using compatible versions and explicit conflict policy; do not remove production fields |
| Misleading comparison | Disable or hide the affected derived view through tested local behavior when possible | Correct the deterministic rule, recompute summaries and communicate affected interpretations |
| Rest scheduling/recovery failure | Report the failure visibly and preserve saved workout facts | Repair/reconcile durable state and OS scheduling; do not claim an alarm is active without evidence |
| Purchase/restore failure | Hold the new offer; preserve existing free access and verified entitlements | Correct configuration/verification and retest affected purchase states |

Prefer a forward-fix release after a migration. An older binary is usable as a rollback only if it has explicitly passed compatibility with the newer local and synced data. CloudKit production additions are not reversed by reverting a commit.

Do not assume a remote kill switch exists: the product is local-first and has no inspected control service. A local capability switch can limit a view or writer after an update, but cannot instantly alter offline installed apps. Do not add a backend merely to make the rollout plan sound safer.

Record who was affected, what changed, data repair status and how the fix was verified. Communicate only through separately authorized channels, with statements supported by the incident evidence.

## 15. M7–M8 — deploy the broader strategy incrementally

### Advanced planning and reviews

After the core pilot, add optional blocks, saved comparison configurations and reusable plan variations. Preserve basic plan provenance for free users. Verify that these capabilities reduce actual preparation/review work before treating them as a paid package.

### Explicit progression

Implement a small rule set only after users can predict its behavior from examples. Start in preview mode: proposals have source sets, equipment increment and reason. Acceptance is explicit; old corrections do not silently replay accepted future changes. Test incomplete sessions, changed equipment, unavailable increments, overrides and resets. Avoid a generalized scripting engine until demand warrants its complexity.

### Commercial release

Use the proposed one-time package as a research direction. Confirm actual costs, existing Lifetime purchase promises and real offer comprehension before selecting a price. The strategy's candidate prices are not approved product prices.

Test purchase, cancellation, pending/unverified results, restore on another device, revocation, offline entitlement access and product unavailability in the appropriate StoreKit/TestFlight environments. Saved facts, exports and existing access remain protected. An optional upgrade screen must not block the gym-floor journey.

### Distribution expansion

Prepare a factual demo of the verified two-gym journey, reviewed listing assets, support documentation and a consent-based feedback path. Start with qualified pilot referrals and narrow coach exchange. Authorize outreach/publication separately. Expand paid acquisition only after retained use, actual purchase behavior and support costs justify it.

### Explicitly conditional scope

Coach administration, public equipment databases, content marketplaces, general AI coaching, Android/web parity and Watch-first development remain separate bets. “Deploy all of this” means execute the complete recommended path and its evidence gates—not automatically build every rejected alternative.

## 16. The next executable work queue

| Order | Task | Completion artifact |
| --- | --- | --- |
| 1 | Capture final native CI state and diagnose startup failure | Reproduction, cause and regression/native evidence |
| 2 | Audit signing/capabilities, versioning and distribution access | Candidate-readiness inventory with verified gaps |
| 3 | Turn the blueprint into an end-to-end prototype; conduct authorized observation | Task results and accepted first-release semantics |
| 4 | Specify plan/context persistence and mixed-version compatibility | Reviewed additive model and test fixtures |
| 5 | Implement M2–M4 in bounded branches | Verified plan-to-review journey |
| 6 | Build the archive/manifest/distribution procedure | Reproducible signed internal candidate |
| 7 | Run the qualified TestFlight pilot | Reliability, comprehension and repeated-use evidence |
| 8 | Make the public release decision | Complete candidate packet and authorized rollout |
| 9 | Develop paid depth and explicit rules where evidence supports them | Separate capability/purchase gates |

The first two tasks can progress before customer research is available. Research can progress while engineering fixes the baseline. Lack of customer evidence blocks speculative expansion, not diagnosis or release preparation.

## 17. Completion checklist

- [ ] Candidate baseline starts and saves; native failure has an evidenced resolution.
- [ ] First-release semantics and observed-user tasks accepted.
- [ ] Plan, equipment, migration and review work form one complete experience.
- [ ] Historical upgrades, mixed-version sync and recovery contract pass.
- [ ] Linux, Apple, accessibility and signed-device evidence match the candidate.
- [ ] Version/build inputs, archive, symbols and manifest identify the processed build.
- [ ] CloudKit production diff and distribution actions are separately approved and recorded.
- [ ] TestFlight pilot completes with incidents resolved and learning gates assessed.
- [ ] Public release has a verified support/containment procedure and a final rollout decision.
- [ ] Advanced scope and monetization follow evidence and preserve existing promises.

A stage is complete only when its artifact and gate exist. A pending check, passing older commit, empty test run or agent's assertion is not release evidence.

## 18. External inputs and bounded blocks

| Needed input | Blocks | Work that can continue |
| --- | --- | --- |
| Named ownership and available capacity | Calendar commitments | Bounded diagnosis/specification |
| Actual Apple distribution access and signing | Upload and signed release proof | Core/Store work and prototype design |
| Suitable devices/accounts | Physical alarm/sync and mixed-client proof | Simulator and portable verification |
| Consented participants | Demand/comprehension/retention decisions | Prototype and reliability work |
| Real economics and existing sales/entitlements | Price and offer commitments | Core product and commercial test design |
| Explicit external-action authorization | Production schema changes, beta invites, publication, rollout | Prepare and review the complete candidate packet |

When a block appears, record the missing input, affected stage, evidence and next independent task. Do not replace missing evidence with another planning document or expand the feature list to avoid the block.

## Source and verification notes

Repository paths and CI snapshot were inspected on 9 November 2026. Apple distribution procedures were checked against the official pages linked above. Revalidate toolchain requirements, roles and store procedures when executing a release. This file describes a proposed deployment system; it does not claim the future pipeline, tests, compatibility mechanisms or feature switches already exist.
