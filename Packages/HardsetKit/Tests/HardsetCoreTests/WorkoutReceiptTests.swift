import Foundation
import Testing

@testable import HardsetCore

@Suite("A receipt names equipment honestly and reads in the order the work was done")
struct WorkoutReceiptTests {
  private let start = Date(timeIntervalSince1970: 1_793_527_200)
  private let bench = ExerciseID()
  private let row = ExerciseID()

  private func line(
    _ exercise: ExerciseID?, _ name: String, _ equipment: WorkoutReceipt.Equipment,
    weight: Double = 100, reps: Int = 8, warmup: Bool = false,
    records: [PersonalRecord] = [], imported: Bool = false
  ) -> WorkoutReceipt.Line {
    .init(
      id: SetID(), exerciseID: exercise, exerciseName: name, equipment: equipment,
      weightKg: weight, reps: reps, isWarmup: warmup, records: records, isImported: imported)
  }

  private func receipt(_ lines: [WorkoutReceipt.Line]) -> WorkoutReceipt {
    WorkoutReceipt(
      id: SessionID(), title: "Push", startedAt: start, finishedAt: start.addingTimeInterval(3600),
      lines: lines)
  }

  // MARK: - Equipment

  /// A nil machine means two different things. For a barbell it is the whole truth; for a leg press
  /// it means the machine was never recorded. The label must say which.
  @Test("A missing machine is named by what the movement is", arguments: [
    (ExerciseModality?.some(.barbell), WorkoutReceipt.Equipment.freeWeight, "Free weight"),
    (.some(.dumbbell), .freeWeight, "Free weight"),
    (.some(.bodyweight), .bodyweight, "Bodyweight"),
    (.some(.machine), .unrecorded, "No machine recorded"),
    (.some(.cable), .unrecorded, "No machine recorded"),
    (nil, .unrecorded, "No machine recorded"),
  ])
  func equipmentFromModality(
    modality: ExerciseModality?, expected: WorkoutReceipt.Equipment, label: String
  ) {
    let equipment = WorkoutReceipt.Equipment(machineName: nil, modality: modality)
    #expect(equipment == expected)
    #expect(line(bench, "Lift", equipment).equipmentLabel == label)
  }

  @Test("A recorded machine is named whatever the movement's modality")
  func recordedMachine() {
    let equipment = WorkoutReceipt.Equipment(machineName: "Hammer Strength Row", modality: .barbell)
    #expect(equipment == .machine("Hammer Strength Row"))
    let saved = line(row, "Row", equipment)
    #expect(saved.machineName == "Hammer Strength Row")
    #expect(saved.equipmentLabel == "Hammer Strength Row")
  }

  @Test("Imported lines say the equipment is unevaluated")
  func importedLabel() {
    let imported = line(bench, "Press (Imported • Strong)", .unrecorded, imported: true)
    #expect(imported.equipmentLabel == "Imported • Unevaluated Machine")
    #expect(!imported.isEquipmentKnown)
  }

  /// The older initialiser is still how previews and snapshots build a receipt.
  @Test("The machine-name initialiser keeps its meaning")
  func compatibilityInitialiser() {
    let named = WorkoutReceipt.Line(
      id: SetID(), exerciseName: "Press", machineName: "Sled", weightKg: 80, reps: 8, isWarmup: false)
    #expect(named.equipment == .machine("Sled"))
    #expect(named.exerciseID == nil)
    let imported = WorkoutReceipt.Line(
      id: SetID(), exerciseName: "Press", machineName: nil, weightKg: 80, reps: 8, isWarmup: false,
      isImported: true)
    #expect(imported.isImported)
    #expect(imported.equipmentLabel == "Imported • Unevaluated Machine")
  }

  // MARK: - Certainty

  @Test("Free weight and recorded machines are evaluated; unknown equipment is not")
  func receiptCertainty() {
    #expect(receipt([]).certainty == .unevaluated)
    #expect(receipt([line(bench, "Bench", .freeWeight), line(row, "Row", .machine("Row"))]).certainty == .high)
    #expect(receipt([line(bench, "Bench", .bodyweight)]).certainty == .high)
    #expect(receipt([line(bench, "Bench", .freeWeight), line(row, "Leg press", .unrecorded)]).certainty == .unevaluated)
    #expect(receipt([line(bench, "Bench", .unrecorded, imported: true)]).certainty == .unevaluated)
  }

