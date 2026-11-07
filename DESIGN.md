# Hardset interface system

The source of truth is `Packages/HardsetKit/Sources/HardsetUI/DesignTokens.swift`
and `Hardset/Assets.xcassets/AccentColor.colorset`. Preserve these tokens and system
Dynamic Type styles; this document records the existing system rather than creating
a second implementation.

- Palette (rounded 8-bit sRGB): accent #2E82F6; background light #F9F9FA / dark
  #0E0E10; surface #FFFFFF / #1C1C1F; border #E0E0E4 / #323238;
  raised surface #F1F1F4 / #28282D. Text and success/warning/error/record colors use
  native adaptive semantic colors, not fixed replacements. Certainty also has a
  written label and symbol, so color is never its only signal.
- Typography uses native scalable styles: body (17 pt at default size), subheadline
  (15), caption (12), title3 (20), title2 (22). Numeric entry and readouts use rounded
  monospaced digits; emphasized labels and section captions are semibold. Honor
  accessibility sizes rather than setting fixed font sizes.
- Spacing: 2 / 4 / 8 / 12 / 16 / 24 pt, from hairline through section tokens.
  Radii: control 10, card 16. Strokes: hairline 1, selected 2.
- Touch targets: at least 44 pt; workout logging controls 56 pt. Selected states use
  accent borders; pressed/elevated surfaces use the raised-surface token. Preserve
  native focus, disabled and accessibility behavior.
- Loading: keep readable content during refresh. Initial history/progression/volume
  loads use the native progress indicator, then show the existing empty or data
  components only after a successful read. Actual
  failures use the existing retry message; cancellation is silent and never clears
  content. Only the latest requested snapshot may replace visible content.
- Motion: the current shared tokens define no custom animations. Snapshot loading
  adds none, so reduced-motion users get the same immediate state feedback. If
  custom motion is introduced, first add shared fast 100–150 ms, medium 150–250 ms,
  and slow 250–350 ms tokens, with ease-out entrances, ease-in exits and ease-in-out
  state changes; document interruption and reduced-motion behavior before use.
