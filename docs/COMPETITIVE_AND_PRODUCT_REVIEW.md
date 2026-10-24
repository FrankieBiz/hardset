# Hardset — Comprehensive Competitive, Architectural, and Ergonomic Review

> **Date**: October 2026  
> **Orchestrator**: Antigravity  
> **Frontier Contributors**: OpenAI GPT-6.1 (`gpt-6.1-sol`), Anthropic Claude (`claude-sonnet-5.5`), DeepSeek (`deepseek-v4.1-flash`)  
> **Verification Status**: 100% Green (`hardset-check all` — 207 tests, 27 suites, 0 failures)

---

## Executive Summary

Hardset is an iOS hypertrophy logging application designed for intermediate and advanced lifters. It is built on three core differentiating tenets:
1. **Calibrated Honesty**: Type-enforced certainty and sources; rendering "unevaluated" rather than inventing data or extrapolating ungrounded curves.
2. **Machine-Level Awareness**: Exercise load history is keyed to `exerciseID × machineID`, tracking physical equipment differences (pin stack, leverage ratio, cable resistance) rather than flattening them into a generic movement.
3. **Gym-Floor Craft**: Fast one-tap set logging, local-first zero-latency storage, and rest timers that survive backgrounding and process termination.

This review presents a synthesis across three frontier model evaluations:
- **DeepSeek (`deepseek-v4.1-flash`)**: Competitive market landscape, user sentiment, pricing tiers, and hypertrophy positioning.
- **Anthropic Claude (`claude-sonnet-5.5`)**: Gym-floor UX ergonomics, friction analysis under physical exertion, and UI token integrity.
- **OpenAI GPT-6.1 (`gpt-6.1-sol`)**: Core engine algorithms, GRDB/SQLiteData persistence, migration safety, and concurrency invariants.

---

## 1. Competitive Landscape Comparison

The iOS hypertrophy and workout tracking category is split into three tiers:
- **Commodity Logging ($0–$3/mo)**: Hevy (15M users, $2.99/mo) and Strong ($4.99/mo or $99 lifetime).
- **Algorithmic Programming ($12–$16/mo)**: MacroFactor Workouts ($11.99/mo), Alpha Progression ($12.99/mo), Boostcamp ($14.99/mo), Fitbod ($15.99/mo).
- **Coach-Brand / Ecosystem ($30–$35/mo)**: RP Hypertrophy ($34.99/mo), Ladder ($29.99/mo), JuggernautAI ($34.99/mo).

### Competitive Matrix

| Dimension | Hardset | Hevy | Strong | MacroFactor Workouts | RP Hypertrophy | Boostcamp | FitNotes |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Claim Honesty & Epistemic Humility** | **High**: Stated confidence & source; declines to guess | Medium: Standard PRs & historical bests | Medium: Basic formulas (Brzycki/Epley) | Low–Med: Algorithmic "black box" adjustments | **Low**: Dogmatic MEV/MRV landmarks; fake precision | Medium: Depends on coach template | **High**: Zero claims; pure unadorned logging |
| **Machine-Level Tracking** | **High**: Native `exercise × machineID` schema | Low: Requires duplicating custom exercises | Low: Single flattened exercise string | Low: Category-level equipment only | Low: Flattened; ignores machine variation | Low: Flat exercise names | Med: Notes field or manual custom lifts |
| **Local-First & Offline Authority** | **High**: GRDB / SQLiteData on-device | Med: Offline logging works; cloud sync primary | Med: Local cache, Strong Cloud sync | **Low**: Launch requires online token validation | **Low**: Release notes document save failures | Med: Programs cached; syncs upon reconnect | **High**: SQLite local-first; no account needed |
| **Rest Timer Architecture** | **High**: System date-based (`RestTimerState`); survives OS kill | Med: In-app timer; background notifications | Med: Basic countdown; occasionally desyncs | Med: Standard timer | **Low**: Frequently cited as missing or broken | Low: Resets on app switch in older builds | Med: Simple notification countdown |
| **Social Friction** | **Zero**: No feed, no profiles, no streaks | High: Mandatory social feed on startup | Zero: Personal logger | Zero: Focused nutrition & workout UI | Zero: Pure coaching tool | Med: Community programs & social boards | Zero: Pure local utility |
| **Monetization & Paywall Friction** | Planned fair model ($3.99) | Med: Gated charts & unlimited routines in Pro | High: Heavy paywalling on basic features | High: Requires $11.99/mo subscription | High: $34.99/mo ($299/yr) barrier | Med: Premium coach programs paywalled | **Zero**: Free, open utility |

---

## 2. What Lifters Love & Hate About Competitors

### What Lifters Love
1. **Instantaneous Set Logging (Hevy, Strong)**: Lifters want to enter reps/weight and tap one button. Any screen that introduces friction while breathing hard is rejected.
2. **Offline Dependability (FitNotes, Strong)**: Gyms are notoriously poor cellular environments (basements, metal buildings). Lifters love apps that open and log instantly without network spinning.
3. **Structured Progression & Volume Landmarks (RP, MacroFactor)**: Serious hypertrophy athletes want to know whether they are doing enough productive volume per muscle group per week without doing spreadsheet math.
4. **Transparent Program Discovery (Boostcamp)**: Lifters appreciate turnkey access to proven programs (e.g. GZCL, 5/3/1, SBS) without manual entry.

