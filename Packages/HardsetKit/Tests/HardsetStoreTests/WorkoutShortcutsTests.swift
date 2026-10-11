import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

@Suite("Shortcuts the lifter starts: recent movements, and repeating a past workout")
@MainActor
struct WorkoutShortcutsTests {
  let now = Date(timeIntervalSince1970: 25_000_000)

  private struct Fixture {
    let database: any DatabaseWriter
    let logger: LoggerStore
    let gyms: GymStore
    let shortcuts: WorkoutShortcutsStore
    let press: ExerciseID
    let curl: ExerciseID
  }

  private func fixture() throws -> Fixture {
    var configuration = Configuration.forTesting()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    let press = ExerciseID()
    let curl = ExerciseID()
    try queue.write { db in
      try Exercise.insert { Exercise.Draft(id: press.rawValue, name: "Leg Press") }.execute(db)
      try Exercise.insert { Exercise.Draft(id: curl.rawValue, name: "Leg Curl") }.execute(db)
    }
    return Fixture(
      database: queue, logger: LoggerStore(database: queue), gyms: GymStore(database: queue),
      shortcuts: WorkoutShortcutsStore(database: queue), press: press, curl: curl)
  }

  private func day(_ offset: Double) -> Date { now.addingTimeInterval(offset * 86_400) }

  /// One finished workout. Each entry is a plan row, with the sets logged against it.
  @discardableResult
  private func workout(
    _ f: Fixture, gym: GymID?, at date: Date,
    _ rows: [(exercise: ExerciseID, machine: MachineID?, sets: [(Double, Int)])]
  ) throws -> SessionID {
    let session = try f.logger.startSession(gymID: gym, at: date)
    for (position, row) in rows.enumerated() {
      let rowID = try f.logger.addExercise(
        to: session, exerciseID: row.exercise, machineID: row.machine, position: position)
      for (index, set) in row.sets.enumerated() {
        _ = try f.logger.logSet(
          sessionID: session, exerciseID: row.exercise, machineID: row.machine,
          sessionExerciseID: rowID, draft: SetEntryDraft(weightKg: set.0, reps: set.1),
          at: date.addingTimeInterval(Double(position * 600 + index * 60)))
      }
    }
    try f.logger.finishSession(session, at: date.addingTimeInterval(3_600))
    return session
  }

  // MARK: Recent

  @Test("Recent movements: newest first, each once, archived ones left out, bounded")
  func recent() throws {
    let f = try fixture()
    let retired = ExerciseID()
    try f.database.write { db in
      try Exercise.insert {
        Exercise.Draft(id: retired.rawValue, name: "Old Row", isArchived: true)
      }
      .execute(db)
    }
    let session = try f.logger.startSession(at: day(-3))
    _ = try f.logger.logSet(
      sessionID: session, exerciseID: f.press, draft: SetEntryDraft(weightKg: 100, reps: 8),
      at: day(-3))
    _ = try f.logger.logSet(
      sessionID: session, exerciseID: f.curl, draft: SetEntryDraft(weightKg: 40, reps: 10),
      at: day(-2))
    _ = try f.logger.logSet(
      sessionID: session, exerciseID: f.press, draft: SetEntryDraft(weightKg: 100, reps: 8),
      at: day(-1))
    _ = try f.logger.logSet(
      sessionID: session, exerciseID: retired, draft: SetEntryDraft(weightKg: 50, reps: 10),
      at: day(0))

    #expect(try f.shortcuts.recentExercises().map(\.id) == [f.press, f.curl])
    #expect(try f.shortcuts.recentExercises(limit: 1).map(\.id) == [f.press])
  }

