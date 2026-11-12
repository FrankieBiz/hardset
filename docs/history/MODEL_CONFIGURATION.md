# Workspace model quality

Hardset keeps the installed model choices and makes reasoning effort and project
context explicit. These are quality-oriented defaults, not a measured claim that
one setting maximizes every model's accuracy on every task.

| Surface | Model selection | Reasoning |
| --- | --- | --- |
| Codex in a trusted checkout | `gpt-6.1-sol` | `xhigh` for work and planning |
| Codex backend dispatcher / child helper | `gpt-6.1-sol` | `xhigh`; explicit `high` override supported |
| Claude interactive | Retains the user's selection (currently `opus` on this machine) | `high` |
| Claude frontend dispatcher / child helper | Retains existing `sonnet` alias | `high`; explicit `xhigh` override requires model support |
| OpenCode | `opencode/deepseek-v4.1-flash-free` | Provider defaults; no unsupported reasoning parameter |
| Direct DeepSeek API | Existing `deepseek-chat` request ID | Optional paid path; alias resolution is unverified |
| Antigravity / Gemini | No installed Gemini CLI found in this environment | No invented model or runtime settings |

## Scope and precedence

- `.codex/config.toml` supplies project defaults without modifying account-wide
  settings. Codex loads project configuration for trusted projects. An explicit
  CLI argument or Orca launch choice takes precedence; a resumed session may keep
  its previous model/effort. Start a new session and inspect its model indicator.
- `.claude/settings.json` sets effort without replacing the user's selected model,
  hooks, permissions, or plugins. `CLAUDE.md` imports `AGENTS.md` and `DESIGN.md`.
  Managed settings, environment variables, per-model settings, local settings,
  and explicit flags can override the project default. Use `/status` and `/effort`
  in a running session to inspect what applies.
- `opencode.json` retains the existing free default and disables the paid
  `deepseek` provider. It does not disable other configured providers or remove
  installed local models. OpenCode reads `AGENTS.md` automatically.
- Orca's installed CLI exposes per-launch `--model` and `--effort`, not a workspace
  settings command. The helper supplies both explicitly. An already-running chat
  is not reconfigured by editing files; this task does not restart active agents.
- Codex's installed model catalog advertises `xhigh` for `gpt-6.1-sol` and
  `gpt-6-astra`. Larger context limits, compaction thresholds, sampling settings,
  and paid upgrades are left at provider defaults rather than guessed.

## Worker quality contract

Every worker reads the shared rules and handoff, stays within assigned paths, and
reports actual verification to the coordinator. The coordinator integrates and
publishes; workers do not launch further workers or run the production finish
protocol. Task briefs still need an objective, owned paths, acceptance criteria,
and verification commands. For taxonomy work, supply the taxonomy specification
and require source evidence and reproducible failing cases.

The dispatcher now passes the requested reasoning setting to each supported CLI.
Codex/OpenCode subprocess timeouts cover execution and drain stdout/stderr
together. Failed `--verify` checks fail the result and CLI exit status.
An effort-only child override preserves the empty model argument correctly.

## Verification

```bash
make check-orchestration
make check
claude doctor
codex exec --help
bash -n scripts/orca-child.sh
```

The orchestration suite mocks provider calls and covers launch arguments, context,
timeouts, verification failure, child argument positions, and paid-probe defaults.
It is part of `make check`. Installed versions checked on 2026-11-08:
Codex 0.163.0, Claude Code 2.1.296, OpenCode 2.2.6.

`make orchestrate-probe` launches real workers and consumes model quota. It skips
the paid DeepSeek API by default; `probe --include-paid-api` explicitly opts in.
No model inference or paid API probes were run for this configuration change.
`codex --strict-config features list` is unsupported in this installed CLI;
configuration syntax was checked with Python TOML/JSON parsers instead.
Local CLI/catalog checks do not prove account entitlement, current alias targets,
server-side effort acceptance, or improvement on a representative task benchmark.
Linux checks do not validate iOS compilation or signing.

## References

- [Codex configuration reference](https://developers.openai.com/codex/config-reference/)
- [Claude settings and precedence](https://code.claude.com/docs/en/settings)
- [Claude model configuration](https://code.claude.com/docs/en/model-config)
- [OpenCode project configuration](https://opencode.ai/docs/config/)
