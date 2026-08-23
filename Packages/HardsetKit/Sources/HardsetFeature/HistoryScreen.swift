import HardsetCore
import HardsetStore
import HardsetUI
import SwiftUI

/// Past workouts, wired.
@MainActor
public struct HistoryScreen: View {
  @State private var rows: [HistoryRow] = []
  @State private var loadFailed = false
  /// The workout being read. History was a dead end until this existed: `HistoryView` has always
  /// taken an `onSelect` and nothing passed one, so every row was a disabled button.
  @State private var opened: HistoryRow?

  private let store: HistoryStore
  private let unit: WeightUnit
  private let onRepeat: (([RepeatableExercise]) -> Void)?

  public init(
    store: HistoryStore,
    unit: WeightUnit,
    onRepeat: (([RepeatableExercise]) -> Void)? = nil
  ) {
    self.store = store
    self.unit = unit
    self.onRepeat = onRepeat
  }

  public var body: some View {
    Group {
      if loadFailed {
        ContentUnavailableView {
          Label("Could not read your history", systemImage: "exclamationmark.triangle")
        } description: {
          Text("Your logged sets are safe. Pull down to try again.")
        }
      } else {
        HistoryView(
          rows: rows,
          unit: unit,
          onSelect: { opened = $0 },
          onDelete: delete
        )
      }
    }
    .task { load() }
    .refreshable { load() }
    .navigationDestination(item: $opened) { row in
      SessionDetailScreen(row: row, store: store, unit: unit, onRepeat: onRepeat)
    }
  }

  /// Discards a workout and everything in it.
  ///
  /// No confirmation dialog: the swipe is already deliberate, and iOS treats a destructive swipe
  /// action as its own confirmation. Reloads afterwards so the list cannot show a row whose rows
  /// are gone.
  private func delete(_ row: HistoryRow) {
    do {
      try store.deleteSession(row.id)
      load()
    } catch {
      // Stated rather than swallowed: a delete that failed must not leave the row looking gone.
      loadFailed = true
    }
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
      loadFailed = false
    } catch {
      rows = []
      loadFailed = true
    }
  }
}
