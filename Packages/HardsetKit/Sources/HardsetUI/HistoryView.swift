import HardsetCore
import SwiftUI

/// A row's worth of a past session, with no dependency on storage.
public struct HistoryRow: Hashable, Sendable, Identifiable {
  public let id: SessionID
  public let title: String
  public let date: Date
  public let duration: Duration?
  public let exerciseNames: [String]
  public let volume: SessionVolume
  /// A recorded span longer than any real workout. Rendered as a caveat rather than a boast.
  public let hasImplausibleDuration: Bool

  public init(
    id: SessionID,
    title: String,
    date: Date,
    duration: Duration?,
    exerciseNames: [String],
    volume: SessionVolume,
    hasImplausibleDuration: Bool
  ) {
    self.id = id
    self.title = title
    self.date = date
    self.duration = duration
    self.exerciseNames = exerciseNames
    self.volume = volume
    self.hasImplausibleDuration = hasImplausibleDuration
  }
}

/// Past workouts, newest first.
///
/// The one thing this screen must not do is present a broken record as an achievement. The
/// ancestor app shipped 9,749-minute workouts here — a session left running overnight, its
/// duration recomputed against the wall clock — and rendered them as personal bests. A session
/// whose recorded span is longer than any real workout is shown with the span replaced by a
/// caveat, because the honest thing to say is "we do not know how long this took", not "20 hours".
///
/// Sessions are grouped by month under pinned, sentence-case headers, so a long history stays
/// navigable without a search field. Each row is a card led by a date block, the way a training
/// log is read: which day, what was done, how much of it.
///
/// When given a `title`, the view draws its own `ScreenHeader` as the first thing in its scroll
/// content, because the tab that hosts it hides the stock navigation bar. With no `subtitle`, the
/// header says how many workouts are shown.
///
/// The list is a page of the newest workouts. When older ones exist, `onShowOlder` draws a quiet
/// control after the last month that asks for more, so a long or imported history is reachable
/// rather than silently cut off. `onDelete` offers deleting a workout from a card's context menu;
/// the caller confirms it.
public struct HistoryView: View {
  private let rows: [HistoryRow]
  private let unit: WeightUnit
  private let title: String?
  private let subtitle: String?
  private let onSelect: ((HistoryRow) -> Void)?
  private let onShowOlder: (() -> Void)?
  private let isLoadingOlder: Bool
  private let onDelete: ((HistoryRow) -> Void)?
  private let onShowSettings: (() -> Void)?

  public init(
    rows: [HistoryRow],
    unit: WeightUnit,
    title: String? = nil,
    subtitle: String? = nil,
    onSelect: ((HistoryRow) -> Void)? = nil,
    onShowOlder: (() -> Void)? = nil,
    isLoadingOlder: Bool = false,
    onDelete: ((HistoryRow) -> Void)? = nil,
    onShowSettings: (() -> Void)? = nil
  ) {
    self.rows = rows
    self.unit = unit
    self.title = title
    self.subtitle = subtitle
    self.onSelect = onSelect
    self.onShowOlder = onShowOlder
    self.isLoadingOlder = isLoadingOlder
    self.onDelete = onDelete
    self.onShowSettings = onShowSettings
  }

