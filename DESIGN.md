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
`errorSurface`) were aliases of the tokens above while the screens were rebuilt, and are deleted:
every screen names the plate tokens, so a stray use of an old name no longer compiles.

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
| `setEntry` | Title 2, semibold, condensed, tabular | Weight and reps in a set row, and the values in a `StatLedger` |
| `figure` | Headline, condensed, tabular | Small figures inside rows and compact ledgers |

Tracking is a ratio of the resolved size, so it follows Dynamic Type: `hero` and `display` -2%,
`readout` -1%, `caption` and `unit` +1%, every other role 0. `hardsetText(_:)` applies a role's
font and tracking together from `Tokens.Text.Role`; the static fonts carry no tracking.
`hardsetText(_:weight:)` applies a weighted variant of a role with the same tracking, so a
semibold caption keeps its +1%; a static weighted font cannot carry tracking, and no modifier
chained after `hardsetText(_:)` is used to change its weight.

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
`error`, `selection` and `warning`. `clank` is the weighty tap of a plate meeting a bar: a CoreHaptics
pattern (a transient at intensity 1.0 and sharpness 0.6, then a 40 ms low rumble) played by
`ClankPlayer`, which falls back to the heavy system impact where CoreHaptics is unavailable, and
which `Tokens.Haptic.clank` names for a view that plays it through `.sensoryFeedback`. Saving a set
plays `clank` under `success` (the row plays both when it is marked logged, so a failed write plays
neither), and the Welcome bar's plate landing is the only other place `clank` is used. `error`
follows every failed command, a repeated failure included. `selection` answers the row's machine
step and the rest bar's −15, +15, pause, skip and next-rest choices. `warning`
marks a rest that ran out on its own when no alarm can mark it (alarms denied or unavailable).
Selection rows, the unit switch and pickers stay silent.

## Components and states

- **Buttons** (`HardsetButtonStyle`): `primary` (plate blue fill), `secondary` (raised steel),
  `quiet` (plate blue text, no fill), `destructive` (red text on the error surface, dimmed to 60%
  while pressed). Sizes `logger` (56 pt) and `regular` (44 pt). States: default, pressed, disabled
  (40% opacity), focused (system focus ring). The look is machined: a secondary button is raised
  steel with the control edge at its boundary and, one hairline inside it, a light top edge and a
  shadowed bottom edge. Pressed, it keeps the control edge, so the 3:1 boundary never disappears,
  loses the edge light, and sinks to `steelPressed`, which in dark is darker than `steelRaised`.
  Primary is a solid plate blue fill, swapping to its pressed fill, with no edge gradient: the edge
  colours are pre-blended for steel and read wrong on plate blue.
- **Keys** (`HardsetKeyStyle`): the same machined face as a secondary button: raised steel with the
  control edge and the edge light inside it, and pressed, the control edge kept, the edge light
  dropped and the darker pressed fill, plus a 0.96 scale.
- **Knurl** (`KnurlPattern`, `.knurl(opacity:)`): a `Canvas` crosshatch at 8% opacity, the
  `KnurlPattern` default. It fills rectangular bounds, so callers with rounded shapes clip it
  themselves. Phase 2 allows it in two places and nowhere else in the product UI (the token
  catalogue keeps one labelled knurl sample on a machined face, drawn with the overlay form): behind
  the rest bar's `hero` countdown, and as the logged-set seal's rim. In the product UI it is always
  a backing layer, `KnurlPattern` inside a `.background { }` clipped to the backing shape; the
  `.knurl(opacity:)` overlay is never used on text, the rest panel or the seal. The countdown is
  drawn in `chalk` in both running and paused states, because `chalk` is the only text colour on the
  knurl, and `Tools/check_contrast.py` gates that pair with the knurl blended in. The seal's
  `checkmark.circle.fill` glyph is never over knurl: the knurl fills only an annulus around an
  opaque `plateGreenSurface` inner disc that holds the glyph, because `plateGreen` on
  `plateGreenSurface` loses contrast with knurl under it. The welcome bar's use belongs to the
  onboarding phase.
