import HardsetCore
import SwiftUI

/// Explicit equipment knowledge, never a guessed plate increment.
public struct LoadStepSheet: View {
  private let machineName: String
  private let unit: WeightUnit
  private let originalIncrementKg: Double?
  private let seedText: String
  private let onSave: (Double?) -> Bool
  private let onCancel: () -> Void
  @State private var buffer: NumericEntryBuffer
  @State private var failed = false

  public init(machineName: String, incrementKg: Double?, unit: WeightUnit,
    onSave: @escaping (Double?) -> Bool, onCancel: @escaping () -> Void) {
    self.machineName = machineName; self.unit = unit
    self.onSave = onSave; self.onCancel = onCancel
    originalIncrementKg = incrementKg
    let seed = NumericEntryBuffer(value: incrementKg.map(unit.fromKilograms), replaceOnFirstEntry: true)
    seedText = seed.text
    _buffer = State(initialValue: seed)
  }
  private var valid: Bool { buffer.isEmpty || buffer.value.map { $0.isFinite && $0 > 0 } == true }
  public var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
          Text(machineName).font(Tokens.Text.title).foregroundStyle(Tokens.Color.textPrimary)
          Text("Enter the smallest load change this machine actually permits in \(unit.abbreviation). Leave it empty if unknown. This controls inline adjustments and future record comparisons; saved loads stay unchanged.")
            .font(Tokens.Text.provenance).foregroundStyle(Tokens.Color.textSecondary)
          NumericPad(buffer: $buffer, title: "Load step", unit: unit.abbreviation, onDone: save)
          if failed {
            Text("The load step could not be saved. Try again. No draft or saved load was changed.")
              .font(Tokens.Text.provenance).foregroundStyle(Tokens.Color.error)
          }
          Button("Save load step", action: save)
            .buttonStyle(HardsetButtonStyle(.primary, size: .logger)).disabled(!valid)
        }.padding(Tokens.Spacing.loose)
      }
      .background(Tokens.Color.background)
      .tint(Tokens.Color.accent)
      .hardsetNavigationTitle("Machine load step")
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) } }
    }
  }
  private func save() {
    guard valid else { return }
    failed = !onSave(buffer.text == seedText ? originalIncrementKg : buffer.value.map(unit.toKilograms))
  }
}
