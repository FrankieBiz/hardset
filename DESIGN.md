# Hardset design system

Source of truth for every visual decision in the app. The implementation lives in
`Packages/HardsetKit/Sources/HardsetUI/DesignTokens.swift` and `Components.swift`; this file
explains the choices, and `Tools/check_contrast.py` verifies the palette numbers below against the
Swift source so the two cannot drift.

## Point of view

Hardset is a calibrated instrument for the gym floor. The product's claim is calibrated honesty,
so the interface behaves like a measuring device rather than a lifestyle app:

- **Colour is evidence, never decoration.** Hue appears only when it says something: an action
  you can take (readout cyan), a set that is saved (green), a caveat (amber/orange), a failure
  (red). Everything else is graphite and chalk.
- **Numbers are the hero.** Weights, reps and rest are set in SF Pro Condensed with tabular
  figures: large, narrow and steady, like stamped plates or a scale readout. Condensed figures fit
  pound values such as `132.28` at full size, so nothing shrinks to fit.
- **Every control looks like a control.** Tappable things have a fill or a 3:1 border; static text
  never imitates a button. A lifter with an elevated heart rate should not have to guess.
- **Restraint everywhere except the log tap.** The one memorable moment is logging a set: the
  check stamps in with a short spring and a success haptic, and the row settles into its logged
  state. Nothing else moves without being asked.

## Palette

Normal appearance values. All text roles are at least 7:1 against `background`, `surface` and
`surfaceRaised` in both appearances; `controlBorder` is at least 3:1 against all three.

| Token | Dark | Light | Role |
| --- | --- | --- | --- |
| `background` | `#0E0E10` | `#F9F9FA` | Screen canvas |
| `surface` | `#1C1C1F` | `#FFFFFF` | Cards, rows, sheets' content |
| `surfaceRaised` | `#28282D` | `#F1F1F4` | Fields, keys, chips, secondary buttons |
| `surfacePressed` | `#2E2E33` | `#EBEBEF` | Momentary pressed fill |
| `border` | `#323238` | `#E0E0E4` | Decorative hairline grouping only |
| `controlBorder` | `#777782` | `#80808A` | Boundaries that identify a control |
| `textPrimary` | `#F5F5F7` | `#151518` | Chalk / graphite body text and values |
| `textSecondary` | `#B9B9C2` | `#4D4D56` | Supporting text, units, provenance |
| `accent` | `#5ED3E6` | `#00515E` | Readout cyan: actions, focus, selection |
| `accentFill` | `#5ED3E6` | `#00515E` | Primary button fill |
| `accentFillPressed` | `#4ABFD3` | `#003D47` | Primary button pressed |
| `onAccent` | `#0E0E10` | `#FFFFFF` | Text on `accentFill` |
| `accentSurface` | `#10292E` | `#E2F4F7` | Selected / focused tint |
| `success` | `#8DE5A2` | `#155B28` | Logged, high certainty |
| `successSurface` | `#13281A` | `#E6F4EA` | Logged row tint |
| `pr` | `#FFD873` | `#5F4B00` | Records, moderate certainty |
| `prSurface` | `#2A2410` | `#FBF3DC` | Record banner |
| `warning` | `#FFB27A` | `#7A3A00` | Caveats, low certainty |
| `warningSurface` | `#2C1D12` | `#FCEEE3` | Caveat banner |
| `error` | `#FF9AA2` | `#981C29` | Failed writes |
| `errorSurface` | `#2E1517` | `#FBEAEB` | Error banner |

Increased Contrast swaps `background`/`surface` to pure black/white, `textPrimary` to pure
white/black, and strengthens `textSecondary` (`#DDDDE4` / `#3D3D44`), `accent` (`#9BE9F4` /
`#003A44`) and `controlBorder` (`#9B9BA5` / `#595964`). Resolution happens live from the trait
collection, in code, with no asset catalogue.

Certainty maps high → `success`, moderate → `pr`, low → `warning`, unevaluated →
`textSecondary`, always with its word and symbol so colour is never the only carrier.

Chart series (one line per machine, never merged) use `accent`, chalk `#E7E7EC`/`#3A3A42`,
lilac `#B9A8FF`/`#5236B8` and rose `#FF9DD6`/`#9A1F66`, each paired with a distinct point symbol.

## Typography

System fonts only, so no resource bundle is needed. Every role is a Dynamic Type text style.

| Token | Style | Use |
| --- | --- | --- |
| `display` | Large Title, bold, expanded | Tab screen headers |
| `title` | Title 3, semibold, expanded | Sheet headers, hero card titles |
| `headline` | Headline | Card and row titles, primary button labels |
| `label` | Body | Ordinary text and control labels |
| `labelEmphasis` | Body, semibold | Emphasised labels |
| `provenance` | Callout | Certainty, borrowed-history notes, corrections |
| `unit` | Callout, medium | Unit suffixes beside values |
| `caption` | Footnote | Supplemental notes only |
| `sectionHeader` | Subheadline, semibold | Sentence-case section labels; never all caps |
| `hero` | Large Title, semibold, condensed, tabular | Rest countdown, keypad display |
| `readout` | Title, semibold, condensed, tabular | Headline figures |
| `setEntry` | Title 2, semibold, condensed, tabular | Weight and reps in a set row |
| `figure` | Headline, condensed, tabular | Small figures inside ledgers and rows |

