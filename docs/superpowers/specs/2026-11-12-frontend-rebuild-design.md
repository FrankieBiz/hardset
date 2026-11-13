# Hardset front-end rebuild: design

Date: 2026-11-12
Branch: `FrankieBiz/premium-frontend-design-plan`
Status: approved by the owner on 2026-11-12

## Intent

Rebuild everything the lifter sees and touches in Hardset to a hyper-premium standard, in the
spirit of the Apple Design Award winners whose opening screens feel seamless, physical and
animated, while staying usable on a gym floor by someone standing at a machine with an elevated
heart rate. The engine underneath (HardsetCore, HardsetStore, HardsetAlarm) is kept and is not
in scope. This document supersedes the feature-freeze direction recorded on 2026-11-11 for all
user-interface work; it does not reopen engine decisions.

The product's claim is calibrated honesty: every number carries a stated certainty and source,
and the interface says "not evaluated" rather than guessing. The rebuild must make that claim
feel like a luxury rather than a disclaimer.

## Why now

The owner's judgment on 2026-11-12: the current direction is "not there." The present interface
is correct, accessible and token-disciplined, but it reads as a specification sheet. It has no
first-run experience at all, no spatial continuity between screens, and a flat surface language
that never catches light. The owner is ready for a clean-slate rebuild of the front end, keeping
only the engine and the facts established in earlier work.

## Goals

1. A first launch that is memorable: a welcome the lifter plays with, a short pitch they interact
   with, and a guided tour over polished staged screens, ending with the lifter ready to log.
2. A single, confident visual language across every screen: dark, machined, quiet, with weights,
   reps and rest as the hero figures.
3. Motion that feels physical and continuous: things respond on touch-down, carry velocity, can
   be interrupted, and arrive from where they were triggered.
4. Gym-floor ergonomics preserved and improved: one tap per set, 56 pt logger targets, keypad
   without the system keyboard, machine picker recency-first, readable under glare.
5. Honesty UI preserved: certainty badge beside every estimated figure, "not evaluated" states,
   source disclosure one tap away.
6. Every screen verifiable: the existing macOS CI renders every screen to PNG in both
   appearances and runs Apple's accessibility audit; the rebuild keeps that lane green.

## Non-goals

- Changing HardsetCore or HardsetStore logic, schema, migrations, certainty math or records.
  Where a new screen needs data the engine does not expose, the design lists it as an engine
  ask, to be scheduled separately.
- Rebuilding the muscle taxonomy. The owner judges it weak and wants it rebuilt later; the
  Volume screen in this rebuild consumes whatever the current engine reports.
- Accounts, sign-in, cloud sync or any networked onboarding. Hardset is local-only on a personal
  team. The "login" moment of award-winning apps maps here to welcome and tour.
- Marketing-style content: no testimonials, pricing pitch or social proof inside the app. The
  Lifetime purchase section stays in Settings exactly as its current behaviour requires.
- Supporting iOS versions below 26.1 or any platform other than iPhone. The widget is kept but
  is not redesigned in this pass beyond adopting the new tokens.

## Anti-goals (what would make this a failure even if it ships)

- A beautiful app that is slower to log a set than today. Any new motion on the logging path
  that adds perceived latency is a defect.
- Animation for its own sake inside the daily app. Onboarding is the deliberate exception; the
  daily app moves only to answer a touch or show a change.
- A generic "dark mode fitness app": near-black canvas, one neon accent, gradient hero cards,
  rounded cards everywhere with the same shadow. The look must come from the subject.
- Colour-only meaning. Every state must also be carried by shape, word or symbol.
- Breaking the 7:1 text and 3:1 control contrast floor, Dynamic Type, Reduce Motion, Increase
  Contrast, Reduce Transparency, VoiceOver or Voice Control behaviour the current app has.
- Drift between the tour's staged screens and the real screens. The tour must be built from the
  real components with fixture data so it cannot lie about the product.

## Constraints

- Swift 6 language mode, strict concurrency, `@MainActor` by default in UI packages,
  `NonisolatedNonsendingByDefault`. HardsetUI components stay `@MainActor`.
