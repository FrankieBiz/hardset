# Hardset design system

Source of truth for every visual decision in the app. The implementation lives in
`Packages/HardsetKit/Sources/HardsetUI/`: `DesignTokens.swift`, `Components.swift`,
`ControlFace.swift`, `PressStyle.swift`, `KnurlPattern.swift`, `TypeRole.swift` and `Haptic.swift`;
this file explains
the choices, and `Tools/check_contrast.py` verifies the palette numbers below against the
Swift source so the two cannot drift. The reasoning and the migration order for the sleeker pass
are in `docs/design/2026-11-20-sleek-apple-spec.md`.

## Status of the sleeker pass

The direction is settled and lands in phases. This file states the target; this section says what
the code does yet, so a reader does not look for a screen that has not moved.

- In code: the palette steps and `controlFillOnCanvas`, continuous radii through `Tokens.Shape`,
  `Elevation.floating`, the `display` role off condensed, `labelEmphasis` retired, and the shared
  kit: the flat control face and its outline rule (`ControlFace.swift`), buttons, chips, the
  segmented control, header buttons, text entry, cards, banners, tags and certainty badges.
- The live session is in code, rebuilt monochrome and type-led (ruling D12): see Set row, Set log
  control, Inline control, Panel and the live-session layout below. Train's start screen is rebuilt
  the same way (see Train start screen), and so are Progress, the board and the movement chart,
  Volume and Library.
- The figure scale is in code (ruling D20): `figureXL`, `countdown`, `monument` and `monumentAside`, the 28 pt title,
  the 64 pt set row, the estimate ceiling and its check. It is scale and hierarchy only: it adds no
  glyph, rule, colour or motion. The onboarding demo and the catalogue's set rows keep the compact
  row, and History's row figures, the keypad display and the welcome bar keep their sizes.
- Every monument and every capped estimate opens "Worked from" (see Inspectable figures): the two
  monuments, a Progress row's six-week change, the scorecard's biggest gain, the live record
  notice and muscle history's four-week comparison and lifetime figures. The audit there lists every
  figure and says which derivation explains it.
- Not yet in code, so the bullets below that name these describe where they are going: whatever a
  screen draws for itself instead of through the kit. That is the scorecard headline's type role and
  the onboarding surfaces. It also includes three private outlined-card button styles that each draw their own
  stroke: the History row, the Settings disclosure row and the receipt's link row, plus the
  methodology citation card. A screen that uses the kit picks up the new look with no change; one that draws its own
  face or stroke keeps the old one until it is migrated.
- The keypad keys keep their `controlEdge` outline until the keypad has had its device check; see
  Keys.

## Point of view

Hardset is a calibrated instrument for the gym floor. The product's claim is calibrated honesty,
so the interface behaves like a measuring device rather than a lifestyle app.

The visual idea is calibrated iron, drawn quietly. Competition plates are colour-coded by mass, and
the colours are a calibration standard, not decoration: red 25 kg, blue 20 kg, yellow 15 kg, green
10 kg, white 5 kg. So the app's colour is the colour of calibrated plates, its surfaces are flat
steps of graphite and chalk that separate by fill rather than by line, and its figures are the
stamped numerals on a plate. The semantic colours (logged green, record gold, caveat amber, failure
red, action blue) are not arbitrary; they carry a story the lifter already knows. The chrome that
floats above the content, the tab bar and sheet toolbars, is the system's own glass; the content
beneath it is never glass.

- **Colour is evidence, never decoration.** Hue appears only when it says something, and it is a
  plate colour: an action you can take (plate blue), a set that is saved (plate green), a record
  (plate yellow), a caveat (warning orange), a failure (plate red). Everything else is steel and
  chalk.
- **On the live session, one accent, and colour only as a small mark.** The log control of the
  workout's primary action is the only saturated colour on the screen: the first set, in workout
  order, that is not logged and can be, not one per movement and not whatever row happens to be
  next. A blank warm-up is next up but cannot be logged, so it does not hold the accent from the
  working set behind it. While the keypad is up its own primary action, Next or Log set, is the
  accent and no row has it. A saved set is a small `plateGreen` seal, a record is
  the `plateYellow` trophy, a caveat is a small `warning` glyph, and a failure is `plateRed`; none
  of them is ever a row fill, a tint, a capsule or a badge background, and no other control is blue.
  The machine, the gym, the history link, the rest lengths and every quiet action are `chalk` or
  `chalkDim`. Certainty is a phrase, not a coloured capsule (see `CertaintyBadge`). The finish
  confirmation's primary button is the one other plate-blue fill, and it exists only while the
  lifter is answering that question.
- **Numbers are the hero, and size is earned by being a measurement.** Weights, reps and rest are
  set in SF Pro Condensed with tabular figures: large, narrow and steady, like stamped plates or a
  scale readout. A number the lifter typed or the app counted is large, up to an 88 pt monument (72
  where the screen is for an action); a
  number a formula produced is never larger than `readout`, 28 pt, whatever it is and wherever it
  sits (see Figure scale). The biggest figures on a screen are therefore the ones that need no
  caveat, and a lifter can tell a measurement from an estimate across the room by its size before
  reading a word.
- **A control says what it does; structure comes from fill, not line.** Cards and groups separate by
  a step of surface. A control is identified by a fill, a verb label or a standard glyph. A 3:1
  outline is kept where those cannot carry it alone: an input that is empty or being typed into,
  every control under Increase Contrast, and every control when Button Shapes is on. Static text and
  a saved value never imitate a button. The live session goes further: no input is boxed, a control
  may be only its label, and the outline returns under Increase Contrast and Button Shapes.
- **Restraint everywhere except the log tap.** The one memorable moment is logging a set: the
  check stamps in with a short spring and the clank, the row settles into its logged state, and the
  rest bar and marks arrive just after, as one event (see The log moment). Nothing else moves
  without being asked.

## Palette

Normal appearance values. All text roles are at least 7:1 against `canvas`, `steel` and
`steelRaised` in both appearances; `controlEdge` is at least 3:1 against all three and against
`steelPressed`, because a pressed face keeps it. Dark is the
primary appearance; light is derived from the same roles and held to the same floor.

| Token | Dark | Light | Role |
| --- | --- | --- | --- |
| `canvas` | `#050608` | `#F2F2F7` | Screen canvas: rubber-matting black, grouped chalk white |
| `steel` | `#1A1B21` | `#FFFFFF` | Cards, rows, sheets' content |
| `steelRaised` | `#24262D` | `#EEEEF2` | Fields, keys, chips and secondary buttons that sit on `steel` |
| `controlFillOnCanvas` | `#24262D` | `#FFFFFF` | Fill of a control that sits directly on `canvas`: header buttons, Train and Settings buttons |
| `steelPressed` | `#111216` | `#E6E6EB` | Momentary pressed fill, darker than `steelRaised` so a press sinks, and distinct from both `steel` and `canvas` so a pressed control with no outline keeps a visible face |
| `hairline` | `#2E3039` | `#DEDEE4` | Decorative separators inside a card; never a boundary |
| `controlEdge` | `#7B7E8C` | `#7E8190` | The outline of an input, and of every control under Increase Contrast or Button Shapes |
| `gaugeTrack` | `#5C5C65` | `#888892` | The unfilled part of a gauge that carries meaning: the first-launch pager's inactive segments. At least 3:1 on `canvas` in every appearance; drawn on `canvas` only |
| `chalk` | `#F3F3F5` | `#141519` | Chalk / graphite body text and values |
| `chalkDim` | `#B6B8C3` | `#4B4D58` | Supporting text, units, provenance |
| `plateBlue` | `#6FB7FF` | `#084A95` | The 20 kg plate: actions, focus, selection, next up |
| `plateBlueFill` | `#6FB7FF` | `#084A95` | Primary button fill |
| `plateBlueFillPressed` | `#5AA6F0` | `#063C7A` | Primary button pressed |
| `onPlateBlue` | `#0C0D10` | `#FFFFFF` | Text on `plateBlueFill` |
| `plateBlueSurface` | `#10233A` | `#E3EFFC` | Selected / focused tint |
| `plateGreen` | `#8FE3A3` | `#0F5A27` | The 10 kg plate: logged, high certainty |
| `plateGreenSurface` | `#122A1A` | `#E5F5EA` | The high-certainty capsule where a screen still draws one |
| `plateYellow` | `#FFD86B` | `#604A00` | The 15 kg plate: records, moderate certainty |
| `plateYellowSurface` | `#2B2410` | `#FBF3DA` | Record banner |
| `plateRed` | `#FF9A9A` | `#9A1B24` | The 25 kg plate: failed writes |
| `plateRedSurface` | `#2E1516` | `#FBEAEA` | Error banner |
| `warning` | `#FFB27A` | `#7A3A00` | Caveats, low certainty; not a plate, the colour of a flagged lift |
| `warningSurface` | `#2C1D12` | `#FCEEE3` | Caveat banner |

Steps: surfaces separate by fill, not by line. Canvas to `steel` is 1.18:1 in dark and 1.12:1 in
light; `steelRaised` on `steel` is 1.14:1 in dark and 1.16:1 in light. `steelRaised` cannot be
brighter in dark: `plateBlue` text on it is 7.12:1 against the 7:1 floor. A control that sits
directly on `canvas` takes `controlFillOnCanvas`, because light `steelRaised` on `canvas` is only
1.04:1. `steelPressed` is below the original proposal in dark (`#111216`, not `#1B1C22`): with no outline, the
proposed value was 1.01:1 against `steel`, so a pressed control inside a card lost its face; this one is 1.09:1
against `steel`, 1.08:1 against `canvas` and still darker than `steelRaised`. The machined edge colours `edgeLight` and `edgeShadow` are retired with the raised face they
drew, and both tokens are deleted.

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
green, yellow and red plates, `warning` and their surfaces keep their normal values: they already
clear the floor. Under Increase Contrast `canvas`, `steel` and `steelRaised` are one colour, so the
fill step is gone and every control wears its `controlEdge`. Resolution happens live from the trait
collection, in code, with no asset catalogue.