  public var body: some View {
    if rows.isEmpty {
      ScrollView {
        VStack(alignment: .leading, spacing: Tokens.Spacing.section) {
          if let title {
            header(title, subtitle: subtitle)
          }
          HardsetEmptyState(
            title: "No workouts yet",
            detail: "Finished workouts appear here.",
            systemImage: "clock.arrow.circlepath"
          )
        }
        .padding(.top, title == nil ? Tokens.Spacing.section : 0)
        .padding(.bottom, Tokens.Spacing.block)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .background(Tokens.Color.background)
    } else {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: Tokens.Spacing.snug, pinnedViews: [.sectionHeaders]) {
          if let title {
            header(title, subtitle: subtitle ?? Self.countText(rows.count))
          }
          ForEach(Self.monthGroups(rows)) { group in
            Section {
              ForEach(group.rows) { row in
                card(for: row)
                  .padding(.horizontal, Tokens.Spacing.loose)
              }
            } header: {
              // Opaque, so rows scrolling under a pinned header never show through it.
              SectionLabel(group.title, count: group.rows.count)
                .padding(.horizontal, Tokens.Spacing.loose)
                .padding(.top, Tokens.Spacing.loose)
                .padding(.bottom, Tokens.Spacing.snug)
                .background(Tokens.Color.background)
            }
          }
          if let onShowOlder {
            Button(action: onShowOlder) {
              Label(
                isLoadingOlder ? "Reading older workouts…" : "Show older workouts",
                systemImage: "clock.arrow.circlepath"
              )
            }
            .buttonStyle(HardsetButtonStyle(.quiet))
            .disabled(isLoadingOlder)
            .padding(.horizontal, Tokens.Spacing.loose)
            .padding(.top, Tokens.Spacing.regular)
          }
        }
        .padding(.top, title == nil ? Tokens.Spacing.snug : 0)
        .padding(.bottom, Tokens.Spacing.block)
      }
      .background(Tokens.Color.background)
    }
  }

  /// The screen's header, with the Settings action when one is given, as on the Train tab.
  private func header(_ title: String, subtitle: String?) -> some View {
    ScreenHeader(title, subtitle: subtitle) {
      if let onShowSettings {
        HeaderIconButton(systemImage: "gearshape", accessibilityLabel: "Settings", action: onShowSettings)
      }
    }
  }

  /// A selectable row is a button with a pressed state and a disclosure chevron. Without a
  /// destination it is a plain card: it must not look, or behave, as if it might go somewhere.
  @ViewBuilder private func card(for row: HistoryRow) -> some View {
    if let onSelect {
      Button {
        onSelect(row)
      } label: {
        HistoryRowContent(row: row, unit: unit, showsDisclosure: true)
      }
      .buttonStyle(HistoryRowButtonStyle())
      .accessibilityLabel(Self.spokenLabel(row, unit: unit))
      .modifier(DeleteWorkoutAction(row: row, onDelete: onDelete))
    } else {
      HistoryRowContent(row: row, unit: unit, showsDisclosure: false)
        .hardsetCard(cornerRadius: Tokens.Radius.control)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.spokenLabel(row, unit: unit))
        .modifier(DeleteWorkoutAction(row: row, onDelete: onDelete))
    }
  }

  // MARK: - Grouping

  /// One calendar month of sessions, in the order the rows arrived. `nonisolated` for the same
  /// reason as `HardsetSegment`: its `id` is computed.
  nonisolated struct MonthGroup: Identifiable {
    let start: Date
    var rows: [HistoryRow]
    var id: Date { start }

    var title: String {
      start.formatted(.dateTime.month(.wide).year())
    }
  }

  /// Groups rows by the month they started in, keeping the caller's order within and between
  /// months. Keyed on the month rather than on adjacency, so rows that arrive slightly out of order
  /// cannot produce two sections for the same month.
  static func monthGroups(_ rows: [HistoryRow], calendar: Calendar = .current) -> [MonthGroup] {
    var order: [Date] = []
    var buckets: [Date: [HistoryRow]] = [:]
    for row in rows {
      let start = calendar.dateInterval(of: .month, for: row.date)?.start ?? row.date
      if buckets[start] == nil { order.append(start) }
      buckets[start, default: []].append(row)
    }
    return order.map { MonthGroup(start: $0, rows: buckets[$0] ?? []) }
  }

  static func countText(_ count: Int) -> String {
    count == 1 ? "1 workout" : "\(count) workouts, newest first"
  }

  // MARK: - Text

  /// The row's date as spoken. The year is added whenever it is not this year, because the month
  /// header that carries it is not read with the row, and imported history repeats every date.
  static func dateText(_ date: Date, now: Date = .now) -> String {
    let style: Date.FormatStyle = .dateTime.weekday(.abbreviated).day().month(.abbreviated)
    return date.formatted(isThisYear(date, now: now) ? style : style.year())
  }

  /// "Tuesday 12 March", or "Tuesday 12 March 2024" when not this year, for a confirmation that
  /// names the workout it acts on.
  public static func fullDateText(_ date: Date, now: Date = .now) -> String {
    let style: Date.FormatStyle = .dateTime.weekday(.wide).day().month(.wide)
    return date.formatted(isThisYear(date, now: now) ? style : style.year())
  }

  private static func isThisYear(_ date: Date, now: Date) -> Bool {
    Calendar.current.isDate(date, equalTo: now, toGranularity: .year)
  }

  static func volumeText(_ volume: SessionVolume, unit: WeightUnit) -> String {
    guard !volume.isEmpty else { return "No sets" }
    var parts = [
      volume.workingSets == 1 ? "1 set" : "\(volume.workingSets) sets",
      volume.reps == 1 ? "1 rep" : "\(volume.reps) reps",
    ]
    if volume.volumeKg > 0 {
      // Named as volume, so weight times reps is never read as the load on the bar.
      let displayed = unit.fromKilograms(volume.volumeKg)
      parts.append("\(Int(displayed.rounded())) \(unit.abbreviation) volume")
    }
    if volume.warmupSets > 0 { parts.append("\(volume.warmupSets) warm-up") }
    return parts.joined(separator: " · ")
  }

  static func spokenLabel(_ row: HistoryRow, unit: WeightUnit) -> String {
    var parts = [row.title.isEmpty ? dateText(row.date) : "\(row.title), \(dateText(row.date))"]
    parts.append(volumeText(row.volume, unit: unit))
    if row.hasImplausibleDuration {
      parts.append("length unknown, this session was left open")
    } else if let duration = row.duration {
      parts.append(duration.clockString)
    }
    return parts.joined(separator: ", ")
  }
}