- iOS 26.1 minimum, Xcode 26.x, SwiftUI only. Liquid Glass, `navigationTransition(.zoom)`,
  `matchedTransitionSource`, `keyframeAnimator`, `phaseAnimator`, `TextRenderer`, Metal shader
  effects (`colorEffect`, `layerEffect`, `distortionEffect`), `TimelineView`, `Canvas`,
  `scrollTransition`, CoreHaptics and `sensoryFeedback` are all available and may be used.
- No image asset catalogue in HardsetUI. Colours and dynamic styles resolve in Swift from the
  trait collection, with `nonisolated` `@Sendable` providers (a MainActor-isolated provider
  trapped when glass sampled a colour off the main thread). The app target's catalogue keeps only
  the icon, accent and launch colour.
- No third-party packages for UI or motion. SwiftUI springs and keyframes are sufficient, and
  the project's dependency surface stays GRDB and SQLiteData.
- No Linux build of SwiftUI. Linux can run `hardset-check parse`, Core and Store tests, and
  `Tools/check_contrast.py`; every visual claim is verified on the macOS CI lane
  (`.github/workflows/ios-ui.yml`) or a Mac, never asserted from Linux.
- `DESIGN.md` is the written source of truth for tokens; `Tools/check_contrast.py` parses the
  Swift token literals and must keep passing. A new token requires a `DESIGN.md` edit in the
  same change.
- Commits attributed to FrankieBiz <frankabisignano@gmail.com>, no AI attribution, no diagrams
  in docs or comments.

## The aesthetic: calibrated iron

One idea carries the whole visual language. Competition plates are colour-coded by mass, and
the colours are a calibration standard, not decoration: red 25 kg, blue 20 kg, yellow 15 kg,
green 10 kg, white 5 kg. Hardset's claim is calibrated honesty. So the app's colour is the colour
of calibrated plates, its surfaces are the materials of a serious gym (machined steel, black
rubber, chalk), and its typography is the stamped figure on a plate.

What this buys: the semantic colours the app already uses (success green, record gold, caveat
amber, failure red, action blue) stop being arbitrary and gain a story the lifter already knows.
The welcome animation, the certainty badge, the log stamp and the record banner all draw from
the same five plates. Nothing else in the app gets a hue.

### Palette

Dark appearance is the primary appearance and the one the owner wants. Light appearance is kept,
derived from the same roles, and verified to the same contrast floor, because Hardset already
supports it and the CI lane tests both. Values below are proposals; `Tools/check_contrast.py`
is the arbiter and the builder adjusts within the stated role until every pair passes 7:1 text
and 3:1 control.

| Role | Dark | Light | Meaning |
| --- | --- | --- | --- |
| `canvas` | `#0C0D10` | `#F6F6F8` | The floor. Rubber matting black with a cold cast. |
| `steel` | `#17181D` | `#FFFFFF` | Cards, rows, sheet content. The base material. |
| `steelRaised` | `#22242B` | `#EEEEF2` | Fields, keys, chips, secondary buttons. |
| `steelPressed` | `#1B1C22` | `#E6E6EB` | Momentary pressed fill, darker than `steelRaised` so a press sinks. |
| `edgeLight` | `#3A3D47` at 60% | `#FFFFFF` at 80% | A 1 pt top-edge highlight that makes a raised surface catch light. Decorative, never a boundary. |
| `edgeShadow` | `#000000` at 50% | `#000000` at 8% | A 1 pt bottom edge for the same purpose. |
| `hairline` | `#2E3039` | `#DEDEE4` | Decorative grouping rules. |
| `controlEdge` | `#7B7E8C` | `#7E8190` | Boundaries that identify a control (3:1 minimum). |
| `chalk` | `#F3F3F5` | `#141519` | Primary text and figures. |
| `chalkDim` | `#B6B8C3` | `#4B4D58` | Units, provenance, supporting text. |
| `plateBlue` | `#6FB7FF` | `#084A95` | Action, focus, selection, next-up. The 20 kg plate. |
| `plateBlueFill` | `#6FB7FF` | `#084A95` | Primary button fill. |
| `onPlateBlue` | `#0C0D10` | `#FFFFFF` | Text on the primary fill. |
| `plateBlueSurface` | `#10233A` | `#E3EFFC` | Selected and focused tint. |
| `plateGreen` | `#8FE3A3` | `#0F5A27` | Logged, high certainty. The 10 kg plate. |
| `plateGreenSurface` | `#122A1A` | `#E5F5EA` | Logged row tint. |
| `plateYellow` | `#FFD86B` | `#604A00` | Records, moderate certainty. The 15 kg plate. |
| `plateYellowSurface` | `#2B2410` | `#FBF3DA` | Record banner. |
| `plateRed` | `#FF9A9A` | `#9A1B24` | Failed writes. The 25 kg plate. |
| `plateRedSurface` | `#2E1516` | `#FBEAEA` | Error banner. |
| `warning` | `#FFB27A` | `#7A3A00` | Caveats, low certainty. Not a plate; it is the colour of a flagged lift, kept from the current system because it already reads correctly and passes. |
| `warningSurface` | `#2C1D12` | `#FCEEE3` | Caveat banner. |

