import SwiftUI

// Shared building blocks. Each one exists because at least two screens needed it and were about
// to draw it differently. See `DESIGN.md` for the states each is expected to cover.

// MARK: - Screen header

/// The top of a tab screen: a display title, one line of context, and at most one action.
///
/// Drawn in the content rather than as a navigation-bar large title, so every tab opens on the same
/// expanded type instead of the stock bar, and so the context line -- which gym, which week -- sits
/// with the title it qualifies.
public struct ScreenHeader<Trailing: View>: View {
  private let title: String
  private let subtitle: String?
  private let trailing: Trailing

  public init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
    self.title = title
    self.subtitle = subtitle
    self.trailing = trailing()
  }

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  /// Title and action share a line at ordinary sizes. At accessibility sizes the action sits on
  /// its own line above the title, at the trailing edge: beside it, a one-word title such as
  /// "Workout" in expanded display type had to break mid-word.
  public var body: some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .trailing, spacing: Tokens.Spacing.snug) {
          trailing
          titleBlock
        }
      } else {
        HStack(alignment: .top, spacing: Tokens.Spacing.regular) {
          titleBlock
          trailing
        }
      }
    }
    .padding(.horizontal, Tokens.Spacing.loose)
    .padding(.top, Tokens.Spacing.snug)
  }

  private var titleBlock: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
      Text(title)
        .font(Tokens.Text.display)
        .foregroundStyle(Tokens.Color.textPrimary)
        .accessibilityAddTraits(.isHeader)
      if let subtitle, !subtitle.isEmpty {
        Text(subtitle)
          .font(Tokens.Text.label)
          .foregroundStyle(Tokens.Color.textSecondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

extension ScreenHeader where Trailing == EmptyView {
  public init(_ title: String, subtitle: String? = nil) {
    self.init(title, subtitle: subtitle) { EmptyView() }
  }
}

/// A round, outlined icon button for a screen header's single action, such as Settings.
public struct HeaderIconButton: View {
  private let systemImage: String
  private let accessibilityLabel: String
  private let action: () -> Void

  public init(systemImage: String, accessibilityLabel: String, action: @escaping () -> Void) {
    self.systemImage = systemImage
    self.accessibilityLabel = accessibilityLabel
    self.action = action
  }

  public var body: some View {
    Button(action: action) {
      HeaderIconGlyph(systemImage: systemImage)
    }
    .buttonStyle(HardsetPressStyle())
    .accessibilityLabel(accessibilityLabel)
    // The Large Content Viewer is iOS-only; the macOS host build (tests only) goes without it.
    #if os(iOS)
      .accessibilityShowsLargeContentViewer {
        Label(accessibilityLabel, systemImage: systemImage)
      }
    #endif
  }
}

/// The same round, outlined control as `HeaderIconButton`, opening a menu of actions instead.
///
/// For the handful of actions that belong to a whole thing -- a workout, a movement -- and are not
/// used every set: they stay one tap away without each taking a full-width button.
public struct HeaderIconMenu<Content: View>: View {
  private let systemImage: String
  private let accessibilityLabel: String
  private let content: Content

  public init(
    systemImage: String = "ellipsis",
    accessibilityLabel: String,
    @ViewBuilder content: () -> Content
  ) {
    self.systemImage = systemImage
    self.accessibilityLabel = accessibilityLabel
    self.content = content()
  }

  public var body: some View {
    Menu {
      content
    } label: {
      HeaderIconGlyph(systemImage: systemImage)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(accessibilityLabel)
    // The Large Content Viewer is iOS-only; the macOS host build (tests only) goes without it.
    #if os(iOS)
      .accessibilityShowsLargeContentViewer {
        Label(accessibilityLabel, systemImage: systemImage)
      }
    #endif
  }
}

/// The circle both header controls draw: raised fill, measured control border, a 44 pt target.
///
/// It grows with text up to the largest ordinary size and stops there, about 60 pt across. Grown
/// linearly to the largest accessibility size it reached about 137 pt and squeezed the screen
/// title beside it; past the cap, the Large Content Viewer shows the symbol and its name, as the
/// system's own bar buttons do.
struct HeaderIconGlyph: View {
  let systemImage: String

  init(systemImage: String) {
    self.systemImage = systemImage
  }

  var body: some View {
    HeaderIconGlyphFace(systemImage: systemImage)
      .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
  }
}

private struct HeaderIconGlyphFace: View {
  let systemImage: String
  /// Scales with the glyph. A fixed 44 pt circle let the symbol spill outside it at larger text
  /// sizes.
  @ScaledMetric(relativeTo: .headline) private var diameter = Tokens.minimumTapTarget

  var body: some View {
    Image(systemName: systemImage)
      .font(Tokens.Text.headline)
      .foregroundStyle(Tokens.Color.textPrimary)
      .frame(width: diameter, height: diameter)
      .background(Tokens.Color.surfaceRaised, in: Circle())
      .overlay(Circle().strokeBorder(Tokens.Color.controlBorder, lineWidth: Tokens.Stroke.hairline))
      .contentShape(Circle())
  }
}

// MARK: - Navigation chrome

public extension View {
  /// For a tab's root screen that draws its own `ScreenHeader`.
  ///
  /// Hides the stock navigation bar on iOS, and lays the background colour under the status bar
  /// so content scrolled upward disappears beneath it instead of colliding with the clock.
  func hardsetTabRoot() -> some View {
    modifier(TabRootChrome())
  }

  /// For a pushed or presented screen that keeps a navigation bar for its Done or Cancel action.
  ///
  /// Sets the accessible navigation title, and draws the visible one in the app's expanded title
  /// type, inline, in place of the system's default bar title.
  func hardsetNavigationTitle(_ title: String) -> some View {
    modifier(NavigationTitleChrome(title: title))
  }
}

private struct TabRootChrome: ViewModifier {
  func body(content: Content) -> some View {
    #if os(iOS)
      content
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
          // A zero-height inset touching the top safe-area edge: its background extends through
          // the status bar, which is exactly the region that needs covering.
          Color.clear
            .frame(height: 0)
            .background(Tokens.Color.background)
        }
    #else
      content
    #endif
  }
}

private struct NavigationTitleChrome: ViewModifier {
  let title: String

  func body(content: Content) -> some View {
    #if os(iOS)
      content
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .principal) {
            Text(title)
              .font(Tokens.Text.title)
              .foregroundStyle(Tokens.Color.textPrimary)
              .lineLimit(1)
              .minimumScaleFactor(0.8)
              .accessibilityAddTraits(.isHeader)
              // Bars cap their text size; the Large Content Viewer is how a bar title stays
              // readable at accessibility sizes, as Apple's own bar items do.
              .accessibilityShowsLargeContentViewer()
          }
        }
    #else
      content
        .navigationTitle(title)
    #endif
  }
}

