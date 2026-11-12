# Front-end rebuild, Phase 1: Design system v2 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Hardset's design tokens with the "calibrated iron" system (plate palette, machined surfaces, knurl texture, condensed display type with size-specific tracking, spring motion tokens, a named haptic vocabulary) while every existing screen keeps building, and render a token catalogue to PNG on the macOS CI lane.

**Architecture:** All work lives in `Packages/HardsetKit/Sources/HardsetUI` and `Tools/check_contrast.py`. `DesignTokens.swift` is rewritten around the new role names; the old names become plain transitional aliases of the nearest new role so the ~13,000 lines of existing views and the widget compile unchanged until later phases replace them. New primitives (machined surfaces, knurl, type roles, haptics) are separate small files. A `TokenCatalogView` renders every token and primitive in every state, and a new snapshot test writes it to PNG in dark, light and dark-with-Increase-Contrast.

**Tech Stack:** Swift 6.2 tools, Swift 6 language mode, `@MainActor` by default in HardsetUI, SwiftUI on iOS 26.1, Swift Testing for the snapshot suite, Python 3 for the contrast checker. No new dependencies, no resource bundle, no Metal (see Task 2).

**Spec:** `docs/superpowers/specs/2026-11-12-frontend-rebuild-design.md`

## Global Constraints

- iOS 26.1 minimum, Swift 6 language mode with strict concurrency; HardsetUI is `@MainActor` by default and `NonisolatedNonsendingByDefault` is on.
- Every colour is a `swatch(light:dark:highLight:highDark:)` hex literal in `DesignTokens.swift` so `Tools/check_contrast.py` can read it. Text roles 7:1, control boundaries 3:1, pressed fills 4.5:1, in all four appearances.
- Colour providers stay `nonisolated` with `@Sendable` closures. No asset catalogue in HardsetUI.
- No third-party packages. No `.metal` files (they would require a resource bundle, which this package has deliberately avoided).
- System fonts only; every type role is a Dynamic Type text style.
- Only `transform` and `opacity` animate; Reduce Motion drops springs and scale.
- A new token requires a `DESIGN.md` edit in the same change.
- Commits authored by `FrankieBiz <frankabisignano@gmail.com>`; no AI attribution; no diagrams in docs or comments. Keep all existing comments and docstrings unless the token they describe is being changed.
- Linux cannot compile SwiftUI. The Linux gate is `hardset-check parse` and `make check`. Visual claims are verified only from the macOS CI artefact (`hardset-ios-ui`, workflow "iOS build and screens", triggered by pushing this branch). Never claim a render passed without the PNG.
- Old token names must keep compiling in every task of this phase: the widget (`HardsetWidget/HardsetWidgetBundle.swift`, 23 token uses) and every HardsetUI/HardsetFeature view still reference them.

## Review Focus

1. Increase Contrast with the dark appearance: `plateBlue` text on `plateBlueSurface` must still clear 7:1 when the surface swaps toward pure black. Pinned in Task 1 by the checker running all four appearances over the new role table.
2. A user with Reduce Transparency on: no token in this phase may be translucent except the two edge colours, which are pre-blended opaque values. Pinned in Task 2 by the catalogue rendering edges as opaque swatches and the checker treating them as ordinary swatches.
3. Dynamic Type at `accessibility5`: negative tracking on `hero` must scale with the resolved size, never a fixed point value, or letters collide at large sizes. Pinned in Task 3 by the catalogue's `accessibility3` capture of every type role.
4. Reduce Motion on: `Motion.fling(initialVelocity:)` must return `nil` through `Motion.adaptive` and a pressed key must still change fill. Pinned in Task 5 by the catalogue's pressed states rendering without scale under a `reduceMotion` environment override.
5. The widget target still compiles against the aliases, since nothing on Linux would notice if it did not. Pinned in Task 8 by the CI app and widget build step.

---

### Task 1: Plate palette, transitional aliases, contrast checker

**Files:**
- Modify: `Packages/HardsetKit/Sources/HardsetUI/DesignTokens.swift:20-130` (the `Tokens.Color` enum)
- Modify: `Tools/check_contrast.py:19-39` (role tables)
- Test: `Tools/check_contrast.py` (it is the test; `make check-contrast` runs it)

