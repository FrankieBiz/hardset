import HardsetCore
import SwiftUI

/// An intentionally static ledger. Sharing never adds a feed or a public profile.
///
/// Sets are listed in the order they were performed, grouped into runs of one movement on one piece
/// of equipment, so the receipt reads like the training log it is rather than repeating the
/// movement's name on every line.
///
/// The same view is rendered into the shared image, so it holds no controls of its own. The one
/// exception is `onDeleteLine`: a screen correcting a past workout passes it while editing, and
/// each set then shows a delete control. The share renderer never passes it.
public struct WorkoutReceiptView: View {
  private let receipt: WorkoutReceipt
  private let unit: WeightUnit
  private let onDeleteLine: ((WorkoutReceipt.Line) -> Void)?

  public init(
    receipt: WorkoutReceipt, unit: WeightUnit,
    onDeleteLine: ((WorkoutReceipt.Line) -> Void)? = nil
  ) {
    self.receipt = receipt
    self.unit = unit
    self.onDeleteLine = onDeleteLine
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.section) {
      Text("HARDSET")
        .font(Tokens.Text.display)
        .foregroundStyle(Tokens.Color.accent)
      VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
        Text(receipt.title.isEmpty ? "Workout receipt" : receipt.title)
          .font(Tokens.Text.title)
        Text(receipt.startedAt.formatted(date: .abbreviated, time: .shortened))
          .font(Tokens.Text.provenance)
          .foregroundStyle(Tokens.Color.textSecondary)
      }
      if receipt.lines.isEmpty {
        Text("No sets were logged in this workout.")
          .font(Tokens.Text.provenance)
          .foregroundStyle(Tokens.Color.textSecondary)
      }
      ForEach(receipt.blocks) { block in
        VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
          VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
            Text(block.exerciseName).font(Tokens.Text.headline)
            Text(block.equipmentLabel)
              .font(Tokens.Text.provenance)
              .foregroundStyle(Tokens.Color.textSecondary)
          }
          .accessibilityElement(children: .combine)
          .accessibilityAddTraits(.isHeader)
          ForEach(block.lines) { line in
            row(line)
          }
          Divider().overlay(Tokens.Color.border)
        }
      }
      Text("Recorded training log. Loads and equipment are user-entered, not independently verified. Records compare working sets of the same movement on the same recorded machine, or with no machine recorded, against history before this workout.")
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.textSecondary)
      if !receipt.notes.isEmpty {
        Text(receipt.notes).font(Tokens.Text.caption).foregroundStyle(Tokens.Color.textSecondary)
      }
    }
    .foregroundStyle(Tokens.Color.textPrimary)
    .padding(Tokens.Spacing.section)
    .background(Tokens.Color.background)
  }

  /// One set: its load and reps as figures, then anything it earned. The delete control, when
  /// present, is its own accessibility element so activating the set's description can never
  /// delete it.
  private func row(_ line: WorkoutReceipt.Line) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.snug) {
      if let onDeleteLine {
        Button {
          onDeleteLine(line)
        } label: {
          Image(systemName: "minus.circle.fill")
            .font(Tokens.Text.headline)
            .foregroundStyle(Tokens.Color.error)
            .frame(minWidth: Tokens.minimumTapTarget, minHeight: Tokens.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Delete set, \(Self.spokenSet(line, unit: unit))")
      }
      VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.snug) {
          Text("\(LoadText.entered(line.weightKg, in: unit)) \(unit.abbreviation) × \(line.reps)")
            .font(Tokens.Text.figure)
            .monospacedDigit()
          if line.isWarmup {
            Text("Warm-up")
              .font(Tokens.Text.caption)
              .foregroundStyle(Tokens.Color.textSecondary)
          }
          Spacer(minLength: 0)
        }
        ForEach(line.records) { record in
          Label(record.kind.label, systemImage: "checkmark.seal")
            .font(Tokens.Text.provenance)
            .foregroundStyle(Tokens.Color.pr)
        }
      }
      .accessibilityElement(children: .combine)
    }
  }

  /// A set in words, for its delete control and for a confirmation that names what it removes.
  public static func spokenSet(_ line: WorkoutReceipt.Line, unit: WeightUnit) -> String {
    "\(line.exerciseName), \(LoadText.entered(line.weightKg, in: unit)) \(unit.abbreviation) "
      + "× \(line.reps)\(line.isWarmup ? ", warm-up" : "")"
  }
}
