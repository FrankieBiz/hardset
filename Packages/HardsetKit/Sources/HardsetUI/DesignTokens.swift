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
    public static let background = dynamic(
      light: (0.976, 0.976, 0.980), dark: (0.055, 0.055, 0.063)
    )
    public static let surface = dynamic(
      light: (1.000, 1.000, 1.000), dark: (0.110, 0.110, 0.122)
    )
    public static let accent = SwiftUI.Color.accentColor

    public static let textPrimary = SwiftUI.Color.primary
    public static let textSecondary = SwiftUI.Color.secondary

    /// Certainty is communicated with colour *and* text, never colour alone -- a
    /// colour-only signal is inaccessible and, for a claim about someone's training, unclear.
    public static func certainty(_ level: CertaintyLevel) -> SwiftUI.Color {
      switch level {
      case .high: .green
      case .moderate: .yellow
      case .low: .orange
      case .unevaluated: .secondary
      }
    }
  }

  /// A colour that follows the system appearance, in sRGB.
  ///
  /// Per-platform because SwiftUI has no cross-platform dynamic-colour initialiser: the
  /// appearance-aware types are `UIColor` and `NSColor`. HardsetUI builds on macOS so the suite
  /// can run on the host, so both paths have to exist.
  private static func dynamic(
    light: (Double, Double, Double), dark: (Double, Double, Double)
  ) -> SwiftUI.Color {
    #if canImport(UIKit)
      return SwiftUI.Color(
        UIColor { traits in
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
    public static let setEntry = Font.system(.title3, design: .rounded).monospacedDigit()
    public static let label = Font.subheadline
    public static let caption = Font.caption
  }

  /// Minimum tap target anywhere in the app — Apple's floor, fine for chips and badges.
  public static let minimumTapTarget: CGFloat = 44

  /// Minimum tap target inside the logger, which is deliberately larger.
  ///
  /// Logging happens one-handed, with sweaty hands, at arm's length from a rack, between
  /// heavy sets. 44 pt is the accessibility floor for a calm user sitting still; the set row
  /// and the keypad get 56 because a missed tap there costs a set.
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
