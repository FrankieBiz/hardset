import HardsetCore
import HardsetStore
import HardsetUI
import SwiftUI

/// Past workouts, wired.
///
/// Draws its own header in every state, because the History tab hides the stock navigation bar.
/// Until the first read finishes it says it is reading rather than claiming there are no workouts:
/// "No workouts yet" for the instant before the list arrives would be a small lie.
///
/// Reads a page of the newest workouts and says how many exist in total, with a control to read
/// older ones. A workout can be deleted from its card's context menu or from its receipt, which
/// also removes single mis-logged sets; both are confirmed first. The list re-reads after a
/// correction and whenever the app returns to the foreground.
///
/// A search field finds an old workout by movement, machine or gym. Typing waits for a pause before
/// anything is read, a newer keystroke cancels the read in flight, and the answer is the same list
/// of workouts, newest first, opening the same receipt. A search that matches nothing says so by
/// name rather than drawing an empty screen.
///
/// A calendar button opens a picker of the months that hold workouts. Choosing one starts the list at
/// that month's last workout and pages older from there, so a period three years back is two taps
/// away; "Back to latest workouts" returns to the newest. The month list is read when the picker
/// opens, not on every appearance of the screen.
@MainActor
public struct HistoryScreen: View {
  /// Owns the read. A newer request cancels an older one, and a cancelled or stale completion
  /// never replaces what is on screen.
  @State private var snapshot = SnapshotLoader<HistoryListing>()

  @State private var selectedSession: ReceiptSelection?
  /// How many sessions the list reads. Grows a page at a time when the lifter asks for older
  /// workouts, so the header can say "latest 50 of 312" rather than calling fifty of many all.
  @State private var limit = HistoryScreen.pageSize
  /// Bumped to re-read: after a correction, and when the app comes back to the foreground.
  @State private var reloadToken = 0
  @State private var receiptChanged = false
  @State private var pendingDeletion: HistoryRow?
  @State private var deletionFailed = false
  /// Owns the search read, apart from the list's, so typing never disturbs the list underneath it
  /// and clearing the field returns to it exactly as it was.
  @State private var searchSnapshot = SnapshotLoader<HistorySearchListing>()
  @State private var searchText = ""
  /// How many matches the search reads. Grows a page at a time, and starts over with each query.
  @State private var searchLimit = HistoryScreen.pageSize
  /// The words whose answer VoiceOver was last told, so a refresh or a longer page of the same
  /// matches does not announce itself again.
  @State private var announcedQuery: String?
  /// The month the list starts from, when the lifter jumped to one; `nil` starts at the newest.
  @State private var anchor: HistoryMonth?
  @State private var isChoosingMonth = false
  /// Owns the read of the months that hold workouts, so the picker shows a failure rather than an
  /// empty list, and a slow read is cancelled when the picker closes.
  @State private var monthsSnapshot = SnapshotLoader<[HistoryMonth]>()
  @Environment(\.scenePhase) private var scenePhase

  private let receipts: ReceiptStore?
  private let store: HistoryStore
  private let unit: WeightUnit
  private let progression: ProgressionStore?
  private let saveAsWorkout: SaveAsWorkoutTools?
  private let onHistoryChanged: (() -> Void)?
  private let onShowSettings: (() -> Void)?
  /// Changes when saved history changed somewhere this screen cannot see, such as an import in
  /// Settings presented over this tab. Each change re-reads, keeping the current list on screen.
  private let dataRevision: Int

  private static let title = "History"
  private static let pageSize = 50
  /// How long typing must pause before a search reads anything. Short enough to feel immediate,
  /// long enough that a word typed at speed is one read and not five.
  private static let searchPause = Duration.milliseconds(250)

  /// What was typed, without the spaces around it.
  private var query: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
  /// A search is showing once the query is long enough to search; shorter, the list is untouched.
  private var isSearching: Bool { HistoryStore.isSearchable(query) }

