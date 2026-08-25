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
  /// How many workouts are currently read. Raised a page at a time by the footer.
  ///
  /// Paged rather than unbounded: a lifter with years of history should not pay to render all of
  /// it to see last Tuesday. Paged rather than *capped*, which is what it was — the cap was
  /// invisible, so the fiftieth workout was simply the last one that existed as far as the app
  /// was concerned.
  @State private var limit = Self.pageSize

  static let pageSize = 50

  private let store: HistoryStore
  private let unit: WeightUnit
  private let onRepeat: (([RepeatableExercise]) -> Void)?
  /// Passed through so a movement's heading in the detail can open its load history.
  private let progression: ProgressionStore?

  public init(
    store: HistoryStore,
    unit: WeightUnit,
    onRepeat: (([RepeatableExercise]) -> Void)? = nil,
    progression: ProgressionStore? = nil
  ) {
    self.store = store
    self.unit = unit
    self.onRepeat = onRepeat
    self.progression = progression
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
          onDelete: delete,
          // Offered only when the last read filled the page, which is the one signal that there
          // may be more. Nil hides it, so no button genuinely means nothing older exists.
          onLoadMore: loadMoreHandler
        )
      }
    }
    .task { load() }
    .refreshable { load() }
    .navigationDestination(item: $opened) { row in
      SessionDetailScreen(
        row: row, store: store, unit: unit, onRepeat: onRepeat, progression: progression
      )
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

  /// `nil` once a read comes back short of the page size, which means the end was reached.
  ///
  /// Spelled out rather than written as a ternary at the call site: a `cond ? method : nil` with a
  /// method reference defeats the type checker here and produces an unattributed
  /// "failed to produce diagnostic" error.
  private var loadMoreHandler: (() -> Void)? {
    rows.count == limit ? { loadMore() } : nil
  }

  /// Reads one more page and re-renders.
  private func loadMore() {
    limit += Self.pageSize
    load()
  }

  private func load() {
    do {
      rows = try store.recentSessions(limit: limit).map { summary in
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
