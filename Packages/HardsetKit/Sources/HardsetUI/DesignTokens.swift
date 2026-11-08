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
///
/// The reasoning behind each value lives in `DESIGN.md` at the repository root, and
/// `Tools/check_contrast.py` reads the `swatch(...)` literals below and fails if any text role
/// drops under 7:1 or any control boundary under 3:1. Keep every colour in that literal form so
/// the check can see it.
public enum Tokens {
  public enum Color {
    // Defined in code rather than in an asset catalogue, which these two colours used to live
    // in. A catalogue inside a package target means a resource bundle, a bundle means an
    // `actool` step, and that step is what broke the first build of the app ever attempted here:
    // it is denied write access to its own output when the package sits under a symlinked path.
    // Two colours are not worth a resource bundle, and this version has no build step to fail.
    public static let background = swatch(
      light: 0xF9F9FA, dark: 0x0E0E10, highLight: 0xFFFFFF, highDark: 0x000000
    )
    public static let surface = swatch(
      light: 0xFFFFFF, dark: 0x1C1C1F, highLight: 0xFFFFFF, highDark: 0x000000
    )
    /// Subtle charcoal hairline for cards, rows, and dividers.
    ///
    /// Decorative grouping only. Anything whose boundary is the thing that tells the lifter "this
    /// is tappable" uses `controlBorder`, which is measured at 3:1.
    public static let border = swatch(
      light: 0xE0E0E4, dark: 0x323238, highLight: 0x595964, highDark: 0x9B9BA5
    )
    /// Elevated or pressed surface fill, one step above `surface`.
    public static let surfaceRaised = swatch(
      light: 0xF1F1F4, dark: 0x28282D, highLight: 0xFFFFFF, highDark: 0x000000
    )
    /// The momentary fill of a pressed key or secondary button. Opaque, so text on it stays
    /// measurable rather than depending on what happens to be underneath.
    public static let surfacePressed = swatch(
      light: 0xEBEBEF, dark: 0x2E2E33, highLight: 0xE6E6EA, highDark: 0x26262B
    )
    /// The boundary that identifies a control: fields, keys, chips, secondary buttons. At least
    /// 3:1 against `background`, `surface` and `surfaceRaised`.
    public static let controlBorder = swatch(
      light: 0x80808A, dark: 0x777782, highLight: 0x595964, highDark: 0x9B9BA5
    )

    /// Readout cyan: the one hue that means "you can act on this".
    ///
    /// Deliberately not the system accent. The asset-catalogue blue measured 3.5:1 on the light
    /// background, failing even ordinary-text AA, and it is the colour of every stock app. This is
    /// at least 7:1 as text on every surface, in both appearances.
    public static let accent = swatch(
      light: 0x00515E, dark: 0x5ED3E6, highLight: 0x003A44, highDark: 0x9BE9F4
    )
    /// The fill of a primary button. Paired only with `onAccent` text.
    public static let accentFill = swatch(
      light: 0x00515E, dark: 0x5ED3E6, highLight: 0x003A44, highDark: 0x9BE9F4
    )
    public static let accentFillPressed = swatch(
      light: 0x003D47, dark: 0x4ABFD3, highLight: 0x002B33, highDark: 0x7FDCEA
    )
    /// Text and symbols drawn on `accentFill`.
    public static let onAccent = swatch(
      light: 0xFFFFFF, dark: 0x0E0E10, highLight: 0xFFFFFF, highDark: 0x000000
    )
    /// The tint behind a selected or focused element. `accent` text stays above 7:1 on it.
    public static let accentSurface = swatch(
      light: 0xE2F4F7, dark: 0x10292E, highLight: 0xD5EEF2, highDark: 0x0B2125
    )

    public static let textPrimary = swatch(
      light: 0x151518, dark: 0xF5F5F7, highLight: 0x000000, highDark: 0xFFFFFF
    )
    public static let textSecondary = swatch(
      light: 0x4D4D56, dark: 0xB9B9C2, highLight: 0x3D3D44, highDark: 0xDDDDE4
    )

    public static let success = swatch(light: 0x155B28, dark: 0x8DE5A2)
    public static let warning = swatch(light: 0x7A3A00, dark: 0xFFB27A)
    public static let error = swatch(light: 0x981C29, dark: 0xFF9AA2)
    public static let pr = swatch(light: 0x5F4B00, dark: 0xFFD873)

    /// Tinted backgrounds for banners and row states. Each keeps its own hue, `textPrimary` and
    /// `textSecondary` above 7:1.
    public static let successSurface = swatch(light: 0xE6F4EA, dark: 0x13281A)
    public static let warningSurface = swatch(light: 0xFCEEE3, dark: 0x2C1D12)
    public static let errorSurface = swatch(light: 0xFBEAEB, dark: 0x2E1517)
    public static let prSurface = swatch(light: 0xFBF3DC, dark: 0x2A2410)

