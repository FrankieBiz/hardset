# HardsetUI token and layout accessibility audit

Reviewed 2026-10-24 against baseline `0542a22`. Maintainer: FrankieBiz <frankabisignano@gmail.com>.

This is an audit and concrete upgrade specification. The proposed tokens and layout fixes have not been applied. Measurements cover source-defined sRGB colors and layout constraints; they do not certify a rendered iOS interface or whole-app WCAG AAA conformance.

## Acceptance criteria

- Use **7:1 for all meaningful application text**, including captions, units, provenance, errors, and action labels. WCAG 2.2 SC 1.4.6 permits 4.5:1 for qualifying large text. Its size definition uses CSS points, so a SwiftUI style name or native point size alone does not establish that exception. Keeping 7:1 throughout avoids that ambiguity. Disabled controls and decoration have exceptions. [W3C: Contrast (Enhanced)](https://www.w3.org/WAI/WCAG22/Understanding/contrast-enhanced.html).
- Required control outlines, state indicators, and chart marks need **3:1 against adjacent colors** under SC 1.4.11, an AA criterion still applicable when targeting AAA. Decorative surface separation does not independently require 3:1. [W3C: Non-text Contrast](https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html).
- Keep Hardset's **44×44pt minimum**, and **56×56pt minimum for logger actions**. Apple's current table lists 44×44pt as the iOS default and 28×28pt as its minimum; the comment describing 44pt as Apple's absolute floor is outdated. Hardset's larger minimum remains appropriate. [Apple HIG: Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility).
- WCAG SC 2.5.5 uses **44×44 CSS pixels**, with exceptions. Native points and CSS pixels are separate units; use the native policy above and inspect actual hit regions. 56pt is a product choice, not a WCAG requirement. [W3C: Target Size (Enhanced)](https://www.w3.org/WAI/WCAG22/Understanding/target-size-enhanced.html).
- Numerical contrast cannot guarantee visibility in glare. Verify both appearances and Increase Contrast on hardware under bright gym lighting and daylight. Apple explicitly recommends testing lighting conditions and supplying increased-contrast variants for custom colors. [Apple HIG: Color](https://developer.apple.com/design/human-interface-guidelines/color).

## DesignTokens.swift: colors

Source: [DesignTokens.swift](../Packages/HardsetKit/Sources/HardsetUI/DesignTokens.swift), lines 22–76; [accent asset](../Hardset/Assets.xcassets/AccentColor.colorset/Contents.json).

### P1: The neutral surfaces are usable; their separation cannot identify a control

The backgrounds are slightly blue, rather than equal-channel grays. Hex values below are the nearest 8-bit representation; calculations use the exact source tuples.

| Token | Light sRGB tuple | Light hex | Dark sRGB tuple | Dark hex |
| --- | --- | --- | --- | --- |
| `background` | `(0.976, 0.976, 0.980)` | `#F9F9FA` | `(0.055, 0.055, 0.063)` | `#0E0E10` |
| `surface` | `(1.000, 1.000, 1.000)` | `#FFFFFF` | `(0.110, 0.110, 0.122)` | `#1C1C1F` |

Surface/background contrast is **1.053257:1 light** and **1.134790:1 dark**. This is acceptable for decorative grouping. It is inadequate if the fill difference is the only way to identify a field, key, or selection. Keep these normal-appearance values; add a dedicated opaque border where boundaries communicate interaction. Increasing every surface's brightness is unnecessary and reduces light-text contrast in dark mode.

### P1: The accent is a measured text-contrast failure

`accent` delegates to `SwiftUI.Color.accentColor`. The app asset contains one universal sRGB color, `(0.180, 0.510, 0.965)`, approximately **`#2E82F6`**, without dark or increased-contrast variants. No explicit tint override was found in the audited UI/app sources. These measurements apply when that asset supplies the accent; a package preview or host can resolve a different accent.

| Accent foreground against | Light | Dark |
| --- | --- | --- |
| Opaque `background` | 3.533189:1 | 5.181042:1 |
| Opaque `surface` | 3.721356:1 | 4.565638:1 |

All four fail 7:1. Both light pairs also fail the AA 4.5:1 ordinary-text threshold. This affects accent-colored text such as machine names, rest adjustments, chart explanations, and add actions. Solid accent icons on these opaque surfaces do exceed 3:1; do not classify every use of blue as failing non-text contrast.

`NumericPad.swift:114` and `:127` use `accent.opacity(0.15)` for action backgrounds. If accent text is also used, compositing that tint over `surface` produces only **3.121063:1 light / 3.811225:1 dark**. The current footer does not explicitly set its foreground, so those are conditional pairing measurements, not a claim about its actual rendered label color. Give footer labels and fills explicit semantic roles.

### P1: System color names do not establish AAA for status or secondary text

`textPrimary` and `textSecondary` are system colors; `success`, `warning`, `error`, `pr`, and `certainty(_:)` use system hue names. Their rendered values depend on platform, traits, and context. Do not assign guessed hex values to `.secondary`, or assume system colors provide 7:1 on Hardset's custom surfaces.

For scale, Apple's currently documented normal light palette includes green `#34C759`, orange `#FF8D28`, red `#FF383C`, and yellow `#FFCC00`. Against white these calculate to **2.2200, 2.3096, 3.5697, and 1.5120:1** respectively. These are illustrative calculations from the published palette, not measurements of SwiftUI's resolved colors. [Apple HIG: Color specifications](https://developer.apple.com/design/human-interface-guidelines/color#Specifications).

The small certainty text, borrowed-history warnings, error banners, and PR titles need measured foreground roles. Preserve the existing certainty words and symbols: they already carry meaning beyond hue. `certainty(_:)` must return the upgraded roles rather than continuing to return `.green`, `.yellow`, `.orange`, or `.secondary` directly.

### Concrete normal-appearance token upgrades

Use the following **opaque sRGB foregrounds** for application content. Each minimum is the smaller ratio against `background` and `surface` in that appearance. Ratios are shown to four decimals; pass/fail was evaluated before rounding.

| Role replacing existing value | Proposed light | Minimum light ratio | Proposed dark | Minimum dark ratio |
| --- | --- | --- | --- | --- |
| `textPrimary`: `.primary` | `#151518` | 17.3023:1 | `#F5F5F7` | 15.6041:1 |
| `textSecondary`: `.secondary` | `#4D4D56` | 7.9388:1 | `#B9B9C2` | 8.7229:1 |
| `accentForeground`: inherited accent | `#06499A` | 8.2139:1 | `#86B7FF` | 8.2776:1 |
| `successForeground`: `.green` | `#155B28` | 7.7915:1 | `#8DE5A2` | 11.2153:1 |
| `warningForeground`: `.orange` | `#694400` | 8.2134:1 | `#FFD36B` | 11.9596:1 |
| `errorForeground`: `.red` | `#981C29` | 7.8707:1 | `#FF9AA2` | 8.4110:1 |
| `prForeground`: `.yellow` | `#5F4B00` | 7.9976:1 | `#FFE080` | 13.1279:1 |
| New `controlBorder` | `#85858F` | 3.4681:1 | `#70707B` | 3.4730:1 |

Map high certainty to `successForeground`, moderate to `prForeground`, low to `warningForeground`, and unevaluated to `textSecondary`. Keep text and icon differences. The border role is for non-text information and must not be reused as caption text.

Separate accent foreground from decorative tint and filled-button colors. An optional opaque `actionSurface` of **`#EDF3FF` light / `#142034` dark** gives **7.7718:1 / 7.9561:1** with the proposed accent foregrounds. Do not place white labels on every bright fill: audit each label/fill pair independently. Native system controls can retain their system styling; the table specifies application-owned content on application-owned surfaces.

### P1: Add increased-contrast resolution

The dynamic helper switches only on light/dark appearance. Add contrast as a second input, retaining the existing code-based UIKit/AppKit approach and avoiding a new package resource build step.

| Role | Proposed increased-contrast light | Proposed increased-contrast dark |
| --- | --- | --- |
| `background`, `surface`, `actionSurface` | `#FFFFFF` | `#000000` |
| `textPrimary` | `#000000` | `#FFFFFF` |
| `textSecondary` | `#3D3D44` | `#DDDDE4` |
| `accentForeground` | `#003C85` | `#AFD0FF` |
| `controlBorder` | `#595964` | `#9B9BA5` |

On these increased-contrast surfaces, primary text reaches 21:1; secondary text reaches 10.7726:1 light / 15.5373:1 dark; accent text reaches 10.5792:1 / 13.2891:1. Normal status foregrounds may be retained: white/black surfaces increase their existing ratios. Strong borders preserve grouping when background and surface share a color.

Use `traits.accessibilityContrast` in the UIKit provider and the corresponding increased-contrast appearances on AppKit, or resolve typed token palettes from SwiftUI's appearance/contrast environment. Keep resolution within HardsetUI. Verify trait changes live; adding static constants alone does not implement Increase Contrast. Use opaque colors for critical content, including pressed states.

## DesignTokens.swift: typography and geometry

Source: lines 79–109. The actual font namespace is **`Tokens.Text`**, not `Tokens.Typography`.

System text styles and monospaced digits are good existing choices. They support Dynamic Type and prevent digit-width jitter. The point sizes below are the default iOS Large category, not fixed sizes; smaller/larger categories change them. Apple's iOS default/minimum guidance is 17pt/11pt, so 12pt captions are not automatically a HIG violation. They are a weak default for essential information read at arm's length. [Apple HIG: Typography](https://developer.apple.com/design/human-interface-guidelines/typography).

| Token/use | Current default | Concrete proposed upgrade |
| --- | --- | --- |
| `readout` | Rounded `.title2`, 22pt, regular | Rounded `.title`, 28pt, medium, monospaced digits for the rest timer/keypad |
| `setEntry` | Rounded `.title3`, 20pt, regular | Rounded `.title2`, 22pt, medium, monospaced digits |
| `label` | `.subheadline`, 15pt | `.body`, 17pt; use `.headline` for primary action labels |
| `caption` | `.caption`, 12pt | `.footnote`, 13pt for supplemental notes only |
| New `provenance` | Important caveats reuse 12pt caption | `.callout`, 16pt; use for certainty, borrowed-machine notes, and corrections |
| New `unit` | Suffixes reuse 12pt caption | `.callout`, 16pt, alongside 22pt values |

Keep semantic font styles and allow vertical expansion; do not substitute fixed `.system(size:)` values. Preserve Bold Text behavior and test the resulting fonts. Larger fonts must land with the adaptive layouts below.

Retain spacing steps **2/4/8/12/16/24pt** and radii **10/16pt**; no measured requirement justifies changing them wholesale. Add typed `CGFloat` geometry roles: `controlBorderWidth = 1`, `focusBorderWidth = 2`, and `controlGap = 8`. Use 2pt control borders in increased contrast and evaluate 12pt gaps in expanded layouts. These are proposed product values, not universal HIG spacing mandates. Keep `hairline = 2` as spacing; it is not a one-device-pixel stroke.

## NumericPad.swift and SetRowView.swift: keypad height and targets

### P1: Quick adjusters bypass the logger target

`NumericPad.swift:71` sets `minHeight: 36`, below both Hardset's 44pt general minimum and its 56pt logger minimum. Change it inside the button label:

```swift
// Before
.frame(maxWidth: .infinity, minHeight: 36)

// After
.frame(minWidth: Tokens.loggerTapTarget,
       maxWidth: .infinity,
       minHeight: Tokens.loggerTapTarget)
.contentShape(Rectangle())
```

Digits and footer actions already declare 56pt minimum heights. Preserve the stable decimal-key slot. Check minimum width as well as height when quick adjusters split into four columns.

### P1: Fixed 370pt sheet is smaller than the pad's declared minimum

When footer actions are present, `NumericPad.swift:43–56` requires at least **36 + (4 × 56) + 56 + (5 × 8) + (2 × 12) = 380pt**, before any additional presentation geometry. `SetRowView.swift:223–227` requests a **370pt** sheet. After giving adjusters 56pt, the minimum becomes **400pt**, before Dynamic Type grows any labels. This is a source-level constraint mismatch; no clipping screenshot was obtained.

Replace the sole `.height(370)` detent with content-aware sizing or larger supported detents such as `[.medium, .large]`, and provide vertical scrolling when the available height is smaller than content. Update the matching `presentationBackgroundInteraction` configuration. Keep actions reachable at accessibility sizes and in landscape; replacing 370 with another fixed height is insufficient.

## SetRowView.swift: preserve targets instead of shrinking values

### P1: Value widths are unconstrained and text can shrink to 60%

At lines 171–177, numeric text uses `.minimumScaleFactor(0.6)` and fields have a minimum height but no minimum width. At the default 20pt style that permits approximately 12pt digits, counteracting arm's-length readability and user enlargement.

With two 56pt-wide fields, the current row needs at least **346pt**: ordinal 28 + history 78 + fields 112 + log 56 + four gaps 48 + horizontal padding 24. SessionView adds another **16pt** outside the row, requiring **362pt** overall before long numbers or increased fonts. At a 320pt overall width, only 35pt per numeric field remains after fixed reservations, if remaining width is shared equally. SwiftUI may instead compress or overflow other content; the layout does not guarantee the intended field sizes.

Add `minWidth: Tokens.loggerTapTarget` inside each value button label, remove the 0.6 shrink fallback, and use a vertical/adaptive row when content does not fit. Move history/provenance above the edit controls; retain both values and the log action at 56pt or larger. Choose layouts from available space and `dynamicTypeSize`, with scrolling for exceptionally narrow constraints. Do not hide borrowed-machine caveats to recover width.

Use the proposed border token to identify editable fields. The current selection stroke uses accent at line 188; preserve an explicit selection indication after separating tint and foreground roles. Verify actual keyboard focus separately from edit selection.

## CertaintyBadge.swift and ExerciseSectionView.swift: interactive labels

### P1: The certainty disclosure and history title have no explicit minimum target

`CertaintyBadge.swift:21–33` is a plain button around caption text and an icon. `ExerciseSectionView.swift:70–85` similarly makes the exercise title a plain button. Add minimum width/height and a rectangular content shape **inside each button's label**, using 44pt for general disclosures and 56pt for logger interactions. Keep the visible badge compact if desired; its hit region must remain large and must not overlap neighboring controls.

`AssumptionChip` at `CertaintyBadge.swift:82` and the chart explanation at `ProgressionChartView.swift:91` put a 44pt frame outside the plain button. That reserves layout space but does not reliably guarantee a matching activation region. Move the frame/content shape inside the label, then inspect hit testing on iOS.

```swift
// Before: frame applied after the plain button.
.buttonStyle(.plain)
.frame(minHeight: Tokens.minimumTapTarget)

// After: apply to the HStack inside the label; keep the button style outside.
.frame(minWidth: Tokens.minimumTapTarget,
       minHeight: Tokens.minimumTapTarget)
.contentShape(Rectangle())
```

## RestBarView.swift and SessionView.swift: width and insets

### P1: Four 56pt controls crowd the countdown

`RestBarView.swift:44–64` combines the countdown, a spacer, and four 56pt controls with five 12pt gaps and 24pt horizontal padding. That reserves **308pt before the countdown's width**. At 320pt, only 12pt remains for the time and exercise metadata. A single horizontal row cannot preserve meaningful content at that width or with large text.

Use a two-row layout when space is insufficient: countdown/metadata above, four controls below. Keep all actions available and at least 56pt square. Avoid shrinking or clipping the timer to fit. At large accessibility sizes, permit another arrangement or scrolling if necessary.

`SessionView.swift:147` adds a guessed 72pt bottom clearance while `:150` already uses `safeAreaInset` for the rest bar. Rely on the inset's measured reservation and remove the extra clearance unless a separately measured design margin is needed. A taller adaptive rest bar must not depend on a fixed 72pt allowance.

## ProgressionChartView.swift: apply tokens to chart semantics

At lines 136/141, machine series use the chart's automatic palette; its colors are not audited merely by upgrading `Tokens.Color`. At lines 147–153, a 1pt warning-colored rule and symbol mark machine changes. Audit series against plot backgrounds at 3:1, use patterns/symbols and labels to distinguish series, and use the proposed warning foreground with at least a 2pt rule for glare resilience. Audit chart annotations and axis/legend text at 7:1. The fixed 220pt chart height at line 159 needs a larger-text layout check so growing legends do not obscure data.

## Verification and implementation order

1. Land opaque foreground roles, certainty mappings, explicit footer colors, and increased-contrast resolution. Resolve and test every used foreground/fill combination, including pressed, selected, and system control states.
2. Enforce targets inside labels and fix keypad sheet sizing together. Raising the adjuster height without fixing the sheet worsens the mismatch.
3. Land larger semantic typography together with adaptive set rows and rest bars. Preserve the current stable digits and opaque logger surfaces.
4. On iOS, verify light/dark × standard/increased contrast, smallest and largest Dynamic Type categories, Bold Text, and narrow/landscape layouts. Test visible regions and hit regions separately with accessibility inspection and taps near control edges. Repeat under bright ambient lighting on physical hardware; the proposed palette is a numerical baseline, not a glare certification.

Contrast was calculated with the WCAG sRGB transfer function (`c / 12.92` through `0.04045`, otherwise `((c + 0.055) / 1.055)^2.4`), relative luminance weights `0.2126/0.7152/0.0722`, and `(Llighter + 0.05) / (Ldarker + 0.05)`. Candidate hex values were decoded exactly; existing tuples were not rounded to hex before calculation. Alpha examples composite channel values over the stated surface before calculating luminance. All seven proposed text roles were checked against both exact normal surfaces in both appearances; every pair exceeds 7:1. Both normal border roles exceed 3:1.

`make check` passed: 86 Swift files parsed with zero failures, 167 Core tests in 22 suites, and 45 Store tests in five local suites. The Store gate loads the official SQLite UUID extension and excludes CloudKit wiring. `git diff --check` also passed. The project generator was not rerun for this documentation change; the existing handoff records generator reproducibility drift.

Linux verification cannot compile SwiftUI or inspect native hit testing, trait resolution, ambient-light performance, or the rendered app. No Core, Store, schema, concurrency, or database-render behavior changes are part of this audit.
