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
      if loadFailed {
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
        .padding(.horizontal, Tokens.Spacing.regular)
      }
    }
    .background(Tokens.Color.ground)
    .navigationTitle(exerciseName)
    .task { load() }
    .refreshable { load() }
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
    var machinesSeenPerGym: [GymID: Int] = [:]

    return ordered.map { series in
      let gym = series.key.machineID.flatMap { history.machineGyms[$0] }
      let gymIndex = gym.flatMap { gyms.firstIndex(of: $0) }
      var withinGym = 0
      if let gym {
        withinGym = machinesSeenPerGym[gym, default: 0]
        machinesSeenPerGym[gym] = withinGym + 1
      }
      return ProgressionChartView.SeriesInput(
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

  private func load() {
    do {
      history = try store.history(for: exerciseID)
      loadFailed = false
    } catch {
      history = nil
      loadFailed = true
    }
  }
}
