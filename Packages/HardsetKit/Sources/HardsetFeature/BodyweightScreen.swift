import HardsetCore
import HardsetStore
import HardsetUI
import SwiftUI

/// `BodyweightView` wired to storage.
///
/// Kept device-local by construction: `BodyweightStore` never touches the sync engine, and
/// `bodyweightEntries` is in `deferredSyncTableNames` rather than the synced list. Turning that on
/// is an additive, permitted change to make deliberately with App Review 5.1.3(ii) in hand -- not
/// something this screen does by reaching for a different store.
public struct BodyweightScreen: View {
  private let store: BodyweightStore
  private let unit: WeightUnit

  @State private var records: [BodyweightRecord] = []
  @State private var isLoading = true
  @State private var smoothedKg: Double?
  @State private var weeklyRate: Claim<Double> = .unevaluated(source: BodyweightTrend.source)
  @State private var isAdding = false
  @State private var errorMessage: String?

  public init(store: BodyweightStore, unit: WeightUnit) {
    self.store = store
    self.unit = unit
  }

  public var body: some View {
    BodyweightView(
      records: records.map {
        BodyweightView.BodyweightRow(id: $0.id, weightKg: $0.weightKg, measuredAt: $0.measuredAt)
      },
      smoothedKg: smoothedKg,
      weeklyRate: weeklyRate,
      unit: unit,
      onAdd: { isAdding = true },
      onDelete: delete
    )
    .overlay {
      if isLoading, records.isEmpty {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(Tokens.Color.ground)
      }
    }
    .task { await reload() }
    .sheet(isPresented: $isAdding) {
      NameEntrySheet(
        title: "Add a reading",
        prompt: "Weight in \(unit.abbreviation)",
        footnote: "Same time of day each time is what makes the trend mean anything \u{2014} "
          + "first thing in the morning is the usual choice.",
        confirmLabel: "Save",
        isDecimal: true,
        onConfirm: { text in
          isAdding = false
          record(text)
        },
        onCancel: { isAdding = false }
      )
    }
    .alert(
      "Could not save that",
      isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    ) {
      Button("OK") { errorMessage = nil }
    } message: {
      Text(errorMessage ?? "")
    }
  }

  /// Entered in whichever unit is on screen, stored in kilograms. The single conversion boundary,
  /// same as every set.
  private func record(_ text: String) {
    // Parsed through the locale, then through the plain form.
    //
    // The sheet presents the system decimal pad, which offers whatever separator the device uses.
    // `Double("62,5")` is nil in every locale, so a lifter in France or Germany typed a fractional
    // weight, tapped Save, and had nothing recorded and nothing said -- the guard returned in
    // silence. A failed parse is now reported rather than swallowed.
    guard let entered = TypedNumber.parse(text), entered > 0 else {
      errorMessage = "\"\(text)\" is not a weight this can read. Try a number like 82.5."
      return
    }
    let store = store
    let weightKg = unit.toKilograms(entered)
    Task {
      let result = await readOffMain { try store.record(weightKg: weightKg) }
      guard !Task.isCancelled else { return }
      switch result {
      case .success: await reload()
      case .failure(let error): errorMessage = error.localizedDescription
      }
    }
  }

  private func delete(_ id: UUID) {
    let store = store
    Task {
      let result = await readOffMain { try store.delete(id) }
      guard !Task.isCancelled else { return }
      switch result {
      case .success: await reload()
      case .failure(let error): errorMessage = error.localizedDescription
      }
    }
  }

  private func reload() async {
    isLoading = true
    let store = store
    let asOf = Date()
    let result = await readOffMain {
      // One history scan. `trend()` plus `history()` performed the same potentially decade-long
      // read twice every time this screen appeared.
      let records = try store.history()
      let readings = records.map(\.reading)
      return (
        records,
        BodyweightTrend.smoothed(readings, endingAt: asOf),
        BodyweightTrend.weeklyRate(readings, asOf: asOf)
      )
    }
    guard !Task.isCancelled else { return }
    switch result {
    case .success(let loaded):
      records = loaded.0
      smoothedKg = loaded.1
      weeklyRate = loaded.2
      errorMessage = nil
    case .failure(let error):
      errorMessage = error.localizedDescription
    }
    isLoading = false
  }
}
