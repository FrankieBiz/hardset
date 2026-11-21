import SwiftUI

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
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  public init(_ items: [Item]) {
    self.items = items
  }

  /// A row of columns at ordinary sizes; at accessibility sizes, one figure per line. Three columns
  /// of large text left each figure a third of the width, and the running app's accessibility
  /// audit flagged "800" as clipping.
  public var body: some View {
    if dynamicTypeSize.isAccessibilitySize {
      VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
        ForEach(items) { item in
          figure(item)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    } else {
      HStack(spacing: 0) {
        ForEach(items) { item in
          figure(item)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, item.id == items.first?.id ? 0 : Tokens.Spacing.regular)
            .overlay(alignment: .leading) {
              if item.id != items.first?.id {
                Rectangle()
                  .fill(Tokens.Color.hairline)
                  .frame(width: Tokens.Stroke.hairline)
              }
            }
        }
      }
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func figure(_ item: Item) -> some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
      HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.tight) {
        Text(item.value)
          .font(Tokens.Text.setEntry)
          .foregroundStyle(Tokens.Color.chalk)
          .lineLimit(1)
        if let unit = item.unit {
          Text(unit)
            .hardsetText(.unit)
            .foregroundStyle(Tokens.Color.chalkDim)
        }
      }
      Text(item.label)
        .hardsetText(.caption)
        .foregroundStyle(Tokens.Color.chalkDim)
    }
    .accessibilityElement(children: .combine)
  }
}

// MARK: - Banner

/// A message that belongs above content: a failed write, a caveat, a record.
///
/// Each kind sits on its own tinted surface with its symbol and a title in its hue, so the kind is
/// carried by shape, word and colour together. It draws no outline: the tint, the symbol and the
/// words are what identify it, and a stroke that carried nothing is gone.
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
  private let onDismiss: (() -> Void)?

  /// - Parameter onDismiss: Draws a close control, for a message the reader may put away once
  ///   read. `nil` leaves the banner until whatever caused it is resolved.
  public init(
    _ kind: Kind, title: String? = nil, message: String, systemImage: String? = nil,
    onDismiss: (() -> Void)? = nil
  ) {
    self.kind = kind
    self.title = title
    self.message = message
    self.systemImage = systemImage
    self.onDismiss = onDismiss
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
          .foregroundStyle(Tokens.Color.chalk)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      if let onDismiss {
        DismissGlyphButton(action: onDismiss)
          // Reached through the banner's named action instead, so the message stays one element.
          .accessibilityHidden(true)
      }
    }
    .padding(Tokens.Spacing.regular)
    .background(tint, in: Tokens.Shape.card)
    .accessibilityElement(children: .combine)
    .accessibilityActions {
      if let onDismiss {
        Button("Dismiss", action: onDismiss)
      }
    }
  }

  private var hue: Color {
    switch kind {
    case .error: Tokens.Color.plateRed
    case .caveat: Tokens.Color.warning
    case .record: Tokens.Color.plateYellow
    case .info: Tokens.Color.plateBlue
    }
  }

  private var tint: Color {
    switch kind {
    case .error: Tokens.Color.plateRedSurface
    case .caveat: Tokens.Color.warningSurface
    case .record: Tokens.Color.plateYellowSurface
    case .info: Tokens.Color.plateBlueSurface
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

/// A small close mark with a full 44 pt target, for putting away a message once it is read.
struct DismissGlyphButton: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: "xmark")
        .hardsetText(.caption, weight: .semibold)
        .foregroundStyle(Tokens.Color.chalkDim)
        .frame(width: Tokens.minimumTapTarget, height: Tokens.minimumTapTarget)
        .contentShape(Rectangle())
    }
    .buttonStyle(HardsetPressStyle())
    // Pulled into the surrounding padding, so a one-line message is not made taller by the
    // mark that closes it; the target keeps its full 44 pt.
    .padding(.vertical, -Tokens.Spacing.regular)
    .padding(.trailing, -Tokens.Spacing.snug)
    .accessibilityLabel("Dismiss")
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
      .foregroundStyle(Tokens.Color.chalkDim)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Tokens.Color.canvas)
  }
}

// MARK: - Arrival

extension View {
  /// How a message arrives: it fades in where it lands, on `Motion.reveal`, while everything it
  /// displaces moves at once, and it leaves at once. Layout never animates, and no animated
  /// transaction is involved, so what the message displaces is not dragged along with the fade.
  /// Under Reduce Motion the fade is replaced by an instant insertion.
  ///
  /// Apply it to the message view where a conditional inserts it. The pickers, the name entry
  /// sheet and the session use it; the root screens adopt it as they are rebuilt.
  public func hardsetArrival() -> some View {
    modifier(HardsetArrivalModifier())
  }
}

/// The insertion-only reveal behind `hardsetArrival()`. A `View` extension cannot read the
/// environment, so the modifier reads Reduce Motion and builds the transition from it.
struct HardsetArrivalModifier: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    content.transition(
      .asymmetric(
        insertion: .opacity.animation(
          Tokens.Motion.adaptive(Tokens.Motion.reveal, reduceMotion: reduceMotion)
        ),
        removal: .identity
      )
    )
  }
}
