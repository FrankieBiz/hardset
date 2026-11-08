import HardsetCore
import HardsetStore
import HardsetUI
import SwiftUI

/// Past workouts, wired.
///
/// Draws its own header in every state, because the History tab hides the stock navigation bar.
/// Until the first read finishes it says it is reading rather than claiming there are no workouts:
/// "No workouts yet" for the instant before the list arrives would be a small lie.
@MainActor
public struct HistoryScreen: View {
  /// Owns the read. A newer request cancels an older one, and a cancelled or stale completion
  /// never replaces what is on screen.
  @State private var snapshot = SnapshotLoader<[HistoryRow]>()

  @State private var selectedSession: ReceiptSelection?
  private let receipts: ReceiptStore?
  private let store: HistoryStore
  private let unit: WeightUnit

  private static let title = "History"
  /// How many sessions the list reads. Named so the header can say when it is showing the newest
  /// of more, rather than calling fifty of many "50 workouts".
  private static let limit = 50

  public init(store: HistoryStore, unit: WeightUnit, receipts: ReceiptStore? = nil) {
    self.receipts = receipts
    self.store = store
    self.unit = unit
  }

  public var body: some View {
    Group {
      if snapshot.loadFailed {
        // Scrollable so the pull-to-refresh the message promises actually works.
        ScrollView {
          VStack(alignment: .leading, spacing: Tokens.Spacing.section) {
            ScreenHeader(Self.title)
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
      } else if let rows = snapshot.value {
        HistoryView(
          rows: rows,
          unit: unit,
          title: Self.title,
          subtitle: rows.count >= Self.limit ? "Latest \(Self.limit) workouts, newest first" : nil,
          onSelect: receipts == nil ? nil : { selectedSession = ReceiptSelection(id: $0.id) }
        )
      } else {
        VStack(alignment: .leading, spacing: 0) {
          ScreenHeader(Self.title)
          HardsetLoadingState("Reading your history…")
        }
        .background(Tokens.Color.background)
      }
    }
    .task { await load() }
    .refreshable { await load() }
    .sheet(item: $selectedSession) { id in
      if let receipts { WorkoutReceiptScreen(sessionID: id.id, store: receipts, unit: unit) }
    }
  }

  private func load() async {
    let store = store
    let limit = Self.limit
    await snapshot.load { @MainActor in
      let summaries = try await store.loadRecentSessions(limit: limit)
      return summaries.map { summary in
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
    }
  }
}

private nonisolated struct ReceiptSelection: Identifiable { let id: SessionID }
