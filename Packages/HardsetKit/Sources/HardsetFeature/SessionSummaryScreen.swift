import HardsetCore
import HardsetStore
import HardsetUI
import SwiftUI

/// The summary, with its muscle breakdown loaded.
///
/// The breakdown is read once, here, rather than passed down from the finishing callback: doing IO
/// inside `finish()` would put a query on the path that closes a workout, and a failure there would
/// have to either be swallowed or block the finish. Loading it after the screen exists means a
/// storage failure costs the breakdown and nothing else.
///
/// It reuses `VolumeStore.report(from:to:)` rather than a session-specific query. A session *is* a
/// date range, the analyzer is already tested, and a second way to count sets per muscle is a
/// second thing that can disagree with the Volume tab.
@MainActor
public struct SessionSummaryScreen: View {
  private let outcome: SessionOutcome
  private let timeline: SessionTimeline
  private let sessionID: SessionID
  private let store: VolumeStore
  private let unit: WeightUnit
  private let onDone: () -> Void

  @State private var muscles: MuscleVolumeReport?

  public init(
    outcome: SessionOutcome,
    timeline: SessionTimeline,
    sessionID: SessionID,
    store: VolumeStore,
    unit: WeightUnit,
    onDone: @escaping () -> Void
  ) {
    self.outcome = outcome
    self.timeline = timeline
    self.sessionID = sessionID
    self.store = store
    self.unit = unit
    self.onDone = onDone
  }

  public var body: some View {
    SessionSummaryView(outcome: outcome, muscles: muscles, unit: unit, onDone: onDone)
      .task {
        // Scoped by session, not by its time span. A window of `startedAt..<finishedAt` is half-open
        // at the top, so a set logged in the same instant the workout was finished fell outside its
        // own summary -- and the window could not tell whose sets it was counting either.
        //
        let store = store
        let sessionID = sessionID
        let result = await readOffMain { try store.report(for: sessionID) }
        guard !Task.isCancelled else { return }
        // The breakdown is additive and the view renders its absence honestly. Finishing the
        // workout has already succeeded, so a report read can never hold that transition hostage.
        if case .success(let report) = result { muscles = report }
      }
  }
}
