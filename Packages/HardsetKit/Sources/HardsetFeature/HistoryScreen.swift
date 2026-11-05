import HardsetCore
import HardsetStore
import HardsetUI
import SwiftUI

/// Past workouts, wired.
@MainActor
public struct HistoryScreen: View {
  @State private var rows: [HistoryRow] = []
  @State private var loadFailed = false

  private let store: HistoryStore
  private let unit: WeightUnit

  public init(store: HistoryStore, unit: WeightUnit) {
    self.store = store
    self.unit = unit
  }

  public var body: some View {
    Group {
      if loadFailed {
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
      } else {
        HistoryView(rows: rows, unit: unit)
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
      loadFailed = false
    } catch {
      rows = []
      loadFailed = true
    }
  }
}
