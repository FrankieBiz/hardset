import SwiftUI

// MARK: - Ledger

/// A row of labelled figures separated by hairlines: sets, reps, volume.
///
/// A ledger rather than a grid of stat tiles, because these are three facts about one thing and
/// should read as one line.
///
/// Every figure is a measurement the lifter typed or the app counted, so each is drawn at
/// `figureXL`, and a monument may lead the ledger with one of them, at 88 pt where the screen's
/// subject is the number and 72 pt where it is an action (`MonumentKind`). An item that is an
/// estimate is drawn at `readout`, the largest an estimate may be, whichever role it would
/// otherwise have had: the ledger is the component that holds the scale's rule, so a caller cannot
/// hand it a formula's output and get a headline back.
public struct StatLedger: View {
  public struct Item: Identifiable, Hashable, Sendable {
    public let label: String
    public let value: String
    public let unit: String?
    /// True when the figure is inferred and not counted or typed: an estimated max, a fractional
    /// muscle credit, a change in either. Such a figure is never drawn above 28 pt.
    public let isEstimate: Bool
    public var id: String { label }

    public init(label: String, value: String, unit: String? = nil, isEstimate: Bool = false) {
      self.label = label
      self.value = value
      self.unit = unit
      self.isEstimate = isEstimate
    }
  }

  /// How a monument stands against the screen it is on. The monument is 88 pt where the screen's
  /// subject is the number, and 72 pt where the screen's subject is the action. A number that
  /// outranks the primary action makes the screen harder to use.
  public enum MonumentKind: Sendable, Hashable {
    /// The number is the content: Volume's weekly working sets. 88 pt.
    case subject
    /// The screen is for an action and the number sits beside it: Train's last-workout volume, under
    /// the controls that start a workout. 72 pt.
    case aside

    var role: Tokens.Text.Role {
      switch self {
      case .subject: .monument
      case .aside: .monumentAside
      }
    }
  }

  private let items: [Item]
  private let monument: Item?
  private let monumentKind: MonumentKind
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  /// - Parameter monument: A measured figure to lead the ledger, above the columns. It is the one
  ///   monument its screen has, and it is left to the caller to have no more than one. An estimate
  ///   passed here is drawn at `readout` like any other estimate.
  /// - Parameter monumentKind: Whether the screen's subject is the number or an action.
  public init(_ items: [Item], monument: Item? = nil, monumentKind: MonumentKind = .subject) {
    self.items = items
    self.monument = monument
    self.monumentKind = monumentKind
  }

  /// The role a figure is drawn in: a monument of the given kind, or `figureXL` when `monument` is
  /// nil. An estimate is capped at `readout` whatever was asked for.
  public static func figureRole(for item: Item, monument: MonumentKind?) -> Tokens.Text.Role {
    if item.isEstimate { return .readout }
    return monument?.role ?? .figureXL
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.loose) {
      if let monument {
        figure(monument, kind: monumentKind)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      if !items.isEmpty {
        columns
      }
    }
  }

  /// A row of columns at ordinary sizes; at accessibility sizes, one figure per line. Three columns
  /// of large text left each figure a third of the width, and the running app's accessibility
  /// audit flagged "800" as clipping.
  ///
  /// At 44 pt the columns are the width of their figures and no wider, so a five-digit volume gets
  /// the room it needs and a short count does not hold space it does not use. Three figures take one
  /// line if they fit. Four, which is the ledger once warm-ups are logged, do not fit beside a
  /// four-digit volume on any phone, so they are always two to a line in columns that line up, and
  /// the layout does not change when the volume crosses 1,000. Three too wide for the line, as at a
  /// six-digit volume on a narrow phone, fall to the same two columns, and none is clipped.
  @ViewBuilder private var columns: some View {
    if dynamicTypeSize.isAccessibilitySize {
      VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
        ForEach(items) { item in
          figure(item, kind: nil)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    } else if items.count > 3 {
      pairedColumns
    } else {
      ViewThatFits(in: .horizontal) {
        ruledRow
        pairedColumns
      }
    }
  }

  /// Two figures to a line, each column as wide as its widest figure so the lines under one another
  /// align. No dividers: the alignment is what groups them.
  private var pairedColumns: some View {
    Grid(
      alignment: .topLeading, horizontalSpacing: Tokens.Spacing.section,
      verticalSpacing: Tokens.Spacing.loose
    ) {
      ForEach(Array(stride(from: 0, to: items.count, by: 2)), id: \.self) { start in
        GridRow {
          figure(items[start], kind: nil)
          if start + 1 < items.count {
            figure(items[start + 1], kind: nil)
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var ruledRow: some View {
    HStack(alignment: .top, spacing: 0) {
      ForEach(items) { item in
        let isFirst = item.id == items.first?.id
        let isLast = item.id == items.last?.id
        figure(item, kind: nil)
          .padding(.leading, isFirst ? 0 : Tokens.Spacing.regular)
          .padding(.trailing, isLast ? 0 : Tokens.Spacing.regular)
          .overlay(alignment: .leading) {
            if !isFirst {
              Rectangle()
                .fill(Tokens.Color.hairline)
                .frame(width: Tokens.Stroke.hairline)
            }
          }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .fixedSize(horizontal: false, vertical: true)
  }

  private func figure(_ item: Item, kind: MonumentKind?) -> some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
      HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.tight) {
        Text(item.value)
          .hardsetText(Self.figureRole(for: item, monument: kind))
          .foregroundStyle(Tokens.Color.chalk)
          .lineLimit(1)
          // A figure must show the whole number. This floor is only for a value wider than the
          // line at its full size, as the keypad's display allows; it does not take part in
          // ordinary layout, which wraps or stacks instead.
          .minimumScaleFactor(0.5)
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
