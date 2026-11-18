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
}
