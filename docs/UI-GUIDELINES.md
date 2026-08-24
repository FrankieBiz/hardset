# Hardset — UI guidelines

The design language for the app. Every value here is either derived from a stated principle or
computed and verified; none of it is taste asserted as fact. Where a number was measured, the
measurement is shown so a future change can be re-checked rather than re-argued.

**Reference points.** Whoop for the *instrument* feeling — dark ground, one hero number per
screen, thin data marks, generous vertical rhythm, the sense that you are reading a device rather
than browsing an app. Apple for restraint — achromatic chrome, elevation instead of decoration,
motion that is physical rather than showy.

**And one deliberate break from Whoop.** Whoop's signature device is a composite 0–100 score in a
coloured ring. Hardset may not ship that, ever. Not for aesthetic reasons: the architecture
forbids it. Every number in this app carries a certainty and a coverage fraction because composite
scores launder missing data into false confidence — the ancestor app scored a session 78/100,
"Dialed in", with three exercises it could not attribute at all. So we take Whoop's *look* and
reject its *epistemics*. This distinction generates several rules below; when one of them seems
inconvenient, this is why it exists.

---

## Implementation status

Honest division, so nobody reads a specification as a description of the app.

**Landed:** the whole of §1, §2 (every value in `Tokens`, verified against this document by
script, including §2.5's gym-hue / machine-stroke rule on the progression chart), §3's token
definitions, §4.1's spacing additions, §5.2 including the `commit(intensity:)` signature, §5.6's
chart draw-on and volume bar reveal, and the parts of §5.3 with a host today -- the logged row recedes, the log control
acknowledges on touch-*down*, and the check replaces the circle. The root forces `.dark`.

**Specification only** -- nothing in the app does this yet: the focus-ring travel and glass morph in
§5.3, the zoom transition in §5.7, most of the haptics table in §5.8, the glass policy in §4.4, and
the concentric-corner rule in §4.2. (§5.6's reveals were listed here *and* under Landed, which
cannot both be true; they are implemented. §5.4's rest bar and §5.5's summary choreography are also
built, and the summary sequence is not yet skippable by tap as M12 requires.)

**Reduce Motion** is honoured everywhere that animates. `CommitButtonStyle` drops the scale and
keeps the dim; `SessionSummaryView`, `VolumeReportView`, `ProgressionChartView` and `RestBarView`
each read the setting; and `SetRowView`'s row-level recede and symbol replace -- which this section
previously recorded as the one gap -- are switched off at the source, with the symbol falling back to
`.identity` rather than a shorter travel, because the travel is the thing being asked about. Verified
by sweeping every `withAnimation`, `.animation(`, `.transition(`, `.contentTransition` and
`symbolEffect` in `HardsetUI` and `HardsetFeature`: each is either guarded directly or driven by a
transaction that is already nilled.

**Tuning is not verification.** Every animation above is implemented to specification and none has
been felt on hardware. Haptic-and-pixel co-timing (M4) and 120 Hz cannot be judged in a simulator,
so expect these numbers to move once the device gate closes. The rest timer stays undecorated until
AlarmKit is proven on a phone: do not decorate a timer that has never fired.

**Known gap this document exposed:** finishing a workout used to only clear the coordinator, so
§5.5 had no host screen at all. A `SessionSummaryView` now exists. Records were *already* surfaced
per set inside the live session by `SessionView` -- an earlier draft of this note claimed no view
read them, which was wrong -- but nothing had ever aggregated them for the session as a whole, and
nothing summarised a finished workout.

---

## 0. The five rules everything else follows from

1. **Colour is information.** Chrome is greyscale. A hue on screen means something specific, or it
   is not there.
2. **The brightest thing is the thing you are doing.** Attention is directed by luminance, not by
   colour or by weight. A finished row recedes; the live row is the brightest object on screen.
3. **Elevation is lightness, not shadow.** On a near-black ground a shadow is invisible. Surfaces
   separate by luminance step plus, where needed, a hairline.
4. **Motion is physics, not decoration.** Anything the user can touch again mid-flight is a spring.
   Anything representing a measured quantity is linear. Nothing loops.
5. **A number and its certainty share one transition.** They appear in the same frame, always. A
   value may never be on screen without its qualification.

---

## 1. Appearance

**Dark-only in v1.** The app sets `.preferredColorScheme(.dark)` at the root and ignores the
system setting. One palette, tuned precisely, is worth more than two palettes tuned adequately.

A light mode is **not** authored, but is deliberately kept cheap to add later:

- No token name contains the word `dark`. Names describe *role* (`ground`, `surface`, `raised`) or
  *elevation step*, never appearance.
- Elevation is defined as an ordered ramp, so a light ramp is a substitution rather than a redesign.
- No value is spelled inline at a call site. `Tokens` remains the only place a colour is written —
  that indirection already exists in `DesignTokens.swift` and is the whole reason this is a later
  decision instead of a rewrite.

The existing `Tokens.Color.dynamic(light:dark:)` helper stays. It currently receives identical
values in both slots, which documents the seam without pretending a light mode has been designed.

---

## 2. Colour

### 2.1 Elevation ramp — achromatic, cool-biased

Four steps at even OKLab lightness intervals, with a slight blue bias (hue 264°, chroma 0.008) so
the greys read cool and instrument-like rather than muddy. Pure neutral greys go brown on OLED at
these levels; pure black (`#000000`) is also avoided — it makes elevation impossible and smears on
scroll.

| Token | Hex | OKLab L | Used for |
|---|---|---|---|
| `ground` | `#080A0E` | 0.145 | the window. Nothing else. |
| `surface` | `#15171B` | 0.205 | cards, set rows, list rows, chart plot backgrounds |
| `raised` | `#222528` | 0.262 | sheets, the numeric pad, anything presented over `surface` |
| `overlay` | `#2F3236` | 0.315 | system popovers and menus only |
| `hairline` | `#37393E` | 0.345 | 1 px separators and card borders |

Adjacent-step separation, WCAG ratio (measured):

```
ground  -> surface   1.104
surface -> raised    1.165
raised  -> overlay   1.196
```

`ground → surface` is the subtlest step, which is why **a card sitting directly on `ground` gets a
hairline border and a card nested inside another surface does not.** Nesting is capped at
`ground → surface → raised`. A fourth level of nesting means the layout is wrong.

### 2.2 Ink

| Token | Hex | vs `surface` | Rule |
|---|---|---|---|
| `textPrimary` | `#F5F5F7` | 16.48 : 1 | the live value, the hero number, the row you are on |
| `textSecondary` | `#9A9AA4` | 6.44 : 1 | labels, units, completed rows, supporting facts |
| `textTertiary` | `#7A7D83` | 4.35 : 1 | disabled controls, decorative separators, `unevaluated` |

`textTertiary` clears 3 : 1 on every surface including `overlay` (3.12 : 1), so it is legal for UI
and large text — but it is the **lowest rung and carries no information a lifter needs**. If a
sentence matters, it is at least `textSecondary`.

An earlier candidate for tertiary (`#62626B`) measured 2.97 : 1 on `surface` and was rejected: it
failed the 3 : 1 non-text floor outright.

### 2.3 Accent

**The accent is white.** `#F5F5F7` — the same value as `textPrimary`.

This falls directly out of rule 2: the interactive thing should be the brightest thing. It also
removes the usual dark-app failure where a saturated brand accent competes with every status colour
on screen.

- **Primary action** — white fill, `ground` (`#080A0E`) label. 18.19 : 1. The single brightest
  object on the screen, and there is at most one per screen.
- **Secondary action** — `textPrimary` label on `surface`, no fill.
- **Tertiary / destructive-adjacent** — `textSecondary` label, no fill. Destructive confirmation
  borrows the system red *inside a system alert only*; we do not paint red into our own chrome.
- **Focus ring** — 2 pt `textPrimary` stroke. Already the behaviour in `SetRowView`; keep it.

`Tokens.Color.accent` used to resolve to `Color.accentColor`, which follows the system tint -- so
the app's identity was whatever tint the device happened to carry. It is now pinned to the explicit
value above.

### 2.4 Status — certainty, and only certainty

The one place a hue is allowed outside a chart. These are the colours behind
`Tokens.Color.certainty(_:)`.

| Level | Hex | vs `surface` | Symbol |
|---|---|---|---|
| `high` | `#34C77B` | 8.20 : 1 | `checkmark.seal` |
| `moderate` | `#E8B93E` | 9.78 : 1 | `circle.lefthalf.filled` |
| `low` | `#E8874A` | 6.83 : 1 | `exclamationmark.triangle` |
| `unevaluated` | `#7A7D83` | 4.35 : 1 | `questionmark.circle` |

All clear AA for normal text. The green/amber/orange ramp is *not* separable under deuteranopia,
which is why the existing rule in `DesignTokens.swift` — colour **and** symbol **and** word, never
colour alone — is load-bearing rather than polite. The symbol is the real channel; the colour is
a fast second read for people who have it.

Status colour appears **only** as small text-and-icon badges on a surface. See §2.6 for why it may
never enter a plot area.

### 2.5 Chart series

Three hues, assigned in fixed order, never cycled. Validated all-pairs (every series is on screen
at once, so adjacent-pair checking is not enough):

| Slot | Hex | OKLab L |
|---|---|---|
| 1 | `#3C9CD0` blue | 0.660 |
| 2 | `#C18503` amber | 0.660 |
| 3 | `#C4729F` purple | 0.655 |
| overflow | `#7A7D83` neutral | 0.590 |

```
Lightness band       PASS  all 3 inside L 0.48–0.67
Chroma floor         PASS  all 3 >= 0.10
CVD separation       PASS  worst all-pairs 8.8 dE (deutan)
Normal-vision floor  PASS  worst all-pairs 18.1 dE
Contrast vs surface  PASS  all 3 >= 3:1   (also >= 3:1 on ground)
```

**Why only three.** Four simultaneous hues do not pass on this ground — it was tried. Cool-only
sets collapse hardest: blue against violet measures **1.1 dE under deuteranopia**, i.e. identical.
Adding a green fourth slot fails too (5.7 dE against purple, and 14.9 against blue on
normal vision, under the 15 floor). Three is not a stylistic cap, it is where the arithmetic stops.

**So hue is spent on the gym, not the machine.** This falls out of the data model — a machine
belongs to a gym — and it is what makes three hues sufficient:

- **Gym → hue.** First three gyms take slots 1–3 in first-seen order. Colour follows the entity
  permanently; a filter that removes a gym must never repaint the survivors.
- **Machine within a gym → stroke dash + marker shape.** `.lineStyle(StrokeStyle(dash:))` and
  `.symbol(by:)`. Two leg presses in one gym are the same hue, different stroke.
- **Beyond three gyms → the neutral slot,** direct-labelled. Never a generated fourth hue.
- **Every series is direct-labelled at its last point** regardless of count. Identity is never
  colour-alone, which is also what makes the 8.8 dE pair legal.

### 2.6 The one hard colour boundary

**Status hues never enter a plot area. Series hues never leave one.**

This is not tidiness. Measured against each other, status `low` `#E8874A` and series amber
`#C18503` differ by **8.4 dE on normal vision** — well under the 15 floor. On the same screen, in
the same shape, they would be the same colour. The separation is therefore structural:

| | Status | Series |
|---|---|---|
| Location | badges on a surface | inside the plot rect only |
| Shape | text + SF Symbol | stroked line or bar |
| Companion | always a word | always a direct label |

A legend swatch is part of the chart and takes series colour. A certainty badge attached to a chart
sits outside the plot rect, in status colour, with its symbol.

### 2.7 Gradients

None on chrome. Two exceptions: the achromatic specular sweep on a personal record (§5.5) and
area fills under a chart line, at ≤ 12 % of the series hue, fading to transparent.

---

## 3. Typography

SF Pro throughout. **Drop `.rounded` from the readout styles.** Rounded numerals read
consumer-fitness; the instrument aesthetic wants the neutral face. `.monospacedDigit()` stays
everywhere a value can change — already correct in the current tokens and the reason a ticking
number does not reflow.

| Token | Style | Weight | Tracking | Use |
|---|---|---|---|---|
| `hero` | `.largeTitle` | semibold | −1.5 | the one number a screen is about |
| `readout` | `.title` | medium | −0.6 | secondary values, the rest countdown |
| `setEntry` | `.title3` | medium | 0 | weight and reps in a set row |
| `title` | `.title3` | semibold | 0 | section headers |
| `label` | `.subheadline` | regular | 0 | field labels, buttons |
| `caption` | `.caption` | regular | 0 | units, footnotes, "Last time" |
| `glyph` | `.title2` | — | — | symbol-only controls: the log circle, pause, skip |
| `mono` | `.caption` monospaced | regular | 0 | technical detail meant to be pasted into a bug report |

**Every style is a semantic `Font.TextStyle`, never a raw point size** — a hardcoded size breaks
Dynamic Type, and this app is read at arm's length in bad light. Tracking is applied through
`@ScaledMetric` so it scales with the text rather than crushing it at AX5.

**One hero number per screen.** This is the single most valuable thing to take from Whoop. If a
screen has two candidates, one of them is a `readout`. If it has three, the screen is doing two
jobs.

Numerals are tabular anywhere they sit in a column. Machine and exercise names are never
truncated mid-word — one line, tail truncation, full string in the accessibility label.

---

## 4. Space, shape, materials

### 4.1 Space

Existing scale is sound. Two additions for the sleeker rhythm — sleekness is mostly negative space:

| Token | pt | Use |
|---|---|---|
| `hairline` | 2 | baseline-to-caption |
| `tight` | 4 | within a label group |
| `snug` | 8 | between related rows |
| `regular` | 12 | inside a card |
| `loose` | 16 | between cards |
| `edge` | 20 | **new** — screen leading/trailing gutter |
| `section` | 24 | between sections |
| `hero` | 32 | **new** — above and below a hero number |

### 4.2 Shape

`Radius.control = 10`, `Radius.card = 16`, `Radius.bar = 4` — keep. All corners continuous,
never circular. `bar` is smaller than `control` because a data bar is 10 pt tall: at radius 10
it becomes a lozenge and stops reading as a length. It was a literal `4` at four call sites
across two charts before it was named, which is how a fourth radius arrives without a decision.

**Nested corners must be concentric,** not equal. An inset child inside a 16 pt card needs
`16 − inset`, not 16. Prefer `ConcentricRectangle`, which derives this from the container rather
than from a hand-computed radius. **Confirmed present** in the iOS 26.4 SDK as
`public struct ConcentricRectangle : Shape, Animatable` in SwiftUICore — an earlier version of this
line asked the reader to verify it, which is now done.

### 4.3 Tap targets

Unchanged and non-negotiable: `minimumTapTarget = 44`, `loggerTapTarget = 56`. The existing
reasoning in `DesignTokens.swift` is correct — 44 is the floor for a calm user sitting still, and
the logger is neither.

### 4.4 Liquid Glass policy

The comment already in `SetRowView` — *"Opaque. Dense numeric rows are the one surface glass is
actively wrong for"* — is promoted to the rule.

**Glass is for floating chrome that content scrolls beneath.** Allowed: the tab bar and
`tabViewBottomAccessory` (already in use), toolbars, the rest bar while it floats over the set
grid, the numeric pad's sheet background.

**Glass is forbidden on content surfaces:** set rows, cards, chart plot areas, anything with dense
monospaced numerals or a hairline border. Two reasons, both concrete — small digits over moving
content lose legibility, and glass lightness varies with whatever is behind it, which breaks the
elevation ladder in §2.1.

- One glass layer at a time. Never glass over glass.
- Sibling glass elements go in a `GlassEffectContainer` so they blend as one shape rather than
  compositing separately.
- Prefer `.glassEffect(.regular)`. `.clear` has almost nothing to refract on `#080A0E`.

### 4.5 Shadow

Not used for elevation, anywhere. On `#080A0E` a shadow is invisible; reaching for one is a sign
the elevation step in §2.1 was skipped. Shadow is permitted only under a genuinely floating glass
element, at ≤ 8 % opacity, and only because the system draws it.

---

## 5. Motion

The part with the most craft in it, and the part most easily faked. What separates good motion from
decorated motion is almost entirely **interruptibility** and **honesty about what the motion
represents** — not duration, easing fashion, or how much moves.

### 5.1 Principles

**M1 — Springs for anything interruptible; duration curves only for one-shot reveals.**
If the user can touch a thing again before its animation ends, it must be a spring. Springs retarget
from their current velocity; a duration curve restarts or jumps. `withAnimation(.easeInOut(duration:
0.3))` on a control that can be double-tapped is the single most common tell of cheap animation.

**M2 — Motion that represents a measured quantity is linear.**
A rest arc with ease-out shows time slowing down. A bar that eases into its value implies a rate
that is not in the data. Easing is for interface; linear is for measurement. This is the same
honesty constraint that governs the numbers, applied to their movement.

**M3 — Acknowledge within 100 ms, complete within 320 ms.**
The acknowledgement and the completion are different budgets. First visible response begins on
touch-*down*, never on the action.

**M4 — Haptic and pixel land on the same frame.** Both driven by the same state change, through
`.sensoryFeedback(_:trigger:)`. Never a haptic on press with the visual on release.

**M5 — Motion implies causation. Animate only what the user caused.**
A value that changed because CloudKit delivered a record appears without animation — otherwise the
app looks like it is moving on its own. Wrap sync-driven mutations in
`withTransaction(Transaction(animation: nil))`.

**M6 — Never animate a value the user is editing.** `.contentTransition(.numericText())` is for
values the app computes. A digit being typed into `NumericEntryBuffer` appears instantly.

**M7 — Informational motion survives Reduce Motion; decorative motion does not.**
Not "turn animation off". The rest arc keeps trimming, because it *is* the timer. The breathing
pulse stops, because it is emphasis. Every named motion below declares its reduced substitute.

**M8 — Zero database work per frame.** The ancestor app ran roughly thirty unbounded fetches a
second in a live session. An animation is never driven by a value a query recomputes: animate from
an immutable deadline or a captured local.

**M9 — Animate the datum, not the pixels.** A bar grows by animating its value, so the axis, the
label, and the stroke width stay correct. `scaleEffect` on a chart mark distorts strokes and text.

**M10 — One event, one animation.** Two things moving on the same event share one curve, offset by
delay. Two independently fired animations drift.

**M11 — Nothing loops.** Every animation is event-driven and terminates. No ambient shimmer, no
pulsing idle state. Battery, and it reads as decoration.

**M12 — Anything over 400 ms is skippable.** A tap jumps to the end state.

### 5.2 The named scale

| Name | Definition | Settles | For |
|---|---|---|---|
| `tap` | `.spring(duration: 0.09, bounce: 0.18)` | 103 ms | press / release |
| `control` | `.spring(duration: 0.16, bounce: 0.12)` | 131 ms | toggle, selection, focus ring travel |
| `surface` | `.spring(duration: 0.24, bounce: 0)` | 284 ms | sheets, cards, rows settling |
| `travel` | `.spring(duration: 0.30, bounce: 0.16)` | 333 ms | an element crossing the screen |
| `reveal` | `.easeOut(duration: 0.32)` | 320 ms | one-shot, non-interruptible reveal |
| `decay` | `.linear(duration: remaining)` | — | the rest countdown — duration *is* the datum |
| `commit(intensity:)` | `.spring(duration: 0.09→0.14, bounce: 0.18→0.04)` | 97–149 ms | **the signature** — a set, weighted by its load |

Settle times are the time to enter and stay within 0.5% of target, recomputed from the constants
actually in `Tokens.Motion` and pinned by `CommitSettlingTests`. An earlier version of this table
was wrong: it carried `tap` at 98 ms, computed from a prototype whose bounce was 0.15, while the
shipped token is 0.18 — chosen so `commit(intensity: 0)` is continuous with `tap`. The lesson is
the obvious one, which is that a table of measurements has to be regenerated from the source of
truth rather than copied forward.

Seven. Anything not on this list needs a reason written next to it.

The first pass of this table was a third slower — `travel` at 420 ms settles at 478 ms, which reads
as loose rather than snappy. Everything is compressed and damped harder, so elements arrive
*settled* rather than arriving early and wobbling.

### 5.2.1 The signature — motion with mass

`commit(intensity:)` scales the spring by how heavy a set is relative to the lifter's own best on
that movement. A set near their maximum commits solidly with almost no overshoot; a light set is
quicker and springier. **It is not slower in any way that reads as lag** — the whole range is 50 ms
and what the hand notices is the missing wobble, because a heavy plate does not wobble and does not
arrive late either.

The intensity comes from `LoadIntensity.fraction(weightKg:heaviestKg:)`. `nil` means unknown, and
unknown applies **no effect at all** rather than a guessed middle — a mid-weight feel on a lift with
no history is the same neutral-70 fallback this codebase exists to avoid, expressed in physics
instead of numerals. A load above the previous best clamps to full intensity, so beating a record
automatically produces the most solid commit in the app: a reward that falls out of the arithmetic
rather than a celebration bolted on.

Invariants are pinned in `CommitShapeTests`: unknown is unmodulated, damping falls monotonically
with load, and duration never passes the snappy ceiling.

**Settling is not monotonic, and that is known rather than intended.** Duration rises with load
while bounce falls, and the two pull in opposite directions, so a mid-weight set settles marginally
*faster* than a light one — 103 ms at intensity 0, 97 ms at 0.5, 149 ms at 1.0. The dip is 6 ms and
imperceptible, the heavy end is unambiguously the longest, and the sense of mass is carried by the
loss of overshoot rather than by total time. `CommitSettlingTests` pins the shape of that envelope
so a change to the constants cannot quietly alter how the log control feels.

### 5.3 Hero moment — logging a set

Done forty times a session, so its budget is tight and its tone is flat. **A logged set gets no
celebration.** Correctness feedback, not applause.

The structural idea: **a logged row recedes, and the next row brightens.** The brightest row on
screen is always the one being worked on (rule 2). Most loggers do the opposite — they light up
what is finished — and the result is a screen that gets louder as it fills.

| t (ms) | What | How |
|---|---|---|
| 0 | log control to `scaleEffect(0.94)` | `tap`, driven by `configuration.isPressed` in a `ButtonStyle` — on touch-down |
| 0 | haptic | `.sensoryFeedback(.success, trigger: isLogged)` — already present, keep |
| 0–180 | `circle` → `checkmark.circle.fill`, crossing to status `high` | `.contentTransition(.symbolEffect(.replace.offUp))` |
| 0–200 | ordinal badge ring fills | `trim` 0→1 on a stroked `Circle`, `control` |
| 40–240 | row recedes: ink `textPrimary` → `textSecondary`, border to `hairline` | `surface` |
| 60–280 | the focus ring **travels** to the next row | one `RoundedRectangle` with `matchedGeometryEffect` in a shared `Namespace`, `travel` |
| 120–400 | rest bar emerges *from the log control* | `GlassEffectContainer` + `.glassEffectID(_:in:)` morph |

One ring that moves, not two that cross-fade. The rest bar growing out of the control you just
pressed is what `glassEffectID` exists for, and it is the difference between a bar that appears and
a bar that arrives.

Forbidden here: confetti, sound, whole-row bounce, any scale over 1.0.

*Reduce Motion:* press → `opacity(0.7)`; symbol → crossfade; ring → instant; focus ring →
crossfade; rest bar → fade, no morph.

### 5.4 Hero moment — the rest timer

The only thing on screen while the lifter does nothing but look at it.

The countdown text stays `Text(timerInterval:)`. It is system-rendered from an absolute deadline,
costs zero updates, and survives backgrounding because nothing of ours is running — the existing
reasoning in `RestBarView` is right and must not be softened to add an arc.

**The arc is one animation, set once. No timer, no `TimelineView`, no ticking state.**

```swift
@State private var fraction: Double = 1   // 1 = full rest remaining

private func retarget(_ state: RestTimerState, total: Duration) {
  switch state {
  case .running(let endsAt):
    let remaining = endsAt.timeIntervalSinceNow
    // Snap to the true position, then run out linearly. Two phases, because the
    // jump is a correction and only the run-out represents elapsed time (M2).
    var t = Transaction(animation: nil); t.disablesAnimations = true
    withTransaction(t) { fraction = max(0, remaining / total.seconds) }
    withAnimation(.linear(duration: remaining)) { fraction = 0 }

  case .paused(let remaining):
    // Freeze at the truth. Never at wherever the animation happened to be.
    var t = Transaction(animation: nil); t.disablesAnimations = true
    withTransaction(t) { fraction = remaining.seconds / total.seconds }

  case .idle:
    withAnimation(.smooth(duration: 0.3)) { fraction = 1 }
  }
}
```

Called on start, resume, pause, ±15 s adjust, and on return to foreground. The naive version — a
1 Hz `TimelineView` redrawing an arc — is precisely the pattern that made the ancestor app re-run
its queries thirty times a second (M8).

- **Form.** A 2 pt rule along the rest bar's top edge, retreating right-to-left. `textPrimary` for
  remaining, `hairline` for spent, round caps. If the rest surface is ever promoted to a full-screen
  state, that state gets a ring instead; the bar does not.
- **±15 s.** `control` spring to the corrected fraction, then re-issue the linear run. The jump is
  interface, the run-out is data.
- **Final 10 s.** `.phaseAnimator` breathing the countdown between `1.0` and `1.02` at ~1 Hz, plus
  `.symbolEffect(.pulse)`. Escalating `.sensoryFeedback(.impact(weight: .light))` at T−3, −2, −1.
- **Honest limit.** Those haptics only fire in the foreground. The terminal alert belongs to
  AlarmKit and is the only thing that reaches a lifter whose phone is in their pocket. The
  in-app escalation is a courtesy, never the mechanism.

*Reduce Motion:* the rule still retreats — it is the timer (M7). The breathing and the pulse stop
entirely.

### 5.5 Hero moment — finishing a workout

The one place a choreographed sequence is earned. Total ≤ 900 ms, 40 ms stagger, skippable by any
tap (M12).

| t (ms) | What |
|---|---|
| 0 | duration and set count, counting up via `.contentTransition(.numericText(value:))` |
| 40–400 | tonnage and working sets count up |
| 200–700 | per-muscle bars grow from baseline, 40 ms stagger, **animating the value** (M9) |
| 500–800 | personal records reveal — a single achromatic specular sweep, 600 ms, once |

The PR sweep is a moving `LinearGradient` mask in `textPrimary`, no hue, and it never repeats
(M11). A PR is bright, not colourful.

**Certainty badges are not a step in this table.** By rule 5, each badge arrives in the same frame
as the number it qualifies, sharing that number's transition. This is deliberate: sequencing the
caveats last would be a way of burying them, and letting the number land alone — even for 300 ms —
would put an unqualified figure on screen. If a number animates, its certainty animates with it.

Also forbidden: any summary "score", a streak, a badge, a sound.

*Reduce Motion:* the whole screen appears at once behind a single 200 ms crossfade. Numbers arrive
final, no count-up, no sweep.

### 5.6 Hero moment — charts and the volume reveal

- **Line draw-on.** Animate a `drawProgress: Double` 0→1 with `reveal`, plotting the prefix of
  points with the final segment interpolated so the head does not stair-step. 60 ms stagger between
  series.
- **Bars.** Animate the value 0→actual with `surface`, 40 ms stagger. Not `scaleEffect` (M9) — a
  scaled bar carries a distorted stroke and a stretched label.
- **Once per screen visit, never per scroll.** Guard with a `hasRevealed` flag. Re-animating on
  every scroll-back is Whoop's one genuine motion mistake and it turns signal into noise.
- **Machine-change annotations** fade in at draw-complete + 120 ms. They explain a shape, so they
  arrive after it.
- **Scrubbing is 1 : 1 with the finger. No animation on a drag, ever.** Animating direct
  manipulation is the clearest possible tell of an amateur implementation. The value readout under
  the crosshair uses `.numericText()`; the crosshair itself has no animation at all.
- **Metric switch** (heaviest load ↔ estimated 1RM): rescale the axis with `surface`. If the new
  metric has no estimable data, the explanation crossfades in — **the existing line never collapses
  toward zero.** That would animate a decline the lifter did not suffer, which is the exact failure
  `ProgressionChartView` exists to prevent.

*Reduce Motion:* no draw-on, no growth, no stagger. Marks are simply present. Scrubbing is
unaffected — it was never animated.

### 5.7 Navigation

Push and pop use the system transition. The one enrichment worth adding: opening an exercise's
progression from a session row uses `.matchedTransitionSource(id:in:)` plus
`.navigationTransition(.zoom(sourceID:in:))`, so the row becomes the screen. Reserve zoom for
navigation where a specific object is genuinely being opened; a list-to-detail push where the
detail is *about* the row but not *of* it keeps the standard slide.

Sheets keep system presentation. `presentationBackgroundInteraction` stays enabled on the numeric
pad — the current reasoning (it should read as a keyboard replacement, not a modal that interrupts
the set) is right.

### 5.8 Haptics

`.sensoryFeedback(_:trigger:)` only. No `UIFeedbackGenerator` — it cannot be tied to a state change
and so cannot satisfy M4.

| Event | Feedback | Status |
|---|---|---|
| Set logged | `.success` | shipped |
| Rest final 3 s | `.impact(weight: .light)` ×3 | shipped |
| Rest complete, foreground | `.success` | shipped |
| Personal record | `.impact(flexibility: .solid, intensity: 0.7)` | shipped |
| Machine changed mid-exercise | `.selection` | shipped |
| Set un-logged / removed | `.impact(weight: .light)` | shipped |
| Destructive confirmed | `.warning` | **no host** — nothing destructive exists yet |

The rest cues are scheduled as individual suspensions until an absolute instant, never as a timer:
nothing re-renders on their account, and `.task(id:)` cancels them when the state changes, so
skipping or pausing silences them without a special case. They fire in the foreground only, which
is a courtesy rather than the mechanism — AlarmKit owns the alert that reaches a lifter whose phone
is in their pocket.

A haptic marks a *committed state change*. Never on scroll, never on appear, never on a value the
app merely recalculated.

---

## 6. Forbidden

Each of these has cost somebody real work somewhere.

1. **A composite 0–100 score, in a ring or anywhere else.** Whoop's signature device. The
   architecture exists to prevent it.
2. **A target line or a red bar on weekly volume.** No per-muscle weekly set target is established,
   so there is nothing to draw against. `VolumeReportView` already says this; it stays true.
3. **Streaks, badges, confetti, celebratory sound.**
4. **Colour as the only channel.** Always plus a symbol, a word, or a label.
5. **Animation on a sync-driven change** (M5).
6. **Skeleton shimmer.** Local SQLite reads complete inside a frame. A shimmer advertises latency
   that does not exist and it loops (M11). Show the real empty state.
7. **Glass on dense numerals** (§4.4).
8. **Shadow for elevation** (§4.5).
9. **`scaleEffect` to grow a chart mark** (M9).
10. **Animating a value being edited** (M6).
11. **Any looping or ambient animation** (M11).
12. **Status hue inside a plot rect, or series hue outside one** (§2.6).
13. **More than one hero number per screen** (§3).
14. **Emoji in the interface.**

---

## 7. Definition of done for any UI change

Not merged until all of these hold:

- [ ] Builds and installs. Use the **iOS Simulator MCP `build` tool** — `xcodebuild` from a
      sandboxed shell cannot run the Swift macro plugin server, even with `-skipMacroValidation`.
- [ ] Every colour comes from `Tokens`. No literal in a view.
- [ ] Contrast re-verified if any colour changed. Text ≥ 4.5 : 1; non-text and large ≥ 3 : 1.
      Also check with Increase Contrast on
      (`xcrun simctl ui <udid> increase_contrast enabled`). The three rungs nearest the floor --
      `textSecondary`, `textTertiary`, `hairline` -- carry a brighter variant, resolved inside the
      `UIColor` provider from `traits.accessibilityContrast`, which is why the tokens can stay
      static and need no environment.
- [ ] No user-facing string uses `^[...](inflect:)` unless it is an inline `Text("...")` literal.
      The markup is only interpreted for a `LocalizedStringKey`; a `String` that reaches
      `Text(String)` renders it verbatim, and it shipped on screen as `^[1 set](inflect: true)`.
- [ ] Categorical palette re-validated all-pairs if a series colour changed. Never eyeballed.
- [ ] Every animation is on the §5.2 scale, or carries a written reason.
- [ ] Every animation declares its Reduce Motion substitute, and it was checked with the setting on.
- [ ] Checked at AX5 Dynamic Type. Nothing clipped, no tap target under 44 pt.
      Set it with `xcrun simctl ui <udid> content_size accessibility-extra-extra-extra-large`, and
      actually look — the first pass over this app found the set row rendering one character per
      line. A fixed-width column or a `.lineLimit(1)` on anything load-bearing is the usual cause;
      prefer a layout that adapts (`ViewThatFits`, or a `dynamicTypeSize.isAccessibilitySize`
      branch) over a `minimumScaleFactor` that "fits" by shrinking text the reader asked to enlarge.
- [ ] Zero database work per animation frame.
- [ ] Every number on screen has its certainty in the same frame.
- [ ] VoiceOver: dense rows are one element with a spoken sentence and named custom actions — not
      five separate focus stops.
