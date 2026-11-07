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
  @State private var rows: [HistoryRow] = []
  @State private var loadFailed = false
  @State private var hasLoaded = false

  private let store: HistoryStore
  private let unit: WeightUnit

  private static let title = "History"
  /// How many sessions the list reads. Named so the header can say when it is showing the newest
  /// of more, rather than calling fifty of many "50 workouts".
  private static let limit = 50

  public init(store: HistoryStore, unit: WeightUnit) {
    self.store = store
    self.unit = unit
  }

  public var body: some View {
    Group {
      if loadFailed {
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
      } else if hasLoaded {
        HistoryView(
          rows: rows,
          unit: unit,
          title: Self.title,
          subtitle: rows.count >= Self.limit ? "Latest \(Self.limit) workouts, newest first" : nil
        )
      } else {
        VStack(alignment: .leading, spacing: 0) {
          ScreenHeader(Self.title)
          HardsetLoadingState("Reading your history…")
        }
        .background(Tokens.Color.background)
      }
    }
    .task { load() }
    .refreshable { load() }
  }

  private func load() {
    do {
      rows = try store.recentSessions(limit: Self.limit).map { summary in
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
    hasLoaded = true
  }
}
