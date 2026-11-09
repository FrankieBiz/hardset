import HardsetCore
import HardsetStore
import HardsetUI
import SwiftUI

/// Choose a real workout, inspect what will carry forward, then explicitly start.
struct RepeatWorkoutScreen: View {
  let history: HistoryStore
  let store: RepeatWorkoutStore
  let gymID: GymID?
  let gymName: String?
  let onStart: (RepeatWorkout) throws -> Void
  @State private var sessions = SnapshotLoader<[SessionSummary]>()
  @State private var preview = SnapshotLoader<RepeatWorkout>()
  @State private var selected: SessionID?
  @State private var startFailed = false
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: Tokens.Spacing.section) {
          if let selected {
            previewContent
              .task(id: selected) {
                await preview.load { try await store.load(selected, at: gymID) }
              }
          } else {
            choices
          }
        }
        .padding(Tokens.Spacing.loose)
      }
      .background(Tokens.Color.background)
      .hardsetNavigationTitle("Repeat a workout")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          if selected != nil {
            Button("Back") { selected = nil; startFailed = false; preview = SnapshotLoader() }
          } else {
            Button("Cancel") { dismiss() }
          }
        }
      }
      .task { await loadSessions() }
    }
  }

  @ViewBuilder private var choices: some View {
    Text("Use your own training as a starting point. Review the movements and equipment before starting.")
      .font(Tokens.Text.provenance).foregroundStyle(Tokens.Color.textSecondary)
    if let rows = sessions.value {
      if rows.isEmpty {
        Text("Finish a workout first. It will appear here for next time.")
          .font(Tokens.Text.label).foregroundStyle(Tokens.Color.textPrimary)
      } else {
        Text("Latest 50 completed workouts")
          .font(Tokens.Text.caption).foregroundStyle(Tokens.Color.textSecondary)
        ForEach(rows) { row in
          Button { selected = row.id } label: {
            VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
              Text(row.title.isEmpty ? "Workout" : row.title).font(Tokens.Text.headline)
              Text(row.timeline.startedAt.formatted(date: .abbreviated, time: .omitted))
                .font(Tokens.Text.caption)
              Text(row.exerciseNames.joined(separator: ", "))
                .font(Tokens.Text.provenance)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
          .buttonStyle(HardsetButtonStyle(.secondary))
        }
      }
    } else if sessions.loadFailed {
      Text("Could not read your workouts.").foregroundStyle(Tokens.Color.error)
      Button("Try again") { Task { await loadSessions() } }
        .buttonStyle(HardsetButtonStyle(.secondary))
    } else { HardsetLoadingState("Reading your workouts…") }
  }

  @ViewBuilder private var previewContent: some View {
    if let workout = preview.value {
      Text(workout.title.isEmpty ? "Your next workout" : workout.title)
        .font(Tokens.Text.title).foregroundStyle(Tokens.Color.textPrimary)
      Text("\(workout.exercises.count) movements · \(workout.workingSets) working sets")
        .font(Tokens.Text.headline).foregroundStyle(Tokens.Color.textPrimary)
      Text(gymName.map { "Training at \($0)" } ?? "No gym selected")
        .font(Tokens.Text.provenance).foregroundStyle(Tokens.Color.textSecondary)
      // Saved set identifiers keep preview rows stable across refreshes.
      ForEach(workout.entries) { entry in
        let exercise = entry.exercise
        VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
          Text(exercise.exerciseName).font(Tokens.Text.headline)
          Text("\(exercise.plannedSets ?? 0) working sets · \(exercise.machineName ?? "Choose equipment during workout")")
            .font(Tokens.Text.provenance).foregroundStyle(Tokens.Color.textSecondary)
        }
        .foregroundStyle(Tokens.Color.textPrimary)
        Divider()
      }
      Text("Copies completed working-set counts. Warm-ups are yours to add. Loads come from your latest history on the same recorded machine; unknown equipment starts blank. Nothing is logged until you log it.")
        .font(Tokens.Text.provenance).foregroundStyle(Tokens.Color.textSecondary)
      if workout.omittedMovements > 0 {
        HardsetBanner(.caveat, message: "\(workout.omittedMovements) archived or unavailable movements were left out.")
      }
      if startFailed {
        HardsetBanner(.error, message: "Could not start this workout. Your history is unchanged. Try again.")
      }
      Button {
        do { try onStart(workout); dismiss() }
        catch { startFailed = true }
      } label: {
        Label("Start this workout", systemImage: "play.fill")
      }
      .buttonStyle(HardsetButtonStyle(.primary, size: .logger))
    } else if preview.loadFailed {
      Text("This workout could not be prepared. It may have no available working sets.")
        .font(Tokens.Text.label).foregroundStyle(Tokens.Color.textSecondary)
      Button("Try again") {
        guard let selected else { return }
        Task { await preview.load { try await store.load(selected, at: gymID) } }
      }.buttonStyle(HardsetButtonStyle(.secondary))
    } else { HardsetLoadingState("Preparing your workout…") }
  }

  private func loadSessions() async {
    await sessions.load { try await history.loadRecentSessions(limit: 50) }
  }
}