`gaugeTrack` is the one boundary-grade colour with no Increase Contrast pair, on purpose. A gauge's
unfilled part is required information, so it is held to 3:1 on `canvas` and cannot be `hairline`, which
is decoration and was 1.54:1 dark and 1.20:1 light when the pager drew its segments with it (ruling
D22). It measures 3.06:1 dark, 3.15:1 light, 3.17:1 dark and 3.51:1 light under Increase Contrast.
`controlEdge` would clear 3:1 as well, but its Increase Contrast pair (`#9B9BA5` / `#595964`) is
loud against pure black and white and leaves the `plateBlue` indicator, in its own Increase Contrast
pair, at about 1.7:1 and 1.6:1 against it: the indicator would read as the quieter segment at the
setting a low-vision lifter turns on. Against `gaugeTrack` the indicator is 3.12:1 dark and 2.47:1
light, and 4.08:1 and 3.20:1 under Increase Contrast. A deep-blue indicator cannot also be 3:1 from a
mid-grey track on the light canvas while the track is 3:1 from the canvas, so the pair is held to
its order and not to 3:1 (`Tools/check_contrast.py`).

Certainty maps high → `plateGreen`, moderate → `plateYellow`, low → `warning`, unevaluated →
`chalkDim`, always with its word and symbol so colour is never the only carrier. On the live
session certainty is language instead: a phrase in `provenance` and `chalkDim`, "Moderate
confidence", with what it is about before it ("From another machine · Low confidence") and a small
info glyph that says it opens. The words carry the level and no hue does; see `CertaintyBadge`.

An estimate derived from a formula is never High: an estimated one-rep max tops out at Moderate,
because the research behind it finds the formula overestimating from about five reps, and only a
measured single, which estimates nothing, is High. `StrengthMath.estimatedOneRepMax` decides this
beside the figure, and every badge, record line and disclosure beside an estimate reads it from
there. This matches the Volume ladder, which never exceeds Moderate either.

Chart series (one line per machine, never merged) use chalk `#E7E7EC`/`#3A3A42`, `plateBlue`,
lilac `#B9A8FF`/`#5236B8` and rose `#FF9DD6`/`#9A1F66`, each paired with a distinct point symbol. Chalk
comes first, so a movement on one machine, which is most of them, draws a monochrome line on a screen
that has no primary action to own an accent; `plateBlue` appears only when a second machine needs a
second hue.

## Typography

System fonts only, so no resource bundle is needed. Every role is a Dynamic Type text style.

| Token | Style | Use |
| --- | --- | --- |
| `display` | Title, semibold, standard width, 28 pt | Tab screen headers; steps down so the figures outrank the word that names the screen |
| `title` | Title 3, semibold | Sheet headers, hero card titles, a sentence that holds figures |
| `headline` | Headline | Card and row titles, primary button labels, emphasised labels |
| `label` | Body | Ordinary text and control labels |
| `provenance` | Callout | Certainty, borrowed-history notes, corrections |
| `unit` | Callout, medium | Unit suffixes beside values |
| `caption` | Footnote | Supplemental notes only |
| `sectionHeader` | Subheadline, semibold | Sentence-case section labels; never all caps |
| `monument` | 88 pt, semibold, condensed, tabular | The one measured figure a screen leads with, where the screen's subject is the number: Volume. At most one per screen |
| `monumentAside` | 72 pt, semibold, condensed, tabular | The same figure where the screen's subject is an action: Train. At most one per screen, and never with a `monument` |
| `countdown` | 64 pt, semibold, condensed, tabular | The rest countdown |
| `figureXL` | 44 pt, semibold, condensed, tabular | Measured figures in a set row, a `StatLedger` and a receipt's sets |
| `hero` | Large Title, semibold, condensed, tabular | Keypad display, welcome bar's total |
| `readout` | Title, semibold, condensed, tabular | Headline figures; the largest an estimate may be |
| `setEntry` | Title 2, semibold, condensed, tabular | Keypad quick steps, history's day figure, Volume's per-muscle counts |
| `figure` | Headline, condensed, tabular | Small figures inside rows and compact ledgers |

**The monument is 88 where the screen's subject is the number, and 72 where the screen's subject is
the action. On Volume the number is the content; on Train the action is. A number that outranks the
primary action makes the screen harder to use, which is the opposite of what this signature is for.**
This is a rule and not a taste: a new screen takes `monument` if the number is what it is for and
`monumentAside` if it is for something the lifter does, and the size is not adjusted by eye.

Condensed is for figures only; a sentence that holds figures is `title` with tabular digits. The
system font chooses its own optical size and tracking, so `display` adds none.

Tracking is a ratio of the resolved size, so it follows Dynamic Type: `hero`, `figureXL`,
`countdown`, `monument` and `monumentAside` -2%, `readout` -1%, `caption` and `unit` +1%, every other role 0. `hardsetText(_:)` applies a role's
font and tracking together from `Tokens.Text.Role`; the static fonts carry no tracking.
`hardsetText(_:weight:)` applies a weighted variant of a role with the same tracking, so a
semibold caption keeps its +1%; a static weighted font cannot carry tracking, and no modifier
chained after `hardsetText(_:)` is used to change its weight.

### Figure scale

`monument`, `monumentAside`, `countdown` and `figureXL` are not text styles: each is a point size that
scales along the curve of the style it is set against (`monument`, `monumentAside` and `countdown`
Large Title, `figureXL` Title), and each stops at accessibility1. At 44 to 88 pt they are already larger than body text at
the biggest setting, and growing further would push a figure wider than the row or card holding
it; the words around a figure keep scaling to accessibility5. The stack and wrap layouts that
accessibility sizes already use carry the rest.

The rule is `Tokens.Text.estimateCeiling`, 28 pt at the default size, and it is the signature of the
app, not a detail of it. A figure is a measurement if the lifter typed it or the app counted it: a
set's weight and reps, a count of working sets, a sum of the loads and reps logged, a countdown to
a deadline the lifter chose. Those may be `figureXL`, `countdown`, `monument` or `monumentAside`. A figure is an
estimate if something was inferred: an Epley one-rep max, a fractional muscle credit, a percentage
change in either, a trend. Those are `readout` at most, usually smaller, and always beside their
certainty. `Role.mayCarryEstimate` is false for the four scale roles and for `hero`; the ledger
draws an item marked `isEstimate` at `readout` whichever role was asked for; and
`Tools/check_figure_cap.py`, part of `make check`, names the files that may use a large role, each
with the reason its numbers are measurements, so that adding a use anywhere else is a visible
edit to that list and not a drive-by. Progress is the proof: every figure on it is an estimate or a
comparison of estimates, so none of them leaves the sentence it is in.

### Inspectable figures

The scale has a second half: a large number the lifter cannot inspect is exactly what the product
refuses. So every monument opens "Worked from", and so does every capped estimate, through the same
`WorkedFromSheet` and a derivation in Core that runs the same inputs through the same functions the
figure came from, so the sheet cannot say what the figure did not do. Each names the formula and lists
every set it left out under "Left out", with the reason.
`Tools/check_interaction_rules.py` fails the build when a file draws a monument without its hookup,
and when a new file draws one at all until the file is added to its list with the derivation that
explains it. It fails the same way when a capped estimate's control or its sheet is removed.

The audit, every figure the app draws above body size or capped as an estimate, as of this pass:

| Surface | Figure | Kind | Size | Opens Worked from |
| --- | --- | --- | --- | --- |
| Volume | Weekly count of working sets | Counted | `monument` 88 | Yes. `WorkingSetCountWorking`: a line per movement, warm-ups under Left out, equal to the report's own count |
| Train | Last workout's volume | Summed | `monumentAside` 72 | Yes. `SessionVolumeWorking`: a line per set as weight × reps, warm-ups under Left out, equal to the history summary's volume (a Store test holds them equal) |
| Volume | A muscle's weekly count; a map tile | Estimate (fractional credit) | `setEntry` 22 | Yes. `MuscleCountWorking` |
| Muscle history | A muscle's last four weeks, the four before, their difference and its lifetime count | Estimate (fractional credit) | `readout` 28 at most | Yes. `MuscleHistory.account`: the two four-week accounts and the lifetime account materialised from the grouped counts, each adding up to its figure. No certainty badge: the weekly curve is not placed on a four-week or lifetime total |
| Progress chart | A machine's latest estimated max; a record star | Estimate; derived | legend figure | Yes. `EstimateWorking`, `RecordWorking` |
| Receipt | A record on a set; the scorecard's record line | Derived | 17 | Yes. `RecordWorking` |
| Rest bar | The countdown | A deadline the lifter chose | `countdown` 64 | Not applicable: nothing was worked out |
| Live session, receipt, Train | Weight and reps of a set; the live "This workout" ledger | Typed or counted | `figureXL` 44 | Not applicable for a typed figure; the ledger's sets are the list above it |
| Progress board | A row's six-week change, and the same figure in the Most improved strip | Estimate (a ratio of two estimates) | 17 | Yes. `ChangeWorking.sixWeek`, rebuilt from `ProgressTrendAnalyzer.comparison`, the function the row's figure came from: the latest session and the baseline five to seven weeks before it, each set as weight × (1 + reps ÷ 30), the sessions passed over in the band, and every warm-up, set on other equipment, session outside the band and session with no estimate under Left out. Read on demand from the board's own grouping; a Store test holds its figure equal to the row's |
| Receipt | The scorecard's "Biggest gain … estimated max" | Estimate (a ratio of two estimates) | 17 | Yes. `ChangeWorking.lastTime`, from the sets the gain was computed from, which travel with it: this workout's sets, last time's on the same machine, the formula, and the warm-ups, sets on other equipment and older sessions counted under Left out. The control is on the screen's receipt and never in the shared image, which holds no controls |
| Live session | The record notice, for an estimated max or any other record | Estimate (for an estimated max); derived | 17 | Yes. `RecordWorking.liveAccount`: one line per record on the notice, each naming the set it beat and the margin the detector applied; the estimate's formula and this session's sets, with those left out; and under Left out of the comparison a count of the warm-ups, other-equipment sets and imported sets it was never measured against. Built from the saved history when asked for, and a Store test holds the replay's records equal to the logger's own |
| Onboarding | The pitch's estimate for a fixed 60 kg set | A demonstration | `readout` 28 | Exempt: no history to open; the arithmetic is the lesson |