    /// One colour per machine series in a progression chart, in legend order.
    ///
    /// Each is at least 3:1 against the plot background and is always paired with its own point
    /// symbol, so two machines are never told apart by hue alone. Neither green, amber, orange nor
    /// red appears here: those already mean something.
    public static let series: [SwiftUI.Color] = [
      accent,
      swatch(light: 0x3A3A42, dark: 0xE7E7EC),
      swatch(light: 0x5236B8, dark: 0xB9A8FF),
      swatch(light: 0x9A1F66, dark: 0xFF9DD6),
    ]

    /// Certainty is communicated with colour *and* text, never colour alone -- a
    /// colour-only signal is inaccessible and, for a claim about someone's training, unclear.
    public static func certainty(_ level: CertaintyLevel) -> SwiftUI.Color {
      switch level {
      case .high: success
      case .moderate: pr
      case .low: warning
      case .unevaluated: textSecondary
      }
    }

    /// The tint a certainty chip sits on, matched to `certainty(_:)`.
    public static func certaintySurface(_ level: CertaintyLevel) -> SwiftUI.Color {
      switch level {
      case .high: successSurface
      case .moderate: prSurface
      case .low: warningSurface
      case .unevaluated: surfaceRaised
      }
    }
  }

  /// A colour that follows the system appearance and the Increase Contrast setting, in sRGB.
  ///
  /// Per-platform because SwiftUI has no cross-platform dynamic-colour initialiser: the
  /// appearance-aware types are `UIColor` and `NSColor`. HardsetUI builds on macOS so the suite
  /// can run on the host, so both paths have to exist.
  ///
  /// Written as hex literals rather than component tuples so `Tools/check_contrast.py` can read the
  /// exact values the app renders. The increased-contrast values default to the normal ones, which
  /// is correct for the status hues: they already clear 7:1, and pure black or white surfaces only
  /// raise that.
  private static func swatch(
    light: UInt32, dark: UInt32, highLight: UInt32? = nil, highDark: UInt32? = nil
  ) -> SwiftUI.Color {
    #if canImport(UIKit)
      return SwiftUI.Color(
        UIColor { traits in
          let isHigh = traits.accessibilityContrast == .high
          let hex =
            traits.userInterfaceStyle == .dark
            ? (isHigh ? highDark ?? dark : dark)
            : (isHigh ? highLight ?? light : light)
          let c = Tokens.components(hex)
          return UIColor(red: c.red, green: c.green, blue: c.blue, alpha: 1)
        }
      )
    #elseif canImport(AppKit)
      return SwiftUI.Color(
        NSColor(name: nil) { appearance in
          let match: NSAppearance.Name =
            appearance.bestMatch(from: [
              .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
            ]) ?? .aqua
          let hex: UInt32
          if match == .darkAqua {
            hex = dark
          } else if match == .accessibilityHighContrastDarkAqua {
            hex = highDark ?? dark
          } else if match == .accessibilityHighContrastAqua {
            hex = highLight ?? light
          } else {
            hex = light
          }
          let c = Tokens.components(hex)
          return NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1)
        }
      )
    #else
      // No appearance API to consult, so the light values are used rather than guessing.
      let c = Tokens.components(light)
      return SwiftUI.Color(.sRGB, red: Double(c.red), green: Double(c.green), blue: Double(c.blue))
    #endif
  }

  /// `nonisolated` on purpose: the dynamic-colour providers above are called by UIKit and AppKit
  /// off the main actor, and this target defaults everything else to `MainActor`.
  nonisolated private static func components(
    _ hex: UInt32
  ) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
    (
      red: CGFloat((hex >> 16) & 0xFF) / 255,
      green: CGFloat((hex >> 8) & 0xFF) / 255,
      blue: CGFloat(hex & 0xFF) / 255
    )
  }

  public enum Spacing {
    public static let hairline: CGFloat = 2
    public static let tight: CGFloat = 4
    public static let snug: CGFloat = 8
    public static let regular: CGFloat = 12
    public static let loose: CGFloat = 16
    public static let section: CGFloat = 24
    /// Between major blocks of a screen, such as the start screen's gym card and its last-workout
    /// summary. Also the page margin's vertical counterpart under a screen header.
    public static let block: CGFloat = 32
  }

  public enum Radius {
    public static let control: CGFloat = 10
    public static let card: CGFloat = 16
  }

  public enum Stroke {
    public static let hairline: CGFloat = 1
    public static let selected: CGFloat = 2
  }

  /// Type roles. Every one is a Dynamic Type text style, so all of them scale.
  ///
  /// Figures use SF Pro Condensed with tabular digits. Condensed is the functional choice, not a
  /// flourish: a pound value such as "132.28" fits a set-row field at full size, where the rounded
  /// face had to shrink it to 60% -- about 12 pt -- to avoid wrapping.
  public enum Text {
    /// Tab screen headers. Expanded width reads as an instrument label, and it is used nowhere
    /// else, so it stays a landmark.
    public static let display = Font.system(.largeTitle, design: .default, weight: .bold)
      .width(.expanded)
    /// Sheet headers and hero card titles.
    public static let title = Font.system(.title3, design: .default, weight: .semibold)
      .width(.expanded)
    /// Card and row titles, and primary button labels.
    public static let headline = Font.headline

    /// The rest countdown and the keypad's display. The biggest figure on any screen.
    public static let hero = Font.system(.largeTitle, design: .default, weight: .semibold)
      .width(.condensed).monospacedDigit()
    /// Numeric readouts use a monospaced digit width so a ticking value does not reflow.
    public static let readout = Font.system(.title, design: .default, weight: .semibold)
      .width(.condensed).monospacedDigit()
    public static let setEntry = Font.system(.title2, design: .default, weight: .semibold)
      .width(.condensed).monospacedDigit()
    /// Small figures inside rows and ledgers: "last time" values, counts, durations.
    public static let figure = Font.system(.headline, design: .default, weight: .semibold)
      .width(.condensed).monospacedDigit()

    public static let label = Font.body
    public static let labelEmphasis = Font.body.weight(.semibold)
    public static let rowTitle = Font.body
    /// Certainty, borrowed-history notes and corrections. Larger than a caption because these
    /// are the caveats the app exists to state, and they are read at arm's length.
    public static let provenance = Font.callout
    /// Unit suffixes beside a value: "kg", "lb", "reps".
    public static let unit = Font.callout.weight(.medium)
    /// Supplemental notes only. Anything the lifter needs uses `provenance` or `label`.
    public static let caption = Font.footnote
    /// Sentence-case section labels. Never uppercased: all-caps labels are harder to read and add
    /// nothing a weight change does not already say.
    public static let sectionHeader = Font.subheadline.weight(.semibold)
  }

  /// Shared timings. See `DESIGN.md` for which interaction uses which.
  ///
  /// Anything that moves reads `accessibilityReduceMotion` and passes `nil` instead, through
  /// `Motion.adaptive`, so the state still changes but nothing travels.
  public enum Motion {
    /// Press feedback on buttons and keys.
    public static let press = Animation.easeOut(duration: 0.12)
    /// In-place state changes: selection, the segment indicator, a row becoming logged.
    public static let state = Animation.easeInOut(duration: 0.2)
    /// Banners and inline confirmations arriving.
    public static let reveal = Animation.easeOut(duration: 0.28)
    /// The log check stamping in. The only spring in the app.
    public static let stamp = Animation.spring(duration: 0.3, bounce: 0.3)

    public static func adaptive(_ animation: Animation, reduceMotion: Bool) -> Animation? {
      reduceMotion ? nil : animation
    }
  }

  /// Minimum tap target anywhere in the app.
  ///
  /// Apple's current guidance lists 44 pt as the iOS default and 28 pt as its minimum; Hardset
  /// keeps 44 as its own floor because nothing here is used sitting still.
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

