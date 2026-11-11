# Hardset user experience and publication review

Review date: 11 November 2026. Baseline: `e24bc5f` on
`FrankieBiz/app-readiness-review` in the `searobin` workspace. Verified final app
source: `1a0029c`; the final evidence update changes documentation only.

**Decision: continue product review; do not submit to the App Store yet.** The
basic logging journey has automated and visual evidence, but public policy and
support pages do not exist, real purchase behavior is unverified, and the signed
device checklist remains open. The user confirmed that this is still the review
stage and no public policy or support URLs have been prepared.

## Scope and acceptance

The coordinator inspected actual source, regression tests, CI logs, real-app
simulator screenshots, and narrow/accessibility-size view renders. Two independent
workers using the configured free DeepSeek Flash model reviewed the workout
journey and the history/settings/data journey. Workers were read-only; the
coordinator owns implementation and final verification.

The review covers starting without an account, choosing equipment, entering and
correcting sets, rest, finishing and recovering workouts, history and progression,
volume, unit changes, import/export, optional Health, and optional Lifetime access.

Acceptance criteria:

- Saved sets retain their exact values and identities through recovery; failed
  persistence must never be presented as a successful log.
- A lifter can complete and correct a workout without a purchase or Health access.
- Storefront failure must not hide the action for restoring an existing purchase.
- Existing palette, Dynamic Type, control states, and reduced-motion behavior remain
  intact; no new visual tokens or animation are needed.
- Report fresh supported verification separately from physical-device and external
  submission gates. Keep policy/support drafts local until reviewed and published.

## What the user can do today

| Journey | Evidence and assessment |
| --- | --- |
| Open and start | Real-app screenshots show a clear Start workout action, optional gym choice, and access to Settings from the main tabs. Startup/root tests cover failed recovery and prevent a second workout from hiding the first. |
| Add movements and log | The simulator journey searches/selects a movement, enters 100 and 8 using one retargeting keypad, then shows a green logged row and a matching 800 lb volume. A later history screenshot contains one set and eight reps. |
| Correct mistakes | Existing real-app tests exercise Undo log, removing a movement, and confirmed workout discard. Store tests verify failed writes and corrected record benchmarks. |
| Machine history | Store regression coverage preserves machine identity and equipment provenance through recovery. Real signed-device interaction and multi-machine UI journeys are still needed. |
| Rest | Durable journal/controller tests cover failed scheduling, recovery, stale completions and retry. Alarm delivery while locked, force-quit and Focus behavior need an actual iPhone. |
| Finish and history | Screenshots show an inline finish confirmation with both choices visible, a completed workout in History, and matching weekly volume. Store tests cover invalid finish times and failure recovery. |
| Volume and progression | The volume screenshot attributes the logged bench set as 1 chest, 0.5 front delts, 0.5 triceps and explains the counting convention. Machine-separated progression and unknown-equipment cases have Store coverage. This is a training log, with no invented program or weekly targets. |
| Keep a copy | CSV, JSON and SQLite export are reachable without a purchase. Settings warns that JSON/SQLite include device-local Health data and that exports cannot restore the app database. Atomic imports and repeat-import detection have regression coverage. |
| Units, gyms and Health | Source exposes unit switching, gym/machine correction, and explicit opt-in Health actions. Store tests cover their portable data behavior. Native Health permission and partial-failure cases require separate validation. |

## Changes made during this review

1. `LifetimePurchaseSection.swift`: restore was conditional on a loaded storefront
   `Product`. With an empty or failed product response, an existing customer could
   only retry product loading. Restore now remains visible in a locked App Store
   build and stays disabled while another purchase operation is busy. It calls the
   existing `AppStore.sync()`/verified-entitlement flow, which does not require a
   loaded product. Product retry remains available separately. No new automatic
   account prompt or purchase is introduced.
2. `HardsetUITests/AppScreensUITests.swift`: the workout journey now asserts the
   logged load and reps, terminates/relaunches the actual app, and requires exactly
   one recovered row with the same saved values and logged state before finishing.
   This closes a coverage gap where screenshots and navigation could pass without
   proving startup recovered the saved set.
3. `docs/release/`: prepared local privacy-policy and support drafts that describe
   the current local-only build, optional Health, exports and Lifetime behavior.
   Operator/contact information, final review and public hosting remain required.
4. `WorkoutReceiptScreen.swift` and `GymManagementScreen.swift`: failures from
   corrections, archiving and refresh now use native alerts rather than a banner
   at the top of scroll content. Failed renames keep the sheet and entered values
   for retry and present their error inside that sheet. This follows History's
   existing error pattern without adding custom motion or changing data semantics.
   Failure presentation still needs native interaction verification.
5. `WorkoutRootModel.swift`: learned gym defaults are applied only at initial
   preparation. Refreshes preserve an explicit Not recorded choice and valid gym
   choices; an archived choice is cleared. Two new regression tests cover the
   nil selection through session persistence and valid/archived options.

## Publication gates still open