Nothing above 28 pt is an estimate, which `Role.mayCarryEstimate`, the ledger and `check_figure_cap.py`
hold. Every capped estimate in the table above is also inspectable, so both halves of the rule hold for
every figure the app draws above body size or as an estimate. The three that were not are each a
comparison of two estimates, or an estimate and the record it beat, which no derivation in Core covered
and no surface had a control for; `ChangeWorking` covers the first two and `RecordWorking.liveAccount`
the third. Where a control sits, it is its own element beside the figure's own, so tapping the row, the
scorecard or the notice does what it always did.

Two choices are on purpose. The change's account lists a session outside the comparison band as one
line with its count of sessions and sets, not a line per set: the reason belongs to the whole session,
and a long history would otherwise be hundreds of lines. And the scorecard's account is built from the
sets the gain was computed from, carried on the gain itself, so it needs no second read and cannot
disagree with the scorecard it explains.

One monument per screen and nowhere else: Volume's weekly working-set count at 88 pt, where the
number is the content, and Train's last workout volume at 72 pt, where the action is. A screen with
no measured figure to lead with has none; Progress, Library, History and the live session have none,
and the live session's own largest figure is the rest countdown. Progress having none is the rule
working, not a gap in it: every figure there is an estimate, and an estimate is never a monument.

## Spacing, radius, stroke

- Spacing: `hairline 2`, `tight 4`, `snug 8`, `regular 12`, `loose 16`, `section 24`, `block 32`.
  Page margin is `loose` (16).
- Radius, all continuous, drawn through `Tokens.Shape`: `control 12` for fields, keys, buttons and
  rows; `card 24` for cards; `bar 4` for the ends of a gauge.
  Inner radius is outer radius minus the padding between them, so a card of 24 with 12 of padding
  holds controls of 12. Capsules are reserved for chips and badges. Sheets take the system's own
  corner radius.
- Stroke: `hairline 1` for separators and the conditional outline, `selected 2` for selection and
  focus rings, the editing field and the ready log key.
- Targets: 44 pt general minimum, 56 pt in the logger (keypad, rest controls), and 64 pt for a set
  row's fields, ordinal and log control, which hold the 44 pt figures. A control that has no visible
  face keeps its frame and hit region.

## Materials and elevation

- System glass is for the chrome the system draws: the tab bar and sheet toolbars. It is never
  `.interactive()`.
- Everything the lifter reads to do the work is opaque: rows, cards, figures, and the rest bar,
  whose countdown is the one number read at arm's length under gym glare. Text on glass cannot be
  gated by `Tools/check_contrast.py`, which measures opaque pairs and could only model glass, so a
  gym-floor tool does not stake its most-read number on a material it cannot certify.
- `Elevation.floating` (`hardsetFloating()`): a soft shadow for a pinned opaque surface, in light
  only, about y 2, blur 12 and 12% black, to be tuned on a device. In dark the 1.34:1 step to
  `canvas` does the separating. It animates nothing.

## Motion

| Token | Value | Use |
| --- | --- | --- |
| `Motion.press` | 120 ms ease-out | Button and key press feedback |
| `Motion.state` | spring, response 0.30, damping 1.0 | Selection, segment indicator, row state |
| `Motion.reveal` | 280 ms ease-out | Banners and inline confirmations appearing |
| `Motion.stamp` | 300 ms spring, bounce 0.3 | The log check, and nothing else |
| `Motion.follow(reduceMotion:)` | `Motion.reveal` started 120 ms after the stamp; none under Reduce Motion | The second beat of the log moment: the "+1 rep" mark, the rest bar and the record notice |
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
leaves at once. A logged row's figures go from `chalkDim` to `chalk` in the frame the set is saved,
with no fade, and the row's height is never animated.

### The log moment

The one signature of the app is not a spring and not a haptic; it is one event that a lifter at a
machine perceives as a single thing, the plate meeting the bar. `LogMoment`
(`Packages/HardsetKit/Sources/HardsetCore/LogMoment.swift`) writes it down as data, the interface
reads its numbers from there, and `LogMomentTests` pins them. It has two beats.

| Beat | When | What |
| --- | --- | --- |
| Contact | The frame the row is marked logged, which is after the write succeeded | The clank (the one haptic), the seal's stamp on `Motion.stamp`, the figures to full `chalk`, the screen's one accent moving to the next set that can be logged. Cuts and the one spring; nothing fades |
| Follow | 120 ms later, one delay for all of it | The "+1 rep" mark, the rest bar, the record notice and the one-time correction hint fade in on `Motion.reveal`. Layout is already final and nothing slides |

The follow beat waits because those things are information about the set and not the set being
stamped: arriving with it, they competed with it on three clocks (a spring, a fade and a hard cut).
120 ms is inside the stamp's own 300 ms, so the two overlap, and the whole moment is over inside
0.45 s (`LogMoment.settleCeiling`). The seal reaches its full size a little after the follow beat
begins, so the eye lands on the stamp first.

Rules, each of which a future change has to break on purpose:

- **One haptic, and it is the clank.** There is no `success` haptic under it: two patterns on one
  instant felt like one doubled tap and are not what is wanted. `Tokens.Haptic` has no `success`.
  `ClankPlayer.play()` is called from the row's `isLogged` false to true change, once, and from
  nowhere else in the logging path; the Welcome bar's plate landing is its only other use. The
  session prepares the engine when it appears, so the first set's clank is not late.
- **Never before the save.** The row is marked logged only by `SessionCoordinator.logSet`, after
  the store has written the set; a refused write leaves the row unlogged and starts no rest, so it
  has no contact. An undo, and a row that appears already logged after a recovery, change nothing
  and play nothing.
- **Reduce Motion keeps the meaning.** One beat, no spring, no fade, no delay: the seal, the mark,
  the rest bar and the notice appear together in the frame the set is saved, and the clank is
  unchanged, because it now carries what the motion no longer does.
- **Nothing else is this theatrical.** No other control stamps, springs with bounce, or sequences a
  second beat. A new use of `Motion.stamp` or of `hardsetArrival(beat: .follow)` outside the set a
  lifter just logged is a change to this section first. A failure, a stale-workout notice and every
  other message stay on the plain reveal.

What this does not claim: that it feels right. The sequence and the Reduce Motion variant are
checked as data and in the code; the felt alignment of the clank with the stamp is a device check
(`docs/OWNER-DEVICE-CHECKLIST.md`), and the seal's first full size lands about 150 ms after the
haptic, which is the number to tune against `LogMoment.followDelay` if the device says the two feel
apart.

Haptics follow the same restraint, and each has a name in `Tokens.Haptic`: `clank`, `error`,
`selection` and `warning`. `clank` is the weighty tap of a plate meeting a bar: a CoreHaptics
pattern (a transient at intensity 1.0 and sharpness 0.6, then a 40 ms low rumble) played by
`ClankPlayer`, which falls back to the heavy system impact where CoreHaptics is unavailable, and
which `Tokens.Haptic.clank` names for a view that plays it through `.sensoryFeedback`. Saving a set
plays `clank` and nothing with it (the row plays it when it is marked logged, so a failed write
plays nothing; see the log moment above), and the Welcome bar's plate landing is the only other
place `clank` is used. `error`
follows every failed command, a repeated failure included. `selection` answers the row's machine
step and the rest bar's −15, +15, pause, skip and next-rest choices. `warning`
marks a rest that ran out on its own when no alarm can mark it (alarms denied or unavailable).
Selection rows, the unit switch and pickers stay silent.

## Components and states

- **Buttons** (`HardsetButtonStyle`): `primary` (plate blue fill), `secondary` (`steelRaised` on a
  card, `controlFillOnCanvas` on canvas), `quiet` (plate blue text, no fill), `destructive` (red text
  on the error surface, dimmed to 60% while pressed). Sizes `logger` (56 pt) and `regular` (44 pt).
  States: default, pressed, disabled (40% opacity), focused (system focus ring). One `primary` per
  state: the thing the lifter came here to do. A secondary button is a flat fill with a `chalk`
  label and no stroke; pressed, it swaps to `steelPressed` and scales to 0.97. Under Increase
  Contrast or Button Shapes every role but `primary` (a fill of about 8:1 needs none), `quiet` and
  `destructive` included, wears the `controlEdge` outline, in both states, so the 3:1 boundary
  never disappears under a finger. A button takes the fill of the surface it sits on, through
  `ControlSurface`: `hardsetCard()` sets `steel` for everything inside it, a steel panel that is not
  a card (the keypad) sets it with `hardsetControlSurface(_:)`, and anything else is on the canvas.
