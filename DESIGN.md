# Hardset design system

Source of truth for every visual decision in the app. The implementation lives in
`Packages/HardsetKit/Sources/HardsetUI/`: `DesignTokens.swift`, `Components.swift`,
`Machined.swift`, `KnurlPattern.swift`, `TypeRole.swift` and `Haptic.swift`; this file explains
the choices, and `Tools/check_contrast.py` verifies the palette numbers below against the
Swift source so the two cannot drift.

## Point of view

Hardset is a calibrated instrument for the gym floor. The product's claim is calibrated honesty,
so the interface behaves like a measuring device rather than a lifestyle app.

The visual idea is calibrated iron. Competition plates are colour-coded by mass, and the colours
are a calibration standard, not decoration: red 25 kg, blue 20 kg, yellow 15 kg, green 10 kg,
white 5 kg. So the app's colour is the colour of calibrated plates, its surfaces are the materials
of a serious gym (machined steel, black rubber, chalk), and its typography is the stamped figure
on a plate. The semantic colours (logged green, record gold, caveat amber, failure red, action
blue) are not arbitrary; they carry a story the lifter already knows.

- **Colour is evidence, never decoration.** Hue appears only when it says something, and it is a
  plate colour: an action you can take (plate blue), a set that is saved (plate green), a record
  (plate yellow), a caveat (warning orange), a failure (plate red). Everything else is steel and
  chalk.
- **Numbers are the hero.** Weights, reps and rest are set in SF Pro Condensed with tabular
  figures: large, narrow and steady, like stamped plates or a scale readout. Condensed figures fit
  pound values such as `132.28` at full size, so nothing shrinks to fit.
- **Every control looks like a control.** Tappable things have a fill or a 3:1 border; static text
  never imitates a button. A lifter with an elevated heart rate should not have to guess.
- **Restraint everywhere except the log tap.** The one memorable moment is logging a set: the
  check stamps in with a short spring and a success haptic, and the row settles into its logged
  state. Nothing else moves without being asked.

## Palette

Normal appearance values. All text roles are at least 7:1 against `canvas`, `steel` and
`steelRaised` in both appearances; `controlEdge` is at least 3:1 against all three and against
`steelPressed`, because a pressed face keeps it. Dark is the
primary appearance; light is derived from the same roles and held to the same floor.

| Token | Dark | Light | Role |
| --- | --- | --- | --- |
| `canvas` | `#0C0D10` | `#F6F6F8` | Screen canvas: rubber-matting black, chalk white |
| `steel` | `#17181D` | `#FFFFFF` | Cards, rows, sheets' content |
| `steelRaised` | `#22242B` | `#EEEEF2` | Fields, keys, chips, secondary buttons |
| `steelPressed` | `#1B1C22` | `#E6E6EB` | Momentary pressed fill, darker than `steelRaised` so a press sinks |
| `edgeLight` | `#30333C` | `#FCFCFD` | Lit top edge of a raised face; decorative, never a boundary |
| `edgeShadow` | `#111216` | `#DBDBDF` | Shaded bottom edge of a raised face; decorative |
| `hairline` | `#2E3039` | `#DEDEE4` | Decorative hairline grouping only |
| `controlEdge` | `#7B7E8C` | `#7E8190` | Boundaries that identify a control |
| `chalk` | `#F3F3F5` | `#141519` | Chalk / graphite body text and values |
| `chalkDim` | `#B6B8C3` | `#4B4D58` | Supporting text, units, provenance |
| `plateBlue` | `#6FB7FF` | `#084A95` | The 20 kg plate: actions, focus, selection, next up |
| `plateBlueFill` | `#6FB7FF` | `#084A95` | Primary button fill |
| `plateBlueFillPressed` | `#5AA6F0` | `#063C7A` | Primary button pressed |
| `onPlateBlue` | `#0C0D10` | `#FFFFFF` | Text on `plateBlueFill` |
| `plateBlueSurface` | `#10233A` | `#E3EFFC` | Selected / focused tint |
| `plateGreen` | `#8FE3A3` | `#0F5A27` | The 10 kg plate: logged, high certainty |
| `plateGreenSurface` | `#122A1A` | `#E5F5EA` | Logged row tint |
| `plateYellow` | `#FFD86B` | `#604A00` | The 15 kg plate: records, moderate certainty |
| `plateYellowSurface` | `#2B2410` | `#FBF3DA` | Record banner |
| `plateRed` | `#FF9A9A` | `#9A1B24` | The 25 kg plate: failed writes |
| `plateRedSurface` | `#2E1516` | `#FBEAEA` | Error banner |
| `warning` | `#FFB27A` | `#7A3A00` | Caveats, low certainty; not a plate, the colour of a flagged lift |
| `warningSurface` | `#2C1D12` | `#FCEEE3` | Caveat banner |

