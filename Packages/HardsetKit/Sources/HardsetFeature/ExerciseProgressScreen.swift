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
        ProgressionChartView(
          series: history?.chartSeries() ?? [],
          machineChanges: history?.machineChanges ?? [],
          unit: unit,
          exerciseName: exerciseName,
          onExplain: { isShowingMethodology = true }
        )
        .padding(.horizontal, Tokens.Spacing.regular)
      }
    }
    .background(Tokens.Color.background)
    .navigationTitle(exerciseName)
    .task { load() }
    .refreshable { load() }
    .sheet(isPresented: $isShowingMethodology) {
      // The estimate is a formula applied to the user's own sets, not a study finding, and the
      // sheet says which formula and where it stops being meaningful.
      MethodologySheet(source: ProgressionAnalyzer.source)
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
