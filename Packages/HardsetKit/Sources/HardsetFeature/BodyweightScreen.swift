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
    .task { reload() }
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
    do {
      try store.record(weightKg: unit.toKilograms(entered))
      reload()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func delete(_ id: UUID) {
    do {
      try store.delete(id)
      reload()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func reload() {
    do {
      let trend = try store.trend()
      records = try store.history()
      smoothedKg = trend.smoothedKg
      weeklyRate = trend.weeklyRate
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
