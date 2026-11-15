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
    self.init(
      machineName: machineName, incrementKg: incrementKg, unit: unit, showsFailure: false,
      onSave: onSave, onCancel: onCancel)
  }

  /// The failed-save state needs `failed`, which is private `@State` set by a rejected save, so
  /// the catalogue reaches it through this seam. The initialiser above is this one with the
  /// failure notice off.
  init(machineName: String, incrementKg: Double?, unit: WeightUnit, showsFailure: Bool,
    onSave: @escaping (Double?) -> Bool, onCancel: @escaping () -> Void) {
    self.machineName = machineName; self.unit = unit
    self.onSave = onSave; self.onCancel = onCancel
    originalIncrementKg = incrementKg
    let seed = NumericEntryBuffer(value: incrementKg.map(unit.fromKilograms), replaceOnFirstEntry: true)
    seedText = seed.text
    _buffer = State(initialValue: seed)
    _failed = State(initialValue: showsFailure)
  }
  private var valid: Bool { buffer.isEmpty || buffer.value.map { $0.isFinite && $0 > 0 } == true }
  public var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
          Text(machineName).font(Tokens.Text.title).foregroundStyle(Tokens.Color.chalk)
          Text("Enter the smallest load change this machine actually permits in \(unit.abbreviation). Leave it empty if unknown. This controls inline adjustments and future record comparisons; saved loads stay unchanged.")
            .font(Tokens.Text.provenance).foregroundStyle(Tokens.Color.chalkDim)
          if failed {
            Text("The load step could not be saved. Try again. No draft or saved load was changed.")
              .font(Tokens.Text.provenance).foregroundStyle(Tokens.Color.plateRed)
          }
          // One commit action: the pad's own footer is the explicit Save. A second "Save" button
          // under a primary "Done" gave two identical-looking commits, only one of which showed
          // when the value could not be saved.
          NumericPad(
            buffer: $buffer, title: "Load step", unit: unit.abbreviation,
            doneTitle: "Save load step", isDoneEnabled: valid, onDone: save
          )
        }.padding(Tokens.Spacing.loose)
      }
      .background(Tokens.Color.canvas)
      .tint(Tokens.Color.plateBlue)
      .hardsetNavigationTitle("Machine load step")
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) } }
    }
    // A step typed but not yet saved survives a brushed swipe; Cancel is the explicit way out.
    .interactiveDismissDisabled(buffer.text != seedText)
  }
  private func save() {
    guard valid else { return }
    failed = !onSave(buffer.text == seedText ? originalIncrementKg : buffer.value.map(unit.toKilograms))
  }
}

#if DEBUG
  #Preview("Load step, known step in kg") {
    LoadStepSheet(
      machineName: "Cybex Leg Press", incrementKg: 2.5, unit: .kilograms, onSave: { _ in true },
      onCancel: {})
  }

  #Preview("Load step, known step in lb") {
    LoadStepSheet(
      machineName: "Cybex Leg Press", incrementKg: 2.5, unit: .pounds, onSave: { _ in true },
      onCancel: {})
  }

  #Preview("Load step, blank (unknown)") {
    LoadStepSheet(
      machineName: "Cybex Leg Press", incrementKg: nil, unit: .kilograms, onSave: { _ in true },
      onCancel: {})
  }

  #Preview("Load step, invalid zero with Save disabled") {
    LoadStepSheet(
      machineName: "Cybex Leg Press", incrementKg: 0, unit: .kilograms, onSave: { _ in true },
      onCancel: {})
  }

  #Preview("Load step, failed save") {
    KeypadCatalogView(section: .loadStep)
  }

  #Preview("Load step, accessibility size") {
    LoadStepSheet(
      machineName: "Cybex Leg Press", incrementKg: 2.5, unit: .kilograms, onSave: { _ in true },
      onCancel: {}
    )
    .environment(\.dynamicTypeSize, .accessibility3)
  }
#endif