// MARK: - Row

/// The inside of a history card: a date block, then what was done and how much of it, with the
/// session's length on the trailing edge.
///
/// At accessibility text sizes the date block moves above the details instead of squeezing them
/// into a narrow column, and the length drops onto its own line.
private struct HistoryRowContent: View {
  let row: HistoryRow
  let unit: WeightUnit
  let showsDisclosure: Bool
  @Environment(\.dynamicTypeSize) var dynamicTypeSize
  /// Wide enough for a two-digit day and a three-letter weekday, and grows with the text.
  @ScaledMetric(relativeTo: .title2) var dateColumnWidth: CGFloat = 44

  var body: some View {
    let isLarge = dynamicTypeSize.isAccessibilitySize
    let layout =
      isLarge
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tokens.Spacing.snug))
      : AnyLayout(HStackLayout(alignment: .top, spacing: Tokens.Spacing.regular))

    HStack(alignment: .center, spacing: Tokens.Spacing.regular) {
      layout {
        dateBlock(isLarge: isLarge)
        details(isLarge: isLarge)
      }
      if showsDisclosure {
        Image(systemName: "chevron.right")
          .font(Tokens.Text.caption.weight(.semibold))
          .foregroundStyle(Tokens.Color.textSecondary)
          .accessibilityHidden(true)
      }
    }
    .padding(Tokens.Spacing.regular)
    .frame(maxWidth: .infinity, minHeight: Tokens.minimumTapTarget, alignment: .leading)
  }

  /// Day of the month in condensed figures over the abbreviated weekday, like a dated log page.
  /// The month itself is the section header above.
  @ViewBuilder private func dateBlock(isLarge: Bool) -> some View {
    if isLarge {
      HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.snug) {
        dayFigure
        weekday
      }
    } else {
      VStack(spacing: 0) {
        dayFigure
        weekday
      }
      .frame(minWidth: dateColumnWidth)
    }
  }

  private var dayFigure: some View {
    Text(row.date, format: .dateTime.day(.twoDigits))
      .font(Tokens.Text.setEntry)
      .foregroundStyle(Tokens.Color.textPrimary)
  }

  private var weekday: some View {
    Text(row.date, format: .dateTime.weekday(.abbreviated))
      .font(Tokens.Text.caption)
      .foregroundStyle(Tokens.Color.textSecondary)
  }

  private func details(isLarge: Bool) -> some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      if isLarge {
        titleText
        durationLabel
      } else {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.snug) {
          titleText
          Spacer(minLength: Tokens.Spacing.snug)
          durationLabel
        }
      }

      figures

      if !row.exerciseNames.isEmpty {
        Text(row.exerciseNames.joined(separator: " · "))
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.textSecondary)
          .lineLimit(2)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// An untitled session reads "Workout": the date block beside it already says which day, and
  /// repeating the date as the title said it twice.
  private var titleText: some View {
    Text(row.title.isEmpty ? "Workout" : row.title)
      .font(Tokens.Text.headline)
      .foregroundStyle(Tokens.Color.textPrimary)
      .lineLimit(2)
  }

  /// Sets, reps and volume in the user's unit, as condensed figures with their units beside them.
  /// Wraps rather than shrinks when the text is large.
  @ViewBuilder private var figures: some View {
    let volume = row.volume
    if volume.isEmpty {
      Text("No sets logged")
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.textSecondary)
    } else {
      FlowLayout(spacing: Tokens.Spacing.regular) {
        figure(volume.workingSets.formatted(), volume.workingSets == 1 ? "set" : "sets")
        figure(volume.reps.formatted(), volume.reps == 1 ? "rep" : "reps")
        // Labelled "volume": "1 set 8 reps 800 lb" read as an 800 lb set.
        if volume.volumeKg > 0 {
          figure(
            Int(unit.fromKilograms(volume.volumeKg).rounded()).formatted(),
            "\(unit.abbreviation) volume"
          )
        }
        if volume.warmupSets > 0 {
          figure(volume.warmupSets.formatted(), "warm-up")
        }
      }
    }
  }

  private func figure(_ value: String, _ label: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.tight) {
      Text(value)
        .font(Tokens.Text.figure)
        .monospacedDigit()
        .foregroundStyle(Tokens.Color.textPrimary)
      Text(label)
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.textSecondary)
    }
  }

  @ViewBuilder private var durationLabel: some View {
    if row.hasImplausibleDuration {
      // The honest statement. A 20-hour span means the session was left open, not that it was
      // trained through, so the number is withheld rather than displayed.
      Label("Length unknown", systemImage: "exclamationmark.circle")
        .font(Tokens.Text.caption.weight(.semibold))
        .foregroundStyle(Tokens.Color.warning)
        .padding(.horizontal, Tokens.Spacing.snug)
        .padding(.vertical, Tokens.Spacing.hairline)
        .background(
          Tokens.Color.warningSurface,
          in: RoundedRectangle(cornerRadius: Tokens.Radius.control / 2)
        )
    } else if let duration = row.duration {
      Text(duration.clockString)
        .font(Tokens.Text.figure)
        .foregroundStyle(Tokens.Color.textSecondary)
    }
  }
}