Increased Contrast swaps `canvas` and `steel` to pure black and white, `chalk` to pure white and
black, and strengthens `chalkDim`, `plateBlue` and `controlEdge` exactly as the current system
does for its equivalents. Reduce Transparency replaces every glass material with `steelRaised`.

The accent moves from readout cyan to plate blue. This is a deliberate change: cyan reads as a
dashboard, plate blue reads as iron. The light-appearance blue is deep enough to pass 7:1 on
white; the builder verifies.

Certainty keeps its mapping: high is `plateGreen`, moderate `plateYellow`, low `warning`,
unevaluated `chalkDim`, always with word and symbol.

Chart series stay one per machine with distinct point symbols: `plateBlue`, chalk, lilac
`#B9A8FF` / `#5236B8`, rose `#FF9DD6` / `#9A1F66`, kept from the current system.

### Materials and depth

The current app is flat. The rebuild gives surfaces weight without noise:

- A raised surface (`steelRaised`) carries a 1 pt `edgeLight` on its top edge and a 1 pt
  `edgeShadow` on its bottom edge. This is the only "shadow" in the app; no soft drop shadows
  under cards.
- Keys on the keypad and the set-row fields are machined: raised fill, edge light, and on press
  they sink to `steelPressed` and lose the edge light, so the press reads as the key going down.
  A pressed face keeps its `controlEdge` outline, so the 3:1 boundary never disappears; only the
  edge light goes. In dark, `steelPressed` is darker than `steelRaised`, so the press sinks rather
  than lights up. An outlined face draws the edge light one hairline inside the control edge.
- The primary button has no edge gradient. The edge colours are pre-blended over steel and read
  wrong on plate blue, so primary is a solid `plateBlueFill` that swaps to
  `plateBlueFillPressed`.
- Liquid Glass is used for system chrome only: the tab bar, the live-workout bottom accessory,
  toolbars, and the tour's floating callout card. Content never sits on glass. The keypad, set
  rows and rest bar stay opaque, as today, because they are read under glare and sweat.
- Glass gets a `plateBlue` tint on the selected tab and the next-up control, nowhere else.
- One signature texture: a knurl. A `Canvas` pattern (`KnurlPattern`) draws a subtle diagonal
  crosshatch, because a Metal shader needs a resource bundle and this package has none. It is
  visible only on the welcome bar, the hero figure background of the rest countdown, and the
  logged-set seal. It never appears behind text that must be read.

### Typography

System fonts only. Every role is a Dynamic Type text style, as today, with two changes:

- The figure roles (`hero`, `readout`, `setEntry`, `figure`) remain SF Pro Condensed, semibold,
  tabular, and gain size-specific tracking: `hero` at -2% and `readout` at -1%, body at 0,
  `caption` and `unit` at +1%. The builder expresses this with `.tracking` scaled by the resolved
  point size, never a fixed value.
- `display` (tab screen headers) moves from bold expanded to semibold condensed at Large Title
  size with -2% tracking, so screen titles look like a stamped plate face and sit in the same
  family as the figures. Expanded width is retired.

The full role table in `DESIGN.md` stays as the authority, edited to these values.

### Spacing, radius, stroke, targets

Unchanged: spacing 2/4/8/12/16/24/32, radius `control` 10 and `card` 16, capsules only for chips
and badges, stroke 1 and 2, targets 44 pt general and 56 pt in the logger. These are correct and
the problem was never geometry.

### Motion

Two regimes, one vocabulary.

