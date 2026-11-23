import Foundation
import Testing

@testable import HardsetCore

@Suite("The progress board groups movements by body part")
struct ProgressBoardTests {
  let epoch = Date(timeIntervalSince1970: 1_700_000_000)

  private func entry(
    _ name: String, machine: String? = nil, bodyPart: MuscleFilterCategory?, day: Int = 0,
    change: Double? = nil
  ) -> ProgressBoard.Entry {
    let key = ProgressionKey(exerciseID: ExerciseID(), machineID: machine == nil ? nil : MachineID())
    return ProgressBoard.Entry(
      row: ProgressBoard.Row(
        trend: MovementTrend(
          key: key, metric: .estimatedMax, sparkline: [1, 2], sixWeekChange: change, sessionCount: 2,
          stalledSessions: nil, latestDate: epoch.addingTimeInterval(Double(day) * 86_400)),
        exerciseName: name, machineName: machine),
      bodyPart: bodyPart
    )
  }

  @Test("Sections follow the body-part order, with movements that have none last")
  func sectionsFollowCategoryOrderAndUntaggedLast() {
    let board = ProgressBoard.make([
      entry("Squat", bodyPart: .quads),
      entry("Mystery", bodyPart: nil),
      entry("Bench", bodyPart: .chest),
      entry("Row", bodyPart: .back),
    ])

    #expect(board.sections.map(\.category) == [.chest, .back, .quads, nil])
    #expect(board.sections.map { $0.rows.map(\.exerciseName) } == [["Bench"], ["Row"], ["Squat"], ["Mystery"]])
  }

  @Test("Within a section the movement trained most recently comes first")
  func rowsSortedByLatestDateThenName() {
    let board = ProgressBoard.make([
      entry("Fly", bodyPart: .chest, day: 1),
      entry("Press", bodyPart: .chest, day: 9),
      entry("Dip", bodyPart: .chest, day: 1),
    ])

    #expect(board.sections.first?.rows.map(\.exerciseName) == ["Press", "Dip", "Fly"])
  }

  @Test("One movement on two machines is two rows, never merged")
  func machinesStaySeparate() {
    let exercise = ExerciseID()
    let a = ProgressBoard.Entry(
      row: ProgressBoard.Row(
        trend: MovementTrend(
          key: ProgressionKey(exerciseID: exercise, machineID: MachineID()), metric: .heaviestLoad,
          sparkline: [1], sixWeekChange: nil, sessionCount: 1, stalledSessions: nil, latestDate: epoch),
        exerciseName: "Press", machineName: "Hammer"),
      bodyPart: .chest)
    let b = ProgressBoard.Entry(
      row: ProgressBoard.Row(
        trend: MovementTrend(
          key: ProgressionKey(exerciseID: exercise, machineID: MachineID()), metric: .heaviestLoad,
          sparkline: [1], sixWeekChange: nil, sessionCount: 1, stalledSessions: nil, latestDate: epoch),
        exerciseName: "Press", machineName: "Life Fitness"),
      bodyPart: .chest)

    let board = ProgressBoard.make([a, b])

    #expect(board.sections.first?.rows.count == 2)
    #expect(Set(board.sections.first?.rows.map(\.id) ?? []).count == 2)
  }

  @Test("Most improved is the three biggest gains from every movement, whichever section it is in")
  func mostImprovedFromEverySection() {
    let board = ProgressBoard.make([
      entry("A", bodyPart: .chest, change: 0.05),
      entry("B", bodyPart: .back, change: 0.2),
      entry("C", bodyPart: nil, change: 0.1),
      entry("D", bodyPart: .quads, change: 0.15),
      entry("E", bodyPart: .quads, change: -0.1),
      entry("F", bodyPart: .core, change: nil),
    ])

    #expect(board.mostImproved.map(\.exerciseName) == ["B", "D", "C"])
  }

  @Test("With nothing trained the board is empty")
  func emptyBoard() {
    #expect(ProgressBoard.make([]) == ProgressBoard.empty)
    #expect(ProgressBoard.empty.sections.isEmpty)
    #expect(ProgressBoard.empty.mostImproved.isEmpty)
  }
  @Test("Even directly constructed boards keep incomparable metrics out of the ranking")
  func rankingAlwaysNamesOneMetric() {
    let row = ProgressBoard.Row(trend: MovementTrend(key: ProgressionKey(exerciseID: ExerciseID()),
      metric: .heaviestLoad, sparkline: [1, 2], sixWeekChange: 1, sessionCount: 2,
      stalledSessions: nil, latestDate: epoch), exerciseName: "High-rep squat")
    #expect(ProgressBoard(sections: [], mostImproved: [row]).mostImproved.isEmpty)
    #expect(ProgressCopy.mostImprovedTitle == "Most improved · estimated max")
  }