**Interfaces:**
- Produces: `Tokens.Color.canvas`, `steel`, `steelRaised`, `steelPressed`, `edgeLight`, `edgeShadow`, `hairline`, `controlEdge`, `chalk`, `chalkDim`, `plateBlue`, `plateBlueFill`, `plateBlueFillPressed`, `onPlateBlue`, `plateBlueSurface`, `plateGreen`, `plateGreenSurface`, `plateYellow`, `plateYellowSurface`, `plateRed`, `plateRedSurface`, `warning`, `warningSurface`, `series`, `certainty(_:)`, `certaintySurface(_:)` — all `SwiftUI.Color`.
- Produces: transitional aliases `background`, `surface`, `surfaceRaised`, `surfacePressed`, `border`, `controlBorder`, `textPrimary`, `textSecondary`, `accent`, `accentFill`, `accentFillPressed`, `onAccent`, `accentSurface`, `success`, `successSurface`, `pr`, `prSurface`, `error`, `errorSurface`, each `public static let old = new`.

- [ ] **Step 1: Rewrite the checker's role tables to the new names so it fails against the current file**

In `Tools/check_contrast.py` replace the four tables:

```python
SURFACES = ["canvas", "steel", "steelRaised"]
TEXT_ON = {
    "chalk": SURFACES,
    "chalkDim": SURFACES,
    "plateBlue": SURFACES + ["plateBlueSurface"],
    "plateGreen": SURFACES + ["plateGreenSurface"],
    "plateYellow": SURFACES + ["plateYellowSurface"],
    "plateRed": SURFACES + ["plateRedSurface"],
    "warning": SURFACES + ["warningSurface"],
    "onPlateBlue": ["plateBlueFill"],
}
TINTS = ["plateBlueSurface", "plateGreenSurface", "plateYellowSurface", "plateRedSurface", "warningSurface"]
PRESSED = {
    "chalk": ["steelPressed"],
    "chalkDim": ["steelPressed"],
    "onPlateBlue": ["plateBlueFillPressed"],
}
BOUNDARY_ON = {"controlEdge": SURFACES}
```

and in `main()` change `{"background", "surface"}` to `{"canvas", "steel"}` and the series loop's `("background", "surface")` to `("canvas", "steel")`.

- [ ] **Step 2: Run the checker to verify it fails**

Run: `python3 Tools/check_contrast.py`
Expected: exit 1, `Missing swatches in ...: canvas, chalk, chalkDim, ...`

- [ ] **Step 3: Rewrite `Tokens.Color` with the new swatches**

Replace the body of `public enum Color` with swatch literals for every role in the Interfaces block, using exactly these values (dark, light, highDark, highLight):

| Role | dark | light | highDark | highLight |
| --- | --- | --- | --- | --- |
| canvas | 0x0C0D10 | 0xF6F6F8 | 0x000000 | 0xFFFFFF |
| steel | 0x17181D | 0xFFFFFF | 0x000000 | 0xFFFFFF |
| steelRaised | 0x22242B | 0xEEEEF2 | 0x000000 | 0xFFFFFF |
| steelPressed | 0x2B2D35 | 0xE6E6EB | 0x26262B | 0xE6E6EA |
| edgeLight | 0x30333C | 0xFCFCFD | (default) | (default) |
| edgeShadow | 0x111216 | 0xDBDBDF | (default) | (default) |
| hairline | 0x2E3039 | 0xDEDEE4 | 0x9B9BA5 | 0x595964 |
| controlEdge | 0x7B7E8C | 0x7E8190 | 0x9B9BA5 | 0x595964 |
| chalk | 0xF3F3F5 | 0x141519 | 0xFFFFFF | 0x000000 |
| chalkDim | 0xB6B8C3 | 0x4B4D58 | 0xDADCE4 | 0x3B3D47 |
| plateBlue | 0x6FB7FF | 0x084A95 | 0x9FD0FF | 0x063A75 |
| plateBlueFill | 0x6FB7FF | 0x084A95 | 0x9FD0FF | 0x063A75 |
| plateBlueFillPressed | 0x5AA6F0 | 0x063C7A | 0x86C2FF | 0x052E5E |
| onPlateBlue | 0x0C0D10 | 0xFFFFFF | 0x000000 | 0xFFFFFF |
| plateBlueSurface | 0x10233A | 0xE3EFFC | 0x0A1A2C | 0xD6E8FA |
| plateGreen | 0x8FE3A3 | 0x0F5A27 | (default) | (default) |
| plateGreenSurface | 0x122A1A | 0xE5F5EA | (default) | (default) |
| plateYellow | 0xFFD86B | 0x604A00 | (default) | (default) |
| plateYellowSurface | 0x2B2410 | 0xFBF3DA | (default) | (default) |
| plateRed | 0xFF9A9A | 0x9A1B24 | (default) | (default) |
| plateRedSurface | 0x2E1516 | 0xFBEAEA | (default) | (default) |
| warning | 0xFFB27A | 0x7A3A00 | (default) | (default) |
| warningSurface | 0x2C1D12 | 0xFCEEE3 | (default) | (default) |

