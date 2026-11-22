import HardsetCore
import HardsetStore
import HardsetUI
import SwiftUI

/// The sheets this screen opens, one at a time. `nonisolated` so its computed `id` satisfies
/// `Identifiable` without isolated-conformance inference, as `VolumeSheet` does.
private nonisolated enum ProgressSheet: Identifiable {
  /// How the load history is measured.
  case methodology
  /// The working behind a figure.
  case working(WorkedFromPresentation)

  var id: String {
    switch self {
    case .methodology: "methodology"
    case .working(let presentation): "working-\(presentation.id.uuidString)"
    }
  }
}

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
  /// The sheet that is up, or `nil`. One value for both, so the screen holds one presentation.
  @State private var presented: ProgressSheet?

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
          VStack(alignment: .leading, spacing: Tokens.Spacing.loose) {
            ProgressionChartView(
              series: seriesInputs,
              machineChanges: history.machineChanges,
              unit: unit,
              estimatesOneRepMax: history.estimatesOneRepMax,
              assumesAddedLoad: history.assumesAddedLoad,
              onExplain: { presented = .methodology },
              onShowEstimateWorking: { showEstimateWorking($0) }
            )
            // Imported history is a line of its own, never joined to a machine's. Said under the
            // chart whenever one of its lines is imported, so the legend's label is not the only hint.
            if history.series.contains(where: { $0.key.isImported }) {
              Text(ProgressCopy.importedSeriesNote)
                .font(Tokens.Text.caption)
                .foregroundStyle(Tokens.Color.chalkDim)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
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
    .background(Tokens.Color.canvas)
    .hardsetNavigationTitle(exerciseName)
    // Keyed on the movement, so a different exercise reloads and a stale read is cancelled.
    .task(id: exerciseID) { await load() }
    .refreshable { await load() }
    .sheet(item: $presented) { sheet in
      switch sheet {
      case .methodology:
        // The estimate is a formula applied to the user's own sets, not a study finding, and the
        // sheet says which formula and where it stops being meaningful.
        MethodologySheet(source: ProgressionAnalyzer.source)
          .hardsetSheet()
      case .working(let presentation):
        // The sets behind the figure the lifter tapped, from the history on screen.
        WorkedFromSheet(account: presentation.account)
          .hardsetSheet()
      }
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
        ProgressionChartView.SeriesInput(
          label: history.label(for: $0.key), points: $0.points,
          recordSessionIDs: history.recordSessionIDs[$0.key] ?? [],
          bestAtWeight: history.bestAtWeight[$0.key] ?? [], key: $0.key)
      }
  }

  /// Opens the working behind a machine's latest estimated max. Derived from the sets the history on
  /// screen was built from, by the functions the chart's own points come from, when it is asked for.
  private func showEstimateWorking(_ key: ProgressionKey) {
    guard let history = snapshot.value,
      let working = EstimateWorking.deriveLatest(
        key: key, samples: history.samples, warmups: history.warmupSamples,
        estimatesOneRepMax: history.estimatesOneRepMax,
        assumesAddedLoad: history.assumesAddedLoad, label: history.label(for:))
    else { return }
    presented = .working(WorkedFromPresentation(working.account(format: WorkedFromFormat(unit: unit))))
  }

  private func load() async {
    let store = store
    let id = exerciseID
    await snapshot.load { try await store.loadHistory(for: id) }
  }
}