  /// - Parameters:
  ///   - progression: Opens each movement's load history from a receipt. Defaults to the receipt
  ///     store's own reader over the same database.
  ///   - saveAsWorkout: Offers "Save as workout" on a receipt, when present.
  ///   - onHistoryChanged: Called after a workout or set was deleted, so other screens showing
  ///     history, such as the start screen's last workout, can re-read.
  ///   - onShowSettings: Draws the Settings button in the header, as the Train tab does.
  ///   - dataRevision: Bumped by the caller after an outside change to saved workouts.
  public init(
    store: HistoryStore,
    unit: WeightUnit,
    receipts: ReceiptStore? = nil,
    progression: ProgressionStore? = nil,
    saveAsWorkout: SaveAsWorkoutTools? = nil,
    onHistoryChanged: (() -> Void)? = nil,
    onShowSettings: (() -> Void)? = nil,
    dataRevision: Int = 0
  ) {
    self.dataRevision = dataRevision
    self.receipts = receipts
    self.store = store
    self.unit = unit
    // The receipt store reads the same database, so load history works even when the caller only
    // wires receipts.
    self.progression = progression ?? receipts?.progression
    self.saveAsWorkout = saveAsWorkout
    self.onHistoryChanged = onHistoryChanged
    self.onShowSettings = onShowSettings
  }

  public var body: some View {
    Group {
      if snapshot.loadFailed {
        // Scrollable so the pull-to-refresh the message promises actually works.
        ScrollView {
          VStack(alignment: .leading, spacing: Tokens.Spacing.section) {
            header
            HardsetEmptyState(
              title: "Could not read your history",
              detail: "Your logged sets are safe. Pull down to try again.",
              systemImage: "exclamationmark.triangle"
            )
          }
          .padding(.bottom, Tokens.Spacing.block)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Tokens.Color.canvas)
      } else if let listing = snapshot.value {
        let shown = showing(listing)
        HistoryView(
          rows: shown.rows,
          unit: unit,
          title: Self.title,
          subtitle: shown.subtitle,
          search: HistorySearch(
            text: $searchText, state: shown.state,
            // A search spans all of history, so there is nowhere to jump while one is showing, and
            // nothing to jump to before a workout has been finished.
            onJumpToMonth: !isSearching && (listing.totalCount > 0 || anchor != nil)
              ? { isChoosingMonth = true } : nil,
            onBackToLatest: !isSearching && anchor != nil ? { jump(to: nil) } : nil),
          onSelect: receipts == nil ? nil : { selectedSession = ReceiptSelection(id: $0.id) },
          onShowOlder: shown.showOlder,
          isLoadingOlder: shown.isLoadingOlder,
          onDelete: receipts == nil ? nil : { pendingDeletion = $0 },
          onShowSettings: onShowSettings
        )
      } else {
        VStack(alignment: .leading, spacing: 0) {
          header
          HardsetLoadingState("Reading your history…")
        }
        .background(Tokens.Color.canvas)
      }
    }
    // Keyed on the page size and the reload token, so asking for older workouts, a correction and
    // a return to the foreground each re-read, and a superseded read is cancelled.
    .task(id: LoadKey(limit: limit, token: reloadToken, revision: dataRevision, anchor: anchor?.start)) {
      await load()
    }
    // Keyed on the words as well, so a keystroke cancels the read, or the pause, of the one before.
    .task(id: SearchKey(query: isSearching ? query : "", limit: searchLimit, token: reloadToken, revision: dataRevision)) {
      await search()
    }
    .onChange(of: query) { _, _ in searchLimit = Self.pageSize }
    .onChange(of: isSearching) { _, searching in
      if !searching { announcedQuery = nil }
    }
    .refreshable {
      await load()
      await search()
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { reloadToken &+= 1 }
    }
    .sheet(isPresented: $isChoosingMonth) {
      HistoryMonthJumpSheet(
        content: monthsContent,
        selected: anchor?.start,
        onSelect: { month in jump(to: month) },
        onCancel: { isChoosingMonth = false }
      )
      // Read each time the picker opens, so a workout finished since is in it.
      .task { await loadMonths() }
      .hardsetSheet()
    }
    .sheet(item: $selectedSession, onDismiss: { receiptDismissed() }) { id in
      if let receipts {
        WorkoutReceiptScreen(
          sessionID: id.id, store: receipts, unit: unit, progression: progression,
          saveAsWorkout: saveAsWorkout, onChanged: { receiptChanged = true }
        )
        .hardsetSheet()
      }
    }
    .confirmationDialog(
      "Delete this workout?",
      isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
      titleVisibility: .visible,
      presenting: pendingDeletion
    ) { row in
      Button("Delete workout", role: .destructive) { Task { await delete(row) } }
      Button("Cancel", role: .cancel) {}
    } message: { row in
      // With the year whenever it is not this one: years of imported history repeat every date.
      Text(HistoryView.fullDateText(row.date) + ". "
        + WorkoutReceiptScreen.workoutDeletionMessage(
          setCount: row.volume.workingSets + row.volume.warmupSets))
    }
    .alert("Could not delete this workout", isPresented: $deletionFailed) {
      Button("OK", role: .cancel) {}
    } message: {
      Text("Nothing was removed. Try again.")
    }
  }

