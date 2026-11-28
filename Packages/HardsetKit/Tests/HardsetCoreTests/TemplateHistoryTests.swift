import Foundation
import Testing

@testable import HardsetCore

@Suite("A saved workout's history is a value the view can draw")
struct TemplateHistoryTests {
  private let start = Date(timeIntervalSince1970: 1_700_000_000)

  private func day(_ offset: Int) -> Date {
    start.addingTimeInterval(Double(offset) * 86_400)
  }

  private func movement(
    _ exerciseID: ExerciseID = ExerciseID(), _ name: String,
    machine: (id: MachineID, name: String)? = nil, sets: Int, volumeKg: Double
  ) -> TemplateHistory.Movement {
    let machineID = machine?.id
    return TemplateHistory.Movement(
      id: "\(exerciseID.description)|\(machineID?.description ?? "")",
      exerciseName: name,
      machineName: machine?.name,
      workingSetCount: sets,
      volumeKg: volumeKg
    )
  }

  private func session(
    _ id: SessionID = SessionID(), day offset: Int,
    movements: [TemplateHistory.Movement]
  ) -> TemplateHistory.Session {
    TemplateHistory.Session(id: id, finishedAt: day(offset), movements: movements)
  }

  @Test("Two sessions come newest first, each with its own movements and counts")
  func sessionsComeNewestFirst() {
    let bench = ExerciseID()
    let row = ExerciseID()
    let older = session(
      day: 1,
      movements: [movement(bench, "Bench press", sets: 3, volumeKg: 2_400)])
    let newer = session(
      day: 4,
      movements: [
        movement(bench, "Bench press", sets: 4, volumeKg: 3_200),
        movement(row, "Cable row", sets: 3, volumeKg: 1_800),
      ])

    let history = TemplateHistory(
      sessions: [older, newer], totalSessionCount: 2, limit: 12)

    #expect(history.sessions.map(\.id) == [newer.id, older.id])
    #expect(history.sessions.map(\.workingSetCount) == [7, 3])
    #expect(history.sessions.map(\.volumeKg) == [5_000, 2_400])
    #expect(history.sessions[0].movements.map(\.exerciseName) == ["Bench press", "Cable row"])
    #expect(history.sessions[1].movements.map(\.exerciseName) == ["Bench press"])
  }

  @Test("A movement in one session is not invented for another")
  func aMovementIsNotInventedForAnotherSession() {
    let bench = ExerciseID()
    let row = ExerciseID()
    let withRow = session(
      day: 2,
      movements: [
        movement(bench, "Bench press", sets: 4, volumeKg: 3_200),
        movement(row, "Cable row", sets: 3, volumeKg: 1_800),
      ])
    let withoutRow = session(
      day: 1,
      movements: [movement(bench, "Bench press", sets: 3, volumeKg: 2_400)])

    let history = TemplateHistory(
      sessions: [withRow, withoutRow], totalSessionCount: 2, limit: 12)

    let newer = history.sessions[0]
    let older = history.sessions[1]
    #expect(newer.movements.count == 2)
    #expect(older.movements.count == 1)
    #expect(older.movements.first?.exerciseName == "Bench press")
    #expect(history.sessions.flatMap(\.movements).filter { $0.exerciseName == "Cable row" }.count == 1)
  }

  @Test("A session's totals are the sum of its working-set rows")
  func sessionTotalsAreItsMovementRows() {
    let movements = [
      movement(ExerciseID(), "Bench press", sets: 4, volumeKg: 4_000),
      movement(ExerciseID(), "Cable row", sets: 3, volumeKg: 1_800),
    ]

    let session = TemplateHistory.Session(
      id: SessionID(), finishedAt: day(0), movements: movements)

    #expect(session.workingSetCount == 7)
    #expect(session.volumeKg == 5_800)
  }

  @Test("The page is at most the limit, while the total is the whole history")
  func pageIsLimitedButTotalIsWhole() {
    let sessions = (0..<3).map { offset in
      session(day: offset, movements: [movement(ExerciseID(), "Squat", sets: 1, volumeKg: 100)])
    }

    let history = TemplateHistory(sessions: sessions, totalSessionCount: 37, limit: 2)

    #expect(history.sessions.count == 2)
    #expect(history.sessions.map(\.finishedAt) == [day(2), day(1)])
    #expect(history.totalSessionCount == 37)
    #expect(history.limit == 2)
  }

  @Test("The sessions line says 12 of 37, and handles the singular forms")
  func sessionsLineCountsAndPluralises() {
    #expect(
      TemplateHistoryCopy.sessionsLine(shown: 12, total: 37)
        == "12 of 37 finished sessions")
    #expect(TemplateHistoryCopy.sessionsLine(shown: 1, total: 37) == "1 of 37 finished sessions")
    #expect(TemplateHistoryCopy.sessionsLine(shown: 37, total: 37) == "37 finished sessions")
    #expect(TemplateHistoryCopy.sessionsLine(shown: 1, total: 1) == "1 finished session")
    #expect(TemplateHistoryCopy.sessionsLine(shown: 0, total: 0) == "0 finished sessions")
  }

  @Test("The detail line names working sets and volume, in the singular too")
  func movementDetailNamesWorkingSetsAndVolume() {
    #expect(
      TemplateHistoryCopy.movementDetail(sets: 4, volume: "1,200 kg")
        == "4 working sets · 1,200 kg volume")
    #expect(
      TemplateHistoryCopy.movementDetail(sets: 1, volume: "100 kg")
        == "1 working set · 100 kg volume")
  }

  @Test("No string in the history copy claims a trend, a record or advice")
  func copyMakesNoClaimItCannotSupport() {
    // The sheet must not claim a comparison it does not compute, so the Progress tab's words are
    // banned here.
    let banned = [
      "should", "recommend", "best", "record", "progress", "improve", "ideal", "goal", "must",
      "streak", "score",
    ]
    let strings = [
      TemplateHistoryCopy.empty,
      TemplateHistoryCopy.sessionsLine(shown: 0, total: 0),
      TemplateHistoryCopy.sessionsLine(shown: 1, total: 1),
      TemplateHistoryCopy.sessionsLine(shown: 12, total: 37),
      TemplateHistoryCopy.movementDetail(sets: 1, volume: "100 kg"),
      TemplateHistoryCopy.movementDetail(sets: 4, volume: "1,200 kg"),
    ]

    for string in strings {
      let lowered = string.lowercased()
      for word in banned {
        #expect(!lowered.contains(word), "“\(word)” appears in “\(string)”")
      }
    }
  }

  @Test("A movement with no machine keeps no machine name and still has its own row")
  func aMovementWithNoMachineIsItsOwnRow() {
    let pullUp = ExerciseID()
    let bench = ExerciseID()
    let machine = (id: MachineID(), name: "Hammer Strength")
    let session = session(
      day: 1,
      movements: [
        movement(bench, "Chest press", machine: machine, sets: 4, volumeKg: 3_600),
        movement(pullUp, "Pull-up", sets: 3, volumeKg: 0),
      ])

    let bodyweight = session.movements[1]
    #expect(session.movements.count == 2)
    #expect(bodyweight.machineName == nil)
    #expect(bodyweight.id == "\(pullUp.description)|")
    #expect(bodyweight.workingSetCount == 3)
  }
}
