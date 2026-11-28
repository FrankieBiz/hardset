#if canImport(UIKit)
  import Foundation
  import HardsetCore
  import HardsetUI
  import SwiftUI
  import Testing
  import UIKit

  /// Renders the exercise card for review from images. The card is a whole component, so each
  /// state is the snapshot's root view: every state once in dark, plus the leg-press card in light
  /// and Increase Contrast. Like the other suites it asserts nothing about pixels.
  @MainActor
  @Suite("Exercise card renders for review", .serialized)
  struct ExerciseCardSnapshotTests {
    private static let size = CGSize(width: 402, height: 720)
    /// One pinned moment for every render, so the dated "Last time" line is fixed in the images.
    private static let now = Date(timeIntervalSince1970: 1_793_000_000)
    private static let lastTime = now.addingTimeInterval(-20 * 86_400)
    private static let newestSet = lastTime.addingTimeInterval(600)

    private enum Machine {
      case unset
      case set(incrementKg: Double?)
      case borrowed
    }

    private enum Rest {
      case absent
      case asking
      case lastUsed
    }

    /// A leg-press card in the named condition, built through the engine's own `build` and
    /// `markLogged`, so every state is one the app can reach.
    private static func state(
      machine: Machine = .set(incrementKg: 10),
      plannedSets: Int = 3,
      logged: Int = 1
    ) -> ExerciseLogState {
      let exercise = ExerciseID()
      let priorMachine = MachineID()
      let machineID: MachineID?
      let machineName: String?
      let incrementKg: Double?
      var priorKeyMachine: MachineID? = priorMachine
      switch machine {
      case .unset:
        machineID = nil
        machineName = nil
        incrementKg = nil
        priorKeyMachine = nil
      case .set(let step):
        machineID = priorMachine
        machineName = "Hammer Strength"
        incrementKg = step
      case .borrowed:
        machineID = MachineID()
        machineName = "Cybex"
        incrementKg = nil
      }
      let key = ProgressionKey(exerciseID: exercise, machineID: priorKeyMachine)
      let records = [
        PriorSetRecord(weightKg: 100, reps: 10, completedAt: Self.lastTime),
        PriorSetRecord(weightKg: 105, reps: 8, completedAt: Self.newestSet),
        PriorSetRecord(weightKg: 60, reps: 12, completedAt: Self.newestSet),
      ]
      let snapshot = PriorPerformanceSnapshot(
        entries: [key: PriorPerformance(key: key, lastSets: records, heaviestSet: records[1])],
        capturedAt: Self.now
      )
      var built = ExerciseLogState.build(
        exerciseID: exercise,
        machineID: machineID,
        exerciseName: "Leg Press",
        machineName: machineName,
        machineIncrementKg: incrementKg,
        snapshot: snapshot,
        plannedSets: plannedSets
      )
      for index in built.slots.indices.prefix(logged) {
        built.markLogged(slotID: built.slots[index].id, setID: SetID())
      }
      return built
    }

    /// The leg-press card the existing renders share: the same fixture the screen suite builds,
    /// with its records twenty days before the pinned `now` rather than at the distant past.
    private static func legPress() -> ExerciseLogState {
      var state = Self.state(logged: 1)
      state.appendSlot(isWarmup: true)
      return state
    }

    private static func card(
      _ state: ExerciseLogState,
      unit: WeightUnit = .kilograms,
      history: Bool = true,
      rest: Rest = .absent,
      menu: Bool = false,
      needsGym: Bool = false
    ) -> some View {
      let showHistory: (() -> Void)? = history ? {} : nil
      let startRest: ((Duration) -> Void)? = rest == .absent ? nil : { _ in }
      let lastRest: Duration? = rest == .lastUsed ? .seconds(90) : nil
      let moveDown: (() -> Void)? = menu ? {} : nil
      let remove: (() -> Void)? = menu ? {} : nil
      return ScrollView {
        ExerciseSectionView(
          state: .constant(state),
          unit: unit,
          onLogSet: { _ in },
          onStartRest: startRest,
          onSelectMachine: {},
          machineNeedsGym: needsGym,
          onShowHistory: showHistory,
          lastRest: lastRest,
          onMoveDown: moveDown,
          onRemove: remove,
          now: Self.now
        )
        .padding(Tokens.Spacing.regular)
      }
      .background(Tokens.Color.canvas)
    }

    /// A card with a keypad host behind it: `onBeginEditing` is what makes a figure editable, and a
    /// row can be told which field the keypad is on.
    private static func editableCard(
      _ state: ExerciseLogState,
      unit: WeightUnit = .kilograms,
      editingSlot: Int? = nil,
      field: SetRowField? = nil,
      text: String? = nil
    ) -> some View {
      ScrollView {
        ExerciseSectionView(
          state: .constant(state),
          unit: unit,
          onLogSet: { _ in },
          onSelectMachine: {},
          onShowHistory: {},
          editingSlotID: editingSlot.map { state.slots[$0].id },
          editingField: field,
          editingText: text,
          onBeginEditing: { _, _ in },
          now: Self.now
        )
        .padding(Tokens.Spacing.regular)
      }
      .background(Tokens.Color.canvas)
    }

    /// The states the other captures cannot reach. A card with no keypad host draws read-only rows,
    /// and a read-only figure is never outlined or underlined, so these are the ones that are, at
    /// the 44 pt figure size: an editable figure at rest, the outline Increase Contrast draws around
    /// it, the caret and underline while it is typed into in each field, and a long pound value
    /// being typed on the narrowest phone.
    @Test func editableRows() async throws {
      let state = Self.legPress()
      try await Snapshot.capture("kit-exercise-editable-dark", size: Self.size) {
        Self.editableCard(state)
      }
      try await Snapshot.capture("kit-exercise-editable-dark-contrast", size: Self.size, contrast: .high) {
        Self.editableCard(state)
      }
      try await Snapshot.capture("kit-exercise-editing-weight-dark", size: Self.size) {
        Self.editableCard(state, editingSlot: 2, field: .weight, text: "102.5")
      }
      try await Snapshot.capture(
        "kit-exercise-editing-reps-dark-contrast", size: Self.size, contrast: .high
      ) {
        Self.editableCard(state, editingSlot: 2, field: .reps, text: "12")
      }
      try await Snapshot.capture(
        "kit-exercise-editing-pounds-dark-375", size: CGSize(width: 375, height: 720)
      ) {
        Self.editableCard(state, unit: .pounds, editingSlot: 2, field: .weight, text: "132.28")
      }
    }

    /// The leg-press card, the default state: a link title, a set machine chip with its step, one
    /// logged set, a warm-up row, and no rest control or menu.
    @Test func legPressCard() async throws {
      let name = "kit-exercise-leg-press"
      try await Snapshot.capture("\(name)-dark", size: Self.size) {
        Self.card(Self.legPress())
      }
      try await Snapshot.capture("\(name)-light", size: Self.size, style: .light) {
        Self.card(Self.legPress())
      }
      try await Snapshot.capture("\(name)-dark-contrast", size: Self.size, contrast: .high) {
        Self.card(Self.legPress())
      }
    }

    @Test func inertTitle() async throws {
      try await Snapshot.capture("kit-exercise-inert-title-dark", size: Self.size) {
        Self.card(Self.legPress(), history: false)
      }
    }

    @Test func machineChips() async throws {
      try await Snapshot.capture("kit-exercise-chip-unset-dark", size: Self.size) {
        Self.card(Self.state(machine: .unset))
      }
      try await Snapshot.capture("kit-exercise-chip-set-dark", size: Self.size) {
        Self.card(Self.state(machine: .set(incrementKg: nil)))
      }
      try await Snapshot.capture("kit-exercise-chip-step-pounds-dark", size: Self.size) {
        Self.card(Self.state(), unit: .pounds)
      }
    }

    /// A workout with no gym: the chip is still drawn, says no machine is recorded and that a gym
    /// comes first, so a lifter who left the gym blank at setup still meets machines.
    @Test func machineChipWithNoGym() async throws {
      try await Snapshot.capture("kit-exercise-chip-needs-gym-dark", size: Self.size) {
        Self.card(Self.state(machine: .unset), needsGym: true)
      }
      try await Snapshot.capture(
        "kit-exercise-chip-needs-gym-light", size: Self.size, style: .light
      ) {
        Self.card(Self.state(machine: .unset), needsGym: true)
      }
      try await Snapshot.capture(
        "kit-exercise-chip-needs-gym-dark-ax3", size: CGSize(width: 402, height: 3200),
        typeSize: .accessibility3
      ) {
        Self.card(Self.state(machine: .unset), needsGym: true)
      }
    }

    @Test func borrowedHistory() async throws {
      try await Snapshot.capture("kit-exercise-borrowed-dark", size: Self.size) {
        Self.card(Self.state(machine: .borrowed, logged: 0))
      }
    }

    /// The dated provenance line: one quiet line under the machine chip for history from this
    /// machine, and no second line for borrowed history, whose badge context carries the date.
    @Test func lastTimeSource() async throws {
      try await Snapshot.capture("exercise-card-last-time-dark", size: Self.size) {
        Self.card(Self.state())
      }
      try await Snapshot.capture(
        "exercise-card-last-time-accessibility3", size: CGSize(width: 402, height: 3200),
        typeSize: .accessibility3
      ) {
        Self.card(Self.state())
      }
      try await Snapshot.capture("exercise-card-last-time-borrowed-dark", size: Self.size) {
        Self.card(Self.state(machine: .borrowed, logged: 0))
      }
    }

    @Test func progress() async throws {
      try await Snapshot.capture("kit-exercise-progress-pips-dark", size: Self.size) {
        Self.card(Self.state(plannedSets: 5, logged: 2))
      }
      try await Snapshot.capture(
        "kit-exercise-progress-many-dark", size: CGSize(width: 402, height: 1100)
      ) {
        Self.card(Self.state(plannedSets: 10, logged: 2))
      }
      try await Snapshot.capture("kit-exercise-progress-complete-dark", size: Self.size) {
        Self.card(Self.state(plannedSets: 3, logged: 3))
      }
    }

    @Test func restControl() async throws {
      try await Snapshot.capture("kit-exercise-rest-last-dark", size: Self.size) {
        Self.card(Self.legPress(), rest: .lastUsed)
      }
      try await Snapshot.capture("kit-exercise-rest-asking-dark", size: Self.size) {
        Self.card(Self.legPress(), rest: .asking)
      }
    }

    /// The menu is a closed `Menu`, so what is captured is its resting face in the header. The
    /// absent state is the default card, already captured above.
    @Test func movementMenu() async throws {
      try await Snapshot.capture("kit-exercise-menu-dark", size: Self.size) {
        Self.card(Self.legPress(), menu: true)
      }
    }

    @Test func narrowPhone() async throws {
      try await Snapshot.capture(
        "kit-exercise-leg-press-dark-375", size: CGSize(width: 375, height: 720)
      ) {
        Self.card(Self.legPress(), unit: .pounds, rest: .lastUsed, menu: true)
      }
    }

    /// At an accessibility size the column header is hidden, the rows stack, the header puts
    /// progress and menu below the name, and the machine name wraps.
    @Test func accessibilitySizes() async throws {
      try await Snapshot.capture(
        "kit-exercise-leg-press-dark-ax3", size: CGSize(width: 402, height: 3200),
        typeSize: .accessibility3
      ) {
        Self.card(Self.legPress(), rest: .lastUsed, menu: true)
      }
      try await Snapshot.capture(
        "kit-exercise-borrowed-dark-ax3", size: CGSize(width: 402, height: 3200),
        typeSize: .accessibility3
      ) {
        Self.card(Self.state(machine: .borrowed, logged: 0), rest: .asking)
      }
    }
  }
#endif
