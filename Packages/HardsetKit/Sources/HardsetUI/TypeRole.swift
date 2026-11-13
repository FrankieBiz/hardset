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
    case labelEmphasis
    case provenance
    case unit
    case caption
    case sectionHeader
    case hero
    case readout
    case setEntry
    case figure

    /// The matching static font, so a role and its static can never disagree.
    public var font: Font {
      switch self {
      case .display: Tokens.Text.display
      case .title: Tokens.Text.title
      case .headline: Tokens.Text.headline
      case .label: Tokens.Text.label
      case .labelEmphasis: Tokens.Text.labelEmphasis
      case .provenance: Tokens.Text.provenance
      case .unit: Tokens.Text.unit
      case .caption: Tokens.Text.caption
      case .sectionHeader: Tokens.Text.sectionHeader
      case .hero: Tokens.Text.hero
      case .readout: Tokens.Text.readout
      case .setEntry: Tokens.Text.setEntry
      case .figure: Tokens.Text.figure
      }
    }

    /// The Dynamic Type text style the font is built from. The modifier scales its tracking
    /// size relative to this style, so tracking follows the same curve as the glyphs.
    public var textStyle: Font.TextStyle {
      switch self {
      case .display, .hero: .largeTitle
      case .readout: .title
      case .setEntry: .title2
      case .title: .title3
      case .headline, .figure: .headline
      case .label, .labelEmphasis: .body
      case .provenance, .unit: .callout
      case .sectionHeader: .subheadline
      case .caption: .footnote
      }
    }

    /// The default point size of `textStyle` at the standard content size. It seeds the scaled
    /// size the tracking is computed from, so the result matches the rendered glyphs.
    public var baseSize: CGFloat {
      switch textStyle {
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

    /// Tracking as a fraction of the text size. Large condensed faces tighten slightly so the
    /// stamped figures sit as one plate; the small roles open slightly for legibility. Every
    /// other role keeps the font's own spacing.
    public var trackingRatio: Double {
      switch self {
      case .hero, .display: -0.02
      case .readout: -0.01
      case .caption, .unit: 0.01
      case .title, .headline, .label, .labelEmphasis, .provenance, .sectionHeader, .setEntry,
        .figure:
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
      .font(role.font)
      .tracking(size * role.trackingRatio)
  }
}

extension View {
  /// Sets the text's font and size-proportional tracking from a design-system type role.
  public func hardsetText(_ role: Tokens.Text.Role) -> some View {
    modifier(HardsetTextModifier(role: role))
  }
}
