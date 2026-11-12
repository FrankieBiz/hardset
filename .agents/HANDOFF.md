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
| 0.4 make every number true | Done: counts removed from docs, `hardset_check` prints real counts, `test.sh` and `make test` removed |
| 0.5 trim agent instructions | Done on this branch, plus the model-tier block in `CODEX.md` |
| 0.6 close CI holes | Merged from Codex (`92d6ba9`). Unverified until CI runs: the four Apple-only suites executing, and an injected unlabelled button failing the audit (not injected yet) |
| 0.7 prune remote branches | Not started: deletes remote branches, needs the user's go-ahead |

## Last green gate

- `make check` exit 0 on the merged tree (2026-11-11): 141 Swift files parsed, 232 Core tests in
  29 suites, 299 Store tests in 30 suites (28 portable Store files of 32), query-plan gate,
  172 contrast pairs. Project generation has no drift. Linux only; no native compile.

## Open decisions

- Task 0.7: confirm before any remote branch is deleted (17 remote branches now).
- The fifteen percent criterion is not met: documentation and tooling are about 22 percent of
  tracked lines. Moving files cannot fix it because `docs/history/` is tracked. Deleting
  `docs/history/research/` alone (about 3,700 long lines, kept in git history) still leaves about 15.5
  percent. Either delete more of `docs/history/` or relax the criterion.
- `opencode.json` is the only remaining match for the roadmap's `orchestrat|handout|deepseek`
  grep. It is the OpenCode model config; delete it only if OpenCode is no longer used.

## Next concrete step

Push the feature branch, wait for the macOS CI run, and read its log for the four Apple-only
suites and the isolated sync-engine step. Then do the one-time injected-unlabelled-button check
for the audit, remove the injection, and only then update main.

## Floor log

(Stage 5 only. One line per friction point met on the gym floor.)
