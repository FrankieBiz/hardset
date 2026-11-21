#if canImport(UIKit)
  import Foundation
  import HardsetCore
  import HardsetUI
  import SwiftUI
  import Testing
  import UIKit

  /// Renders the numeric pad and the load-step sheet for review from images. Both are whole
  /// components, so each state is the snapshot's root view: every state once in dark, plus the
  /// default state in light and Increase Contrast. The failed save is the one state that needs an
  /// internal seam, so it is the `KeypadCatalogView` section that holds it, captured once in dark.
  @MainActor
  @Suite("Keypad renders for review", .serialized)
  struct KeypadSnapshotTests {
    private static let padSize = CGSize(width: 402, height: 580)
    private static let sheetSize = CGSize(width: 402, height: 874)

    private static let weight = NumericEntryBuffer(
      value: 102.5, maximumIntegerDigits: 4, maximumFractionDigits: 2
    )
    private static let emptyWeight = NumericEntryBuffer(
      value: nil, maximumIntegerDigits: 4, maximumFractionDigits: 2
    )
    private static let reps = NumericEntryBuffer(
      value: 8, allowsDecimal: false, maximumIntegerDigits: 3, maximumFractionDigits: 0
    )
    private static let emptyReps = NumericEntryBuffer(
      value: nil, allowsDecimal: false, maximumIntegerDigits: 3, maximumFractionDigits: 0
    )

    @Test func weightWithDoneAndNext() async throws {
      let name = "kit-keypad-weight-done-next"
      try await Snapshot.capture("\(name)-dark", size: Self.padSize) { Self.weightPad() }
      try await Snapshot.capture("\(name)-light", size: Self.padSize, style: .light) {
        Self.weightPad()
      }
      try await Snapshot.capture("\(name)-dark-contrast", size: Self.padSize, contrast: .high) {
        Self.weightPad()
      }
    }

    @Test func repsWithLog() async throws {
      try await Snapshot.capture("kit-keypad-reps-log-enabled-dark", size: Self.padSize) {
        NumericPad(
          buffer: .constant(Self.reps), title: "Reps", context: "Leg Press · Set 2",
          unit: "reps", onDone: {}, onLog: {}, canLog: true
        )
      }
      try await Snapshot.capture("kit-keypad-reps-log-disabled-dark", size: Self.padSize) {
        NumericPad(
          buffer: .constant(Self.emptyReps), title: "Reps", context: "Leg Press · Set 2",
          unit: "reps", onDone: {}, onLog: {}, canLog: false
        )
      }
    }

    @Test func loadStepPad() async throws {
      try await Snapshot.capture("kit-keypad-load-step-done-enabled-dark", size: Self.padSize) {
        NumericPad(
          buffer: .constant(NumericEntryBuffer(value: 2.5)), title: "Load step", unit: "kg",
          doneTitle: "Save load step", isDoneEnabled: true, onDone: {}
        )
      }
      try await Snapshot.capture("kit-keypad-load-step-done-disabled-dark", size: Self.padSize) {
        NumericPad(
          buffer: .constant(NumericEntryBuffer(value: 0)), title: "Load step", unit: "kg",
          doneTitle: "Save load step", isDoneEnabled: false, onDone: {}
        )
      }
    }

    /// An empty display shows the dash, and with nothing typed the negative quick steps are
    /// disabled, so one capture holds both states.
    @Test func emptyDisplayAndDisabledNegativeSteps() async throws {
      try await Snapshot.capture("kit-keypad-empty-dark", size: Self.padSize) {
        NumericPad(
          buffer: .constant(Self.emptyWeight), title: "Weight", unit: "kg", onDone: {},
          onNext: {}
        )
      }
    }

    @Test func replaceablePrefill() async throws {
      try await Snapshot.capture("kit-keypad-prefill-dark", size: Self.padSize) {
        NumericPad(
          buffer: .constant(NumericEntryBuffer(value: 60, replaceOnFirstEntry: true)),
          title: "Weight", unit: "kg", onDone: {}, onNext: {}
        )
      }
    }

    /// The static context line. The one with a live rest timer is the last test.
    @Test func contextLine() async throws {
      try await Snapshot.capture("kit-keypad-context-dark", size: Self.padSize) {
        NumericPad(
          buffer: .constant(Self.weight), title: "Weight", context: "Leg Press · Set 2",
          unit: "kg", onDone: {}, onNext: {}
        )
      }
    }

    /// A saved set's reps, being corrected: the context line says so, and with the set already
    /// logged the last field offers Done as the primary action and no "Log set".
    @Test func correctingASavedSet() async throws {
      try await Snapshot.capture("kit-keypad-correction-reps-dark", size: Self.padSize) {
        NumericPad(
          buffer: .constant(Self.reps), title: "Reps", context: "Leg Press · Set 1 · Correcting",
          unit: "reps", onDone: {}
        )
      }
      try await Snapshot.capture(
        "kit-keypad-correction-reps-light", size: Self.padSize, style: .light
      ) {
        NumericPad(
          buffer: .constant(Self.reps), title: "Reps", context: "Leg Press · Set 1 · Correcting",
          unit: "reps", onDone: {}
        )
      }
    }

    @Test func integerFieldWithHiddenDecimalSlot() async throws {
      try await Snapshot.capture("kit-keypad-integer-dark", size: Self.padSize) {
        NumericPad(
          buffer: .constant(Self.reps), title: "Reps", unit: "reps", onDone: {}, onNext: {}
        )
      }
    }

    @Test func accessibilitySizes() async throws {
      try await Snapshot.capture(
        "kit-keypad-weight-dark-ax3", size: CGSize(width: 402, height: 1100),
        typeSize: .accessibility3
      ) { Self.weightPad() }
    }

    // MARK: - Load-step sheet

    /// Every load-step sheet capture, here and in the failed save below, wears the plate-blue tint
    /// a real presentation applies through `hardsetSheet()`, so the toolbar Cancel is plate blue
    /// rather than near-black.
    @Test func loadStepSheet() async throws {
      try await Snapshot.capture("kit-keypad-sheet-kg-dark", size: Self.sheetSize) {
        LoadStepSheet(
          machineName: "Cybex Leg Press", incrementKg: 2.5, unit: .kilograms,
          onSave: { _ in true }, onCancel: {}
        )
        .tint(Tokens.Color.plateBlue)
      }
      try await Snapshot.capture("kit-keypad-sheet-lb-dark", size: Self.sheetSize) {
        LoadStepSheet(
          machineName: "Cybex Leg Press", incrementKg: 2.5, unit: .pounds,
          onSave: { _ in true }, onCancel: {}
        )
        .tint(Tokens.Color.plateBlue)
      }
      try await Snapshot.capture("kit-keypad-sheet-blank-dark", size: Self.sheetSize) {
        LoadStepSheet(
          machineName: "Cybex Leg Press", incrementKg: nil, unit: .kilograms,
          onSave: { _ in true }, onCancel: {}
        )
        .tint(Tokens.Color.plateBlue)
      }
      try await Snapshot.capture("kit-keypad-sheet-zero-dark", size: Self.sheetSize) {
        LoadStepSheet(
          machineName: "Cybex Leg Press", incrementKg: 0, unit: .kilograms,
          onSave: { _ in true }, onCancel: {}
        )
        .tint(Tokens.Color.plateBlue)
      }
      try await Snapshot.capture(
        "kit-keypad-sheet-kg-dark-ax3", size: CGSize(width: 402, height: 1800),
        typeSize: .accessibility3
      ) {
        LoadStepSheet(
          machineName: "Cybex Leg Press", incrementKg: 2.5, unit: .kilograms,
          onSave: { _ in true }, onCancel: {}
        )
        .tint(Tokens.Color.plateBlue)
      }
    }

    /// The failed save, reached through the catalogue's internal seam.
    @Test func loadStepFailedSave() async throws {
      for section in KeypadCatalogView.Section.allCases {
        try await Snapshot.capture(
          "kit-keypad-\(section.rawValue)-dark", size: Self.sheetSize
        ) {
          KeypadCatalogView(section: section)
            .tint(Tokens.Color.plateBlue)
        }
      }
    }

    /// Last, and alone: a running rest timer in the context line is a live `Text(timerInterval:)`,
    /// which once stalled a render.
    @Test func contextLineWithLiveRest() async throws {
      try await Snapshot.capture("kit-keypad-context-rest-dark", size: Self.padSize) {
        NumericPad(
          buffer: .constant(Self.weight), title: "Weight", context: "Leg Press · Set 2",
          unit: "kg", restEndsAt: Date().addingTimeInterval(84), onDone: {}, onNext: {}
        )
      }
    }

    private static func weightPad() -> some View {
      NumericPad(
        buffer: .constant(weight), title: "Weight", unit: "kg", onDone: {}, onNext: {}
      )
    }
  }
#endif
