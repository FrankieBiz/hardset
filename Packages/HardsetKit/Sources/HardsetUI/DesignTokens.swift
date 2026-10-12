import HardsetCore
import SwiftUI

#if canImport(UIKit)
  import UIKit
#elseif canImport(AppKit)
  import AppKit
#endif

/// Semantic design tokens.
///
/// Every colour, spacing step and text style the app uses is named here rather than spelled
/// inline at call sites. That indirection is the seam that makes the whole app themeable later
/// without touching a single screen -- retrofitting it after the views exist is the expensive
/// version of this work.
public enum Tokens {
  public enum Color {
    // Defined in code rather than in an asset catalogue, which these two colours used to live
    // in. A catalogue inside a package target means a resource bundle, a bundle means an
    // `actool` step, and that step is what broke the first build of the app ever attempted here:
    // it is denied write access to its own output when the package sits under a symlinked path.
    // Two colours are not worth a resource bundle, and this version has no build step to fail.
    public static let background = adaptive(light: Palette.backgroundLight, dark: Palette.backgroundDark)
    public static let surface = adaptive(light: Palette.surfaceLight, dark: Palette.surfaceDark)
    /// Separates a card from the background in light mode, where white on #F2F2F7 is quiet.
    public static let cardStroke = SwiftUI.Color.primary.opacity(0.08)
    public static let accent = SwiftUI.Color.accentColor

    public static let textPrimary = SwiftUI.Color.primary
    /// The palette's tested grey, not the system `secondary` (about 3.4:1 on light backgrounds).
    public static let textSecondary = adaptive(Palette.swatch(.secondaryText))

    // What happened, as opposed to how sure the app is (`certainty(_:)`). A record is not "high
    // confidence" and an error is not "low confidence", so neither borrows a certainty colour.
    public static let success = adaptive(Palette.swatch(.success))
    public static let record = adaptive(Palette.swatch(.record))
    public static let caution = adaptive(Palette.swatch(.caution))
    public static let critical = adaptive(Palette.swatch(.critical))
    /// An honest caveat ("≥", "from another machine", "length unknown") is plain grey text with a
    /// glyph. Orange made a lower bound read as a failure (spec §3, item 2).
    ///
    /// The grey is the palette's tested neutral, not the system `secondary`. Nothing here tests
    /// `secondary`'s contrast, and it is likely under 4.5:1 on a light background. A caveat reads
    /// as secondary through its small type, not through a fainter colour.
    public static let caveat = adaptive(Palette.swatch(.certaintyUnevaluated))

    /// Certainty is communicated with colour *and* a glyph and a word, never colour alone -- a
    /// colour-only signal is inaccessible and, for a claim about someone's training, unclear. The
    /// glyph and the word are `CertaintyMark`'s, decided and tested in Core; this is only the
    /// colour.
    ///
    /// The values are `Palette`'s certainty roles, whose contrast as text is tested in Core, with
    /// darker (light mode) or lighter (dark mode) variants under Increase Contrast.
    public static func certainty(_ certainty: Certainty) -> SwiftUI.Color {
      switch certainty {
      case .high: certaintyHigh
      case .moderate: certaintyModerate
      case .low: certaintyLow
      case .unevaluated: certaintyUnevaluated
      }
    }

    // Built once rather than per call: `certainty(_:)` runs in row bodies, and a fresh dynamic
    // colour each time would never compare equal to the last one.
    private static let certaintyHigh = adaptive(Palette.swatch(.certaintyHigh))
    private static let certaintyModerate = adaptive(Palette.swatch(.certaintyModerate))
    private static let certaintyLow = adaptive(Palette.swatch(.certaintyLow))
    private static let certaintyUnevaluated = adaptive(Palette.swatch(.certaintyUnevaluated))
  }

  /// One palette role's colour, following the appearance and the Increase Contrast setting.
  private nonisolated static func adaptive(_ swatch: PaletteSwatch) -> SwiftUI.Color {
    adaptive(
      light: swatch.light, lightIncreasedContrast: swatch.lightIncreasedContrast,
      dark: swatch.dark, darkIncreasedContrast: swatch.darkIncreasedContrast
    )
  }

  private nonisolated static func adaptive(light: PaletteColor, dark: PaletteColor) -> SwiftUI.Color {
    // Backgrounds carry no text contrast requirement of their own, so one value serves both
    // contrast settings.
    adaptive(light: light, lightIncreasedContrast: light, dark: dark, darkIncreasedContrast: dark)
  }

