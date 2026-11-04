# Orca Multi-Model Orchestration Framework

## Core Philosophy: Orchestrator vs. Heavy Lifters

Antigravity operates as the **Master Orchestrator**, not a monolithic heavy lifter. The orchestrator's job is project coordination, contract definition, task decomposition, quality gatekeeping, test verification, and production release. The heavy engineering lifting is delegated to specialized, newest-generation frontier models via the unified orchestration hub (`scripts/orchestrate.py`) and local Orca runtime.

---

## Model Specialization Matrix (Newest Frontier Generation Only)

Older-generation models (e.g. Claude 3.5, Claude 3.7, GPT-4o, legacy tiers) are strictly prohibited. Every model in the orchestration pool is selected for its distinct frontier strengths:

| Model Tier | Orchestration Worker / Model ID | Primary Specialization & Strengths | Best Used For |
| :--- | :--- | :--- | :--- |
| **OpenAI / Codex** | Worker: `codex`<br>Model: `gpt-6.1-sol` or `gpt-6-astra`<br>Effort: `high` / `xhigh` | **Core Engine, GRDB Storage, & Swift 6 Strict Concurrency**<br>Flawless algorithmic reasoning, Swift 6 strict concurrency (`NonisolatedNonsendingByDefault`), nonisolated Foundation-only `HardsetCore`, permanent schema rules (`DECISIONS.md` §4), SQLiteData sync engine preservation, and zero database work per render. Guided by `CODEX.md`. | - Foundation-only `HardsetCore` engine & timeline logic<br>- GRDB schema migrations & permanent SQLite rules<br>- `PriorPerformanceSnapshot` build-once performance contracts<br>- Swift 6 concurrency verification & `hardset-check store` |
| **Anthropic / Claude** | Worker: `claude`<br>Model: `claude-sonnet-5.5` / `claude-opus-5-5`<br>Effort: `high` | **SwiftUI Ergonomics, UI Tokens & Calibrated Honesty**<br>Deliberate aesthetic restraint, typography hierarchy (`Tokens.Typography`), monochrome signals, CertaintyBadge design, keypad interaction ergonomics, and session log craft. Guided by `CLAUDE.md`. | - `HardsetUI` design tokens & dark slate components<br>- `CertaintyBadge` honest reporting without invention<br>- Custom numeric keypad & dynamic set row interactions<br>- Session history, progression charts, & volume reports |
| **DeepSeek (OpenCode / API)** | Worker: `opencode` / `deepseek`<br>Model: `deepseek/deepseek-flash`<br>Speed: Sub-second | **Taxonomy Parsing, Seed Audits & Boundary Fuzzing**<br>High-throughput execution for structured hypertrophy taxonomy parsing, seed catalogue auditing, volume math verification, and boundary fuzzing. Guided by `docs/MuscleTaxonomy-spec.md`. | - Muscle taxonomy parsing against `docs/MuscleTaxonomy-spec.md`<br>- 50-movement seed catalogue verification & attribution<br>- Fractional volume attribution matrices & boundary fuzzing<br>- Multi-machine load conflict edge cases |
| **Antigravity** | Role: `orchestrator`<br>Authority: Master Conductor | **Master Conductor, System Integrator & Release Authority**<br>Coordinates multi-model workers, spins up child worktrees for Claude Code and OpenCode, defines task contracts, resolves integration conflicts, executes tests (`make check` / `hardset-check all`), and drives git finish protocol. | - Task decomposition & contract specification<br>- Child worktree creation (`scripts/orca-child.sh`)<br>- Multi-model worker dispatch & telemetry tracking<br>- Test suite execution (`make check`) & project generator (`make project`)<br>- Production release push via `agent-finish` |

---

## Unified Programmatic & CLI Orchestration Hub

The repository includes a battle-tested orchestration CLI and Python module at `scripts/orchestrate.py`:

### Diagnostic Probe
Verify connectivity, models, latency, and tokens across all three frontier workers:
```bash
make orchestrate-probe
# Or directly:
python3 scripts/orchestrate.py probe
```

### Worker Dispatches

#### 1. Core & Store Engineering (Codex `gpt-6.1-sol`)
```bash
python3 scripts/orchestrate.py backend \
  --task "Implement per-machine load extrapolation bounds in HardsetCore" \
  --files Packages/HardsetKit/Sources/HardsetCore/ExerciseLogState.swift \
  --verify
```
Automatically enforces `CODEX.md` instructions, Swift 6 strict concurrency, and zero diagrams. `--verify` triggers `make check` upon completion.

#### 2. Frontend Ergonomics (Claude `claude-sonnet-5.5`)
```bash
python3 scripts/orchestrate.py frontend \
  --task "Refine CertaintyBadge typography tokens and high-density set row spacing" \
  --files Packages/HardsetKit/Sources/HardsetUI/CertaintyBadge.swift \
  --verify
```
Automatically enforces `CLAUDE.md` instructions, MainActor UI isolation, dark palette tokens, and zero diagrams.