- **Cards** (`hardsetCard`): `steel` fill, decorative `hairline` border; selected uses a 2 pt
  `plateBlue` ring and `plateBlueSurface` fill.
- **Chips** (`HardsetChip`): capsule, raised fill; selected uses `plateBlueFill` with `onPlateBlue`
  text.
- **Tags** (`HardsetTag`): the public name of the non-interactive label on a row (modality,
  "Recent", "Custom"). Flat `steelRaised`, no outline, no edge light. It stays on one line at
  ordinary sizes and wraps at accessibility sizes, never truncating the word it carries.
- **Segmented control** (`HardsetSegmentedControl`): replaces the system segmented picker; the
  selection indicator slides with `Motion.state`. The indicator is a `matchedGeometryEffect`, a
  documented exception to "only transform and opacity animate": it moves a shape between two
  segments inside one container and never changes the container's layout.
- **Screen header** (`ScreenHeader`): display title, one context line, optional trailing action.
- **Banner** (`HardsetBanner`): record, caveat, and error messages on their tinted surfaces. The
  `info` kind stays as a neutral note and is listed for deletion in the final phase if nothing
  uses it. A banner's stroke, `hue.opacity(0.35)`, the same stroke on the session screen's
  warning and record cards, and the 0.35 outline on a non-interactive `CertaintyCapsule`,
  `certainty(level).opacity(0.35)`, are decorative strokes that never carry meaning: the words,
  the symbol and the tinted surface identify the kind or level, so they are exempt from the 3:1
  boundary rule that applies to controls. A message-only banner speaks only its message to
  VoiceOver, as it does today; speaking the kind is recorded for the accessibility pass. A
  picker's error banner (gym, machine and exercise pickers) is pinned above the list at ordinary
  sizes and moves into the scrolling content at accessibility sizes, so a tall banner can never
  push the list off screen; the banner is never height-capped.
- **Arrival** (`hardsetArrival()`): the one public modifier that carries a message's
  insertion-only opacity reveal on `Motion.reveal`, with no animated transaction. The pickers and
  the name entry sheet and the session use it; the root screens adopt it when they are rebuilt.
- **Ledger** (`StatLedger`): a row of labelled figures separated by hairlines, used for session
  totals. Its values stay in the `setEntry` role, a step larger than the `figure` used inside rows
  and compact ledgers; a larger headline figure uses `readout`.
- **Empty and loading states**: explain what is missing and what to do next; loading is a quiet line
  of text, not a spinner. An empty slot is drawn with a dashed outline, the app's one mark for
  "nothing here yet": the empty-state socket, the "Add movement" slot, a warm-up's ordinal, an
  incomplete set's log control, and the rule under "Not evaluated".
- **Tags versus chips**: a chip can be tapped and wears the control border; a tag (modality,
  "Recent", "Custom", an untrained muscle) is filled only, so it never imitates a control. At
  accessibility sizes a wrapping tag, assumption chip or certainty capsule takes the control radius
  instead of a capsule, so wrapped text stays inside its outline.
- **Library** (`LibraryView`, `LibraryScreen`): every selectable movement grouped by body part, with a
  ledger of the count in each at the bottom. Movements with no body part come first under a `warning`
  header with its `exclamationmark.triangle` symbol, "Needs a body part", because until one is tagged its
  sets count toward no muscle. A row is a 56 pt `SelectionCardButtonStyle` button for the lifter's own
  movement and opens the editor; a curated movement is a flat card with a "Curated" `HardsetTag` and does
  not open it, so nothing that looks tappable does nothing. The footer lists every body part, zeros
  included, in `figure` against `chalkDim` for a zero, each row under a `hairline`. It reads what is
  there: loading is a quiet line, a failed read says so in `HardsetEmptyState`, and neither draws an empty
  library. It adds no token and no motion.
