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

  public var body: some View {
    HStack(alignment: .top, spacing: Tokens.Spacing.regular) {
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
      trailing
    }
    .padding(.horizontal, Tokens.Spacing.loose)
    .padding(.top, Tokens.Spacing.snug)
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
      Image(systemName: systemImage)
        .font(Tokens.Text.headline)
        .foregroundStyle(Tokens.Color.textPrimary)
        .frame(width: Tokens.minimumTapTarget, height: Tokens.minimumTapTarget)
        .background(Tokens.Color.surfaceRaised, in: Circle())
        .overlay(Circle().strokeBorder(Tokens.Color.controlBorder, lineWidth: Tokens.Stroke.hairline))
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(accessibilityLabel)
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
              .accessibilityAddTraits(.isHeader)
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

// MARK: - Chip

/// A filter or tag chip. Capsule, outlined, and filled with the accent when selected.
///
/// The visible capsule is compact so a rail of them reads as one control, but the tappable region
/// is the full 44 pt minimum.
public struct HardsetChip: View {
  private let title: String
  private let isSelected: Bool
  private let action: () -> Void

  public init(_ title: String, isSelected: Bool, action: @escaping () -> Void) {
    self.title = title
    self.isSelected = isSelected
    self.action = action
  }

  public var body: some View {
    Button(action: action) {
      Text(title)
        .font(Tokens.Text.caption.weight(.semibold))
        .foregroundStyle(isSelected ? Tokens.Color.onAccent : Tokens.Color.textPrimary)
        .lineLimit(1)
        .padding(.horizontal, Tokens.Spacing.regular)
        .padding(.vertical, Tokens.Spacing.snug)
        .background(isSelected ? Tokens.Color.accentFill : Tokens.Color.surfaceRaised, in: Capsule())
        .overlay(
          Capsule().strokeBorder(
            isSelected ? Tokens.Color.accentFill : Tokens.Color.controlBorder,
            lineWidth: Tokens.Stroke.hairline
          )
        )
        .frame(minHeight: Tokens.minimumTapTarget)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
  }
}

// MARK: - Segmented control

/// One option in a `HardsetSegmentedControl`.
///
/// `nonisolated` so its computed `id` satisfies `Identifiable` without depending on isolated
/// conformance inference, as `SettingsSheet`'s `Disclosure` does.
public nonisolated struct HardsetSegment<Value: Hashable>: Identifiable {
  public let title: String
  public let value: Value
  public var id: Value { value }

  public init(_ title: String, value: Value) {
    self.title = title
    self.value = value
  }
}

/// Replaces the system segmented picker, which renders identically in every app and in a shade of
/// grey that does not meet this app's contrast floor.
///
/// Each segment is a full-height 44 pt button with the selected trait, and the indicator slides
/// between them on `Motion.state` -- or simply moves, with Reduce Motion on.
public struct HardsetSegmentedControl<Value: Hashable>: View {
  @Binding private var selection: Value
  private let segments: [HardsetSegment<Value>]
  @Namespace private var indicator
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  public init(selection: Binding<Value>, segments: [HardsetSegment<Value>]) {
    self._selection = selection
    self.segments = segments
  }

  public var body: some View {
    HStack(spacing: Tokens.Spacing.hairline) {
      ForEach(segments) { segment in
        Button {
          withAnimation(Tokens.Motion.adaptive(Tokens.Motion.state, reduceMotion: reduceMotion)) {
            selection = segment.value
          }
        } label: {
          Text(segment.title)
            .font(Tokens.Text.label.weight(.semibold))
            .foregroundStyle(
              segment.value == selection ? Tokens.Color.onAccent : Tokens.Color.textPrimary
            )
            .lineLimit(1)
            .padding(.horizontal, Tokens.Spacing.snug)
            .frame(maxWidth: .infinity, minHeight: Tokens.minimumTapTarget)
            .background {
              if segment.value == selection {
                RoundedRectangle(cornerRadius: Tokens.Radius.control - Tokens.Spacing.hairline)
                  .fill(Tokens.Color.accentFill)
                  .matchedGeometryEffect(id: "indicator", in: indicator)
              }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(segment.value == selection ? [.isSelected] : [])
      }
    }
    .padding(Tokens.Spacing.hairline)
    .background(
      Tokens.Color.surfaceRaised,
      in: RoundedRectangle(cornerRadius: Tokens.Radius.control)
    )
    .overlay(
      RoundedRectangle(cornerRadius: Tokens.Radius.control)
        .strokeBorder(Tokens.Color.controlBorder, lineWidth: Tokens.Stroke.hairline)
    )
  }
}

// MARK: - Ledger

/// A row of labelled figures separated by hairlines: sets, reps, volume.
///
/// A ledger rather than a grid of stat tiles, because these are three facts about one thing and
/// should read as one line.
public struct StatLedger: View {
  public struct Item: Identifiable, Hashable, Sendable {
    public let label: String
    public let value: String
    public let unit: String?
    public var id: String { label }

    public init(label: String, value: String, unit: String? = nil) {
      self.label = label
      self.value = value
      self.unit = unit
    }
  }

  private let items: [Item]

  public init(_ items: [Item]) {
    self.items = items
  }

  public var body: some View {
    HStack(spacing: 0) {
      ForEach(items) { item in
        VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
          HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.tight) {
            Text(item.value)
              .font(Tokens.Text.setEntry)
              .foregroundStyle(Tokens.Color.textPrimary)
              .lineLimit(1)
            if let unit = item.unit {
              Text(unit)
                .font(Tokens.Text.unit)
                .foregroundStyle(Tokens.Color.textSecondary)
            }
          }
          Text(item.label)
            .font(Tokens.Text.caption)
            .foregroundStyle(Tokens.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, item.id == items.first?.id ? 0 : Tokens.Spacing.regular)
        .overlay(alignment: .leading) {
          if item.id != items.first?.id {
            Rectangle()
              .fill(Tokens.Color.border)
              .frame(width: Tokens.Stroke.hairline)
          }
        }
        .accessibilityElement(children: .combine)
      }
    }
    .fixedSize(horizontal: false, vertical: true)
  }
}

// MARK: - Banner

/// A message that belongs above content: a failed write, a caveat, a record.
///
/// Each kind sits on its own tinted surface with its symbol and a title in its hue, so the kind is
/// carried by shape, word and colour together.
public struct HardsetBanner: View {
  public enum Kind: Sendable, Hashable {
    case error
    case caveat
    case record
    case info
  }

  private let kind: Kind
  private let title: String?
  private let message: String
  private let systemImage: String?

  public init(_ kind: Kind, title: String? = nil, message: String, systemImage: String? = nil) {
    self.kind = kind
    self.title = title
    self.message = message
    self.systemImage = systemImage
  }

  public var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.regular) {
      Image(systemName: systemImage ?? defaultSymbol)
        .font(Tokens.Text.headline)
        .foregroundStyle(hue)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
        if let title {
          Text(title)
            .font(Tokens.Text.headline)
            .foregroundStyle(hue)
        }
        Text(message)
          .font(Tokens.Text.provenance)
          .foregroundStyle(Tokens.Color.textPrimary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(Tokens.Spacing.regular)
    .background(tint, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
    .overlay(
      RoundedRectangle(cornerRadius: Tokens.Radius.card)
        .strokeBorder(hue.opacity(0.35), lineWidth: Tokens.Stroke.hairline)
    )
    .accessibilityElement(children: .combine)
  }

  private var hue: Color {
    switch kind {
    case .error: Tokens.Color.error
    case .caveat: Tokens.Color.warning
    case .record: Tokens.Color.pr
    case .info: Tokens.Color.accent
    }
  }

  private var tint: Color {
    switch kind {
    case .error: Tokens.Color.errorSurface
    case .caveat: Tokens.Color.warningSurface
    case .record: Tokens.Color.prSurface
    case .info: Tokens.Color.accentSurface
    }
  }

  private var defaultSymbol: String {
    switch kind {
    case .error: "exclamationmark.triangle.fill"
    case .caveat: "exclamationmark.circle"
    case .record: "trophy.fill"
    case .info: "info.circle"
    }
  }
}

// MARK: - Loading

/// What a screen shows while a read is in flight: one quiet line, not a spinner.
///
/// Reads here take milliseconds, so a spinner would mostly flash. A sentence that says what is
/// being read is honest for the rare slow case and invisible in the common one.
public struct HardsetLoadingState: View {
  private let message: String

  public init(_ message: String) {
    self.message = message
  }

  public var body: some View {
    Text(message)
      .font(Tokens.Text.label)
      .foregroundStyle(Tokens.Color.textSecondary)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Tokens.Color.background)
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
