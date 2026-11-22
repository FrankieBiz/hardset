# Sleek Apple redesign: Phase 0 spec

Date: 2026-11-20. Status: proposal for the owner's decision. No app source, snapshot or `DESIGN.md`
was changed to produce it.

Base: `origin/main` at `c2c061f`. Evidence: the `hardset-ios-ui` artifact of CI run 44730379130
(main, green): 355 layer-rendered PNGs in `snapshots/` and 54 real-app captures plus 8 audit reports
in `app-screens/`. The run on `FrankieBiz/hardset-plan2` was still in progress, so it is not used.
Nothing here was compiled: this machine is Linux. Every claim about how something looks or feels in
the hand is marked as needing a device pass.

Companion file: `docs/design/2026-11-20-sleek-apple-DESIGN.diff`, the proposed `DESIGN.md` change as a
patch. It is deliberately not applied, because `DESIGN.md` states the palette that
`Tools/check_contrast.py` is meant to keep true of the Swift source; applying it before the code moves
would make the document false. Phase 1 applies it with `git apply` in the same change as the tokens.

## 1. What this asks the owner to decide

The direction is: keep the semantics, replace the skin. Plate colours stay evidence, figures stay
condensed and tabular, certainty stays visible, the log stamp stays the only theatre. What goes is the
middle layer between flat content and the system's glass chrome: the machined metal.

Three decisions are the owner's, and each costs something real (section 11):

1. **The outline policy.** Today every control carries a measured 3:1 `controlEdge` stroke. This spec
   replaces that with an affordance rule: no stroke on labelled buttons, keys, chips, cards and header
   buttons; stroke kept on inputs that are empty or being typed into; every stroke restored under
   Increase Contrast and Button Shapes. That reverses a documented design decision (`Machined.swift`,
   `DESIGN.md`). It is not required by WCAG for text-labelled controls, but it is a house floor today.
2. **Condensed titles.** `display` (the "Workout", "Progress" screen titles) moves from condensed
   semibold to standard-width bold. It is the app's most visible typographic fingerprint. Figures stay
   condensed. One token decides it, so it can be reversed cheaply.
3. **Glass on the rest bar.** Recommended, but only behind a device pass, because translucent text
   cannot be certified by the contrast gate. The opaque fallback ships either way.

## 2. What the renders show

Read as a product designer, from the actual captures, not from the source.