- **Keys** (`HardsetKeyStyle`): a key is its figure or glyph in `chalk` in a 56 pt cell a third of
  the pad's width: no face, no fill and no outline. Pressed, it sinks to 0.96 and dims to 80% on
  `Motion.press` (Reduce Motion drops the scale), as every control with no face of its own does;
  disabled, it dims to 40%. Under Increase Contrast or Button Shapes each key wears the 3:1
  `controlEdge` outline around its whole cell. The quick steps are keys in `chalk`: the machine's own
  increment as minus two, minus one, plus one and plus two of it, or −5, −2.5, +2.5 and +5 when none is
  recorded (see The single-thumb pad traversal), and Done is an inline control; the one filled
  control on the pad is its primary action, Next or Log set, which owns the screen's accent while
  the pad is up (the rows give theirs up, see the set log control). The keypad drops its keys' faces
  because the screen behind it has none; gym glare and sweaty hands on a face-less key are a device
  check, and it reverts in one place, `HardsetKeyFace`. The same pad serves the load-step editor
  and the receipt's correction sheet, which have no live machine increment in hand and so offer the
  fallback steps.
- **The single-thumb pad traversal** (`NumericPad`, the session's keypad sheet, `QuickSteps`): the
  logger is operated with the thumb of the hand holding the phone, the other hand on the bar. That
  is a rule with three clauses, each held by a check, so a future change cannot reintroduce what the
  pad exists to remove.
  - **No system keyboard, no cursor, ever, on the logging path.** Weight, reps, a load step, a rest
    and a correction are typed on `NumericPad`, which edits a `NumericEntryBuffer`. No file on that
    path (`Tools/check_interaction_rules.py` lists them) may declare a text input: `TextField`,
    `TextEditor`, `SecureField`, `.keyboardType`, `@FocusState`, `.focused`, `.searchable` or a UIKit
    text view. A keyboard covers half a small screen, puts the digits where the hardware says, and
    needs a dismiss gesture the free hand is not free to make; a field needs a cursor placed. A
    search field in a picker or a name is text and is not on the path. The real
    app is driven through a workout in CI and asserts that no system keyboard appears with the weight
    open, after Next, or on the reps (`AppScreensUITests`).
  - **Weight to reps is one press.** `Next` retargets the same pad in place: the display names the
    new field, the prefill is selected so the first digit replaces it, and nothing is dismissed and
    presented again. The last field offers `Log set`, so a changed set is entered and logged without
    a trip back to the row's check. Type a weight, Next, type the reps, Log set: no cursor and no
    second tap on the reps field. A set that is already right is one tap on its check.
  - **The steps are the machine's.** The pad's quick steps are the machine's recorded increment as
    minus two, minus one, plus one and plus two of it, in the unit the pad shows (`QuickSteps`), and
    the row's −/+ use the same number, so the pad never steps to a load the equipment cannot hold. A
    pin stack of 4.5 kg offers −9, −4.5, +4.5 and +9 and, read in pounds, 9.92 and 19.84. With no
    increment recorded the pad falls back to 2.5 and 5, which claims nothing about the machine, and
    the row's −/+ stay absent, as they always have, because a stepper on the row would assert a step.
    Reps move by −1, +1 and +2. A step is a key like the others, a cell the width of its column and
    56 pt tall, four across at ordinary sizes (about 88 by 56 pt on a 402 pt phone) and two by two at
    accessibility sizes; the row's steps are 56 pt tall and half the row wide.

  Where everything the logger needs between sets lives, so reach is a property of the layout and not
  of luck. The header scrolls away with the list, and nothing is pinned to the top: the live screen's
  pinned things are the rest bar and the keypad, both at the bottom, and the check forbids anything
  else being pinned to the top.

  | The lifter needs | It lives | Reach |
  | --- | --- | --- |
  | Log a set that is right | The check at the trailing edge of its row, 64 pt, in the list | Scrolls into the lower part of the screen; the list is flicked with the same thumb |
  | Type a weight or reps | The pad, pinned at the bottom; the row's figures open it | Pad top at or below 40% of the screen, every key below that |
  | Weight to reps, Log set, Done | The pad's footer: Next, Log set and Done, 56 pt | Bottom of the pad, the bottom of the screen |
  | Step the load | The pad's quick steps, and −/+ under the next row where the machine's step is recorded | Pad; the next row, wherever the list has put it |
  | Rest: −15, +15, pause, skip, next rest | The rest bar, pinned at the bottom; the next-rest row at ordinary sizes only | At or below 60% of the screen |
  | Machine, movement options, add a set | The card's own header and footer, in the list | Scrolls into reach |
  | Finish the workout | The end of the list, and Workout options in the header | The end of the list is a flick away; the header menu is a convenience, never the only way |
  | Change gym, Settings | The gym line in the list, and the header | Not needed to log a set |

  **The pinned stack is capped at accessibility sizes.** The record notice and the rest bar are pinned
  over the list, so what they cover is what the list loses. At accessibility3 the full notice, about half
  the screen on its own, stacked on the rest bar covered about eighty percent of it and left a sliver
  of the list to log in; that grew worse when the figure scale grew. So at accessibility sizes the
  notice collapses to one line (a trophy, "2 records" and a close mark, a 56 pt control) that opens
  its detail, and the rest bar keeps only the countdown and the four controls (see Record notice and
  Rest bar), and the one-time correction hint waits for the rest to end. The rule is that the two
  together cover at most half the screen, so the upper half always holds the list and the set being
  logged can be seen and reached; `SingleThumbReachTests` hosts the session with a notice and a running
  rest at accessibility3 and accessibility5 and asserts it.

  The pinned figures are measured and not assumed: `SingleThumbReachTests` hosts the live session at
  402 by 874 pt, asks where the keypad and the rest bar actually are, and asserts them, writing every
  number it measured to `thumb-reach.txt` beside the renders. It does not say where a row is in the
  list, which is wherever the lifter scrolled it, nor that a given hand reaches a given point: the
  next-up check at the trailing edge is the right thumb's, and a left-handed lifter crosses the
  screen to it. Both are device checks (`docs/OWNER-DEVICE-CHECKLIST.md`). It adds no token and no
  motion.
- **Knurl** (`KnurlPattern`, `.knurl(opacity:)`): a `Canvas` crosshatch at 8% opacity, the
  `KnurlPattern` default. It fills rectangular bounds, so callers with rounded shapes clip it
  themselves. It is retired from the live session: the rest bar's countdown is drawn directly on
  the panel in `chalk`, and the logged-set seal is a plain `checkmark.circle.fill` with no knurled
  rim and no disc, so the stamp is the one theatrical moment and a texture is not part of it. The
  welcome bar's shaft, in onboarding, is the one place left, and the token catalogue keeps one
  labelled sample. The knurl is always a backing layer, `KnurlPattern` inside a `.background { }`
  clipped to the backing shape, and is never drawn behind text.
- **Cards** (`hardsetCard`): `steel` fill, continuous `card` radius, no border. Separation is the
  step to `canvas`; inside a card, rows separate by `hairline` only where they need to. Selected
  uses a 2 pt `plateBlue` ring and `plateBlueSurface` fill, because selection is state. Under
  Increase Contrast, where the fill step is gone, a card wears a `hairline` border.
- **Panel** (`hardsetPanel`): the one raised tone of the live session: `steelRaised` on the `card`
  radius, no colour and no border, with a `hairline` border under Increase Contrast. The rest bar
  and the record notice are panels, so they stand on the same step off the canvas, and what a panel
  says is carried by its words and one small mark. The record notice ends in a compact "Worked from"
  control, `provenance` words in `chalkDim` and the glyph, that opens what each record beat, the
  formula behind an estimate and every set left out. The stale-workout notice is a neutral `hardsetCard`
  with a small `warning` glyph, because it holds buttons that need a fill to step off.
- **Record notice** (`SessionView`): the records of the set just logged, a panel at the foot of the
  live session: the movement and "New record" with the trophy in `plateYellow`, a line per record that
  says what it beat ("Best estimated 1RM: About 162 kg, up from about 122 kg") and, under an estimate,
  its certainty as a phrase, then the compact "Worked from" control. It arrives on the log moment's
  follow beat and is put away with its close mark. At accessibility sizes, where it has a way to open
  its detail, it is one line instead: the trophy, "1 record" or "2 records", and the close mark, the
  whole line a 56 pt control that opens "Worked from", where every record, what it beat, the formula and
  the sets behind it are written out at the lifter's own pace. Without a way to open that detail the
  card stays whole, because collapsing would hide the records. Neither form adds a token or a motion
  beyond the follow beat.
- **Chips** (`HardsetChip`): capsule, raised fill, no stroke; selected uses `plateBlueFill` with
  `onPlateBlue` text.
- **Inline control** (`InlineControlStyle`): a control that is only its label, for a screen that has
  dropped its containers: words, a symbol or both, with no fill, no outline and no shape. The
  caller sets the font and colour; the style supplies a rectangular hit region, 44 pt tall in
  general and the logger's 56 pt where a missed tap costs a set, and the press, which sinks the
  label to 0.97 and dims it to 80% on `Motion.press` with Reduce Motion dropping the scale. Under
  Increase Contrast or Button Shapes it draws the `controlEdge` outline and a little padding to
  sit inside it, so a control that looks like plain text still looks like one to anyone who asked.
  It dims to 40% when disabled only if the caller says so. The live session's machine line, gym
  line, "Add set", "Warm-up", rest, "Add movement", load-step and rest-bar controls are inline
  controls, and `HeaderIconStyle.bare` is the same idea for the header's glyphs. An unset gym or
  machine ("Set gym", "Choose machine") reads in full `chalk`, an invitation; a set one reads in
  `chalkDim` with a chevron. With no gym there are no machines to list, but the card's machine line
  is still drawn: "Choose machine" with "Set a gym first" in `chalkDim` beside it, spoken as "No
  machine recorded", and a tap opens the choice of gym. Hiding it would leave a lifter who left the
  gym blank at setup never meeting per-machine history until the receipt says none was recorded.
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
  uses it. A banner and a non-interactive
  `CertaintyCapsule` carry no stroke: the words, the symbol and the tinted surface identify the
  kind or level. An interactive `CertaintyBadge` is identified by its symbol and word, and wears
  an outline only under Increase Contrast or Button Shapes. Its `.language` style, which the live
  session uses, is the same control as a phrase with an info glyph and no tint, and the disclosure it
  opens restates the level as a chalk heading instead of a capsule; the other screens keep the
  capsule until they are rebuilt. A message-only banner speaks only its message to
  VoiceOver, as it does today; speaking the kind is recorded for the accessibility pass. A
  picker's error banner (gym, machine and exercise pickers) is pinned above the list at ordinary
  sizes and moves into the scrolling content at accessibility sizes, so a tall banner can never
  push the list off screen; the banner is never height-capped.
- **Arrival** (`hardsetArrival()`): the one public modifier that carries a message's
  insertion-only opacity reveal on `Motion.reveal`, with no animated transaction. The pickers and
  the name entry sheet and the session use it; the root screens adopt it when they are rebuilt.
- **Ledger** (`StatLedger`): a row of labelled figures separated by hairlines, used for session
  totals. Its values are `figureXL`, 44 pt, because each is a count or a sum of what was logged. The
  columns are the width of their figures, so a five-digit volume has room. Three figures take one
  line, with dividers, if they fit. Four, the ledger once warm-ups are logged, do not fit beside a
  four-digit volume on any phone, so they are always two to a line in aligned columns with no
  dividers, and the layout does not change as the volume crosses 1,000; three too wide for the line
  fall to the same two columns. At accessibility sizes each takes a line. An item marked `isEstimate` is drawn at `readout`. A ledger may lead with one
  monument, above the columns, when its screen has one, and says which kind it is (`MonumentKind`):
  `.subject`, 88 pt, where the screen's subject is the number, and `.aside`, 72 pt, where it is an
  action. Train's last-workout section leads with its volume as an aside and leaves sets and reps in
  the columns, and with no volume, as in a bodyweight session, it has no monument.
- **Empty and loading states**: explain what is missing and what to do next; loading is a quiet line
  of text, not a spinner. An empty slot is drawn with a dashed outline, the app's one mark for
  "nothing here yet": the empty-state socket, the workout editor's "Add movement" slot and the rule
  under "Not evaluated". The live session draws none: its "Add movement" is an inline control, a
  warm-up's ordinal is a plain "W", and an incomplete set's log control is an empty square. A screen
  that has dropped its containers asks `HardsetEmptyState` for `.quiet`, the same symbol and words
  with no socket, and Train's "No sessions yet" is plain left-aligned type with no symbol.
- **Tags versus chips**: a chip can be tapped and is a raised fill with an action label; a tag
  (modality, "Recent", "Custom", an untrained muscle) is flat `steelRaised`, so it never imitates a
  control. At
  accessibility sizes a wrapping tag, assumption chip or certainty capsule takes the control radius
  instead of a capsule, so wrapped text stays inside its outline.
- **Library** (`LibraryView`, `LibraryScreen`): every movement grouped by body part, with a
  ledger of the count in each at the bottom. The list is the picker's movements and the ones a workout
  import created (`CatalogSeeder.libraryExercises`), because the Library is the only place an imported
  movement's body part and equipment can be set; the picker, search and recent list still leave imported
  movements out, however they are tagged, so nobody logs today's sets against an imported copy.
  Movements with no body part come first under the header "Needs a body part", whose
  `exclamationmark.triangle` is the one `warning` mark and whose words are `chalk`, because until one is
  tagged its sets count toward no muscle. Nothing is boxed: a row is type under a hairline, the name in
  `headline` and what it trains in `provenance`, with its equipment and whose it is as plain `caption`
  words in `chalkDim` at the trailing edge, or under the name at accessibility sizes. A row for the
  lifter's own movement is a 56 pt button that ends in a chevron, which is what says it opens the editor,
  and says "Custom", or "Imported" for one a workout import created; a curated movement is a plain row
  with no chevron and no "Curated" word on screen, because a word repeated on every row says nothing,
  and its spoken label still says "Curated". A
  movement that is not curated and has no equipment on record says "Equipment not set" after its
  muscles in `provenance`, so the absence of a mark is not the only sign. A curated row does
  not open the editor, so nothing that looks tappable does nothing. The footer lists every body part, zeros
  included, in `figure` against `chalkDim` for a zero, each row under a `hairline`. It reads what is
  there: loading is a quiet line, a failed read says so in `HardsetEmptyState` with the quiet style, and
  neither draws an empty library. The one accent on the screen is the "New movement" plus in the bar,
  which is the screen's primary action. It adds no token and no motion.
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
  An imported movement opens the same sheet with two differences. Its name is plain text with a
  `caption` saying why it stays (a later import finds the movement by that name, so renaming it would
  start a second one), and Save says its imported sets will count toward the muscles in Volume. Any
  movement with no equipment on record, imported or not, opens with no equipment chip selected and a
  `caption` under "Equipment" saying that no max is estimated until the lifter says what the load is.
  Saving without choosing leaves the equipment as it was, so naming a body part never declares
  equipment; only a chip the lifter taps does.
- **Train start screen** (`HardsetRootView.startView`, `WorkoutCardsView`): nothing on it is boxed.
  Top to bottom: the header, with Library and Settings as `.bare` header glyphs and the gym as the
  header's own line; the saved workouts; the empty "Start workout", its sentence, and the two
  controls that follow it; then, under a hairline, the last workout. The gym line is the live
  session's gym chip: a pin, "Training at" and the name in `chalkDim`, and a chevron that says it
  opens the list, wrapping rather than truncating a long name; with no gym it is "Add a gym to track machines" in full `chalk` with a plus and its
  reason in `caption` under it, an invitation and not a warning. Its accessible name is unchanged,
  and Voice Control also answers to "Change gym". The last workout is a section label and one
  button: the workout's title (or its date) in `headline`, its length in `figure` with a clock, said
  as a length and never as a clock face ("2 min", "1 h 44 min", nothing under a minute, so "1:44" is
  never read as an hour and forty-four minutes; History says it the same way), a
  chevron, the volume as the screen's one monument (`monumentAside`, 72 pt, its unit word "lb volume"
  beside the figure, as History says "800 lb volume", and "Weight × reps" under it, so a bare "800 lb"
  is never read as a lift:
  the subject of this screen is starting a workout, so the number sits beside the action and does not outrank it)
  over a `StatLedger` of working sets and reps at `figureXL`, and the movements in `label` and
  `chalkDim`. With no volume, as in a bodyweight session, there is no monument and the ledger is
  the counts. It is a 56 pt `InlineControlStyle` region that opens the receipt, and beneath it, as
  its own control and never inside it, an inline "Worked from" opens the sets the volume was summed
  from. With no finished workout, "No sessions yet" is left-aligned type under the same hairline and no symbol. The one
  accent is the primary Start: the up-next workout's when one is saved, the empty "Start workout"
  otherwise. It adds no token and no motion.
