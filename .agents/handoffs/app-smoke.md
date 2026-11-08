# App smoke-test execution

- Objective: compile and execute the app target's own smoke suite in the existing
  native workflow; repair its obsolete private RootView() reference.
- Workspace: /home/frankbiz/orca/workspaces/hardset/mojarra, branch
  FrankieBiz/verify-app-smoke, based on main7acda12. Existing linked worktree reused.
- Owned paths: HardsetTests/AppSmokeTests.swift, .github/workflows/ios-ui.yml,
  docs/MAC-VERIFICATION.md and this handoff. No production Swift changes intended.
- Acceptance: app test target builds and actually executes at least one passing
  Swift Testing test; existing macOS/app/widget/screen gates stay green. No private
  RootView initializer dependency. Signed account/device checks remain separate.
- Baseline: current test source calls RootView(), private and parameterized. Existing
  CI only builds the app/widget and selects package UI snapshots, so it misses this
  target. Added an app xcodebuild test step plus a nonzero-passing-test log gate;
  publish to feature branch first to capture the actual native compiler failure.
- make check passed before baseline publication:98 files,179 Core/23 suites,
  81 selected Store/5 suites,8 query cases,172 contrast pairs. Native baseline pending.
- Separate root milestone: main7acda12 CI run42430194445 is live; code parent924dd1f
  already passed native CI42429147943,14 renders, with root light/dark reviewed.
  Do not restart live jobs. Check these exact runs when resuming.

- Native baseline is live: run42430403543, commit78cf2e8, branch
  FrankieBiz/verify-app-smoke. It adds the test gate while intentionally retaining
  the old RootView() call, to capture the actual compiler error before the fix.
- Main repeat run42430194445 still live on7acda12. No restart/cancellation requested.
- Pending fix after baseline: target the app entry point instead of its private
  parameterized RootView, with explicit MainActor isolation; then require actual
  nonzero test execution and the existing rendering gates to pass before main.

- 2026-11-08: native baseline42430403543 failed as expected at
  AppSmokeTests.swift:15: cannot find RootView in scope. Replaced that call with
  MainActor-isolated HardsetApp construction. make check passed:98 parsed Swift
  files,179 Core/23 suites,81 selected Store/5 suites,8 query cases,172 contrast pairs.
  Native fix verification remains pending; do not infer runtime success from Linux.
