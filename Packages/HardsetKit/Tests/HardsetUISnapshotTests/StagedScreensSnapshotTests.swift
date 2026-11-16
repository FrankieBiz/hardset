#if canImport(UIKit)
  import Foundation
  import HardsetCore
  import HardsetFeature
  import HardsetStore
  import HardsetUI
  import SwiftUI
  import Testing
  import UIKit

  /// Renders every screen the first-launch tour stages, from `TourFixtures`, so the tour is built on
  /// screens that already draw correctly and cannot show something the product does not do.
  ///
  /// Each capture stages its own environment, so no two share a database, and staging happens with
  /// `try` before the capture: a fixture that fails to build fails the test instead of rendering an
  /// empty screen that looks like a capture. The screens are the real ones: the Train start screen
  /// through `HardsetRootView`, and the live session, machine picker, Volume, History and Settings
  /// as the root builds them. The live session is drawn outside the tab view because this renderer
  /// cannot draw the tab bar's glass accessory (R47). The receipt is internal to `HardsetFeature`
  /// and is staged when Phase 6 rebuilds it (R46). Like the other render suites it is inert unless
  /// `HARDSET_SNAPSHOT_DIR` is set, and it asserts nothing about pixels.
  @MainActor
  @Suite("Staged tour screens render for review", .serialized)
  struct StagedScreensSnapshotTests {
    /// The staged world's present is the real clock, so the root view and the screens that read
    /// "now" agree with the history that lies before it.
    private static func stage(_ stage: TourFixtures.Stage) throws -> TourFixtures.Staged {
      try TourFixtures.make(stage: stage, now: Date())
    }

    /// The start screen as the tour opens on it, drawn by the real root view.
    @Test func trainStart() async throws {
      guard Snapshot.directory != nil else { return }
      let dark = try Self.stage(.start)
      try await Snapshot.capture("tour-start-dark") {
        HardsetRootView(environment: dark.environment, unit: .kilograms)
      }
      let light = try Self.stage(.start)
      try await Snapshot.capture("tour-start-light", style: .light) {
        HardsetRootView(environment: light.environment, unit: .kilograms)
      }
    }

    /// The same root inside the staged phone at the tour's share of the screen width, to review the
    /// frame itself: its steel plate, its rim, and the scaled screen inside it.
    @Test func framedStartScreen() async throws {
      guard Snapshot.directory != nil else { return }
      let staged = try Self.stage(.start)
      let width = Snapshot.phone.width * ScaledPhoneFrame<EmptyView>.screenWidthFraction
      try await Snapshot.capture("tour-start-framed-dark") {
        ZStack {
          Tokens.Color.canvas.ignoresSafeArea()
          ScaledPhoneFrame {
            HardsetRootView(environment: staged.environment, unit: .kilograms)
          }
          .frame(width: width)
        }
      }
    }

    /// The workout in progress, wired to a real coordinator and database, outside the tab view.
    @Test func liveSession() async throws {
      guard Snapshot.directory != nil else { return }
      let dark = try Self.stage(.liveSession)
      let darkSession = try #require(dark.liveSession)
      try await Snapshot.capture("tour-live-dark") {
        Self.liveSessionScreen(dark, coordinator: darkSession)
      }
      let light = try Self.stage(.liveSession)
      let lightSession = try #require(light.liveSession)
      try await Snapshot.capture("tour-live-light", style: .light) {
        Self.liveSessionScreen(light, coordinator: lightSession)
      }
    }

    /// The machine picker as the gym's own machines fill it: the machine the exercise is on first
    /// and selected, the others below.
    @Test func machinePicker() async throws {
      guard Snapshot.directory != nil else { return }
      let staged = try Self.stage(.liveSession)
      let options = staged.machines.map {
        MachineOption(
          id: $0.id, displayName: $0.displayName, stackIncrementKg: $0.stackIncrementKg)
      }
      try await Snapshot.capture("tour-machines-dark") {
        NavigationStack {
          MachinePickerView(
            recent: Array(options.prefix(1)), others: Array(options.dropFirst()),
            selected: options.first?.id, onSelect: { _ in }, onCancel: {})
        }
        .tint(Tokens.Color.plateBlue)
        .background(Tokens.Color.canvas.ignoresSafeArea())
      }
    }

    /// The Volume tab over a real week of staged history.
    @Test func volume() async throws {
      guard Snapshot.directory != nil else { return }
      let dark = try Self.stage(.start)
      try await Snapshot.capture("tour-volume-dark") { Self.volumeScreen(dark) }
      let light = try Self.stage(.start)
      try await Snapshot.capture("tour-volume-light", style: .light) { Self.volumeScreen(light) }
    }

    /// The History tab over twelve staged workouts. Tall, so the month grouping and several rows
    /// are in view.
    @Test func history() async throws {
      guard Snapshot.directory != nil else { return }
      let size = CGSize(width: Snapshot.phone.width, height: 1500)
      let dark = try Self.stage(.start)
      try await Snapshot.capture("tour-history-dark", size: size) { Self.historyScreen(dark) }
      let light = try Self.stage(.start)
      try await Snapshot.capture("tour-history-light", size: size, style: .light) {
        Self.historyScreen(light)
      }
    }

    /// Settings, with the gym the tour stages in its gyms section.
    @Test func settings() async throws {
      guard Snapshot.directory != nil else { return }
      let staged = try Self.stage(.start)
      try await Snapshot.capture("tour-settings-dark", size: CGSize(width: 402, height: 1600)) {
        SettingsSheet(
          useImperial: .constant(false), transfer: staged.environment.transfer,
          health: staged.environment.health, sync: staged.environment.sync,
          gyms: staged.environment.gyms, onDone: {}
        )
        .tint(Tokens.Color.plateBlue)
        .background(Tokens.Color.canvas.ignoresSafeArea())
      }
    }

    // MARK: - Screens

    private static func liveSessionScreen(
      _ staged: TourFixtures.Staged, coordinator: SessionCoordinator
    ) -> some View {
      NavigationStack {
        LiveSessionScreen(
          coordinator: coordinator, unit: .kilograms, catalog: staged.environment.catalog,
          gyms: staged.environment.gyms, progression: staged.environment.progression,
          gymName: staged.gymName, onShowSettings: {}
        )
        .hardsetTabRoot()
      }
    }

    private static func volumeScreen(_ staged: TourFixtures.Staged) -> some View {
      NavigationStack {
        WeeklyVolumeScreen(store: staged.environment.volume, onShowSettings: {})
          .hardsetTabRoot()
      }
    }

    private static func historyScreen(_ staged: TourFixtures.Staged) -> some View {
      NavigationStack {
        HistoryScreen(
          store: staged.environment.history, unit: .kilograms,
          receipts: staged.environment.receipts, progression: staged.environment.progression,
          onShowSettings: {}
        )
        .hardsetTabRoot()
      }
    }
  }
#endif
