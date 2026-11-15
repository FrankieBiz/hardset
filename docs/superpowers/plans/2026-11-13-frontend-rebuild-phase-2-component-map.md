# Phase 2 map: component kit on the calibrated-iron tokens

Reference appendix to `docs/superpowers/plans/2026-11-13-frontend-rebuild-phase-2-component-kit.md`. It is a snapshot of the code at `09e967c`, written before any Phase 2 task ran; file names and line numbers are as they were then, so after Task 1 moves code, find symbols by name. Where this map and the plan disagree, the plan wins. The eight reader digests it was built from are not committed.

Repo: /home/frankbiz/orca/workspaces/hardset/nursehound. Branch FrankieBiz/premium-frontend-design-plan-2 at 09e967c. That commit is the same one origin/FrankieBiz/premium-frontend-design-plan points at, and the tree is clean apart from an untracked `Tools/__pycache__/`. Sources: the eight digests in this directory, the spec (`docs/superpowers/specs/2026-11-12-frontend-rebuild-design.md`, "Component kit" lines 454-487 and "Delivery" lines 519-534), `DESIGN.md`, the Phase 1 plan's "Remaining phases" (lines 386-395) and the last two entries in `.agents/HANDOFF.md`.

Abbreviations: U = `Packages/HardsetKit/Sources/HardsetUI`, F = `Packages/HardsetKit/Sources/HardsetFeature`, T = `Packages/HardsetKit/Tests/HardsetUISnapshotTests`, ST = `T/ScreenSnapshotTests.swift`, UIT = `HardsetUITests/AppScreensUITests.swift`, DT = `U/DesignTokens.swift`. Rulings are numbered R1 to R37 and defined in section 6. Call-site counts are written as total (prod/preview/test).

## 0. Claims checked against source for this map

| Claim | Evidence I read | Result |
| --- | --- | --- |
| The snapshot target cannot see internal HardsetUI symbols, so every catalogue must be a public view inside HardsetUI | `rg "@testable" T` is empty; `TokenCatalogSnapshotTests.swift:1-66` imports `HardsetUI` plainly; `Snapshot.capture(_:size:style:typeSize:contrast:_:)` is at ST:346-353; `CatalogSection` is `private` at `U/TokenCatalogView.swift:60` | Confirmed |
| Phase 1 left the kit files on the alias names, and the self-drawn press style never dims a disabled control | `rg -c` finds 31 alias lines and 0 new-name lines in `U/Components.swift`. `HardsetPressStyle` (Components.swift:315-337) applies opacity 0.8 and scale 0.97 and does not read `isEnabled`. `SelectionTag`, `SelectionIndicator` and `SelectionCardButtonStyle` are internal (SelectionRow.swift:113, 154, 191). `HardsetButtonBody` and `HardsetKeyBody` pass `Tokens.Motion.press` unadapted (DT:520, 647) | Confirmed |
| The UI tests depend on labels and set-row geometry, not on identifiers. No accessibility identifier exists | `rg accessibilityIdentifier` over every `.swift` file is empty. Taps at `dx 0.44`, `0.93` and `0.08` are at UIT:82, 95, 161, 167, 171 | Confirmed |
| The engine walks 3, 8, 15 and 25 reps as high, moderate, unevaluated, unevaluated (relevant to R11) | `HardsetCore/StrengthMath.swift:43-68`: certainty is high for 2-6 reps, moderate for 7-10, low otherwise, and the result is unevaluated above 12 reps | Confirmed |
| Package files are never registered in the project, and `make check` does not run the generator | `Tools/generate_project.py` SOURCES lists only four app-shell files. The Makefile `check` target runs orchestration tests, `hardset_check.py all`, the query gate and the contrast checker | Confirmed |
| Linux gates are green at HEAD | `hardset-check parse`: "parsed 147 Swift files; failures: 0". `python3 -B Tools/check_contrast.py`: "all 176 pairs meet their floor across 23 swatches" | Confirmed (both run read-only) |
| None of the onboarding or fixture names exist yet, and `fontWeight(` is never used | `rg` for WelcomeBarView, PlateTray, PitchPage, TourStage, ScaledPhoneFrame, SpotlightOverlay, CalloutCard, SetupPage, OnboardingFlow, OnboardingModel, TourFixtures and `HardsetTag` returns nothing. `rg "fontWeight\("` returns nothing | Confirmed |

---

## 1. Scope proposal

### 1.1 Rule

The spec's kit list (lines 459-473) names everything the rebuild ships. Delivery item 2 says "Component kit: every component above, each with an all-states preview and snapshot". Read literally, "every component above" includes screens and onboarding. Delivery items 3 to 6 assign those to later phases, so the literal reading contradicts the phase list (R1).

Ruling: Phase 2 covers kit lines 461 to 468: the press style Phase 1 did not touch, the primitives, the honesty components, and the logger and picker components. Phase 2 restyles them in place on the new token names, keeps every public signature, adds only additive defaulted parameters and internal state seams, and gives each one an all-states preview and a snapshot. Behaviour described in the screen sections of the spec belongs to the phase that rebuilds that screen.

As a shorthand: Phase 2 changes how a component looks and which states it can show. Phases 4 to 6 change what it does.

### 1.2 Assignment of every kit-list entry

| Kit-list entry (spec line) | Phase | Justifying sentence |
| --- | --- | --- |
| `Tokens` and the `swatch` resolver (459) | 1, done | Delivery 1: "Design system v2: `DesignTokens.swift`, `DESIGN.md`, `check_contrast.py` expectations, machined surfaces, knurl shader, haptic namespace, motion tokens." |
| `.machinedRaised()`, `.machinedPressed()`, `.knurl(opacity:)` (460) | 1, done | Same sentence |
| `HardsetButtonStyle`, `HardsetKeyStyle` (461-462) | 1, done. Phase 2 makes one residual Reduce Motion fix (R3) | HANDOFF 2026-11-13: "machined button and key styles ... `HardsetButtonFace`/`HardsetKeyFace` are shared by the live styles and the catalogue" |
| `HardsetPressStyle` (462) | 2 | Delivery 2: "Component kit: every component above, each with an all-states preview and snapshot." Phase 1 did not touch it (Components.swift has no new-name references) |
| `ScreenHeader`, `HeaderIconButton`, `HeaderIconMenu`, `SectionLabel`, `HardsetChip`, `HardsetTag`, `HardsetSegmentedControl`, `StatLedger`, `HardsetBanner`, `HardsetLoadingState`, `HardsetEmptyState`, `HardsetSearchField`, `SelectionRow`, `SelectionIndicator` (463-465) | 2 | Delivery 2 (above). Phase 1 plan line 390: "Component kit on the new tokens (every component with an all-states preview and snapshot)." |
| `CertaintyBadge`, `AssumptionChip`, `UnevaluatedReadout`, `MethodologySheet` (466) | 2 | Same two sentences |
| `SetRowView`, `ExerciseSectionView`, `NumericPad`, `RestBarView`, `LoadStepSheet`, `NameEntrySheet`, `MachinePickerView`, `GymPickerView`, `ExercisePickerView` (467-468) | 2 for look and states. 5 for live-session behaviour | The look is Delivery 2. The behaviour is Delivery 5: "Live session and keypad rebuilt on the kit with the real coordinator", and plan line 393 adds "auto rest on log" |
| `SessionView` (469) | 5 | Delivery 5 (above) |
| `HistoryView`, `WorkoutReceiptView`, `VolumeReportView`, `MuscleHeatmapView`, `ProgressionChartView` (469-470) | 6 | Delivery 6: "Train, History, Receipt, Volume, Progress, Settings rebuilt on the kit." |
| `WelcomeBarView`, `PlateTray`, `PitchPage`, `TourStage`, `SpotlightOverlay`, `CalloutCard`, `SetupPage`, `OnboardingFlow` (471-472) | 4 | Delivery 4: "Onboarding: welcome bar, pitch pages, tour, setup, the gating and replay, the UI test." |
| `ScaledPhoneFrame` (471) | 3 | Delivery 3: "Fixtures and staged screens: `TourFixtures`, `ScaledPhoneFrame`, every screen rendered from fixtures and snapshotted." |
| `TourFixtures` (473) | 3 | Same sentence |
| Kit primitives the list does not name but that are on aliases and used by kit components: `hardsetCard`, `hardsetSheet`, `hardsetTabRoot`, `hardsetNavigationTitle`, `SelectionCardButtonStyle`, `entryFieldChrome`, `hardsetEntryField`, `hardsetNameInput`, `pickerCancelAction`, `DismissGlyphButton`, `CertaintyCapsule` | 2 | DESIGN.md "Components and states" lists Cards, Selection and Text entry as kit components. Phase 7 deletes the aliases, so every kit body must stop using them first |

### 1.3 Spec components that do not exist in code yet

| Name | Phase | Note |
| --- | --- | --- |
| `HardsetTag` | 2 | The same thing exists as the internal `SelectionTag` (U/SelectionRow.swift:154). See R4 |
| `WelcomeBarView`, `PlateTray`, `PitchPage`, `TourStage`, `SpotlightOverlay`, `CalloutCard`, `SetupPage`, `OnboardingFlow` | 4 | No symbol exists. The spec also names an `OnboardingModel` (line 256) that is not in the kit list |
| `ScaledPhoneFrame`, `TourFixtures` | 3 | No symbol exists. `ST` `Fixtures` is the starting point |
| `Motion.zoom` | n/a | Deliberately has no Swift symbol (DT:347-349). The call site uses `navigationTransition(.zoom)` |
| CoreHaptics `clank` | 4 | `Tokens.Haptic.clank` is the heavy system impact for now (Haptic.swift:11-14) |

`SelectionIndicator` exists but is internal. It stays internal unless Phase 4 needs it from HardsetFeature.

---

## 2. Per-component tables (Phase 2 components only)

Global facts that apply to every row below:

- **Accessibility identifiers.** None exist anywhere, so none can be lost. "Strings that must survive" lists the accessibility label text UIT matches on, plus labels that the real-app accessibility audit and VoiceOver users rely on.
- **Alias renames.** Use exactly these: background to canvas, surface to steel, surfaceRaised to steelRaised, surfacePressed to steelPressed, border to hairline, controlBorder to controlEdge, textPrimary to chalk, textSecondary to chalkDim, accent to plateBlue, accentFill to plateBlueFill, accentFillPressed to plateBlueFillPressed, onAccent to onPlateBlue, accentSurface to plateBlueSurface, success to plateGreen, successSurface to plateGreenSurface, pr to plateYellow, prSurface to plateYellowSurface, error to plateRed, errorSurface to plateRedSurface (DT:160-178). The aliases themselves stay until Phase 7.
- **Tracking.** Roles with non-zero tracking (display and hero at -2%, readout at -1%, caption and unit at +1%) switch to `.hardsetText(role)`. Zero-tracking roles may keep their static fonts (R17).
- **Signatures.** "Frozen" means the public init stays byte-identical. Additive defaulted parameters are allowed only where the row says so.
- **Unrenderable states.** Reduce Motion cannot be rendered. Its correctness is checked by code review and by the grep in section 3.4.