  private var header: some View {
    ScreenHeader(Self.title) {
      if let onShowSettings {
        HeaderIconButton(
          systemImage: "gearshape", accessibilityLabel: "Settings", style: .bare,
          action: onShowSettings)
      }
    }
  }

  /// Says when the list is a page of more, and how many more. `nil` lets the list state its own
  /// count when it holds everything. A list that starts at a month says where, and that newer
  /// workouts are not on it, so it is never read as the whole history.
  private static func subtitle(_ listing: HistoryListing) -> String? {
    if let month = listing.anchor {
      return HistoryCopy.anchoredSubtitle(
        month: month.formatted(.dateTime.month(.wide).year()),
        shown: listing.rows.count, total: listing.totalCount)
    }
    guard listing.hasMore else { return nil }
    return "Latest \(listing.rows.count) of \(listing.totalCount) workouts, newest first"
  }

  /// Starts the list at `month`, or back at the newest workouts for `nil`. The newest month is the
  /// newest workouts, so choosing it starts nowhere in particular. The page size starts over, in
  /// the same change, so the list is read once.
  private func jump(to month: HistoryMonth?) {
    let newest = monthsSnapshot.value?.first?.start
    anchor = month?.start == newest ? nil : month
    limit = Self.pageSize
    isChoosingMonth = false
  }

  private var monthsContent: HistoryMonthJumpSheet.Content {
    if monthsSnapshot.loadFailed { return .failed }
    if let months = monthsSnapshot.value { return .months(months) }
    return .loading
  }

  private func loadMonths() async {
    let store = store
    let calendar = Calendar.current
    await monthsSnapshot.load { @MainActor in try await store.loadMonths(calendar: calendar) }
  }

  private func receiptDismissed() {
    guard receiptChanged else { return }
    receiptChanged = false
    reloadToken &+= 1
    onHistoryChanged?()
  }

  private func delete(_ row: HistoryRow) async {
    pendingDeletion = nil
    guard let receipts else { return }
    do {
      try await receipts.deleteSession(row.id)
    } catch ReceiptError.sessionNotFound {
      // Already gone, for example removed on another device; re-reading shows the truth.
    } catch {
      deletionFailed = true
      return
    }
    reloadToken &+= 1
    onHistoryChanged?()
  }

  private func load() async {
    let store = store
    let limit = limit
    let month = anchor
    await snapshot.load { @MainActor in
      let page = try await store.loadHistory(limit: limit, startedBefore: month?.end)
      return HistoryListing(
        rows: Self.rows(from: page), totalCount: page.totalCount, limit: limit, anchor: month?.start)
    }
    // Everything at and before the month was deleted while the list stood on it: fall back to the
    // newest workouts rather than showing "No workouts yet" over a history that has some.
    if let month, snapshot.value?.anchor == month.start, snapshot.value?.rows.isEmpty == true,
      anchor?.start == month.start
    {
      anchor = nil
      self.limit = Self.pageSize
    }
  }