// MARK: - View Modifiers

public struct HardsetCardModifier: ViewModifier {
  public let isSelected: Bool
  public let cornerRadius: CGFloat

  public init(isSelected: Bool = false, cornerRadius: CGFloat = Tokens.Radius.card) {
    self.isSelected = isSelected
    self.cornerRadius = cornerRadius
  }

  public func body(content: Content) -> some View {
    content
      .background(
        isSelected ? Tokens.Color.accentSurface : Tokens.Color.surface,
        in: RoundedRectangle(cornerRadius: cornerRadius)
      )
      .overlay(
        RoundedRectangle(cornerRadius: cornerRadius)
          .strokeBorder(
            isSelected ? Tokens.Color.accent : Tokens.Color.border,
            lineWidth: isSelected ? Tokens.Stroke.selected : Tokens.Stroke.hairline
          )
      )
  }
}

public struct HardsetSheetModifier: ViewModifier {
  public init() {}

  public func body(content: Content) -> some View {
    #if os(iOS)
      content
        .presentationBackground(Tokens.Color.background)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Tokens.Radius.card)
        .tint(Tokens.Color.accent)
    #else
      content
        .presentationBackground(Tokens.Color.background)
        .presentationDragIndicator(.visible)
        .tint(Tokens.Color.accent)
    #endif
  }
}