### 2.1 Shared surfaces (task P2-02)

**HardsetPressStyle**

| Field | Value |
| --- | --- |
| File | U/Components.swift:315-337, moved to U/PressStyle.swift by P2-01 |
| Exists | Yes, public |
| Init | `public init()` |
| States to preview | Rest; pressed, drawn by a new internal `HardsetPressFace(isPressed:)`; a disabled sample showing it is not dimmed |
| Call sites | 7 (6/1/0): SessionView:423, 587; ExerciseSectionView:208, 361; Components:85, 301, 405. Signature frozen |
| Tokens and literals | No aliases. Literals 0.97 (scale) and 0.8 (opacity) are DESIGN.md numbers; keep them in one place |
| Must survive | Never reads `isEnabled`; scale gated on `!reduceMotion`; animation through `Tokens.Motion.adaptive(Tokens.Motion.press, ...)` |
| Strings | None of its own |
| Delta to spec | Add the internal face. Under R2 the style stays the press for controls without a steel face. Steel faces move to the machined press |

**hardsetCard / HardsetCardModifier**

| Field | Value |
| --- | --- |
| File | DT:400-423, 445 |
| Exists | Yes, public |
| Init | `public init(isSelected: Bool = false, cornerRadius: CGFloat = Tokens.Radius.card)`; `func hardsetCard(selected: Bool = false, cornerRadius: CGFloat = Tokens.Radius.card) -> some View` |
| States to preview | Unselected; selected; control radius |
| Call sites | 12 prod. Frozen |
| Tokens and literals | accentSurface, surface, accent, border |
| Must survive | Flat `steel` card, no drop shadow; 1 pt hairline unselected; 2 pt plate-blue ring and tint when selected |
| Delta to spec | Rename only (spec line 158-160: no soft shadows under cards) |

**hardsetSheet / HardsetSheetModifier**

| Field | Value |
| --- | --- |
| File | DT:425-440, 449 |
| Exists | Yes, public |
| Init | `public init()`; `func hardsetSheet()` |
| States to preview | Not renderable, because the harness does not present sheets. Verified in real-app screenshots |
| Call sites | 21. Frozen |
| Tokens and literals | background, accent (tint) |
| Must survive | `presentation*` modifiers inside `#if os(iOS)`; tint for system chrome; visible drag indicator; card radius |
| Delta to spec | Rename only |

**HardsetButtonStyle / HardsetKeyStyle (Phase 1 residual)**

| Field | Value |
| --- | --- |
| File | DT:461-679 |
| Exists | Yes, public; faces internal |
| Init | `public init(_ role: Role = .primary, size: Size = .regular, fullWidth: Bool = true)`; `public init()` |
| States to preview | Already in `TokenCatalogView` buttons section; no new capture |
| Call sites | 67 and 4. Frozen |
| Tokens and literals | None |
| Must survive | Shared faces with the catalogue; one view identity across a press; disabled at 0.4 |
| Delta to spec | R3: route both `.animation(Tokens.Motion.press, ...)` calls through `adaptive`. Superseded by the plan, Ruling R38: a pressed destructive button dims to 0.6 like quiet (Task 2 Step 5); the existing pressed Destructive sample in the token catalogue buttons section shows it. |

### 2.2 Screen chrome (task P2-03, U/Components.swift after the split)

**ScreenHeader**

| Field | Value |
| --- | --- |
| File | U/Components.swift:13-67 |
| Exists | Yes, public |
| Init | `public init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing)`; `extension ScreenHeader where Trailing == EmptyView { public init(_ title: String, subtitle: String? = nil) }` |
| States to preview | Title only; title and subtitle; trailing icon button; trailing button and menu; long title; ax3 with trailing on its own line above the title |
| Call sites | 8 (6/1/1). Frozen |
| Tokens and literals | textPrimary, textSecondary; `Tokens.Text.display` static font |
| Must survive | `.isHeader` on the title; ax-size layout; subtitle hidden when nil or empty |
| Strings | Trailing labels come from callers: "Settings" (UIT:29, 252), "Workout options" (UIT:192) |
| Delta to spec | `.hardsetText(.display)` for -2% tracking (spec 186-188); rename |

**HeaderIconButton, HeaderIconMenu, HeaderIconGlyph (internal), HeaderIconGlyphFace (private)**

