import HardsetCore
import SwiftUI

#if canImport(UIKit)
  import UIKit
#elseif canImport(AppKit)
  import AppKit
#endif

/// Semantic design tokens.
///
/// Every colour, spacing step, text style and animation the app uses is named here rather than
/// spelled inline at call sites. That indirection is the seam that makes the whole app themeable
/// without touching a single screen -- retrofitting it after the views exist is the expensive
/// version of this work. It is already load-bearing: this file has ~270 call sites across 15 view
/// files, so the palette below reached every screen as a one-file change.
///
/// The full rationale, the measured contrast figures, and the motion specifications live in
/// `docs/UI-GUIDELINES.md`. Numbers here are not taste: each was computed and verified, and the
/// checked-in hex literals match that document exactly so a reader can audit one against the other.
public enum Tokens {
  public enum Color {
    // MARK: Elevation
    //
    // Four steps at even OKLab lightness intervals, hue 264 degrees at chroma 0.008 -- a slight
    // blue bias, because pure neutral greys read brown on OLED at these levels. Pure black is
    // avoided deliberately: it makes elevation impossible and smears on scroll.
    //
    // Adjacent-step separation, measured as a WCAG ratio:
    //   ground  -> surface  1.104     surface -> raised  1.165     raised -> overlay  1.196
    //
    // ground -> surface is the subtlest step, which is why a card sitting directly on `ground`
    // takes a `hairline` border and a card nested inside another surface does not. Nesting is
    // capped at ground -> surface -> raised; a fourth level means the layout is wrong.

    /// The window. Nothing else.
    public static let ground = dynamic(light: srgb(0x08_0A_0E), dark: srgb(0x08_0A_0E))
    /// Cards, set rows, list rows, chart plot backgrounds.
    public static let surface = dynamic(light: srgb(0x15_17_1B), dark: srgb(0x15_17_1B))
    /// Sheets, the numeric pad -- anything presented over `surface`.
    public static let raised = dynamic(light: srgb(0x22_25_28), dark: srgb(0x22_25_28))
    /// System popovers and menus only.
    public static let overlay = dynamic(light: srgb(0x2F_32_36), dark: srgb(0x2F_32_36))
    /// 1 px separators and card borders. Elevation is lightness plus a hairline, never a shadow:
    /// on `ground` a shadow is invisible, so reaching for one means the step above was skipped.
    public static let hairline = dynamic(
      light: srgb(0x37_39_3E), dark: srgb(0x37_39_3E),
      // Increase Contrast: 1.55:1 -> 2.81:1 against `surface`.
      increasedContrast: srgb(0x5D_5F_64)
    )

    // MARK: Ink
    //
    // Measured against `surface`: primary 16.48:1, secondary 6.44:1, tertiary 4.35:1.

    /// The live value, the hero number, the row being worked on.
    public static let textPrimary = dynamic(light: srgb(0xF5_F5_F7), dark: srgb(0xF5_F5_F7))
    /// Labels, units, completed rows, supporting facts.
    public static let textSecondary = dynamic(
      light: srgb(0x9A_9A_A4), dark: srgb(0x9A_9A_A4),
      // Increase Contrast: 6.44:1 -> 9.92:1 against `surface`.
      increasedContrast: srgb(0xBF_C0_CA)
    )
    /// Disabled controls, decorative separators, `unevaluated`.
    ///
    /// Clears 3:1 on every surface including `overlay` (3.12:1), so it is legal for non-text and
    /// large text -- but it is the lowest rung and carries nothing a lifter needs. If a sentence
    /// matters it is at least `textSecondary`. An earlier candidate (0x62626B) measured 2.97:1 on
    /// `surface` and was cut for failing the 3:1 floor outright.
    public static let textTertiary = dynamic(
      light: srgb(0x7A_7D_83), dark: srgb(0x7A_7D_83),
      // Increase Contrast: 4.35:1 -> 8.05:1 against `surface`.
      increasedContrast: srgb(0xAA_AE_B4)
    )

    // MARK: Accent

    /// The accent is white, and is deliberately the same value as `textPrimary`.
    ///
    /// It follows from the rule that the brightest thing on screen should be the thing you are
    /// doing. It also removes the usual dark-app failure where a saturated brand hue competes with
    /// every status colour at once.
    ///
    /// This used to be `SwiftUI.Color.accentColor`, which follows the system tint -- meaning the
    /// app's identity was whatever tint the device happened to carry. Pinned so it is ours.
    public static let accent = textPrimary

