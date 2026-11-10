# Hardset workstreams — what to give each agent

**Updated:** 9 November 2026. These are ready-to-assign briefs for [perfect.md](../../perfect.md). Assigning work is separate from this planning change; no workers have been started.

## Start here

**Give [01 — Native foundation](01-native-foundation.md) to Codex first.** The app's real native journey has failed before reaching the start screen. Establish a trustworthy startup/save/recovery baseline before large changes make diagnosis harder.

Use the current candidate's final logs rather than an older status. At inspection, run `42730480581` for commit `91d13f0` was in progress; earlier run `42713517490` failed startup. This is a dated observation, not a claim about the latest result.

## The large assignments

| Brief | Preferred agent | Work | When to start |
| --- | --- | --- | --- |
| [01 Native foundation](01-native-foundation.md) | Codex | Startup, database/sync lifetime, signing/capability diagnosis and native reliability | **First** |
| [02 Domain and persistence architecture](02-domain-and-persistence.md) | Codex; Claude may review contracts | Plans, immutable versions, sequence, equipment context, migration and comparison engine | Contract design after startup diagnosis is bounded; production implementation after 01 and the prototype/semantic gate |
| [03 Product and native experience](03-product-and-native-experience.md) | Claude; Codex can implement if necessary | Complete prototype, navigation, routine authoring, equipment flows, review and accessibility | Prototype can start alongside 01; production UI waits for 02's accepted contracts |
| [04 Adversarial audit](04-adversarial-audit.md) | DeepSeek through the configured free OpenCode route | Taxonomy/content checks, scenario matrices, reproducible counterexamples and fixture proposals | Read-only audit can start alongside 01; replay against integrated milestones later |
| [05 Integration and distribution](05-integration-and-distribution.md) | Codex or the primary coordinator | Candidate builds, compatibility evidence, native gates, TestFlight procedure and release recovery | Read-only inventory can start early; candidate integration follows 02/03/04 |

These are role preferences grounded in project instructions. They are not measured model-quality rankings. A single agent may complete several briefs sequentially. Do not substitute an unavailable model or change provider configuration without checking the installed settings.

## Model selection

- Codex: installed `gpt-6.1-sol`, project default `xhigh`, or another expressly permitted project model with verified availability.
- Claude: retain the owner's installed model selection, `high` effort. The project permits its specified frontier Sonnet/Opus tiers; verify the actual alias before dispatch rather than guessing a provider ID.
- DeepSeek: retain `opencode/deepseek-v4.1-flash-free` through OpenCode. No paid API route, new provider or model download is needed for these audits.

See [model configuration](../MODEL_CONFIGURATION.md). No model is called merely by appearing in this table.

## Sequence and concurrency

1. Start 01 in one isolated Orca worktree with its exact base recorded.
2. Optionally run 03's prototype/docs phase and 04's evidence phase in separate worktrees. Neither owns production files while 01 is diagnosing startup.
3. Review 01's actual diff and native evidence. Preserve unrelated/in-progress work and the existing repeat-workout implementation.
4. Accept the product semantics from the prototype. Have 02 publish the domain/read-write contracts and migration compatibility plan; have 03 review them for interaction needs.
5. Implement 02 in bounded milestones. 03 may implement matching UI slices once the relevant contracts are accepted. Store/Core belong to 02; UI/Feature belong to 03. Do not have either worker patch the other's layer to bypass a mismatch.
6. Replay 04's cases against each integrated slice. The responsible implementer fixes production defects; the coordinator chooses durable regression tests.
7. Complete 05's native/distribution evidence before any pilot or release action. Deeper progression and monetization remain later, gated work in the same architecture.

Do not send “build all of perfect.md” to every worker. Each brief has a distinct output, boundaries and stopping condition.

## Shared worker contract

Workers read `AGENTS.md`, the current handoff, `perfect.md`, the three product documents and their assigned brief. Core/Store work also reads `CODEX.md`; UI work reads `CLAUDE.md` and `DESIGN.md`; taxonomy audits read the taxonomy specification.

One agent owns one checkout and branch. Use Orca's version-matched workflow. Workers do not delegate, integrate other workers, modify global settings, publish, or push production main. These task assignments explicitly reserve integration and outward delivery for the coordinator, even where generic repository finish instructions describe direct main delivery.

Return the exact commit/base, owned-file diff, actual commands and exit codes, evidence locations, unresolved failures, decisions and next step. Write task-specific handoffs under `.agents/handoffs/`; the coordinator updates shared state. Never stage another worker's changes.

The coordinator inspects every result and runs appropriate checks on the actual integrated commit. Linux parsing is not native compilation. A prototype is not observed-user validation. A fixture proposal is not a reproduced defect. Keep those distinctions in the report.

## Copy-and-paste first assignment

> Work on Hardset's native startup and persistence foundation using `docs/workstreams/01-native-foundation.md` as your task contract. Read the current handoff and inspect git status first. Preserve existing branch work. Diagnose the failure where native tests never reach the start screen, prove its cause, and implement a bounded fix with regression and native verification. Verify signed capabilities rather than assuming missing entitlements explain the failure. Stay inside the brief's ownership; request a coordinator ownership change if another layer must change. Do not implement the new routine architecture yet, spawn workers, publish or push production main. Report actual diffs, commands, exit codes and any Apple/device evidence still unavailable.