| # | Observation | Evidence | Consequence |
| --- | --- | --- | --- |
| 1 | One live-session screen carries twelve stroked shapes: two header circles, the gym chip, the card, the card's menu circle, two value fields, Start rest, Add set, the Add movement slot, the workout summary card and Finish workout. | `app-screens/14-session-logged.png` | Outlines are the structure. This is what reads as an instrument panel rather than an iOS app. |
| 2 | Saved set values are drawn as outlined controls, but they are inert. The set row's read-only state "never reports a press", yet its face is the same raised, outlined key as an editable field. | `kit-setrow-fields-dark-contrast.png` (the "Read-only" sample); `SetRowFieldFace` | The logged row has the most outlines of any state, and it breaks the system's own rule that static text never imitates a button. |
| 3 | The keypad is seventeen outlined faces and one filled one (Next). | `app-screens/13-keypad-weight.png` | The grid is already the affordance; the strokes add weight, not information. |
| 4 | Five full-width actions have identical weight: Start rest, Add set, Finish workout, and on other screens New workout, Repeat last workout, Export CSV. Finish workout, done once a session, looks exactly like Start rest, done every set. | 14-session-logged, 30-light-start, 02-settings | The only filled control on the live screen is the next-up check. Everything else competes at one tier. |
| 5 | The chrome is already Apple's. The tab bar and the sheet "Done" are system Liquid Glass (the package targets iOS 26.1), and the tour callout already uses `glassEffect`. Beside them the content is machined metal. | All captures; `Package.swift` platforms; `CalloutCard.swift` | The clash that makes the app feel like two systems stacked is metal content inside glass chrome. |
| 6 | Light mode is the most outline-heavy appearance. A light `steelRaised` control sitting on `canvas` is 1.04:1, so on canvas only the stroke identifies it. | `30-light-start.png`, `31-light-volume.png`; contrast math in section 7 | The Apple look will differ most in light, and light is under-rendered: 69 light PNGs against 183 dark. |
| 7 | Increase Contrast collapses `canvas`, `steel` and `steelRaised` to one colour. The strokes are then the only structure. | `kit-setrow-fields-dark-contrast.png` | Strokes cannot be deleted globally. They have to become conditional. |
| 8 | The rest bar is a stroked panel holding a knurled tile holding the countdown, above four outlined buttons: two nested containers around one number. | `restbar-running-440.png` | The knurl tile is a container with no job except the texture. |
| 9 | A logged row is washed green end to end and also wears a green seal with a check. The wash and the seal both say "saved". The Beat mark then needs a 0.35 stroke because its own fill vanishes on the wash. | `14-session-logged.png`; `DESIGN.md` "Beat mark" | The wash is redundant with the seal and creates a second-order stroke. |
| 10 | The measured logger rhythm is tight and already at its limit: set-row pitch 67.5 pt, a three-set card 486 pt (measured from `live-session-real-dark.png` at 2x). An iPhone 17 (874 pt tall) leaves an estimated 650 pt of content between the header and the tab bar. | `live-session-real-dark.png` | Adding air to the logger costs sets per screen. Density is not where the gain is; nested containers are. |
| 11 | The Progress card puts the certainty capsule alone on its own bottom row, adding a row of about 30 pt whose left side is empty. The overlay-plus-hidden-spacer layout is deliberate (the badge must not nest in the card's button) but costs a line. | `kit-progressboard-dark.png` | A layout change is available without touching the honesty rule. |
| 12 | Every curated Library row repeats a "Curated" tag, and every row carries two stacked tags. | `kit-library-mixed-dark.png` | Repeated constant information is noise. The exception ("Custom") is the information. |
| 13 | The capsule strokes in the layer-rendered snapshots show clipped vertical ends. The real-app captures show clean capsules. The suite already has a `capsulesThroughImageRenderer` test to separate a drawing defect from a renderer artefact. | `kit-progressboard-dark.png` vs `14-session-logged.png`; `ScreenSnapshotTests` | Judge strokes from `app-screens/`, never from the kit renders. |

Not visible in any render, so worth stating: the real-app journey `AppScreensUITests` captures Start,
Settings, Volume, History, the session, keypad, pickers and onboarding, but not the Progress tab, not
the Library sheet, and the light pass is only Start, Volume, History and Settings. Progress and Library
exist only as layer-rendered kit snapshots with no system chrome. `18-volume-with-workout.png` is in
fact the workout receipt, not Volume.

## 3. The four highest-leverage changes

Verdict on the hypothesis (outlines-as-structure, density, outlined controls, hierarchy of type):

| Hypothesis | Verdict | What the renders say |
| --- | --- | --- |
| Outlines as structure | Confirmed, the biggest lever | Observations 1, 2, 3, 6. |
| Outlined controls | Confirmed, but it is the same problem | A control is outlined because the system forbids identifying it by anything weaker. Fixing the policy fixes both. |
| Density | Corrected | Do not add air to the logger. Remove nested containers instead (observations 8, 10). Air is right on Progress, Library and Settings. |
| Hierarchy of type | Demoted | The live screen's type hierarchy is already legible. What reads un-Apple is condensed words and the extra tracking, not the number of roles. |
| (not in the hypothesis) | Added: state styling | Observations 2 and 9 are specific to the hero screen and large. |

The four, in the order to do them:

1. **Replace the stroke-everywhere rule with an affordance rule.** Surfaces separate by fill step;
   strokes appear only on inputs that are empty or being edited, and everywhere under Increase Contrast
   or Button Shapes. Effect on the live screen: twelve stroked shapes become the Add movement dashed
   slot and the unlogged value fields. Sections 5.1 and 4.
2. **Make the set row state-aware: a container means "you can change this".** Unlogged fields keep a
   filled, outlined face; a logged row loses its green wash and its field faces and shows plain values
   beside the seal; frames never change, so nothing reflows when a set is logged. Section 5.3.
3. **Widen the surface steps and move to continuous, concentric corners.** Dark canvas to steel goes
   from 1.10 to 1.18 and steel to raised stays 1.14, so cards can lose their hairline. Card radius 16
   to 24 and control radius 10 to 12, both continuous, so inner radius equals outer radius minus the
   12 pt card padding. Sections 4.1 and 4.4.
4. **Retire the machined skin and thin the action tiers.** No edge-light gradient, no knurl tile behind
   the countdown, no press that "sinks with an edge". One filled primary per state, neutral fill for
   secondary, plain text for tertiary. Section 5.2.

Type is deliberately fifth and small: `display` moves off condensed, one role is retired, and the rest
is usage rules (section 4.2).

## 4. Token table

Status: **kept**, **changed**, **new** or **retired**. Values are normal appearance; Increase
Contrast values are unchanged except where stated. Hex is sRGB.

### 4.1 Colour

| Token | Dark | Light | Status | Reasoning |
| --- | --- | --- | --- | --- |
| `canvas` | `#0C0D10` to `#050608` | `#F6F6F8` to `#F2F2F7` | changed | Widens canvas to steel so a card needs no stroke. Light value is Apple's grouped background. |
| `steel` | `#17181D` to `#1A1B21` | `#FFFFFF` | changed (dark) | Dark canvas to steel 1.10 to 1.18; light 1.08 to 1.12. |
| `steelRaised` | `#22242B` to `#24262D` | `#EEEEF2` | changed (dark) | Keeps 1.14 against the new steel. Brighter is not available: `plateBlue` text on it is 7.12:1 at `#24262D` and 7.02:1 at `#25272E`, against a 7:1 floor. |
| `steelPressed` | `#1B1C22` | `#E6E6EB` | kept | Still darker than `steelRaised`, still clears 4.5:1 for chalk and keeps `controlEdge` at 3:1. |
| `controlFillOnCanvas` | `#24262D` | `#FFFFFF` | new | Fill of a control that sits directly on `canvas`: header buttons, Train and Settings buttons. Light `steelRaised` on canvas is 1.04:1; `steel` on canvas is 1.12:1. Dark equals `steelRaised`. |
| `edgeLight` | `#30333C` | `#FCFCFD` | retired | The lit top edge of the machined face. Eight uses. The staged phone's rim moves to `hairline`. |
| `edgeShadow` | `#111216` | `#DBDBDF` | retired | The shaded bottom edge. Five uses. |
| `hairline` | `#2E3039` | `#DEDEE4` | kept | Decorative separators inside a card or grouped rows, and the Increase Contrast outline. Still 107 uses. |
| `controlEdge` | `#7B7E8C` | `#7E8190` | kept, role narrowed | Values untouched and still gated at 3:1 on every surface. Drawn only per section 5.1. |
| `chalk` | `#F3F3F5` | `#141519` | kept | Gate floor met with margin (section 7). |
| `chalkDim` | `#B6B8C3` | `#4B4D58` | kept | 7.65:1 on the new dark raised, 7.25:1 on light raised. Cannot get quieter: see section 11. |
| `plateBlue`, `plateBlueFill`, `plateBlueFillPressed`, `onPlateBlue`, `plateBlueSurface` | unchanged | unchanged | kept | Action colour. `plateBlueSurface` also becomes the tinted face of the quiet chip. |
| `plateGreen` | `#8FE3A3` | `#0F5A27` | kept | Saved, high certainty. |
| `plateGreenSurface` | `#122A1A` | `#E5F5EA` | kept, role changed | No longer a full-row wash. Used by the seal's inner disc, win marks and the high-certainty capsule. |
| `plateYellow`, `plateYellowSurface` | unchanged | unchanged | kept | Records, moderate certainty. |
| `plateRed`, `plateRedSurface` | unchanged | unchanged | kept | Failure. |
| `warning`, `warningSurface` | unchanged | unchanged | kept | Caveats, low certainty. |
| `series` (chart) | unchanged | unchanged | kept | Each paired with its own symbol. |
| Increase Contrast values | unchanged | unchanged | kept | The steps collapse to pure black or white there by design; strokes come back (section 5.1). |

No hue is added. No gradient is added; the one existing gradient (the machined edge) is removed.

### 4.2 Typography

System fonts only, every role a Dynamic Type style. Sizes are at the default Large setting.

| Token | Now | Proposed | Status | Reasoning |
| --- | --- | --- | --- | --- |
| `display` | Large Title 34, semibold, condensed, tracking -2% | Large Title 34, bold, standard width, tracking 0 | changed | Words in a condensed face with extra negative tracking are the least Apple thing on screen. The system font applies its own optical tracking and size, so no custom value is needed. Owner decision D2. |
| `title` | Title 3 20, semibold | unchanged | kept | |
| `headline` | Headline 17, semibold | unchanged | kept | Absorbs `labelEmphasis`. |
| `label` | Body 17 | unchanged | kept | |
| `labelEmphasis` | Body 17, semibold | use `headline` | retired | Identical in size and weight to `headline`. Ten uses move. |
| `provenance` | Callout 16 | unchanged | kept | Caveats are read at arm's length; not shrunk. |
| `unit` | Callout 16, medium, +1% | unchanged | kept | |
| `caption` | Footnote 13, +1% | unchanged | kept | 102 uses, the most used role. Structural headers (the "Set, Last time, kg, Reps" columns) are the usage to review. |
| `sectionHeader` | Subheadline 15, semibold | unchanged | kept | |
| `hero` | Large Title 34, semibold, condensed, tabular, -2% | unchanged | kept | Number. |
| `readout` | Title 28, semibold, condensed, tabular, -1% | unchanged | kept | Number. Usage rule below. |
| `setEntry` | Title 2 22, semibold, condensed, tabular | unchanged | kept | The set row's figure. |
| `figure` | Headline 17, semibold, condensed, tabular | unchanged | kept | |

Usage rules, the real hierarchy change:

- Condensed is for figures only. A sentence that happens to hold figures ("Beat last time on 5 of 7",
  the scorecard headline, currently `readout`) moves to `title` with `monospacedDigit()`.
- A value must not change width while typed: `hero`, `readout`, `setEntry`, `figure` stay tabular and
  condensed. No role that carries a typed or ticking figure is touched.
- Roles go from 13 to 12. The ladder 17, 16, 15, 13 is kept because the 1 pt steps are the caveat
  sizes, not decoration.

### 4.3 Spacing

| Token | Now | Status | Reasoning |
| --- | --- | --- | --- |
| `hairline 2`, `tight 4`, `snug 8`, `regular 12`, `loose 16`, `section 24`, `block 32` | same | kept | The scale is fine. |
| Page margin | `loose` 16 | kept | |
| Gap between cards, logger | `regular` 12 | kept | Density budget (section 11). |
| Gap between cards, Progress, Library, Settings | `regular` 12 | changed to `loose` 16 | These screens have room and no per-set cost. |
| Card content padding | 12 to 16 mixed | rule | 12 when the card holds rows of controls (concentric with a 24 card and 12 controls), 16 when it holds prose. |

### 4.4 Radius and shape

| Token | Now | Proposed | Status | Reasoning |
| --- | --- | --- | --- | --- |
| `Radius.card` | 16, circular | 24, continuous | changed | 32 uses. All 93 `cornerRadius:` sites draw a default circular `RoundedRectangle`; continuous is a real change at every one. |
| `Radius.control` | 10, circular | 12, continuous | changed | 49 uses. Concentric: a 24 card with 12 padding wants a 12 inner radius, where 16 and 10 never met. |
| Capsules, circles | as is | unchanged | kept | Chips, tags, badges, the seal. |
| Bars (Volume gauges) | square ends | 4 continuous | changed | Skin only; the scale and the hollow "counted, not modelled" bar are unchanged. |
| Sheet corner | `presentationCornerRadius(card)` | remove the override | retired | Let the system own the sheet's device-concentric radius. |

Implementation note: add one helper (a `Tokens.Shape` pair returning the continuous rounded rectangle)
so the radius change is one seam rather than 93 edits.

### 4.5 Stroke

| Token | Status | Reasoning |
| --- | --- | --- |
| `Stroke.hairline 1` | kept | Separators, the conditional outline. |
| `Stroke.selected 2` | kept | Selection and focus ring, the editing field, the ready log key. These are state, not structure. |

### 4.6 Materials and elevation

| Token | Status | Reasoning |
| --- | --- | --- |
| System glass on the tab bar, sheet toolbars, tour callout | kept | Already Apple's, already in place. |
| `Material.chrome` (glass for pinned, text-bearing chrome) | new, gated | Rest bar only, behind a device pass. Opaque fallback below. Never `.interactive()`. |
| Glass on content (rows, cards, figures) | refused | Section 10. |
| `Elevation.floating` | new | A soft shadow for a pinned opaque surface, light appearance only (about y 2, blur 12, 12% black); dark relies on the 1.34 step to canvas. Values to be tuned on device. |

Rest bar fallback, shipped regardless: panel `steelRaised` at card radius, no stroke, `Elevation.floating`,
countdown drawn directly in `chalk` (no knurl tile), controls as 56 pt label-identified buttons.

### 4.7 Motion and haptics

| Token | Status | Reasoning |
| --- | --- | --- |
| `Motion.press` 120 ms ease-out | kept | Fill swap and 0.97 scale (0.96 keys). No edge-light drop, because the edge light is retired. |
| `Motion.state` spring 0.30, damping 1.0 | kept | Also carries the logged row's field faces fading out. |
| `Motion.reveal` 280 ms ease-out | kept | |
| `Motion.stamp` | kept | The log check. Untouched. |
| `Motion.fling` | kept | |
| `zoom` | kept | System. |
| Haptics (`clank`, `success`, `error`, `selection`, `warning`) | kept | |

No new motion token. Nothing in this redesign adds a movement.

## 5. Component rules behind the tokens

### 5.1 The affordance rule (replaces "every control has a 3:1 border")

A control is identified by at least one of: a fill at 3:1 or better against its container (the primary
blue, about 8:1); a verb label or standard glyph; a 3:1 outline. The stroke is drawn only when:

- the control is an input that is empty or being typed into (the unlogged set-row value fields, text
  entry, the keypad display), or
- Increase Contrast is on (`colorSchemeContrast == .high`), or Button Shapes is on
  (`accessibilityShowButtonShapes`, already read by `quiet` buttons), in which case every control wears
  `controlEdge` as today.

Everything else is fill and label. `controlEdge` keeps its values and its gate. Saved values, tags,
banners, cards and the capsule outlines already classed as decorative never get a stroke.

### 5.2 Action tiers

| Tier | Face | Used for |
| --- | --- | --- |
| Primary | `plateBlueFill`, `onPlateBlue` label | The next-up log check, Start (Train), Save in editors, Next on the keypad. One per state. |
| Secondary | `steelRaised` on a card or `controlFillOnCanvas` on canvas, `chalk` label, no stroke | Start rest, Add set, Finish workout, New workout, Export, Earlier and Later. |
| Tertiary | `plateBlue` text, no fill | Warm-up, "How sets are counted", Edit. |
| Chip, tinted | `plateBlueSurface` fill, `plateBlue` text, no stroke | The unset gym and machine chips ("Set gym", "Choose machine"), replacing the blue outlined capsule. |
| Destructive | `plateRed` on `plateRedSurface` | Unchanged. |

Sizes (56 pt logger, 44 pt regular) are unchanged. Pressed: fill swaps to `steelPressed`, scale 0.97,
Reduce Motion drops the scale and keeps the swap.

### 5.3 The set row

| State | Face | Change |
| --- | --- | --- |
| Incomplete | dashed log key, empty fields | Unchanged. Dashed is the app's mark for "nothing here yet". |
| Unlogged, ready | filled, outlined value fields; plate blue outlined log key | Radius 12 continuous; edge-light gradient removed. The outline stays (decision D1b below). |
| Editing | `plateBlueSurface` with 2 pt `plateBlue` ring | Unchanged. |
| Next up | plate blue filled log key | Unchanged. |
| Logged | plain `setEntry` values on the card, the green seal, no field faces, no wash | The wash is removed. Frames are identical to the unlogged row, so nothing reflows; the field faces fade on `Motion.state`, with Reduce Motion an instant swap. |

The ordinal tile becomes a plain numeral in a fixed-width column (same alignment, one fewer container);
the warm-up's dashed "W" stays. The Beat mark loses its 0.35 stroke, because its fill no longer
vanishes on a tint. VoiceOver, Voice Control, named actions and the combined row element are untouched:
this is a styling change only.

Decision D1b: whether to also drop the outline on unlogged value fields is left for a device pass. This
spec keeps it. Dropping it would take the live screen to a single stroked object but makes the most
important tap target a filled rectangle at roughly 1.15:1.

### 5.4 The keypad

Keys sit on `steel` inside the sheet, so they take `steelRaised` (1.14 dark, 1.16 light). Keys lose the
stroke and the edge light and keep the pressed sink and the 0.96 scale. Done is secondary; Next is
primary; the four quick steps keep `plateBlue` labels. This reverses the note in `HardsetKeyStyle`
("a key identified only by a fill one shade off the pad is a key the lifter has to look for"), so it is
its own migration step with its own device check, and it can be reverted alone.

### 5.5 The rest bar

The one genuinely open design question. A pinned bar scrolls over cards that are themselves `steel`, and
with fill steps near 1.14 it cannot be separated from them by fill alone once its stroke is gone. Two
answers:

- Recommended: `Material.chrome`, a glass panel with an opaque-tinted scrim, countdown in `chalk`,
  controls label-identified. Worst-case contrast with the scrim is computed in section 7, but the tint
  maths for glass is an assumption about system compositing and must be verified on a device. Reduce
  Transparency falls back to the opaque panel.
- Fallback: opaque `steelRaised` with `Elevation.floating`. Ships if the device pass fails.

The countdown remains the system-rendered `Text(timerInterval:)`; no timer logic is in scope.

### 5.6 Badges, tags, banners, selection

- `CertaintyCapsule` (non-interactive) and the interactive `CertaintyBadge`: fill, symbol and word stay;
  the 0.35 outline goes; Button Shapes and Increase Contrast restore an outline on the interactive one.
  Each estimated metric keeps its badge. None is merged or dropped for density.
- `HardsetBanner`: tinted fill, symbol and word stay; the 0.35 stroke goes.
- Selection (`SelectionRow`, selection cards, the chip): the 2 pt `plateBlue` ring and the filled check
  stay, because selection is state.
- Tags: unchanged.
- Library: the "Curated" tag is dropped from the visual row and the exception ("Custom") is kept. The
  accessibility label still says "Curated". Needs owner confirmation because it changes what is drawn,
  not only how.

### 5.7 Light mode

Light is a first-class target and is where this change is most visible. The rule is the same; the
numbers differ: canvas to steel 1.12, `steelRaised` on canvas 1.04 (hence `controlFillOnCanvas`), white
keys on gray as Apple draws them. Every phase adds light renders before it changes light pixels.

## 6. Migration order and risk

Implementation does not start until PR #6 (`hardset-plan2`) is merged: it edits `LiveSessionScreen`,
`WeeklyVolumeScreen`, `OnboardingFlow`, `ScaledPhoneFrame`, `LibraryScreen` and `WorkoutEditorScreen`,
which are exactly the screens below.

| Phase | Scope and files | Risk | Gate before merge |
| --- | --- | --- | --- |
| 1a | Prerequisites, test code only. Capture Progress, Library and a light-mode live session in `AppScreensUITests`. Add the layout budget and hit-region assertions (section 9). Pin a "before" set. | Low. Changes no UI. | Existing UI tests green; new captures present in the artifact. |
| 1b | Tokens and shared kit only. `DesignTokens.swift`, `Components.swift`, `Machined.swift` (retire), `PressStyle.swift`, `Messages.swift` (banner), `CertaintyBadge.swift`, `HardsetTag.swift`, `ChipsAndSegments.swift`, `SelectionRow.swift`, `KnurlPattern.swift` use, the catalog views, `Tools/check_contrast.py` (new pairs), `DESIGN.md` (apply the diff). | Highest blast radius: it moves the look of every screen at once. Mitigated by changing nothing in screens. | `make check`; contrast gate on the new swatches; kit renders reviewed pair by pair. |
| 2a | Train and live session, the hero. `SessionView.swift`, `ExerciseSectionView.swift`, `SetRowView.swift`, `WorkoutCardsView.swift`, `SetRowCatalogView.swift`. | Highest product risk: the log path. Hit regions must stay 56 pt; the row must not reflow on logging; accessibility labels and actions must be byte-identical. Collides with #6 if started early. | Layout budget test; hit-region test; accessibility audit count not above baseline; device pass on item 1. |
| 2b | Keypad. `NumericPad.swift`, `LoadStepSheet.swift`. | Reverses a documented decision. Gym glare and sweaty hands are not testable on a Simulator. | Device pass; independently revertible. |
| 2c | Rest bar. `RestBarView.swift`. | Glass cannot be certified by the contrast gate; Reduce Transparency path. Timer correctness is untouched. | Device pass; opaque fallback present. |
| 3a | Progress and Volume. `ProgressBoardView.swift`, `ProgressionChartView.swift`, `VolumeReportView.swift`, `MuscleHeatmapView.swift`. | The certainty badge overlay is laid out so it never nests inside the card's button; moving it inline touches that anchor. Chart colours and symbols must not change. | Badge visible on every estimated metric in every render; chart series unchanged. |
| 3b | Library, editors, pickers. `LibraryView.swift`, `MovementEditorSheet.swift`, `WorkoutEditorView.swift`, `ExercisePickerView.swift`, `MachinePickerView.swift`, `GymPickerView.swift`, `NameEntrySheet.swift`. | Many chips and tags; the "Curated" drop is a content decision. | Owner sign-off on D-Curated; text-invariance check. |
| 4 | Settings (`HardsetFeature/SettingsSheet.swift` and sections), History and receipt (`HistoryView.swift`, `WorkoutReceiptView.swift`), onboarding (`WelcomeBarView.swift`, `PlateTray.swift`, `PitchDemos.swift`), tour (`ScaledPhoneFrame.swift`, `CalloutCard.swift`, `SpotlightOverlay.swift`). Then the review of the whole artifact set. | Lowest per screen. The shared receipt image is "deliberately dark" and must not follow the appearance. The staged phone's rim loses `edgeLight`. | Screen-by-screen review of the full artifact set. |

## 7. Contrast and accessibility math

Method: the repository's own `Tools/check_contrast.py`, unmodified, was run against a copy of
`DesignTokens.swift` carrying only the proposed `canvas`, `steel` and `steelRaised` values. Current: all
184 pairs meet their floor across 23 swatches. Proposed: all 184 pairs meet their floor across 23
swatches. Ratios are WCAG relative luminance, computed from the same hex literals the app renders.

Text floor 7:1 (SC 1.4.6) against `canvas`, `steel`, `steelRaised`; boundary floor 3:1 (SC 1.4.11).

| Pair | Floor | Dark now to proposed | Light now to proposed |
| --- | --- | --- | --- |
| `chalk` on `steelRaised` | 7 | 13.98 to 13.63 | 15.77 to 15.77 |
| `chalkDim` on `canvas` | 7 | 9.84 to 10.26 | 7.78 to 7.52 |
| `chalkDim` on `steel` | 7 | 8.97 to 8.70 | 8.39 to 8.39 |
| `chalkDim` on `steelRaised` | 7 | 7.85 to 7.65 | 7.25 to 7.25 |
| `plateBlue` on `canvas` | 7 | 9.15 to 9.55 | 8.03 to 7.76 |
| `plateBlue` on `steelRaised` | 7 | 7.30 to 7.12 | 7.49 to 7.49 |
| `plateRed` on `steelRaised` | 7 | 7.63 to 7.44 | 7.10 to 7.10 |
| `plateGreen` on `steelRaised` | 7 | 10.10 to 9.84 | 7.22 to 7.22 |
| `plateYellow` on `steelRaised` | 7 | 11.28 to 11.00 | 7.33 to 7.33 |
| `warning` on `steelRaised` | 7 | 8.78 to 8.56 | 7.46 to 7.46 |
| `controlEdge` on `canvas` | 3 | 4.82 to 5.02 | 3.58 to 3.47 |
| `controlEdge` on `steel` | 3 | 4.39 to 4.26 | 3.87 to 3.87 |
| `controlEdge` on `steelRaised` | 3 | 3.84 to 3.74 | 3.34 to 3.34 |
| `controlEdge` on `steelPressed` | 3 | 4.21 to 4.21 | 3.11 to 3.11 |

The tightest proposed text pair is `plateBlue` on dark `steelRaised` at 7.12:1, a margin of 0.12 (it was
0.30). That is what stops the dark steps reaching Apple's 1.22: anything brighter breaks 7:1 for the
action colour. The lever, if the owner ever wants more separation, is a brighter `plateBlue`, which this
spec refuses to change.

Surface steps (not text; they replace strokes as structure):

| Step | Dark now to proposed | Light now to proposed | Apple grouped, for scale |
| --- | --- | --- | --- |
| `steel` on `canvas` | 1.10 to 1.18 | 1.08 to 1.12 | 1.23 dark, 1.12 light |
| `steelRaised` on `steel` | 1.14 to 1.14 | 1.16 to 1.16 | 1.22 dark |
| `steelRaised` on `canvas` | 1.25 to 1.34 | 1.07 to 1.04 | |
| `controlFillOnCanvas` on `canvas` | | 1.12 (white) | |
| pressed on raised | 1.10 to 1.12 | 1.07 to 1.07 | |

Changed pairs outside the gate:

| Pair | Result |
| --- | --- |
| Logged value text, `chalk` on `steel` (no longer on the green wash) | 15.50 dark, 18.24 light, against 13.81 and 16.14 on the wash |
| Seal glyph, `plateGreen` on `plateGreenSurface` (unchanged pair) | 9.98 dark, 7.40 light |
| Tinted chip, `plateBlue` on `plateBlueSurface` (unchanged pair) | 7.47 dark, 7.43 light |
| Secondary label, `chalk` on `steelRaised` | 13.63 dark, 15.77 light |
| `controlEdge` under Increase Contrast, `#9B9BA5` on black / `#595964` on white | 7.63 and 6.91 (both well over 3:1); `canvas`, `steel`, `steelRaised` are one colour there, so fill step is 1.00 |

Rest bar with a scrim, a worst-case chalk countdown. Model: the glass tint behaves as an alpha
composite of `steelRaised` over the backdrop. This is an assumption about the system, to be verified
on a device.

| Backdrop under the bar | Scrim 0.88 | Scrim 0.80 | Scrim 0.70 |
| --- | --- | --- | --- |
| Dark, `plateBlueFill` (a primary button scrolling under) | 10.85 | 9.10 | 7.28 |
| Dark, a white text pixel | 9.35 | 7.14 | 5.09 |
| Light, `plateBlueFill` `#084A95` | 12.96 | 11.33 | 9.50 |
| Light, black text pixel | 11.98 | 9.85 | 7.60 |

At 0.88 or above every case clears 7:1. Below 0.70 a white text pixel in dark does not. The proposal is
a scrim of 0.88 or more, with the opaque panel as the fallback.

Hit regions and targets: unchanged, 44 pt generally and 56 pt in the logger. A control that loses its
visible face (a logged value, a plain tertiary button) keeps its frame and `contentShape`, so the
region does not shrink. The implementation test in section 9 asserts it.

## 8. Dynamic Type, Reduce Motion, Increase Contrast, Button Shapes

**Dynamic Type.** No layout, frame or stacking rule changes. Specific checks:

- Card radius 24 continuous with 12 pt padding and a text-led card at 16: the first character of a
  wrapped line clears the corner at every size.
- `display` in standard width bold is wider than condensed. The longest titles (Progress, Workout,
  Library) must stay on one line at the largest ordinary size and may wrap onto the action-above-title
  layout at accessibility sizes, which already exists. Verify at the existing `ax3` renders.
- Set row stacking at accessibility sizes (`isStacked`) is unchanged; a logged row's plain values keep
  their frame.
- Retiring the ordinal tile changes nothing at accessibility sizes, where the ordinal sits in the header
  line.

**Reduce Motion.** Everything that moves already adapts, and this adds nothing that travels:

- Press: scale dropped, fill swap kept.
- Logged row: the field faces fade on `Motion.state`; with Reduce Motion the swap is instant. The row's
  height never animates.
- Glass: never `.interactive()`, so there is no touch shimmer. Reduce Transparency selects the opaque
  rest bar.
- The log stamp, spotlight and plate tray are untouched.

**Increase Contrast.** Resolution stays in the trait collection, in code. Strokes return on every control
(section 5.1), `controlEdge` takes its `#595964` / `#9B9BA5` values, and surfaces stay pure white or
black.

**Button Shapes.** The existing `accessibilityShowButtonShapes` read is generalised from `quiet` buttons
to every stroke-free control, so the system setting restores the outline exactly where the user asked.

**VoiceOver and Voice Control.** No label, hint, trait, named action or input label changes in any
phase. Dropping the visual "Curated" tag keeps it in the spoken label.

## 9. Snapshot and verification strategy

What exists, which changes the question:

- There are no committed pixel baselines. `HardsetUISnapshotTests` writes PNGs only when
  `HARDSET_SNAPSHOT_DIR` is set and "asserts nothing about pixels"; it "exists to be looked at". Nothing
  can be regenerated because nothing is compared.
- The artifact expires after 14 days.
- What does fail a build: compile errors, the UI-journey `XCTAssert`s, the portable and app tests, and
  the contrast gate in `make check`. The accessibility audit is recorded, not asserted ("Audit issues
  are recorded rather than failing the run").
- The failure mode is therefore not a stale baseline. It is accepting a whole new artifact set as the
  new normal, when a clipped label, a lost certainty badge or a 52 pt hit region would pass every
  automated check.

Strategy:

1. **Pin the before.** Tag `main` at `c2c061f` and keep run 44730379130's artifact reachable, or
   re-run the workflow on the tag with `workflow_dispatch` at review time, since artifacts expire.
2. **Add the missing coverage first (Phase 1a).** Real-app captures for the Progress tab, the Library
   sheet and a light-mode live session. Of the 355 snapshot PNGs, 183 are dark and 69 light; Increase
   Contrast is 41 dark and 1 light; large text (`ax3`) is 43 dark and 2 light. The appearance that
   changes most has the least coverage.
3. **Add assertions where there are none.** All three are test code, not product code:
   - a layout budget: the fitted height of a three-set `ExerciseSectionView` fixture at Large type may
     not exceed today's 486 pt by more than 8 pt, and set-row pitch may not exceed 68 pt;
   - a hit-region check: set-row fields, the log control and keypad keys stay at 56 pt, other controls
     at 44 pt, including a logged row's plain values;
   - a text invariance check: the set of accessibility labels in each fixture is identical before and
     after, which is what protects the certainty and honesty vocabulary from a styling change.
4. **Extend the contrast gate.** Add `controlFillOnCanvas`, the tinted chip pair, and the rest bar scrim
   worst cases. Add a stroke-policy check that fails on `controlEdge` or an outline used outside the
   allowed places in section 5.1.
5. **Use the audit counts as a no-regression baseline, per screen, by type.** From run 44730379130:
   workout 32 findings (13 "Contrast failed" and 3 "Element has no description" on the movement picker;
   the same report lists keyboard prediction cells, so these appear to be rows under the keyboard, and
   PR #6 has a commit that audits the picker with the keyboard down), onboarding 92 (46 "Contrast failed"
   and 43 "Text clipped" on tour step 2, plus a clipped welcome label and one small hit area on pitch 1),
   start and tabs 4, gym 2, corrections 0, light 0. A phase may lower these; none may raise a screen's
   count.
6. **Review by group, not wholesale.** Which renders move, by phase:

   | Moves in 1b | Moves in 2a to 4 | Must not move |
   | --- | --- | --- |
   | `tokens-*`, `kit-surfaces-*`, `kit-chips-*`, `kit-messages-*`, `kit-honesty-*` (skin only) | Screens in migration order | Every string, every certainty badge, every chart series, every frame size listed in the layout and hit-region tests |

   Compare dark and light of the same screen as a pair, and view strokes in `app-screens/`, not in kit
   renders (observation 13). Treat a kit render diff as expected, a text or frame diff as a bug.
7. **Do not regenerate or re-accept in bulk.** One reviewed phase at a time; the artifact for each phase
   is compared against the pinned before, not against the previous phase.

## 10. Refusal list

What this will not change, and why:

1. The plate colours' hex values and meanings (blue action, green saved, yellow record, amber caveat,
   red failure). Colour stays evidence. No new hue, no decorative gradient.
2. The certainty and honesty vocabulary: every badge, the word "Not evaluated", "unevaluated" rendering
   instead of guessing, borrowed-history notes, "No machine recorded". No badge is removed, merged or
   shrunk below `provenance` to save space.
3. Tabular and condensed figures on every number, and the no-width-change-while-typing rule.
4. The 7:1 text floor, even though Apple's own secondary label is far quieter. It is why secondary text
   cannot go lighter (section 11).
5. 44 pt targets, and 56 pt in the logger: set row, keypad, rest controls.
6. The log stamp, its spring and its haptics, and no new theatre: no confetti, no glass touch shimmer,
   no springy buttons, no new motion token.
7. Glass on content. Rows, cards and figures stay opaque. Glass is for pinned chrome only.
8. System symbols only. No custom iconography or illustration.
9. Navigation structure, the four tabs and every control's function. No feature changes.
10. Moving the logger or Settings onto system `List` and `Form`. It would change focus, accessibility
    and layout behaviour; a different project.
11. The dashed outline as the one mark for "nothing here yet".
12. Dropping the outline on unlogged set-row value fields in this pass (D1b). Deferred to a device pass.
13. A dark-only look. Both appearances get renders and gates in every phase.
14. Core, Store, the project file generator, `Hardset.xcodeproj` (never hand-edited), `HANDOFF.md`, and
    every snapshot bundle.
15. Brightening `plateBlue`. It is the lever for wider dark steps, and it would change the action
    colour.

## 11. Where "sleeker" costs the product something real

This section matters more than the agreement above.

1. **Discoverability of controls under glare.** The documented rule ("every control looks like a
   control, 3:1 border") was a considered answer to a lifter at an elevated heart rate in poor light.
   Fill steps of 1.12 to 1.18 are what Apple ships and they work indoors; they have not been tested on
   this app's floor. That is why strokes stay on empty inputs, return under Increase Contrast and Button
   Shapes, and why dropping the unlogged field outline (D1b) and the keypad strokes (2b) each need a
   device pass and each revert independently. Risk accepted by this spec: a user who has neither setting
   on sees fewer boundaries than today.
2. **The 7:1 floor and the dark steps.** Apple's dark steps are about 1.22. This app's text colours cap
   them near 1.14 to 1.18, so dark cards without a stroke separate less than stock iOS cards do, and
   secondary text can never be as quiet as iOS's secondary label. Hierarchy has to come from size and
   weight, not from dimmer text. This is the main reason a dark-mode result may feel flatter than the
   mock-up in anyone's head.
3. **Air versus sets per screen.** At 67.5 pt per set a three-set card is 486 pt, and a session of five
   movements is over three screens already. Every 4 pt added to a set row costs 12 pt per card. Sleeker
   usually means more air; the logger cannot afford it, so its rhythm is frozen and the gain comes from
   deleting containers. The sleeker result on Progress and Library will be larger than on the hero
   screen, which is the opposite of what an owner would expect.
4. **The logged-row wash is a scan cue.** Removing it leaves the seal to say "saved". At arm's length,
   down a card of eight rows, a column of seals may be a weaker cue than a green band. That is a device
   check, not a Simulator judgement.
5. **Glass cannot be certified.** The contrast gate works on opaque pairs. Text on glass is only as
   good as the model in section 7 and a device. If the pass fails, the rest bar ships opaque and pinned
   chrome keeps a different look from the system's own, which the owner may find unsatisfying.
6. **The point of view goes.** "Calibrated iron" is the machined stroke, the edge light and the knurl as
   much as the plate colours. After this change what remains is plate colour, condensed figures and
   honest language. That may be the right product, but it is a smaller visual idea, and an app that
   blends with Apple is by definition less recognisable at a glance. `DESIGN.md`'s "Point of view"
   section is rewritten in the diff for that reason, not only the tables.
7. **Condensed titles are the brand's fingerprint.** D2 trades them for system alignment. If the owner
   wants one remaining signature, this is the cheapest to keep and the least harmful.
8. **Light mode gets worse before it gets better.** Light surfaces are separated by 1.12 and a pale key
   on a pale canvas by less. Light is the appearance with the weakest coverage in the renders and the
   one where stroke removal is most visible.
9. **Review cost.** With no pixel baselines, every phase relies on human review of about 350 images and
   on assertions this spec adds. That is more process than "swap the tokens" suggests.

Open decisions for the owner, with this spec's recommendation:

| Id | Decision | Recommendation |
| --- | --- | --- |
| D1 | Affordance rule in place of the 3:1 stroke rule | Yes, with the Increase Contrast and Button Shapes restore. |
| D1b | Also drop the unlogged value-field outline | No for now; decide after a device pass. |
| D2 | `display` off condensed | Yes. Cheapest to reverse. |
| D3 | Glass rest bar | Yes behind a device pass; opaque fallback ships. |
| D4 | Drop the "Curated" tag from the visual Library row | Yes, and keep it in the spoken label. |
| D5 | Rounded gauge ends on Volume bars | Yes; skin only. |

## 12. What was not verified

- Nothing was built or run on a device. Native colour resolution, hit regions, Dynamic Type layout and
  glass behaviour are Mac and device checks (`docs/MAC-VERIFICATION.md`).
- The Plan 2 branch had no finished run, so its changes to the live session are not reflected.
- Progress and Library were read from kit renders (no system chrome), because the real-app journey does
  not capture them.
- The scrim model for glass in section 7 is an assumption about system compositing.
- "Feels right in the hand" is a device pass on the live session and cannot be judged from a PNG.

## Appendix A: Reproducing the numbers

1. Download the artifact: `gh run download 44730379130 -R github.com/FrankieBiz/hardset -D <empty dir>`.
2. Current gate: `python3 Tools/check_contrast.py`.
3. Proposed gate: copy `Packages/HardsetKit/Sources/HardsetUI/DesignTokens.swift` to a temporary path,
   set `canvas` to light `0xF2F2F7` / dark `0x050608`, `steel` dark to `0x1A1B21`, `steelRaised` dark to
   `0x24262D`, then `python3 Tools/check_contrast.py <that file>`. Result: all 184 pairs meet their
   floor.
4. Ratios in the tables are the standard WCAG relative-luminance ratio, `(L1 + 0.05) / (L2 + 0.05)`,
   using the same `linear` and `luminance` functions as `Tools/check_contrast.py`.
5. Layout figures (67.5 pt pitch, 486 pt card) are read from `snapshots/live-session-real-dark.png`
   (804 px wide, 2x): rows at 760, 895 and 1030 px, card from 415 to 1388 px.
6. Audit counts are `grep -c '^\['` on each `accessibility-audit-*.txt` in `app-screens/`.
