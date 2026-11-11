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
///
/// Presented in a sheet that keeps its navigation bar for the caller's Done button, so the title
/// is drawn by `hardsetNavigationTitle` in the app's own type rather than by the stock bar.
@MainActor
public struct ExerciseProgressScreen: View {
  @State private var snapshot = SnapshotLoader<ProgressionHistory>()
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
      Group {
        if snapshot.loadFailed {
          HardsetEmptyState(
            title: "Could not read this history",
            detail: "Your logged sets are safe. Pull down to try again.",
            systemImage: "exclamationmark.triangle"
          )
        } else if let history = snapshot.value {
          ProgressionChartView(
            series: seriesInputs,
            machineChanges: history.machineChanges,
            unit: unit,
            estimatesOneRepMax: history.estimatesOneRepMax,
            onExplain: { isShowingMethodology = true }
          )
        } else {
          // Until the first read lands, say so. The chart's "No history yet" would be a claim
          // about the lifter's training made before the history was even read.
          HardsetLoadingState("Reading this history…")
        }
      }
      .padding(.horizontal, Tokens.Spacing.loose)
      .padding(.top, Tokens.Spacing.loose)
      .padding(.bottom, Tokens.Spacing.block)
    }
    .background(Tokens.Color.background)
    .hardsetNavigationTitle(exerciseName)
    // Keyed on the movement, so a different exercise reloads and a stale read is cancelled.
    .task(id: exerciseID) { await load() }
    .refreshable { await load() }
    .sheet(isPresented: $isShowingMethodology) {
      // The estimate is a formula applied to the user's own sets, not a study finding, and the
      // sheet says which formula and where it stops being meaningful.
      MethodologySheet(source: ProgressionAnalyzer.source)
        .hardsetSheet()
    }
  }

  /// Series are labelled here because the label needs the store's machine names, and the chart is
  /// deliberately free of storage. Ordered by most recently used so the machine the lifter is on
  /// now reads first in the legend.
  private var seriesInputs: [ProgressionChartView.SeriesInput] {
    guard let history = snapshot.value else { return [] }
    return history.series
      .sorted { lhs, rhs in
        (lhs.points.last?.date ?? .distantPast) > (rhs.points.last?.date ?? .distantPast)
      }
      .map {
        ProgressionChartView.SeriesInput(label: history.label(for: $0.key), points: $0.points)
      }
  }

  private func load() async {
    let store = store
    let id = exerciseID
    await snapshot.load { try await store.loadHistory(for: id) }
  }
}