- **Movement editor** (`MovementEditorSheet`, `MovementEditorDraft`): a name field in `entryFieldChrome`,
  body-part chips, a `SelectionRow` per muscle where the body part has more than one, up to three optional
  secondary muscles chosen from chips (each counts half a set), and the equipment as chips. Chips wrap
  into rows at ordinary sizes and stack one to a line at accessibility sizes; five segments could not hold
  "Bodyweight" at a phone's width, so equipment is chips, not a `HardsetSegmentedControl`. Save is the one
  `primary` 56 pt button and waits until there is a name and a primary muscle, saying which is missing in
  `provenance` under it. A failed save is a native alert, because the sheet scrolls and a banner at the
  top would be out of sight beside the button it answers; the sheet stays up with everything typed.
  Nothing is inferred from the name, and what is saved is the lifter's own attribution at moderate
  certainty. It adds no token and no motion.
- **Workout cards** (`WorkoutCardsView`, `WorkoutCard`): the Train tab's saved workouts. The workout done
  longest ago, or never, is the up-next card, in `hardsetCard`, with its name in `title`, "3 movements" in
  `label` and a context line in `provenance`: "Up next · last done 4 days ago · beat 4 of 6 last time".
  Its one `primary` 56 pt button reads "Start" and the name; starting is a single tap with no
  confirmation, because the lifter is standing at a machine. It is the screen's one primary button:
  while a saved workout is shown, the empty "Start workout" below it steps down to `secondary`. The
  other workouts are control-radius cards with a `secondary` Start and a `quiet` Edit, and "New workout"
  and "Repeat last workout" are `secondary` buttons below them, the second only when a finished workout
  of the lifter's own exists (an imported one does not count). Nothing is claimed that was not measured:
  "beat 4 of 6" appears only when something was compared, and only on the workout it belongs to. The
  order is the rotation, never a schedule or a streak. At accessibility sizes the buttons stack. It adds
  no token and no motion.
- **Workout editor** (`WorkoutEditorView`, `WorkoutEditorScreen`, `WorkoutDraft`): a name field in
  `entryFieldChrome` and a card per movement. Each card has Sets and, once added, a rep range as large
  44 pt minus and plus controls around a `figure` value, so a plan made sitting down cannot hold a number
  the plan refuses; a rest as a rail of chips, none first; a machine tag only for a movement saved with one,
  with "Use the usual machine" to clear it; and move up, move down and remove as round header controls,
  dimmed to 0.4 when they cannot move. "Add movement" is the dashed slot and opens the same picker and the
  same movement editor as the live workout. Save is the one `primary` 56 pt button and says what is
  missing under it. A failed save or delete is a native alert, because the editor scrolls. Deleting
  archives: workouts already done from it keep every set. It adds no token and no motion.
- **Split balance** (`SplitBalance`, inside the workout editor): planned sets per body group across one
  rotation, each saved workout counted once, in the sentence-case `label` role. A group reads "12 sets
  touch it", which is a count of sets and never a total of its muscles, or "Nothing planned" in `warning`
  with its `exclamationmark.triangle` symbol, so the gap is carried by shape and word as well as colour.
  The neck is left out until something is planned for it. It sets no target and makes no judgement, and
  it says when planned sets sit on movements with no muscles recorded, because those count toward no
  group. It adds no token and no motion.
- **Progress board** (`ProgressBoardView`, `ProgressScreen`, the Progress tab): every trained movement,
  one row per movement and machine, grouped by body part under `SectionLabel` headers, with the movements
  that have no body part last under the `warning` header. A row is a `SelectionCardButtonStyle` card: the
  movement in `headline`, its machine in `provenance`, a small `plateBlue` sparkline of the last dozen
  sessions (hidden from VoiceOver and dropped at accessibility sizes), and one sentence that names its
  metric: "Estimated max +8% in 6 weeks", or "Not enough history" in `chalkDim` when no session sits six
  weeks back. Beside every estimated-max figure sits its `CertaintyBadge`, drawn over the card's corner
  as its own control so it never nests inside the card's button. A six-week change uses the weaker
  certainty of its two estimates. Imported history has its own series and says "Imported · machine
  not recorded" in the same `provenance` role. Machine and cable movements whose sets have no
  machine say "No machine recorded" there and in the chart legend. A movement with no record in its last
  three sessions is flagged "Stalled · 3 sessions" in `warning` with `pause.circle`, and no advice. "Most
  improved · estimated max" at the top repeats the three biggest estimated-max gains; load and rep
  percentages stay in their own movement rows. Empty, it says "Log a workout and your progress
  shows up here"; loading is a quiet line and a failed read says so, never an empty board. It adds no
  token and no motion.