Edges: `edgeLight` and `edgeShadow` are opaque values, pre-blended over `steelRaised` (`edgeLight`
is 60% `#3A3D47` in dark and 80% white in light; `edgeShadow` is 50% black in dark and 8% black in
light). They stay opaque so an edge is the same colour wherever a face is drawn; do not turn them
into alphas.

The earlier names (`background`, `surface`, `surfaceRaised`, `surfacePressed`, `border`,
`controlBorder`, `textPrimary`, `textSecondary`, `accent`, `accentFill`, `accentFillPressed`,
`onAccent`, `accentSurface`, `success`, `successSurface`, `pr`, `prSurface`, `error`,
`errorSurface`) remain as aliases of the tokens above during the rebuild and are deleted in its
final phase.

Increased Contrast swaps `canvas`, `steel` and `steelRaised` to pure white (light) or black (dark)
and `chalk` to pure black or white. It strengthens `steelPressed` (`#E6E6EA` / `#26262B`),
`hairline` and `controlEdge` (both `#595964` / `#9B9BA5`), `chalkDim` (`#3B3D47` / `#DADCE4`),
`plateBlue` and `plateBlueFill` (`#063A75` / `#9FD0FF`), `plateBlueFillPressed` (`#052E5E` /
`#86C2FF`), `onPlateBlue` (white / black) and `plateBlueSurface` (`#D6E8FA` / `#0A1A2C`). The
edges, the green, yellow and red plates, `warning` and their surfaces keep their normal values:
they already clear the floor. Resolution happens live from the trait collection, in code, with no
asset catalogue.

Certainty maps high → `plateGreen`, moderate → `plateYellow`, low → `warning`, unevaluated →
`chalkDim`, always with its word and symbol so colour is never the only carrier.

Chart series (one line per machine, never merged) use `plateBlue`, chalk `#E7E7EC`/`#3A3A42`,
lilac `#B9A8FF`/`#5236B8` and rose `#FF9DD6`/`#9A1F66`, each paired with a distinct point symbol.

## Typography

System fonts only, so no resource bundle is needed. Every role is a Dynamic Type text style.

| Token | Style | Use |
| --- | --- | --- |
| `display` | Large Title, semibold, condensed | Tab screen headers |
| `title` | Title 3, semibold | Sheet headers, hero card titles |
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

Tracking is a ratio of the resolved size, so it follows Dynamic Type: `hero` and `display` -2%,
`readout` -1%, `caption` and `unit` +1%, every other role 0. `hardsetText(_:)` applies a role's
font and tracking together from `Tokens.Text.Role`; the static fonts carry no tracking.

## Spacing, radius, stroke

- Spacing: `hairline 2`, `tight 4`, `snug 8`, `regular 12`, `loose 16`, `section 24`, `block 32`.
  Page margin is `loose` (16).
- Radius: `control 10` for fields, keys, buttons and rows; `card 16` for cards and sheets.
  Capsules are reserved for chips and badges.
- Stroke: `hairline 1` for borders, `selected 2` for selection and focus rings.
- Targets: 44 pt general minimum, 56 pt in the logger (set rows, keypad, rest controls).

## Motion

| Token | Value | Use |
| --- | --- | --- |
| `Motion.press` | 120 ms ease-out | Button and key press feedback |
| `Motion.state` | spring, response 0.30, damping 1.0 | Selection, segment indicator, row state |
| `Motion.reveal` | 280 ms ease-out | Banners and inline confirmations appearing |
| `Motion.stamp` | 300 ms spring, bounce 0.3 | The log check, and nothing else |
| `Motion.fling(initialVelocity:)` | spring, response 0.35, damping 0.80 | Gesture release only, carrying the gesture's velocity |
| `zoom` (no Swift symbol; `navigationTransition(.zoom)` at the call site) | system zoom transition | A card growing into its screen and back |

`state` is critically damped, so it settles without overshoot and carries velocity into a
reversed target. `zoom` is the system's `navigationTransition(.zoom)` and has no animation value
of its own, because the system owns its timing, interruption and Reduce Motion behaviour.

Pressed controls scale to 0.97 and swap to their pressed fill. With Reduce Motion on, scale and
spring are dropped and only the fill or opacity changes, instantly or with `Motion.state`. Only
`transform` and `opacity` style properties animate; layout never does.