#### 3. Batch Taxonomy Extraction & Fuzzing (DeepSeek `deepseek-v4.1-flash`)
```bash
python3 scripts/orchestrate.py extract \
  --prompt "Verify the fractional muscle volume attribution matrix for unilateral split squats" \
  --json
```

#### 4. OpenCode Dispatch (OpenCode `deepseek/deepseek-flash`)
```bash
python3 scripts/orchestrate.py opencode \
  --task "Audit exercise catalog seed definitions against muscle taxonomy spec" \
  --files docs/MuscleTaxonomy-spec.md Packages/HardsetKit/Sources/HardsetStore/CatalogSeeder.swift \
  --verify
```
Dispatches task execution to OpenCode CLI runtime with automated streaming NDJSON parsing, cost tracking, and optional `--verify` test gate.

### Child Worktree Spawning for Claude Code & OpenCode

Antigravity spins up isolated child worktrees for worker agents using the dedicated child helper `scripts/orca-child.sh` or `scripts/orchestrate.py`:

#### 1. Spawn a Claude Code Child Worktree
```bash
./scripts/orca-child.sh spawn claude ui-certainty-badge "Refine CertaintyBadge typography tokens and high-density set row spacing"
```
Or via Python:
```bash
python3 scripts/orchestrate.py child-spawn --agent claude --name ui-certainty-badge --prompt "Refine CertaintyBadge tokens"
```
Creates a child worktree under the current parent workspace, sets up the Claude session, and binds the child git branch.

#### 2. Spawn an OpenCode Child Worktree
```bash
./scripts/orca-child.sh spawn opencode taxonomy-fuzz "Verify fractional volume attribution matrix for unilateral split squats"
```
Or via Python:
```bash
python3 scripts/orchestrate.py child-spawn --agent opencode --name taxonomy-fuzz --prompt "Verify taxonomy matrix"
```
Creates a child worktree under the current parent workspace, sets up OpenCode with `deepseek/deepseek-flash`, and binds the child git branch.

#### 3. List Active Child Worktrees
```bash
./scripts/orca-child.sh list
# Or:
make orchestrate-children
```

#### 4. Inspect Child Progress
```bash
./scripts/orca-child.sh inspect <worktree-selector>
```
Displays git status, recent commits, and diffs from the child worktree without touching working state.

#### 5. Non-Destructive Child Integration & Test Gate
```bash
./scripts/orca-child.sh merge <worktree-selector>
```
Ensures child working copy is clean, merges the child branch non-destructively, and runs `make check`. If any tests fail, the merge is rolled back immediately.

### Telemetry & Token Ledger
Every worker dispatch is recorded in `.qa/orchestration/token_ledger.json` and saved as an individual receipt in `.qa/orchestration/runs/`:
```bash
make orchestrate-stats
# Or directly:
python3 scripts/orchestrate.py stats
```
Displays cumulative input tokens, cached tokens, output tokens, reasoning tokens, and dollar costs per model tier.

---

## Supervised Orca Multi-Tab Workflow

When running multi-agent tasks in parallel supervised worktrees:

### Step 1: Create or Bind an Orchestration Run
```bash
orca orchestration run-create --objective "<feature-or-loop-name>" --json
```

### Step 2: Formulate the Task Specification Contract
Every delegated task must define:
- **Target**: The exact files or subsystem in scope.
- **Change**: Concrete implementation requirements and expected output.
- **Constraints**: Invariants, backward compatibility, Swift 6 strict concurrency, permanent schema rules, zero diagram rules, and no breaking existing tests.
- **Ownership**: Boundaries the worker is permitted to edit.
- **Acceptance Criteria**: The exact automated check (`hardset-check all` or `make check`) that proves completion.

### Step 3: Dispatch Work to the Specialist Agent
```bash
orca orchestration worker-start \
  --task-title "<Task Title>" \
  --spec "<Self-contained Core or Store specification>" \
  --agent codex \
  --model gpt-6.1-sol \
  --effort high \
  --worktree current \
  --json
```

### Step 4: Verification & Quality Gate
Before any feature is accepted:
```bash
make check
```
Verifies syntax parse across 86 Swift files, 162 Core unit tests in 22 suites, and 45 Store tests in 5 suites with official SQLite UUID extension loaded.

### Step 5: Mandatory Production Release
```bash
agent-finish "<imperative commit message>"
```
Or manually:
```bash
git add -A
git commit -m "<imperative commit message>"
git push origin HEAD:main
```
Attributed strictly to `FrankieBiz <frankabisignano@gmail.com>` with zero AI markers or co-author tags.
