import Charts
import HardsetCore
import SwiftUI

/// Bodyweight, presented as a trend rather than as whatever the scale said this morning.
///
/// The hero figure is the seven-day average, and the number under it is a fitted weekly rate that
/// simply does not appear until the readings can support one. Both decisions live in
/// `BodyweightTrend`; this view renders the result and never computes a change of its own.
///
/// The raw readings are still drawn, faintly, under the averaged line. Showing only the smooth line
/// would overstate how orderly the data is, which is the opposite of the point.
public struct BodyweightView: View {
  private let records: [BodyweightRow]
  private let smoothedKg: Double?
  private let weeklyRate: Claim<Double>
  private let unit: WeightUnit
  private let onAdd: () -> Void
  private let onDelete: ((UUID) -> Void)?

  @State private var isShowingMethodology = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// One reading, as this screen needs it.
  ///
  /// Declared here rather than reusing the store's row type, for the same reason `HistoryRow` and
  /// `LoggedSetRow` are: `HardsetUI` depends on `HardsetCore` only, never on `HardsetStore`.
  public struct BodyweightRow: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let weightKg: Double
    public let measuredAt: Date

    public init(id: UUID, weightKg: Double, measuredAt: Date) {
      self.id = id
      self.weightKg = weightKg
      self.measuredAt = measuredAt
    }

