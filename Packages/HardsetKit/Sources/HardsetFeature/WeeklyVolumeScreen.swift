import HardsetCore
import HardsetStore
import HardsetUI
import SwiftUI

/// Sets per muscle for the last seven days, wired.
///
/// Loads once per appearance rather than observing the database. The report is a snapshot of a
/// window, so a figure that changed while being read would be describing two different windows at
/// once — and there is no live-updating requirement here that would justify the complexity.
@MainActor
public struct WeeklyVolumeScreen: View {
  @State private var report: MuscleVolumeReport?
  /// Why the last read failed, in the user's words. Kept as the message rather than a flag so the
  /// screen cannot show copy that was not written for this failure.
  @State private var loadError: String?
  @State private var isShowingMethodology = false

  private let store: VolumeStore
  private let now: () -> Date

  public init(store: VolumeStore, now: @escaping () -> Date = { Date() }) {
    self.store = store
    self.now = now
  }

  public var body: some View {
    Group {
      if let report {
        VolumeReportView(
          report: report,
          // Tokens the catalogue cannot train yet are content debt, not the user's coverage gap.
          excludedFromGaps: ExerciseCatalog.unauthoredDirectTokens,
          onExplainCounting: { isShowingMethodology = true }
        )
      } else if let loadError {
        // Says what is wrong and what is not. Logged sets are safe either way, and saying so is
        // the difference between an error and a scare. "Try again" is a button because a pull to
        // refresh cannot fire here: there is no scroll view to pull.
        ContentUnavailableView {
          Label("Volume unavailable", systemImage: "exclamationmark.triangle")
        } description: {
          Text(loadError)
        } actions: {
          Button("Try again") { load() }
        }
      } else {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(Tokens.Color.background)
      }
    }
    .task { load() }
    .refreshable { load() }
    .sheet(isPresented: $isShowingMethodology) {
      // Generated from the same value the counting uses, so the disclosure cannot drift from the
      // arithmetic. The certainty comes from the report too: a fixed "Moderate" overstated every
      // muscle the evidence does not model, and nil (nothing credited) hides the badge.
      MethodologySheet(source: SetCounting.source, certainty: report?.highestCertainty)
    }
  }

  private func load() {
    do {
      report = try store.rollingWeek(endingAt: now())
      loadError = nil
    } catch {
      report = nil
      loadError = FailureCopy.message(for: error, during: .loadVolume)
    }
  }
}
