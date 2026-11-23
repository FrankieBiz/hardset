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

    // MARK: Steel: canvas and surfaces
    //
    // Surfaces separate by fill, not by line. Canvas to `steel` is 1.18:1 in dark and 1.12:1 in
    // light, and `steelRaised` on `steel` is 1.14:1 in dark and 1.16:1 in light, so a card needs
    // no border. `steelRaised` cannot be brighter in dark: `plateBlue` text on it is 7.12:1
    // against the 7:1 floor. `Tools/check_contrast.py` gates the steps as well as the text.

    /// The screen canvas: the deepest graphite in dark, Apple's grouped background in light.
    public static let canvas = swatch(
      light: 0xF2F2F7, dark: 0x050608, highLight: 0xFFFFFF, highDark: 0x000000
    )
    /// Cards, rows and the content of sheets.
    public static let steel = swatch(
      light: 0xFFFFFF, dark: 0x1A1B21, highLight: 0xFFFFFF, highDark: 0x000000
    )
    /// One step above `steel`: fields, keys, chips and secondary buttons that sit on `steel`.
    public static let steelRaised = swatch(
      light: 0xEEEEF2, dark: 0x24262D, highLight: 0xFFFFFF, highDark: 0x000000
    )
    /// The fill of a control that sits directly on `canvas`: header buttons, and the secondary
    /// buttons of a screen with no card around them.
    ///
    /// Light `steelRaised` on `canvas` is only 1.04:1, so on canvas a control is white, 1.12:1.
    /// In dark it is the same colour as `steelRaised`. Under Increase Contrast it collapses to
    /// pure white or black with the rest of the steps, and the outline comes back.
    public static let controlFillOnCanvas = swatch(
      light: 0xFFFFFF, dark: 0x24262D, highLight: 0xFFFFFF, highDark: 0x000000
    )
    /// The momentary fill of a pressed key or secondary button. In both normal appearances it is
    /// darker than `steelRaised`, so a press sinks rather than lights up. Opaque, so text on it
    /// stays measurable rather than depending on what happens to be underneath.
    ///
    /// Dark is `#111216`, below the first sleeker-pass spec's `#1B1C22`. With no outline to hold the
    /// boundary, that value was 1.01:1 against the new dark `steel`, so a pressed button or chip
    /// inside a card lost its face entirely. `#111216` is 1.09:1 against `steel`, 1.08:1 against
    /// `canvas` and 1.24:1 below `steelRaised`, so it reads as sunk on every surface it is pressed
    /// on. `Tools/check_contrast.py` gates both steps.
    public static let steelPressed = swatch(
      light: 0xE6E6EB, dark: 0x111216, highLight: 0xE6E6EA, highDark: 0x26262B
    )
    /// Subtle charcoal hairline for separators inside a card or grouped rows, and the card's
    /// outline under Increase Contrast.
    ///
    /// Decorative grouping only. It is never what tells the lifter something is tappable.
    public static let hairline = swatch(
      light: 0xDEDEE4, dark: 0x2E3039, highLight: 0x595964, highDark: 0x9B9BA5
    )
    /// The outline of an input, and of every control under Increase Contrast or Button Shapes.
    /// At least 3:1 against `canvas`, `steel`, `steelRaised`, `controlFillOnCanvas` and
    /// `steelPressed`, since a pressed face keeps it. A labelled button, key, chip or header
    /// button on a normal appearance is identified by its fill and its label instead, and does
    /// not draw it; see `ControlOutline`.
    public static let controlEdge = swatch(
      light: 0x7E8190, dark: 0x7B7E8C, highLight: 0x595964, highDark: 0x9B9BA5
    )
    /// The unfilled part of a gauge that says where the lifter stands: the inactive segments of the
    /// first-launch pages' three-segment progress.
    ///
    /// Required information, so not `hairline`, which is for decoration and measures 1.54:1 on dark
    /// `canvas` and 1.20:1 on light (ruling D22). At least 3:1 on `canvas` in all four appearances:
    /// 3.06 dark, 3.15 light, 3.17 dark and 3.51 light under Increase Contrast.
    ///
    /// One pair with no Increase Contrast override, on purpose. `controlEdge`'s own Increase Contrast
    /// pair is made loud against pure black and white, and `plateBlue`'s is not far from it, so the
    /// active segment would sit at about 1.7:1 and 1.6:1 against the inactive ones: the indicator
    /// would read as the quieter of the two at the setting a low-vision lifter turns on. Against this
    /// pair the `plateBlue` segment is 3.12:1 dark and 2.47:1 light, and 4.08:1 and 3.20:1 under
    /// Increase Contrast. `Tools/check_contrast.py` gates both the 3:1 and that order.
    ///
    /// Drawn on `canvas` only. On dark `steel` it measures 2.60:1, which is why the gate does not
    /// list `steel`.
    public static let gaugeTrack = swatch(light: 0x888892, dark: 0x5C5C65)

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
    /// red appears here: those already mean something. The first is chalk, so a movement on one
    /// machine, which is most of them, draws a monochrome line: a screen with no primary action has
    /// no accent to spend, and `plateBlue` only appears when a second machine needs a second hue.
    public static let series: [SwiftUI.Color] = [
      swatch(light: 0x3A3A42, dark: 0xE7E7EC),
      plateBlue,
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

  /// Corner radii. Every one is drawn continuous, through `Tokens.Shape`, so a corner is the
  /// system's own curve and not a circular arc.
  ///
  /// Concentric: inner radius is outer radius minus the padding between them. A card of 24 with
  /// 12 of padding holds controls of 12. Capsules and circles are reserved for chips, badges and
  /// the logged seal, and sheets take the system's own corner radius.
  public enum Radius {
    public static let control: CGFloat = 12
    public static let card: CGFloat = 24
    /// The ends of a gauge bar. Skin only: the bar's scale is unchanged.
    public static let bar: CGFloat = 4
  }

  /// The continuous rounded rectangles the radii describe, in one place so a radius change or a
  /// corner-style change is one edit and not one per call site.
  ///
  /// `RoundedRectangle(cornerRadius:)` alone draws a circular arc, which is not what the system
  /// draws; every new use names one of these instead.
  public enum Shape {
    public static let card = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
    public static let control = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
    public static let bar = RoundedRectangle(cornerRadius: Radius.bar, style: .continuous)

    /// A continuous rounded rectangle of any radius, for the one place a token radius is
    /// adjusted, such as an indicator inset inside its track.
    public static func rounded(_ radius: CGFloat) -> RoundedRectangle {
      RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
  }

  public enum Stroke {
    public static let hairline: CGFloat = 1
    public static let selected: CGFloat = 2
  }

  /// A soft shadow for a surface that is pinned over scrolling content and so cannot be told from
  /// the cards beneath it by fill alone: the rest bar.
  ///
  /// Material-free by decision. Glass would put the most-read number in the app on a surface the
  /// contrast gate can only model, so pinned chrome stays opaque and is separated by a fill step
  /// and this shadow. Light appearance only: in dark the 1.34:1 step to `canvas` does the
  /// separating and a black shadow on near-black adds nothing. The values are a starting point to
  /// be tuned on a device. It animates nothing.
  public enum Elevation {
    public static let floatingOpacity: Double = 0.12
    public static let floatingRadius: CGFloat = 12
    public static let floatingOffset: CGFloat = 2
  }

  /// Type roles. Every one is a Dynamic Type text style, so all of them scale.
  ///
  /// Figures use SF Pro Condensed with tabular digits. Condensed is the functional choice, not a
  /// flourish: a pound value such as "132.28" fits a set-row field at full size, where the rounded
  /// face had to shrink it to 60% -- about 12 pt -- to avoid wrapping. Condensed is for figures
  /// only: a sentence that happens to hold figures is `title` with tabular digits.
  public enum Text {
    /// Tab screen headers. Semibold at Title size (28 pt), in the system's standard width: the
    /// system font applies its own optical size and tracking, so none is added. A title is the word
    /// that names a screen and a figure is its content, so the title steps down below the figures
    /// it sits over instead of competing with them. Condensed is kept for the figures beneath it.
    public static let display = Font.system(.title, design: .default, weight: .semibold)
    /// Sheet headers, hero card titles, and a sentence that holds figures. Standard width:
    /// expanded width is retired, and the condensed face is kept for figures.
    public static let title = Font.system(.title3, design: .default, weight: .semibold)
    /// Card and row titles, primary button labels, and emphasised labels.
    public static let headline = Font.headline

    /// The keypad's display and the welcome bar's total.
    public static let hero = Font.system(.largeTitle, design: .default, weight: .semibold)
      .width(.condensed).monospacedDigit()
    /// Numeric readouts use a monospaced digit width so a ticking value does not reflow.
    ///
    /// This is the largest a figure may be when it is not a measurement. See `estimateCeiling`.
    public static let readout = Font.system(.title, design: .default, weight: .semibold)
      .width(.condensed).monospacedDigit()
    public static let setEntry = Font.system(.title2, design: .default, weight: .semibold)
      .width(.condensed).monospacedDigit()
    /// Small figures inside rows and ledgers: "last time" values, counts, durations.
    public static let figure = Font.system(.headline, design: .default, weight: .semibold)
      .width(.condensed).monospacedDigit()

    // MARK: Scale

    /// The largest a figure may be, in points at the default content size, when the number is an
    /// estimate and not a measurement: an Epley one-rep max, a fractional muscle credit, a change
    /// in either. A formula's output can be wrong in ways a lifter cannot see, so it is never drawn
    /// larger than a number the lifter typed or the app counted.
    ///
    /// The four figure roles below, `figureXL`, `countdown`, `monument` and `monumentAside`, are for
    /// measurements only, and `Role.mayCarryEstimate` is false for each of them. That is the
    /// scale's whole argument: size is earned by being measured, so the biggest numbers on a screen
    /// are the ones that can be trusted without a caveat. `Tools/check_figure_cap.py` holds each of
    /// the three to the files that draw measurements.
    public static let estimateCeiling: CGFloat = 28

    /// A figure the lifter typed or the app counted, in a set row or a ledger: 44 pt. Fixed point
    /// sizes in this block do not scale; `hardsetText(_:)` scales them with Dynamic Type, up to the
    /// role's `maximumDynamicTypeSize`, and is the way to set them.
    static let figureXL = Font.system(size: 44, weight: .semibold, design: .default)
      .width(.condensed).monospacedDigit()
    /// The rest countdown, the one number read at arm's length mid-set: 64 pt.
    static let countdown = Font.system(size: 64, weight: .semibold, design: .default)
      .width(.condensed).monospacedDigit()
    /// The one measured figure a screen leads with, at most one per screen: 88 pt. The monument is 88
    /// where the screen's subject is the number, and `monumentAside` is 72 where the screen's subject
    /// is the action. Weekly working sets on Volume, where the number is the content. A screen with
    /// no measured figure to lead with has none.
    static let monument = Font.system(size: 88, weight: .semibold, design: .default)
      .width(.condensed).monospacedDigit()
    /// The monument on a screen whose subject is an action: 72 pt. The last workout's volume on Train,
    /// where the primary action is starting a workout and a number that outranked it would make the
    /// screen harder to use.
    static let monumentAside = Font.system(size: 72, weight: .semibold, design: .default)
      .width(.condensed).monospacedDigit()

    public static let label = Font.body
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
    ///
    /// A critically damped spring (damping fraction 1.0) rather than a fixed-duration ease: it
    /// settles without overshoot, and when a change is reversed mid-flight it carries the
    /// current velocity into the new target instead of restarting a curve from rest.
    public static let state = Animation.spring(response: 0.30, dampingFraction: 1.0)
    /// Banners and inline confirmations arriving. Its length is `LogMoment.revealDuration`, so the
    /// log moment's plan and the reveal it draws cannot disagree.
    public static let reveal = Animation.easeOut(duration: LogMoment.revealDuration)
    /// The log check stamping in. The only spring with bounce outside a gesture release. Its length
    /// is `LogMoment.sealDuration`.
    public static let stamp = Animation.spring(duration: LogMoment.sealDuration, bounce: 0.3)

    /// The second beat of the log moment: the reveal, started `LogMoment.followDelay` after the
    /// stamp. The "+1 rep" mark, the rest bar and the record notice use it, so they arrive together
    /// and just after the seal lands instead of on three clocks of their own. `nil` under Reduce
    /// Motion, where they appear with the seal in the same frame and nothing is delayed.
    public static func follow(reduceMotion: Bool) -> Animation? {
      reduceMotion ? nil : reveal.delay(LogMoment.followDelay)
    }

    /// A release that hands the gesture's own velocity to the settle, such as a sheet or a card
    /// let go mid-drag.
    ///
    /// Interpolating springs are additive, so a new target re-aimed mid-flight keeps the motion
    /// continuous. Pass the release velocity, normalised by the distance still to travel, so
    /// the object keeps the speed the finger gave it. Named `fling` because `throw` is a keyword.
    public static func fling(initialVelocity: Double = 0) -> Animation {
      .interpolatingSpring(Spring(response: 0.35, dampingRatio: 0.80), initialVelocity: initialVelocity)
    }

    // Zoom: screen-to-screen zoom uses `navigationTransition(.zoom)` and carries no animation
    // token. The system owns its timing, interruption and Reduce Motion behaviour, so a token
    // here would only be a second, competing source of truth.

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

/// A card: a `steel` fill on a continuous corner, and no border.
///
/// Separation is the step from `steel` to `canvas`. Selected, the card takes `plateBlueSurface`
/// and a 2 pt `plateBlue` ring, because selection is state and not structure. Under Increase
/// Contrast, where `canvas` and `steel` are one colour and the step is gone, an unselected card
/// wears a `hairline` border instead.
///
/// Everything inside a card is drawn on `steel`, so a button, chip or header button in it takes
/// `steelRaised` and not the canvas fill.
public struct HardsetCardModifier: ViewModifier {
  public let isSelected: Bool
  public let cornerRadius: CGFloat

  @Environment(\.colorSchemeContrast) private var contrast

  public init(isSelected: Bool = false, cornerRadius: CGFloat = Tokens.Radius.card) {
    self.isSelected = isSelected
    self.cornerRadius = cornerRadius
  }

  public func body(content: Content) -> some View {
    let shape = Tokens.Shape.rounded(cornerRadius)
    content
      .hardsetControlSurface(.steel)
      .background(
        isSelected ? Tokens.Color.plateBlueSurface : Tokens.Color.steel,
        in: shape
      )
      .overlay {
        if isSelected {
          shape.strokeBorder(Tokens.Color.plateBlue, lineWidth: Tokens.Stroke.selected)
        } else if contrast == .increased {
          shape.strokeBorder(Tokens.Color.hairline, lineWidth: Tokens.Stroke.hairline)
        }
      }
  }
}

/// A raised panel for a message or a bar pinned over the list: `steelRaised` on a continuous `card`
/// radius, no colour, no border. It is the one raised tone the live session uses, so the rest bar
/// and a record notice stand on the same step off the canvas, and what a panel says is carried by
/// its words and a small mark and never by its fill. Pinned over scrolling content, it takes
/// `Elevation.floating`, which draws in light appearance only. Under Increase Contrast, where the
/// fill step is gone, it wears a `hairline` border, as a card does.
public struct HardsetPanelModifier: ViewModifier {
  @Environment(\.colorSchemeContrast) private var contrast

  public init() {}

  public func body(content: Content) -> some View {
    content
      .background(Tokens.Color.steelRaised, in: Tokens.Shape.card)
      .overlay {
        if contrast == .increased {
          Tokens.Shape.card.strokeBorder(Tokens.Color.hairline, lineWidth: Tokens.Stroke.hairline)
        }
      }
      .hardsetFloating()
  }
}

/// A sheet's background and chrome. The corner radius is the system's own, which is concentric
/// with the device's corners; overriding it with a token only made it differ from every other
/// sheet on the phone.
public struct HardsetSheetModifier: ViewModifier {
  public init() {}

  public func body(content: Content) -> some View {
    content
      .presentationBackground(Tokens.Color.canvas)
      .presentationDragIndicator(.visible)
      .tint(Tokens.Color.plateBlue)
  }
}

/// The soft shadow of a pinned opaque surface. See `Tokens.Elevation`.
struct HardsetFloatingModifier: ViewModifier {
  @Environment(\.colorScheme) private var colorScheme

  func body(content: Content) -> some View {
    content.shadow(
      color: colorScheme == .light ? .black.opacity(Tokens.Elevation.floatingOpacity) : .clear,
      radius: Tokens.Elevation.floatingRadius,
      x: 0,
      y: Tokens.Elevation.floatingOffset
    )
  }
}

public extension View {
  func hardsetCard(selected: Bool = false, cornerRadius: CGFloat = Tokens.Radius.card) -> some View {
    modifier(HardsetCardModifier(isSelected: selected, cornerRadius: cornerRadius))
  }

  func hardsetSheet() -> some View {
    modifier(HardsetSheetModifier())
  }

  /// Puts the view on the one raised panel tone. See `HardsetPanelModifier`.
  func hardsetPanel() -> some View {
    modifier(HardsetPanelModifier())
  }

  /// Lifts a pinned opaque surface off the content scrolling beneath it with a soft shadow, in
  /// light appearance only. The fill step does the separating in dark.
  func hardsetFloating() -> some View {
    modifier(HardsetFloatingModifier())
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
    /// A flat fill that steps off its surface, with no outline. For the actions of a state that
    /// are not the one thing the lifter came to do.
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
    HardsetButtonFace(
      role: role,
      size: size,
      fullWidth: fullWidth,
      isPressed: configuration.isPressed,
      isEnabled: isEnabled
    ) {
      configuration.label
    }
    .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
    .animation(
      Tokens.Motion.adaptive(Tokens.Motion.press, reduceMotion: reduceMotion),
      value: configuration.isPressed
    )
  }
}

/// A button's face in a given state: the label set in the role's type and colour, laid out to the
/// size's tap target, on the role's surface, with the disabled and pressed opacity rules.
///
/// `HardsetButtonStyle` draws its live buttons with it, and the token catalogue draws its pressed
/// samples with it, because a `ButtonStyle` cannot be forced pressed in a render. Sharing the face
/// keeps the catalogue honest: a sample cannot drift from what a press actually shows. The press
/// scale and its animation stay in the style, since they are motion rather than a face.
///
/// No role is outlined by default: a button is identified by its fill and its verb. Under Increase
/// Contrast or Button Shapes every role but `primary`, whose fill is already about 8:1 against its
/// surface, wears the `controlEdge` outline, in both states, so the boundary is there exactly
/// where the lifter asked for it and never disappears under a finger. The face reads both settings
/// itself, so a catalogue render under either shows the outline without being told.
struct HardsetButtonFace<Label: View>: View {
  private let role: HardsetButtonStyle.Role
  private let size: HardsetButtonStyle.Size
  private let fullWidth: Bool
  private let isPressed: Bool
  private let isEnabled: Bool
  private let label: Label

  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.accessibilityShowButtonShapes) private var showsButtonShapes

  init(
    role: HardsetButtonStyle.Role,
    size: HardsetButtonStyle.Size,
    fullWidth: Bool,
    isPressed: Bool,
    isEnabled: Bool,
    @ViewBuilder label: () -> Label
  ) {
    self.role = role
    self.size = size
    self.fullWidth = fullWidth
    self.isPressed = isPressed
    self.isEnabled = isEnabled
    self.label = label()
  }

  var body: some View {
    let shape = Tokens.Shape.control
    surface(
      label
        .font(Tokens.Text.headline)
        .foregroundStyle(foreground)
        .multilineTextAlignment(.center)
        .padding(.horizontal, role == .quiet ? Tokens.Spacing.snug : Tokens.Spacing.loose)
        .padding(.vertical, Tokens.Spacing.snug)
        .frame(
          maxWidth: fullWidth ? .infinity : nil,
          minHeight: size == .logger ? Tokens.loggerTapTarget : Tokens.minimumTapTarget
        ),
      shape: shape
    )
    .contentShape(shape)
    .opacity(opacity)
  }

  /// Disabled dims every role to 40%. A pressed quiet or destructive button, which has no pressed
  /// fill to swap, dims to 60%.
  private var opacity: Double {
    guard isEnabled else { return 0.4 }
    return (role == .quiet || role == .destructive) && isPressed ? 0.6 : 1
  }

  /// Draws the role's face behind the label. The tiers, from most to least weight: `primary` is a
  /// solid plate-blue fill, one per state, swapping to its pressed fill; `secondary` is a flat
  /// fill that steps off its surface and sinks to `steelPressed`; `quiet` is plate-blue text with
  /// no fill; `destructive` is red text on the error surface. The role never changes across a
  /// press, so each branch is one view whose pressed state only changes its arguments, and the
  /// label keeps its identity. A modifier that returns `some View` cannot be applied
  /// conditionally inline, so the choice is made here.
  @ViewBuilder
  private func surface<Content: View>(_ content: Content, shape: RoundedRectangle) -> some View {
    let request = ControlEdgeRequest(contrast: contrast, showsButtonShapes: showsButtonShapes)
    switch role {
    case .primary:
      content.background(
        isPressed ? Tokens.Color.plateBlueFillPressed : Tokens.Color.plateBlueFill,
        in: shape
      )
    case .secondary:
      content.modifier(ControlFaceModifier(shape: shape, isPressed: isPressed, outline: .onRequest))
    case .quiet:
      content
        .overlay {
          if request.isRequested {
            shape.strokeBorder(Tokens.Color.controlEdge, lineWidth: Tokens.Stroke.hairline)
          }
        }
    case .destructive:
      content
        .background(Tokens.Color.plateRedSurface, in: shape)
        .overlay {
          if request.isRequested {
            shape.strokeBorder(Tokens.Color.controlEdge, lineWidth: Tokens.Stroke.hairline)
          }
        }
    }
  }

  private var foreground: Color {
    switch role {
    case .primary: Tokens.Color.onPlateBlue
    case .secondary: Tokens.Color.chalk
    case .quiet: Tokens.Color.plateBlue
    case .destructive: Tokens.Color.plateRed
    }
  }
}

/// A keypad key: its figure or glyph in `chalk` over the keypad's `steel` panel, with no face and no
/// fill, and no outline until one is asked for. A key is a 56 pt cell that is a third of the pad's width, and the numeral is
/// what the lifter sees.
///
/// Pressed, the key sinks to 0.96 and dims to 80% on `Motion.press`, as every control with no face
/// of its own does, and Reduce Motion drops the scale. Where the lifter has asked for boundaries,
/// through Increase Contrast or Button Shapes, each key wears the 3:1 `controlEdge` outline around
/// its whole cell, so the boundary comes back exactly where it was asked for.
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
    HardsetKeyFace(isPressed: configuration.isPressed, isEnabled: isEnabled) {
      configuration.label
    }
    .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
    .animation(
      Tokens.Motion.adaptive(Tokens.Motion.press, reduceMotion: reduceMotion),
      value: configuration.isPressed
    )
  }
}

