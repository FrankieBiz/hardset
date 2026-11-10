# 01 — Native startup and persistence foundation

**Preferred agent:** Codex. **Priority:** first. **Master stage:** M0 in [perfect.md](../../perfect.md).

## Objective

Make the existing app start, persist training and recover reliably on the exact candidate before expanding its architecture. This is one substantial systems assignment, not a UI redesign or a rewrite of the persistence stack.

## Starting evidence

Earlier native run [42713517490](https://github.com/FrankieBiz/hardset/actions/runs/42713517490) failed because real-app tests could not reach the start screen. Portable tests had passed. The checked-in app entitlements declared HealthKit only when inspected; audit effective signed entitlements and actual container configuration. This is a hypothesis to investigate, not a diagnosis.

Read current CI state and collect its actual logs/screenshots/results. Do not blindly repeat a superseded run. Preserve the prior repeat-workout branch and v10 migration; they are part of the inspected candidate, not disposable scratch work.

## Owned paths

Initially: `Hardset/Hardset.entitlements`, `Hardset/HardsetApp.swift`, Store `AppStartup.swift`, `Database.swift`, `SyncSetup.swift`, corresponding startup/lifecycle tests, `Tools/generate_project.py`, and `.github/workflows/ios-ui.yml` when needed for reliable evidence. Keep the app shell thin. Generated project changes come only from the generator.

The coordinator may expand this list after a demonstrated cause crosses a boundary. Do not change Core training semantics, Feature/UI screens, pricing or product scope unilaterally.

## Work and deliverables

1. Reproduce or bound the failure with exact commit, Xcode, runtime, launch configuration and logs. Separate startup failure from test harness failure.
2. Trace opening/migration, sync construction, retained resource lifetime and root recovery. Verify actual signed capabilities and provisioning where relevant.
3. Implement the smallest complete causal fix. Preserve local records on account changes and persist-before-claim ordering.
4. Add a meaningful regression and a real-app startup/save/relaunch journey. Do not hide production startup behind a success-returning test stub.
5. Return a short foundation-readiness report with causal evidence, changes, verification and remaining device/account requirements.

## Acceptance criteria

- The failure has an evidenced cause or a tightly documented reproduction/block; it is not attributed to signing by guesswork.
- A candidate starts and creates a gym, starts a workout, saves a set, relaunches and finishes without losing or duplicating committed facts.
- Recovery and account-change behavior preserve local data; schema repair never relies on erasing the database.
- Native execution evidence matches the delivered commit; Linux and physical-device limits are explicitly reported.
- The diff stays bounded and leaves the future routine architecture for brief 02.

## Verification

Primary: `make check`. Also run `python3 Tools/generate_project.py` and confirm expected/idempotent generated changes. On Apple infrastructure, run `swift build --package-path Packages/HardsetKit`, `./test.sh`, and the exact real-app CI journey from `.github/workflows/ios-ui.yml`. Use `DEVICE-CHECKLIST.md` for the signed-device checks.

If only Linux is available, deliver portable evidence plus the native candidate/run required next. Do not declare M0 complete without the gate in `perfect.md`. Diagnose through available CI artifacts and prepare a reviewable fix before escalating for missing access.

## Handoff

Record the reproduction, failed approaches, causal trace, commit, commands and artifact locations in `.agents/handoffs/native-foundation.md`. Do not dispatch workers or run production finish/publish actions. The coordinator owns integration and delivery.