// MARK: - Section label

/// A sentence-case section label, optionally with a count.
///
/// Replaces the tracked-out uppercase headers the pickers used to draw. A weight change separates a
/// section from its rows; capitals only make the words harder to read.
public struct SectionLabel: View {
  private let title: String
  private let count: Int?

  public init(_ title: String, count: Int? = nil) {
    self.title = title
    self.count = count
  }

  public var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.snug) {
      Text(title)
        .font(Tokens.Text.sectionHeader)
        .foregroundStyle(Tokens.Color.textPrimary)
      if let count {
        Text(count, format: .number)
          .font(Tokens.Text.caption.monospacedDigit())
          .foregroundStyle(Tokens.Color.textSecondary)
      }
      Spacer(minLength: 0)
    }
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isHeader)
  }
}

#if DEBUG
  private struct ComponentsHarness: View {
    @State private var unit = "kg"
    @State private var chip = true

    var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: Tokens.Spacing.section) {
          ScreenHeader("Train", subtitle: "Saturday 7 November") {
            HeaderIconButton(systemImage: "gearshape", accessibilityLabel: "Settings") {}
          }
          VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
            SectionLabel("Chest", count: 6)
            HardsetSegmentedControl(
              selection: $unit,
              segments: [HardsetSegment("kg", value: "kg"), HardsetSegment("lb", value: "lb")]
            )
            HStack {
              HardsetChip("All", isSelected: chip) { chip = true }
              HardsetChip("Back", isSelected: !chip) { chip = false }
            }
            StatLedger([
              .init(label: "Working sets", value: "12"),
              .init(label: "Reps", value: "96"),
              .init(label: "Volume", value: "9,400", unit: "kg"),
            ])
            HardsetBanner(
              .record, title: "Heaviest load", message: "105 kg, up from 100 kg")
            HardsetBanner(
              .error, message: "That set could not be saved. It has not been logged.")
            Button("Start workout") {}
              .buttonStyle(HardsetButtonStyle(.primary, size: .logger))
            Button("Finish workout") {}
              .buttonStyle(HardsetButtonStyle(.secondary))
            Button("How sets are counted") {}
              .buttonStyle(HardsetButtonStyle(.quiet, fullWidth: false))
          }
          .padding(.horizontal, Tokens.Spacing.loose)
        }
      }
      .background(Tokens.Color.background)
    }
  }

  #Preview("Components") {
    ComponentsHarness()
  }
#endif