| Priority | Gate | Concrete next step |
| --- | --- | --- |
| Required | Public privacy policy and in-app link are absent. | Review the local draft, choose operator/contact details, host a stable HTTPS page, and add its link to Settings and App Store Connect. Apple requires a policy link in both locations under [5.1.1(i)](https://developer.apple.com/app-store/review/guidelines/#privacy). |
| Required | Public support page/contact is absent. | Review the support draft, choose a monitored route, publish it, and set App Store Connect's support URL. [Apple's review preparation page](https://developer.apple.com/app-store/review/) requires working support and privacy links. |
| Required | Release purchase behavior has not been demonstrated. | Configure/confirm `com.hardset.app.lifetime` as a non-consumable, then test purchase, cancel, pending, restore, refund/revocation, offline launch, and unavailable-product restoration with the actual signed release. The simulator/development build deliberately bypasses the paid gate. |
| Required | Real rest alerts and Health integration remain unverified. | Complete the relevant checks in `DEVICE-CHECKLIST.md` on a signed iPhone build, including denied permissions, locked screen, force-quit, Focus, pause/resume and Health read/write failures. |
| Required | Accessibility evidence contains unresolved reports. | Re-run the picker audit with the keyboard dismissed and visible rows scrolled into view, then inspect the remaining clipped-text/description reports with VoiceOver and accessibility text sizes. Do not equate CI success with a clean audit. |
| Required | App Store submission state is unknown. | Confirm the distribution archive/signature, privacy manifest in the final bundle, privacy answers, screenshots, age rating, review contact/notes and purchase metadata in App Store Connect. This review did not access that account or submit a build. |
| Product decision | The current entitlement file enables Health only; workouts are local-only. | Decide whether v1 ships with this clearly disclosed limit. Do not advertise iCloud sync. If sync is enabled later, add paid-team entitlements, review local-only backfill, test two-device/account changes, deploy the schema deliberately, and revise the policy. |
| Product decision | App icon remains the documented interim icon. | Review the actual store asset and either approve it or commission the final artwork before screenshots/store metadata are finalized. |

The local-only design and lack of a database restore workflow are disclosed
limitations, not new regressions. App deletion must never be recommended as a
troubleshooting step for someone who needs to retain their training history.

## Verification evidence

- Fresh combined `make check` passed: 12 offline orchestration
  tests; syntax parsing of 141 Swift files; 232 Core tests in 29 suites; 299 Store
  tests in 30 suites; query-result/index checks; all 172 palette contrast pairs.
  Four Apple/CloudKit Store test files are explicitly excluded by the Linux lane.
- `python3 Tools/generate_project.py` produced no project/scheme diff, and
  `git diff --check` passed.
- Baseline native evidence: [CI run 43016366146](https://github.com/FrankieBiz/hardset/actions/runs/43016366146)
  passed for `bd4fd3d`. Its app source is identical to baseline `e24bc5f`; the only
  intervening diff is a handoff entry. The artifact contains Debug/Release builds,
  app/package tests, view renders and five real-app journeys in dark/light mode.
- Artifacts were downloaded to `/tmp/hardset-readiness-baseline`. The coordinator
  visually inspected start, movement picker, empty/logged set states, finish
  confirmation, populated History/Volume and an accessibility-size session render.
- The artifact's accessibility reports are **not clean**: unsupported Dynamic Type
  in some chrome, picker contrast reports under the on-screen keyboard, clipped
  text/description findings, a disabled Later button contrast report, and a volume
  audit timeout. Some are likely presentation/system artifacts; they are not
  silently dismissed as false positives or all proven application defects.
- Final native verification **passed** for `1a0029c954941b7cae343322c0a373de01968b02`
  in [CI run 43114752712](https://github.com/FrankieBiz/hardset/actions/runs/43114752712).
  The coordinator checked the run's SHA, every step result, and the downloaded
  logs: Debug and Release app/widget builds, 60 feature tests in 8 suites, one app
  smoke test, 36 screen/controller tests in 2 suites, and all 5 actual-app UI
  journeys passed. This supersedes the intermediate `f2b1c3a` run.
- The strengthened workout journey passed: it logged 100 lb and 8 reps, terminated
  and relaunched the app, found exactly one `Set 1, 100 lb, 8 reps, logged` row,
  and confirmed that a new workout was not offered over the open workout. The
  coordinator inspected `14b-session-resumed.png` in
  `/tmp/hardset-readiness-final/app-screens`; it shows the recovered set and the
  matching 800 lb volume. Recovery is proven by the test assertions/log, rather
  than inferred from the image alone.
- The final volume audit completed and also flagged muscle tags below the visible
  scroll area, near the fixed map button/tab bar. Picker rows behind the keyboard
  were flagged again. These reports need visible-row/device inspection; no blanket
  accessibility pass is claimed. Light-mode and correction-menu audit reports were
  clean in this run. Native failure injection for the new alerts and signed-device
  StoreKit, AlarmKit and Health behavior remain unverified.

## Independent review results

Both read-only reviews completed without editing the repository or running shared
test caches. Their reports are static source reviews, with no device claims.

| Review | Findings and disposition |
| --- | --- |
| First launch and daily workout | No additional proven user-facing defect. Reported an unused `SessionCoordinator.addSet` wrapper as low-priority cleanup; retained it because cleanup is unnecessary for release readiness. Identified native coverage gaps for manual rest, add/warm-up sets, machine/gym changes, stale-workout finish, light-mode logger and large text. These are validation gaps rather than proof those actions are broken. |
| History, settings and data | Confirmed that `refreshGyms()` replaced an explicit nil/Not recorded selection with the learned gym. Fixed in an isolated free-model worker and integrated as `cc8245c`; the regression failed on the original code and passed after the fix. The coordinator reviewed the diff, strengthened the persistence assertions to require a real saved session, and ran the combined checks. |
| History, settings and data | Confirmed off-screen failure feedback in receipt corrections and gym management. Coordinator replaced it with native alerts and preserved failed rename input; native failure-path interaction remains to verify. |
| History, settings and data | Confirmed missing StoreKit purchase tests and minimal Settings snapshot dependencies. Retained as explicit release validation gaps. Image sharing's 30-set limit is intentional to bound memory; receipts remain shareable as text. No broad refactoring was introduced. |

Report files for this session: `/tmp/opencode/hardset-journey-review.md` and
`/tmp/opencode/hardset-worker-history-settings-findings.md`. Durable conclusions
and verification are recorded here rather than relying on those temporary files.