/// A key in a given state: the chalk label in a logger-height cell the width of its column, dimmed
/// while pressed or disabled, and outlined only where Increase Contrast or Button Shapes asks.
/// Shared by `HardsetKeyStyle` and the token catalogue's pressed keys, because a `ButtonStyle`
/// cannot be forced pressed in a render.
struct HardsetKeyFace<Label: View>: View {
  private let isPressed: Bool
  private let isEnabled: Bool
  private let label: Label

  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.accessibilityShowButtonShapes) private var showsButtonShapes

  init(isPressed: Bool, isEnabled: Bool, @ViewBuilder label: () -> Label) {
    self.isPressed = isPressed
    self.isEnabled = isEnabled
    self.label = label()
  }

  var body: some View {
    let request = ControlEdgeRequest(contrast: contrast, showsButtonShapes: showsButtonShapes)
    label
      .foregroundStyle(Tokens.Color.chalk)
      .frame(maxWidth: .infinity, minHeight: Tokens.loggerTapTarget)
      .overlay {
        if request.isRequested {
          Tokens.Shape.control
            .strokeBorder(Tokens.Color.controlEdge, lineWidth: Tokens.Stroke.hairline)
        }
      }
      .contentShape(Rectangle())
      .opacity(isEnabled ? (isPressed ? 0.8 : 1) : 0.4)
  }
}
