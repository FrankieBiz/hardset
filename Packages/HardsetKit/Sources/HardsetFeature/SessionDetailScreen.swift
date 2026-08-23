import HardsetCore
import HardsetStore
import HardsetUI
import SwiftUI

/// One past workout, wired.
///
/// Maps the store's rows onto the view's, which is the boundary that keeps `HardsetUI` free of any
/// storage dependency.
@MainActor
public struct SessionDetailScreen: View {
  private let row: HistoryRow
  private let store: HistoryStore
  private let unit: WeightUnit
  /// Starts this workout again. `nil` hides the affordance -- correct when a workout is already in
  /// progress, because the app will not silently abandon one.
  private let onRepeat: (([RepeatableExercise]) -> Void)?

  @State private var sets: [LoggedSetRow] = []
  @State private var loadFailed = false

  public init(
    row: HistoryRow,
    store: HistoryStore,
    unit: WeightUnit,
    onRepeat: (([RepeatableExercise]) -> Void)? = nil
  ) {
    self.row = row
    self.store = store
    self.unit = unit
    self.onRepeat = onRepeat
  }

  public var body: some View {
    Group {
      if loadFailed {
        ContentUnavailableView {
          Label("Could not read this workout", systemImage: "exclamationmark.triangle")
        } description: {
          Text("Your logged sets are safe. Pull down to try again.")
        }
      } else {
        SessionDetailView(
          title: row.title,
          date: row.date,
          duration: row.duration,
          hasImplausibleDuration: row.hasImplausibleDuration,
          sets: sets,
          unit: unit
        )
      }
    }
    .navigationTitle(row.title.isEmpty ? "Workout" : row.title)
    .toolbar {
      if let onRepeat, !sets.isEmpty {
        ToolbarItem(placement: .primaryAction) {
          Button {
            // Rebuilt from what was logged, not from what was planned.
            onRepeat((try? store.plan(for: row.id)) ?? [])
          } label: {
            Label("Do it again", systemImage: "arrow.clockwise")
          }
        }
      }
    }
    .task { load() }
    .refreshable { load() }
  }

  private func load() {
    do {
      sets = try store.sets(in: row.id).map {
        LoggedSetRow(
          id: $0.id.rawValue,
          exerciseName: $0.exerciseName,
          isBodyweight: $0.modality == .bodyweight,
          machineName: $0.machineName,
          weightKg: $0.weightKg,
          reps: $0.reps,
          rpe: $0.rpe,
          isWarmup: $0.isWarmup
        )
      }
      loadFailed = false
    } catch {
      sets = []
      loadFailed = true
    }
  }
}