| Field | Value |
| --- | --- |
| File | U/Components.swift:70-166 |
| Exists | Yes. Button and menu public; glyph internal |
| Init | `public init(systemImage: String, accessibilityLabel: String, action: @escaping () -> Void)`; `public init(systemImage: String = "ellipsis", accessibilityLabel: String, @ViewBuilder content: () -> Content)`; `HeaderIconGlyph(systemImage:)` |
| States to preview | Rest; pressed (glyph face with `isPressed`); ax3 capped at xxxLarge |
| Call sites | 8 (6/1/1) and 2 (2/0/0). Frozen |
| Tokens and literals | textPrimary, surfaceRaised, controlBorder |
| Must survive | `@ScaledMetric(relativeTo: .headline)` diameter; `.dynamicTypeSize(...DynamicTypeSize.xxxLarge)` cap; Large Content Viewer closure inside `#if os(iOS)`; `contentShape(Circle())`; caller-supplied labels |
| Strings | "Settings", "Workout options", "\(state.exerciseName) options" (interpolated at ExerciseSectionView.swift:221; checked by the plan's no-removed-line diff, not by rg -F) (UIT:180 "Barbell Bench Press options") |
| Delta to spec | R2: the circle becomes `MachinedModifier(shape: Circle(), isPressed:, outlined: true)`. The menu label gets press feedback, which only a device can confirm (R2). Superseded by the plan, Rulings R2 and R40: `HeaderIconButton` uses `MachinedPressStyle(shape: Circle(), outlined: true)`, whose face owns a square hit region of at least 44 pt (replacing `contentShape(Circle())`); `HeaderIconMenu` keeps `.buttonStyle(.plain)` and the resting face, and its press feel is a device check. |

**SectionLabel**

| Field | Value |
| --- | --- |
| File | U/Components.swift:240-264 |
| Exists | Yes, public |
| Init | `public init(_ title: String, count: Int? = nil)` |
| States to preview | No count; count; long title; ax3 |
| Call sites | 26 (24/1/1). Frozen |
| Tokens and literals | textPrimary, textSecondary; count in `caption.monospacedDigit()` |
| Must survive | Combined element with `.isHeader` (reads "Chest, 6"); sentence case |
| Delta to spec | Count uses `.hardsetText(.caption)` plus the view `.monospacedDigit()` (that view modifier compiles at ExerciseSectionView.swift:390); rename |

**hardsetTabRoot, hardsetNavigationTitle**

| Field | Value |
| --- | --- |
| File | U/Components.swift:170-232 |
| Exists | Yes, public |
| Init | `func hardsetTabRoot() -> some View`; `func hardsetNavigationTitle(_ title: String) -> some View` |
| States to preview | Title inside a `NavigationStack` root: normal and long. ST:159 shows the pattern |
| Call sites | 7 and 20. Frozen |
| Tokens and literals | background, textPrimary; `minimumScaleFactor(0.8)` |
| Must survive | iOS-only toolbar and title-mode calls gated; principal title with `.isHeader` and Large Content Viewer |
| Delta to spec | Rename; keep the scale factor (R16) |

### 2.3 Chips, tag, segments (task P2-04)

**HardsetChip**

| Field | Value |
| --- | --- |
| File | U/Components.swift:272-304, moved to U/ChipsAndSegments.swift |
| Exists | Yes, public |
| Init | `public init(_ title: String, isSelected: Bool, action: @escaping () -> Void)` |
| States to preview | Unselected; selected; each pressed; long title; ax3 in a rail |
| Call sites | 10 (2/2/6). Frozen |
| Tokens and literals | onAccent, textPrimary, accentFill (twice), surfaceRaised, controlBorder; `caption.weight(.semibold)` |
| Must survive | Compact capsule with a 44 pt tall hit region (frame after the surface, then `contentShape(Rectangle())`); `.isSelected` trait; silent; one line in the rail |
| Strings | Visible titles only. ExercisePicker "All" and region names |
| Delta to spec | R2: unselected is a machined, raised, outlined capsule that sinks on press. Selected is `plateBlueFill` with no edge gradient and swaps to `plateBlueFillPressed`. New internal `HardsetChipFace` (worked example in 3.2); caption tracking |

**HardsetTag (new public name for SelectionTag)**

| Field | Value |
| --- | --- |
| File | U/SelectionRow.swift:150-185, moved unchanged to U/HardsetTag.swift by P2-01 |
| Exists | No by that name (R4) |
| Init | `public init(_ title: String, systemImage: String? = nil)`. Keep `typealias SelectionTag = HardsetTag` (internal) until P2-16 |
| States to preview | Text; with symbol; long text; ax3 wrap |
| Call sites | 4 internal: SelectionRow:56, 65; ExercisePickerView:234, 237. Additive public type |
| Tokens and literals | textSecondary, surfaceRaised; `caption.weight(.semibold)` |
| Must survive | Filled only, with no outline and no edge, so it never imitates a control (DESIGN.md "Tags versus chips"); symbol hidden; wraps at accessibility sizes; caller overrides such as "Your own movement" |
| Delta to spec | Public plus the spec name; rename; caption tracking |

**HardsetSegmentedControl / HardsetSegment**

| Field | Value |
| --- | --- |
| File | U/Components.swift:339-420, moved to U/ChipsAndSegments.swift |
| Exists | Yes, public; `HardsetSegment` is `public nonisolated struct` |
| Init | `public init(_ title: String, value: Value)`; `public init(selection: Binding<Value>, segments: [HardsetSegment<Value>])` |
| States to preview | Two segments, each selected (kg and lb); four segments (a reps-like set); long labels; ax3 wrap; pressed segment |
| Call sites | 4 (2/1/1), generic over `ProgressionMetric`, `Bool` and `String`. Frozen; keep `nonisolated` |
| Tokens and literals | onAccent, textPrimary, accentFill, surfaceRaised (twice), controlBorder; inline `Radius.control - Spacing.hairline` |
| Must survive | Indicator slides on `adaptive(Motion.state)`; wraps at ax sizes; `.isSelected`; silent, because the unit switch is at SettingsSheet:116 |
| Delta to spec | Track becomes a static machined raised face. Indicator stays a `plateBlueFill` with no gradient. Segments keep the opacity press (R2). Keep `matchedGeometryEffect` (R15) |

### 2.4 Messages, readouts, empty and loading (task P2-05)

**StatLedger / StatLedger.Item**

| Field | Value |
| --- | --- |
| File | U/Components.swift:422-498, moved to U/Messages.swift |
| Exists | Yes, public |
| Init | `public init(_ items: [Item])`; `public struct Item: Identifiable, Hashable, Sendable { public init(label: String, value: String, unit: String? = nil) }` |
| States to preview | Two, three and four items; with and without unit; a long value; ax3 stacked |
| Call sites | 4 containers (2/1/1) and 14 `Item` constructions. Frozen |
| Tokens and literals | border, textPrimary, textSecondary (twice) |
| Must survive | Stacks at accessibility sizes and never shrinks; one combined element per figure (value, unit, label); hairline dividers |
| Delta to spec | `unit` and `caption` tracking; rename. The value role stays `setEntry` (R5) |

**HardsetBanner / DismissGlyphButton (internal)**

| Field | Value |
| --- | --- |
| File | U/Components.swift:500-618, moved to U/Messages.swift |
| Exists | Yes. Banner public; glyph internal |
| Init | `public init(_ kind: Kind, title: String? = nil, message: String, systemImage: String? = nil, onDismiss: (() -> Void)? = nil)`; `Kind { error, caveat, record, info }`; `DismissGlyphButton(action:)` |
| States to preview | Four kinds, each with message only and with title and message; dismissible; custom symbol ("bell.slash"); long message; ax3 |
| Call sites | 18 (13/2/3). The glyph is also used at SessionView:709. Frozen; keep all four cases (R6) |
| Tokens and literals | error, pr, accent, errorSurface, prSurface, accentSurface, textPrimary, textSecondary; `hue.opacity(0.35)` |
| Must survive | One combined element; a named "Dismiss" action with the glyph hidden; kind carried by a per-kind default symbol and hue, plus the title when supplied; the symbol stays hidden from VoiceOver and the spoken output is unchanged (plan R39); negative padding on the glyph so a one-line banner stays one line; no haptic |
| Strings | "Dismiss" |
| Delta to spec | Rename. Add a public `View.hardsetArrival()` modifier: insertion-only opacity on `adaptive(Motion.reveal)`, removal `.identity` (R7, additive). The glyph gets the opacity press. Keep the 0.35 stroke (R8) |

**HardsetLoadingState**

| Field | Value |
| --- | --- |
| File | U/Components.swift:620-640, moved to U/Messages.swift |
| Exists | Yes, public |
| Init | `public init(_ message: String)` |
| States to preview | Short; long, wrapping; ax3 |
| Call sites | 10 (9/0/1), including the app target (HardsetApp.swift:83). Frozen |
| Tokens and literals | textSecondary, background |
| Must survive | Never a spinner; fills the space on the canvas |
| Delta to spec | Rename. The wordmark belongs to the caller (R24) |

**HardsetEmptyState**

| Field | Value |
| --- | --- |
| File | U/HardsetEmptyState.swift |
| Exists | Yes, public |
| Init | `public init(title: String, detail: String? = nil, systemImage: String, actionTitle: String? = nil, actionSystemImage: String = "plus", action: (() -> Void)? = nil)` |
| States to preview | No detail; detail; plus action; retry ("arrow.clockwise"); filter escape ("line.3.horizontal.decrease"); a title without an action, which hides the button; ax3 |
| Call sites | 18 (14/2/2), including the app target (HardsetApp.swift:58). Frozen |
| Tokens and literals | textSecondary (twice), surfaceRaised, controlBorder, textPrimary; dash `[4, 3]` |
| Must survive | The dashed socket is the one "nothing here yet" mark and stays flat, not machined; the button appears only when both title and closure are given; primary, not full width; glyph and text in one combined element |
| Delta to spec | Rename only. The Train empty copy is Phase 6 |

### 2.5 Entry and selection (task P2-06)

**HardsetSearchField / entryFieldChrome (internal)**

| Field | Value |
| --- | --- |
| File | U/HardsetSearchField.swift |
| Exists | Yes. Field public; chrome internal. The public wrapper `hardsetEntryField` lives in NameEntrySheet.swift |
| Init | `public init(text: Binding<String>, prompt: String = "Search movements", requestsFocus: Bool = false)`; `func entryFieldChrome(isFocused: Bool) -> some View` |
| States to preview | Empty (prompt); filled with the clear button; focused ring, drawn through `entryFieldChrome(isFocused: true)` in-module; ax3 |
| Call sites | 3 (1/2/0); chrome 2 internal. Frozen |
| Tokens and literals | accent (three), textSecondary (three), textPrimary, surfaceRaised, controlBorder |
| Must survive | "Clear search" at 44 pt; focus ring opacity on `adaptive(Motion.state)`; `requestsFocus` on appear; `.search` submit label; autocorrection off; iOS-only autocapitalisation gated |
| Strings | "Clear search" |
| Delta to spec | Rename. Entry fields stay flat raised fill plus control edge, with no edge light (R2) |

**SelectionRow**

| Field | Value |
| --- | --- |
| File | U/SelectionRow.swift:9-101 |
| Exists | Yes, public |
| Init | `public init(title: String, subtitle: String? = nil, badge: String? = nil, leadingIcon: String? = nil, isSelected: Bool = false, action: @escaping () -> Void)` |
| States to preview | Unselected; selected; subtitle; badge; leading icon, selected and not; long title; disabled; pressed (face); ax3 with the badge under the title |
| Call sites | 9 (4/5/0). Frozen |
| Tokens and literals | textPrimary, textSecondary |
| Must survive | Spoken label "title, subtitle, badge" without the word "selected"; traits `.isButton` and `.isSelected`; 56 pt minimum; silent |
| Delta to spec | Badge drawn with `HardsetTag`; rename |

**SelectionCardButtonStyle, SelectionIndicator, SelectionIconSquare, pickerCancelAction (all internal or private)**

| Field | Value |
| --- | --- |
| File | U/SelectionRow.swift:103-265 |
| Exists | Yes, internal or private |
| Init | `SelectionCardButtonStyle(isSelected:cornerRadius:)`; `SelectionIndicator(isSelected:)`; `pickerCancelAction(_:)` |
| States to preview | Card at rest, pressed, selected and disabled; indicator on and off |
| Call sites | Card style 3 (SelectionRow; ExercisePicker:225; MachinePicker:250); indicator 2; cancel 2. Keep internal signatures |
| Tokens and literals | surfacePressed, controlBorder, accent (twice), textSecondary, surfaceRaised; 0.98 scale, 0.4 disabled, 0.6 indicator start scale |
| Must survive | Pressed fill under the card ring; disabled at 0.4 (R20); both indicator symbols always laid out, so text never shifts; `adaptive(Motion.state)` |
| Delta to spec | Scale 0.98 becomes 0.97 (R19); new internal `SelectionCardFace(isSelected:isPressed:isEnabled:cornerRadius:)` for the catalogue; rename |

### 2.6 Honesty (tasks P2-07 and P2-08)

**CertaintyBadge, plus internal CertaintyCapsule, private CertaintyDetail and CertaintyPressStyle**

| Field | Value |
| --- | --- |
| File | U/CertaintyBadge.swift:1-164, 260-281 |
| Exists | Yes. Badge public; capsule internal |
| Init | `public init(level: CertaintyLevel, methodology: String, citation: String? = nil)`; `CertaintyCapsule(level:isInteractive:)` |
| States to preview | Four levels closed; pressed; static and interactive capsule; open detail in normal form and large-text form (through an internal seam on the detail content); citation nil and present; long methodology; ax3 wrapping "High confidence"; Increase Contrast, where the unevaluated capsule is carried only by its outline |
| Call sites | 13 (8/2/3). Frozen |
| Tokens and literals | surface (three), border, textPrimary (two), textSecondary; 0.35 static outline; 0.7 press opacity; `readingWidth` 320 |
| Must survive | 44 by 44 hit region inside the label; accessibility label "\(level.label). How this was calculated."; popover below xxxLarge and sheet at xxxLarge and above; capsule label wraps with `fixedSize(horizontal: false, vertical: true)`; word and symbol always present; silent; the badge stays beside every estimate (project instructions) |
| Strings | "High confidence", "Moderate confidence", "Low confidence", "Not evaluated", "How this is calculated", "Done" |
| Delta to spec | Delete `CertaintyPressStyle` and use `HardsetPressStyle` (R18); add a public `CertaintyLevel.init(_ certainty: Certainty)` in this file and have `MethodologySheet.level(for:)` delegate to it (R36); caption tracking; rename. Superseded by the plan, Ruling R18: only the badge capsule takes `HardsetPressStyle`; `AssumptionChip` takes `MachinedPressStyle(shape: Capsule(), outlined: true)` |

**AssumptionChip**

| Field | Value |
| --- | --- |
| File | U/CertaintyBadge.swift:166-206 |
| Exists | Yes, public; preview-only use |
| Init | `public init(label: String, correctionPrompt: String, onCorrect: @escaping () -> Void)` |
| States to preview | Default; pressed; long label wrapping; ax3 |
| Call sites | 1 (0/1/0). Frozen. Core requires both strings (HardsetCore/Certainty.swift:65-68) |
| Tokens and literals | textPrimary, accent, surfaceRaised, controlBorder |
| Must survive | Accessibility label "\(label). \(correctionPrompt)."; the 44 pt frame inside the label |
| Delta to spec | It is a tappable chip, so it takes the R2 machined face (share `HardsetChipFace` once P2-04 lands; until then it is drawn locally). The label must wrap. Minimum width 44. An optional additive `init(_ assumption: Assumption, onCorrect:)`. Superseded by the plan, Rulings R18 and R40: the chip is styled with `MachinedPressStyle(shape: Capsule(), outlined: true)`, not `HardsetChipFace`, and is a compact capsule inside a hit region of at least 44 by 44 pt |

**UnevaluatedReadout**

| Field | Value |
| --- | --- |
| File | U/CertaintyBadge.swift:208-258 |
| Exists | Yes, public |
| Init | `public init(explanation: String)` |
| States to preview | Short; long; ax3 |
| Call sites | 2 (1/1/0). Frozen |
| Tokens and literals | textSecondary (two), controlBorder; dash `[4, 3]`; the literal "Not evaluated" |
| Must survive | Dashed rule under "Not evaluated"; one combined element (the words, then the explanation); `readout` in the figure's place |
| Delta to spec | Use `CertaintyLevel.unevaluated.label` instead of the literal; `.hardsetText(.readout)`; check wrapping at ax3 |

**MethodologySheet**

| Field | Value |
| --- | --- |
| File | U/MethodologySheet.swift |
| Exists | Yes, public |
| Init | `public init(source: EvidenceSource, certainty: Certainty? = nil)`; internal statics `level(for:)`, `label(for:)`, `symbol(for:)` |
| States to preview | Certainty at each level and none; validRange present and absent; citation present and absent; long text; ax3 |
| Call sites | 7 (3/3/1). `level(for:)` is called by ProgressionChartView:170, 344 and MuscleHeatmapView:35, so it must stay. Frozen |
| Tokens and literals | background, textPrimary, textSecondary, surfaceRaised, border |
| Must survive | Text generated from `EvidenceSource`; headings marked `.isHeader`; text selection; Done in the confirmation toolbar; owns its `NavigationStack` |
| Strings | "How this is calculated", "Where this applies, and where it does not", "Source", "Done" |
| Delta to spec | Rename. The citation card stays flat `steelRaised` with a hairline, because it is not a control (R2) |

### 2.7 Logger (tasks P2-09 to P2-12)

**SetRowView (plus SetRowField, and LoadFigure and SetRowMetrics, which P2-01 moves out)**

| Field | Value |
| --- | --- |
| File | U/SetRowView.swift |
| Exists | Yes, public |
| Init | `public init(draft: Binding<SetEntryDraft>, ordinal: Int, isWarmup: Bool = false, isLogged: Bool = false, isNext: Bool = false, showsInlineLabels: Bool = true, unit: WeightUnit, machineIncrementKg: Double? = nil, previous: PriorSetRecord? = nil, priorNote: String? = nil, editingField: SetRowField? = nil, editingText: String? = nil, onLog: @escaping () -> Void, onBeginEditing: ((SetRowField) -> Void)? = nil, onUndo: (() -> Void)? = nil, onEdit: (() -> Void)? = nil, onRemove: (() -> Void)? = nil)` |
| States to preview | Log control incomplete, ready, next up and logged; a next row that is incomplete (dashed, not blue); warm-up blank and filled; editing weight with "100." and editing reps; read-only (`onBeginEditing` nil); step buttons in kg and lb; prior note; no previous; pressed field and log-control faces; ax3 stacked with "Log set" and "Logged" |
| Call sites | 4 (1/3/0); the only prod caller is ExerciseSectionView:100-122. Frozen. `SetRowField` is used by SessionView |
| Tokens and literals | surface, successSurface, surfaceRaised (three), textSecondary (seven), textPrimary (two), controlBorder (three), accentSurface, accent (three), accentFill, onAccent, success (two); dashes `[3, 2]` and `[4, 3]`; scale factors 0.8 and 0.85; seal start scale 0.6; incomplete opacity 0.6; `SetReadoutBody` 0.97 and 0.85; `Radius.control - Spacing.tight` |
| Must survive | One combined element; the `spokenLabel` text exactly (identical across a relaunch); hints; Voice Control names "Set N", "Log set N", and "Log set" and "Log" on the next-up row; custom actions and context menu titles; tap geometry 0.44, 0.93 and 0.08 at default size on a 402 pt phone; the `SetRowMetrics` widths; step buttons only for a positive finite increment, moving canonical kg; the selection haptic counter; success fires only on false to true; the tint is an opacity layer and the stamp scope is the glyphs only; saved values are never dimmed (`SetReadoutStyle`); `contextMenuPreview` iOS-gated |
| Strings | Labels beginning "Set 1", containing ", logged", "100 " and ", 8 reps" (UIT:78, 96-102, 110); "Undo log" (UIT:172); "Edit set", "Remove set", "Log set", "Logged", "next to log". Superseded by the plan, Task 9 Step 4: the spoken label is composed at runtime and checked by the no-removed-line diff; only "Undo log", "Edit set", "Remove set", "Log set", "Logged" and "next to log" are checked by rg -F. |
| Delta to spec | Machined raised fields with edge light that sink on press, through a shared internal face (spec 161-166, 391-392). The editing field is `plateBlueSurface` with a 2 pt `plateBlue` ring and no edge light (R2). Next up stays an opaque `plateBlueFill` (R14). Logged is a `plateGreen` seal over knurl clipped to `Circle()`, rendered Canvas-safely (R9). Keep the haptics as they are (R13). Keep scale factor 0.85 for now (R34). Superseded by the plan, Ruling R9: the seal sits inside a `KnurlPattern` ring (a `.background`, no new `Canvas`) around an opaque `plateGreenSurface` inner disc, so the glyph is never over knurl |

**ExerciseSectionView**

| Field | Value |
| --- | --- |
| File | U/ExerciseSectionView.swift |
| Exists | Yes, public |
| Init | `public init(state: Binding<ExerciseLogState>, unit: WeightUnit, onLogSet: @escaping (SetSlot) -> Void, onStartRest: ((Duration) -> Void)? = nil, onSelectMachine: (() -> Void)? = nil, onShowHistory: (() -> Void)? = nil, lastRest: Duration? = nil, editingSlotID: UUID? = nil, editingField: SetRowField? = nil, editingText: String? = nil, onBeginEditing: ((SetSlot, SetRowField) -> Void)? = nil, onUndoSet: ((SetSlot) -> Void)? = nil, onEditSet: ((SetSlot) -> Void)? = nil, onRemoveSet: ((SetSlot) -> Void)? = nil, onMoveUp: (() -> Void)? = nil, onMoveDown: (() -> Void)? = nil, onRemove: (() -> Void)? = nil)` |
| States to preview | `Fixtures.legPress()` card; history link and inert title; machine chip unset, set, and set with step; borrowed-history badge; progress with pips, more than eight sets (no pips) and complete (green); rest control with and without `lastRest`; menu present and absent; ax3 |
| Call sites | 4 (1/1/2). Frozen. Statics `spoken(_:)` (SessionView:674) and `restChoices` stay |
| Tokens and literals | accent, surfaceRaised (two), controlBorder (two), textPrimary (two), textSecondary (four), success (three), accentSurface; pip 10 by 6; scale factor 0.8; spacer height 1 |
| Must survive | `CertaintyBadge(level: .low, ...)` when `priorNote` is set; progress label "\(logged) of \(working) working sets logged"; machine-chip labels and input labels; "Start a rest of …" and "Other rest durations"; "Add set" and "Add warm-up set"; column header hidden at ax sizes |
| Strings | "\(state.exerciseName) options" (interpolated at ExerciseSectionView.swift:221; checked by the plan's no-removed-line diff, not by rg -F), "Remove movement" (UIT:180, 183), "Move up", "Move down" |
| Delta to spec | A set machine chip takes the machined face, an unset one keeps the tint with the opacity press (R2); `plateGreen` pips; rename. The gym chip, auto rest and the meaning of `lastRest` move to Phase 5 |

**NumericPad**

| Field | Value |
| --- | --- |
| File | U/NumericPad.swift |
| Exists | Yes, public |
| Init | `public init(buffer: Binding<NumericEntryBuffer>, title: String? = nil, context: String? = nil, unit: String? = nil, restEndsAt: Date? = nil, doneTitle: String = "Done", isDoneEnabled: Bool = true, onDone: (() -> Void)? = nil, onNext: (() -> Void)? = nil, onLog: (() -> Void)? = nil, canLog: Bool = false)` |
| States to preview | Weight with Done and Next; reps with Log enabled and disabled; load step with one Done, enabled and disabled; empty display "—"; replaceable prefill (`replaceOnFirstEntry: true`); context line (render the resting timer once, isolated); disabled negative quick steps on an empty buffer; integer field with the hidden decimal slot; ax3 two-by-two quick steps |
| Call sites | 5 (2/2/1). Frozen |
| Tokens and literals | surface, textPrimary (two), textSecondary (three), accent (three), accentSurface; quick-step values; scale factors 0.5 and 0.7; `lineLimit(2)` |
| Must survive | "Next field"; digit labels "0" to "9"; "Decimal point", "Delete"; "Done" default; display label "\(title), \(spoken value)"; "Log set"; announcements, including "Replaced X."; focus moves to the display on a title change; no `TextField` and no system keyboard; the grid never reflows; "Plus/Minus N" labels and input labels |
| Strings | "Next field" (UIT:83, 87), "0" to "9" (UIT:84, 92, 163-165), "Done" (UIT:94, 166), a display label beginning "Reps" (UIT:90) |
| Delta to spec | `.hardsetText(.hero)` on the display; `.hardsetText(.readout)` on keys; rename. The keys are already machined from Phase 1. Increment quick steps and the fling sheet move to Phase 5 (R12) |

**LoadStepSheet**

| Field | Value |
| --- | --- |
| File | U/LoadStepSheet.swift |
| Exists | Yes, public |
| Init | `public init(machineName: String, incrementKg: Double?, unit: WeightUnit, onSave: @escaping (Double?) -> Bool, onCancel: @escaping () -> Void)` |
| States to preview | Known step in kg; known step in lb; blank (unknown); invalid zero with Save disabled; failed save (needs an internal seam, because `failed` is private `@State`); ax3 |
| Call sites | 2 (1/0/1). Frozen |
| Tokens and literals | textPrimary, textSecondary, error, background, accent |
| Must survive | "Save load step"; blank means nil; unchanged text returns the original kg exactly; `interactiveDismissDisabled` while edited; failure text stays visible; Cancel |
| Delta to spec | Rename only |

**RestBarView**

| Field | Value |
| --- | --- |
| File | U/RestBarView.swift |
| Exists | Yes, public |
| Init | `public init(state: RestTimerState, metadata: RestMetadata? = nil, referenceDate: Date = Date(), onAdjust: @escaping (Duration) -> Void, onPauseResume: @escaping () -> Void, onSkip: @escaping () -> Void)` |
| States to preview | Paused at 402 pt (two lines) and 440 pt; with and without metadata; ax3; running, isolated in its own last `@Test` with a fixed `referenceDate` |
| Call sites | 4 (1/2/1). Frozen |
| Tokens and literals | surfaceRaised, border, textPrimary, textSecondary (three), accent; 15-second literals |
| Must survive | No `TimelineView` and no ticking state; the system timer `Text`; paused shown as static text; container `.contain`; status `.ignore` with a spoken label that embeds the timer; key labels and input labels; 56 pt `HardsetKeyStyle` keys; haptics stay in SessionView |
| Strings | "Minus 15 seconds", "Plus 15 seconds", "Pause rest", "Resume rest", "Skip rest", "Resting", "Paused" |
| Delta to spec | `.hardsetText(.hero)`; the countdown sits on a knurled backing at 8% (R9) inside an opaque panel; `ViewThatFits` stays (R10); rename. Drag, duration chooser and auto rest move to Phase 5. Superseded by the plan, Ruling R9: the countdown, in chalk in both states, has `KnurlPattern` at 8% in its own `.background`, behind the countdown only; status words, the exercise line and the keys stay off the knurl |

### 2.8 Pickers and entry sheets (tasks P2-13 to P2-15)

**NameEntrySheet, plus the public hardsetNameInput() and hardsetEntryField(isFocused:)**

| Field | Value |
| --- | --- |
| File | U/NameEntrySheet.swift |
| Exists | Yes, public |
| Init | `public init(title: String, prompt: String, footnote: String? = nil, confirmLabel: String = "Add", errorMessage: String? = nil, onConfirm: @escaping (String) -> Void, onCancel: @escaping () -> Void)` |
| States to preview | Footnote and none; error banner; long error; typed name (additive `initialName: String = ""`, R27); disabled confirm; ax3 |
| Call sites | 7 (3/3/1); modifiers 2 and 2. Frozen, plus the additive parameter |
| Tokens and literals | textSecondary (two), background, textPrimary, accent |
| Must survive | Name passed as an argument, trimmed; confirm disabled until non-blank; keyboard up on appear; error announced; interactive dismiss locked while typed; Cancel; it stays the first `TextField` on screen |
| Strings | "Add" (UIT:230); `app.textFields.firstMatch` (UIT:226) |
| Delta to spec | Rename; `hardsetArrival()` on the banner (after P2-05); caption tracking on the footnote |

**GymPickerView / GymOption**

| Field | Value |
| --- | --- |
| File | U/GymPickerView.swift |
| Exists | Yes, public |
| Init | `public init(gyms: [GymOption], selected: GymID?, errorMessage: String? = nil, onSelect: @escaping (GymID?) -> Void, onAddGym: @escaping () -> Void)`; `GymOption(id: GymID, name: String)` |
| States to preview | No gyms; gyms with one selected; nil selection ("Not recorded"); unlisted selection; error; many gyms; loading (R27); ax3 |
| Call sites | 4 (2/1/1). Frozen, plus additive `isLoading: Bool = false` and `onCancel: (() -> Void)? = nil` |
| Tokens and literals | textSecondary, accent, background |
| Must survive | "Add a gym" (UIT:221); "Not recorded" as a real choice; silent |
| Delta to spec | Pin the banner above the `ScrollView` (R26); trim whitespace-only errors; rename |

**MachinePickerView / MachineOption**

| Field | Value |
| --- | --- |
| File | U/MachinePickerView.swift |
| Exists | Yes, public |
| Init | `public init(recent: [MachineOption], others: [MachineOption] = [], selected: MachineID?, unit: WeightUnit = .kilograms, errorMessage: String? = nil, onSelect: @escaping (MachineID?) -> Void, onAddMachine: (() -> Void)? = nil, onEditIncrement: ((MachineID) -> Void)? = nil, onArchive: ((MachineID) -> Void)? = nil, onCancel: (() -> Void)? = nil)`; `MachineOption(id:displayName:stackIncrementKg:)` |
| States to preview | Zero, one and many recent machines; others; hero selected; row selected; nil and unlisted selection; steps in kg and lb; unknown step; error with and without machines; load-step button shown; no Add; long names; loading (R27); ax3 |
| Call sites | 3 (1/1/1). Frozen, plus additive `isLoading: Bool = false` |
| Tokens and literals | textSecondary (two), textPrimary (two), accent, background |
| Must survive | Recency order exactly as given; hero accessibility label "Used last time, …"; "Not recorded"; "Add a machine"; "Set this machine’s load step" (U+2019 apostrophe, as at MachinePickerView.swift:114; superseded by the plan's Labels-kept gate, which matches it with `rg -n 'machine\x{2019}s load step'`) only for a listed selected machine; archive only by context menu or accessibility action, never for the selected machine, always confirmed; `formatStep` text; silent |
| Delta to spec | Pin the banner (R26); show a loading line instead of "No machines to show" on an empty first frame (R27); rename |

**ExercisePickerView**

| Field | Value |
| --- | --- |
| File | U/ExercisePickerView.swift |
| Exists | Yes, public |
| Init | `public init(query: Binding<String>, entries: [CatalogEntry], recent: [CatalogEntry] = [], errorMessage: String? = nil, onCancel: (() -> Void)? = nil, onCreate: ((String) -> Void)? = nil, onSelect: @escaping (CatalogEntry) -> Void)`; public statics `categoryTitle(for:)`, `displayName(_:)`, `spokenLabel(for:)` |
| States to preview | Browse; recents first; partial query; no match, with and without create; region filter active (internal seam for the private `selectedCategory`); hidden-by-filter empty; loading; read failed with the pinned banner; custom entry tags; "Not attributed" and "Not recognised" sections; ax3 with stacked tags |
| Call sites | 3 (1/1/1). Frozen. `displayName` is used by MuscleHeatmapView and VolumeReportView |
| Tokens and literals | background (three), textPrimary, textSecondary, accent |
| Must survive | Row labels begin with the movement name; hint "Adds it to this workout"; rail label "Filter by body region"; a second tap clears the filter; "Show all regions"; create only when allowed and with no exact match; loading before the first read; query cleared on disappear; the `searchesFirst` rule |
| Strings | Labels beginning "Barbell Bench Press" (UIT:68, 152); "Your own movement" |
| Delta to spec | `SelectionTag` call sites become `HardsetTag`; chips arrive from P2-04; rename |

---

## 3. Catalogue and snapshot recipe

### 3.1 Two patterns

- **Small components** (chips, banners, badges, set rows) get a catalogue. Add a public `<Group>CatalogView` in HardsetUI with a nested `public enum Section: String, CaseIterable, Sendable` and `public init(section: Section? = nil)`, laid out like `TokenCatalogView`. A matching `<Group>CatalogSnapshotTests.swift` captures each section in dark, light and dark-contrast, plus ax3 for the sections that reflow.
- **Whole-screen components** (MethodologySheet, NameEntrySheet, LoadStepSheet, the three pickers, NumericPad, ExerciseSectionView) are rendered directly as the root view, one capture per state. ST does this today, for example `LoadStepSheet(...)` at ST:43. The "all-states preview" for these is one `#Preview` per state inside `#if DEBUG`.
- **Forced states.** Pressed, focused and opened states are drawn through internal faces or internal state seams that take the state as a plain parameter. Only the in-module catalogue uses them, because the test target sees only public symbols.
- **Shared section chrome.** P2-02 moves `CatalogSection` from `private` in TokenCatalogView.swift:60-75 into an internal `U/CatalogChrome.swift`, keeping the same init `init(_ title: String, @ViewBuilder content: () -> Content)`, and deletes the private copy. Never leave both, because a private and an internal type with the same name risks an ambiguity error.
- **PNG names.** Use the prefix `kit-<group>-<section>-<appearance>[-ax3]` so nothing collides with existing names such as `keypad-dark` or `restbar-*`.
- **Release builds.** Catalogue views are not `#if DEBUG`, following `TokenCatalogView` (R29). Nothing they use may be defined inside `#if DEBUG`.

### 3.2 Worked example (P2-04 chips; the face follows R2)

The face, in U/ChipsAndSegments.swift. It mirrors `HardsetKeyFace` (DT:655-679) and `HardsetButtonFace.surface` (DT:590-610) and uses only APIs that already compile in CI. Superseded in part by the plan, Ruling R17: the label uses `.hardsetText(.caption, weight: .semibold)` in place of `.font(Tokens.Text.caption.weight(.semibold))`.

```swift
/// A chip's face in a given state. Shared by `HardsetChip` and the chip catalogue, because a
/// `ButtonStyle` cannot be forced pressed in a render. Each branch is one view whose pressed state
/// only changes its arguments, so the label keeps its identity across a press.
struct HardsetChipFace<Label: View>: View {
  private let isSelected: Bool
  private let isPressed: Bool
  private let label: Label

  init(isSelected: Bool, isPressed: Bool, @ViewBuilder label: () -> Label) {
    self.isSelected = isSelected
    self.isPressed = isPressed
    self.label = label()
  }

  var body: some View {
    surface(
      label
        .font(Tokens.Text.caption.weight(.semibold))
        .foregroundStyle(isSelected ? Tokens.Color.onPlateBlue : Tokens.Color.chalk)
        .lineLimit(1)
        .padding(.horizontal, Tokens.Spacing.regular)
        .padding(.vertical, Tokens.Spacing.snug)
    )
    .frame(minHeight: Tokens.minimumTapTarget)
    .contentShape(Rectangle())
  }

  @ViewBuilder
  private func surface<Content: View>(_ content: Content) -> some View {
    if isSelected {
      content.background(
        isPressed ? Tokens.Color.plateBlueFillPressed : Tokens.Color.plateBlueFill,
        in: Capsule()
      )
    } else {
      content.modifier(MachinedModifier(shape: Capsule(), isPressed: isPressed, outlined: true))
    }
  }
}
```

The live chip keeps its public init. Its body becomes `Button(action: action) { Text(title) }`, styled with a private `ButtonStyle`. That style's body draws `HardsetChipFace(isSelected:isPressed: configuration.isPressed) { configuration.label }`, then `.scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)` and `.animation(Tokens.Motion.adaptive(Tokens.Motion.press, reduceMotion: reduceMotion), value: configuration.isPressed)`, then `.accessibilityAddTraits(isSelected ? [.isSelected] : [])`. In HardsetUI, `Configuration` is safe to use because that module does not import GRDB.

The catalogue, in `U/ChipCatalogView.swift`:

```swift
import SwiftUI

/// Every chip, tag and segment state, for review from images. Static: no state, no I/O.
public struct ChipCatalogView: View {
  public enum Section: String, CaseIterable, Sendable {
    case chips, tags, segments
  }

  private let section: Section?

  public init(section: Section? = nil) {
    self.section = section
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Tokens.Spacing.section) {
        if let section {
          sectionView(section)
        } else {
          ForEach(Section.allCases, id: \.self) { sectionView($0) }
        }
      }
      .padding(.horizontal, Tokens.Spacing.loose)
      .padding(.vertical, Tokens.Spacing.loose)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(Tokens.Color.canvas.ignoresSafeArea())
  }

  @ViewBuilder
  private func sectionView(_ section: Section) -> some View {
    switch section {
    case .chips: ChipStates()
    case .tags: TagStates()
    case .segments: SegmentStates()
    }
  }
}

private struct ChipStates: View {
  var body: some View {
    CatalogSection("Chips") {
      VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
        HStack(spacing: Tokens.Spacing.snug) {
          HardsetChip("Unselected", isSelected: false) {}
          HardsetChip("Selected", isSelected: true) {}
        }
        HStack(spacing: Tokens.Spacing.snug) {
          HardsetChipFace(isSelected: false, isPressed: true) { Text("Pressed") }
          HardsetChipFace(isSelected: true, isPressed: true) { Text("Pressed") }
        }
        HardsetChip("Hammer Strength Leg Press", isSelected: false) {}
      }
    }
  }
}
// TagStates and SegmentStates follow the same shape; SegmentStates uses .constant(...) bindings.

#if DEBUG
  #Preview("Chips, all states") {
    ChipCatalogView()
  }
#endif
```

The test, in `T/ChipCatalogSnapshotTests.swift`. It copies TokenCatalogSnapshotTests.swift:1-66.

```swift
#if canImport(UIKit)
  import Foundation
  import HardsetUI
  import SwiftUI
  import Testing
  import UIKit

  @MainActor
  @Suite("Chip catalogue renders for review", .serialized)
  struct ChipCatalogSnapshotTests {
    private static let width: CGFloat = 402

    private static func height(_ section: ChipCatalogView.Section) -> CGFloat {
      switch section {
      case .chips: 320
      case .tags: 240
      case .segments: 420
      }
    }

    @Test func sectionsInEveryAppearance() async throws {
      for section in ChipCatalogView.Section.allCases {
        let size = CGSize(width: Self.width, height: Self.height(section))
        let name = "kit-chips-\(section.rawValue)"
        try await Snapshot.capture("\(name)-dark", size: size) { ChipCatalogView(section: section) }
        try await Snapshot.capture("\(name)-light", size: size, style: .light) {
          ChipCatalogView(section: section)
        }
        try await Snapshot.capture("\(name)-dark-contrast", size: size, contrast: .high) {
          ChipCatalogView(section: section)
        }
      }
    }

    @Test func accessibilitySizes() async throws {
      try await Snapshot.capture(
        "kit-chips-segments-dark-ax3", size: CGSize(width: Self.width, height: 900),
        typeSize: .accessibility3
      ) { ChipCatalogView(section: .segments) }
    }
  }
#endif
```

The heights above are starting guesses. After the first CI run, raise any height whose PNG is cut off at the bottom edge, because nothing detects a crop.

### 3.3 Generator and parse commands

- `hardset-check parse`: syntax only. Expect "failures: 0". The count starts at 147 and rises by one for each new `.swift` file. P2-01 adds five files (152) and P2-02 adds three (155).
- `python3 -B Tools/generate_project.py && git diff --exit-code -- Hardset.xcodeproj`: exit 0 with no output proves no project drift. Files in HardsetUI, HardsetFeature and the package tests need no registration. `-B` avoids creating `Tools/__pycache__`. `make check` does not run this check (R22).
- `python3 -B Tools/check_contrast.py`: expect "all 176 pairs meet their floor across 23 swatches". Only P2-11 may change the count (R9).
- `make check`: orchestration tests, parse, Core and Store suites, the query gate and contrast. The coordinator runs it before integrating each wave.

### 3.4 Phase 2 grep gates (Linux, per task, on owned files only)

- **No aliases.** `rg -n "Tokens\.Color\.(background|surface|surfaceRaised|surfacePressed|border|controlBorder|textPrimary|textSecondary|accent|accentFill|accentFillPressed|onAccent|accentSurface|success|successSurface|pr|prSurface|error|errorSurface)\b" <owned files>` must print nothing.
- **Reduce Motion.** `rg -n "(\.animation|withAnimation)\(\s*Tokens\.Motion\.(press|state|reveal|stamp)" <owned files>` must print nothing, because every motion goes through `adaptive`. Every `scaleEffect(` hit is checked by eye for a `reduceMotion` gate.
- **Public API frozen.** `diff <(git show <base>:<file> | rg -o "public [^{]*") <(rg -o "public [^{]*" <file>)` may show only added lines.
- **Labels kept.** `rg -F "<string>" <owned files>` finds every string in the component's "Strings" row. Superseded by the plan's Conventions, Grep gates (which also correct every other gate in this list): a literal is checked in the file that declares it, a composed or interpolated label by a diff showing its expression unchanged, and a typographic character is copied from source, never retyped (the U+2019 in `machine’s` is matched with `rg -n 'machine\x{2019}s load step'`).
- **No new colours.** `rg -n "Color\(|UIColor|NSColor|\.white\b|\.black\b" <owned files>` must print nothing outside DT.

### 3.5 Which checks run where

| Check | Where | What it catches | Notes |
| --- | --- | --- | --- |
| `hardset-check parse` | Linux | Syntax only, including inside inactive `#if canImport(UIKit)` blocks | Not types, labels, isolation, exhaustiveness or access control |
| Grep gates (3.4) | Linux | Aliases, unadapted motion, public API removal, lost labels, stray colours | Phase 2 rules only |
| `check_contrast.py` | Linux | Palette pairs from hex literals | Not alpha strokes, dimmed pixels or pairs drawn by views |
| Generator diff | Linux | Project and scheme drift | Run explicitly |
| `make check` | Linux | All of the above plus Core, Store and the query gate | No SwiftUI compile |
| macOS host `swift build` (ios-ui.yml:39-42) | CI, about 4 min | HardsetUI and HardsetFeature compile on macOS 15, so unguarded iOS-only APIs fail here | First real compile |
| iOS Debug app and widget (51-60) | CI | Full compile including `#Preview` blocks | Previews are compiled here |
| iOS Release (62-73) | CI | Uses of DEBUG-only symbols | Catalogue views must not depend on DEBUG code |
| HardsetTests (75-86) | CI | App smoke | |
| Snapshot render (88-102) | CI, about 35 min in | Test-target compile errors; writes the PNGs | Passes on "TEST SUCCEEDED" even if a PNG is missing; count the PNGs |
| Real-app journey and audit (109-157) | CI | Label strings, set-row tap geometry, accessibility audit (recorded, never fails the run) | A "Busy" launch race means rerun the job, not change code |
| PNG review | Coordinator | Visual states, crops, ax3 reflow | `gh run download <id> -n hardset-ios-ui -D /tmp/hardset-ui`, then `ls /tmp/hardset-ui/snapshots \| rg '^kit-'` |
| Device | Owner | Glare, press feel on menus and machined faces, haptics | Phase 7 checklist |

---

## 4. Compile-pitfall checklist (deduplicated, most likely first)

1. **Internal symbols named from the test target.** There is no `@testable`. Tests may name only public catalogue views, their `Section` enums and public kit inits. Faces and seams stay internal and are reached only through a catalogue.
2. **Non-exhaustive switches.** Every new `Section` case must appear in both the catalogue `sectionView` switch and the test's `height(_:)` switch. Switches over `CertaintyLevel`, `HardsetBanner.Kind`, `RestTimerState`, `SetRowField`, `Certainty` and Store errors take no `default`.
3. **Guessed signatures and types.** Copy inits verbatim from section 2. `CertaintyBadge` takes `CertaintyLevel`, not Core's `Certainty`. Pickers take `GymID` and `MachineID` (build them with `MachineID()`), not `UUID`. `Claim.init` traps on `.unevaluated`; use `Claim.unevaluated(source:)` or `StrengthMath`.
4. **Read-only accessibility environment keys.** `.environment(\.accessibilityReduceMotion, ...)` failed in CI run 43355703657. Treat `accessibilityShowButtonShapes`, `accessibilityReduceTransparency` and `accessibilityDifferentiateWithoutColor` the same way. Pass a Bool to the face instead.
5. **iOS-only APIs in the macOS host build.** The `accessibilityShowsLargeContentViewer { }` closure form, `.contentShape(.contextMenuPreview, _)`, `presentation*`, `textInputAutocapitalization`, `navigationBarTitleDisplayMode`, `toolbar(.hidden, for: .navigationBar)` and any glass API all go inside `#if os(iOS)`. Put the `#if` on its own line inside the modifier chain, as at Components.swift:88-92.
6. **Missing `public init`.** A public type's memberwise init is internal. `HardsetTag` and every catalogue view need an explicit `public init`.
7. **Name collisions.** A nested `Section` hides SwiftUI's `Section` inside the catalogue type. Never keep the private `CatalogSection` alongside the internal one. Inside `Tokens`, spell `SwiftUI.Color` and `SwiftUI.Text`. In files that import GRDB or SQLiteData (ST, HardsetFeature), spell `ButtonStyleConfiguration`.
8. **DEBUG-only symbols.** Anything defined under `#if DEBUG` used outside it breaks the Release step. Catalogue fixtures live outside DEBUG.
9. **Isolation.** Types with a computed `id`, or used as `sheet(item:)` or `task(id:)` keys, or captured in `@Sendable` closures, are declared `nonisolated` (the `HardsetSegment` pattern). Helpers called from `sensoryFeedback` trigger closures are `nonisolated static`. Closures capture values, not `self`.
10. **Knurl placement.** `.knurl()` is an overlay and draws over its content, so never call it on the countdown, the rest panel, text or the seal. Draw the knurl as `KnurlPattern(opacity: 0.08)` inside a `.background { ... }`, clipped to the backing shape (`.clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.control))` or `.clipShape(Circle())`), so it sits under glyphs and above the panel fill. `KnurlPattern` already resolves its tokens before its `Canvas` closure (KnurlPattern.swift:22-27), so write no new `Canvas`. Superseded by the plan, Ruling R9 (the seal's glyph is never over knurl).
11. **Dynamic colours.** Create them only through `swatch(...)` in DT. A `UIColor { }` formed in MainActor code traps with SIGTRAP when glass samples it off the main thread.
12. **`.fontWeight(_:)` after `.hardsetText(_:)`.** This has never compiled in this repo. P2-02 proves it once in its catalogue before any other task depends on it (R17). Superseded by the plan, Ruling R17: `.fontWeight(_:)` is not used; weighted tracked roles use the `hardsetText(_:weight:)` overload P2-02 adds in `U/TypeRole.swift`.
13. **Press faces.** A `@ViewBuilder` that returns different modifier chains for pressed and rest rebuilds the label. Use one modifier whose arguments change, as `MachinedModifier(isPressed:)` does (commit ca47acd).
14. **Live timers in snapshots.** A live `Text(timerInterval:)` once stalled a run. Use paused or fixed-date states, and put any running capture in its own last `@Test`.
15. **Crops.** Window heights are hand-set constants and crop silently. Check the bottom edge of every new PNG.
16. **`@State` initial values.** They are read once. Drive catalogue states with parameters or `.constant(...)` bindings.
17. **`Text + Text`.** Deprecated in iOS 26 and only a warning, but use interpolation.
18. **Process.** Test-target errors surface about 35 minutes into a run, so read test files with the most care. Pushes to the same ref cancel each other, so batch work. Never stage `Packages/HardsetKit/Package.resolved` (SourceKit-LSP rewrites it).

---

## 5. Task decomposition

The capture counts in this section are superseded by the plan's per-task counts and Ruling R30 (about 192 new captures in all).

Rules that apply to every task:

- Each task owns exactly the files listed for it. Same-wave tasks are disjoint.
- No task adds a colour, type, radius or motion token. If one seems necessary, the task stops and escalates, because the spec requires a `DESIGN.md` edit in the same change.
- `DESIGN.md` is edited only by P2-02 and P2-16. Wave tasks put the DESIGN.md text they need in their report.
- `Tools/check_contrast.py` and `U/KnurlPattern.swift` are edited only by P2-11.
- `T/ScreenSnapshotTests.swift`, `HardsetUITests` and every HardsetFeature file are edited by no Phase 2 task.
- Workers run the Linux gates and report diffs and results. The coordinator integrates each wave and pushes the phase branch once per wave, then reviews the `kit-*` PNGs per task. A rejected task is reverted alone; disjoint files make that clean.

**Common verification (V)** for every task: `hardset-check parse` with failures 0 and the expected count; the grep gates in 3.4 on the owned files; `python3 -B Tools/check_contrast.py` unchanged; `python3 -B Tools/generate_project.py && git diff --exit-code -- Hardset.xcodeproj`. On CI, the task's expected `kit-<group>-*` PNG count is present, the existing screen PNGs still render, and the real-app journey is green.

### Wave 0 (sequential)

**P2-01 Split shared files (pure move, no body changes)**

- Owns: `U/Components.swift`; new `U/PressStyle.swift` (HardsetPressStyle and its body), `U/ChipsAndSegments.swift` (HardsetChip, HardsetSegment, HardsetSegmentedControl), `U/Messages.swift` (StatLedger, HardsetBanner, DismissGlyphButton, HardsetLoadingState); `U/SelectionRow.swift`, with SelectionTag moved unchanged to new `U/HardsetTag.swift`; `U/SetRowView.swift`, with LoadFigure and SetRowMetrics moved to new `U/LoggerFormatting.swift`. Components.swift keeps the screen chrome and the DEBUG `ComponentsHarness`.
- Depends on: nothing.
- Verify: V; parse count 152; a move check, `diff <(git show HEAD~1:<old files> | sort) <(cat <old and new files> | sort)` showing only import lines; `git diff -M --color-moved=dimmed-zebra` shows nothing but moves.
- Captures: 0.

**P2-02 Kit scaffolding and shared surfaces**

- Owns: `U/TokenCatalogView.swift` (delete the private CatalogSection only); new `U/CatalogChrome.swift`; `U/PressStyle.swift` (internal `HardsetPressFace`); DT lines 398-452 (card and sheet on new names) and 495-522 and 636-649 (R3); new `U/SurfacesCatalogView.swift` with sections press, cards, type-weight probe (proves `.hardsetText(.caption).fontWeight(.semibold)`, R17); new `T/SurfacesCatalogSnapshotTests.swift`; `DESIGN.md` "Press feedback on self-drawn controls" and the new tag and machined-face rules (R2, R4). Superseded by the plan, Ruling R17: P2-02 also owns `U/TypeRole.swift` and always adds the `hardsetText(_:weight:)` overload, and the type-weight section compares plain and weighted text.
- Depends on: P2-01.
- Verify: V. Then push alone to CI. Wave 1 starts only after this run is green and `kit-surfaces-*` is reviewed, so the recipe and the `fontWeight` composition are proven once. Superseded by the plan, Ruling R17 and Task 2 Step 11: Wave 1 may be dispatched once P2-02 passes V and both reviews, and no Wave 1 branch is merged until this run's result is known.
- Captures: about 6.

### Wave 1 (parallel; every task depends on P2-02)

| Task | Owns | Components | Additional verification | Captures |
| --- | --- | --- | --- | --- |
| P2-03 Screen chrome | `U/Components.swift`; new `U/ScreenChromeCatalogView.swift`; new `T/ScreenChromeCatalogSnapshotTests.swift` | ScreenHeader, HeaderIconButton, HeaderIconMenu, glyph face, SectionLabel, hardsetTabRoot, hardsetNavigationTitle | Labels "Settings", "Workout options", "options" present in callers unchanged; ax3 capture. Superseded by the plan, Task 3: P2-03 also renames the one alias in the DEBUG `ComponentsHarness` | about 7 |
| P2-04 Chips, tag, segments | `U/ChipsAndSegments.swift`, `U/HardsetTag.swift` (public `HardsetTag` plus internal `typealias SelectionTag = HardsetTag`); new `U/ChipCatalogView.swift`; new `T/ChipCatalogSnapshotTests.swift` | HardsetChip and its face, HardsetTag, HardsetSegmentedControl | `rg "SelectionTag\(" U` still compiles through the typealias (4 sites); `HardsetSegment` keeps `nonisolated` | about 11 |
| P2-05 Messages | `U/Messages.swift`, `U/HardsetEmptyState.swift`; new `U/MessagesCatalogView.swift`; new `T/MessagesCatalogSnapshotTests.swift` | StatLedger, HardsetBanner and glyph, `hardsetArrival()`, HardsetLoadingState, HardsetEmptyState | All four `Kind` cases kept; "Dismiss" action kept | about 11 |
| P2-06 Entry and selection | `U/HardsetSearchField.swift`, `U/SelectionRow.swift`; new `U/SelectionCatalogView.swift`; new `T/SelectionCatalogSnapshotTests.swift` | Search field and chrome, SelectionRow, card style and face, indicator, icon square, pickerCancelAction | Internal signatures of card style, indicator and cancel action unchanged (used by the pickers); "Clear search" | about 7 |
| P2-07 Honesty, inline | `U/CertaintyBadge.swift`; new `U/HonestyCatalogView.swift`; new `T/HonestyCatalogSnapshotTests.swift` | CertaintyBadge, capsule, detail seam, AssumptionChip, UnevaluatedReadout, `CertaintyLevel.init(_ Certainty)` | `TokenCatalogView` certainty section still compiles; light-contrast capture added for this group (R31) | about 9 |
| P2-08 Methodology sheet | `U/MethodologySheet.swift`; new `T/MethodologySheetSnapshotTests.swift` (direct root) | MethodologySheet | `level(for:)` signature unchanged (two external callers) | about 6 |
| P2-09 Set row | `U/SetRowView.swift`; new `U/SetRowCatalogView.swift`; new `T/SetRowCatalogSnapshotTests.swift` | SetRowView, field face, log-control face, seal | `spokenLabel`, `voiceControlNames`, accessibility actions and hints diff empty; `SetRowMetrics` unchanged; on CI, `testWorkoutJourneyDark` and `testCorrectionsAndDiscardDark` green (tap geometry) | about 8 |
| P2-10 Keypad and load step | `U/NumericPad.swift`, `U/LoadStepSheet.swift`; new `T/KeypadSnapshotTests.swift` (direct root) | NumericPad, LoadStepSheet | "Next field", digits, "Done", display label prefix unchanged; failed-save seam internal | about 8 |
| P2-11 Rest bar | `U/RestBarView.swift`, `U/KnurlPattern.swift` (doc comment only), `Tools/check_contrast.py` (knurl-blend pairs for chalk on the knurled backing, R9); new `T/RestBarCatalogSnapshotTests.swift` | RestBarView | Contrast count rises by exactly the added pairs and all pass; running capture isolated last; labels unchanged | about 6 |

### Wave 2 (parallel; depends on Wave 1 being integrated, for visual review rather than compile)

| Task | Owns | Depends on | Additional verification | Captures |
| --- | --- | --- | --- | --- |
| P2-12 Exercise card | `U/ExerciseSectionView.swift`; new `T/ExerciseCardSnapshotTests.swift`, which may use `Fixtures.legPress()` because `Fixtures` is internal to the same test target | P2-03, P2-07, P2-09 | "options", "Remove movement", progress label, machine-chip labels unchanged; `spoken(_:)` and `restChoices` unchanged | about 4 |
| P2-13 Name entry and gym picker | `U/NameEntrySheet.swift`, `U/GymPickerView.swift`; new `T/NameAndGymSnapshotTests.swift` | P2-05, P2-06 | "Add", "Add a gym"; field remains the first `TextField`; additive params default to today's behaviour | about 6 |
| P2-14 Machine picker | `U/MachinePickerView.swift`; new `T/MachinePickerSnapshotTests.swift` | P2-05, P2-06 | Archive and load-step affordance rules unchanged; additive `isLoading` defaults to false | about 6 |
| P2-15 Exercise picker | `U/ExercisePickerView.swift`; new `T/ExercisePickerSnapshotTests.swift` | P2-04, P2-05, P2-06 | Row label prefix and hint unchanged; `SelectionTag` sites switched to `HardsetTag` | about 7 |

### Wave 3

**P2-16 Kit completion**

- Owns: `U/HardsetTag.swift` (delete the typealias once `rg "SelectionTag" U` shows no use); `U/SelectionRow.swift` badge call sites (two lines, after P2-06 is integrated); `U/Components.swift` `ComponentsHarness` (delete it only if every state it shows is in a catalogue, otherwise keep it; superseded by the plan, Tasks 3 and 16: P2-03 renames the harness's one alias, and P2-16 owns its deletion only); `DESIGN.md` (component rulings R4 to R10, R15, R16, R19, R20); the `.agents/HANDOFF.md` entry; optionally a DEBUG-only `KitCatalogView` preview index that is not snapshotted.
- Verify: V and `make check`; a final CI run with every `kit-*` PNG reviewed, about 100 new captures, and the run time checked against the timeout (R30). Superseded by the plan, Ruling R30: about 192 new captures against a timeout raised to 120 minutes.

The Wave 0 and Wave 3 tasks own files that Wave 1 and 2 tasks also own. That is acceptable because the waves are sequential.

---

## 6. Open questions and contradictions, with recommended rulings

| ID | Contradiction or question | Recommended ruling |
| --- | --- | --- |
| R1 | Delivery 2 says "every component above" (the whole kit list), but Delivery 3 to 6 assign screens, onboarding and fixtures to later phases | Phase 2 covers kit lines 461-468, restyled in place with frozen signatures (section 1). Screens and behaviour follow the delivery list |
| R2 | Press and material. DESIGN.md says self-drawn controls drop to 80-85% opacity "in place of a pressed fill". The spec says every self-drawn control sinks and that raised `steelRaised` surfaces carry edge light | Steel faces sink; everything else dims. Machined raised outlined faces with the `MachinedModifier` press: unselected chips, AssumptionChip, header circles, the segmented track (static), set-row value fields, a set machine chip, and keys and secondary buttons (already). Flat, with no edge light: tags, the empty-state socket, entry fields, SelectionIconSquare, banners, cards, the methodology citation card and the rest-bar panel. Opacity press: segments, the dashed "Add movement" slot, the exercise-name link, an unset machine chip, the dismiss glyph. A selected chip swaps `plateBlueFill` to `plateBlueFillPressed` like a primary button. An editing set-row field is `plateBlueSurface` with a 2 pt `plateBlue` ring and no edge light. P2-02 edits DESIGN.md to match. Superseded by the plan, Rulings R2, R18 and R40: the set log control (ready, next up) takes the opacity press through `HardsetPressFace`, the `CertaintyBadge` capsule and the "Clear search" glyph take `HardsetPressStyle`, and every sinking face is fed `isPressed` by `MachinedPressStyle`, the HardsetChip style or `SetFieldStyle`. |
| R3 | `HardsetButtonBody` and `HardsetKeyBody` animate `Motion.press` under Reduce Motion (DT:520, 647); DESIGN.md says "instantly or with `Motion.state`" | Route both through `Tokens.Motion.adaptive`, so the fill swaps instantly |
| R4 | The spec names `HardsetTag`; the code has the internal `SelectionTag` | Public `HardsetTag` with an internal typealias during the phase, removed in P2-16 |
| R5 | DESIGN.md says `figure` is for "small figures inside ledgers"; `StatLedger` uses `setEntry` for session totals | Keep `setEntry`, so the hero totals do not regress. P2-16 edits DESIGN.md to "rows and compact ledgers". Add a compact ledger only when Phase 6 History needs one |
| R6 | `HardsetBanner.Kind.info` is undocumented, unused in production, and plate blue means "act" | Keep the case for source compatibility, render it in the catalogue, document it as a neutral note, and list it for deletion in Phase 7 if still unused |
| R7 | DESIGN.md requires an insertion-only reveal with no animated transaction, but only SessionView has it (private), and HardsetRootView animates its container | Add a public `hardsetArrival()` in P2-05. Phase 2 pickers adopt it; SessionView and HardsetRootView adopt it in Phases 5 and 6 |
| R8 | The banner stroke `hue.opacity(0.35)` and the static capsule outline at 0.35 are alphas the gate cannot check | Keep both as decorative strokes that never carry meaning. P2-16 documents the exception |
| R9 | The spec and DESIGN.md put knurl behind the hero countdown; the KnurlPattern doc comment says "never behind values" | Allow it behind the `hero` countdown and as the seal's backing only. P2-11 updates the doc comment and adds checker pairs for chalk on the 8% chalk-blended `steelRaised`. By my estimate that is about 11:1 in dark and 13:1 in light, but the checker is the authority. Superseded by the plan, Ruling R9: the knurl is a `.background` backing, never the `.knurl()` overlay; the countdown is chalk in both states; the seal's glyph is never over knurl; 8 pairs, 184 in all |
| R10 | The spec says "four controls in a row"; the code uses `ViewThatFits` with two lines on most phones | Not a real conflict: the four controls stay in one row beneath the countdown. Keep `ViewThatFits`, which never truncates |
| R11 | Pitch 2 asks for segments 3, 8, 15 and 25 reps to walk high, moderate, low, unevaluated; the engine gives high, moderate, unevaluated, unevaluated | Phase 4 issue, recorded now. Change the segments to 3, 8, 12 and 15. The engine is a non-goal and wins |
| R12 | The spec wants keypad quick steps by the machine increment; the pad has fixed steps and no such parameter | Phase 5 (Live session). Phase 2 keeps the fixed steps |
| R13 | The spec plays `clank` then `success` on the log stamp; DESIGN.md says "`success` belongs to the log tap alone", and CoreHaptics `clank` is a Phase 4 item | Phase 2 keeps `success` only. Sequencing lands with Phase 4 CoreHaptics and Phase 5 logging, behind the "no perceived latency" anti-goal |
| R14 | Spec line 172 tints glass on "the next-up control", but set rows stay opaque and content never sits on glass | Next up stays an opaque `plateBlueFill`. Strike that clause from the spec in P2-16 |
| R15 | `matchedGeometryEffect` on the segment indicator versus "only transform and opacity animate" | Keep it. It is a geometry effect at render time and no sibling relays out |
| R16 | `hardsetNavigationTitle` uses `minimumScaleFactor(0.8)` against "adaptive layouts in place of shrinking text" | Keep it as the documented bar exception, with the Large Content Viewer. Name the exception in DESIGN.md |
| R17 | DESIGN.md applies tracking only through `hardsetText`, yet every component uses static fonts. A role modifier cannot take `.weight(.semibold)` | Use `hardsetText` for non-zero-tracking roles. For weighted variants use `.hardsetText(role).fontWeight(.semibold)`, proven once in P2-02. If CI rejects it, fall back to the static weighted font plus an explicit role-tracking modifier, decided in P2-02. Superseded by the plan, Ruling R17: P2-02 always adds `hardsetText(_:weight:)` in `U/TypeRole.swift`, and weighted tracked roles use only that form |
| R18 | `CertaintyPressStyle` uses opacity 0.7; DESIGN.md says 80-85% | Delete it and use `HardsetPressStyle` (0.8). Superseded by the plan, Ruling R18: the badge capsule takes `HardsetPressStyle`; `AssumptionChip` takes `MachinedPressStyle(shape: Capsule(), outlined: true)` |
| R19 | `SelectionCardBody` scales to 0.98; DESIGN.md says 0.97 | Use 0.97 |
| R20 | `SelectionCardBody` dims disabled rows to 0.4, and the audit measures dimmed text | Keep it. A disabled selection row is a disabled control like a button at 40%. Saved logger values stay undimmed |
| R21 | AGENTS.md quotes 86 files, 162 Core tests and 45 Store tests (now 147, 232 and 299). The HANDOFF "Open" bullet about dark `steelPressed` was already fixed by the fix wave | The coordinator corrects both outside Phase 2 tasks. No task should act on the stale bullet |
| R22 | The spec says `make check` includes project generation and that new files are "registered through the generator". The generator never lists package files and `make check` does not run it | Treat the idempotence diff in 3.3 as the check. Amend the spec sentence in P2-16 |
| R23 | The spec says "the snapshot test renders the whole kit"; one view crops, and a shared enum breaks disjoint ownership | Per-group catalogue views and suites. Together they render the kit |
| R24 | The spec's Startup screen shows a wordmark plus `HardsetLoadingState`; the component draws only a line | Keep the component a line. The wordmark is the startup view's job in Phase 4 (root gating) or Phase 6 |
| R25 | The spec lists gym and machine "merge"; no merge exists in Core, Store or UI | No merge in this rebuild without an engine ask. Amend the spec |
| R26 | DESIGN.md says gym and machine change failures use native alerts and that a failure must not scroll away; the Machine and Gym pickers put the banner inside the `ScrollView` | Phase 2 pins picker banners above the scroll, like ExercisePicker. Whether the caller uses an alert or a banner is a Phase 5 decision |
| R27 | DESIGN.md says never show an empty state before a read, but the Machine and Gym pickers have no loading input. NameEntrySheet cannot show typed text. GymPicker breaks the `pickerCancelAction` convention | Additive defaulted parameters: `isLoading: Bool = false` on both pickers, `initialName: String = ""` on NameEntrySheet (also enables rename reuse in Phase 6), `onCancel: (() -> Void)? = nil` on GymPickerView. Callers adopt them in Phase 5 or 6 |
| R28 | The spec's Setup page uses `HardsetSearchField` for a gym name, but it is search-specific (magnifier, `.search` submit, no capitalisation) | Phase 4 builds the name field from the public `hardsetNameInput()` and `hardsetEntryField(isFocused:)`. No new kit component. Amend the spec |
| R29 | Catalogue views ship in the Release binary | Follow `TokenCatalogView` (not DEBUG-gated) for consistency. Revisit in Phase 7 |
| R30 | About 100 new captures at about 4.3 s each adds about 7 min to runs that have taken 40-61 min, against a 75 min timeout | Hold to the per-task capture budgets in section 5. Raise `timeout-minutes` in ios-ui.yml only if a run exceeds 65 min, and as its own reviewed change. Superseded by the plan, Ruling R30: about 192 captures; the timeout is raised from 75 to 120 in its own reviewed commit before the Wave 1 push, and the budget is recomputed before each wave push |
| R31 | The spec asks for dark, light and Increase Contrast; light with Increase Contrast has never been captured | Dark, light and dark-contrast for every group. Add light-contrast only for the honesty group, where certainty hues keep normal values |
| R32 | HANDOFF records the cowfish worktree on `FrankieBiz/premium-frontend-design-plan`; this worktree is nursehound on `-plan-2` at the same commit | The coordinator picks one branch for Phase 2 before Wave 0 and does not push both |
| R33 | AGENTS.md's finish protocol says push to main; the spec says each phase is "committed on the feature branch" and reviewed before the next; the user said it is "not on main yet" | Commit on the feature branch. No push to main during the rebuild unless the owner explicitly asks |
| R34 | The set-row value has `minimumScaleFactor(0.85)` while DESIGN.md says "nothing shrinks to fit" | Keep it in Phase 2 and judge it from `kit-setrow` pounds captures at 375 pt in Phase 7 polish |
| R35 | The Volume spec wants `doseResponse` certainty per muscle; the heatmap uses `certaintyCeiling`, where counted-only muscles are low rather than unevaluated | Phase 6. No Phase 2 change |
| R36 | There are three separate `Certainty` to `CertaintyLevel` mappings (MethodologySheet, SessionView, WorkoutReceiptScreen) | Add a public `CertaintyLevel.init(_ certainty: Certainty)` in P2-07 and have `level(for:)` delegate to it. The SessionView and receipt copies move in Phases 5 and 6 |
| R37 | The spec's default is "every existing view ... is replaced" | For kit components in Phase 2, rewrite bodies in place and keep files and public signatures. The spec allows this ("the builder may keep a file where its body survives"), and it keeps screens, widget and tests compiling until Phases 5 to 7 replace them |