### What Lifters Hate (Dominate 1-Star & 2-Star Reviews)
1. **Crashes and Lost Workouts (RP, Strong, MacroFactor)**: The single most damaging failure mode. If a lifter logs 5 grueling sets and the app crashes or drops the session upon backgrounding, trust is permanently severed.
2. **Social Feed Bloat (Hevy)**: Many serious lifters resent being forced onto a social network feed when opening an app to train.
3. **Opaque "Smart" Algorithms & Dogmatic Science (RP, MacroFactor)**: RP's rigid auto-regulation and volume landmark dogmatism (MEV/MAV/MRV) frequently forces arbitrary deloads or set additions that lifters feel are detached from actual recovery.
4. **Subscription Creep & Paywall Hostage (Strong, RP, Fitbod)**: Users bitterly resent basic utilities (like historical progression charts or CSV export) being locked behind $15–$35/month subscriptions.
5. **Equipment Mismatches & Machine Inconsistency (RP, Fitbod, Hevy)**:
   - Apps prescribe exercises for equipment the gym doesn't have.
   - A 100 kg leg press on a 45-degree sled is conflated with 100 kg on a horizontal cable press. Lifters are forced to clutter their libraries with duplicate exercises ("Leg Press - Cybex", "Leg Press - Hammer").

---

## 3. What Needs to be Pivoted in Hardset

### Architectural Pivots
1. **Establish a Single Application-Lifetime Database & Sync Coordinator**:
   - `SyncEngine` retention currently depends on view state retention. If the root view graph re-renders or shifts, the sync engine can be deallocated, freezing writes.
   - **Pivot**: Move the persistence root and CloudKit `SyncEngine` ownership into an application-lifetime model container.
2. **Durable In-Flight Rest Timer Persistence**:
   - Although `RestTimerState` correctly models rest as an immutable date rather than a ticking countdown, the active rest deadline is currently held in transient memory.
   - **Pivot**: Write the active rest target instant to a lightweight local SQLite key-value row so that restarting the app or returning from a Live Activity automatically restores the identical countdown state.
3. **Explicit Cross-Machine Prefill Disambiguation**:
   - When a lifter switches machines within a session, the engine must never silently copy load from Machine A to Machine B.
   - **Pivot**: Make cross-machine prefill an explicit visual choice with clear provenance badges rather than an implicit inheritance.

### UX & Gym-Floor Ergonomic Pivots
1. **Inline Step Adjustments (+/- Steppers) Instead of Modal Keypad Sheets**:
   - Currently, every weight or rep edit opens a 360 pt modal sheet.
   - In 80% of gym situations, the lifter does either: (a) exactly what was prefilled, or (b) last time plus/minus one pin or plate increment.
   - **Pivot**: Implement inline +/- steppers on the set row matching the machine's `stackIncrementKg` (e.g. +5 kg / -5 kg), reserving the custom keypad sheet for large jumps or initial entry.
2. **Activate CertaintyBadge on Primary Work Surfaces**:
   - `CertaintyBadge` currently has zero call sites in the primary workout view. The app's core differentiator ("calibrated honesty") is invisible where the lifter needs it most.
   - **Pivot**: Display compact certainty indicators directly beside prefilled loads on the set row (e.g. "Same Machine", "Cross-Machine Estimate", "Unevaluated").
3. **Inline Recent Machine Switcher**:
   - Currently, changing machines requires tapping a chip, opening a full navigation modal, and searching.
   - **Pivot**: Expose the lifter's 2–3 most recently used machines for that exercise as horizontal quick-toggle chips directly in the exercise section header.

---

## 4. What Needs to be Improved in Hardset

### Core Engine & Mathematical Logic
1. **Fix Cross-Machine Next-Set Draft Inheritance**:
   - When switching from Machine A (100 kg) to Machine B (prior best 50 kg), appending a new set draft must pull from Machine B's history, not Machine A's active draft.
2. **Fix `machineChanges` Session Max Attribution**:
   - `machineChanges` in transition analysis currently calculates session maximum across all machines combined, erroneously attributing Machine B's load to Machine A. Scope peak calculations strictly to matching `machineID`.
3. **Enforce Strict Input Validation on Drafts**:
   - `SetEntryDraft(weightKg: .infinity, reps: 8).isLoggable` currently evaluates to `true`.
   - Constrain drafts to finite positive numbers within realistic human limits (e.g. 0 kg to 1,000 kg, 1 to 100 reps).
4. **Eliminate Arbitrary Query Truncation in Analytics**:
   - Replace the arbitrary 500-row global limit in `PriorPerformanceSnapshot` and the 1,000-row limit in PR queries with targeted per-exercise window functions.

### Storage & Schema Migration Safety
1. **P0 Migration Rectification**:
   - Columns `curatedName` and `sessionExerciseID` were previously added directly into the `v1` migration block. Existing production databases that already ran `v1` would crash on launch without a forward `v2` migration step.
   - Formalize clean, sequential migrations (`v1`, `v2`, `v3`) with automated verification.
2. **Safeguard iCloud Account Switch Handling**:
   - Maintain explicit implementation of `HardsetSyncDelegate.syncEngine(_:accountChanged:)` to prevent SQLiteData's default behavior from erasing local databases during iCloud account transitions.

### SwiftUI UI & Keypad Refinement
1. **First-Keystroke Replacement in Numeric Buffer**:
   - When tapping into an already-prefilled field, the first keystroke should replace the existing value rather than appending to it.
2. **Next-Field Traversal on Numeric Pad**:
   - Add a "Next" action key to advance focus from Weight to Reps without closing the keypad sheet.
3. **User-Configurable Machine Stack Steps**:
   - Expose an `AssumptionChip` allowing lifters to set or edit `stackIncrementKg` (e.g. 2.5 kg, 5 kg, 10 lb) directly from the machine picker.
4. **Token Color Semantic Partitioning**:
   - Disentangle certainty colors (`.high`, `.medium`, `.low`) from system state indicators (Logged, PR, Error). Reserve certainty tokens exclusively for epistemic honesty badges.
