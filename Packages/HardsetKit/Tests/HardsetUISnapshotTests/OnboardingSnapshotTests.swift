#if canImport(UIKit)
  import Foundation
  import GRDB
  import HardsetCore
  import HardsetFeature
  import HardsetStore
  import HardsetUI
  import SwiftUI
  import Testing
  import UIKit

  /// Renders the first-launch sequence as the pager draws it: each page with its chrome (the Skip
  /// control, the progress segments, the primary button), Setup for a fresh install and for one
  /// that already has a gym, and every step of the tour over the staged phone.
  ///
  /// The tour captures are the proof that the spotlight lands on the real control: each is the real
  /// root view in the staged phone, asked into its state through `TourStaging`. This renderer
  /// cannot draw Liquid Glass, so the callout card appears without its glass, and the real-app
  /// screenshots show it. The tour builds two staged databases and prepares two roots, so its
  /// captures wait longer than the others. Like the other render suites it is inert unless
  /// `HARDSET_SNAPSHOT_DIR` is set, and it asserts nothing about pixels.
  @MainActor
  @Suite("Onboarding renders for review", .serialized)
  struct OnboardingSnapshotTests {
    private static let tourSettle: Duration = .seconds(9)

    private static func freshGyms() throws -> GymStore {
      HardsetEnvironment(database: try Fixtures.database()).gyms
    }

    private static func flow(
      _ gyms: GymStore, page: OnboardingModel.Page, step: OnboardingModel.TourStep = .train,
      imperial: Bool = false
    ) -> some View {
      OnboardingFlow(
        gyms: gyms, useImperial: .constant(imperial), startingPage: page, startingTourStep: step
      ) { _ in }
    }

    // MARK: - Pages

    @Test func welcome() async throws {
      guard Snapshot.directory != nil else { return }
      let gyms = try Self.freshGyms()
      try await Snapshot.capture("onboarding-welcome-dark") { Self.flow(gyms, page: .welcome) }
      try await Snapshot.capture("onboarding-welcome-light", style: .light) {
        Self.flow(gyms, page: .welcome)
      }
    }

    @Test func pitches() async throws {
      guard Snapshot.directory != nil else { return }
      let gyms = try Self.freshGyms()
      try await Snapshot.capture("onboarding-pitch-1-dark") { Self.flow(gyms, page: .pitchSetRow) }
      try await Snapshot.capture("onboarding-pitch-2-dark") {
        Self.flow(gyms, page: .pitchEstimate)
      }
      try await Snapshot.capture("onboarding-pitch-3-dark") { Self.flow(gyms, page: .pitchRest) }
      try await Snapshot.capture("onboarding-pitch-1-light", style: .light) {
        Self.flow(gyms, page: .pitchSetRow)
      }
    }

    // MARK: - Setup

    @Test func setupForAFreshInstall() async throws {
      guard Snapshot.directory != nil else { return }
      let gyms = try Self.freshGyms()
      try await Snapshot.capture("onboarding-setup-fresh-dark") { Self.flow(gyms, page: .setup) }
      try await Snapshot.capture("onboarding-setup-fresh-light", style: .light) {
        Self.flow(gyms, page: .setup, imperial: true)
      }
      try await Snapshot.capture(
        "onboarding-setup-fresh-dark-ax3", size: CGSize(width: 402, height: 1400),
        typeSize: .accessibility3
      ) { Self.flow(gyms, page: .setup) }
    }

    /// An install that already has a gym: the unit is preselected and the gym is a selection row,
    /// with no empty name field.
    @Test func setupForAnExistingInstall() async throws {
      guard Snapshot.directory != nil else { return }
      let staged = try TourFixtures.make(stage: .start, now: Date())
      try await Snapshot.capture("onboarding-setup-existing-dark", settle: .seconds(2)) {
        Self.flow(staged.environment.gyms, page: .setup, imperial: true)
      }
    }

    // MARK: - Tour

    /// Every step of the tour, one capture each, in the order the lifter sees them.
    @Test func tourSteps() async throws {
      guard Snapshot.directory != nil else { return }
      let gyms = try Self.freshGyms()
      for step in OnboardingModel.TourStep.allCases {
        try await Snapshot.capture(
          "onboarding-tour-\(step.number)-dark", settle: Self.tourSettle
        ) { Self.flow(gyms, page: .tour, step: step) }
      }
    }

    @Test func tourInLightAndAtALargeSize() async throws {
      guard Snapshot.directory != nil else { return }
      let gyms = try Self.freshGyms()
      try await Snapshot.capture(
        "onboarding-tour-2-light", style: .light, settle: Self.tourSettle
      ) { Self.flow(gyms, page: .tour, step: .logSet) }
      try await Snapshot.capture(
        "onboarding-tour-1-dark-ax3", typeSize: .accessibility3, settle: Self.tourSettle
      ) { Self.flow(gyms, page: .tour, step: .train) }
    }
  }
#endif