- **Workout cards** (`WorkoutCardsView`, `WorkoutCard`): the Train tab's saved workouts, drawn without
  cards. The workout done longest ago, or never, is the up-next workout, type on the canvas, with its
  name in `title`, "3 movements" in `label` and a context line in `provenance`: "Up next · last done 4
  days ago · beat 4 of 6 last time". Its one `primary` 56 pt button reads "Start" and the name;
  starting is a single tap with no confirmation, because the lifter is standing at a machine. Under it
  is "Edit", an inline control in `chalkDim`. It is the screen's one primary button: while a saved
  workout is shown, the empty "Start workout" below it steps down to `secondary`. The other workouts
  are rows under a "Your workouts" label, each under a hairline: the name in `headline` and its line
  in `provenance`, with "Start" in `chalk` and "Edit" in `chalkDim` as inline controls at the
  trailing edge. The empty "Start workout" follows the workouts, and under it are the inline controls
  "Repeat last workout", only when a finished workout of the lifter's own exists (an imported one does
  not count), and "New saved workout", which opens the plan editor and starts nothing. "Repeat" keeps
  the logger's 56 pt region, because it starts a workout; "New saved workout" is 44 pt. They sit
  below the start and never above it, and the editor's control says it makes a saved workout, so a
  lifter in a hurry cannot take it for starting one (`WorkoutCardActions`). Nothing is claimed that
  was not measured: "beat 4 of 6" appears only when something was compared, and only on the workout
  it belongs to. The order is the rotation, never a schedule or a streak. A workout counts as done,
  for the rotation, the last-done day, "last time" and "Repeat last workout" alike, only when it
  finished with a working set: an accidental Start finished with nothing logged,
  or with warm-ups only, leaves all of them where they were. At accessibility sizes a row's controls
  stack under its text. It adds no token and no motion.
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
  that have no body part last under a header whose `warning` glyph is its only colour. Nothing is boxed:
  a row is type on the canvas under a hairline, a button of 56 pt or more. It reads the
  movement in `headline`, its machine in `provenance`, a small `chalkDim` sparkline of the last dozen
  sessions with its newest session a `chalk` point (hidden from VoiceOver and dropped at accessibility
  sizes), and one sentence that names its
  metric: "Estimated max +8% in 6 weeks", in `provenance` and `chalkDim` with the signed percent alone
  in `figure` and `chalk`, so the number is what the eye reads first and the sentence stays whole
  (`ProgressBoardView.sentence` finds the figure inside `ProgressCopy`'s own words; it never composes
  them), or, in `chalkDim`, "Estimated max · no 6-week comparison" with
  the history the movement does have ("4 sessions over 3 weeks. A comparison needs a session 5 to 7
  weeks before the latest.") when no session sits in that band. It never says "Not enough history":
  a movement trained every four weeks has plenty and only misses the band. The band is
  `ProgressTrendAnalyzer.comparisonBandDays`, and the words are written from it. When every claim behind
  the figure is a measured single, which estimates nothing, the metric is named "Max" and not
  "Estimated max" ("Max +5% in 6 weeks"), here, on the scorecard's gain and in their Worked from
  accounts alike (`ProgressTrendAnalyzer.isMeasured`); a change with a formula's estimate on either
  side stays "Estimated max". Beside every estimated-max figure sits its `CertaintyBadge` in the `.language`
  style, a phrase ("Moderate confidence" and an info glyph) under the sentence, as its own control beneath
  the row's button so it never nests inside it. A six-week change uses the weaker
  certainty of its two estimates. Imported history has its own series and says "Imported · machine
  not recorded" in the same `provenance` role. A movement with no equipment on record, which is every
  imported one until the lifter sets it in Library, shows its added-load reading with the sentence that
  its body's own load is unknown and, under it, "Equipment not set, so no max is estimated. Set it in
  Library, on the Train tab." (`ProgressCopy.equipmentNotSet`, also in the chart and spoken by VoiceOver).
  The estimated max appears once the lifter has declared equipment that has one, never before, and
  naming a body part declares nothing; a bodyweight movement gets none however it is declared.
  Imported history is never merged into what the lifter logged, so a lift can have two rows, and the
  split is stated rather than hidden (`ProgressBoard.sourceNotes`, in `provenance` and `chalkDim` as the
  last line of a row): an imported row says "Not combined with sets you log in Hardset, even for the same
  lift"; a movement with both an imported series and a logged one, which is what an import under the
  catalogue's own name makes, says on each row that the other is on its own row; and a logged row with no
  imported series of its own movement says nothing, because two names that look alike are not evidence
  of one lift and the app does not guess. Above the rows, in `caption`, the board says once why a lift
  can appear twice, whenever any row is imported. Under a movement's chart, one `caption` says an
  imported line is kept as its own series because an imported set records no machine. No merge action is
  offered: the two series would stay two rows either way, since an imported series has its own key, and
  moving sets between movements would rewrite history to draw the same chart. Machine and cable
  movements whose sets have no
  machine say "No machine recorded" there and in the chart legend. A movement with no record in its last
  three sessions says "No record in 3 sessions" in `chalk` beside a `warning` `pause.circle`, the glyph being
  the caveat's one mark, and no advice: the rule
  is only that none of those sessions set a record, and "stalled" would claim more about the lifter's
  body than the data knows. "Most
  improved · estimated max" at the top repeats three estimated-max gains, ordered by the confidence of
  the estimate first, then the size of the gain, with a movement that has no record in 3 sessions after
  one of the same confidence that has, and a `caption` under its label says so
  (`ProgressCopy.mostImprovedOrdering`), so a Low-confidence gain that also has no record in 3
  sessions is never on top while a better-supported gain sits
  below it; load and rep percentages stay in their own movement rows. Empty, it says "Log a workout and your progress
  shows up here"; loading is a quiet line and a failed read says so, never an empty board. A row that
  has a six-week change also draws a quiet "Worked from" control, `provenance` words in `chalkDim` and the
  glyph, beside its certainty phrase (under it at accessibility sizes), as its own control beneath the
  row's button. It opens the latest session, the baseline and everything left out (see Inspectable
  figures), and a failed read says so under that row's control. It adds no token and no motion.
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
  receipt here; a discarded workout, and one finished with no sets, have none to open. On the screen,
  the biggest gain carries a quiet "Worked from this gain" control beneath its line that opens this
  workout's sets, last time's and what was left out; the shared image never draws it. The receipt's
  own sets, the load and reps the lifter typed, are `figureXL` with the unit and the multiply sign
  as the quiet words between them, because they are measurements; the scorecard's headline stays
  `readout` and its estimated gain stays a sentence, so on the receipt too the estimates are the
  smaller figures. It has no monument. It adds no token and no motion.