  /// A colour that follows the system appearance and the Increase Contrast setting, in sRGB.
  ///
  /// Per-platform because SwiftUI has no cross-platform dynamic-colour initialiser: the
  /// appearance-aware types are `UIColor` and `NSColor`. HardsetUI builds on macOS so the suite
  /// can run on the host, so both paths have to exist.
  ///
  /// `nonisolated`, and the providers touch only `Sendable` values, because UIKit and AppKit call
  /// a provider whenever they resolve the colour, and nothing promises that happens on the main
  /// actor.
  private nonisolated static func adaptive(
    light: PaletteColor, lightIncreasedContrast: PaletteColor,
    dark: PaletteColor, darkIncreasedContrast: PaletteColor
  ) -> SwiftUI.Color {
    #if canImport(UIKit)
      return SwiftUI.Color(
        UIColor { traits in
          let isDark = traits.userInterfaceStyle == .dark
          let isIncreased = traits.accessibilityContrast == .high
          return Tokens.uiColor(
            isDark
              ? (isIncreased ? darkIncreasedContrast : dark)
              : (isIncreased ? lightIncreasedContrast : light)
          )
        }
      )
    #elseif canImport(AppKit)
      return SwiftUI.Color(
        NSColor(name: nil) { appearance in
          // AppKit reports Increase Contrast as its own appearance names, so all four are offered.
          let match =
            appearance.bestMatch(from: [
              .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
            ]) ?? .aqua
          let c: PaletteColor =
            switch match {
            case .darkAqua: dark
            case .accessibilityHighContrastDarkAqua: darkIncreasedContrast
            case .accessibilityHighContrastAqua: lightIncreasedContrast
            default: light
            }
          return NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1)
        }
      )
    #else
      // No appearance API to consult, so the light values are used rather than guessing.
      return SwiftUI.Color(.sRGB, red: light.red, green: light.green, blue: light.blue)
    #endif
  }

  #if canImport(UIKit)
    private nonisolated static func uiColor(_ c: PaletteColor) -> UIColor {
      UIColor(red: c.red, green: c.green, blue: c.blue, alpha: 1)
    }
  #endif

  public enum Spacing {
    public static let hairline: CGFloat = 2
    public static let tight: CGFloat = 4
    public static let snug: CGFloat = 8
    public static let regular: CGFloat = 12
    public static let loose: CGFloat = 16
    public static let section: CGFloat = 24
  }

  public enum Radius {
    public static let control: CGFloat = 10
    public static let card: CGFloat = 16
  }

  public enum Text {
    /// Numeric readouts use a monospaced digit width so a ticking value does not reflow.
    public static let readout = Font.system(.title2, design: .rounded).monospacedDigit()
    /// The active set's weight, and the largest type on screen. A text style, so it scales with
    /// Dynamic Type.
    public static let hero = Font.system(.largeTitle, design: .rounded).weight(.semibold).monospacedDigit()
    public static let setEntry = Font.system(.title3, design: .rounded).monospacedDigit()
    public static let label = Font.subheadline
    public static let caption = Font.caption
  }

  /// Spring presets that collapse under Reduce Motion (spec 2.6).
  ///
  /// `nil` means no animation, so `withAnimation(Tokens.Motion.quick(reduceMotion))` and
  /// `.animation(Tokens.Motion.quick(reduceMotion), value:)` both become instant. Frequent actions
  /// (a log, a step) use `quick`: settled, no bounce (HIG, quiet on repetition).
  public enum Motion {
    public static func quick(_ reduceMotion: Bool) -> Animation? {
      reduceMotion ? nil : .spring(duration: 0.25, bounce: 0)
    }

    public static func emphasis(_ reduceMotion: Bool) -> Animation? {
      reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.2)
    }

    /// A pad or bar arriving from the bottom edge slides; under Reduce Motion it fades instead.
    public static func edgeTransition(_ reduceMotion: Bool) -> AnyTransition {
      reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }
  }

  /// Core decides what happened; this only says how it feels. One crisp impact per log, and a
  /// distinct success for a record, which is the app's one earned moment (spec §3, items 4–5).
  public enum Haptic {
    // Pure, so callable from `sensoryFeedback`'s closure whatever isolation SwiftUI gives it.
    public nonisolated static func feedback(for event: FeedbackEvent) -> SensoryFeedback {
      switch event {
      case .log: .impact(weight: .medium)
      case .record: .success
      case .error: .error
      case .restAdjust: .selection
      }
    }
  }

  /// Minimum tap target anywhere in the app — Apple's floor, fine for chips and badges.
  public static let minimumTapTarget: CGFloat = 44

  /// Minimum tap target inside the logger, which is deliberately larger.
  ///
  /// Logging happens one-handed, with sweaty hands, at arm's length from a rack, between
  /// heavy sets. 44 pt is the accessibility floor for a calm user sitting still; the set row
  /// and the keypad get 56 because a missed tap there costs a set.
  public static let loggerTapTarget: CGFloat = 56

  /// The most a tap target grows with the type. Uncapped, 56 pt reaches about 170 pt at the
  /// largest size, and a set row's reps field and check mark would leave the hero weight no room.
  public static let maximumTapTarget: CGFloat = 88

  /// A tap target that scales with the type (`@ScaledMetric`), held between `floor` and
  /// `maximumTapTarget`.
  ///
  /// The clamp goes both ways because `@ScaledMetric` also scales *down*: at the three text sizes
  /// below Large, 44 pt becomes about 36 and 56 about 46. A floor holds at every size.
  public static func tapTarget(_ scaled: CGFloat, floor: CGFloat) -> CGFloat {
    min(max(scaled, floor), maximumTapTarget)
  }
}
