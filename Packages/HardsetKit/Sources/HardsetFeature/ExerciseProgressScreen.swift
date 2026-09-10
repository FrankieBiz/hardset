import HardsetCore
import HardsetStore
import HardsetUI
import SwiftUI

/// One movement's load history, wired.
///
/// This is where the app's per-machine tracking pays off, and it is the reason the chart refuses
/// to merge machines: a single line through two different leg presses draws progress the lifter did
/// not make. Reaching it from the live session matters as much as the chart itself — "how have I
/// been doing on this" is a question asked while standing at the machine, not at a desk.
@MainActor
public struct ExerciseProgressScreen: View {
  @State private var history: ProgressionHistory?
  @State private var isLoading = true
  @State private var loadFailed = false
  @State private var isShowingMethodology = false

  private let store: ProgressionStore
  private let exerciseID: ExerciseID
  private let exerciseName: String
  private let unit: WeightUnit

  public init(
    store: ProgressionStore,
    exerciseID: ExerciseID,
    exerciseName: String,
    unit: WeightUnit
  ) {
    self.store = store
    self.exerciseID = exerciseID
    self.exerciseName = exerciseName
    self.unit = unit
  }

  public var body: some View {
    ScrollView {
      if isLoading && history == nil {
        ProgressView()
          .frame(maxWidth: .infinity, minHeight: 240)
      } else if loadFailed {
        ContentUnavailableView {
          Label("Could not read this history", systemImage: "exclamationmark.triangle")
        } description: {
          Text("Your logged sets are safe. Pull down to try again.")
        }
      } else {
        VStack(alignment: .leading, spacing: 0) {
          ProgressionChartView(
            series: seriesInputs,
            machineChanges: history?.machineChanges ?? [],
            unit: unit,
            onExplain: { isShowingMethodology = true }
          )
          // The comparison the chart draws but never states. Same data, no second read.
          MachineComparisonView(rows: comparisonRows, unit: unit)
        }
        .padding(.horizontal, Tokens.Spacing.edge)
      }
    }
    .background(Tokens.Color.ground)
    .navigationTitle(exerciseName)
    .task { await load() }
    .refreshable { await load() }
    .sheet(isPresented: $isShowingMethodology) {
      // The estimate is a formula applied to the user's own sets, not a study finding, and the
      // sheet says which formula and where it stops being meaningful.
      MethodologySheet(source: ProgressionAnalyzer.source)
    }
  }

  /// Series are labelled here because the label needs the store's machine names, and the chart is
  /// deliberately free of storage. Ordered by most recently used so the machine the lifter is on
  /// now reads first in the legend.
  private var seriesInputs: [ProgressionChartView.SeriesInput] {
    guard let history else { return [] }
    let ordered = history.series.sorted { lhs, rhs in
      (lhs.points.last?.date ?? .distantPast) > (rhs.points.last?.date ?? .distantPast)
    }
    // Hue is assigned per gym, in the order this chart first mentions each one, so it is stable
    // for the life of the chart and does not shift when a series drops out.
    let gyms = history.gymOrder(for: ordered.map(\.key))
    // Counted per *colour bucket*, not per gym. Keyed on `GymID` the counter never advanced for a
    // series with no gym -- free weights, and a machine whose gym row is gone -- so two of them
    // drew the same neutral grey with the same solid stroke and were indistinguishable. Everything
    // past the third gym shares the overflow colour for the same reason, so it shares the counter.
    let overflowBucket = Tokens.Color.Series.ordered.count
    var machinesSeenPerBucket: [Int: Int] = [:]

    return ordered.map { series in
      let gym = series.key.machineID.flatMap { history.machineGyms[$0] }
      let gymIndex = gym.flatMap { gyms.firstIndex(of: $0) }
      let bucket = gymIndex.map { min($0, overflowBucket) } ?? overflowBucket
      let withinGym = machinesSeenPerBucket[bucket, default: 0]
      machinesSeenPerBucket[bucket] = withinGym + 1
      return ProgressionChartView.SeriesInput(
        key: series.key,
        label: history.label(for: series.key),
        points: series.points,
        gymIndex: gymIndex,
        machineIndexInGym: withinGym
      )
    }
  }

  /// Per-machine bests, labelled here for the same reason the chart's series are: the label needs
  /// the store's machine names, and the view stays free of storage.
  private var comparisonRows: [MachineComparisonView.Row] {
    guard let history else { return [] }
    let computed = MachineComparison.rows(from: history.series)
    guard let reference = computed.first else { return [] }
    let referenceLabel = history.label(for: reference.key)
    return computed.map { row in
      MachineComparisonView.Row(
        key: row.key,
        label: history.label(for: row.key),
        heaviestLoadKg: row.heaviestLoadKg,
        bestEstimatedOneRepMaxKg: row.bestEstimatedOneRepMaxKg,
        lastTrained: row.lastTrained,
        sessionCount: row.sessionCount,
        heaviestLoadDeltaKg: row.heaviestLoadDeltaKg,
        referenceLabel: row.isReference ? nil : referenceLabel
      )
    }
  }

  private func load() async {
    isLoading = true
    let store = store
    let exerciseID = exerciseID
    let result = await readOffMain { try store.history(for: exerciseID) }
    guard !Task.isCancelled else { return }

    switch result {
    case .success(let loaded):
      history = loaded
      loadFailed = false
    case .failure:
      history = nil
      loadFailed = true
    }
    isLoading = false
  }
}