  @Test("Movements whose latest sets share a timestamp come back in a stable order, by set id")
  func recentTieBreak() throws {
    let f = try fixture()
    let session = try f.logger.startSession(at: day(-1))
    var logged: [(set: SetID, exercise: ExerciseID)] = []
    for exercise in [f.press, f.curl] {
      let set = try f.logger.logSet(
        sessionID: session, exerciseID: exercise, draft: SetEntryDraft(weightKg: 50, reps: 10),
        at: day(-1))
      logged.append((set, exercise))
    }
    let expected = logged.sorted { $0.set.rawValue.uuidString.lowercased() < $1.set.rawValue.uuidString.lowercased() }
      .map(\.exercise)
    for _ in 0..<5 {
      #expect(try f.shortcuts.recentExercises().map(\.id) == expected)
    }
  }

  @Test("Archived movements do not use up the bound")
  func archivedDoNotCrowd() throws {
    let f = try fixture()
    let retired = ExerciseID()
    try f.database.write { db in
      try Exercise.insert {
        Exercise.Draft(id: retired.rawValue, name: "Old Row", isArchived: true)
      }
      .execute(db)
    }
    let session = try f.logger.startSession(at: day(-3))
    _ = try f.logger.logSet(
      sessionID: session, exerciseID: f.press, draft: SetEntryDraft(weightKg: 100, reps: 8),
      at: day(-3))
    _ = try f.logger.logSet(
      sessionID: session, exerciseID: retired, draft: SetEntryDraft(weightKg: 50, reps: 10),
      at: day(0))
    #expect(try f.shortcuts.recentExercises(limit: 1).map(\.id) == [f.press])
  }

  @Test("No history, no recent movements")
  func noneYet() throws {
    let f = try fixture()
    #expect(try f.shortcuts.recentExercises().isEmpty)
  }

  // MARK: Repeat

  @Test("Repeat copies the movements and machines in order, and no loads or set counts")
  func copiesMovementsAndMachines() throws {
    let f = try fixture()
    let gym = try f.gyms.createGym(name: "Home", now: now)
    let hammer = try f.gyms.createMachine(
      at: gym, name: "Leg Press", brand: "Hammer Strength", stackIncrementKg: 5, now: now)
    let past = try workout(
      f, gym: gym, at: day(-8),
      [(f.press, hammer, [(100, 8), (100, 8)]), (f.curl, nil, [(40, 10)])])

    let plan = try f.shortcuts.repeatPlan(of: past)

    #expect(plan.sourceSessionID == past)
    #expect(plan.gymID == gym)
    #expect(plan.items.map(\.exerciseID) == [f.press, f.curl])
    #expect(plan.items.map(\.machineID) == [hammer, nil])
    #expect(plan.items[0].machineName == "Hammer Strength Leg Press")
    #expect(plan.items[0].machineIncrementKg == 5)
    #expect(plan.items[0].exerciseName == "Leg Press")
    #expect(plan.plannedExercises.allSatisfy { $0.plannedSets == nil })
  }

  /// Review Focus: repeating an older workout must not bring back its loads.
  @Test("A repeated workout prefills from the latest history, not from the workout repeated")
  func prefillComesFromLatestHistory() throws {
    let f = try fixture()
    let gym = try f.gyms.createGym(name: "Home", now: now)
    let hammer = try f.gyms.createMachine(at: gym, name: "Leg Press", now: now)
    let past = try workout(f, gym: gym, at: day(-8), [(f.press, hammer, [(100, 8), (100, 8)])])
    try workout(f, gym: gym, at: day(-2), [(f.press, hammer, [(110, 6)])])

    let plan = try f.shortcuts.repeatPlan(of: past)
    let coordinator = try SessionCoordinator.start(
      store: f.logger, gymID: plan.gymID, plan: plan.plannedExercises, now: { self.now })

    #expect(coordinator.exercises[0].machineID == hammer)
    #expect(coordinator.exercises[0].slots.count == 1)
    #expect(coordinator.exercises[0].slots[0].draft.weightKg == 110)
    #expect(coordinator.exercises[0].slots[0].draft.reps == 6)
  }

  @Test("Two blocks of one movement both repeat; a movement never logged does not")
  func onlyWhatWasDone() throws {
    let f = try fixture()
    let past = try workout(
      f, gym: nil, at: day(-3),
      [(f.press, nil, [(100, 8)]), (f.curl, nil, []), (f.press, nil, [(80, 12)])])
    #expect(try f.shortcuts.repeatPlan(of: past).items.map(\.exerciseID) == [f.press, f.press])
  }

