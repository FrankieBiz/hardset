import Charts
import HardsetCore
import SwiftUI

/// Every movement the lifter has trained, grouped by body part, each with a trend.
///
/// A row is one movement on one machine, as it is one series everywhere else, and says what it
/// measures: "Estimated max +8% in 6 weeks", never a bare number. Where that figure is an estimate
/// its certainty sits beside it, and a movement with no session six weeks back says "Not enough
/// history" rather than borrowing another window. At the top, the three biggest estimated-max gains. A movement
/// that has not set a record in its last three sessions is flagged "Stalled" in the warning colour,
/// with no advice attached: it is a fact about the sessions, not a prescription.
///
/// The words come from `ProgressCopy` and the grouping from `ProgressBoard`, both tested without a
/// view; this draws them. The sparkline is decoration for the eye and is hidden from VoiceOver,
/// which reads the sentence instead.
///
/// When given a `title`, the view draws its own `ScreenHeader` first in its scroll content, because
/// the tab that hosts it hides the stock navigation bar.
public struct ProgressBoardView: View {
  private let board: ProgressBoard
  private let title: String?
  private let subtitle: String?
  private let onSelect: (ProgressBoard.Row) -> Void
  private let onShowSettings: (() -> Void)?

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  /// - Parameters:
  ///   - onSelect: Opens a movement's progress screen.
  ///   - onShowSettings: Draws the Settings button in the header, as the other tabs do.
  public init(
    board: ProgressBoard,
    title: String? = nil,
    subtitle: String? = nil,
    onShowSettings: (() -> Void)? = nil,
    onSelect: @escaping (ProgressBoard.Row) -> Void
  ) {
    self.board = board
    self.title = title
    self.subtitle = subtitle
    self.onShowSettings = onShowSettings
    self.onSelect = onSelect
  }

  public var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: Tokens.Spacing.snug, pinnedViews: [.sectionHeaders]) {
        if let title {
          header(title)
        }
        if board.sections.isEmpty {
          HardsetEmptyState(
            title: "No progress to show yet",
            detail: "Log a workout and your progress shows up here.",
            systemImage: "chart.line.uptrend.xyaxis"
          )
          .padding(.top, Tokens.Spacing.section)
        } else {
          if !board.mostImproved.isEmpty {
            mostImprovedStrip
          }
          ForEach(board.sections) { section in
            Section {
              ForEach(section.rows) { row in
                rowCard(row, showsSparkline: true)
                  .padding(.horizontal, Tokens.Spacing.loose)
              }
            } header: {
              sectionHeader(section)
                .padding(.horizontal, Tokens.Spacing.loose)
                .padding(.top, Tokens.Spacing.loose)
                .padding(.bottom, Tokens.Spacing.snug)
                // Opaque, because the header is pinned and rows scroll underneath it.
                .background(Tokens.Color.canvas)
            }
          }
        }
      }
      .padding(.top, title == nil ? Tokens.Spacing.snug : 0)
      .padding(.bottom, Tokens.Spacing.block)
    }
    .background(Tokens.Color.canvas)
  }

  private func header(_ title: String) -> some View {
    ScreenHeader(title, subtitle: subtitle) {
      if let onShowSettings {
        HeaderIconButton(systemImage: "gearshape", accessibilityLabel: "Settings", action: onShowSettings)
      }
    }
  }

  // MARK: - Most improved

  private var mostImprovedStrip: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      SectionLabel(ProgressCopy.mostImprovedTitle)
      ForEach(board.mostImproved) { row in
        rowCard(row, showsSparkline: false)
      }
    }
    .padding(.horizontal, Tokens.Spacing.loose)
    .padding(.top, Tokens.Spacing.regular)
  }

  // MARK: - Sections

  @ViewBuilder private func sectionHeader(_ section: ProgressBoard.Section) -> some View {
    if let category = section.category {
      SectionLabel(ExercisePickerView.categoryTitle(for: category), count: section.rows.count)
    } else {
      // Movements with no body part: said as a gap to close, in the library's own words.
      HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.snug) {
        Image(systemName: "exclamationmark.triangle")
          .accessibilityHidden(true)
        Text("Needs a body part")
        Text(section.rows.count, format: .number)
          .monospacedDigit()
        Spacer(minLength: 0)
      }
      .font(Tokens.Text.sectionHeader)
      .foregroundStyle(Tokens.Color.warning)
      .accessibilityElement(children: .combine)
      .accessibilityAddTraits(.isHeader)
    }
  }

  // MARK: - Rows

  /// The whole card opens the movement. The certainty badge is its own control, drawn over the card
  /// rather than inside its button, so a tap on it explains the estimate and a tap anywhere else
  /// opens the history. Both read separately to VoiceOver.
  private func rowCard(_ row: ProgressBoard.Row, showsSparkline: Bool) -> some View {
    Button {
      onSelect(row)
    } label: {
      rowContent(row, showsSparkline: showsSparkline)
    }
    .buttonStyle(SelectionCardButtonStyle(isSelected: false))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(ProgressCopy.spokenRow(row))
    .accessibilityHint("Opens its history")
    .overlay(alignment: .bottomTrailing) {
      badge(for: row)
    }
  }

  private func rowContent(_ row: ProgressBoard.Row, showsSparkline: Bool) -> some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      HStack(alignment: .center, spacing: Tokens.Spacing.regular) {
        VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
          Text(row.exerciseName)
            .font(Tokens.Text.headline)
            .foregroundStyle(Tokens.Color.chalk)
            .fixedSize(horizontal: false, vertical: true)
          if let machine = row.machineName {
            Text(machine)
              .font(Tokens.Text.provenance)
              .foregroundStyle(Tokens.Color.chalkDim)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if showsSparkline, !dynamicTypeSize.isAccessibilitySize {
          Sparkline(values: row.trend.sparkline)
            .frame(width: 72, height: 32)
        }
      }

      VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
        if let change = ProgressCopy.changeText(for: row.trend) {
          Text(change)
            .font(Tokens.Text.provenance)
            .foregroundStyle(Tokens.Color.chalk)
            .fixedSize(horizontal: false, vertical: true)
        } else {
          Text(ProgressCopy.notEnoughHistory)
            .font(Tokens.Text.provenance)
            .foregroundStyle(Tokens.Color.chalkDim)
        }
        if let stalled = ProgressCopy.stalledText(for: row.trend) {
          Label(stalled, systemImage: "pause.circle")
            .font(Tokens.Text.provenance)
            .foregroundStyle(Tokens.Color.warning)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      // Room for the badge drawn over the card's corner. The badge itself, hidden, is the spacer, so
      // the room is exactly its size at every Dynamic Type size and the sentence never runs under it.
      if showsBadge(row) {
        badge(for: row)
          .hidden()
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
    }
    .padding(.horizontal, Tokens.Spacing.regular)
    .padding(.vertical, Tokens.Spacing.snug)
    .frame(maxWidth: .infinity, minHeight: Tokens.loggerTapTarget, alignment: .leading)
    .contentShape(RoundedRectangle(cornerRadius: Tokens.Radius.control))
  }

  private func showsBadge(_ row: ProgressBoard.Row) -> Bool {
    row.trend.metric == .estimatedMax && row.trend.certainty != nil
  }

  /// Beside every estimated-max figure, the certainty of the estimate behind it.
  @ViewBuilder private func badge(for row: ProgressBoard.Row) -> some View {
    if row.trend.metric == .estimatedMax, let certainty = row.trend.certainty {
      CertaintyBadge(
        level: MethodologySheet.level(for: certainty),
        methodology: ProgressionAnalyzer.source.methodology,
        citation: ProgressionAnalyzer.source.validRange
      )
      .padding(.trailing, Tokens.Spacing.snug)
    }
  }
}