`edgeLight` and `edgeShadow` are opaque values pre-blended over `steelRaised` (a 60% `#3A3D47` and a 50% black in dark; an 80% white and an 8% black in light), documented as such in their doc comments so nobody "fixes" them into alpha. `series` keeps its four entries with `plateBlue` first. `certainty(_:)` maps high → `plateGreen`, moderate → `plateYellow`, low → `warning`, unevaluated → `chalkDim`; `certaintySurface(_:)` maps to the matching surfaces and `steelRaised` for unevaluated. Keep the existing doc comments where the role survives (adapting the name) and write new ones for the new roles; the comment on `accent` about the asset-catalogue blue moves to `plateBlue`.

- [ ] **Step 4: Add the transitional aliases below the new swatches**

Inside `Tokens.Color`, after the new roles, add a `// MARK: - Transitional aliases (deleted in phase 7)` block with one `public static let` per old name assigning the new role: `background = canvas`, `surface = steel`, `surfaceRaised = steelRaised`, `surfacePressed = steelPressed`, `border = hairline`, `controlBorder = controlEdge`, `textPrimary = chalk`, `textSecondary = chalkDim`, `accent = plateBlue`, `accentFill = plateBlueFill`, `accentFillPressed = plateBlueFillPressed`, `onAccent = onPlateBlue`, `accentSurface = plateBlueSurface`, `success = plateGreen`, `successSurface = plateGreenSurface`, `pr = plateYellow`, `prSurface = plateYellowSurface`, `error = plateRed`, `errorSurface = plateRedSurface`. Plain aliases, no deprecation attribute (123 call sites of `textSecondary` alone would drown the CI log).

- [ ] **Step 5: Run the checker and the parse gate**

Run: `python3 Tools/check_contrast.py && hardset-check parse`
Expected: `Contrast: all N pairs meet their floor across 23 swatches.` and the parse summary with zero errors.

- [ ] **Step 6: Commit**

```bash
git add Packages/HardsetKit/Sources/HardsetUI/DesignTokens.swift Tools/check_contrast.py
git -c user.name="FrankieBiz" -c user.email="frankabisignano@gmail.com" commit -m "Introduce the plate palette with transitional aliases"
```

---

### Task 2: Machined surfaces and the knurl pattern

**Files:**
- Create: `Packages/HardsetKit/Sources/HardsetUI/Machined.swift`
- Create: `Packages/HardsetKit/Sources/HardsetUI/KnurlPattern.swift`

**Interfaces:**
- Consumes: `Tokens.Color.steelRaised`, `steelPressed`, `edgeLight`, `edgeShadow`, `controlEdge`, `chalk`; `Tokens.Radius.control`; `Tokens.Stroke.hairline`.
- Produces: `extension View { func machinedRaised<S: InsettableShape>(_ shape: S, outlined: Bool = false) -> some View; func machinedPressed<S: InsettableShape>(_ shape: S) -> some View }`, `struct MachinedModifier<S: InsettableShape>: ViewModifier` with `init(shape: S, isPressed: Bool, outlined: Bool)`, and `public struct KnurlPattern: View` with `init(pitch: CGFloat = 3, opacity: Double = 0.08)`, plus `extension View { func knurl(opacity: Double = 0.08) -> some View }`.

- [ ] **Step 1: Write `MachinedModifier` in `Machined.swift`**

`body(content:)` fills `shape` with `steelPressed` when `isPressed`, else `steelRaised`; when not pressed, overlays `shape.strokeBorder(LinearGradient(colors: [edgeLight, edgeShadow], startPoint: .top, endPoint: .bottom), lineWidth: Tokens.Stroke.hairline)`; when `outlined`, overlays `shape.strokeBorder(Tokens.Color.controlEdge, lineWidth: Tokens.Stroke.hairline)` on top of the edge gradient; sets `.contentShape(shape)`. The pressed state draws no edge, so the key reads as having gone down. Add the two `View` extension functions.

