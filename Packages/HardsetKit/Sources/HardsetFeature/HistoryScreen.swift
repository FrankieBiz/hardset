import HardsetCore
import HardsetStore
import HardsetUI
import SwiftUI

/// Past workouts, wired.
@MainActor
public struct HistoryScreen: View {
  @State private var rows: [HistoryRow] = []
  /// Why the last read failed, in the user's words. Kept as the message rather than a flag so the
  /// screen cannot show copy that was not written for this failure.
  @State private var loadError: String?
  /// The session whose detail is open. Setting it pushes the screen; the read happens there.
  @State private var openedSession: SessionID?
  @State private var detail: SessionDetail?
  @State private var detailError: String?
  /// The session `detailError` belongs to, so another session never shows it for a frame.
  @State private var detailErrorSession: SessionID?
  @State private var progressTarget: ProgressTarget?

  private struct ProgressTarget: Hashable {
    let id: ExerciseID
    let name: String
  }

  private let store: HistoryStore
  private let details: SessionDetailStore
  private let progression: ProgressionStore
  private let unit: WeightUnit
  private let onRepeat: ((SessionID) -> Void)?

  /// - Parameter onRepeat: Starts a workout from a past one. Offered only in its row's menu, and
  ///   run only when the lifter picks it. Passing `nil` hides the action, which is how a workout
  ///   in progress keeps it from replacing the session.
  public init(
    store: HistoryStore,
    details: SessionDetailStore,
    progression: ProgressionStore,
    unit: WeightUnit,
    onRepeat: ((SessionID) -> Void)? = nil
  ) {
    self.store = store
    self.details = details
    self.progression = progression
    self.unit = unit
    self.onRepeat = onRepeat
  }

  public var body: some View {
    Group {
      if let loadError {
        // "Try again" is a button because a pull to refresh cannot fire here: there is no scroll
        // view to pull.
        ContentUnavailableView {
          Label("History unavailable", systemImage: "exclamationmark.triangle")
        } description: {
          Text(loadError)
        } actions: {
          Button("Try again") { load() }
        }
      } else {
        HistoryView(
          rows: rows,
          unit: unit,
          onSelect: { openedSession = $0.id },
          // The view reports the row; the root starts from the session's id.
          onRepeat: onRepeat.map { repeatSession in { (row: HistoryRow) in repeatSession(row.id) } }
        )
      }
    }
    .task { load() }
    .refreshable { load() }
    .navigationDestination(item: $openedSession) { id in detailScreen(id) }
  }

  @ViewBuilder private func detailScreen(_ id: SessionID) -> some View {
    Group {
      if let detail, detail.summary.sessionID == id {
        SessionDetailView(
          detail: detail,
          unit: unit,
          onShowProgress: { exerciseID, name in
            progressTarget = ProgressTarget(id: exerciseID, name: name)
          }
        )
      } else if let detailError, detailErrorSession == id {
        ContentUnavailableView {
          Label("Couldn't open this workout", systemImage: "exclamationmark.circle")
        } description: {
          Text(detailError)
        } actions: {
          Button("Try again") { loadDetail(id, retry: true) }
        }
      } else {
        ProgressView()
          .accessibilityLabel("Loading workout")
      }
    }
    .navigationTitle("Workout")
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
    // Read here, once per opened session, never in a body.
    .task(id: id) { loadDetail(id) }
    .navigationDestination(item: $progressTarget) { target in
      ExerciseProgressScreen(
        store: progression, exerciseID: target.id, exerciseName: target.name, unit: unit)
    }
  }

  /// Reads the session unless it is already loaded. Popping the load-history screen re-fires the
  /// task; reloading then would swap the list for a spinner and lose its scroll position.
  /// `retry` is "Try again": it clears the failure and reads again.
  private func loadDetail(_ id: SessionID, retry: Bool = false) {
    if !retry, detail?.summary.sessionID == id { return }
    // A different session, or a retry: nothing of the previous one may show while this loads.
    detail = nil
    detailError = nil
    detailErrorSession = nil
    do {
      detail = try details.detail(for: id)
    } catch {
      detailError = FailureCopy.message(for: error, during: .loadHistory)
      detailErrorSession = id
    }
  }

  private func load() {
    do {
      rows = try store.recentSessions().map { summary in
        HistoryRow(
          id: summary.id,
          title: summary.title,
          date: summary.timeline.startedAt,
          duration: summary.timeline.knownLength,
          exerciseNames: summary.exerciseNames,
          volume: summary.volume,
          hasImplausibleDuration: summary.hasImplausibleDuration
        )
      }
      loadError = nil
    } catch {
      rows = []
      loadError = FailureCopy.message(for: error, during: .loadHistory)
    }
  }
}