- **Scorecard** (`WorkoutReceiptView`, `ScorecardCopy`): the block at the top of a finished workout's
  receipt, in `hardsetCard`. The headline, "Beat last time on 5 of 7", is in `readout`; a record line sits
  on `plateYellowSurface` with its trophy; "Biggest gain: Chest press, estimated max +6%" names its
  metric, and an estimated gain wears a non-interactive `CertaintyCapsule` on its own line beneath it
  (the share text says the same in words, "· Moderate confidence", because the receipt is rendered into an
  image and holds no controls); and each movement that earned a mark has a row: `plateGreen` with an up arrow for a win, the
  figures of the set ("+1 rep", "+2.5 kg · +1 rep"), `plateYellow` with the trophy for a record that no
  set beat its partner on, and `chalkDim` for "Matched" and "First time on this machine". Counted by
  movement. A movement with no earlier session on its machine is a first time and is left out of both
  numbers; one that fell short is carried by the count and never drawn as a failure. The same words open
  the share text, and the same view is rendered into the shared image. Finishing a workout opens its
  receipt here; a discarded workout, and one finished with no sets, have none to open. It adds no token
  and no motion.
- **Save as workout** (receipt): a `secondary` button under the share actions, offered for a workout with
  sets and not for an imported one, whose movements are kept apart from the catalogue's. It asks for a
  name in `NameEntrySheet`, builds the plan from the workout's movements in their order with the number
  of working sets logged, never counting warm-ups, and opens the workout editor on it as a new workout.
  Once saved, a neutral `info` banner says where it is. It adds no token and no motion.
- **Selection** (`SelectionRow`, `SelectionCardButtonStyle`, `SelectionIndicator`): selected choices
  take the plate blue ring and `plateBlueSurface`, and the trailing indicator swaps an empty ring
  for a filled check, so the choice is carried by shape as well as colour. A pressed selection
  card scales to 0.97 (not 0.98, to match every other pressed face). A disabled selection row
  dims to 0.4, as a disabled control does; saved logger values are never dimmed.
- **Rest bar** (`RestBarView`): keeps its `ViewThatFits`: the countdown and the four controls (−15,
  +15, pause, skip) share one row when they fit, and otherwise the controls drop to their own
  single row under the countdown; the four controls never split across rows.
- **Navigation titles** (`hardsetNavigationTitle`): the one title that may shrink, with
  `minimumScaleFactor(0.8)`, so a long exercise name stays on a single line in a bar. It is a
  documented exception to "adaptive layouts in place of shrinking text".
- **Plate tray and Welcome bar** (`PlateTray`, `WelcomeBarView`): the first screen's centrepiece, and
  the one place onboarding is allowed larger, physical motion. Five plates, coloured by mass (red
  25 kg, blue 20, yellow 15, green 10, white 5, which is chalk), rest in a tray as 56 pt targets with
  their mass stamped in `canvas`. Tapping one, or throwing it up, loads it on the bar's two sleeves
  with a `clank`; the bar droops a few degrees in proportion to the load, on `Motion.state`; tapping
  a loaded plate returns it. The total is in `hero` with its unit. After four idle seconds the bar
  loads one 20 kg plate per side on its own, and any touch takes over. Reduce Motion draws it
  already loaded and swaps the stack instantly. The shaft is the one place the knurl is drawn as a
  texture, because it carries no text.
- **Staged phone** (`ScaledPhoneFrame`): a real screen laid out at phone size (402 by 874 pt) and
  scaled down onto a `steel` plate with a hairline `edgeLight` rim; the first-launch tour stages
  the app's own screens in it, built from `TourFixtures`. The tour gives it 78% of the screen's
  width. A frame that is not interactive is inert to touch and hidden from VoiceOver; an interactive
  one, for the steps that ask the lifter to tap, is neither. It adds no token and no motion.
