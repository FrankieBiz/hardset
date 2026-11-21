# Plan 2 — Interaction and accessibility debt

Baseline: `main` after Plan 1. Source: the 2026-11-19 review entry's "known remaining" list, the 2026-11-18 SwiftUI review's deferred minors, and the accessibility findings in `docs/APP_READINESS_REVIEW.md`.

## Objective
The app's interaction layer stops having known defects. Every item here was found by a reviewer and deliberately deferred; deferring them again is how a launch ships with a list of "we knew about that".

## Non-goals
- No visual redesign, no new tokens, no new screens.
- No change to animation durations or easing beyond what a fix requires.
- Nothing that needs a physical device beyond what can be resolved from a render.

## S1. One sheet presentation, not four
Four `.sheet` modifiers sit on one anchor. Consolidate to a single presentation with an enum-driven destination.

Acceptance: one `.sheet` per anchor; every existing sheet still opens with the same content; the UI journeys that open them pass; the PR names any case that genuinely needs its own presentation and why.

## S2. UI tests stop sharing store state
Journeys currently share one store, so order changes results and a failure in one can mask another.

Acceptance: each journey starts from a known empty or fixture state; the journey suite passes in its normal order and in reverse order; nothing in the production target is added purely for tests beyond what already exists (`hardset.onboardingVersion`-style launch state is acceptable).

## S3. Onboarding and tour accessibility findings
Outstanding reports: the pitch progress segments have a small hit area; the staged phone reports scaled text as clipped and is reachable by VoiceOver; the tour's VoiceOver behaviour is unconfirmed.

Acceptance: the pitch segment's tappable area is at least 44 pt without changing its drawn size; the staged phone is hidden from assistive technology in a way that actually works for UIKit-hosted content (the earlier `accessibilityHidden` attempt did not; a hosting controller was tried and reverted for appearance, so any retry must keep the appearance identical); the audit reports for the onboarding screens are clean or the remaining finding is written down with the reason it is a system artefact. Says clearly which parts still need a device.

## S4. Picker and contrast findings, re-audited honestly
The readiness review recorded findings that were never re-checked with the keyboard dismissed and rows scrolled into view: picker contrast under the on-screen keyboard, a disabled Later button, clipped text, and a volume audit timeout.

Acceptance: re-run the accessibility audit over those screens with the keyboard dismissed and visible rows in view; fix what is real; for anything that is not, record the evidence and the reason. CI success is not the same as a clean audit and the PR must not claim one.

## S5. Renaming into an existing name must refuse, not silently drop tagging
In the picker and the workout-editor sheet, renaming a movement to a name that already exists returns the existing movement and throws away the attribution just typed. The Library refuses this. Make all three behave the same.

Acceptance: all three surfaces show the same refusal with the same wording; a test covers the picker and editor paths; no silent data loss.

## Verification
- `make check` exit 0 with counts.
- Native CI green with run ID.
- The macOS render suite for every screen whose presentation or layout changed; at least one new PNG per changed state, looked at and described.
- Accessibility: attach the audit output for the screens named in S3 and S4, before and after.

## Risks
- S1 and S5 touch presentation code that the snapshot suite pins; expect PNG churn and review each diff rather than regenerating the bundle.
- S2 must not weaken assertions to get isolation. An assertion removed to make a journey pass is a rejected PR.
- S3's staged-phone fix has already failed once (two different ways). If the third attempt changes appearance, revert and report instead of shipping a visual regression.

## Owner decisions this plan needs
- None. If S3 cannot be fixed without a device, that is a recorded gap, not a blocker.