  @Test("Sets with no plan row count toward the first row for their movement, as in resume")
  func orphanSetsAttributedLikeResume() throws {
    let f = try fixture()
    let session = try f.logger.startSession(at: day(-3))
    _ = try f.logger.addExercise(to: session, exerciseID: f.press, position: 0)
    _ = try f.logger.addExercise(to: session, exerciseID: f.press, position: 1)
    _ = try f.logger.logSet(
      sessionID: session, exerciseID: f.press, draft: SetEntryDraft(weightKg: 100, reps: 8),
      at: day(-3))
    try f.logger.finishSession(session, at: day(-3).addingTimeInterval(3_600))

    #expect(try f.shortcuts.repeatPlan(of: session).items.count == 1)
  }

  @Test("A machine changed mid-exercise repeats the machine it ended on")
  func endedOnMachine() throws {
    let f = try fixture()
    let gym = try f.gyms.createGym(name: "Home", now: now)
    let hammer = try f.gyms.createMachine(at: gym, name: "Leg Press", brand: "Hammer", now: now)
    let cybex = try f.gyms.createMachine(at: gym, name: "Leg Press", brand: "Cybex", now: now)
    let session = try f.logger.startSession(gymID: gym, at: day(-3))
    let row = try f.logger.addExercise(
      to: session, exerciseID: f.press, machineID: hammer, position: 0)
    _ = try f.logger.logSet(
      sessionID: session, exerciseID: f.press, machineID: hammer, sessionExerciseID: row,
      draft: SetEntryDraft(weightKg: 100, reps: 8), at: day(-3))
    try f.logger.setSessionExerciseMachine(rowID: row, machineID: cybex)
    _ = try f.logger.logSet(
      sessionID: session, exerciseID: f.press, machineID: cybex, sessionExerciseID: row,
      draft: SetEntryDraft(weightKg: 80, reps: 8), at: day(-3).addingTimeInterval(300))
    try f.logger.finishSession(session, at: day(-3).addingTimeInterval(3_600))

    #expect(try f.shortcuts.repeatPlan(of: session).items.map(\.machineID) == [cybex])
  }

  /// Review Focus: removed equipment stays removed.
  @Test("An archived machine is not revived; the movement stays and asks for one")
  func archivedMachineNotRevived() throws {
    let f = try fixture()
    let gym = try f.gyms.createGym(name: "Home", now: now)
    let hammer = try f.gyms.createMachine(at: gym, name: "Leg Press", now: now)
    let past = try workout(f, gym: gym, at: day(-8), [(f.press, hammer, [(100, 8)])])
    try f.gyms.archiveMachine(hammer)

    let plan = try f.shortcuts.repeatPlan(of: past)

    #expect(plan.items.map(\.exerciseID) == [f.press])
    #expect(plan.items[0].machineID == nil)
    #expect(plan.items[0].machineName == nil)
    #expect(plan.gymID == gym)
  }

  @Test("An archived gym is not revived, nor its machines")
  func archivedGymNotRevived() throws {
    let f = try fixture()
    let gym = try f.gyms.createGym(name: "Old Gym", now: now)
    let hammer = try f.gyms.createMachine(at: gym, name: "Leg Press", now: now)
    let past = try workout(f, gym: gym, at: day(-8), [(f.press, hammer, [(100, 8)])])
    try f.gyms.archiveGym(gym)

    let plan = try f.shortcuts.repeatPlan(of: past)

    #expect(plan.gymID == nil)
    #expect(plan.items[0].machineID == nil)
  }

  @Test("Repeating a workout that does not exist is reported")
  func unknownSession() throws {
    let f = try fixture()
    #expect(throws: LoggerStoreError.sessionNotFound) {
      try f.shortcuts.repeatPlan(of: SessionID())
    }
  }
}