- **Pitch pages** (`PitchPage`, `PitchSetRowPage`, `PitchEstimatePage`, `PitchRestPage`): three
  pages with one anatomy, a `title` headline, two lines in `label` and one live element that is the
  real component, never a picture. "One tap per set" is a real set row prefilled from last time; its
  tap plays `clank` then the row's own `success`. "Honest numbers" is the engine's estimate for the
  same 60 kg set at 3, 8, 12 and 15 reps, so the badge walks high, moderate, low and not evaluated
  because `StrengthMath` says so. "Rest that keeps time" is the real rest bar over a `DemoRestTimer`,
  an in-memory timer with no alarm, whose controls give the selection haptic. The first-launch pager
  shows three short `hairline` segments above the primary button, the active one `plateBlue`,
  sliding on `Motion.state`; like the segmented control's indicator it is one shape moved between
  two places inside its row.
- **Tour** (`TourStage`, `SpotlightOverlay`, `CalloutCard`, `tourTarget`, `TourStaging`): the real
  root view in the staged phone, asked into each state through the `TourStaging` environment value
  the real screens read, with the controls it points at tagged in place. The spotlight is the
  canvas at 70% with one rounded hole that moves between targets on `Motion.state`; it is drawn, not
  laid out, so it joins the segmented control's indicator as a documented exception to "only
  transform and opacity animate". Touches outside the hole are swallowed, and only step two, the
  staged set's check, lets one through. A system sheet always presents over the whole window, so
  inside the staged phone the keypad, machine picker and Settings draw inline (`stagedSheet`): the
  sheet's content is the real content, on a `steel` surface with the card radius and the lit top
  edge. The callout is the one floating element on system glass besides the toolbars, and sits in
  the half of the phone the target is not in. Both Reduce Motion paths drop the hole's travel.
- **Setup** (`SetupPage`): "Before your first set." Two selection rows for the unit, which edit the
  stored preference in place, and the gym: existing gyms as selection rows with one preselected, or
  for a new lifter one name field that may stay blank. A failed save stays on the page with the
  reason and the typed name kept.
- **Text entry** (`entryFieldChrome`): raised fill, control border, and a 2 pt plate blue ring that
  fades in on focus. Used by the search field and the name entry sheet.
- **Set log control**: four states, never confused: incomplete (dashed, disabled), ready (plate blue
  outline), next up (plate blue fill), logged (the stamp). The first three are square key faces with
  a check; a logged set loses its key face and wears a round `plateGreen` seal
  (`checkmark.circle.fill`) with a knurled rim, on the row's `plateGreenSurface` tint, so logged and
  next up differ by shape, not only by hue. At accessibility sizes the control also reads "Log set"
  or "Logged", and VoiceOver hears "next to log" on the next-up row. Voice Control answers to
  "Set 2", "Log set 2", and, on the next-up row, "Log set".
