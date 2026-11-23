import Charts
import HardsetCore
import SwiftUI

/// Every movement the lifter has trained, grouped by body part, each with a trend.
///
/// A row is one movement on one machine, as it is one series everywhere else, and says what it
/// measures: "Estimated max +8% in 6 weeks", never a bare number. Where that figure is an estimate
/// its certainty sits beside it, and a movement with no session five to seven weeks before its
/// latest says it has no 6-week comparison and how much history it does have, rather than borrowing
/// another window. At the top, the three best-supported estimated-max gains, in an order the strip
/// states. A movement that has not set a record in its last three sessions says "No record in 3
/// sessions" in the warning colour, with no advice attached: it is a fact about the sessions, not a
/// verdict on the lifter and not a prescription.
///
/// Imported history is never merged into what the lifter logged here, so a lift can have two rows.
/// Each imported row says it is not combined with the sets logged in Hardset, a movement with both
/// halves says so on both rows, and the board says once, above its rows, why a lift can appear
/// twice. No two names are guessed to be one movement.
///
/// The words come from `ProgressCopy` and the grouping from `ProgressBoard`, both tested without a
/// view; this draws them. The sparkline is decoration for the eye and is hidden from VoiceOver,
/// which reads the sentence instead.
///
/// Nothing is boxed and nothing but a caveat is coloured. A row is type on the canvas under a
/// hairline: the movement, its machine, the sentence with its figure set in the tabular face, and
/// the certainty as a phrase beneath it. The sparkline is `chalkDim` with the newest session in
/// `chalk`, because this screen has no primary action to own an accent, and a warning glyph is the
/// only hue on it.
///
/// When given a `title`, the view draws its own `ScreenHeader` first in its scroll content, because
/// the tab that hosts it hides the stock navigation bar.
public struct ProgressBoardView: View {
  private let board: ProgressBoard
  private let title: String?
  private let subtitle: String?
  private let onSelect: (ProgressBoard.Row) -> Void
  private let onShowSettings: (() -> Void)?
  /// Read once from the board, not per row: how an imported row and the logged row beside it relate.
  private let sourceNotes: [ProgressionKey: String]

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
    self.sourceNotes = board.sourceNotes
    self.title = title
    self.subtitle = subtitle
    self.onShowSettings = onShowSettings
    self.onSelect = onSelect
  }

  public var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
        if let title {
          header(title)
        }
        if board.sections.isEmpty {
          HardsetEmptyState(
            title: "No progress to show yet",
            detail: "Log a workout and your progress shows up here.",
            systemImage: "chart.line.uptrend.xyaxis",
            style: .quiet
          )
          .padding(.top, Tokens.Spacing.section)
        } else {
          if board.hasImportedHistory {
            Text(ProgressCopy.importedBoardNote)
              .font(Tokens.Text.caption)
              .foregroundStyle(Tokens.Color.chalkDim)
              .fixedSize(horizontal: false, vertical: true)
              .padding(.horizontal, Tokens.Spacing.loose)
              .padding(.top, Tokens.Spacing.regular)
          }
          if !board.mostImproved.isEmpty {
            mostImprovedStrip(board.mostImproved, metric: .estimatedMax)
          }
          if !board.mostImprovedAddedLoad.isEmpty {
            mostImprovedStrip(board.mostImprovedAddedLoad, metric: .addedLoad)
          }
          ForEach(board.sections) { section in
            Section {
              ForEach(section.rows) { entry in
                rowView(entry, showsSparkline: true)
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
        HeaderIconButton(
          systemImage: "gearshape", accessibilityLabel: "Settings", style: .bare,
          action: onShowSettings)
      }
    }
  }

  // MARK: - Most improved

  private func mostImprovedStrip(_ rows: [ProgressBoard.Row], metric: TrendMetric) -> some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      SectionLabel("Most improved · " + ProgressCopy.metricName(metric).lowercased())
      // The order is not by percentage alone, so the strip says what it is.
      Text(ProgressCopy.mostImprovedOrdering)
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.chalkDim)
        .fixedSize(horizontal: false, vertical: true)
      // Each row carries its own hairline, so they sit flush: spacing would put a gap between a row's
      // text and the rule that belongs to the next.
      VStack(alignment: .leading, spacing: 0) {
        ForEach(rows) { entry in
          rowView(entry, showsSparkline: false)
        }
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
      // Movements with no body part: said as a gap to close, in the library's own words. The
      // warning glyph is the mark; the words are `chalk`, as the stale-workout notice's are.
      HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.snug) {
        Image(systemName: "exclamationmark.triangle")
          .foregroundStyle(Tokens.Color.warning)
          .accessibilityHidden(true)
        Text("Needs a body part")
          .foregroundStyle(Tokens.Color.chalk)
        Text(section.rows.count, format: .number)
          .monospacedDigit()
          .foregroundStyle(Tokens.Color.chalkDim)
        Spacer(minLength: 0)
      }
      .font(Tokens.Text.sectionHeader)
      .accessibilityElement(children: .combine)
      .accessibilityAddTraits(.isHeader)
    }
  }

  // MARK: - Rows

  /// A row is the movement's button, then its certainty, under a hairline. The button opens the
  /// history; the certainty is its own control beneath it rather than inside it, so a tap on it
  /// explains the estimate and a tap anywhere else opens the history. Both read separately to
  /// VoiceOver.
  private func rowView(_ row: ProgressBoard.Row, showsSparkline: Bool) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Rectangle()
        .fill(Tokens.Color.hairline)
        .frame(height: Tokens.Stroke.hairline)
        .accessibilityHidden(true)
      Button {
        onSelect(row)
      } label: {
        rowContent(row, showsSparkline: showsSparkline)
      }
      .buttonStyle(
        InlineControlStyle(
          minHeight: Tokens.loggerTapTarget, alignment: .leading, fullWidth: true)
      )
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(ProgressCopy.spokenRow(row, sourceNote: sourceNotes[row.id]))
      .accessibilityHint("Opens its history")
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
          Text(Self.sentence(change, figure: row.trend.sixWeekChange.map(ProgressCopy.signedPercent)))
            .fixedSize(horizontal: false, vertical: true)
        } else {
          // What is missing, not a verdict on the history: a movement trained every four weeks, or
          // with a gap, has plenty of history and no session in the comparison band. The span the
          // movement does have is said on the line below.
          Text(ProgressCopy.noChangeText(for: row.trend))
            .font(Tokens.Text.provenance)
            .foregroundStyle(Tokens.Color.chalkDim)
            .fixedSize(horizontal: false, vertical: true)
          Text(ProgressCopy.historyText(for: row.trend))
            .font(Tokens.Text.provenance)
            .foregroundStyle(Tokens.Color.chalkDim)
            .fixedSize(horizontal: false, vertical: true)
        }
        if let assumption = row.trend.loadAssumption {
          Text(assumption)
            .font(Tokens.Text.provenance)
            .foregroundStyle(Tokens.Color.chalkDim)
            .fixedSize(horizontal: false, vertical: true)
        }
        if let note = ProgressCopy.equipmentNote(for: row.trend) {
          Text(note)
            .font(Tokens.Text.provenance)
            .foregroundStyle(Tokens.Color.chalkDim)
            .fixedSize(horizontal: false, vertical: true)
        }
        if let stalled = ProgressCopy.stalledText(for: row.trend) {
          // The glyph is the caveat's one mark; the words are plain `chalk`.
          HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.snug) {
            Image(systemName: "pause.circle")
              .foregroundStyle(Tokens.Color.warning)
              .accessibilityHidden(true)
            Text(stalled)
              .foregroundStyle(Tokens.Color.chalk)
          }
          .font(Tokens.Text.provenance)
          .accessibilityElement(children: .combine)
        }
        if let note = sourceNotes[row.id] {
          Text(note)
            .font(Tokens.Text.provenance)
            .foregroundStyle(Tokens.Color.chalkDim)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.top, Tokens.Spacing.snug)
    // A row with a certainty phrase gives its bottom space to the phrase's own 44 pt region, so
    // the phrase sits under the sentence it qualifies instead of floating a line below it.
    .padding(.bottom, row.trend.certainty == nil ? Tokens.Spacing.snug : 0)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// "Estimated max +8% in 6 weeks" with the figure, and only the figure, in the tabular face and
  /// `chalk`, so the number is the largest thing in the sentence and the words around it stay
  /// quiet. The sentence is `ProgressCopy`'s, untouched: the figure is found in it, never composed
  /// beside it, so a change to the words cannot leave this behind. When it is not found, as with
  /// "unchanged in 6 weeks", the whole sentence is drawn plainly.
  static func sentence(_ text: String, figure: String?) -> AttributedString {
    var attributed = AttributedString(text)
    attributed.font = Tokens.Text.provenance
    attributed.foregroundColor = Tokens.Color.chalkDim
    if let figure, let range = attributed.range(of: figure) {
      attributed[range].font = Tokens.Text.figure
      attributed[range].foregroundColor = Tokens.Color.chalk
    }
    return attributed
  }

  /// Beside every estimated-max figure, the certainty of the estimate behind it, as a phrase.
  @ViewBuilder private func badge(for row: ProgressBoard.Row) -> some View {
    if let certainty = row.trend.certainty {
      CertaintyBadge(
        level: MethodologySheet.level(for: certainty),
        methodology: row.trend.loadAssumption ?? ProgressionAnalyzer.source.methodology,
        citation: row.trend.loadAssumption == nil ? ProgressionAnalyzer.source.validRange : nil,
        style: .language
      )
    }
  }
}

/// A trend line with no axes: the shape of the last dozen sessions, nothing more, in `chalkDim`.
/// The newest session is marked with a `chalk` point so its end is visible. Hidden from VoiceOver, which reads the
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
        .foregroundStyle(Tokens.Color.chalkDim)
        .lineStyle(StrokeStyle(lineWidth: Tokens.Stroke.selected))
      }
      PointMark(
        x: .value("Session", max(values.count - 1, 0)),
        y: .value("Value", values.last ?? 0)
      )
      .foregroundStyle(Tokens.Color.chalk)
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
