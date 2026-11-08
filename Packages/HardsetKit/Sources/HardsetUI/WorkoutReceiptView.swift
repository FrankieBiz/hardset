import HardsetCore
import SwiftUI

/// An intentionally static ledger. Sharing never adds a feed or a public profile.
public struct WorkoutReceiptView: View {
  private let receipt: WorkoutReceipt
  private let unit: WeightUnit
  public init(receipt: WorkoutReceipt, unit: WeightUnit) { self.receipt = receipt; self.unit = unit }
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
      ForEach(receipt.lines) { line in
        VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
          HStack(alignment: .firstTextBaseline) {
            Text(line.exerciseName).font(Tokens.Text.headline)
            Spacer(minLength: Tokens.Spacing.snug)
            Text("\(unit.fromKilograms(line.weightKg).formatted(.number.precision(.fractionLength(0...2)))) \(unit.abbreviation) × \(line.reps)")
              .font(Tokens.Text.figure).monospacedDigit()
          }
          Text(line.machineName ?? (line.isImported ? "Imported • Unevaluated Machine" : "Unevaluated Machine"))
            .font(Tokens.Text.provenance)
            .foregroundStyle(Tokens.Color.textSecondary)
          if line.isWarmup { Text("Warm-up").font(Tokens.Text.caption) }
          ForEach(line.records) { record in
            Label(record.kind.label, systemImage: "checkmark.seal")
              .font(Tokens.Text.provenance)
              .foregroundStyle(Tokens.Color.pr)
          }
          Divider().overlay(Tokens.Color.border)
        }
        .accessibilityElement(children: .combine)
      }
      Text("Recorded training log. Loads and equipment are user-entered, not independently verified. Records compare working sets on the same recorded machine against history before this workout.")
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
}
