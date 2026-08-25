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
  /// Reads one movement's load history. `nil` leaves the headings inert, which is correct when no
  /// progression store was supplied.
  private let progression: ProgressionStore?

  @State private var sets: [LoggedSetRow] = []
  /// The workout's own note, read alongside its sets.
  @State private var notes = ""
  @State private var loadFailed = false
  /// Which movement's load history is open.
  @State private var progressTarget: ProgressTarget?

  private struct ProgressTarget: Identifiable, Hashable {
    let id: ExerciseID
  }

  public init(
    row: HistoryRow,
    store: HistoryStore,
    unit: WeightUnit,
    onRepeat: (([RepeatableExercise]) -> Void)? = nil,
    progression: ProgressionStore? = nil
  ) {
    self.row = row
    self.store = store
    self.unit = unit
    self.onRepeat = onRepeat
    self.progression = progression
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
          notes: notes,
          unit: unit,
          onShowProgress: progression == nil ? nil : { progressTarget = ProgressTarget(id: $0) }
        )
      }
    }
    .navigationDestination(item: $progressTarget) { target in
      if let progression {
        ExerciseProgressScreen(
          store: progression,
          exerciseID: target.id,
          exerciseName: sets.first { $0.exerciseID == target.id }?.exerciseName ?? "Movement",
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
          exerciseID: $0.exerciseID,
          exerciseName: $0.exerciseName,
          isBodyweight: $0.modality == .bodyweight,
          machineName: $0.machineName,
          weightKg: $0.weightKg,
          reps: $0.reps,
          rpe: $0.rpe,
          kind: $0.kind
        )
      }
      notes = try store.notes(for: row.id)
      loadFailed = false
    } catch {
      sets = []
      notes = ""
      loadFailed = true
    }
  }
}