Daily app (the instrument). Motion answers a touch or shows a change, nothing else:

| Token | Value | Use |
| --- | --- | --- |
| `Motion.press` | 120 ms ease-out | Key and button sink on touch-down, never on release |
| `Motion.state` | spring, response 0.30, damping 1.0 | Selection, segment indicator, row state, sheet content settling |
| `Motion.reveal` | 280 ms ease-out, opacity only | Banners and inline confirmations appearing |
| `Motion.stamp` | spring, response 0.30, bounce 0.30 | The log check, and nothing else |
| `Motion.zoom` | system zoom transition | Opening a receipt, an exercise's progress, a machine's detail: the card the lifter tapped grows into the screen and shrinks back to the same card |
| `Motion.fling` | spring, response 0.35, damping 0.80, velocity from the gesture | Only on gesture release: the keypad sheet, the rest bar's drag, the tour's page swipe |

Rules carried from the apple-design foundations and already partly in `DESIGN.md`:

- Feedback on touch-down. Every self-drawn control sinks the instant it is touched.
- Springs start from the presentation value and inherit gesture velocity; nothing locks input
  while it moves.
- Enter and exit along the same path; sheets dismiss where they came from; the zoom returns to
  its source card.
- Only transform and opacity animate. Height is never animated; a logged row's tint is a layer
  whose opacity fades.
- Reduce Motion: springs and scale are dropped; fills and opacity change instantly or on
  `Motion.state`; the zoom becomes a cross-fade; the welcome bar is drawn already loaded and
  reacts to touch with opacity only.

Onboarding (the exception). Larger, orchestrated, physical motion is allowed because the lifter
is sitting down, once, and asked for it. Even here: every sequence is interruptible by a tap or
swipe, nothing loops slower than one cycle per three seconds, no full-screen parallax, and Reduce
Motion gets a still version with cross-fades.

### Haptics

A `Tokens.Haptic` namespace replaces inline calls, so every haptic has a name and a rule:

| Name | Pattern | When |
| --- | --- | --- |
| `clank` | CoreHaptics: sharp transient, intensity 1.0, sharpness 0.6, then a 40 ms low rumble | A plate landing on the welcome bar; the log stamp |
| `success` | system success | The log tap only (the stamp plays `clank` then `success`) |
| `error` | system error | Every failed command, including repeats |
| `selection` | system selection | Machine step, rest −15/+15/pause/skip, tour page landing |
| `warning` | system warning | A rest that ran out with no alarm to mark it |

Pickers, the unit switch and selection rows stay silent, as today.

## First launch

Shown once, gated by an `@AppStorage("hardset.onboardingVersion")` integer so a future redesign
can show it again. An existing install with history sees the welcome, pitch and tour on update
(the owner wants to see it), but its Setup page is pre-filled from what exists: the stored unit
is preselected and existing gyms appear as selection rows instead of an empty "Add gym" field,
so nothing is duplicated. Replayable from Settings under "Show the tour again." Every screen has a
visible "Skip" in the top trailing corner from the second screen onward; skipping from any point
lands on the same setup screen so no lifter misses units and gym.

The sequence is a horizontal pager built on `TabView(.page)` with the index hidden, driven by a
single `OnboardingModel` so the builder can test every state without the pager. Pages are:
Welcome, three Pitch pages, Tour, Setup. Pager swipes are allowed everywhere except on the
welcome bar's hit region, which owns the horizontal drag.

### Screen 1: Welcome

Canvas is `canvas`. In the upper third, the wordmark "Hardset" in `display`, and beneath it one
line in `chalkDim`: "A calibrated log for the lifts you actually do." Nothing else above the
bar.

The middle of the screen is the bar: a horizontal Olympic bar drawn in SwiftUI (`Canvas` for
the shaft with a chrome gradient and the knurl shader, shapes for the sleeves and collars),
seen side-on. Five plates rest below it in a tray, drawn as rounded rectangles seen edge-on with
their plate colour and a white mass stamp ("25", "20", "15", "10", "5"), each a 56 pt target.