    // MARK: Status
    //
    // The one place a hue is allowed outside a chart. Measured on `surface`: high 8.20:1,
    // moderate 9.78:1, low 6.83:1 -- all clear AA for normal text.

    /// Certainty is communicated with colour *and* symbol *and* text, never colour alone.
    ///
    /// That rule is load-bearing rather than polite: this green/amber/orange ramp is not separable
    /// under deuteranopia, so the symbol is the real channel and the colour is a fast second read
    /// for people who have it. A colour-only signal would also be, for a claim about someone's
    /// training, simply unclear.
    public static func certainty(_ level: CertaintyLevel) -> SwiftUI.Color {
      switch level {
      case .high: statusHigh
      case .moderate: statusModerate
      case .low: statusLow
      case .unevaluated: textTertiary
      }
    }

    public static let statusHigh = dynamic(light: srgb(0x34_C7_7B), dark: srgb(0x34_C7_7B))
    public static let statusModerate = dynamic(light: srgb(0xE8_B9_3E), dark: srgb(0xE8_B9_3E))
    public static let statusLow = dynamic(light: srgb(0xE8_87_4A), dark: srgb(0xE8_87_4A))

    /// Chart series colours, and the rule that keeps them apart from status.
    ///
    /// **Three hues, because that is where the arithmetic stops.** Four simultaneous hues do not
    /// pass all-pairs colour-blind separation on this ground; it was measured, not guessed.
    /// Cool-only sets collapse hardest -- blue against violet is 1.1 dE under deuteranopia, i.e.
    /// identical -- and a green fourth slot fails too (5.7 dE against purple, 14.9 against blue on
    /// normal vision, under the floor of 15). These three pass: worst all-pairs 8.8 dE under
    /// deuteranopia, worst normal-vision pair 18.1 dE, all at least 3:1 on both `ground` and
    /// `surface`.
    ///
    /// So hue is spent on the **gym**, not the machine -- which falls out of the data model, since
    /// a machine belongs to a gym. Machines within one gym separate by stroke dash and marker
    /// shape instead, and every series is direct-labelled regardless of count, which is what makes
    /// the tightest pair legal.
    ///
    /// Re-validate with the data-viz palette validator on any change here. Never by eye: three
    /// eyeballed candidates failed before these were derived.
    public enum Series {
      /// Assigned in fixed order, never cycled. Colour follows the entity permanently -- a filter
      /// that removes a gym must not repaint the survivors.
      public static let ordered: [SwiftUI.Color] = [
        dynamic(light: srgb(0x3C_9C_D0), dark: srgb(0x3C_9C_D0)),
        dynamic(light: srgb(0xC1_85_03), dark: srgb(0xC1_85_03)),
        dynamic(light: srgb(0xC4_72_9F), dark: srgb(0xC4_72_9F)),
      ]

      /// Beyond the third gym, series fold into one neutral rather than inventing a fourth hue.
      public static let overflow = textTertiary

      public static func hue(forGymIndex index: Int) -> SwiftUI.Color {
        index >= 0 && index < ordered.count ? ordered[index] : overflow
      }
    }

    // MARK: - Plumbing

    /// Splits a `0xRRGGBB` literal into sRGB components.
    ///
    /// Hex rather than decimals so the values in this file are diffable against
    /// `docs/UI-GUIDELINES.md` character for character.
    private nonisolated static func srgb(_ hex: UInt32) -> (Double, Double, Double) {
      (
        Double((hex >> 16) & 0xFF) / 255,
        Double((hex >> 8) & 0xFF) / 255,
        Double(hex & 0xFF) / 255
      )
    }

