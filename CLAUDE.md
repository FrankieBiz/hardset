# Hardset — Frontend & Ergonomics Instructions

@AGENTS.md
@DESIGN.md

Hardset is an iOS hypertrophy logger for intermediate lifters. Scope and order of work are in
`docs/ROADMAP.md`; follow it before starting any feature.

## Frontend rules
1. **Calibrated honesty**: every metric carries a stated certainty and source. Render "unevaluated" rather than guess or extrapolate. `CertaintyBadge` stays visible beside estimated metrics (1RM estimates, fractional attribution).
2. **Design tokens**: follow `DESIGN.md` and `Packages/HardsetKit/Sources/HardsetUI/DesignTokens.swift`. Keep the light and dark palettes, increased contrast, and reduced-motion behaviour. Weights, reps and rest timers use monospaced tabular figures. No asset catalogues in `HardsetUI`: colours and styles are defined in Swift.
3. **Gym floor ergonomics**: one tap per set. The keypad (`NumericPad.swift`) rejects phantom values and respects unit conversion (kg canonical, lb display). The machine picker is recency-first.
4. **Concurrency**: all `HardsetUI` components are `@MainActor`. The composition root lives in `HardsetFeature`; the `.xcodeproj` app target stays a thin shell.

## Constraints
- No diagrams of any kind in responses, comments or documentation.
- No AI attribution in code comments or commit messages; all work is attributed to FrankieBiz <frankabisignano@gmail.com>.
- Preserve existing comments, docstrings and tests unless asked to change them.
- Before finishing: `hardset-check parse` and `make check` (see `AGENTS.md`).
