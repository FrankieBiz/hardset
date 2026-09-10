import HardsetCore
import HardsetStore
import HardsetUI
import SwiftUI

/// Past workouts, wired.
@MainActor
public struct HistoryScreen: View {
  @State private var rows: [HistoryRow] = []
  @State private var isLoading = true
  @State private var loadFailed = false
  /// A delete that did not happen, stated over the intact list rather than in place of it.
  ///
  /// This used to raise `loadFailed`, which is the flag the whole body branches on -- so a failed
  /// delete threw a perfectly good list off screen and replaced it with "Could not read your
  /// history", copy about a read that had not failed. Nothing cleared it but a later successful
  /// load, so the screen stayed on that message.
  @State private var deleteFailed = false
  /// Counts committed deletes so `.sensoryFeedback` has something to trigger on.
  @State private var deleteCount = 0
  /// True once any read has returned, successful or not.
  ///
  /// The spinner is gated on this rather than on `isLoading` because an empty database keeps
  /// `rows` empty forever: a pull-to-refresh on the empty state flipped the branch mid-gesture and
  /// took the pull indicator with it. A local SQLite read has no latency worth advertising twice.
  @State private var hasLoadedOnce = false
  /// Whether the last read saw a workout older than the page it returned.
  ///
  /// Read as `limit + 1` and trimmed, because `rows.count == limit` is also true at exactly 50,
  /// 100 or 150 workouts -- so the footer appeared, raised the limit, returned the same rows and
  /// vanished again. The absence of the footer is supposed to mean nothing older exists; this is
  /// what makes its presence mean the converse.
  @State private var hasMore = false
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
      if !hasLoadedOnce {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if loadFailed {
        // An explicit button, not the pull gesture the copy used to name: this branch renders a
        // bare `ContentUnavailableView` with nothing scrollable under it, so `.refreshable` had no
        // descendant to attach to and the only recovery was leaving the screen and coming back.
        ContentUnavailableView {
          Label("Could not read your history", systemImage: "exclamationmark.triangle")
        } description: {
          Text("Your logged sets are safe.")
        } actions: {
          Button("Try again") { Task { await load() } }
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
    .task { await load() }
    .refreshable { await load() }
    // `.warning` per UI-GUIDELINES §5.8's "Destructive confirmed" row, which was marked as having
    // no host until workout deletion shipped. Success only: a haptic marks a committed change, and
    // the failure path states itself in the alert below.
    .sensoryFeedback(.warning, trigger: deleteCount)
    .alert("Could not delete that workout", isPresented: $deleteFailed) {
      Button("OK", role: .cancel) {}
    } message: {
      Text("It is still in your history. Nothing was removed.")
    }
    .navigationDestination(item: $opened) { row in
      SessionDetailScreen(
        row: row, store: store, unit: unit, onRepeat: onRepeat, progression: progression
      )
    }
    .toolbar {
      if let progression {
        ToolbarItem(placement: .primaryAction) {
          NavigationLink {
            ProgressionBrowserScreen(store: progression, unit: unit)
          } label: {
            Label("Browse progress", systemImage: "chart.line.uptrend.xyaxis")
          }
        }
      }
    }
  }

  /// Discards a workout and everything in it.
  ///
  /// No confirmation dialog: the swipe reveals a destructive button that has to be seen and
  /// tapped, and iOS treats that as its own confirmation. That was only ever true once
  /// `HistoryView` passed `allowsFullSwipe: false` -- the default fires the button without
  /// drawing it, which is precisely what this comment used to assume could not happen.
  /// Reloads afterwards so the list cannot show a row whose rows are gone.
  private func delete(_ row: HistoryRow) {
    let store = store
    let sessionID = row.id
    Task {
      let result = await readOffMain {
        try store.deleteSession(sessionID)
      }
      guard !Task.isCancelled else { return }
      switch result {
      case .success:
        deleteCount += 1
        await load()
      case .failure:
        // Stated rather than swallowed: a delete that failed must not leave the row looking gone.
        // An alert over the intact list, because the list underneath is what makes the message
        // ("it is still in your history") a true statement rather than a second claim to check.
        deleteFailed = true
      }
    }
  }

  /// `nil` once a read proves there is nothing older, which means the end was reached.
  ///
  /// Spelled out rather than written as a ternary at the call site: a `cond ? method : nil` with a
  /// method reference defeats the type checker here and produces an unattributed
  /// "failed to produce diagnostic" error.
  private var loadMoreHandler: (() -> Void)? {
    !isLoading && hasMore ? { loadMore() } : nil
  }

  /// Reads one more page and re-renders.
  private func loadMore() {
    limit += Self.pageSize
    Task { await load() }
  }

  private func load() async {
    isLoading = true
    let store = store
    let limit = limit
    // One row past the page, then trimmed. The extra row is the only thing that distinguishes
    // "the page is full" from "there is more", and conflating the two put a "Show older workouts"
    // button on screen at exactly 50, 100 or 150 workouts that did nothing but remove itself.
    let result = await readOffMain { try store.recentSessions(limit: limit + 1) }
    guard !Task.isCancelled else { return }
    switch result {
    case .success(let summaries):
      hasMore = summaries.count > limit
      rows = summaries.prefix(limit).map { summary in
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
    case .failure:
      rows = []
      hasMore = false
      loadFailed = true
    }
    isLoading = false
    hasLoadedOnce = true
  }
}
