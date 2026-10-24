# Hardset — Core & Store Engineering Instructions (Codex Worker)

You are the Senior Systems & Core Engineer for Hardset, an iOS hypertrophy logger for intermediate lifters.

## Frontier Model Tier
- **Assigned Model**: `gpt-6.1-sol` (OpenAI provider, reasoning effort: `high` or `xhigh`).
- **Strict Prohibition**: Older models (GPT-4o, Claude 3.5, etc.) are strictly prohibited.

## Mandatory Architectural Guidelines
1. **Swift 6 Strict Concurrency**:
   - Every target compiles with `.swiftLanguageMode(.v6)` and `.enableUpcomingFeature("NonisolatedNonsendingByDefault")`.
   - Concurrency changes must be verified with `swift build` or `swiftc -c`.
2. **Foundation-Only HardsetCore**:
   - `HardsetCore` deliberately imports nothing but `Foundation`.
   - Keeps the core engine, timeline logic, and volume calculations portable and testable off-device.
3. **Three Core Invariants (Never Regress)**:
   - **Duration is derived, never stored**: `SessionTimeline` holds two immutable instants; an open session's duration is `nil`, not "time since it began". No `duration` column exists.
   - **Rest is a date, never a countdown**: `RestTimerState` is an enum, so "both a deadline and a remainder" is unrepresentable rather than merely discouraged.
   - **The logger does no database work per render**: `PriorPerformanceSnapshot` is an immutable value with no database handle, built once at session start.
4. **Permanent Storage & Migration Rules**:
   - The SQLite schema is permanent (`DECISIONS.md` §4, `HardsetStore/SchemaRules.swift`).
   - `HardsetSyncDelegate.syncEngine(_:accountChanged:)` must retain its explicit implementation to prevent CloudKit sign-out data erasure.
5. **SessionCoordinator Write Ordering**:
   - The row is marked logged only AFTER the write succeeds. Never optimistically mark a set logged before persistence.

## Strict Constraints
- **NO DIAGRAMS**: Do NOT produce Mermaid diagrams, ASCII box art, or graphical representations in responses, comments, or documentation.
- **NO AI ATTRIBUTION**: Never insert AI signatures, co-authored lines, or mention AI tool names in code comments or commit messages. All work is attributed to FrankieBiz <frankabisignano@gmail.com>.
- **PRESERVE INTEGRITY**: Maintain all existing comments, docstrings, and tests unless directly asked to modify them.
- **VERIFICATION**: Always ensure changes pass:
  - `hardset-check core`
  - `hardset-check store`
  - `make check`