/// Offers deleting a workout from its card: a context-menu item and a named accessibility action.
/// The caller confirms before anything is removed.
private struct DeleteWorkoutAction: ViewModifier {
  let row: HistoryRow
  let onDelete: ((HistoryRow) -> Void)?

  @ViewBuilder func body(content: Content) -> some View {
    if let onDelete {
      content
        .contextMenu {
          Button(role: .destructive) {
            onDelete(row)
          } label: {
            Label("Delete workout…", systemImage: "trash")
          }
        }
        .accessibilityAction(named: "Delete workout") { onDelete(row) }
    } else {
      content
    }
  }
}

/// A selectable history card: the card's own fill, with the pressed fill faded in over it and the
/// card pressed in slightly while the finger is down. Scale is dropped with Reduce Motion and the
/// fill changes instantly.
///
/// The pressed fill is a layer whose opacity changes, rather than a colour that changes, so the
/// only properties that animate are opacity and scale.
private struct HistoryRowButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    HistoryRowButtonBody(configuration: configuration)
  }
}

private struct HistoryRowButtonBody: View {
  let configuration: ButtonStyleConfiguration
  @Environment(\.accessibilityReduceMotion) var reduceMotion

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: Tokens.Radius.control)
    configuration.label
      .background {
        ZStack {
          shape.fill(Tokens.Color.surface)
          shape.fill(Tokens.Color.surfacePressed)
            .opacity(configuration.isPressed ? 1 : 0)
        }
      }
      .overlay(shape.strokeBorder(Tokens.Color.border, lineWidth: Tokens.Stroke.hairline))
      .contentShape(shape)
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
      .animation(
        Tokens.Motion.adaptive(Tokens.Motion.press, reduceMotion: reduceMotion),
        value: configuration.isPressed
      )
  }
}

#if DEBUG
  private struct HistoryPreviewHarness: View {
    let selectable: Bool
    let day = Date(timeIntervalSince1970: 15_000_000)

    var body: some View {
      HistoryView(
        rows: [
          HistoryRow(
            id: SessionID(), title: "Push", date: day,
            duration: .seconds(4_320),
            exerciseNames: ["Bench Press", "Overhead Press", "Cable Triceps Pushdown"],
            volume: SessionVolume(workingSets: 12, warmupSets: 2, volumeKg: 9_400, reps: 96),
            hasImplausibleDuration: false
          ),
          // Left running overnight: the span is withheld rather than shown as a 20-hour workout.
          HistoryRow(
            id: SessionID(), title: "Legs", date: day.addingTimeInterval(-172_800),
            duration: .seconds(72_000),
            exerciseNames: ["Barbell Back Squat", "Romanian Deadlift"],
            volume: SessionVolume(workingSets: 8, warmupSets: 3, volumeKg: 11_200, reps: 64),
            hasImplausibleDuration: true
          ),
          // Untitled, and a month earlier, so it falls under its own header.
          HistoryRow(
            id: SessionID(), title: "", date: day.addingTimeInterval(-2_678_400),
            duration: .seconds(2_700),
            exerciseNames: ["Lat Pulldown"],
            volume: SessionVolume(workingSets: 4, warmupSets: 0, volumeKg: 2_100, reps: 40),
            hasImplausibleDuration: false
          ),
        ],
        unit: .kilograms,
        title: "History",
        onSelect: selectable ? { _ in } : nil
      )
    }
  }

  #Preview("History") {
    HistoryPreviewHarness(selectable: false)
  }

  #Preview("History, selectable") {
    HistoryPreviewHarness(selectable: true)
  }

  #Preview("No workouts") {
    HistoryView(rows: [], unit: .pounds, title: "History")
  }
#endif