- [ ] **Step 2: Write `KnurlPattern` in `KnurlPattern.swift`**

A `Canvas` that strokes two families of parallel hairlines at +45° and −45° across its bounds with spacing `pitch`, in `Tokens.Color.chalk` at `opacity`, line width 0.5. Deliberately a Canvas rather than a Metal shader: a `.metal` file in a package target needs a resource bundle, which this package avoids. `knurl(opacity:)` overlays `KnurlPattern` clipped to the view's own shape via `.clipped()` and `.allowsHitTesting(false)`. The pattern is never placed behind body text; its doc comment says so.

- [ ] **Step 3: Parse**

Run: `hardset-check parse`
Expected: zero errors.

- [ ] **Step 4: Commit**

```bash
git add Packages/HardsetKit/Sources/HardsetUI/Machined.swift Packages/HardsetKit/Sources/HardsetUI/KnurlPattern.swift
git -c user.name="FrankieBiz" -c user.email="frankabisignano@gmail.com" commit -m "Add machined surface modifiers and the knurl pattern"
```

---

### Task 3: Type roles with size-specific tracking

**Files:**
- Modify: `Packages/HardsetKit/Sources/HardsetUI/DesignTokens.swift` (the `Tokens.Text` enum, around lines 225-265)
- Create: `Packages/HardsetKit/Sources/HardsetUI/TypeRole.swift`

**Interfaces:**
- Produces: `Tokens.Text.Role: Sendable, CaseIterable` with cases `display, title, headline, label, labelEmphasis, provenance, unit, caption, sectionHeader, hero, readout, setEntry, figure`; each has `var font: Font`, `var textStyle: Font.TextStyle`, `var trackingRatio: Double` (hero −0.02, display −0.02, readout −0.01, caption +0.01, unit +0.01, all others 0). `extension View { func hardsetText(_ role: Tokens.Text.Role) -> some View }`.
- Keeps: every existing `Tokens.Text.<name>` static `Font` (the aliases later phases will stop using), with `display` and `title` changed as below.

- [ ] **Step 1: Change the two static fonts**

In `Tokens.Text`: `display` becomes `Font.system(.largeTitle, design: .default, weight: .semibold).width(.condensed)`; `title` becomes `Font.system(.title3, design: .default, weight: .semibold)` (standard width). Update both doc comments: display is a stamped plate face in the family of the figures; expanded width is retired.

- [ ] **Step 2: Write `Tokens.Text.Role` and `HardsetTextModifier` in `TypeRole.swift`**

`Role.font` returns the matching static font. `HardsetTextModifier` holds `@ScaledMetric(relativeTo:)` sized from a `baseSize` table (largeTitle 34, title 28, title2 22, title3 20, headline 17, body 17, callout 16, subheadline 15, footnote 13) and applies `.font(role.font).tracking(scaledSize * role.trackingRatio)`. Because `@ScaledMetric(relativeTo:)` needs the text style at init, build the modifier with `init(role:)` and set the wrapper via `_size = ScaledMetric(wrappedValue: role.baseSize, relativeTo: role.textStyle)`.

- [ ] **Step 3: Parse**

Run: `hardset-check parse`
Expected: zero errors.

- [ ] **Step 4: Commit**

```bash
git add Packages/HardsetKit/Sources/HardsetUI/DesignTokens.swift Packages/HardsetKit/Sources/HardsetUI/TypeRole.swift
git -c user.name="FrankieBiz" -c user.email="frankabisignano@gmail.com" commit -m "Add condensed display type and tracked type roles"
```

---

### Task 4: Motion and haptic vocabularies

**Files:**
- Modify: `Packages/HardsetKit/Sources/HardsetUI/DesignTokens.swift` (the `Tokens.Motion` enum)
- Create: `Packages/HardsetKit/Sources/HardsetUI/Haptic.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetUI/SetRowView.swift:156,472`
- Modify: `Packages/HardsetKit/Sources/HardsetUI/SessionView.swift:299,307,310`