Interaction: tap or drag a plate and it rises to the sleeve with `Motion.fling`, inheriting the
drag velocity, and lands with `clank`. Plates stack outward in the order chosen. The bar shaft
bends a few points in the middle in proportion to total mass (a `keyframeAnimator` on a
quadratic control point) and settles with a critically damped spring. Dragging a loaded plate
off returns it to the tray. The running total updates in `hero` beside the sleeve: "60 kg" or
"132.3 lb" per the locale guess, with `unit` in `chalkDim`. After the lifter has loaded at
least one plate, the subtitle under the wordmark changes to "That's a set logged in one tap."
with `Motion.reveal`.

If the lifter does nothing for four seconds, the app loads one 20 kg plate per side on its own,
with the same clank, so the screen demonstrates itself; any touch interrupts and hands control
to the lifter. Reduce Motion: the bar is drawn already loaded with 20s, tapping a plate swaps the
stack instantly with an opacity change, and `clank` still plays.

At the bottom, a single primary button, 56 pt, full width minus page margin: "Start". Pressing
it slides the page.

### Screens 2 to 4: Pitch

Three pages, each with the same anatomy so they read as one set: a headline in `title`, two
lines in `label`, and one interactive element that is the real component with fixture data.
Each page's element is live, not an image.

Pitch 1, "One tap per set." The element is a real `SetRowView` for "Chest press", prefilled
from a prior performance of 60 kg for 10. The row's next-up check is in `plateBlue`. Tapping
it logs the set: the stamp animation, `clank` and `success`, the row settling onto
`plateGreenSurface`. A second row appears beneath with the next prefill. The copy: "Weight and
reps are already filled in from last time. If the set went as planned, one tap logs it."

Pitch 2, "Honest numbers." The element is a `readout` figure for an estimated one-rep max with
a live `CertaintyBadge`, and beneath it a `HardsetSegmentedControl` with four segments showing
the same 60 kg set at "3 reps", "8 reps", "15 reps" and "25 reps". The engine's real rule drives
the badge (`StrengthMath`: certainty is high at low reps, falls past six, and becomes
unevaluated beyond the estimable ceiling), so the segments walk high, moderate, low,
unevaluated, and the figure itself is computed by the engine, not typed into the fixture. The
one-line provenance text under it is the engine's own wording. The copy: "Every estimate says
how sure it is. When Hardset can't tell, it says so instead of guessing."

Pitch 3, "Rest that keeps time." The element is a real `RestBarView` counting down from 90
seconds, with −15, +15, pause and skip live and giving `selection` haptics. The copy: "Rest runs
as an alarm, so it finishes on time even if the phone is in your pocket."

Each page has "Next" as a primary button and the pager dots are replaced by three short
`hairline` segments above the button, the active one in `plateBlue`, sliding on `Motion.state`.

### Screen 5: Tour

One page that hosts a staged phone. The staged phone is a `ScaledPhoneFrame`: a rounded
rectangle in `steel` with an `edgeLight`, sized to about 78% of the screen width, containing a
real root view rendered from `TourFixtures` (an in-memory environment with a sample gym,
"Downtown", three machines, a live session with two exercises and three logged sets, one record,
seven days of volume and twelve sessions of history). The staged phone is interactive only where
a step says so; elsewhere a transparent overlay swallows touches so the lifter cannot wander.

Steps, each with a callout card on glass anchored to the highlighted control, a spotlight
cutout (a `canvas` scrim at 70% with a rounded-rectangle hole that moves between targets with
`Motion.state` via `matchedGeometryEffect`), a one-line explanation, and "Next":

1. Train tab, start screen: "Your last workout is one tap from repeating."
2. Live session, set row: "Weight, reps, log. The check is the only thing you need to hit."
   This step is interactive: the lifter must tap the check to continue; the step's "Next" is
   hidden until they do.
3. Live session, keypad: "Tap a figure to change it. The keypad never hides the row."
4. Live session, rest bar: "Rest starts when you log a set, and you can nudge it."
5. Machine picker: "The machine in front of you is at the top. Each machine keeps its own
   history."
6. Volume tab: "Sets per muscle this week, counted from what you logged, scaled to your own
   week."
7. History tab and receipt: "Every session is a receipt you can share."
8. Settings: "Units, gyms, export, and the tour again, all here."

A "Skip tour" link sits under "Next" throughout. The step counter reads "3 of 8" in `caption`.

### Screen 6: Setup

Headline: "Before your first set." Two choices on `SelectionRow`s:

- Units: "Kilograms" or "Pounds", preselected from the locale guess the app already makes
  (`hardset.useImperial`).
- Gym: a `HardsetSearchField` name entry with "Add gym" beneath, prefilled empty with the
  placeholder "Where do you train?"; the lifter may leave it blank, in which case the app keeps
  today's "Not recorded" behaviour.

Primary button: "Start logging". It sets the onboarding version, saves the choices through the
existing stores (`@AppStorage` for units, `GymStore` for the gym) and transitions to the root
with a cross-fade, never a push, so the app does not appear to be another onboarding page.

## The app

### Structure

Three tabs stay: Train, Volume, History. Settings stays a sheet reachable from every tab
header. The live workout stays non-modal with the bottom accessory above the tab bar. This
structure is right; the rebuild changes how it looks and moves, not where things are.

The tab bar and bottom accessory are Liquid Glass tinted `plateBlue` on the selected item. The
accessory shows the current exercise name in `headline`, the rest countdown in `figure` when
rest is running, and nothing else.

### Train tab, no workout

`ScreenHeader` "Train" with the context line stating today's date and the chosen gym. Below:

- The last workout as a hero card: date, the gym, a `StatLedger` of sets, reps and volume, and
  the first three exercise names. Tapping it zooms (`Motion.zoom`) into its receipt.
- "Start workout" as the 56 pt primary button, and "Repeat last workout" as a secondary button
  beneath it when a last workout exists. (Repeat requires an engine ask; see below.)
- The gym chip under the header; tapping opens the gym picker as a sheet from the chip.

Empty state when there is no history: the dashed empty-state socket with "No sessions yet.
Start a workout and your last one will live here."

### Live session

The single most important screen. The layout stays an exercise list of set rows with the keypad
and rest bar; the rebuild changes these things:

- Exercise header: the exercise name in `title`, the machine chip and gym chip beneath, the
  progress ("2 of 4 sets") in `figure`, and a menu. At accessibility sizes progress and menu
  move below the name, as today.
- Set rows: 56 pt, machined fields (raised, edge light) for weight and reps, each in `setEntry`,
  with the unit in `unit`. The log control keeps its four states (incomplete dashed, ready
  outline, next-up filled, logged seal), with next-up in `plateBlue` and the seal in
  `plateGreen` over the knurl texture.
- The keypad opens as a sheet from the tapped field with `Motion.fling`, stays up across Next
  between weight and reps, and shows the replaceable prefill as selected text on
  `plateBlueSurface`. Keys are machined and sink on touch-down. Quick steps (−/+ by the
  machine increment) sit above the digits.
- The rest bar is opaque, pinned above the accessory, with the countdown in `hero` over the
  knurl texture at 8% opacity and the four controls in a row. It drags up with `Motion.fling`
  to reveal duration choices and drags down to dismiss them.
- Logging a set plays the stamp, `clank`, `success`, and starts rest automatically at the
  movement's last chosen duration. The current product starts rest only from an explicit
  duration choice; this rebuild changes that, because auto rest was already planned in the
  2026-11-11 roadmap and a second tap after every set contradicts "one tap per set". The
  explicit chooser remains: a movement with no duration yet asks once, the rest bar's drag-up
  changes the duration for the next set, and the durable rest state and retry banner behave
  exactly as today. Nothing else on the screen moves.
- "Finish" lives in the header menu and in the bottom accessory on other tabs. Finishing
  zooms into the receipt.

### Receipt

Opened by zoom from a history row, the last-workout card or Finish. A static receipt: date, gym,
per-exercise sets with machine provenance, records with their definition, caveats, and share
actions (text and the dark image) as today. Corrections (remove a set, discard) through native
alerts, as today.

### Volume tab

`ScreenHeader` "Volume" with the week range as context. Square-ended gauges per muscle scaled
to the week's own maximum, solid `plateBlue` for modelled muscles and hollow for counted-only,
with the words beside the bar. The muscle map sheet keeps its two-column layout. A methodology
link under the list. The taxonomy behind this screen is out of scope and will change later;
the screen must therefore depend only on `MuscleVolumeReport` and not on muscle names being
stable.