- **Save as workout** (receipt): a `secondary` button under the share actions, offered for a workout with
  sets and not for an imported one, whose movements are kept apart from the catalogue's. It asks for a
  name in `NameEntrySheet`, builds the plan from the workout's movements in their order with the number
  of working sets logged, never counting warm-ups, and opens the workout editor on it as a new workout.
  Once saved, a neutral `info` banner says where it is. It adds no token and no motion.
- **Where the history lives** (receipt): a lifter who never opens Settings would never learn that a
  build with no iCloud sync keeps their history on one phone, so the receipt says it in one quiet
  line, in `caption` and `chalkDim`, under the share and save buttons: "Saved on this iPhone only.
  Deleting Hardset deletes your history, and Settings can export a copy." It is not a banner and not a
  modal. It appears only where it is true (`DataSafetyCopy.receiptNote(for:)` is `nil` for a build that
  syncs, and for a screen that does not know), it is drawn outside the receipt view so the shared image
  never carries it, and Settings still holds the whole warning. The launch view hands the sync status
  down through the environment. It adds no token and no motion.
- **Worked from** (`WorkedFromSheet`, `WorkedFromButton`, `WorkedFromAccount`): the one presentation behind
  every number that can say how it was made. An estimated max (the figure in a chart legend row), a muscle's
  count (the figure on a Volume row and on a map tile) and a record (the chart's star key, a receipt set's
  record and the scorecard's record line) each open the same sheet, in the `MethodologySheet` family: the
  figure in `readout` with how far to trust it and where it is from, the rule in `label`, then the sets that
  fed it and what was left out, each a line of `figure` over `provenance`. A line's standing is carried by a
  word and a symbol, a tick, a ring or a minus, and never by colour. Every set that did not count is a line
  under "Left out" with its reason, so nothing is silently missing. The account is derived in Core from the
  same inputs and through the same functions as the figure (`EstimateWorking`, `MuscleCountWorking`,
  `RecordWorking`), so the sheet does no arithmetic and cannot say what the figure did not do. The control is
  visible without a gesture: a glyph beside the figure, or a quiet "Worked from" button. It is never drawn on
  the shared receipt image. VoiceOver hears the account as one sentence on the header and each line as one
  sentence. Imported history keeps its split here as everywhere: an imported set is left out of a machine's
  line as imported history, an imported series has a working of its own and says what its records were
  compared with, and a movement a workout import created is marked as one on the lines that count it. Its
  confidence is whatever the estimator gives, and the account states the ladder from the estimator itself,
  so a formula's figure never reads higher than Moderate. A correction to a finished set shows in the
  working as it shows in the figure: a receipt's records are derived from the receipt as it is read now,
  found again by the set's id, and a chart's from the history as it is read now, so neither explains a
  record or an estimate from the figures before the correction. It adds no token and no motion.
- **History search and month jump** (`HistorySearch`, `HistorySearchBar`, `HistoryMonthJumpSheet`): under the
  History header, the app's own search field and, beside it, a round calendar header button. The field finds
  workouts by movement, machine or gym and says so in its prompt; typing waits for a pause before anything is
  read, and the results are the same month-grouped cards, opening the same receipt, with a subtitle that names
  the words ("7 workouts match “bench”, newest first"). A search that finds nothing is a `HardsetEmptyState`
  that names the words, "No workouts match “deadlift”", never a blank screen; one still being read says so in
  a quiet line, and one that failed says history is safe. VoiceOver is told what a search found, once per
  query, because the matches appear away from where focus is. The field sits in the one scrolling column every
  state shares, so a no-match never rebuilds it and the keyboard stays up; dragging the list puts it away. The
  calendar button opens a sheet of the months that hold workouts, under pinned year headings, each a
  `SelectionRow` with its workout count and the current month marked by the ring and check. Choosing one starts
  the list at that month's last workout and pages older; the subtitle says "from March 2023 and earlier", and a
  quiet "Back to latest workouts" button returns. A search spans all of history, so the calendar button is
  hidden while one is showing. It adds no token and no motion.
- **Selection** (`SelectionRow`, `SelectionCardButtonStyle`, `SelectionIndicator`): selected choices
  take the plate blue ring and `plateBlueSurface`, and the trailing indicator swaps an empty ring
  for a filled check, so the choice is carried by shape as well as colour. A pressed selection
  card scales to 0.97 (not 0.98, to match every other pressed face). A disabled selection row
  dims to 0.4, as a disabled control does; saved logger values are never dimmed.
- **Rest bar** (`RestBarView`): keeps its `ViewThatFits`: the countdown and the four controls (−15,
  +15, pause, skip) share one row when they fit, and otherwise the controls drop to their own
  single row under the countdown; the four controls never split across rows. The countdown is
  `countdown`, 64 pt, drawn directly on the panel in `chalk`, with no knurl tile; at accessibility
  sizes the words under it stack beneath the figure instead of wrapping beside it. The panel is opaque `steelRaised` at the
  card radius with `Elevation.floating` and no stroke, except the `hairline` border Increase
  Contrast gives every panel because the fill step is gone: glass was considered and refused,
  because the contrast gate cannot certify text on it. Controls are 56 pt
  inline controls identified by their label or glyph, with no key face; Increase Contrast and
  Button Shapes outline them. "Resting" and "Paused" are `chalkDim`, and the next rest's lengths
  are figures: the chosen one in `chalk` with a 2 pt rule under it, the others `chalkDim`.
  At accessibility sizes the bar is the countdown and the four controls and nothing else: "Resting",
  the movement and set it follows and the "Next rest" row (and its drag) are dropped, because pinned over
  the list they would cover the set being logged. The movement and set are still read aloud, the card's
  rest control still sets the next rest, and "Paused" is kept, since a frozen number is otherwise
  indistinguishable from a running one.
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
- **Pitch pages** (`PitchPage`, `PitchSetRowPage`, `PitchEstimatePage`, `PitchRestPage`): three
  pages with one anatomy, a `title` headline, two lines in `label` and one live element that is the
  real component, never a picture. "One tap per set" is a real set row prefilled from last time; its
  tap plays the log moment, the stamp and the one `clank`. "Honest numbers" is the engine's estimate for the
  same 60 kg set at 1, 3, 12 and 15 reps, so the badge walks high (the single, which is measured and
  the only High), moderate, low and not evaluated because `StrengthMath` says so. "Rest that keeps
  time" is the real rest bar over a `DemoRestTimer`,
  an in-memory timer with no alarm, whose controls give the selection haptic. The first-launch pager
  shows three short segments above the primary button, the active one `plateBlue` and the others
  `gaugeTrack`, sliding on `Motion.state`; like the segmented control's indicator it is one shape moved
  between two places inside its row. The segments are information (they say how much of the
  introduction is left, and "Page N of 3" says the same to VoiceOver), so they clear 3:1 and are
  never `hairline`. The gauge is not a control, and the accessibility audit's hit-area line on it is a
  false positive that is not suppressed.
- **Setup** (`SetupPage`): "Before your first set." Two selection rows for the unit, which edit the
  stored preference in place, and the gym: existing gyms as selection rows with one preselected, or
  for a new lifter one name field that may stay blank. A failed save stays on the page with the
  reason and the typed name kept.
- **Text entry** (`entryFieldChrome`): raised fill, control border, and a 2 pt plate blue ring that
  fades in on focus. Used by the search field and the name entry sheet. An input keeps its outline,
  because it is identified by its box.
- **Live session layout** (`SessionView`, `ExerciseSectionView`): no container around a movement.
  The page margin is `loose` and the only inset, a movement's header, rows and actions sit
  straight on the canvas, and movements are separated by `block` of space, each owning the space
  above it. The only hairlines are between two set rows and above the workout's totals, where
  they separate; the totals are a section label and a ledger with no card. The rest bar and the
  record notice are panels. The screen's contents are, top to bottom: the header, the gym line,
  the movements, one "Add movement" inline control, the totals and the finish control; nothing
  on it is a card except the stale-workout notice, which holds buttons.
- **Set row**: the figures are the content. Weight and reps are the `figureXL` role, 44 pt, the
  largest text on the card, tabular and set tight, in a 64 pt row, with a quiet multiply sign
  between them in `provenance` and `chalkDim`: weight ends at the sign and reps begin after it, so
  the sign is one axis down the list and the column header's unit and "Reps" sit over their figures.
  Reps have a fixed 64 pt column and the weight takes the rest, because weight is the wider figure
  and an equal split left "227.5" less than it needs; a long pound value such as `132.28` shrinks a
  little (floor 0.7) on a 375 pt phone and not on a 402 pt one. A row that carries its own unit
  labels, as the onboarding demo and the catalogue do, keeps the compact `readout` size and 56 pt
  row, since it has no column header and its labels need the width. The ordinal is small and dim
  (`caption`, `chalkDim`) in a fixed column with no tile behind it; a warm-up's is a plain "W", and
  at accessibility sizes it is spelled "Set 2" or "Warm-up". Last time is a small dim pair in its own
  fixed column. Nothing is boxed, tinted or outlined: there is no wash on a logged row, and a
  hairline exists only between two rows, inset past the ordinal column.
  Weight and reps have no box because the keypad is the input surface and the row is never a form.
  A figure still to be logged is dimmed to `chalkDim`, which clears 7:1 on every surface; once the
  set is logged it reads in full `chalk`. While the keypad types into a field its figure is `chalk`
  with a still caret after it and a 2 pt `chalk` underline, and nothing else changes; the caret does
  not blink. Each field's hit region is the row's 64 pt tall and its whole column wide,
  and the ordinal and last time are a button into the weight, so no part of the row left of the
  check is dead. Increase Contrast and Button Shapes bring the `controlEdge` outline back around an
  editable figure, so a boundary appears exactly where it was asked for.
  A saved figure is tappable too, and does what a figure that looks tappable should: it opens the
  keypad to correct it. The set stays saved while it is corrected: the figure on screen is the saved
  one until the correction has been written, the keypad says "Correcting" beside the set's name, and
  its last field offers Done and no "Log set", because there is nothing left to log. The correction
  is written when the keypad leaves that figure (Next, Done, another figure, the sheet going away),
  through the coordinator, which persists first and changes the row only after the write succeeds;
  a failed write leaves the saved figures and shows the failure. A field left empty, or typed back to
  what it held, writes nothing. A correction keeps the set's machine, its place and its save time,
  starts no rest and claims no record. A finished workout's set is corrected through the receipt,
  by the same operation and with downstream recomputed (see History). "Edit set" in the long-press
  menu and for VoiceOver does the same thing as tapping the weight, and "Undo log" still takes a
  set back.
  Nothing on a saved figure says it can be tapped, so two things say it in words. The movement's
  options menu, the visible "…" in the card's corner, opens with "Correct set": one entry when a
  single set is saved, a list naming each set by its figures ("Set 2 · 100 kg × 10") when several
  are, and each puts the keypad on that set's weight exactly as a tap does. It is another way to
  the same correction, not a second mechanism. And once, in a lifter's first workout, one quiet
  line at the bottom edge says "Tap a saved weight or reps to correct it." in `provenance` and
  `chalkDim` with an inline "Got it": not a modal, not a banner, no colour, the insertion-only
  reveal on `Motion.reveal` (instant under Reduce Motion), wrapped and with the dismissal below it
  at accessibility sizes. It is drawn only once a set is saved, only where a correction can be
  written, never over the keypad, an error or a new record.
  It is spent when it is drawn, not when it is dismissed (`HintPreferences`, a device preference),
  and opening a saved figure to correct it dismisses it too.
- **Set log control**: four states, never confused, each one SF Symbol of one weight and one size,
  about 30 pt inside the logger's whole 56 pt region: incomplete is an empty square in `controlEdge`
  (faint, and above the 3:1 floor for a graphic), ready is a checked square in `chalkDim`, next up is
  that square filled with `plateBlueFill`, the one saturated colour on the screen and only on the
  workout's primary action (every other loggable row is drawn as ready), and logged is a
  round `plateGreen` `checkmark.circle.fill`. A square logs a set and a circle is a set that is
  logged, so logged and next up differ by shape, not only by hue. Nothing is dashed, knurled or
  boxed, and a logged row has no tint. The stamp is the seal scaling in from 0.6 on `Motion.stamp`
  as the unlogged glyph fades out, and the one flourish on the screen, the contact of the log moment
  (see The log moment); with Reduce Motion it simply appears. At accessibility sizes the control also reads "Log set" or "Logged" in `chalk`, and
  VoiceOver hears "next to log" on the next-up row. Voice Control answers to "Set 2", "Log set 2",
  and, on the next-up row, "Log set".
- **Press feedback on self-drawn controls** (`HardsetPressStyle` and the set row's own styles): flat
  faces sink, everything else dims, and no press moves layout.
  - Flat faces (a raised fill: unselected chips, `AssumptionChip`, the header icon button, keys and
    secondary buttons) sink to `steelPressed` and scale to 0.97 (keys 0.96) on `Motion.press`. They never dim, so a boundary that is drawn survives a press. The header icon
    menu is the one exception: `HeaderIconMenu` is a `Menu`, not a `Button`, so it keeps its resting
    face, and its press feel is a device check. A selected chip swaps `plateBlueFill` to
    `plateBlueFillPressed`. A control's hit region is at least 44 by 44 pt, however compact its face.
  - Controls that draw their own fill and shape with no steel face (segments, the exercise-name
    link, every inline control, the dismiss glyph, the "Clear search" glyph, the certainty badge and
    the set row's weight and reps figures) sink to 0.97 and drop to 80% opacity on `Motion.press`,
    in place of a pressed fill.
  - The set log control draws its own fill and shape: the log control (ready and next up) dims and
    scales like other self-drawn controls; incomplete and logged show no press. Next up keeps its
    `plateBlueFill` while pressed.
  - Static surfaces take no press: tags, the empty-state socket, entry fields, banners, cards, the
    rest bar's panel, and a saved row's figures where the screen cannot correct a set. Tags never
    take a control's face, so a tag never imitates a control.
  - Reduce Motion drops the scale and keeps only the fill or opacity change. Disabled controls are
    never dimmed by a press style, so saved rows and inert titles keep full contrast.
- **Dated Last time** (set row header): when a movement's "Last time" column quotes sets saved on
  this machine, the card says when they were done in one quiet line under the machine chip, or under
  the name when there is no chip: "Last time 25 Oct · 2 weeks ago", or "Last time today" for sets
  logged today, in `provenance` and `chalkDim`. The date is the newest `completedAt` among the sets
  the column quotes, not the heaviest set, which can be years old. Borrowed history gets no second
  line: the existing "From another machine" badge takes the date into its context ("From another
  machine · 25 Oct · 2 weeks ago · Low confidence"). A movement with no prior, or a prior with no
  sets, draws nothing — never "never". It states what the row already relies on: no advice, no
  detraining model, no "you may be weaker", and no cutoff for a "long" gap. No icon, capsule, tap
  target or motion.
- **Target line** (set row): when a movement has a rep range and history on this exact machine, an
  unlogged row is prefilled with the double-progression target and says where it came from in `provenance`
  and `chalkDim`: "Target · One more rep than last time", "Top of your range; hold it", or "Every set hit
  the top of your range: add one step" (one plate, "assumed step", when the machine has no saved step).
  The "Last time" column still shows what last time was, so a target is never read as history. History
  borrowed from another machine gives no target and the prefill is as it always was. It adds no motion.
- **Beat mark** (set row): once a set is logged, a short mark under the values, in type with no
  capsule, fill or stroke, says how it compares with the same set last time on this machine, in the
  figures of the set: "+1 rep", "+2.5 kg", "+5 lb · +1 rep", never a bare "Beat". A win is `plateGreen`
  with an up arrow; a match is "Matched" in `chalkDim` with an equals sign, so neither is carried by
  colour alone. It hangs under the last-time column, which it speaks about. A set that fell short, a
  warm-up, a set with no partner and a set done on another machine show nothing. It arrives through
  `hardsetArrival()`, the insertion-only opacity reveal on `Motion.reveal`, so the row's height
  changes at once and nothing animates layout. The row's spoken label says it in the same words
  ("plus 1 rep on last time"). It adds no token and no motion beyond `Motion.reveal`.
- **Replaceable prefill**: when the keypad opens on a value the next key will replace, its display
  draws that value as selected text, the figure in `steel` knocked out of a solid `chalk` block,
  until the first edit. Once it is being typed the figure is `chalk` with a still caret after it,
  as in the row. Static; no motion, and no hue.
- **Button Shapes**: with the system setting on, every stroke-free control, `quiet` buttons
  included, wears the `controlEdge` outline, and the exercise name (the load-history link) is
  underlined.
- **Volume bars**: round-ended gauges, 4 pt tall and continuous, on a `hairline` ground, scaled to the
  week's own maximum, never to a target. Modelled muscles are solid `chalk`; muscles that are counted
  but not modelled are hollow (a `chalkDim` outline, no fill) and say so in words beside the name. The
  screen has no primary action, so the bars carry no accent. A row is the muscle's name in `label` and
  its count in `setEntry`, the certainty phrase tucked under the name as its subtitle and the bar closing
  it, with space between rows and no card, so the count is the biggest thing in the row. At accessibility
  sizes the name, the count and the phrase each take a line. The week's total is the screen's
  `monument`, 88 pt and stacked above its sentence at accessibility sizes, because it is the one
  figure here that is a count of what was logged, and an inline "Worked from" under it opens the sets it
  was counted from (`WorkingSetCountWorking`); the per-muscle counts are fractional credits, an
  adopted convention, so they stay in `setEntry`. The window
  controls "Earlier" and "Later" and "How sets are counted" are inline controls in `chalk`, with "Later"
  dimmed to 40% on the newest window; the two window controls stack one above the other when they
  cannot sit side by side, because a word that says what the control does is never truncated;
  "Muscle history" is a pinned row under a hairline, words and a chevron, a 56 pt control. It adds no
  token and no motion.
- **Certainty on a muscle's count**: the badge beside a weekly count is about the research, not the
  count: whether published studies of weekly sets reach that muscle at that many sets. It is moderate
  for the six modelled muscles up to about 25 fractional sets, low above that, and not evaluated for
  every other muscle, whose count is still shown. The rule is `VolumeAnalyzer.doseResponse` and
  nothing else: the volume rows draw the `MuscleCertaintyBadge`, so one count never carries two
  answers. The Volume rows draw it as the `.language` phrase under the muscle's name.
  `VolumeAnalyzer.certaintyMeaning` says what the badge is about, once, in words on the Volume screen
  and at the top of the "How sets are counted" disclosure; the disclosure's capsule is the best level
  a count can reach, `VolumeAnalyzer.bestCertainty`, and `certaintyScale` names where each level
  applies. Settings opens the same disclosure. No new token, no motion.
  Muscle history carries no badge at all: its figures cover four weeks or a lifetime, and a weekly
  curve placed on a longer total would be a claim the research does not make (D24 §3.2). It says once,
  above its rows, that the badge on Volume is about weekly sets and the sheet does not rate a
  four-week total.
- **Lower bounds and muscles the catalogue cannot train yet**: the caveat "Counts below are
  lower bounds" says the cause and the way out. The Volume screen draws it as a neutral note, a card
  with a small `warning` glyph and `chalk` words, as the stale-workout notice is drawn; it says
  sets on a movement with no muscles recorded count toward no muscle, and a movement the lifter made,
  or one a workout import created, gets its muscles from a body part set in Library on the Train tab.
  The muscles no built-in movement trains directly (`ExerciseCatalog.unauthoredDirectTokens`) are
  not listed under "Nothing logged for", where a zero would blame the lifter; the Volume screen names
  the ones with nothing credited in their own section, "Not counted directly yet", with the reason
  ("This is a gap in the catalogue, not in your training"). On Volume the muscles in both sections
  are plain `label` type in `chalkDim` joined by " · ", not tags, because nothing there can be tapped.
  Muscle history keeps the same distinctions per muscle: content debt says the catalogue's gap, an
  absence is a plain "No credited sets", and a history with unattributed sets makes it "No credited
  sets · N working sets have no body part recorded" with the Library route (D24 §3.4). No new token,
  no motion.
- **Charts**: nothing around the chart: the metric control, then the metric's name, what is plotted and
  its certainty as a `.language` phrase, the plot, a hairline and the legend sit straight on the canvas.
  One series per machine with its own colour and point symbol (the first is chalk, see the palette notes),
  a custom legend in app
  type, with equipment provenance allowed to wrap fully at accessibility sizes, and machine changes
  as 2 pt dashed `warning` rules. "Worked from these records" and "How this is measured" are inline
  controls in `chalk`. The chart opens on the estimated max,
  which rises when the lifter does more weight or more reps, with the heaviest load as the other
  segment; it opens on the heaviest load when no estimate can be made. A session that set a record is
  marked on its line with a `star.fill` in `plateYellow`, drawn over the machine's own point, and the
  legend says what the star means, so colour is never the only carrier. Beneath the chart a "Best at
  each weight" table lists, per machine, the most reps at each weight and the day they were first
  reached ("90 lb · 12 reps · Nov 4"): facts from the sets, so it carries no certainty badge.

## Accessibility floor

7:1 text contrast, a 3:1 boundary on every input and, under Increase Contrast or Button Shapes, on
every control, Dynamic Type through every role, adaptive layouts in
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
- Settings adds file import/export and a StoreKit Lifetime section. Reuse existing spacing, typography, buttons and semantic error colours.
  Import previews state unknown equipment and unit/time-zone interpretation before
  saving. Busy operations disable their controls and expose native progress.
- History opens a static receipt of committed sets. It states equipment provenance,
  caveats and same-machine record definitions. Native share sheets handle text and a
  deliberately dark image; long sessions retain text sharing rather than render an
  unbounded image. It adds no animation and responds to Dynamic Type. A finished set can be
  corrected as well as removed (ruling D13). "Correct a set" is in the receipt's toolbar menu, at the
  top where the receipt opens, and under "Correct this workout" at the bottom beside "Remove a
  set"; either turns on a mode in which each set shows a plate-blue pencil, and one mode is on at a
  time. The pencil opens `SetCorrectionSheet`: the movement and where it was done, one line saying
  that only the weight and reps change and that History, volume, records and progress, including how
  later workouts compare with this one, are recalculated from the corrected figures, both figures as
  56 pt controls, the logger's own `NumericPad`, and "Next" then "Save correction" as the only
  write. A figure the lifter did not touch is written back exactly as saved, so a lifter reading
  pounds who corrects only the reps does not rewrite the weight through a rounded conversion.
  The write keeps the set's id, machine, plan row, ordinal, warm-up flag, RPE and save time, and the
  workout's own start and finish, and is one transaction that persists before the receipt claims it:
  the receipt is re-read from storage, so what it shows is what is stored. Volume, records, load
  history and the Progress stall flag are derived from the stored sets on every read and nothing is
  cached beside them, so one write is the whole recomputation; the screens under the receipt
  re-read on `dataRevision`. A correction that makes a record is recorded as one, on the receipt
  and on the movement's chart, and one that takes a record away takes it off. Nothing celebrates: a
  neutral `info` banner says what the set now is and, when it changed, that it is now recorded as a
  best or no longer counts as a record, with no trophy, no tint and no haptic. A failed save keeps
  the sheet up with the figures typed, and Cancel and a swipe-down are blocked while figures are
  unsaved. Removing a set is unchanged, and its banner now says a removed set cannot be added back
  and points to correcting when the figures were the problem. Because records are replayed, a
  correction to an earlier workout can change a later workout's records when it changes the
  baseline they were judged against; that is the ledger being true and not a bug. It adds no token
  and no motion.
- Muscle history, the optional paid surface, uses the existing palette and fractional-set method,
  never target bands. It is one row per muscle in declaration order: last trained, the last four
  weeks against the four before, the lifetime total, and a twelve-week shape that includes zero so an
  untrained week sits on the floor. No figure is a monument and no figure carries the weekly certainty
  badge, because the badge is a placement on a weekly curve. Unknown attribution keeps the
  lower-bound mark and the Library route; counted-only and unauthored muscle tokens keep their own
  words. The shape is dropped at accessibility sizes, as the Progress sparkline is. No new colour,
  radius, typography or motion token is introduced.
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
