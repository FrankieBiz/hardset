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
  @State private var loadFailed = false
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
      } else if loadFailed {
        // Says what is wrong and what is not. Logged sets are safe either way, and saying so is
        // the difference between an error and a scare.
        ContentUnavailableView {
          Label("Could not read this week", systemImage: "exclamationmark.triangle")
        } description: {
          Text("Your logged sets are safe. Pull down to try again.")
        }
      } else {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(Tokens.Color.ground)
      }
    }
    .task { load() }
    .refreshable { load() }
    .sheet(isPresented: $isShowingMethodology) {
      // Generated from the same value the counting uses, so the disclosure cannot drift from the
      // arithmetic.
      MethodologySheet(source: SetCounting.source, certainty: .moderate)
    }
  }

  private func load() {
    do {
      report = try store.rollingWeek(endingAt: now())
      loadFailed = false
    } catch {
      report = nil
      loadFailed = true
    }
  }
}