Certainty on this screen: the current view hard-codes a moderate badge for the whole report
(`VolumeReportView.swift:184`), which the engine does not assert. The rebuild removes the
report-level badge. Each modelled muscle shows the certainty its `doseResponse` position
carries; a counted-only muscle shows "Not evaluated" with the lower-bound caveat. No new engine
work is required for this.

### History tab

`ScreenHeader` "History". Sessions as rows grouped by month with a `StatLedger` per row.
Tapping zooms into the receipt. The exercise progress screen (one movement's load chart with
machine changes as dashed `warning` rules and a custom legend) is reached from the receipt and
keeps its chart series rules.

### Settings sheet

Sections: Units, Gyms (push to management), Data (export, import with preview), Apple Health,
Lifetime, Tour ("Show the tour again"), About (methodology disclosures). All rows on `steel`
with hairlines; buttons per role. No new behaviour beyond the tour replay.

### Startup

While the database opens and migrates, the canvas shows the wordmark and a quiet status line
(`HardsetLoadingState`), never a spinner. On failure, `HardsetEmptyState` with "Try again" in
the primary style. Onboarding is evaluated only after the root is ready, so a lifter never sees
the tour over a half-built app.

## Component kit

HardsetUI is rebuilt as a kit in which every component has a preview with every state, and the
snapshot test renders the whole kit. The kit:

- `Tokens` (Color, Text, Spacing, Radius, Stroke, Motion, Haptic) and the `swatch` resolver.
- `Machined` surface modifiers: `.machinedRaised()`, `.machinedPressed()`, `.knurl(opacity:)`.
- `HardsetButtonStyle` (primary, secondary, quiet, destructive; logger and regular sizes),
  `HardsetKeyStyle`, `HardsetPressStyle`.
- `ScreenHeader`, `HeaderIconButton`, `HeaderIconMenu`, `SectionLabel`, `HardsetChip`,
  `HardsetTag`, `HardsetSegmentedControl`, `StatLedger`, `HardsetBanner`, `HardsetLoadingState`,
  `HardsetEmptyState`, `HardsetSearchField`, `SelectionRow`, `SelectionIndicator`.
- `CertaintyBadge`, `AssumptionChip`, `UnevaluatedReadout`, `MethodologySheet`.
- `SetRowView`, `ExerciseSectionView`, `NumericPad`, `RestBarView`, `LoadStepSheet`,
  `NameEntrySheet`, `MachinePickerView`, `GymPickerView`, `ExercisePickerView`.
- `SessionView`, `HistoryView`, `WorkoutReceiptView`, `VolumeReportView`, `MuscleHeatmapView`,
  `ProgressionChartView`.
- Onboarding: `WelcomeBarView`, `PlateTray`, `PitchPage`, `TourStage`, `ScaledPhoneFrame`,
  `SpotlightOverlay`, `CalloutCard`, `SetupPage`, `OnboardingFlow`.
- `TourFixtures`: the staged in-memory environment, also used by snapshot tests.

Behaviour that must survive the rewrite even though no screen section above names it: the rest
recovery failure banner above every tab and its blocking of timer commands, gym and machine
management (rename, merge, archive, their alerts and retry), the machine load-step editor,
Apple Health settings, data import preview and export, the Lifetime restore action, and the root
readiness gating in `WorkoutRootModel`. These are rebuilt on the kit, not dropped.

What is deleted: every existing view in HardsetUI and HardsetFeature is replaced. The builder
may keep a file where its body survives the new design unchanged, but the default is to rewrite.
`DesignTokens.swift` is rewritten with the new roles. During phases 1 to 6 the old token names
survive as deprecated aliases of the nearest new role so the existing screens, the widget and the
macOS lane keep building while each screen is replaced; phase 7 deletes the aliases, and the
build failing at that point is the proof that no old screen survived. Tests in `HardsetUISnapshotTests` and `HardsetUITests`
are rewritten against the new screens; Core and Store tests are untouched.

## Engine asks (not built in this pass, listed for scheduling)

1. Repeat last workout: a `SessionCoordinator` entry point that starts a session from a prior
   session's plan. Until it exists, the Train tab's secondary button is omitted.
2. The record-comparison certainty bug (`PersonalRecords.swift`, noted in the 2026-11-11
   review) is engine-side; the new screens show whatever the engine says and must not paper
   over it.

