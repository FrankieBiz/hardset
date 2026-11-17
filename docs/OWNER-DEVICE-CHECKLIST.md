# Owner's device checklist: the front-end rebuild

CI proves what a runner can: the app builds, every component and staged screen renders to PNG, and
the real app is driven through a workout and through the first launch with Apple's accessibility
audit on each screen. It cannot prove how something feels in the hand, or how glass reads over a
moving screen. These are the checks that remain, in the order a lifter meets them. Tick each on a
physical iPhone, in the gym lighting where it matters.

## First launch (delete the app, or use Settings, "Show the tour again")

- [ ] **Welcome bar.** Tap each plate: it rises and lands with a `clank` that feels like a plate
      meeting a bar, not a buzz. Throw a plate upward with a swipe. The bar droops a few degrees
      under load and settles without wobbling. Tapping a loaded plate returns it. Leave it alone for
      four seconds: it loads one 20 kg plate a side by itself, and a touch takes over at once.
- [ ] A horizontal swipe on the bar loads or unloads and never turns the page; a swipe anywhere
      else turns it.
- [ ] **Pitch pages.** The set row logs with a stamp, `clank` under `success`. The estimate's four
      segments read high, moderate, low, not evaluated. The rest bar counts down and −15, +15, pause
      and skip each answer with a selection tick.
- [ ] **Tour.** The staged phone is legible at its size and nothing is cropped. The callout card on
      glass stays readable over both a bright (light mode) and a dark staged screen, and never
      covers the control it points at. Step two lets only the staged check be tapped, and "Next"
      appears after it. The keypad, machine picker and Settings steps open inside the phone.
- [ ] **Setup.** On an install that already has a gym, the unit and the gym are preselected and no
      name field appears. On a fresh install a blank gym name starts logging.
- [ ] **Reduce Motion, VoiceOver and the largest Dynamic Type** each reach "Start logging".
- [ ] Settings, "Show the tour again" replays the tour without Setup and without touching the
      stored version.

## The daily app

- [ ] **Log tap.** `clank` under `success` is heavy once, not twice: if it reads as a double buzz,
      lower the clank's intensity in `ClankPlayer` before anything else.
- [ ] **Auto rest.** A movement you have chosen a rest for starts that rest when a working set is
      saved; a warm-up starts none; a movement with no remembered rest starts none and asks once.
- [ ] **Next rest.** The row under the rest bar and a drag up on the bar open the lengths, a drag
      down closes them, choosing one changes the next rest and not the running one.
- [ ] **Keypad** retargets in place between weight and reps, and its keys sink on touch-down.
- [ ] **Press feel** on the header icon menu (a `Menu` never reports a press, so it is device-only)
      and on the machined faces.
- [ ] **Glare and sweat.** Plate blue, the caption text and the certainty capsules stay legible at
      arm's length in daylight; the log control can be hit one-handed with a chalky thumb.
- [ ] **Volume.** Each muscle carries its own certainty; none speaks for the whole report.
- [ ] **Train.** The last-workout card opens its receipt. With no history the start screen says
      "No sessions yet".

## Decisions that are the owner's

- [ ] Under Increase Contrast in dark, `steelRaised` is pure black, so filled-only tags and icon tiles
      lose their fill (the word and symbol still carry the meaning) and a pressed face reads lighter
      instead of sinking. Keep, or choose a darker pressed fill for that mode.
- [ ] The paused rest countdown is chalk like the running one; only the word "Paused" and the play
      glyph tell them apart.
- [ ] The receipt opens as a sheet, not the spec's zoom transition. Build the zoom, or keep the sheet.
- [ ] "Repeat last workout" is omitted until the engine has an entry point for it.
