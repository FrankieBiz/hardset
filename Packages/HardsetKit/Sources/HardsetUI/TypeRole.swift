import SwiftUI

extension Tokens.Text {
  /// Every type role as a value, so a view can ask for a role by name and get the font together
  /// with the tracking that belongs to it.
  ///
  /// The static fonts above stay for existing call sites. A static `Font` cannot carry tracking,
  /// and a fixed point value would not scale with Dynamic Type: tightening large condensed
  /// figures by a constant would collide their letters at accessibility sizes. A role instead
  /// states tracking as a ratio of the resolved text size, applied by `HardsetTextModifier`.
  public enum Role: Sendable, CaseIterable, Hashable {
    case display
    case title
    case headline
    case label
    case provenance
    case unit
    case caption
    case sectionHeader
    case hero
    case readout
    case setEntry
    case figure
    /// A figure the lifter typed or the app counted, in a set row or a ledger. 44 pt.
    case figureXL
    /// The rest countdown. 64 pt.
    case countdown
    /// The one measured figure a screen leads with. 88 pt, at most one per screen.
    case monument

    /// The matching static font, so a role and its static can never disagree.
    ///
    /// For `figureXL`, `countdown` and `monument` it is the font at the role's base size, which does
    /// not scale with Dynamic Type; `hardsetText(_:)` is how those roles are set.
    public var font: Font {
      switch self {
      case .display: Tokens.Text.display
      case .title: Tokens.Text.title
      case .headline: Tokens.Text.headline
      case .label: Tokens.Text.label
      case .provenance: Tokens.Text.provenance
      case .unit: Tokens.Text.unit
      case .caption: Tokens.Text.caption
      case .sectionHeader: Tokens.Text.sectionHeader
      case .hero: Tokens.Text.hero
      case .readout: Tokens.Text.readout
      case .setEntry: Tokens.Text.setEntry
      case .figure: Tokens.Text.figure
      case .figureXL: Tokens.Text.figureXL
      case .countdown: Tokens.Text.countdown
      case .monument: Tokens.Text.monument
      }
    }

    /// The font at a size already scaled for the current Dynamic Type setting. The three scale
    /// roles are built from the scaled size; every other role is a text style and scales itself.
    func scaledFont(_ size: CGFloat) -> Font {
      switch self {
      case .figureXL, .countdown, .monument:
        Font.system(size: size, weight: .semibold, design: .default)
          .width(.condensed).monospacedDigit()
      default:
        font
      }
    }

    /// The Dynamic Type text style the font is built from. The modifier scales its tracking
    /// size relative to this style, so tracking follows the same curve as the glyphs.
    public var textStyle: Font.TextStyle {
      switch self {
      case .hero, .countdown, .monument: .largeTitle
      case .display, .readout, .figureXL: .title
      case .setEntry: .title2
      case .title: .title3
      case .headline, .figure: .headline
      case .label: .body
      case .provenance, .unit: .callout
      case .sectionHeader: .subheadline
      case .caption: .footnote
      }
    }

    /// The default point size of `textStyle` at the standard content size. It seeds the scaled
    /// size the tracking is computed from, so the result matches the rendered glyphs.
    public var baseSize: CGFloat {
      switch self {
      // The three scale roles are not a text style's size; they scale along the curve of the
      // style they are set against, from their own size.
      case .figureXL: return 44
      case .countdown: return 64
      case .monument: return 88
      default: break
      }
      return switch textStyle {
      case .largeTitle: 34
      case .title: 28
      case .title2: 22
      case .title3: 20
      case .headline: 17
      case .body: 17
      case .callout: 16
      case .subheadline: 15
      case .footnote: 13
      default: 17
      }
    }

    /// Whether a figure that is an estimate may be drawn in this role: its size at the default
    /// content size is within `Tokens.Text.estimateCeiling`. False for `hero` and for the three
    /// scale roles, so a formula's output can never be set at the size of a measurement.
    public var mayCarryEstimate: Bool {
      baseSize <= Tokens.Text.estimateCeiling
    }

