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
  @Environment(\.scenePhase) private var scenePhase

  private let receipts: ReceiptStore?
  private let store: HistoryStore
  private let unit: WeightUnit
  private let progression: ProgressionStore?
  private let onHistoryChanged: (() -> Void)?
  private let onShowSettings: (() -> Void)?
  /// Changes when saved history changed somewhere this screen cannot see, such as an import in
  /// Settings presented over this tab. Each change re-reads, keeping the current list on screen.
  private let dataRevision: Int

  private static let title = "History"
  private static let pageSize = 50

  /// - Parameters:
  ///   - progression: Opens each movement's load history from a receipt. Defaults to the receipt
  ///     store's own reader over the same database.
  ///   - onHistoryChanged: Called after a workout or set was deleted, so other screens showing
  ///     history, such as the start screen's last workout, can re-read.
  ///   - onShowSettings: Draws the Settings button in the header, as the Train tab does.
  ///   - dataRevision: Bumped by the caller after an outside change to saved workouts.
  public init(
    store: HistoryStore,
    unit: WeightUnit,
    receipts: ReceiptStore? = nil,
    progression: ProgressionStore? = nil,
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
        .background(Tokens.Color.background)
      } else if let listing = snapshot.value {
        HistoryView(
          rows: listing.rows,
          unit: unit,
          title: Self.title,
          subtitle: Self.subtitle(listing),
          onSelect: receipts == nil ? nil : { selectedSession = ReceiptSelection(id: $0.id) },
          onShowOlder: listing.hasMore ? { limit = listing.rows.count + Self.pageSize } : nil,
          isLoadingOlder: listing.limit < limit,
          onDelete: receipts == nil ? nil : { pendingDeletion = $0 },
          onShowSettings: onShowSettings
        )
      } else {
        VStack(alignment: .leading, spacing: 0) {
          header
          HardsetLoadingState("Reading your history…")
        }
        .background(Tokens.Color.background)
      }
    }
    // Keyed on the page size and the reload token, so asking for older workouts, a correction and
    // a return to the foreground each re-read, and a superseded read is cancelled.
    .task(id: LoadKey(limit: limit, token: reloadToken, revision: dataRevision)) { await load() }
    .refreshable { await load() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { reloadToken &+= 1 }
    }
    .sheet(item: $selectedSession, onDismiss: { receiptDismissed() }) { id in
      if let receipts {
        WorkoutReceiptScreen(
          sessionID: id.id, store: receipts, unit: unit, progression: progression,
          onChanged: { receiptChanged = true }
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
        HeaderIconButton(systemImage: "gearshape", accessibilityLabel: "Settings", action: onShowSettings)
      }
    }
  }

  /// Says when the list is a page of more, and how many more. `nil` lets the list state its own
  /// count when it holds everything.
  private static func subtitle(_ listing: HistoryListing) -> String? {
    guard listing.hasMore else { return nil }
    return "Latest \(listing.rows.count) of \(listing.totalCount) workouts, newest first"
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
    await snapshot.load { @MainActor in
      let page = try await store.loadHistory(limit: limit)
      let rows = page.sessions.map { summary in
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
      return HistoryListing(rows: rows, totalCount: page.totalCount, limit: limit)
    }
  }
}

private nonisolated struct ReceiptSelection: Identifiable { let id: SessionID }

/// One read of the list: the rows, how many finished workouts exist, and the page size asked for.
private nonisolated struct HistoryListing: Sendable {
  let rows: [HistoryRow]
  let totalCount: Int
  let limit: Int
  var hasMore: Bool { rows.count < totalCount }
}

private nonisolated struct LoadKey: Hashable, Sendable {
  let limit: Int
  let token: Int
  let revision: Int
}
