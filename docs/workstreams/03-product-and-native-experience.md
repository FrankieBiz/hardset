# 03 — Product flow and native experience architecture

**Preferred agent:** Claude with the retained project model and high effort; Codex is a fallback implementer. **Stages:** M1 and the UI of M2–M4; later M7/M8 presentation only when authorized.

## Objective

Make the complete plan-to-workout-to-review journey understandable and fast on an iPhone, using Hardset's established design system. This is product interaction architecture followed by native implementation, not cosmetic polish.

## Dependencies and two phases

**Phase A may start alongside brief 01.** Read-only inspection of production code; write a coherent prototype/flow specification and observed-use task plan under `docs/ux/`. Freeze plan semantics with the coordinator. A code prototype, if needed, must be explicitly isolated and assigned before changing production files.

**Phase B starts after brief 01's baseline and brief 02's relevant public contracts pass review.** Implement matching native slices. Do not invent production models in views to bypass an unavailable Store contract.

## Owned paths

Phase A: `docs/ux/`. Phase B: `Packages/HardsetKit/Sources/HardsetUI/`, `Sources/HardsetFeature/`, `DESIGN.md`, `HardsetUITests/` and UI snapshot tests. Preserve existing behavior outside the agreed scope.

Core, Store, migrations, signing, generator and CI belong to the other workstreams. If a necessary contract is missing, propose it in writing and have its owner implement it.

## Major deliverables

1. A complete flow covering bring/build/log-now entry, flexible plan sequence, routine editing, equipment selection/substitution, active-workout access and descriptive review.
2. Clear today-only versus future-plan choices, unknown-equipment treatment and source-fact/proposal distinction. Test the proposed Train/Plan/Review navigation against raw-history discoverability.
3. Native routine/editor, contextual equipment flow and comparison surfaces against accepted contracts. Reuse tokens and components; document deliberate extensions before implementing them.
4. An end-to-end real-app journey including short workouts, missed days, two gym setups, correction and unknown imports. Include loading, retry and failure behavior rather than happy-path screenshots alone.
5. A reviewable interaction/accessibility report with actual native evidence and any remaining physical checks.

## Acceptance criteria

- A lifter can complete the whole journey and distinguish planned work, suggestions and committed facts.
- One-day changes do not appear to rewrite the future plan; the active session stays reachable while navigating.
- Changed equipment and unmatched work remain clear in reviews; the design does not imply growth or equal resistance across machines.
- Larger text, VoiceOver, reduced motion, light/dark, focus and touch targets are checked in native execution; unavailable checks remain explicit.
- Production UI uses accepted public records/commands and existing design tokens, with no per-render database reads or duplicate domain logic.

## Verification

Primary repository gate: `make check`; this parses SwiftUI but cannot compile or render it on Linux. Require `swift build --package-path Packages/HardsetKit` on macOS and the existing real-app UI/snapshot tests on iOS. Native screenshots and accessibility audits must match the candidate. Use `docs/MAC-VERIFICATION.md` and report physical-device ergonomics separately.

The coordinator arranges authorized observation using the research protocol; the worker may prepare and analyze it but must not invent participant results or send unapproved messages. The proposed 8-of-10 prototype gate is a management criterion, not already-achieved validation.

## Handoff

Write `.agents/handoffs/native-experience.md` with accepted contracts, interaction decisions, changed files, screenshots/run links, test results and remaining issues. Do not change pricing or entitlements, dispatch workers or publish/main-push. Integration and external release remain with the coordinator.