    var reading: BodyweightReading {
      BodyweightReading(weightKg: weightKg, measuredAt: measuredAt)
    }
  }

  public init(
    records: [BodyweightRow],
    smoothedKg: Double?,
    weeklyRate: Claim<Double>,
    unit: WeightUnit,
    onAdd: @escaping () -> Void,
    onDelete: ((UUID) -> Void)? = nil
  ) {
    self.records = records
    self.smoothedKg = smoothedKg
    self.weeklyRate = weeklyRate
    self.unit = unit
    self.onAdd = onAdd
    self.onDelete = onDelete
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Tokens.Spacing.section) {
        if records.isEmpty {
          empty
          // Only in the empty state. Once there are readings the action lives in the toolbar, where
          // it does not need scrolling past a year of rows to reach -- adding today's weight is the
          // reason this screen gets opened.
          addButton
        } else {
          hero
          if plotted.count >= 2 { chart }
          list
        }
      }
      .padding(.horizontal, Tokens.Spacing.edge)
      .padding(.vertical, Tokens.Spacing.loose)
    }
    .background(Tokens.Color.ground)
    .toolbar {
      if !records.isEmpty {
        // `.primaryAction` rather than `.topBarTrailing`: the latter does not exist on macOS, and
        // this module builds for the host so the suite can run there.
        ToolbarItem(placement: .primaryAction) {
          Button(action: onAdd) {
            Label("Add a reading", systemImage: "plus")
          }
        }
      }
    }
    .sheet(isPresented: $isShowingMethodology) {
      MethodologySheet(source: BodyweightTrend.source, certainty: weeklyRate.certainty)
    }
  }

  // MARK: - Hero

  @ViewBuilder private var hero: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
      HStack(spacing: Tokens.Spacing.tight) {
        Text("\(BodyweightTrend.smoothingDays)-day average")
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.textSecondary)
        // The disclosure guideline 1.4.1 asks for, on the same screen as the number.
        Button {
          isShowingMethodology = true
        } label: {
          Image(systemName: "info.circle")
            .font(Tokens.Text.caption)
            .foregroundStyle(Tokens.Color.textSecondary)
            // A caption-sized glyph is about 13 pt. This is the only route to the 1.4.1 disclosure
            // for the figure above it, so it gets a real target.
            .frame(minWidth: Tokens.minimumTapTarget, minHeight: Tokens.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("How this figure is calculated")
      }

      if let smoothedKg {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.snug) {
          Text(Self.format(unit.fromKilograms(smoothedKg), places: 1))
            .font(Tokens.Text.hero)
            .tracking(Tokens.Tracking.hero)
            .monospacedDigit()
            .contentTransition(reduceMotion ? .identity : .numericText(value: smoothedKg))
            .foregroundStyle(Tokens.Color.textPrimary)
          Text(unit.abbreviation)
            .font(Tokens.Text.label)
            .foregroundStyle(Tokens.Color.textSecondary)
        }
      } else {
        // Readings exist, but none inside the window. A stale figure presented as current would be
        // worse than saying so.
        Text("No readings in the last \(BodyweightTrend.smoothingDays) days")
          .font(Tokens.Text.readout)
          .foregroundStyle(Tokens.Color.textSecondary)
      }

      rateLine
      if let latest = records.first { latestLine(latest) }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder private var rateLine: some View {
    if let perWeek = weeklyRate.value {
      let direction = BodyweightTrend.direction(perWeek: perWeek)
      HStack(spacing: Tokens.Spacing.tight) {
        Image(systemName: Self.symbol(for: direction))
        Text(rateText(perWeek, direction: direction))
        if weeklyRate.certainty < .high {
          // Hedged in words as well as colour, because colour alone is not an encoding.
          Text("\u{00B7} \(MethodologySheet.label(for: weeklyRate.certainty))")
            .foregroundStyle(Tokens.Color.certainty(MethodologySheet.level(for: weeklyRate.certainty)))
        }
      }
      .font(Tokens.Text.label)
      .foregroundStyle(Tokens.Color.textSecondary)
      .accessibilityElement(children: .combine)
    } else {
      Text(
        "A weekly rate needs readings at least \(BodyweightTrend.minimumSpanDays) days apart. "
          + "Keep weighing in."
      )
      .font(Tokens.Text.caption)
      .foregroundStyle(Tokens.Color.textSecondary)
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func rateText(_ perWeek: Double, direction: BodyweightTrend.Direction) -> String {
    guard direction != .steady else { return "Holding steady" }
    let magnitude = Self.format(unit.fromKilograms(abs(perWeek)), places: 1)
    let verb = direction == .gaining ? "Gaining" : "Losing"
    return "\(verb) \(magnitude) \(unit.abbreviation) a week"
  }

  private static func symbol(for direction: BodyweightTrend.Direction) -> String {
    switch direction {
    case .gaining: "arrow.up.right"
    case .losing: "arrow.down.right"
    case .steady: "equal"
    }
  }

  /// Today's actual number, kept separate from the average.
  ///
  /// Both facts matter and they are not the same fact: the average is the trend, the latest reading
  /// is what the scale said. Collapsing them would make one of the two a lie.
  private func latestLine(_ latest: BodyweightRow) -> some View {
    Text(
      "Last reading \(Self.format(unit.fromKilograms(latest.weightKg), places: 1)) "
        + "\(unit.abbreviation), \(latest.measuredAt.formatted(.relative(presentation: .named)))"
    )
    .font(Tokens.Text.caption)
    .foregroundStyle(Tokens.Color.textSecondary)
  }

  // MARK: - Chart

  /// Raw readings inside the rate window, oldest first.
  private var plotted: [BodyweightRow] {
    guard let newest = records.first?.measuredAt else { return [] }
    let cutoff = newest.addingTimeInterval(-Double(BodyweightTrend.windowDays) * 86_400)
    return records.filter { $0.measuredAt > cutoff }.sorted { $0.measuredAt < $1.measuredAt }
  }

  private var smoothedLine: [BodyweightReading] {
    BodyweightTrend.smoothedSeries(plotted.map(\.reading))
  }

  private var chart: some View {
    Chart {
      // The readings themselves, recessive. Present so the line is not mistaken for the data.
      ForEach(plotted) { row in
        PointMark(
          x: .value("Date", row.measuredAt),
          y: .value("Weight", unit.fromKilograms(row.weightKg))
        )
        .symbolSize(18)
        .foregroundStyle(Tokens.Color.textSecondary.opacity(0.45))
      }
      // One series, so no legend: the heading above already names it.
      ForEach(smoothedLine, id: \.measuredAt) { point in
        LineMark(
          x: .value("Date", point.measuredAt),
          y: .value("Weight", unit.fromKilograms(point.weightKg))
        )
        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
        .foregroundStyle(Tokens.Color.accent)
        .interpolationMethod(.monotone)
      }
      // The emphasised endpoint: where the trend has actually got to.
      if let last = smoothedLine.last {
        PointMark(
          x: .value("Date", last.measuredAt),
          y: .value("Weight", unit.fromKilograms(last.weightKg))
        )
        .symbolSize(70)
        .foregroundStyle(Tokens.Color.accent)
      }
    }
    // Bodyweight never starts at zero, so a zero baseline would compress every real change into a
    // flat line at the top of the plot.
    .chartYScale(domain: .automatic(includesZero: false))
    .chartYAxisLabel(unit.abbreviation)
    .chartLegend(.hidden)
    .frame(height: 170)
    .accessibilityLabel("Bodyweight over the last \(BodyweightTrend.windowDays) days")
  }

  // MARK: - List

  private var list: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      Text("Readings")
        .font(Tokens.Text.title)
        .foregroundStyle(Tokens.Color.textPrimary)

      VStack(spacing: Tokens.Spacing.hairline) {
        ForEach(records) { row in
          HStack {
            Text(Self.format(unit.fromKilograms(row.weightKg), places: 1))
              .font(Tokens.Text.setEntry)
              .monospacedDigit()
              .foregroundStyle(Tokens.Color.textPrimary)
            Text(unit.abbreviation)
              .font(Tokens.Text.caption)
              .foregroundStyle(Tokens.Color.textSecondary)
            Spacer(minLength: Tokens.Spacing.regular)
            Text(row.measuredAt.formatted(date: .abbreviated, time: .shortened))
              .font(Tokens.Text.caption)
              .foregroundStyle(Tokens.Color.textSecondary)
          }
          .padding(.horizontal, Tokens.Spacing.regular)
          .frame(minHeight: Tokens.minimumTapTarget)
          .background(
            Tokens.Color.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.control)
          )
          .accessibilityElement(children: .combine)
          .contextMenu {
            if let onDelete {
              // A mistyped weight is a wrong fact rather than history worth keeping, and it drags
              // the average with it until it is gone.
              Button(role: .destructive) { onDelete(row.id) } label: {
                Label("Delete this reading", systemImage: "trash")
              }
            }
          }
        }
      }
    }
  }

  private var addButton: some View {
    Button(action: onAdd) {
      Label("Add a reading", systemImage: "plus")
        .font(Tokens.Text.label)
        .frame(maxWidth: .infinity, minHeight: Tokens.loggerTapTarget)
    }
    .buttonStyle(.plain)
    .foregroundStyle(Tokens.Color.accent)
    .background(Tokens.Color.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
  }

  private var empty: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      Image(systemName: "scalemass")
        .font(Tokens.Text.hero)
        .foregroundStyle(Tokens.Color.textSecondary)
      Text("No readings yet")
        .font(Tokens.Text.title)
        .foregroundStyle(Tokens.Color.textPrimary)
      Text(
        "Weigh in when you can, ideally at the same time of day. The figure shown will be a "
          + "\(BodyweightTrend.smoothingDays)-day average, because a single morning is mostly food "
          + "and water."
      )
      .font(Tokens.Text.label)
      .foregroundStyle(Tokens.Color.textSecondary)
      .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// Trailing zeros trimmed, so 80 kg is "80" and not "80.0".
  static func format(_ value: Double, places: Int) -> String {
    var text = String(format: "%.\(places)f", value)
    guard text.contains(".") else { return text }
    while text.hasSuffix("0") { text.removeLast() }
    if text.hasSuffix(".") { text.removeLast() }
    return text
  }
}

#if DEBUG
  #Preview("Bodyweight") {
    let now = Date()
    let rows = (0..<24).map { day in
      BodyweightView.BodyweightRow(
        id: UUID(),
        weightKg: 84 - 0.4 * (Double(23 - day) / 7) + (day.isMultiple(of: 3) ? 0.5 : -0.3),
        measuredAt: now.addingTimeInterval(-Double(day) * 86_400)
      )
    }
    let readings = rows.map { BodyweightReading(weightKg: $0.weightKg, measuredAt: $0.measuredAt) }
    return NavigationStack {
      BodyweightView(
        records: rows,
        smoothedKg: BodyweightTrend.smoothed(readings, endingAt: now),
        weeklyRate: BodyweightTrend.weeklyRate(readings, asOf: now),
        unit: .kilograms,
        onAdd: {}
      )
      .navigationTitle("Bodyweight")
    }
  }
#endif
