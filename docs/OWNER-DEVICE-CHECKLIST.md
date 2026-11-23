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
- [ ] **Pitch pages.** The set row logs with a stamp and one `clank`. The estimate's four
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

- [ ] **Log tap, the log moment.** One tap on the check is one event: the clank and the stamp begin
      together, and about a tenth of a second later the rest bar, the "+1 rep" mark and any record
      notice fade in as one. Check that: (1) the clank is one tap, not two, and nothing buzzes under
      it (there is no success haptic any more); (2) the *first* set of a fresh launch clanks as
      crisply as the tenth, because the session starts the haptic engine ahead of it; (3) the clank
      and the seal feel like the same instant. The seal first reaches its full size about 150 ms
      after the haptic, so if the two feel apart, tune `LogMoment.followDelay` and the seal's
      spring together, not the haptic alone; (4) a log from the keypad's "Log set" reads the same
      as one from the row's check, with the sheet leaving as the bar arrives; (5) with Reduce Motion
      on, the seal, the mark and the rest bar appear at once with the clank and nothing travels;
      (6) a write that fails plays nothing and stamps nothing. If the clank reads as too heavy,
      lower its intensity in `ClankPlayer` before anything else.
- [ ] **Auto rest.** A movement you have chosen a rest for starts that rest when a working set is
      saved; a warm-up starts none; a movement with no remembered rest starts none and asks once.
- [ ] **Next rest.** The row under the rest bar and a drag up on the bar open the lengths, a drag
      down closes them, choosing one changes the next rest and not the running one.
- [ ] **Keypad** retargets in place between weight and reps, and its keys sink on touch-down.
- [ ] **Single-thumb traversal.** With the phone in one hand and the other on the bar: tap a weight,
      type it, press Next, type the reps, press Log set, and never move the thumb to the top half of
      the screen, never see the system keyboard, never place a cursor. The pad's top edge is at or
      below 40% of the screen and the rest bar's at or below 60% (CI measures both and writes
      `thumb-reach.txt`; this is whether it *feels* in reach). The log check sits at the trailing
      edge, the right thumb's side: say whether a left-handed lifter should be offered the mirror.
- [ ] **Machine steps.** On a machine with a recorded increment, the pad's quick steps are that step
      and twice it, the row's −/+ show the same number, and stepping from a typed load lands on a
      load the stack can hold. In pounds a 4.5 kg stack shows 9.92 and 19.84. On a machine with no
      increment recorded the pad offers 2.5 and 5 and the row shows no −/+. Every step is hit first
      time with a chalky thumb.
- [ ] **Press feel** on the header icon menu (a `Menu` never reports a press, so it is device-only)
      and on the flat control faces, which now step off their surface by fill and carry no outline
      unless Increase Contrast or Button Shapes is on: confirm each reads as a control in daylight.
- [ ] **Glare and sweat.** Plate blue, the caption text and the certainty capsules stay legible at
      arm's length in daylight; the log control can be hit one-handed with a chalky thumb.
- [ ] **Correcting a saved set.** Log a set, then open the movement's "…" menu: it opens with
      "Correct set" (one entry with one saved set, a list naming each set by its figures with
      several), and choosing one puts the keypad on that set's weight. In a lifter's first workout,
      one quiet line at the bottom says a saved weight or reps can be tapped to correct it; it is
      not a modal, "Got it" puts it away, it does not come back in the next workout or after a
      relaunch, and it is not drawn over an error, a new record or the keypad. At the largest
      Dynamic Type it wraps with "Got it" below it, and with Reduce Motion it appears at once.
- [ ] **Correcting a finished set.** On a receipt, "Correct" in the toolbar and "Correct a set…"
      at the bottom both show a pencil beside each set. The sheet seeds the saved figures, "Next"
      moves to the reps, "Save correction" writes, and the receipt then shows the corrected set with
      a neutral note and no celebration. In pounds, correcting only the reps leaves the weight
      exactly as saved. After a correction, History's volume, the movement's chart and the Progress
      tab agree with it. "Remove a set…" still deletes.
- [ ] **Volume.** Each muscle carries its own certainty; none speaks for the whole report. The
      88 pt weekly count has "Worked from" under it: it opens a line per movement that adds up to the
      figure, with warm-ups under "Left out", and says it is counted and not estimated.
- [ ] **Train.** The last-workout card opens its receipt, and the "Worked from" beneath it opens a
      line per set (weight × reps = its volume) whose sum is the 72 pt figure, with warm-ups under
      "Left out". With no history the start screen says "No sessions yet".

## Decisions that are the owner's

- [ ] Under Increase Contrast in dark, `steelRaised` is pure black, so filled-only tags and icon tiles
      lose their fill (the word and symbol still carry the meaning) and a pressed face reads lighter
      instead of sinking. Keep, or choose a darker pressed fill for that mode.
- [ ] The paused rest countdown is chalk like the running one; only the word "Paused" and the play
      glyph tell them apart.
- [ ] The receipt opens as a sheet, not the spec's zoom transition. Build the zoom, or keep the sheet.
- [ ] "Repeat last workout" is omitted until the engine has an entry point for it.