/// A trend line with no axes: the shape of the last dozen sessions, nothing more. The newest
/// session is marked with a point so its end is visible. Hidden from VoiceOver, which reads the
/// row's sentence.
private struct Sparkline: View {
  let values: [Double]

  var body: some View {
    Chart {
      ForEach(Array(values.enumerated()), id: \.offset) { item in
        LineMark(
          x: .value("Session", item.offset),
          y: .value("Value", item.element)
        )
        .foregroundStyle(Tokens.Color.plateBlue)
        .lineStyle(StrokeStyle(lineWidth: Tokens.Stroke.selected))
      }
      PointMark(
        x: .value("Session", max(values.count - 1, 0)),
        y: .value("Value", values.last ?? 0)
      )
      .foregroundStyle(Tokens.Color.plateBlue)
    }
    .chartXAxis(.hidden)
    .chartYAxis(.hidden)
    .chartLegend(.hidden)
    .chartYScale(domain: .automatic(includesZero: false))
    .accessibilityHidden(true)
  }
}

#if DEBUG
  #Preview("Progress board") {
    func row(
      _ name: String, machine: String?, metric: TrendMetric, change: Double?, stalled: Int? = nil,
      certainty: Certainty? = nil
    ) -> ProgressBoard.Row {
      ProgressBoard.Row(
        trend: MovementTrend(
          key: ProgressionKey(exerciseID: ExerciseID(), machineID: machine == nil ? nil : MachineID()),
          metric: metric, sparkline: [50, 52, 51, 55, 57, 60], sixWeekChange: change,
          sessionCount: 6, stalledSessions: stalled, latestDate: .now, certainty: certainty),
        exerciseName: name, machineName: machine)
    }
    let press = row("Chest press", machine: "Hammer Strength", metric: .estimatedMax, change: 0.08, certainty: .moderate)
    let squat = row("Back squat", machine: nil, metric: .heaviestLoad, change: nil, stalled: 3)
    return ProgressBoardView(
      board: ProgressBoard(
        sections: [
          ProgressBoard.Section(category: .chest, rows: [press]),
          ProgressBoard.Section(category: .quads, rows: [squat]),
        ],
        mostImproved: [press]),
      title: "Progress", onSelect: { _ in })
  }
#endif