**Interfaces:**
- Produces: `Tokens.Motion.press` (unchanged), `state = Animation.spring(response: 0.30, dampingFraction: 1.0)`, `reveal` (unchanged), `stamp` (unchanged), `static func fling(initialVelocity: Double = 0) -> Animation` returning `.interpolatingSpring(Spring(response: 0.35, dampingRatio: 0.80), initialVelocity: initialVelocity)`, `adaptive(_:reduceMotion:)` (unchanged).
- Produces: `Tokens.Haptic` with `static let clank: SensoryFeedback = .impact(weight: .heavy, intensity: 1.0)`, `success = .success`, `error = .error`, `selection = .selection`, `warning = .warning`. The CoreHaptics transient-plus-rumble pattern from the spec is deferred to Phase 4 with the welcome bar, where a `HapticEngine` wrapper will own `CHHapticEngine`; `clank` is the system impact until then.

- [ ] **Step 1: Update `Tokens.Motion`**

Change `state` to the spring and add `fling(initialVelocity:)`. Update the `stamp` comment from "the only spring in the app" to "the only spring with bounce outside a gesture release". Add a `zoom` doc comment stating that screen-to-screen zoom uses `navigationTransition(.zoom)` and carries no animation token.

- [ ] **Step 2: Write `Tokens.Haptic` in `Haptic.swift` and replace the five inline call sites**

`SetRowView.swift:156` uses `Tokens.Haptic.selection`; `:472` uses `Tokens.Haptic.success`; `SessionView.swift:299` uses `Tokens.Haptic.error`; `:307` uses `Tokens.Haptic.selection`; `:310`'s closure returns `Tokens.Haptic.warning` where it returned `.warning`. Behaviour is unchanged.

- [ ] **Step 3: Parse**

Run: `hardset-check parse`
Expected: zero errors.

- [ ] **Step 4: Commit**

```bash
git add Packages/HardsetKit/Sources/HardsetUI/DesignTokens.swift Packages/HardsetKit/Sources/HardsetUI/Haptic.swift Packages/HardsetKit/Sources/HardsetUI/SetRowView.swift Packages/HardsetKit/Sources/HardsetUI/SessionView.swift
git -c user.name="FrankieBiz" -c user.email="frankabisignano@gmail.com" commit -m "Name the motion and haptic vocabularies"
```

---

### Task 5: Machined button and key styles

**Files:**
- Modify: `Packages/HardsetKit/Sources/HardsetUI/DesignTokens.swift` (`HardsetButtonBody` and `HardsetKeyBody`, around lines 380-519)

**Interfaces:**
- Consumes: `machinedRaised(_:outlined:)`, `machinedPressed(_:)` from Task 2; `Tokens.Color.plateBlueFill`, `plateBlueFillPressed`, `onPlateBlue`, `chalk`, `plateBlue`, `plateRed`, `plateRedSurface`.
- Keeps: `HardsetButtonStyle(_:size:fullWidth:)`, `HardsetButtonStyle.Role`, `.Size`, `HardsetKeyStyle()` signatures unchanged.

- [ ] **Step 1: Restyle `HardsetButtonBody`**

`.secondary` replaces its `background` plus `controlBorder` overlay with `machinedRaised(shape, outlined: true)` when not pressed and `machinedPressed(shape)` when pressed. `.primary` keeps the solid `plateBlueFill` / `plateBlueFillPressed` fills and adds the edge gradient stroke when not pressed. `.quiet` and `.destructive` are unchanged apart from role names. Scale 0.97 on press stays, dropped under Reduce Motion, as today.

- [ ] **Step 2: Restyle `HardsetKeyBody`**

Replace its background and overlay with `machinedRaised(shape, outlined: true)` when not pressed and `machinedPressed(shape)` when pressed. Scale 0.96 stays, dropped under Reduce Motion.

- [ ] **Step 3: Parse**

Run: `hardset-check parse`
Expected: zero errors.

- [ ] **Step 4: Commit**

```bash
git add Packages/HardsetKit/Sources/HardsetUI/DesignTokens.swift
git -c user.name="FrankieBiz" -c user.email="frankabisignano@gmail.com" commit -m "Machine the button and key styles"
```

---

### Task 6: Token catalogue and its snapshot

**Files:**
- Create: `Packages/HardsetKit/Sources/HardsetUI/TokenCatalogView.swift`
- Create: `Packages/HardsetKit/Tests/HardsetUISnapshotTests/TokenCatalogSnapshotTests.swift`
- Modify: `Packages/HardsetKit/Tests/HardsetUISnapshotTests/ScreenSnapshotTests.swift:345-392` (`Snapshot.capture` gains a contrast parameter)