public extension View {
  func hardsetCard(selected: Bool = false, cornerRadius: CGFloat = Tokens.Radius.card) -> some View {
    modifier(HardsetCardModifier(isSelected: selected, cornerRadius: cornerRadius))
  }

  func hardsetSheet() -> some View {
    modifier(HardsetSheetModifier())
  }
}

// MARK: - Button styles

/// The app's buttons. Every tappable thing that is not a row, a key or a chip uses this.
///
/// The label is laid out inside the style, so the minimum height, the content shape and the hit
/// region are the same rectangle -- a frame applied outside a plain button reserves space without
/// reliably extending what can be tapped.
public struct HardsetButtonStyle: ButtonStyle {
  public enum Role: Sendable, Hashable {
    /// Accent fill. One per screen: the thing the lifter came here to do.
    case primary
    /// Raised fill and a control border.
    case secondary
    /// Accent text with no fill, for low-emphasis actions beside content.
    case quiet
    /// Error text on the error surface. For actions that close or discard something.
    case destructive
  }

  public enum Size: Sendable, Hashable {
    /// 56 pt. The logger and the start screen.
    case logger
    /// 44 pt. Everywhere else.
    case regular
  }

  private let role: Role
  private let size: Size
  private let fullWidth: Bool

  public init(_ role: Role = .primary, size: Size = .regular, fullWidth: Bool = true) {
    self.role = role
    self.size = size
    self.fullWidth = fullWidth
  }

  public func makeBody(configuration: Configuration) -> some View {
    HardsetButtonBody(configuration: configuration, role: role, size: size, fullWidth: fullWidth)
  }
}

private struct HardsetButtonBody: View {
  let configuration: ButtonStyleConfiguration
  let role: HardsetButtonStyle.Role
  let size: HardsetButtonStyle.Size
  let fullWidth: Bool

  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: Tokens.Radius.control)
    configuration.label
      .font(size == .logger ? Tokens.Text.headline : Tokens.Text.labelEmphasis)
      .foregroundStyle(foreground)
      .multilineTextAlignment(.center)
      .padding(.horizontal, role == .quiet ? Tokens.Spacing.snug : Tokens.Spacing.loose)
      .padding(.vertical, Tokens.Spacing.snug)
      .frame(
        maxWidth: fullWidth ? .infinity : nil,
        minHeight: size == .logger ? Tokens.loggerTapTarget : Tokens.minimumTapTarget
      )
      .background(fill, in: shape)
      .overlay {
        if role == .secondary {
          shape.strokeBorder(Tokens.Color.controlBorder, lineWidth: Tokens.Stroke.hairline)
        }
      }
      .contentShape(shape)
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
      .opacity(isEnabled ? (role == .quiet && configuration.isPressed ? 0.6 : 1) : 0.4)
      .animation(Tokens.Motion.press, value: configuration.isPressed)
  }

  private var foreground: Color {
    switch role {
    case .primary: Tokens.Color.onAccent
    case .secondary: Tokens.Color.textPrimary
    case .quiet: Tokens.Color.accent
    case .destructive: Tokens.Color.error
    }
  }

  private var fill: Color {
    switch role {
    case .primary:
      configuration.isPressed ? Tokens.Color.accentFillPressed : Tokens.Color.accentFill
    case .secondary:
      configuration.isPressed ? Tokens.Color.surfacePressed : Tokens.Color.surfaceRaised
    case .quiet:
      .clear
    case .destructive:
      Tokens.Color.errorSurface
    }
  }
}

/// A keypad key: raised, outlined, and pressed in rather than highlighted.
///
/// The outline is the measured `controlBorder`. A key identified only by a fill one shade off the
/// pad is a key the lifter has to look for.
public struct HardsetKeyStyle: ButtonStyle {
  public init() {}

  public func makeBody(configuration: Configuration) -> some View {
    HardsetKeyBody(configuration: configuration)
  }
}

private struct HardsetKeyBody: View {
  let configuration: ButtonStyleConfiguration

  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: Tokens.Radius.control)
    configuration.label
      .foregroundStyle(Tokens.Color.textPrimary)
      .frame(maxWidth: .infinity, minHeight: Tokens.loggerTapTarget)
      .background(
        configuration.isPressed ? Tokens.Color.surfacePressed : Tokens.Color.surfaceRaised,
        in: shape
      )
      .overlay(shape.strokeBorder(Tokens.Color.controlBorder, lineWidth: Tokens.Stroke.hairline))
      .contentShape(shape)
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
      .opacity(isEnabled ? 1 : 0.4)
      .animation(Tokens.Motion.press, value: configuration.isPressed)
  }
}
