# Fix app launch failure and whole-app feature audit

- Updated: 2026-11-09
- Maintainer: FrankieBiz <frankabisignano@gmail.com>
- Worktree: `/home/frankbiz/orca/workspaces/hardset/dace`; branch `FrankieBiz/fix-app-launch-failure`
  (pushed; Orca renamed it from `FrankieBiz/dace`).
- Objective (user, verbatim): "make sure all the feature in hardset actually work rn i when i go to test i
  get could not open hardset and try again to open your workouts. make sure everything feel good while
  using the app. eveerything interact seemlessly and all the buttons are where they should be"

## Root cause (fixed, verified)

`ca32573` removed the iCloud/CloudKit and aps entitlements so the personal team (26XMKJFG8P, bundle
`com.francisbisignano.hardset`) can sign. SQLiteData 1.10.0's `attachMetadatabase` and `SyncEngine.init`
resolve the container from entitlements and throw `noCloudKitContainer` in a live context, so every
launch and retry ended on "Could not open Hardset". CI run 42523107381 on `main` reproduced the exact
screen. `5465c41` opens local-only (no metadatabase, no engine) when no container is entitled, adds
`SyncStatus` (portable, tested), an "iCloud: Saved on this iPhone only" Settings section, and error text
on the startup failure screen. An entitled build whose engine fails still gates startup (rows written
without the engine's triggers would never upload). CI run 42529382718 passed everything, including the
real-app journey and the new Settings assertion; screenshots in `/tmp/hardset-fix-42529382718`.

`362b798`: `install_device.sh` finds the iPhone via devicectl JSON (the table grep never matched; the
xctrace fallback chose the Mac), builds Release, uses exact product paths, warns about the 7-day
personal-team expiry and that deleting the local-only app erases workouts. `mac-install`/`mac-test`
build the current branch (`BRANCH ?=`), not main. CI compiles Release too.

## User decisions (2026-11-09)

- Deep muscle map: unlocked in development builds (simulator or embedded.mobileprovision) with a visible
  note; App Store builds keep the paid gate.
- Rest: remember the lifter's last chosen duration per movement, one-tap reuse; never invent a default.
- Delivery: PR from this branch, merge to main once CI is green.

## Audit

Workflow `hardset-feature-audit` (script copy: `build/workflows/hardset-feature-audit.js`, run
`wf_f424f9a8-3e6`): 8 area reviewers, 2 skeptics per area (code truth, design intent), gap critic, round 2
(accessibility, training-logic correctness, feel/motion, lifecycle/time). Round 1: 128 findings, 104
confirmed, 18 plausible, 6 rejected. Per-workstream finding files and the ownership/interface contract:
`/tmp/hardset-plan/ws-*.md`, `/tmp/hardset-plan/CONTRACT.md`; durable copies (git-ignored) in
`build/plan/` together with the raw and verified finding JSON.

## Wave 1 in progress

Seven parallel workers, each in its own worktree branched from `362b798`, branches
`FrankieBiz/wave1-{A,B,B2,C,D,E,F}`: A corrections/session logic (undo/remove/discard/setGym/custom
movements/recents/rest preferences), B live session UI, B2 pickers, C rest timer/AlarmKit/Info.plist,
D root/tabs/accessory, E history/receipts/volume/progress, F settings/import/Health/purchase/gym
management. File ownership is exclusive per CONTRACT.md.

## Next steps

1. Merge each wave-1 branch into this branch; replace HardsetRootView's inline rest banner with C's
   `RestTimerIssueBanner`; apply cross-workstream requests; update HardsetUITests for changed flows.
2. `make check`, push, CI; download artifacts and review every screenshot; fix compile errors.
3. Fold round-2 audit findings into a wave 2 by file ownership.
4. Docs: DEVICE-CHECKLIST/docs still describe iCloud/push/RevenueCat setups (finding T, plausible).
5. Open PR, merge to main when CI is green (authorized), then tell the user to run `make mac-install`.

## Verification so far

- `make check` (Linux) after `5465c41`: 126 Swift files parsed, 181 Core tests, 203 Store tests in 26
  suites, query plans, 172 contrast pairs — all passed.
- CI 42529382718: all steps passed (macOS package, feature tests, app/widget build, app test, snapshots,
  real-app dark+light journeys).

## Notes

- SourceKit-LSP background indexing on this machine rewrites `Packages/HardsetKit/Package.resolved`
  (adds a Linux-only OpenCombine pin). Restore it before committing; never stage it.
- CI run on main also showed a one-off "application is installing, cannot launch" race in
  `testGymPickerDark`; not seen on the fix branch run.