- **Press feedback on self-drawn controls** (`HardsetPressStyle`, `MachinedPressStyle` and the set
  row's own styles): steel faces sink, everything else dims, and no press moves layout.
  - Machined faces (raised steel with the control edge and the edge light: unselected chips,
    `AssumptionChip`, the header icon button, the set machine chip, the set row's value fields, keys
    and secondary buttons) sink to `steelPressed`, lose the edge light, keep the control edge and
    scale to 0.97 (keys 0.96) on `Motion.press`. They never dim, so the 3:1 boundary survives a
    press. The header icon menu is the one exception: `HeaderIconMenu` is a `Menu`, not a `Button`,
    so it keeps its resting machined face, and its press feel is a device check. A selected chip
    swaps `plateBlueFill` to `plateBlueFillPressed`. An editing set-row field is `plateBlueSurface`
    with a 2 pt `plateBlue` ring and no edge light. A machined control's hit region is at least 44
    by 44 pt, however compact its face.
  - Controls that draw their own fill and shape with no steel face (segments, the dashed "Add
    movement" slot, the exercise-name link, an unset machine chip, the dismiss glyph, the "Clear
    search" glyph and the certainty badge) sink to 0.97 and drop to 80% opacity on `Motion.press`,
    in place of a pressed fill.
  - The set log control draws its own fill and shape: the set row's value fields sink as machined
    faces; the log control (ready and next up) dims and scales like other self-drawn controls;
    incomplete and logged show no press. Next up keeps its `plateBlueFill` while pressed.
  - Flat surfaces take no machined press and carry no edge light: tags, the empty-state socket,
    entry fields, banners, cards and the rest bar's panel. Tags are filled only and never take the
    machined face, so a tag never imitates a control.
  - Reduce Motion drops the scale and keeps only the fill or opacity change. Disabled controls are
    never dimmed by a press style, so saved rows and inert titles keep full contrast.
- **Target line** (set row): when a movement has a rep range and history on this exact machine, an
  unlogged row is prefilled with the double-progression target and says where it came from in `provenance`
  and `chalkDim`: "Target · One more rep than last time", "Top of your range; hold it", or "Every set hit
  the top of your range: add one step" (one plate, "assumed step", when the machine has no saved step).
  The "Last time" column still shows what last time was, so a target is never read as history. History
  borrowed from another machine gives no target and the prefill is as it always was. It adds no motion.
- **Beat mark** (set row): once a set is logged, a tag-shaped capsule under the values says how it compares
  with the same set last time on this machine, in the figures of the set: "+1 rep", "+2.5 kg", "+5 lb · +1
  rep", never a bare "Beat". A win is `plateGreen` on `plateGreenSurface` with an up arrow; a match is
  "Matched" in `chalkDim` on `steelRaised` with an equals sign, so neither is carried by colour alone. It
  wears a 0.35 hue outline, a decorative stroke like a banner's that never carries meaning and is exempt
  from the 3:1 boundary rule, because the capsule's own fill vanishes on the logged row's tint. At
  accessibility sizes, where its words can wrap, it takes the control radius instead of a capsule. A
  set that fell short, a warm-up, a set with no partner and a set done on another machine show nothing.
  It arrives through `hardsetArrival()`, the insertion-only opacity reveal on `Motion.reveal`, so the row's
  height changes at once and nothing animates layout. The row's spoken label says it in the same words
  ("plus 1 rep on last time"). It adds no token and no motion beyond `Motion.reveal`.
- **Replaceable prefill**: when the keypad opens on a value the next key will replace, its display
  draws that value on `plateBlueSurface` with a hairline `plateBlue` ring, as selected text, until
  the first edit. Static; no motion.
- **Button Shapes**: with the system setting on, `quiet` buttons wear the `secondary` control border
  and the exercise name (the load-history link) is underlined.
- **Volume bars**: square-ended gauges scaled to the week's own maximum, never to a target. Modelled
  muscles are solid plate blue; muscles that are counted but not modelled are hollow (plate blue
  outline on `plateBlueSurface`) and say so in words beside the bar.
- **Charts**: one series per machine with its own colour and point symbol, a custom legend in app
  type, with equipment provenance allowed to wrap fully at accessibility sizes, and machine changes
  as 2 pt dashed `warning` rules. The chart opens on the estimated max,
  which rises when the lifter does more weight or more reps, with the heaviest load as the other
  segment; it opens on the heaviest load when no estimate can be made. A session that set a record is
  marked on its line with a `star.fill` in `plateYellow`, drawn over the machine's own point, and the
  legend says what the star means, so colour is never the only carrier. Beneath the chart a "Best at
  each weight" table lists, per machine, the most reps at each weight and the day they were first
  reached ("90 lb · 12 reps · Nov 4"): facts from the sets, so it carries no certainty badge.

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
- Rest starts from a duration the lifter chose: logging a working set starts the rest last
  chosen for that movement, and a movement with none asks once through the card's rest control and
  remembers the answer. The app never starts a rest of a length nobody chose. Durable absolute-date
  state is separate from OS scheduling; a visible retry banner reports either persistence or
  scheduling failure. No countdown state is stored or animated by a custom loop. The rest bar's
  "Next rest" row, and a drag up on the bar, open a row of lengths for the movement's next rest; it
  appears by an insertion-only opacity reveal like any message, because a height that animated would
  slide the set rows above it.
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