Not an engine ask: `TourFixtures` needs no new Core API. `ExerciseLogState`, `PersonalRecord`,
`MuscleVolumeReport` and `SessionSummary` have public initialisers, and the existing snapshot
suite already renders the real root view from an in-memory migrated database queue
(`ScreenSnapshotTests.swift`), which is the basis for the fixtures.

## Verification

Linux, every change: `hardset-check parse`, `make check` (Core, Store, contrast, project
generation). The generator must produce identical project and scheme files for any file added
to HardsetUI or HardsetFeature, which means new files are registered through the generator,
never by hand.

macOS CI, every push: the package snapshot tests render every component state and every staged
screen to PNG in dark, light and Increase Contrast; `HardsetUITests` drives the real app through
onboarding, a full workout and the tabs on an iPhone 17 simulator, saves system-composited
screenshots, and runs `performAccessibilityAudit` on each screen. The onboarding journey is
added to that test. Glass is only verifiable in the real-app screenshots.

Physical device, owner: glare, sweat, one-handed reach to the log control, the welcome bar's
feel, and haptic character. These cannot be claimed from CI and the plan leaves them as owner
checks with a checklist.

## Delivery

Phases are sequential because each depends on the previous one's kit. Each phase ends green on
Linux and on the macOS lane, is committed on the feature branch, and is reviewed from its
rendered PNGs before the next begins.

1. Design system v2: `DesignTokens.swift`, `DESIGN.md`, `check_contrast.py` expectations,
   machined surfaces, knurl shader, haptic namespace, motion tokens. Preview catalogue and
   snapshot of every token and primitive.
2. Component kit: every component above, each with an all-states preview and snapshot.
3. Fixtures and staged screens: `TourFixtures`, `ScaledPhoneFrame`, every screen rendered from
   fixtures and snapshotted.
4. Onboarding: welcome bar, pitch pages, tour, setup, the gating and replay, the UI test.
5. Live session and keypad rebuilt on the kit with the real coordinator.
6. Train, History, Receipt, Volume, Progress, Settings rebuilt on the kit.
7. Polish pass from the rendered PNGs and the owner's device checklist; `DESIGN.md` final.

## Left to the builder

- Exact spring and keyframe values inside the stated tokens, tuned on a Mac with the rendered
  frames and, where possible, a simulator recording.
- The bar and plate geometry, chrome gradient stops, knurl shader parameters, and the bend
  function; the constraint is that it reads as an Olympic bar side-on at a glance and stays
  under 2 ms per frame on an iPhone 15-class device.
- How the spotlight hole is cut (a `mask` with an inverted rounded rectangle is the expected
  route) and how callouts avoid the safe areas.
- The pitch pages' exact copy, within the voice: plain verbs, sentence case, no selling.
- File layout inside HardsetUI and HardsetFeature, and the order of component work inside a
  phase.
- Which existing views, if any, survive unchanged.

## Decisions recorded from the conversation

- Onboarding is one-time (with replay from Settings), and the daily app stays the calibrated
  instrument; onboarding is the deliberate motion exception. (Owner.)
- The tour runs over polished staged screens with sample data, not the lifter's real empty
  app. (Owner.)
- The engine, data and math stay; the taxonomy is weak and will be rebuilt in a later pass,
  outside this plan. (Owner.)
- Most of the existing front end may be deleted. (Owner.)
- Calibrated plates as the visual idea, plate blue replacing cyan, machined surfaces, knurl
  texture, condensed display type, glass for chrome only, no third-party motion library. (My
  calls, open to change.)
- A Setup page with units and gym at the end of onboarding, and skip from any page landing on
  Setup. (My call.)
- Three tabs, non-modal workout and Settings as a sheet kept as-is. (My call, since the owner
  did not object to the structure, only the feel.)
- Rest starts automatically when a set is logged, with the explicit chooser kept for a
  movement's first rest and for changing the duration. (Settled 2026-11-12: the owner
  delegated the call; this reverses the earlier explicit-choice decision.)
- Deprecated token aliases during the rebuild, deleted in the final phase. Pitch 2 driven by the
  engine's real reps-based certainty rule. Volume report badge replaced by per-muscle certainty.
  Existing installs see the tour but get a pre-filled Setup page. All existing behaviours listed
  under "Component kit" survive. (My calls, from the reviewer's questions.)
