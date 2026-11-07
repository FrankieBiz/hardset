import HardsetCore
import HardsetStore
import HardsetUI
import SwiftUI

/// Past workouts, wired.
@MainActor
public struct HistoryScreen: View {
  @State private var snapshot = SnapshotLoader<[HistoryRow]>()

  private let store: HistoryStore
  private let unit: WeightUnit

  public init(store: HistoryStore, unit: WeightUnit) {
    self.store = store
    self.unit = unit
  }

  public var body: some View {
    Group {
      if snapshot.loadFailed {
        VStack {
          Spacer()
          HardsetEmptyState(
            title: "Could not read your history",
            detail: "Your logged sets are safe. Pull down to try again.",
            systemImage: "exclamationmark.triangle"
          )
          Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.Color.background)
      } else if let rows = snapshot.value {
        HistoryView(rows: rows, unit: unit)
      } else {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(Tokens.Color.background)
      }
    }
    .task { await load() }
    .refreshable { await load() }
  }

  private func load() async {
    let store = store
    await snapshot.load { @MainActor in
      let summaries = try await store.loadRecentSessions()
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