    /// The largest Dynamic Type size the role grows to, or `nil` for a role that grows with the
    /// whole range. The three scale roles stop at accessibility1: at 44 to 88 pt they are already
    /// larger than body text at the biggest setting, and growing further would push a figure wider
    /// than the row or card that holds it. The words around a figure keep scaling.
    public var maximumDynamicTypeSize: DynamicTypeSize? {
      switch self {
      case .figureXL, .countdown, .monument: .accessibility1
      default: nil
      }
    }

    /// Tracking as a fraction of the text size. Large condensed figures tighten slightly so the
    /// stamped figures sit as one plate; the small roles open slightly for legibility. Every
    /// other role keeps the font's own spacing, `display` included: the system font applies its
    /// own optical tracking at large sizes, and a second value on top would be a guess.
    public var trackingRatio: Double {
      switch self {
      case .hero, .figureXL, .countdown, .monument: -0.02
      case .readout: -0.01
      case .caption, .unit: 0.01
      case .display, .title, .headline, .label, .provenance, .sectionHeader, .setEntry, .figure:
        0
      }
    }
  }
}

/// Applies a type role's font and its tracking, with the tracking computed from the size the
/// text actually resolves to under the current Dynamic Type setting.
///
/// A fixed tracking value in points would be right at one size and wrong at every other. Scaling
/// the size with `ScaledMetric` and multiplying by the role's ratio keeps negative tracking
/// proportional, so large condensed figures never collide at accessibility sizes.
public struct HardsetTextModifier: ViewModifier {
  private let role: Tokens.Text.Role
  @ScaledMetric private var size: CGFloat

  public init(role: Tokens.Text.Role) {
    self.role = role
    _size = ScaledMetric(wrappedValue: role.baseSize, relativeTo: role.textStyle)
  }

  public func body(content: Content) -> some View {
    content
      .font(role.scaledFont(size))
      .tracking(size * role.trackingRatio)
  }
}

/// Applies a type role's font at a different weight, with the role's tracking.
///
/// Holds the same `ScaledMetric` size as `HardsetTextModifier`, so the tracking is computed from
/// the size the text resolves to and matches an unweighted use of the role exactly. A weighted
/// font is a static `Font` and cannot carry tracking, and a weight modifier chained after
/// `.hardsetText(_:)` is not used in this repository, so a weighted variant of a tracked
/// role is written through this modifier.
struct HardsetWeightedTextModifier: ViewModifier {
  private let role: Tokens.Text.Role
  private let weight: Font.Weight
  @ScaledMetric private var size: CGFloat

  init(role: Tokens.Text.Role, weight: Font.Weight) {
    self.role = role
    self.weight = weight
    _size = ScaledMetric(wrappedValue: role.baseSize, relativeTo: role.textStyle)
  }

  func body(content: Content) -> some View {
    content
      .font(role.scaledFont(size).weight(weight))
      .tracking(size * role.trackingRatio)
  }
}

extension View {
  /// Sets the text's font and size-proportional tracking from a design-system type role.
  public func hardsetText(_ role: Tokens.Text.Role) -> some View {
    modifier(HardsetTextModifier(role: role)).hardsetDynamicTypeCap(role)
  }

  /// Sets the text from a design-system type role at the given weight, with the role's tracking.
  public func hardsetText(_ role: Tokens.Text.Role, weight: Font.Weight) -> some View {
    modifier(HardsetWeightedTextModifier(role: role, weight: weight)).hardsetDynamicTypeCap(role)
  }

  /// Stops the role's growth at its `maximumDynamicTypeSize`. Applied outside the modifier that
  /// reads the scaled size, so the size it reads is the capped one.
  @ViewBuilder
  func hardsetDynamicTypeCap(_ role: Tokens.Text.Role) -> some View {
    if let cap = role.maximumDynamicTypeSize {
      dynamicTypeSize(...cap)
    } else {
      self
    }
  }
}
