# History

Material moved here by roadmap Task 0.3 so the working tree shows only what drives current work.
Nothing here is an authority. `docs/ROADMAP.md` decides scope and order; `DESIGN.md` decides
visuals; `.agents/HANDOFF.md` records current state. Test counts, branch names and model
assignments in these files describe the day they were written and are not kept true.

| File | What it is | Why it moved |
| --- | --- | --- |
| `root-HANDOFF.md` | The long root handoff, including the multi-model orchestration mandate | Replaced by the short current-state handoff |
| `agents-HANDOFF.md` | The append-only task log kept in `.agents/HANDOFF.md` | Same |
| `handoffs/` | Per-task handoffs: app readiness, app smoke, catalogue no-op, launch failure, the GPT handout | Same; each task is merged or recorded in git history |
| `research/` | The research corpus behind the muscle taxonomy and product direction | Frozen by the roadmap; findings become tasks, not new documents |
| `CORE_STORE_ARCHITECTURE_REVIEW.md` | Core and Store review from 2026-10-24 | Findings that mattered are tracked in the roadmap stages |
| `UI_TOKEN_ACCESSIBILITY_AUDIT.md` | Token and contrast audit, since implemented | Implemented; `DESIGN.md` and `Tools/check_contrast.py` are the live record |
| `COMPETITIVE_AND_PRODUCT_REVIEW.md` | Competitor and pricing review | Pricing is a Stage 7 decision |
| `LOADING_PERFORMANCE.md` | Measurements and the loading work log | Measurements are valid for the date and fixtures recorded; the query-plan gate stays in `make check` |
| `APP_READINESS_REVIEW.md` | Readiness review of 2026-11-11 | A review document, not a task list; moved with the other reviews because it describes the deleted orchestration checks |
| `MODEL_CONFIGURATION.md` | Per-assistant model and effort settings | Describes the deleted orchestration tooling; the config files themselves are unchanged |

The multi-model orchestration scripts, the model handouts and `DEEPSEEK.md` were deleted rather
than moved. They remain in git history before the commit that removed them.
