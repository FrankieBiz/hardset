#if canImport(UIKit)
  import Foundation
  import HardsetCore
  import HardsetFeature
  import HardsetStore
  import HardsetUI
  import SwiftUI
  import Testing
  import UIKit

  /// Renders the first-launch sequence as the pager draws it: each page with its chrome (the Skip
  /// control, the progress segments, the primary button), and Setup for a fresh install and for one
  /// that already has a gym.
  ///
  /// Like the other render suites it is inert unless `HARDSET_SNAPSHOT_DIR` is set, and it asserts
  /// nothing about pixels.
  @MainActor
  @Suite("Onboarding renders for review", .serialized)
  struct OnboardingSnapshotTests {
    private static func freshGyms() throws -> GymStore {
      HardsetEnvironment(database: try Fixtures.database()).gyms
    }

    private static func gymsWithOneGym() throws -> (GymStore, GymID) {
      let destination = try Fixtures.database()
      let gyms = HardsetEnvironment(database: destination).gyms
      let id = try gyms.createGym(name: "Downtown", now: Date())
      return (gyms, id)
    }

    private static func flow(
      _ gyms: GymStore, page: OnboardingModel.Page, imperial: Bool = false
    ) -> some View {
      OnboardingFlow(
        gyms: gyms, useImperial: .constant(imperial), startingPage: page
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
      let (gyms, _) = try Self.gymsWithOneGym()
      try await Snapshot.capture("onboarding-setup-existing-dark", settle: .seconds(2)) {
        Self.flow(gyms, page: .setup, imperial: true)
      }
    }
  }
#endif
