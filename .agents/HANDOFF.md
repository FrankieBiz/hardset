# Current state

Authority: `docs/ROADMAP.md`. Older handoffs, reviews and research are in `docs/history/`.

- Updated: 2026-11-11
- Stage: 0, clear the deck
- Branch and worktree: `FrankieBiz/work-through-roadmap-with` in
  `/home/frankbiz/orca/workspaces/hardset/angelshark`; Codex child worktree
  `/home/frankbiz/orca/workspaces/hardset/stage0-ci` for tasks 0.6 and the tool half of 0.4

## Stage 0 status

| Task | State |
| --- | --- |
| 0.1 merge readiness branch | Done: `origin/main` is `abe9ec6`, which contains `1a0029c`; macOS CI run 43120034334 on main succeeded |
| 0.2 delete process tooling and model docs | Done on this branch |
| 0.3 collapse handoffs | Done on this branch |
| 0.4 make every number true | Docs half done here; `hardset_check` half and `test.sh` removal pending |
| 0.5 trim agent instructions | Done on this branch, plus the model-tier block in `CODEX.md` |
| 0.6 close CI holes | With Codex; the injected-button audit check needs one CI run |
| 0.7 prune remote branches | Not started: deletes remote branches, needs the user's go-ahead |

## Last green gate

- `make check` exit 0 on this branch after 0.2 and 0.3 (2026-11-11): 141 Swift files parsed,
  232 Core tests in 29 suites, 299 Store tests in 30 suites, query-plan gate, 172 contrast pairs.
  Linux only; no native compile.

## Open decisions

- Task 0.7: confirm before any remote branch is deleted.
- The roadmap's "documentation and tooling below fifteen percent of tracked lines" cannot be met by
  moving files, because `docs/history/` is still tracked. Either delete `docs/history/research/`
  (about 1.1 MB, kept in git history) or relax the criterion.
- The roadmap's own ground-truth table quotes test counts; they are dated to commit `e24bc5f`.

## Next concrete step

Review Codex's diff for 0.6 and 0.4 (tool half), merge it, delete `test.sh` and the `make test`
target once CI isolates the sync-engine suites, rewrite the README test section, rerun `make check`,
push the feature branch and wait for a green macOS CI run before any update of main.

## Floor log

(Stage 5 only. One line per friction point met on the gym floor.)