    /// A colour that follows the system appearance, in sRGB.
    ///
    /// **Both slots deliberately carry the same value.** The app is dark-only in v1 and forces
    /// `.dark` at the root, so the light slot is never consulted. It is written out anyway, and
    /// this function kept, so that authoring a light mode later is filling in one tuple per token
    /// rather than re-plumbing every token and reintroducing the appearance provider. That is the
    /// whole reason "light mode later" is a cheap decision instead of a redesign -- do not
    /// "simplify" this into a plain colour.
    ///
    /// Per-platform because SwiftUI has no cross-platform dynamic-colour initialiser: the
    /// appearance-aware types are `UIColor` and `NSColor`. HardsetUI builds on macOS so the suite
    /// can run on the host, so both paths have to exist. Identical values also mean host previews
    /// render correctly whatever appearance the Mac is in.
    /// `nonisolated` is load-bearing, not tidiness. `HardsetUI` builds with
    /// `defaultIsolation(MainActor)`, so without it the closure below is inferred `@MainActor` --
    /// and SwiftUI resolves colours off the main actor while updating the view graph
    /// (`resolvedHDRColor` inside `updateOutputsAsync`). Swift 6 then traps in
    /// `dispatch_assert_queue`, which crashed the app on the first tap that animated a colour.
    /// The provider must be callable from any thread because UIKit calls it from any thread.
    /// - Parameter increasedContrast: What to use when the reader has turned on Increase Contrast.
    ///   `nil` means this colour has nothing to gain from it -- `textPrimary` is already 16.48:1
    ///   against `surface`, and lifting it further would only reduce the separation from the
    ///   rungs below.
    private nonisolated static func dynamic(
      light: (Double, Double, Double),
      dark: (Double, Double, Double),
      increasedContrast: (Double, Double, Double)? = nil
    ) -> SwiftUI.Color {
      #if canImport(UIKit)
        return SwiftUI.Color(
          UIColor { traits in
            // The trait collection is already here, which is why Increase Contrast needs no
            // environment plumbing and the tokens can stay static.
            if traits.accessibilityContrast == .high, let high = increasedContrast {
              return UIColor(red: high.0, green: high.1, blue: high.2, alpha: 1)
            }
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
          }
        )
      #elseif canImport(AppKit)
        return SwiftUI.Color(
          NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let c = isDark ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
          }
        )
      #else
        // No appearance API to consult, so the light values are used rather than guessing.
        return SwiftUI.Color(.sRGB, red: light.0, green: light.1, blue: light.2)
      #endif
    }
  }

  public enum Spacing {
    public static let hairline: CGFloat = 2
    public static let tight: CGFloat = 4
    public static let snug: CGFloat = 8
    public static let regular: CGFloat = 12
    public static let loose: CGFloat = 16
    /// Screen leading/trailing gutter. Sleekness is mostly negative space.
    public static let edge: CGFloat = 20
    public static let section: CGFloat = 24
    /// Above and below a hero number.
    public static let hero: CGFloat = 32
  }

  public enum Radius {
    public static let control: CGFloat = 10
    public static let card: CGFloat = 16
  }

  public enum Text {
    /// The one number a screen is about. There is at most one of these per screen: if a screen has
    /// two candidates, one is a `readout`; if it has three, the screen is doing two jobs.
    public static let hero = Font.system(.largeTitle, design: .default, weight: .semibold)
      .monospacedDigit()
    /// Numeric readouts use a monospaced digit width so a ticking value does not reflow.
    ///
    /// Deliberately *not* `.rounded`, which it used to be. Rounded numerals read
    /// consumer-fitness; the instrument aesthetic this app is going for wants the neutral face.
    public static let readout = Font.system(.title, design: .default, weight: .medium)
      .monospacedDigit()
    public static let setEntry = Font.system(.title3, design: .default, weight: .medium)
      .monospacedDigit()
    public static let title = Font.system(.title3, design: .default, weight: .semibold)
    public static let label = Font.subheadline
    public static let caption = Font.caption
  }

  /// Letter-spacing, in points at the default text size.
  ///
  /// Separate from `Text` because tracking is a view modifier, not part of a `Font`. Call sites
  /// apply it with `@ScaledMetric` so it scales with Dynamic Type instead of crushing the text at
  /// AX5, and only styles at `title` size or above get any.
  public enum Tracking {
    public static let hero: CGFloat = -1.5
    public static let readout: CGFloat = -0.6
  }

  /// The complete motion vocabulary. Six curves; anything not on this list needs a reason written
  /// next to it.
  ///
  /// Two rules decide which one to reach for, and they are the whole difference between motion
  /// that feels physical and motion that feels decorated:
  ///
  /// 1. **Springs for anything interruptible; duration curves only for one-shot reveals.** If the
  ///    user can touch a thing again before its animation ends, it must be a spring -- springs
  ///    retarget from their current velocity, a duration curve restarts or jumps.
  /// 2. **Motion representing a measured quantity is linear.** A rest countdown with ease-out
  ///    shows time slowing down. Easing is for interface; linear is for measurement.
  ///
  /// Durations here are deliberately short. The first pass ran `travel` at 420 ms, which settles
  /// at 478 ms -- a third of a second for a focus ring to move, which reads as loose rather than
  /// snappy. Everything is compressed by roughly a third and damped harder, so elements arrive
  /// *settled* instead of arriving early and wobbling.
  ///
  /// Feel is still unverified on hardware: haptic-and-pixel co-timing and 120 Hz cannot be judged
  /// in a simulator. These are implemented to specification and expected to need tuning against a
  /// phone, which is a different thing from being unwritten.
  public enum Motion {
    // Written as explicit springs rather than `.snappy`/`.smooth` so the numbers are visible and
    // so `commit(intensity:)` below is continuous with `tap` at zero intensity.

    /// Press and release. Begins on touch-*down*, never on the action. Settles in ~103 ms.
    ///
    /// 103, not 98. §5.2 of the guidelines records that 98 was computed from a prototype whose
    /// bounce was 0.15 while the shipped value is 0.18 -- and then this comment kept the discredited
    /// figure, which is how a corrected number survives in the one place a reader is most likely to
    /// trust it.
    public static let tap = Animation.spring(duration: 0.09, bounce: 0.18)
    /// Toggle, selection, focus-ring travel. Settles in ~131 ms.
    public static let control = Animation.spring(duration: 0.16, bounce: 0.12)
    /// Sheets, cards, rows settling. Critically damped -- no overshoot on a surface. ~284 ms.
    public static let surface = Animation.spring(duration: 0.24, bounce: 0)
    /// An element crossing the screen. Settles in ~334 ms.
    public static let travel = Animation.spring(duration: 0.30, bounce: 0.16)
    /// One-shot, non-interruptible reveal.
    public static let reveal = Animation.easeOut(duration: 0.32)

    /// **The signature.** A set's commit, weighted by how heavy the set is.
    ///
    /// The app is about weight, and no lifting app has ever felt heavier when the weight was
    /// heavier. A set near the lifter's own best commits solidly with almost no overshoot; a light
    /// set is quicker and springier. It is not slower in any way that reads as lag -- the entire
    /// range is 50 ms and what the hand actually notices is the missing wobble.
    ///
    /// `intensity` is `LoadIntensity.fraction(weightKg:heaviestKg:)`. Passing `nil` yields exactly
    /// `tap`: an unknown load applies no effect rather than implying a middleweight one. The shape
    /// and its invariants are tested in `CommitShapeTests`.
    public static func commit(intensity: Double?) -> Animation {
      let shape = LoadIntensity.commitShape(intensity: intensity)
      return .spring(duration: shape.duration, bounce: shape.bounce)
    }

    /// The rest countdown, whose duration *is* the datum.
    ///
    /// Linear on purpose, and takes the remaining time rather than a constant: the correct
    /// implementation sets one animation from an absolute deadline and never ticks. A 1 Hz redraw
    /// is what made the ancestor app re-run its queries thirty times a second.
    public static func decay(remaining: TimeInterval) -> Animation {
      .linear(duration: max(0, remaining))
    }
  }

  /// Minimum tap target anywhere in the app -- Apple's floor, fine for chips and badges.
  public static let minimumTapTarget: CGFloat = 44

  /// Minimum tap target inside the logger, which is deliberately larger.
  ///
  /// Logging happens one-handed, with sweaty hands, at arm's length from a rack, between
  /// heavy sets. 44 pt is the accessibility floor for a calm user sitting still; the set row
  /// and the keypad get 56 because a missed tap there costs a set.
  /// The rest bar's progress rule, per §5.4: a 2 pt rule with round caps along the top edge.
  ///
  /// A named token rather than a literal at the call site, which is where every other dimension in
  /// this file already lives.
  public static let restRuleHeight: CGFloat = 2

  public static let loggerTapTarget: CGFloat = 56
}

/// Mirror of `HardsetCore.Certainty` for the UI layer.
///
/// Declared here so `HardsetUI` does not need to import the engine merely to colour a badge,
/// and so a rendering change can never alter engine semantics.
public enum CertaintyLevel: String, Sendable, CaseIterable {
  case unevaluated, low, moderate, high

  /// The word shown to the user. "Unevaluated" is stated plainly rather than hidden, because
  /// the app's claim is that it says when it does not know.
  public var label: String {
    switch self {
    case .high: "High confidence"
    case .moderate: "Moderate confidence"
    case .low: "Low confidence"
    case .unevaluated: "Not evaluated"
    }
  }

  public var symbolName: String {
    switch self {
    case .high: "checkmark.seal"
    case .moderate: "circle.lefthalf.filled"
    case .low: "exclamationmark.triangle"
    case .unevaluated: "questionmark.circle"
    }
  }
}
