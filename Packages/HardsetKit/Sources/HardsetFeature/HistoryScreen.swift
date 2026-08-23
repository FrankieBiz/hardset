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

  public init(store: HistoryStore, unit: WeightUnit) {
    self.store = store
    self.unit = unit
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
        HistoryView(rows: rows, unit: unit) { opened = $0 }
      }
    }
    .task { load() }
    .refreshable { load() }
    .navigationDestination(item: $opened) { row in
      SessionDetailScreen(row: row, store: store, unit: unit)
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
