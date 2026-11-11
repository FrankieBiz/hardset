# App readiness review handoff

- Timestamp: 2026-11-11 (UTC).
- Objective: user asked for cheaper agents plus the coordinator to review the app
  from the user's perspective, fix concrete problems, and assess publication readiness.
- Workspace: `/home/frankbiz/orca/workspaces/hardset/searobin`.
- Branch: `FrankieBiz/app-readiness-review`; clean baseline `e24bc5f`.
- User clarification: no privacy-policy/support URLs exist yet; still in review.
  Prepare drafts locally. Do not publish pages or submit the app.

## Active work and ownership

- Coordinator owns all changes. Two OpenCode workers are strictly read-only in
  the current checkout and use verified running DeepSeek V4.1 Flash Free.
- Orca binary resolved once from ORCA_CLI_COMMAND:
  `/home/frankbiz/.config/orca/linux-orca-cli-shim/orca`.
- Supervised run: `run_a7bfcca1e621`.
- Workout journey review: task `task_eb1374b0b7bd`, dispatch `ctx_4d9535776101`.
- History/settings/data review: task `task_a7505b86da9f`, dispatch `ctx_9ee6bc882e25`.
- Use Orca orchestration messages/worker_done notifications for results. Do not
  steer worker terminals or poll mail. Guide says to end the coordinator turn
  when independent work is done; workers wake the coordinator when they report.
- Worker 2 has been told the coordinator owns the restore fix and release drafts.

## Completed

- Read current source/design, actual handoff, UI tests and release config.
- Baseline and post-change `make check` both passed: 12 offline orchestration
  tests; 141 syntax parses; 232 Core tests/29 suites; 297 portable Store tests/30
  suites; query gate; 172 contrast pairs. Apple/CloudKit exclusions remain explicit.
- Generator creates no diff; whitespace check passes.
- Verified baseline native run43016366146 succeeded for `bd4fd3d`, which has the
  same app/test source as baseline `e24bc5f` (only handoff docs differ).
- Downloaded artifacts to `/tmp/hardset-readiness-baseline`; inspected actual
  start, picker, empty/logged session, finish confirmation, populated History and
  Volume screenshots plus accessibility-size session render.
- Native logs: Debug/Release builds; 60 portable feature tests/8 suites;
  app smoke1/1; snapshot/controller36/2; real-app dark4 + light1 all passed.
- Accessibility reports contain unresolved findings. Most picker contrast reports
  are rows under keyboard; disabled Later contrast; chrome Dynamic Type;
  clipped/description reports; volume audit timeout. Do not claim clean a11y.
- Concrete fix: Restore purchases no longer depends on storefront Product loading.
  Reuses existing busy/button state; no new automatic account prompts or motion.
- Expanded actual workout UI test asserts entered100 +8 reps, logged state, then
  terminates/relaunches and requires exactly one identical recovered logged row.
- Commit `f2b1c3a` contains source/test/DESIGN changes, authored/committed as
  FrankieBiz <frankabisignano@gmail.com>. Pushed only to review feature branch.
- Native CI for `f2b1c3a`: https://github.com/FrankieBiz/hardset/actions/runs/43111642053
  was running when this handoff was written. Do not claim the new test passed yet.

## Uncommitted owned documentation

- `docs/APP_READINESS_REVIEW.md`: full overview, evidence, open gates; worker
  results/native final status still need updating.
- `docs/release/PRIVACY_POLICY_DRAFT.md` and `SUPPORT_DRAFT.md`: local drafts;
  operator/contact/public URL and final release verification needed. No external
  publishing is authorized by the latest user clarification.
- This handoff. No unrelated edits at baseline. Do not stage Package.resolved if
  SourceKit independently adds its Linux-only OpenCombine pin.

## Settled conclusions and next step

- Continue review; not ready to submit yet. No live policy/support pages, no
  in-app policy link, no confirmed App Store product/sandbox flow, real-device
  Alarm/Health/accessibility gates open. Current entitlement file is Health-only:
  local-only is an explicitly disclosed product limit; do not promise iCloud.
- Apple sources checked: App Review Guidelines5.1.1(i),3.1.1;
  https://developer.apple.com/app-store/review/ and
  https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy
- On worker wake: examine evidence and source before accepting findings; fix
  reproducible meaningful defects within scope, with appropriate regression checks.
- Check native CI43111642053. If the relaunch test fails, inspect screenshots and
  logs; do not weaken assertions merely to turn it green. Restore transaction
  behavior itself still needs an actual signed StoreKit sandbox run.
- Finish report with both worker outcomes and actual new native evidence. Review
  all diffs, run final applicable checks, commit only owned docs/fixes, and integrate
  non-destructively under repository finish rules (main only with green native CI).
  Public app/page publication remains pending; git delivery is a separate action.

## Worker reports received and follow-up — 2026-11-11

- Both initial workers completed successfully via worker_done and modified no files.
  Reports: `/tmp/opencode/hardset-journey-review.md` and
  `/tmp/opencode/hardset-worker-history-settings-findings.md`.
- Journey review found no proven new defect, only an unused addSet seam and native
  coverage gaps. Do not broaden this task into unused-code cleanup.
- Data review found explicit nil gym choices overwritten by refreshGyms (source
  confirmed) plus off-screen correction/management error banners.
- New isolated free OpenCode worker owns ONLY Store/WorkoutRootModel.swift and its
  StoreTests/WorkoutRootModelTests.swift. Task `task_1ad35aa64e1a`, dispatch
  `ctx_0b05894d8c89`, worktree
  `/home/frankbiz/orca/workspaces/hardset/preserve-gym-choice`, base `e24bc5f`.
  Brief requires pre-fix failing regression, green Store suite, targeted commit
  with required identity, no push/finish/delegation/shared docs edits.
- Coordinator modified Feature/WorkoutReceiptScreen.swift and
  Feature/GymManagementScreen.swift: use native error alerts independent of scroll;
  failed rename remains in sheet with input retained and its own alert. DESIGN.md
  updated, parse141 and whitespace pass. Full make check now running.
- Native CI43111642053 for original f2b1c3a has passed Debug and Release builds;
  app/snapshot/UI tests were still running at last status. It does NOT include new
  alert changes or the pending gym fix. Avoid pushing intermediate commits that
  unnecessarily restart that lane; integrate worker then push combined final tree.
- Review report updated with both findings/dispositions. Need finish gym integration,
  inspect worker diff/evidence, run final make check, push combined review branch
  for native CI, then complete delivery under existing main protocol only when green.

## Gym fix integrated — 2026-11-11

- Worker commit ddb4cff on FrankieBiz/preserve-gym-choice modified only its two
  owned files and has the required author/committer. Worktree status was clean.
- Reviewed actual diff, cherry-picked as cc8245c into the review branch, preserving
  all primary UI/doc work. Initial learningDefault:true is separate from refresh;
  no schema or migration changes. Regression covers initial default, explicit nil
  through session persistence, valid pick and archived pick.
- Worker reports red299/30 with3 issues in the nil-persistence regression, then
  green299/30. Coordinator's combined make check independently passed232 Core +
  299 Store,141 parses,12 orchestration, query gate and172 contrast pairs.
- Strengthened the new test to #require both coordinator and saved session before
  asserting gymID nil (avoids a vacuous pass if no session exists). Final make
  check must run after this test refinement before the primary commit/push.
- Own root comment now correctly says archived selections clear and explicit
  Not recorded stays; no root behavior changed.
- Remaining: commit UI/error fixes + owned docs after final check; push combined
  review branch for native CI; verify screenshots/new relaunch test; then update
  review/handoff with final evidence and advance main only with green checks.