In practice: a message or inline confirmation arrives with an insertion-only opacity transition
carrying `Motion.reveal`, and no animated transaction, so what it displaces moves at once and it
leaves at once. A logged row's tint is a layer whose opacity fades on `Motion.state`; the row's
height is never animated.

Haptics follow the same restraint, and each has a name in `Tokens.Haptic`: `clank`, `success`,
`error`, `selection` and `warning`. `clank` is a heavy, full-strength impact for a weighty physical
moment; it is the heavy system impact until the welcome bar introduces CoreHaptics. `success`
belongs to the log tap alone. `error` follows every failed command, a repeated failure included.
`selection` answers the row's machine step and the rest bar's −15, +15, pause and skip. `warning`
marks a rest that ran out on its own when no alarm can mark it (alarms denied or unavailable).
Selection rows, the unit switch and pickers stay silent.

## Components and states

- **Buttons** (`HardsetButtonStyle`): `primary` (plate blue fill), `secondary` (raised steel),
  `quiet` (plate blue text, no fill), `destructive` (red text on the error surface). Sizes `logger`
  (56 pt) and `regular` (44 pt). States: default, pressed, disabled (40% opacity), focused (system
  focus ring). The look is machined: a secondary button is raised steel with the control edge at
  its boundary and, one hairline inside it, a light top edge and a shadowed bottom edge. Pressed,
  it keeps the control edge, so the 3:1 boundary never disappears, loses the edge light, and sinks
  to `steelPressed`, which in dark is darker than `steelRaised`. Primary is a solid plate blue
  fill, swapping to its pressed fill, with no edge gradient: the edge colours are pre-blended for
  steel and read wrong on plate blue.
- **Keys** (`HardsetKeyStyle`): the same machined face as a secondary button: raised steel with the
  control edge and the edge light inside it, and pressed, the control edge kept, the edge light
  dropped and the darker pressed fill, plus a 0.96 scale.
- **Knurl** (`KnurlPattern`, `.knurl(opacity:)`): a `Canvas` crosshatch for a control's face or a
  hero figure's backing, never behind text. It fills rectangular bounds, so callers with rounded
  shapes clip it themselves.
- **Cards** (`hardsetCard`): `steel` fill, decorative `hairline` border; selected uses a 2 pt
  `plateBlue` ring and `plateBlueSurface` fill.
- **Chips** (`HardsetChip`): capsule, raised fill; selected uses `plateBlueFill` with `onPlateBlue`
  text.
- **Segmented control** (`HardsetSegmentedControl`): replaces the system segmented picker; the
  selection indicator slides with `Motion.state`.
- **Screen header** (`ScreenHeader`): display title, one context line, optional trailing action.
- **Banner** (`HardsetBanner`): record, caveat, and error messages on their tinted surfaces.
- **Ledger** (`StatLedger`): a row of labelled figures separated by hairlines, used for session
  totals.
- **Empty and loading states**: explain what is missing and what to do next; loading is a quiet line
  of text, not a spinner. An empty slot is drawn with a dashed outline, the app's one mark for
  "nothing here yet": the empty-state socket, the "Add movement" slot, a warm-up's ordinal, an
  incomplete set's log control, and the rule under "Not evaluated".
- **Tags versus chips**: a chip can be tapped and wears the control border; a tag (modality,
  "Recent", "Custom", an untrained muscle) is filled only, so it never imitates a control.
- **Selection** (`SelectionRow`, `SelectionCardButtonStyle`, `SelectionIndicator`): selected choices
  take the plate blue ring and `plateBlueSurface`, and the trailing indicator swaps an empty ring
  for a filled check, so the choice is carried by shape as well as colour.
- **Text entry** (`entryFieldChrome`): raised fill, control border, and a 2 pt plate blue ring that
  fades in on focus. Used by the search field and the name entry sheet.
- **Set log control**: four states, never confused: incomplete (dashed, disabled), ready (plate blue
  outline), next up (plate blue fill), logged (the stamp). The first three are square key faces with
  a check; a logged set loses its key face and wears a round `plateGreen` seal
  (`checkmark.circle.fill`) on the row's `plateGreenSurface` tint, so logged and next up differ by
  shape, not only by hue. At accessibility sizes the control also reads "Log set" or "Logged", and
  VoiceOver hears "next to log" on the next-up row. Voice Control answers to "Set 2", "Log set 2",
  and, on the next-up row, "Log set".
