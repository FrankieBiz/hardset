#if canImport(UIKit)
  import Foundation
  import HardsetCore
  import HardsetUI
  import SwiftUI
  import Testing
  import UIKit

  /// Renders the machine picker as the root view, one capture per state, so it can be reviewed from
  /// images.
  ///
  /// The picker is a whole screen, so it is not a catalogue section. Every state is captured once
  /// in dark, and the default state, a gym with no machines, is also captured in light and with
  /// Increase Contrast. Like the other render suites it is inert unless `HARDSET_SNAPSHOT_DIR` is
  /// set, and it asserts nothing about pixels.
  @MainActor
  @Suite("Machine picker renders for review", .serialized)
  struct MachinePickerSnapshotTests {
    private static let phone = CGSize(width: 402, height: 874)
    private static let tall = CGSize(width: 402, height: 1300)
    private static let accessibility = CGSize(width: 402, height: 2800)

    private static let hammer = MachineOption(
      id: MachineID(), displayName: "Hammer Strength Leg Press", stackIncrementKg: 10)
    private static let cybex = MachineOption(
      id: MachineID(), displayName: "Cybex Leg Press", stackIncrementKg: 4.5)
    private static let technogym = MachineOption(
      id: MachineID(), displayName: "Technogym Selection Leg Press", stackIncrementKg: 5)
    private static let lifeFitness = MachineOption(
      id: MachineID(), displayName: "Life Fitness Pro Leg Press", stackIncrementKg: 2.5)
    private static let panatta = MachineOption(id: MachineID(), displayName: "Panatta Leg Press")
    private static let hackSquat = MachineOption(
      id: MachineID(), displayName: "Plate-loaded hack squat by the window, second from the end",
      stackIncrementKg: 2.5)
    /// A second long name for the other list, so no machine is offered as both recent and other.
    private static let backWallHackSquat = MachineOption(
      id: MachineID(), displayName: "Plate-loaded hack squat on the back wall, under the clock",
      stackIncrementKg: 2.5)

    private static let manyRecent = [hammer, cybex, technogym, lifeFitness]

    private static func picker(
      recent: [MachineOption],
      others: [MachineOption] = [],
      selected: MachineID? = nil,
      unit: WeightUnit = .kilograms,
      errorMessage: String? = nil,
      isLoading: Bool = false,
      onAddMachine: (() -> Void)? = {},
      onEditIncrement: ((MachineID) -> Void)? = nil
    ) -> some View {
      NavigationStack {
        MachinePickerView(
          recent: recent,
          others: others,
          selected: selected,
          unit: unit,
          errorMessage: errorMessage,
          isLoading: isLoading,
          onSelect: { _ in },
          onAddMachine: onAddMachine,
          onEditIncrement: onEditIncrement,
          onArchive: { _ in },
          onCancel: {}
        )
        .hardsetNavigationTitle("Machine")
      }
      // A real presentation applies hardsetSheet()'s plate-blue tint, so Cancel is plate blue.
      .tint(Tokens.Color.plateBlue)
      // Fills the window with the app canvas, so a picker shorter than its window leaves no seam
      // of window background below its content.
      .background(Tokens.Color.canvas.ignoresSafeArea())
    }

    // MARK: - Default state

    /// A gym with no machines and nothing wrong: the picker's default, in every appearance.
    @Test func zeroRecentMachines() async throws {
      let name = "kit-machine-zero"
      try await Snapshot.capture("\(name)-dark", size: Self.phone) { Self.picker(recent: []) }
      try await Snapshot.capture("\(name)-light", size: Self.phone, style: .light) {
        Self.picker(recent: [])
      }
      try await Snapshot.capture("\(name)-dark-contrast", size: Self.phone, contrast: .high) {
        Self.picker(recent: [])
      }
    }

    // MARK: - Recency

    @Test func oneAndManyRecentMachines() async throws {
      try await Snapshot.capture("kit-machine-one-dark", size: Self.phone) {
        Self.picker(recent: [Self.hammer], others: [Self.panatta])
      }
      try await Snapshot.capture("kit-machine-many-dark", size: Self.tall) {
        Self.picker(recent: Self.manyRecent, others: [Self.panatta])
      }
    }

    @Test func othersOnly() async throws {
      try await Snapshot.capture("kit-machine-others-dark", size: Self.phone) {
        Self.picker(recent: [], others: [Self.panatta, Self.lifeFitness])
      }
    }

    // MARK: - Selection

    @Test func selection() async throws {
      try await Snapshot.capture("kit-machine-hero-selected-dark", size: Self.tall) {
        Self.picker(recent: Self.manyRecent, selected: Self.hammer.id)
      }
      try await Snapshot.capture("kit-machine-row-selected-dark", size: Self.tall) {
        Self.picker(recent: Self.manyRecent, selected: Self.technogym.id)
      }
      try await Snapshot.capture("kit-machine-not-recorded-selected-dark", size: Self.tall) {
        Self.picker(recent: Self.manyRecent, selected: nil)
      }
      // A machine the list does not hold: nothing is selected on screen and no load-step button
      // is offered, even though the caller supplied one.
      try await Snapshot.capture("kit-machine-unlisted-selected-dark", size: Self.tall) {
        Self.picker(
          recent: Self.manyRecent, selected: MachineID(), onEditIncrement: { _ in })
      }
    }

    // MARK: - Steps

    @Test func steps() async throws {
      try await Snapshot.capture("kit-machine-steps-kg-dark", size: Self.tall) {
        Self.picker(recent: Self.manyRecent, unit: .kilograms)
      }
      try await Snapshot.capture("kit-machine-steps-lb-dark", size: Self.tall) {
        Self.picker(recent: Self.manyRecent, unit: .pounds)
      }
      try await Snapshot.capture("kit-machine-unknown-step-dark", size: Self.phone) {
        Self.picker(recent: [Self.panatta], others: [Self.hammer])
      }
    }

    // MARK: - Errors and loading

    @Test func errors() async throws {
      try await Snapshot.capture("kit-machine-error-with-machines-dark", size: Self.tall) {
        Self.picker(
          recent: [Self.hammer, Self.cybex],
          others: [Self.panatta],
          errorMessage: "This machine could not be saved. You can still log without one."
        )
      }
      try await Snapshot.capture("kit-machine-error-without-machines-dark", size: Self.phone) {
        Self.picker(
          recent: [],
          errorMessage: "This gym’s machines could not be read. You can still log without one."
        )
      }
    }

    @Test func loading() async throws {
      try await Snapshot.capture("kit-machine-loading-dark", size: Self.phone) {
        Self.picker(recent: [], isLoading: true)
      }
    }

    // MARK: - Actions and names

    @Test func actionsAndNames() async throws {
      try await Snapshot.capture("kit-machine-load-step-dark", size: Self.tall) {
        Self.picker(
          recent: Self.manyRecent,
          selected: Self.cybex.id,
          onEditIncrement: { _ in }
        )
      }
      try await Snapshot.capture("kit-machine-no-add-dark", size: Self.tall) {
        Self.picker(recent: Self.manyRecent, onAddMachine: nil)
      }
      try await Snapshot.capture("kit-machine-long-names-dark", size: Self.tall) {
        Self.picker(
          recent: [Self.hackSquat, Self.technogym], others: [Self.backWallHackSquat])
      }
    }

    // MARK: - Accessibility sizes

    @Test func accessibilitySizes() async throws {
      try await Snapshot.capture(
        "kit-machine-many-dark-ax3", size: Self.accessibility, typeSize: .accessibility3
      ) {
        Self.picker(recent: Self.manyRecent, others: [Self.panatta])
      }
      // At accessibility sizes the uncapped banner is inside the scrolling content, not pinned
      // above it. This phone-height capture checks that, with the banner there, the first two
      // list rows (of one recent and several other machines) are visible, so it can fail.
      try await Snapshot.capture(
        "kit-machine-error-dark-ax3", size: Self.phone, typeSize: .accessibility3
      ) {
        Self.picker(
          recent: [Self.hammer],
          others: [Self.cybex, Self.technogym, Self.lifeFitness],
          errorMessage: "This gym’s machines could not be read. You can still log without one."
        )
      }
    }
  }
#endif