## Spacing, radius, stroke

- Spacing: `hairline 2`, `tight 4`, `snug 8`, `regular 12`, `loose 16`, `section 24`, `block 32`.
  Page margin is `loose` (16).
- Radius: `control 10` for fields, keys, buttons and rows; `card 16` for cards and sheets.
  Capsules are reserved for chips and badges.
- Stroke: `hairline 1` for borders, `selected 2` for selection and focus rings.
- Targets: 44 pt general minimum, 56 pt in the logger (set rows, keypad, rest controls).

## Motion

| Token | Duration | Curve | Use |
| --- | --- | --- | --- |
| `Motion.press` | 120 ms | ease-out | Button and key press feedback |
| `Motion.state` | 200 ms | ease-in-out | Selection, segment indicator, row state |
| `Motion.reveal` | 280 ms | ease-out | Banners and inline confirmations appearing |
| `Motion.stamp` | 300 ms spring, bounce 0.3 | spring | The log check, and nothing else |

Pressed controls scale to 0.97 and swap to their pressed fill. With Reduce Motion on, scale and
spring are dropped and only the fill or opacity changes, instantly or with `Motion.state`. Only
`transform` and `opacity` style properties animate; layout never does.

## Components and states

- **Buttons** (`HardsetButtonStyle`): `primary` (accent fill), `secondary` (raised fill, control
  border), `quiet` (accent text, no fill), `destructive` (error text on error surface). Sizes
  `logger` (56 pt) and `regular` (44 pt). States: default, pressed, disabled (40% opacity),
  focused (system focus ring).
- **Keys** (`HardsetKeyStyle`): raised fill, control border, pressed fill plus 0.96 scale.
- **Cards** (`hardsetCard`): surface fill, decorative border; selected uses a 2 pt accent ring
  and `accentSurface` fill.
- **Chips** (`HardsetChip`): capsule, raised fill; selected uses accent fill with `onAccent` text.
- **Segmented control** (`HardsetSegmentedControl`): replaces the system segmented picker; the
  selection indicator slides with `Motion.state`.
- **Screen header** (`ScreenHeader`): display title, one context line, optional trailing action.
- **Banner** (`HardsetBanner`): record, caveat, and error messages on their tinted surfaces.
- **Ledger** (`StatLedger`): a row of labelled figures separated by hairlines, used for session
  totals.
- **Empty and loading states**: explain what is missing and what to do next; loading is a quiet
  line of text, not a spinner. An empty slot is drawn with a dashed outline, the app's one mark
  for "nothing here yet": the empty-state socket, the "Add movement" slot, a warm-up's ordinal,
  an incomplete set's log control, and the rule under "Not evaluated".
- **Tags versus chips**: a chip can be tapped and wears the control border; a tag (modality,
  "Recent", "Custom", an untrained muscle) is filled only, so it never imitates a control.
- **Selection** (`SelectionRow`, `SelectionCardButtonStyle`, `SelectionIndicator`): selected
  choices take the accent ring and `accentSurface`, and the trailing indicator swaps an empty
  ring for a filled check, so the choice is carried by shape as well as colour.
- **Text entry** (`entryFieldChrome`): raised fill, control border, and a 2 pt accent ring that
  fades in on focus. Used by the search field and the name entry sheet.
- **Set log control**: four states, never confused: incomplete (dashed, disabled), ready
  (accent outline), next up (accent fill), logged (success fill, the stamp).
- **Volume bars**: square-ended gauges scaled to the week's own maximum, never to a target.
  Modelled muscles are solid accent; muscles that are counted but not modelled are hollow (accent
  outline on `accentSurface`) and say so in words beside the bar.
- **Charts**: one series per machine with its own colour and point symbol, a custom legend in app
  type, and machine changes as 2 pt dashed `warning` rules.

## Accessibility floor

7:1 text contrast, 3:1 control boundaries, Dynamic Type through every role, adaptive layouts in
place of shrinking text, one combined accessibility element per set row with named actions, and
Reduce Motion honoured in every animation. Native verification of resolved colours, hit regions,
and Dynamic Type layouts happens on the Mac; see `docs/MAC-VERIFICATION.md`.
||||||| 33d2b09

## Loading and startup

Behaviour first recorded alongside the snapshot loading work, drawn here with this system's
components rather than native spinners.

- Keep readable content on screen during a refresh. A screen's first read shows its header and a
  quiet loading line (`HardsetLoadingState`), never a spinner, and never an empty state before a
  read has succeeded. Only a successful read shows the empty or data components.
- Failures use the screen's honest retry message, in a scroll view so pull-to-refresh works.
  Cancellation is silent and never clears content, and only the latest requested snapshot may
  replace what is visible (`SnapshotLoader`).
- Startup: while the database opens and migrates and the sync engine is built, show the startup
  screen on the app canvas with a quiet line of status. Publish the workout interface only after
  the whole resource set succeeds. A failure uses `HardsetEmptyState` with an explicit retry
  action in `HardsetButtonStyle(.primary)`. A disappearing scene does not restart or cancel
  process-owned preparation.
- Neither adds motion or colour-only feedback, so Reduce Motion users see the same immediate
  state changes.
