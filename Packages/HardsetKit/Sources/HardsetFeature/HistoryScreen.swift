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

  private let store: HistoryStore
  private let unit: WeightUnit
  private let onRepeat: ((SessionID) -> Void)?

  /// - Parameter onRepeat: Starts a workout from a past one. Offered only in its row's menu, and
  ///   run only when the lifter picks it. Passing `nil` hides the action, which is how a workout
  ///   in progress keeps it from replacing the session.
  public init(store: HistoryStore, unit: WeightUnit, onRepeat: ((SessionID) -> Void)? = nil) {
    self.store = store
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
          // The view reports the row; the root starts from the session's id.
          onRepeat: onRepeat.map { repeatSession in { (row: HistoryRow) in repeatSession(row.id) } }
        )
      }
    }
    .task { load() }
    .refreshable { load() }
  }

  private func load() {
    do {
      rows = try store.recentSessions().map { summary in
        HistoryRow(
          id: summary.id,
          title: summary.title,
          date: summary.timeline.startedAt,
          duration: summary.timeline.duration,
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
