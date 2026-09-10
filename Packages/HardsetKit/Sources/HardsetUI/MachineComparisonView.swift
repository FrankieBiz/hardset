import HardsetCore
import SwiftUI

/// "What do I press on each of these?" — answered in words, under the chart.
///
/// The chart already draws one line per machine and never merges them, which is the app's central
/// claim. What it does not do is *say* the numbers: reading two loads off two lines is work, and
/// the lifter's actual question is a comparison, not a trend. This is that comparison, and it is a
/// pure read over series the chart is already holding.
///
/// Every delta is stated as a difference between machines. Across two machines a load gap is
/// neither progress nor regression — it is leverage, cam shape and carriage weight — and a lifter
/// reading "-20 kg" as having got weaker is the exact misreading `MachineChange` exists to prevent.
public struct MachineComparisonView: View {
  public struct Row: Hashable, Sendable, Identifiable {
    public let key: ProgressionKey
    public let label: String
    public let heaviestLoadKg: Double
    public let bestEstimatedOneRepMaxKg: Double?
    public let lastTrained: Date
    public let sessionCount: Int
    /// `nil` on the machine everything else is measured against.
    public let heaviestLoadDeltaKg: Double?
    /// The reference machine's name, for wording the delta. `nil` on the reference row.
    public let referenceLabel: String?

    public var id: ProgressionKey { key }

    public init(
      key: ProgressionKey,
      label: String,
      heaviestLoadKg: Double,
      bestEstimatedOneRepMaxKg: Double?,
      lastTrained: Date,
      sessionCount: Int,
      heaviestLoadDeltaKg: Double?,
      referenceLabel: String?
    ) {
      self.key = key
      self.label = label
      self.heaviestLoadKg = heaviestLoadKg
      self.bestEstimatedOneRepMaxKg = bestEstimatedOneRepMaxKg
      self.lastTrained = lastTrained
      self.sessionCount = sessionCount
      self.heaviestLoadDeltaKg = heaviestLoadDeltaKg
      self.referenceLabel = referenceLabel
    }
  }

  private let rows: [Row]
  private let unit: WeightUnit
  /// Captured at construction rather than read while rendering, so recency is a value the view was
  /// handed instead of a clock read that differs between two draws of the same row.
  private let now: Date

  public init(rows: [Row], unit: WeightUnit, now: Date = Date()) {
    self.rows = rows
    self.unit = unit
    self.now = now
  }

  public var body: some View {
    // One machine is not a comparison. Rendering a single row under a single-line chart would be
    // restating it, so this section simply is not there.
    if rows.count > 1 {
      VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
        Text("Your best on each")
          .font(Tokens.Text.title)
          .foregroundStyle(Tokens.Color.textPrimary)

        VStack(spacing: Tokens.Spacing.snug) {
          ForEach(rows) { row(for: $0) }
        }

        Text(
          "Loads on different machines are never combined. The gap between them is the equipment "
            + "\u{2014} leverage, the cam, the weight of the carriage \u{2014} not your strength."
        )
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.vertical, Tokens.Spacing.loose)
    }
  }

  private func row(for row: Row) -> some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
      HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.snug) {
        Text(row.label)
          .font(Tokens.Text.label)
          .foregroundStyle(Tokens.Color.textPrimary)
        Spacer(minLength: 0)
        Text("\(Self.number(unit.displayValue(fromKilograms: row.heaviestLoadKg))) \(unit.abbreviation)")
          .font(Tokens.Text.setEntry)
          .foregroundStyle(Tokens.Color.textPrimary)
      }

      Text(detail(for: row))
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(Tokens.Spacing.regular)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Tokens.Color.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
    .accessibilityElement(children: .combine)
    .accessibilityLabel(spokenLabel(for: row))
  }

  /// The estimate, when there is one, then when they were last on it, then the comparison.
  private func detail(for row: Row) -> String {
    var parts: [String] = []
    if let estimate = row.bestEstimatedOneRepMaxKg {
      parts.append(
        "Est. 1RM \(Self.number(unit.displayValue(fromKilograms: estimate))) \(unit.abbreviation)"
      )
    }
    // `TrainingRecency`, not the system relative format: DECISION #42 banned the latter because it
    // collapses seven to thirteen days into "last week". The row that reaches this card already
    // words it that way, and one fact must not be worded two ways across a tap.
    parts.append("Last trained \(TrainingRecency.phrase(since: row.lastTrained, asOf: now))")
    if let delta = row.heaviestLoadDeltaKg, let reference = row.referenceLabel {
      // Converted before it is worded, so a lifter reading in pounds is not told "20 kg more".
      parts.append(
        MachineComparison.explanation(
          forDelta: unit.displayValue(fromKilograms: delta),
          unitAbbreviation: unit.abbreviation,
          machineName: reference
        )
      )
    } else {
      parts.append("The one you use most \u{2014} everything else is measured against it.")
    }
    return parts.joined(separator: " \u{2022} ")
  }

  private func spokenLabel(for row: Row) -> String {
    "\(row.label), \(detail(for: row).replacingOccurrences(of: " \u{2022} ", with: ", "))"
  }

  /// Trailing ".0" dropped so a whole number reads as one. Rounding already happened in
  /// `displayValue`, which is the single place conversion and precision live.
  ///
  /// Formatted through the locale rather than `String(format: "%.1f")`, which writes a POSIX point
  /// whatever the reader's separator is — the same defect the input side already fixed.
  static func number(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...1)))
  }
}
