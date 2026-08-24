import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

/// The chain that has to hold for per-machine tracking to be reachable at all: a session knows its
/// gym, the gym is preselected from behaviour, and the machine survives a restart.
@Suite("A session knows where it is")
@MainActor
struct GymSelectionTests {
  let now = Date(timeIntervalSince1970: 18_000_000)

  private func fixture() throws -> (LoggerStore, GymStore, ExerciseID) {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let database = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(database)
    let exercise = ExerciseID()
    try database.write { db in
      try Exercise.insert { Exercise.Draft(id: exercise.rawValue, name: "Leg Press") }.execute(db)
    }
    return (LoggerStore(database: database), GymStore(database: database), exercise)
  }

  @Test("The gym survives a recovery, so a resumed workout offers the same equipment")
  func gymSurvivesResume() throws {
    let (logger, gyms, exercise) = try fixture()
    let gym = try gyms.createGym(name: "Barbell Club", now: now)
    let live = try SessionCoordinator.start(
      store: logger, gymID: gym,
      plan: [PlannedExercise(exerciseID: exercise, exerciseName: "Leg Press", plannedSets: 1)],
      now: { self.now }
    )
    #expect(live.gymID == gym)

    let recovered = try #require(try SessionCoordinator.resume(store: logger, now: { self.now }))
    #expect(recovered.gymID == gym)
  }

  @Test("The next workout is preselected to the last gym actually trained at")
  func lastUsedGymIsLearnedFromSessions() throws {
    let (logger, gyms, _) = try fixture()
    let home = try gyms.createGym(name: "Home", now: now)
    let club = try gyms.createGym(name: "Club", now: now)

    #expect(try gyms.lastUsedGym() == nil, "nothing logged yet, so nothing to assume")

    let first = try logger.startSession(gymID: home, at: now)
    try logger.finishSession(first, at: now.addingTimeInterval(3600))
    #expect(try gyms.lastUsedGym() == home)

    let second = try logger.startSession(gymID: club, at: now.addingTimeInterval(86_400))
    try logger.finishSession(second, at: now.addingTimeInterval(90_000))
    #expect(try gyms.lastUsedGym() == club)
  }

  @Test("A session with no gym does not overwrite the last known one")
  func unrecordedGymIsNotAPreference() throws {
    let (logger, gyms, _) = try fixture()
    let club = try gyms.createGym(name: "Club", now: now)
    let atClub = try logger.startSession(gymID: club, at: now)
    try logger.finishSession(atClub, at: now.addingTimeInterval(3600))

    // Travelling, hotel gym, nothing recorded.
    let away = try logger.startSession(at: now.addingTimeInterval(86_400))
    try logger.finishSession(away, at: now.addingTimeInterval(90_000))

    #expect(try gyms.lastUsedGym() == club)
  }

  @Test("An archived gym is not offered back")
  func archivedGymIsNotPreselected() throws {
    let (logger, gyms, _) = try fixture()
    let club = try gyms.createGym(name: "Club", now: now)
    let session = try logger.startSession(gymID: club, at: now)
    try logger.finishSession(session, at: now.addingTimeInterval(3600))
    try gyms.archiveGym(club)

    // Preselecting it would open a machine picker whose gym no longer exists to the user.
    #expect(try gyms.lastUsedGym() == nil)
  }

  @Test("Choosing a machine mid-workout is what lands machineID on the set")
  func machineChosenMidWorkoutIsRecorded() throws {
    let (logger, gyms, exercise) = try fixture()
    let gym = try gyms.createGym(name: "Club", now: now)
    let machine = try gyms.createMachine(
      at: gym, name: "Hammer Strength Leg Press", stackIncrementKg: 10, now: now
    )
    let live = try SessionCoordinator.start(
      store: logger, gymID: gym,
      plan: [PlannedExercise(exerciseID: exercise, exerciseName: "Leg Press", plannedSets: 1)],
      now: { self.now }
    )
    // Nothing is selected until the lifter says so — the app does not guess which unit they used.
    #expect(live.exercises[0].machineID == nil)

    #expect(
      live.changeMachine(
        to: machine, machineName: "Hammer Strength Leg Press", inExercise: live.exercises[0].id
      )
    )
    live.exercises[0].slots[0].draft = SetEntryDraft(weightKg: 100, reps: 8)
    #expect(live.logSet(slotID: live.exercises[0].slots[0].id, inExercise: live.exercises[0].id))

    // The whole differentiator in one assertion: the set is attributed to a physical machine.
    let stored = try logger.sets(in: live.sessionID)
    #expect(stored.count == 1)
    #expect(stored[0].machineID == machine)
    // And the picker will offer it first next time, because it is now the most recent.
    #expect(try gyms.recentMachines(for: exercise, at: gym).map(\.id) == [machine])
  }
}
