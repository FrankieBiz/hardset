import HardsetCore
import HardsetStore
import HardsetUI
import SwiftUI

/// "How this workout has gone": the recent finished sessions of one saved workout, read once when
/// the sheet opens.
///
/// A failed read says so and keeps the sheet open with a retry. It never draws the empty state for
/// a failure: "nothing yet" and "could not read" are different facts, and only one of them is the
/// lifter's.
public struct TemplateHistorySheet: View {
  private let templateID: TemplateID
  private let workoutName: String
  private let store: TemplateStore
  private let unit: WeightUnit
  @State private var snapshot = SnapshotLoader<TemplateHistory>()
  @Environment(\.dismiss) private var dismiss

  /// - Parameter workoutName: The saved workout's name, used as the sheet's title.
  public init(
    templateID: TemplateID, workoutName: String, store: TemplateStore, unit: WeightUnit
  ) {
    self.templateID = templateID
    self.workoutName = workoutName
    self.store = store
    self.unit = unit
  }

  public var body: some View {
    NavigationStack {
      ScrollView {
        content
      }
      .scrollBounceBehavior(.basedOnSize)
      .background(Tokens.Color.canvas)
      .hardsetNavigationTitle(workoutName)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
      .task { await load() }
    }
    .tint(Tokens.Color.plateBlue)
  }

  @ViewBuilder private var content: some View {
    if let history = snapshot.value {
      if history.sessions.isEmpty {
        HardsetEmptyState(
          title: TemplateHistoryCopy.empty,
          detail: "Finish this workout with a working set and it will appear here.",
          systemImage: "clock.arrow.circlepath",
          style: .quiet
        )
      } else {
        TemplateHistoryView(history: history, unit: unit)
      }
    } else if snapshot.loadFailed {
      HardsetEmptyState(
        title: "Could not read this workout's history",
        detail: "Your logged sets are safe. Try again.",
        systemImage: "exclamationmark.triangle",
        actionTitle: "Try again",
        actionSystemImage: "arrow.clockwise",
        style: .quiet,
        action: { Task { await load() } }
      )
    } else {
      HardsetLoadingState("Reading this workout's history…")
    }
  }

  /// One screen-open read. The retry calls the same function, so a read that succeeds only on the
  /// second attempt fills in everything the first would have.
  private func load() async {
    let store = self.store
    let id = self.templateID
    await snapshot.load { try await store.history(for: id) }
  }
}