  /// Reads the matches for what is typed. Does nothing until the query is long enough to search.
  private func search() async {
    let words = query
    guard HistoryStore.isSearchable(words) else { return }
    let store = store
    let limit = searchLimit
    // A new query waits for typing to pause; the next keystroke cancels this task and the pause
    // with it. Asking for more of the same matches, or re-reading after a correction, does not wait.
    if searchSnapshot.value?.query != words {
      do { try await Task.sleep(for: Self.searchPause) } catch { return }
    }
    await searchSnapshot.load { @MainActor in
      let page = try await store.searchHistory(words, limit: limit)
      return HistorySearchListing(
        query: words, rows: Self.rows(from: page), totalCount: page.totalCount, limit: limit)
    }
    announceAnswer(to: words)
  }

  /// Tells VoiceOver what a search found, once per query: the matches appear under the field, away
  /// from where focus is, so without this a lifter who cannot see the list would not know the
  /// search had answered, or that nothing matched.
  private func announceAnswer(to words: String) {
    guard !Task.isCancelled, announcedQuery != words,
      let found = searchSnapshot.value, found.query == words
    else { return }
    announcedQuery = words
    AccessibilityNotification.Announcement(
      found.rows.isEmpty
        ? HistoryCopy.noMatchTitle(for: words)
        : HistoryCopy.searchSubtitle(query: words, shown: found.rows.count, total: found.totalCount)
    ).post()
  }

  private static func rows(from page: HistoryPage) -> [HistoryRow] {
    page.sessions.map { summary in
      HistoryRow(
        id: summary.id,
        title: summary.title,
        date: summary.timeline.startedAt,
        duration: summary.timeline.duration,
        exerciseNames: summary.exerciseNames,
        volume: summary.volume,
        hasImplausibleDuration: summary.hasImplausibleDuration,
        isImported: summary.isImported
      )
    }
  }

  /// What the list shows now: the whole history, or the answer to the query being typed.
  private struct Showing {
    var rows: [HistoryRow]
    var subtitle: String?
    var state: HistorySearch.State
    var showOlder: (() -> Void)?
    var isLoadingOlder: Bool
  }

  private func showing(_ listing: HistoryListing) -> Showing {
    guard isSearching else {
      return Showing(
        rows: listing.rows, subtitle: Self.subtitle(listing), state: .idle,
        showOlder: listing.hasMore ? { limit = listing.rows.count + Self.pageSize } : nil,
        isLoadingOlder: listing.limit < limit)
    }
    if searchSnapshot.loadFailed {
      return Showing(
        rows: [], subtitle: nil, state: .failed(query), showOlder: nil, isLoadingOlder: false)
    }
    // Until the first answer arrives there are no rows to show, and the list says it is searching.
    // After that the rows stay on screen while a newer query is read, each answer naming the
    // words it answers, so a late arrival is never read as the answer to what is now typed.
    guard let found = searchSnapshot.value else {
      return Showing(
        rows: [], subtitle: nil, state: .searching(query), showOlder: nil, isLoadingOlder: false)
    }
    return Showing(
      rows: found.rows,
      subtitle: found.rows.isEmpty
        ? nil
        : HistoryCopy.searchSubtitle(
          query: found.query, shown: found.rows.count, total: found.totalCount),
      state: .answered(found.query),
      showOlder: found.hasMore ? { searchLimit = found.rows.count + Self.pageSize } : nil,
      isLoadingOlder: found.limit < searchLimit)
  }
}

private nonisolated struct ReceiptSelection: Identifiable { let id: SessionID }

/// One read of the list: the rows, how many finished workouts exist, and the page size asked for.
private nonisolated struct HistoryListing: Sendable {
  let rows: [HistoryRow]
  let totalCount: Int
  let limit: Int
  /// The start of the month the list was read from, or `nil` when it starts at the newest.
  let anchor: Date?
  var hasMore: Bool { rows.count < totalCount }
}

/// One read of a search: the words it answers, the matches shown, how many workouts matched in all,
/// and the page size asked for.
private nonisolated struct HistorySearchListing: Sendable {
  let query: String
  let rows: [HistoryRow]
  let totalCount: Int
  let limit: Int
  var hasMore: Bool { rows.count < totalCount }
}

private nonisolated struct LoadKey: Hashable, Sendable {
  let limit: Int
  let token: Int
  let revision: Int
  let anchor: Date?
}

private nonisolated struct SearchKey: Hashable, Sendable {
  let query: String
  let limit: Int
  let token: Int
  let revision: Int
}