  // MARK: - Imported history beside what was logged here

  private func series(
    _ name: String, exercise: ExerciseID, imported: Bool, machine: MachineID? = nil,
    bodyPart: MuscleFilterCategory? = .chest
  ) -> ProgressBoard.Entry {
    ProgressBoard.Entry(
      row: ProgressBoard.Row(
        trend: MovementTrend(
          key: ProgressionKey(exerciseID: exercise, machineID: machine, isImported: imported),
          metric: .heaviestLoad, sparkline: [1], sixWeekChange: nil, sessionCount: 1,
          stalledSessions: nil, latestDate: epoch),
        exerciseName: name, machineName: imported ? ProgressCopy.importedHistory : nil),
      bodyPart: bodyPart)
  }

  @Test("One movement with an imported series and a logged one says on both rows that the other is separate")
  func bothHalvesOfOneMovementPointAtEachOther() {
    let bench = ExerciseID()
    let imported = series("Barbell Bench Press", exercise: bench, imported: true)
    let logged = series("Barbell Bench Press", exercise: bench, imported: false)

    let board = ProgressBoard.make([imported, logged])

    // Two rows, never one: the series are kept apart, not merged.
    #expect(board.rows.count == 2)
    #expect(board.sourceNotes[imported.row.id] == ProgressCopy.importedBesideLogged)
    #expect(board.sourceNotes[logged.row.id] == ProgressCopy.loggedBesideImported)
    #expect(ProgressCopy.importedBesideLogged != ProgressCopy.loggedBesideImported)
  }

  @Test("Logged history on two machines each points at the imported series of the same movement")
  func everyLoggedRowOfTheMovementPoints() {
    let press = ExerciseID()
    let hammer = series("Chest press", exercise: press, imported: false, machine: MachineID())
    let lifeFitness = series("Chest press", exercise: press, imported: false, machine: MachineID())
    let imported = series("Chest press", exercise: press, imported: true)

    let notes = ProgressBoard.make([hammer, lifeFitness, imported]).sourceNotes

    #expect(notes[hammer.row.id] == ProgressCopy.loggedBesideImported)
    #expect(notes[lifeFitness.row.id] == ProgressCopy.loggedBesideImported)
    #expect(notes[imported.row.id] == ProgressCopy.importedBesideLogged)
  }

  @Test("An imported movement under its own name says it is not combined, and names no other row")
  func importedAloneIsNotMatchedByName() {
    // Same words, different movements: the app has no evidence they are one lift, so neither row
    // points at the other and the imported one says only what is true of every imported row.
    let imported = series("Bench Press (Imported • Strong)", exercise: ExerciseID(), imported: true)
    let logged = series("Bench Press", exercise: ExerciseID(), imported: false)

    let notes = ProgressBoard.make([imported, logged]).sourceNotes

    #expect(notes[imported.row.id] == ProgressCopy.importedAlone)
    #expect(notes[logged.row.id] == nil)
    #expect(!ProgressCopy.importedAlone.contains("Bench"))
  }

  @Test("A board with no imported row has no notes and no board-level sentence")
  func noImportedHistoryNoNotes() {
    let board = ProgressBoard.make([
      series("Squat", exercise: ExerciseID(), imported: false, bodyPart: .quads),
      series("Press", exercise: ExerciseID(), imported: false),
    ])

    #expect(board.sourceNotes.isEmpty)
    #expect(!board.hasImportedHistory)
    #expect(ProgressBoard.empty.sourceNotes.isEmpty)
    #expect(!ProgressBoard.empty.hasImportedHistory)
  }

  @Test("Any imported row makes the board say once why a lift can appear twice")
  func boardNoteAppearsWithImportedHistory() {
    let board = ProgressBoard.make([series("Row (Imported • Hevy)", exercise: ExerciseID(), imported: true)])

    #expect(board.hasImportedHistory)
    #expect(ProgressCopy.importedBoardNote.contains("appear twice"))
    #expect(ProgressCopy.importedBoardNote.contains("does not guess"))
    #expect(ProgressCopy.importedBoardNote.contains("never joins"))
  }

  @Test("The relationship is spoken with the row, after everything else it says")
  func sourceNoteIsSpoken() {
    let entry = series("Barbell Bench Press", exercise: ExerciseID(), imported: true)

    let spoken = ProgressCopy.spokenRow(entry.row, sourceNote: ProgressCopy.importedBesideLogged)

    #expect(spoken.hasSuffix(ProgressCopy.importedBesideLogged))
    #expect(ProgressCopy.spokenRow(entry.row) == ProgressCopy.spokenRow(entry.row, sourceNote: nil))
    #expect(!ProgressCopy.spokenRow(entry.row).contains("Not combined"))
  }
}