- **Press feedback on self-drawn controls** (`HardsetPressStyle`, and the set row's fields and
  check): controls that draw their own fill and shape (chips, segments, the dashed "Add movement"
  slot, header circles, the machine and gym chips) sink to 0.97 and drop to 80–85% opacity on
  `Motion.press`, in place of a pressed fill. Reduce Motion keeps only the opacity. Disabled
  controls are never dimmed by it, so saved rows and inert titles keep full contrast.
- **Replaceable prefill**: when the keypad opens on a value the next key will replace, its display
  draws that value on `plateBlueSurface` with a hairline `plateBlue` ring, as selected text, until
  the first edit. Static; no motion.
- **Button Shapes**: with the system setting on, `quiet` buttons wear the `secondary` control border
  and the exercise name (the load-history link) is underlined.
- **Volume bars**: square-ended gauges scaled to the week's own maximum, never to a target. Modelled
  muscles are solid plate blue; muscles that are counted but not modelled are hollow (plate blue
  outline on `plateBlueSurface`) and say so in words beside the bar.
- **Charts**: one series per machine with its own colour and point symbol, a custom legend in app
  type, and machine changes as 2 pt dashed `warning` rules.

## Accessibility floor

7:1 text contrast, 3:1 control boundaries, Dynamic Type through every role, adaptive layouts in
place of shrinking text, one combined accessibility element per set row with named actions, and
Reduce Motion honoured in every animation. At accessibility sizes screen headers put their
action on its own line above the title, exercise headers put progress and menu below the name,
keypad quick steps form a two-by-two grid, segments and selection tags wrap, and header circles
stop growing at xxxLarge with the Large Content Viewer in their place. Accessible names begin with
the words a control shows (WCAG 2.5.3), so Voice Control users can say what they see. Native verification of resolved colours, hit regions,
and Dynamic Type layouts happens on the Mac; see `docs/MAC-VERIFICATION.md`.

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

- Root readiness: catalog, workout recovery and gym options must load successfully
  before a new workout is offered. Use `HardsetLoadingState` and the existing
  retry action on `HardsetEmptyState`; never present a recovery failure as an empty
  workout. Appearance callers share model-owned preparation, so one disappearing
  caller does not abandon recovery. Later appearances preserve live drafts and
  finished-state transitions instead of replaying an old snapshot.

## Handout feature additions

- Logger rows expose −/+ controls only when an explicit positive machine increment
  exists. They add/subtract canonical kilograms and convert only the label. Each
  button uses the existing56pt logger style and selection haptic. Blank loads stay
  blank, saved loads are read-only, and Reduce Motion uses the existing button style.
- Rest starts only from an explicit duration choice. Durable absolute-date state is
  separate from OS scheduling; a visible retry banner reports either persistence or
  scheduling failure. No countdown state is stored or animated by a custom loop.
- Settings adds file import/export, optional Apple Health and a StoreKit Lifetime
  section. Reuse existing spacing, typography, buttons and semantic error colours.
  Import previews state unknown equipment and unit/time-zone interpretation before
  saving. Busy operations disable their controls and expose native progress.
- History opens a static receipt of committed sets. It states equipment provenance,
  caveats and same-machine record definitions. Native share sheets handle text and a
  deliberately dark image; long sessions retain text sharing rather than render an
  unbounded image. It adds no animation and responds to Dynamic Type.
- The optional deep muscle map uses the existing palette and fractional-set method,
  with labelled values and comparative tracks, never target bands. It uses two
  columns at ordinary sizes and one at accessibility sizes. Unknown attribution
  keeps the lower-bound caveat; counted-only muscle tokens retain that disclosure.
  No new colour, radius, typography or motion token is introduced.
- The machine picker’s load-step editor uses the existing numeric pad and an explicit
  Save action. Blank means unknown. Changing a saved step preserves all current draft
  values; logger VoiceOver actions expose the same one-step adjustments as the buttons.
- Rest recovery failure appears above every tab and prevents new timer commands until
  recovery succeeds. It does not block the workout database, personal history or export.

- Saved logger facts retain full foreground contrast even though their actions are
  disabled. Confidence labels wrap at large Dynamic Type sizes instead of truncating
  the word that qualifies a claim. Neither change introduces motion or new tokens.
- The Lifetime section always offers an explicit restore action to a locked App Store
  build, including when storefront product information is unavailable. Restore uses
  the existing secondary button and busy state; product retry remains a separate action.
- Failed receipt corrections and gym/machine changes use native alerts, so the
  failure remains visible and accessible regardless of scroll position. A failed
  rename keeps the sheet and typed values available for retry. These reuse system
  presentation and add no custom motion.