**Interfaces:**
- Consumes: everything produced in Tasks 1 to 5.
- Produces: `public struct TokenCatalogView: View { public init() }`; `Snapshot.capture(_:size:style:typeSize:contrast:_:)` with `contrast: UIAccessibilityContrast = .normal` applied through `host.traitOverrides.accessibilityContrast = contrast` (iOS 17+ API).

- [ ] **Step 1: Write the snapshot test first**

```swift
@Suite("Token catalogue renders for review", .serialized)
struct TokenCatalogSnapshotTests {
  @Test func catalogue() async throws {
    let tall = CGSize(width: 402, height: 2400)
    try await Snapshot.capture("tokens-dark", size: tall) { TokenCatalogView() }
    try await Snapshot.capture("tokens-light", size: tall, style: .light) { TokenCatalogView() }
    try await Snapshot.capture("tokens-dark-contrast", size: tall, contrast: .high) { TokenCatalogView() }
    try await Snapshot.capture("tokens-dark-ax3", size: CGSize(width: 402, height: 3600), typeSize: .accessibility3) { TokenCatalogView() }
    try await Snapshot.capture("tokens-dark-reduced-motion", size: tall) {
      TokenCatalogView().environment(\.accessibilityReduceMotion, true)
    }
  }
}
```

Wrap the file in the same `#if canImport(UIKit)` guard as `ScreenSnapshotTests.swift`.

- [ ] **Step 2: Add the `contrast` parameter to `Snapshot.capture`**

After `host.overrideUserInterfaceStyle = style`, set `host.traitOverrides.accessibilityContrast = contrast`. Default `.normal` so every existing call is unchanged.

- [ ] **Step 3: Write `TokenCatalogView`**

A `ScrollView` on `Tokens.Color.canvas`, page margin `loose`, sections separated by `section` spacing, each with a `SectionLabel`:

