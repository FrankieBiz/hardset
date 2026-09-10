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
  @State private var isLoading = true
  @State private var isRepeating = false
  @State private var repeatFailed = false
  /// True once the read has returned, successful or not.
  ///
  /// Gating the spinner on `isLoading` instead flipped the branch out from under a pull-to-refresh
  /// on a workout with no logged sets -- `sets` stays empty there, so the refresh replaced the
  /// scrollable content, and its own pull indicator, with a spinner mid-gesture.
  @State private var hasLoadedOnce = false
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
      if !hasLoadedOnce {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if loadFailed {
        // An explicit button rather than the pull the copy used to name: this branch is a bare
        // `ContentUnavailableView` with nothing scrollable beneath it, so the `.refreshable` below
        // has no descendant to attach to and the gesture the sentence described did not exist.
        ContentUnavailableView {
          Label("Could not read this workout", systemImage: "exclamationmark.triangle")
        } description: {
          Text("Your logged sets are safe.")
        } actions: {
          Button("Try again") { Task { await load() } }
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
    // Painted across every branch, matching `ProgressionBrowserScreen`. `SessionDetailView` fills
    // itself with `ground`, so leaving the spinner and the error state unpainted showed the system
    // background for as long as they were up and then jumped.
    .background(Tokens.Color.ground)
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
      // Gated on there being a working set, not merely a set. `plan(for:)` filters to
      // `countsAsWorkingSet`, so an all-warm-up or all-drop workout produced an empty plan, and
      // the root's `!plan.isEmpty` guard then dropped it -- the spinner flickered and nothing
      // happened. An absent control is this app's own idiom for "this cannot act".
      if onRepeat != nil, sets.contains(where: { $0.kind.countsAsWorkingSet }) {
        ToolbarItem(placement: .primaryAction) {
          Button(action: repeatWorkout) {
            if isRepeating {
              ProgressView()
            } else {
              Label("Do it again", systemImage: "arrow.clockwise")
            }
          }
          .disabled(isRepeating)
          .accessibilityLabel(isRepeating ? "Preparing workout" : "Do it again")
        }
      }
    }
    .task { await load() }
    .refreshable { await load() }
    .alert("Could not prepare that workout", isPresented: $repeatFailed) {
      Button("OK", role: .cancel) {}
    } message: {
      Text("Your history is unchanged. Try again from this workout.")
    }
  }

  private func load() async {
    isLoading = true
    let store = store
    let sessionID = row.id
    let result = await readOffMain { (try store.sets(in: sessionID), try store.notes(for: sessionID)) }
    guard !Task.isCancelled else { return }
    switch result {
    case .success(let loaded):
      sets = loaded.0.map {
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
      notes = loaded.1
      loadFailed = false
    case .failure:
      sets = []
      notes = ""
      loadFailed = true
    }
    isLoading = false
    hasLoadedOnce = true
  }

  private func repeatWorkout() {
    guard let onRepeat else { return }
    isRepeating = true
    repeatFailed = false
    let store = store
    let sessionID = row.id
    Task {
      let result = await readOffMain { try store.plan(for: sessionID) }
      guard !Task.isCancelled else { return }
      isRepeating = false
      switch result {
      case .success(let plan):
        onRepeat(plan)
      case .failure:
        // The old `try? ?? []` path invoked the action with an empty plan and made a failed read
        // look like a successful tap that opened an empty workout.
        repeatFailed = true
      }
    }
  }
}
