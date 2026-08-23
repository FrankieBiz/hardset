import HardsetCore
import HardsetStore
import HardsetUI
import SwiftUI

/// One past workout, wired.
///
/// Maps the store's rows onto the view's, which is the boundary that keeps `HardsetUI` free of any
/// storage dependency.
@MainActor
public struct SessionDetailScreen: View {
  private let row: HistoryRow
  private let store: HistoryStore
  private let unit: WeightUnit

  @State private var sets: [LoggedSetRow] = []
  @State private var loadFailed = false

  public init(row: HistoryRow, store: HistoryStore, unit: WeightUnit) {
    self.row = row
    self.store = store
    self.unit = unit
  }

  public var body: some View {
    Group {
      if loadFailed {
        ContentUnavailableView {
          Label("Could not read this workout", systemImage: "exclamationmark.triangle")
        } description: {
          Text("Your logged sets are safe. Pull down to try again.")
        }
      } else {
        SessionDetailView(
          title: row.title,
          date: row.date,
          duration: row.duration,
          hasImplausibleDuration: row.hasImplausibleDuration,
          sets: sets,
          unit: unit
        )
      }
    }
    .navigationTitle(row.title)
    .task { load() }
    .refreshable { load() }
  }

  private func load() {
    do {
      sets = try store.sets(in: row.id).map {
        LoggedSetRow(
          id: $0.id.rawValue,
          exerciseName: $0.exerciseName,
          isBodyweight: $0.modality == .bodyweight,
          machineName: $0.machineName,
          weightKg: $0.weightKg,
          reps: $0.reps,
          rpe: $0.rpe,
          isWarmup: $0.isWarmup
        )
      }
      loadFailed = false
    } catch {
      sets = []
      loadFailed = true
    }
  }
}