  // MARK: - Structure

  @Test("Movements are listed once each, in the order first performed")
  func movements() {
    let lines = [
      line(bench, "Bench", .freeWeight), line(row, "Row", .machine("Row")),
      line(bench, "Bench", .freeWeight), line(nil, "Preview", .freeWeight),
    ]
    #expect(receipt(lines).movements.map(\.exerciseID) == [bench, row])
    #expect(receipt(lines).movements.map(\.name) == ["Bench", "Row"])
  }

  @Test("Consecutive sets of one movement on one piece of equipment read as one block")
  func blocks() {
    let lines = [
      line(bench, "Bench", .freeWeight, weight: 60, warmup: true),
      line(bench, "Bench", .freeWeight), line(bench, "Bench", .freeWeight),
      line(row, "Row", .machine("Row A")), line(row, "Row", .machine("Row B")),
      line(bench, "Bench", .freeWeight),
    ]
    let blocks = receipt(lines).blocks
    #expect(blocks.map(\.exerciseName) == ["Bench", "Row", "Row", "Bench"])
    #expect(blocks.map(\.equipmentLabel) == ["Free weight", "Row A", "Row B", "Free weight"])
    #expect(blocks.map(\.lines.count) == [3, 1, 1, 1])
    #expect(blocks.flatMap(\.lines) == lines)
    #expect(Set(blocks.map(\.id)).count == blocks.count)
  }

  // MARK: - Text

  @Test("The shared text groups each movement and states each record's comparison")
  func text() {
    let record = PersonalRecord(kind: .heaviestLoad, weightKg: 100, reps: 8, previousWeightKg: 95)
    let text = receipt([
      line(bench, "Bench", .freeWeight, records: [record]),
      line(row, "Row", .machine("Row A"), weight: 72.5, reps: 10, records: [record]),
      line(row, "Row", .machine("Row A"), weight: 40, warmup: true),
    ]).text(unit: .kilograms, locale: Locale(identifier: "en_US_POSIX"))
    let rows = text.split(separator: "\n").map(String.init)
    #expect(rows.contains("Bench · Free weight"))
    #expect(rows.contains("  100 kg × 8"))
    #expect(rows.contains("    Heaviest weight · same movement with no machine recorded"))
    #expect(rows.contains("Row · Row A"))
    #expect(rows.contains("  72.5 kg × 10"))
    #expect(rows.contains("    Heaviest weight · same recorded machine"))
    #expect(rows.contains("  40 kg × 8 · Warm-up"))
    #expect(text.contains("not independently verified"))
    #expect(!text.contains("Unevaluated Machine"))
  }

  /// Six fraction digits of a converted pound value in a shared message reads as a measurement.
  @Test("Shared loads use the logger's precision, never default floating-point digits")
  func textPrecision() {
    let text = receipt([line(bench, "Bench", .freeWeight, weight: 100)])
      .text(unit: .pounds, locale: Locale(identifier: "en_US_POSIX"))
    #expect(text.contains("  220.46 lb × 8"))
  }
}

@Suite("Loads read the same everywhere")
struct LoadTextTests {
  private let posix = Locale(identifier: "en_US_POSIX")

  @Test("An entered load shows at most two decimals, like the keypad that took it")
  func entered() {
    #expect(LoadText.entered(100, in: .kilograms, locale: posix) == "100")
    #expect(LoadText.entered(102.25, in: .kilograms, locale: posix) == "102.25")
    #expect(LoadText.entered(100, in: .pounds, locale: posix) == "220.46")
    #expect(LoadText.entered(WeightUnit.pounds.toKilograms(225), in: .pounds, locale: posix) == "225")
  }

  /// An estimate implying ten-gram precision reads as a measurement.
  @Test("An estimate is rounded the way StrengthMath rounds estimates")
  func estimate() {
    #expect(LoadText.estimate(116.7, in: .kilograms, locale: posix) == "116.5")
    #expect(LoadText.estimate(116.8, in: .kilograms, locale: posix) == "117")
    #expect(LoadText.estimate(100, in: .pounds, locale: posix) == "220")
  }
}