1. Palette: one row per colour role (name in `caption`, a 44 pt swatch of the colour on `steel`, and the role's text sample on each of `canvas`, `steel`, `steelRaised` where it is a text role). Order: surfaces, edges, text, plate blue family, plate green, plate yellow, plate red, warning, series.
2. Machined: a 56 pt `machinedRaised` rectangle, an outlined one, a pressed one, and a 120 by 56 pt raised rectangle with `.knurl()`.
3. Type: every `Tokens.Text.Role` showing its name and a sample ("Chest press" for text roles, "132.3 kg" for figure roles) via `.hardsetText(role)`.
4. Buttons: each `HardsetButtonStyle.Role` in both sizes, plus a disabled primary; a row of three `HardsetKeyStyle` keys. Pressed states are shown by a second instance of each with `MachinedModifier(shape:isPressed: true, outlined:)` applied directly, since a `ButtonStyle` cannot be forced pressed in a render.
5. Certainty: all four `CertaintyLevel`s as `CertaintyBadge`.
6. Motion and haptics: a text table listing each `Tokens.Motion` and `Tokens.Haptic` name with its value, so the PNG documents them.

- [ ] **Step 4: Parse**

Run: `hardset-check parse`
Expected: zero errors.

- [ ] **Step 5: Commit**

```bash
git add Packages/HardsetKit/Sources/HardsetUI/TokenCatalogView.swift Packages/HardsetKit/Tests/HardsetUISnapshotTests/TokenCatalogSnapshotTests.swift Packages/HardsetKit/Tests/HardsetUISnapshotTests/ScreenSnapshotTests.swift
git -c user.name="FrankieBiz" -c user.email="frankabisignano@gmail.com" commit -m "Render the token catalogue for review"
```

---

### Task 7: DESIGN.md for the new system

**Files:**
- Modify: `DESIGN.md` (sections "Point of view", "Palette", "Typography", "Motion", and the haptics paragraph)
- Modify: `docs/superpowers/specs/2026-11-12-frontend-rebuild-design.md` (two lines: the light `plateBlue`/`plateGreen` values and the knurl technique)

- [ ] **Step 1: Rewrite the palette table**

Replace the palette table with the 23 roles and the exact hex values from Task 1, including an "Edges" note that `edgeLight` and `edgeShadow` are opaque pre-blended values. Add the "calibrated iron" paragraph from the spec's aesthetic section to "Point of view", replacing the "Colour is evidence" bullet's wording so the plate story is stated. Keep the Increased Contrast paragraph, updating names and values.

- [ ] **Step 2: Rewrite the typography table and add the tracking rule**

`display` is Large Title, semibold, condensed; `title` is Title 3, semibold. Add one sentence: tracking is a ratio of the resolved size (hero and display −2%, readout −1%, caption and unit +1%), applied by `hardsetText(_:)`.

- [ ] **Step 3: Rewrite the motion table and the haptics paragraph**

Motion table: `press` 120 ms ease-out; `state` spring, response 0.30, damping 1.0; `reveal` 280 ms ease-out; `stamp` 300 ms spring, bounce 0.3; `fling(initialVelocity:)` spring, response 0.35, damping 0.80, gesture release only; `zoom` the system zoom transition for card-to-screen. Haptics paragraph lists `Tokens.Haptic` names and their rules as in the spec's haptic table, noting `clank` is the heavy system impact until the welcome bar introduces CoreHaptics.

- [ ] **Step 4: Correct the spec**

In the spec's palette table change `plateBlue` light to `#084A95` (and `plateBlueFill`), `plateGreen` light to `#0F5A27`, and remove the "Known at writing" sentence. In "Materials and depth" change "A Metal `layerEffect` draws" to "A `Canvas` pattern (`KnurlPattern`) draws", with the reason (no resource bundle).

- [ ] **Step 5: Run the full Linux gate**

Run: `make check`
Expected: exit 0; parse count, Core tests, Store tests, query gate and `Contrast: all N pairs meet their floor` all reported.

- [ ] **Step 6: Commit**

```bash
git add DESIGN.md docs/superpowers/specs/2026-11-12-frontend-rebuild-design.md
git -c user.name="FrankieBiz" -c user.email="frankabisignano@gmail.com" commit -m "Document the calibrated iron design system"
```

---

### Task 8: Build and render on the macOS lane

**Files:**
- None created. Fixes from the review land in the files above.

- [ ] **Step 1: Push the branch**

Run: `git push -u origin FrankieBiz/premium-frontend-design-plan`
Expected: the push is accepted and GitHub starts "iOS build and screens".

- [ ] **Step 2: Watch the run to completion**

Run: `gh run list --branch FrankieBiz/premium-frontend-design-plan --limit 1` then `gh run watch <id> --exit-status`
Expected: exit 0 after roughly 40 minutes. If it fails, read the failing step's log with `gh run view <id> --log-failed`, fix, commit, push, and repeat. Two consecutive failures of the same step mean stop and report the error with a hypothesis rather than pushing again.

- [ ] **Step 3: Download and review the catalogue**

Run: `rm -rf /tmp/hardset-ui && gh run download <id> -n hardset-ios-ui -D /tmp/hardset-ui && ls /tmp/hardset-ui/snapshots | grep tokens`
Expected: `tokens-dark.png`, `tokens-light.png`, `tokens-dark-contrast.png`, `tokens-dark-ax3.png`, `tokens-dark-reduced-motion.png`. Open each with the Read tool and check, in order: every palette row renders the named colour (not clear or black); the raised rectangle shows a lighter top edge and darker bottom edge; the knurl is visible but faint; `display` and `hero` are condensed and tighter than body; the accessibility3 capture shows no overlapping letters in `hero`; the pressed key shows no edge and a darker fill; in the contrast capture the canvas is pure black and chalk pure white. Also open `components-dark.png`, `session-dark.png` and `keypad-dark.png` to confirm the existing screens still render on the aliases with plate blue in place of cyan.

- [ ] **Step 4: Record the verification**

Append a dated entry to `.agents/HANDOFF.md` with: objective, branch, run id, the Linux `make check` summary line, which PNGs were reviewed and what was seen, and anything left for a Mac or device. Commit:

```bash
git add .agents/HANDOFF.md
git -c user.name="FrankieBiz" -c user.email="frankabisignano@gmail.com" commit -m "Record phase 1 design system verification"
git push
```

---

## Remaining phases

Each later phase gets its own plan written when the previous one is green on the macOS lane, because its tasks depend on the exact names the previous phase produced:

2. Component kit on the new tokens (every component with an all-states preview and snapshot).
3. `TourFixtures` and staged screens (`ScaledPhoneFrame`, every screen from fixtures).
4. Onboarding (welcome bar with CoreHaptics `clank`, pitch pages, tour, setup, gating, UI test).
5. Live session and keypad on the kit with the real coordinator, auto rest on log.
6. Train, History, Receipt, Volume, Progress, Settings on the kit.
7. Alias deletion, polish from PNGs, owner's device checklist, final `DESIGN.md`.
