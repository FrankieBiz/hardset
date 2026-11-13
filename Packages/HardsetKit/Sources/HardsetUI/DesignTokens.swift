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
    // Defined in code rather than in an asset catalogue, which these colours used to live in. A
    // catalogue inside a package target means a resource bundle, a bundle means an `actool` step,
    // and that step is what broke the first build of the app ever attempted here: it is denied
    // write access to its own output when the package sits under a symlinked path. A handful of
    // colours are not worth a resource bundle, and this version has no build step to fail.

    // MARK: Steel: canvas, surfaces and edges

    /// The screen canvas: the deepest graphite in dark, a faint chalk-white in light.
    public static let canvas = swatch(
      light: 0xF6F6F8, dark: 0x0C0D10, highLight: 0xFFFFFF, highDark: 0x000000
    )
    /// Cards, rows and the content of sheets.
    public static let steel = swatch(
      light: 0xFFFFFF, dark: 0x17181D, highLight: 0xFFFFFF, highDark: 0x000000
    )
    /// Elevated or pressed surface fill, one step above `steel`: fields, keys, chips and
    /// secondary buttons.
    public static let steelRaised = swatch(
      light: 0xEEEEF2, dark: 0x22242B, highLight: 0xFFFFFF, highDark: 0x000000
    )
    /// The momentary fill of a pressed key or secondary button. Opaque, so text on it stays
    /// measurable rather than depending on what happens to be underneath.
    public static let steelPressed = swatch(
      light: 0xE6E6EB, dark: 0x2B2D35, highLight: 0xE6E6EA, highDark: 0x26262B
    )
    /// The lit top edge of a raised face, written as an opaque value rather than an alpha.
    ///
    /// Pre-blended over `steelRaised`: 60% `#3A3D47` in dark, 80% white in light. It stays opaque
    /// so the edge is the same colour wherever the face is drawn; do not turn it into an alpha.
    public static let edgeLight = swatch(light: 0xFCFCFD, dark: 0x30333C)
    /// The shaded bottom edge of a raised face, written as an opaque value rather than an alpha.
    ///
    /// Pre-blended over `steelRaised`: 50% black in dark, 8% black in light. It stays opaque so
    /// the edge is the same colour wherever the face is drawn; do not turn it into an alpha.
    public static let edgeShadow = swatch(light: 0xDBDBDF, dark: 0x111216)
    /// Subtle charcoal hairline for cards, rows, and dividers.
    ///
    /// Decorative grouping only. Anything whose boundary is the thing that tells the lifter "this
    /// is tappable" uses `controlEdge`, which is measured at 3:1.
    public static let hairline = swatch(
      light: 0xDEDEE4, dark: 0x2E3039, highLight: 0x595964, highDark: 0x9B9BA5
    )
    /// The boundary that identifies a control: fields, keys, chips, secondary buttons. At least
    /// 3:1 against `canvas`, `steel` and `steelRaised`.
    public static let controlEdge = swatch(
      light: 0x7E8190, dark: 0x7B7E8C, highLight: 0x595964, highDark: 0x9B9BA5
    )

    // MARK: Chalk: text

    /// Body text and values: chalk in dark, graphite in light.
    public static let chalk = swatch(
      light: 0x141519, dark: 0xF3F3F5, highLight: 0x000000, highDark: 0xFFFFFF
    )
    /// Supporting text, units and provenance.
    public static let chalkDim = swatch(
      light: 0x4B4D58, dark: 0xB6B8C3, highLight: 0x3B3D47, highDark: 0xDADCE4
    )

    // MARK: Plate colours: evidence, never decoration

    /// Plate blue: the one hue that means "you can act on this".
    ///
    /// Deliberately not the system accent. The asset-catalogue blue measured 3.5:1 on the light
    /// background, failing even ordinary-text AA, and it is the colour of every stock app. This is
    /// a deeper, tuned blue that is at least 7:1 as text on every surface, in both appearances.
    public static let plateBlue = swatch(
      light: 0x084A95, dark: 0x6FB7FF, highLight: 0x063A75, highDark: 0x9FD0FF
    )
    /// The fill of a primary button. Paired only with `onPlateBlue` text.
    public static let plateBlueFill = swatch(
      light: 0x084A95, dark: 0x6FB7FF, highLight: 0x063A75, highDark: 0x9FD0FF
    )
    public static let plateBlueFillPressed = swatch(
      light: 0x063C7A, dark: 0x5AA6F0, highLight: 0x052E5E, highDark: 0x86C2FF
    )
    /// Text and symbols drawn on `plateBlueFill`.
    public static let onPlateBlue = swatch(
      light: 0xFFFFFF, dark: 0x0C0D10, highLight: 0xFFFFFF, highDark: 0x000000
    )
    /// The tint behind a selected or focused element. `plateBlue` text stays above 7:1 on it.
    public static let plateBlueSurface = swatch(
      light: 0xE3EFFC, dark: 0x10233A, highLight: 0xD6E8FA, highDark: 0x0A1A2C
    )

    /// Logged, and high certainty.
    public static let plateGreen = swatch(light: 0x0F5A27, dark: 0x8FE3A3)
    /// Records, and moderate certainty.
    public static let plateYellow = swatch(light: 0x604A00, dark: 0xFFD86B)
    /// Failed writes.
    public static let plateRed = swatch(light: 0x9A1B24, dark: 0xFF9A9A)
    /// Caveats, and low certainty.
    public static let warning = swatch(light: 0x7A3A00, dark: 0xFFB27A)

    /// Tinted backgrounds for banners and row states. Each keeps its own hue, `chalk` and
    /// `chalkDim` above 7:1.
    public static let plateGreenSurface = swatch(light: 0xE5F5EA, dark: 0x122A1A)
    public static let plateYellowSurface = swatch(light: 0xFBF3DA, dark: 0x2B2410)
    public static let plateRedSurface = swatch(light: 0xFBEAEA, dark: 0x2E1516)
    public static let warningSurface = swatch(light: 0xFCEEE3, dark: 0x2C1D12)

    /// One colour per machine series in a progression chart, in legend order.
    ///
    /// Each is at least 3:1 against the plot background and is always paired with its own point
    /// symbol, so two machines are never told apart by hue alone. Neither green, amber, orange nor
    /// red appears here: those already mean something.
    public static let series: [SwiftUI.Color] = [
      plateBlue,
      swatch(light: 0x3A3A42, dark: 0xE7E7EC),
      swatch(light: 0x5236B8, dark: 0xB9A8FF),
      swatch(light: 0x9A1F66, dark: 0xFF9DD6),
    ]

    /// Certainty is communicated with colour *and* text, never colour alone -- a
    /// colour-only signal is inaccessible and, for a claim about someone's training, unclear.
    public static func certainty(_ level: CertaintyLevel) -> SwiftUI.Color {
      switch level {
      case .high: plateGreen
      case .moderate: plateYellow
      case .low: warning
      case .unevaluated: chalkDim
      }
    }

    /// The tint a certainty chip sits on, matched to `certainty(_:)`.
    public static func certaintySurface(_ level: CertaintyLevel) -> SwiftUI.Color {
      switch level {
      case .high: plateGreenSurface
      case .moderate: plateYellowSurface
      case .low: warningSurface
      case .unevaluated: steelRaised
      }
    }

    // MARK: - Transitional aliases (deleted in phase 7)

    public static let background = canvas
    public static let surface = steel
    public static let surfaceRaised = steelRaised
    public static let surfacePressed = steelPressed
    public static let border = hairline
    public static let controlBorder = controlEdge
    public static let textPrimary = chalk
    public static let textSecondary = chalkDim
    public static let accent = plateBlue
    public static let accentFill = plateBlueFill
    public static let accentFillPressed = plateBlueFillPressed
    public static let onAccent = onPlateBlue
    public static let accentSurface = plateBlueSurface
    public static let success = plateGreen
    public static let successSurface = plateGreenSurface
    public static let pr = plateYellow
    public static let prSurface = plateYellowSurface
    public static let error = plateRed
    public static let errorSurface = plateRedSurface
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
  ///
  /// `nonisolated`, and its providers `@Sendable`, because UIKit resolves dynamic colours on
  /// whatever thread is rendering -- under iOS 26 that includes the threads sampling content for
  /// Liquid Glass. A provider formed in this target's default `MainActor` isolation inherits that
  /// isolation and a runtime check, and the check traps the moment a colour is resolved off the
  /// main thread: the app exited with SIGTRAP as the first sheets presented.
  nonisolated private static func swatch(
    light: UInt32, dark: UInt32, highLight: UInt32? = nil, highDark: UInt32? = nil
  ) -> SwiftUI.Color {
    #if canImport(UIKit)
      return SwiftUI.Color(
        UIColor { @Sendable traits in
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
        NSColor(name: nil) { @Sendable appearance in
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
    /// Tab screen headers. A stamped plate face in the family of the figures: condensed and
    /// semibold, so a header reads as the same engraved lettering as the numbers beneath it.
    /// Expanded width is retired.
    public static let display = Font.system(.largeTitle, design: .default, weight: .semibold)
      .width(.condensed)
    /// Sheet headers and hero card titles. Standard width: expanded width is retired, and the
    /// condensed face is kept for display and figures.
    public static let title = Font.system(.title3, design: .default, weight: .semibold)
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
  /// Button Shapes. A custom style bypasses the system's own rendering of it, so a quiet button,
  /// accent text with no fill, stayed indistinguishable from coloured text for exactly the people
  /// who asked to see the difference. With it on, a quiet button wears the secondary outline.
  @Environment(\.accessibilityShowButtonShapes) private var showsButtonShapes

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
        if role == .secondary || (role == .quiet && showsButtonShapes) {
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
