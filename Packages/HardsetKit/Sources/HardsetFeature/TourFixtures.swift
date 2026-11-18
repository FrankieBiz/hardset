import Foundation
import GRDB
import HardsetCore
import HardsetStore

/// The staged app the first-launch tour shows: a gym called "Downtown" with three machines, twelve
/// finished workouts of history (three of them in the last seven days) and, for the live stage, a
/// workout in progress with two movements and three logged sets.
///
/// Nothing here is typed in as a result. The data goes through the same write path the app uses,
/// a `SessionCoordinator` with an injected clock, so the records, the week's volume, "Last time"
/// and every prefill a screen shows are what the engine produces from these sets. A tour built on
/// invented figures would demonstrate something the product does not do.
///
/// The environment is an in-memory database migrated exactly as the app's is, so it never touches
/// the lifter's own data. Every date derives from `now`, so a test that passes a fixed instant gets
/// the same data every time.
@MainActor
public enum TourFixtures {
  /// The gym every staged screen is at.
  public static let gymName = "Downtown"

  /// How far the staging has gone: the start screen's world, or a workout already under way.
  public enum Stage: Sendable {
    /// History only, with no workout open: what the Train tab shows before a lifter starts.
    case start
    /// History plus an open workout: two movements, three logged sets and sets still to log.
    case liveSession
  }

  /// A staged app and the pieces a screen or a test needs to reach into it.
  public struct Staged {
    public let environment: HardsetEnvironment
    /// The in-memory database behind `environment`, for a test that reads it directly.
    public let database: any DatabaseWriter
    public let gymID: GymID
    public let gymName: String
    /// The gym's three machines, in the order they were created.
    public let machines: [MachineRecord]
    /// The open workout, reopened the way a relaunch reopens one, so any set a lifter logs in the
    /// tour is stamped with the real clock. `nil` at `.start`.
    public let liveSession: SessionCoordinator?
  }

  /// Why a fixture could not be built. A fixture that quietly built less than it promised would
  /// leave a tour screen empty, so every failed step is thrown with its reason.
  public struct FixtureError: Error, CustomStringConvertible {
    public let description: String
  }

  /// Builds the staged app.
  ///
  /// - Parameters:
  ///   - now: The instant the staged world treats as the present. The history lies before it. Pass
  ///     the real current date for the tour; a test passes a fixed instant at or before the real
  ///     clock, because the open workout is reopened with the real clock.
  ///   - unit: The unit the lifter reads. The loads and the machines' steps are written in round
  ///     numbers of it, so a lifter in pounds sees 225 and 20 lb steps, not 231.49 and 22.05; they
  ///     are stored in kilograms like every set.
  public static func make(
    stage: Stage, now: Date = Date(), unit: WeightUnit = .kilograms
  ) throws -> Staged {
    var configuration = Configuration()
    // As the app's own database is opened: required for the schema's cascades to fire.
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)

    let environment = HardsetEnvironment(database: queue)
    let day: TimeInterval = 86_400
    let beginning = now.addingTimeInterval(-40 * day)
    try environment.catalog.seed(now: beginning)
    let gymID = try environment.gyms.createGym(name: gymName, now: beginning)

    var machineIDs: [MachineID] = []
    for machine in machineSpecs {
      machineIDs.append(
        try environment.gyms.createMachine(
          at: gymID, name: machine.name, brand: machine.brand,
          stackIncrementKg: unit.toKilograms(machine.step(in: unit)), now: beginning))
    }
    let stored = try environment.gyms.machines(at: gymID)
    let machines = machineIDs.compactMap { id in stored.first { $0.id == id } }
    guard machines.count == machineSpecs.count else {
      throw FixtureError(description: "The gym's machines were not all saved.")
    }

    // One mutable instant that the coordinator reads as "now", advanced between sets, so each set
    // is stamped where it belongs in the workout.
    var current = beginning
    let clock: () -> Date = { current }

    func perform(_ lifts: [Lift], in coordinator: SessionCoordinator) throws {
      for lift in lifts {
        let machine = machines[lift.machine]
        guard
          let entry = try environment.catalog.search(lift.movement)
            .first(where: { $0.name == lift.movement })
        else {
          throw FixtureError(description: "The catalogue has no movement named \(lift.movement).")
        }
        let added = coordinator.addExercise(
          entry, machineID: machine.id, machineName: machine.displayName,
          machineIncrementKg: machine.stackIncrementKg, plannedSets: lift.planned)
        guard added else {
          throw FixtureError(description: "\(lift.movement) could not be added to the workout.")
        }
        let index = coordinator.exercises.count - 1
        for (slotIndex, set) in lift.logged.enumerated() {
          coordinator.exercises[index].slots[slotIndex].draft = SetEntryDraft(
            weightKg: unit.toKilograms(set.load.in(unit)), reps: set.reps)
          current = current.addingTimeInterval(180)
          let state = coordinator.exercises[index]
          let logged = coordinator.logSet(slotID: state.slots[slotIndex].id, inExercise: state.id)
          guard logged else {
            throw FixtureError(description: "A set of \(lift.movement) could not be logged.")
          }
        }
      }
    }

    // Oldest first, so each workout's prefill and records come from the ones before it.
    for workout in pastWorkouts {
      current = now.addingTimeInterval(-workout.daysAgo * day)
      let coordinator = try SessionCoordinator.start(
        store: environment.logger, gymID: gymID, plan: [], now: clock)
      try perform(workout.lifts, in: coordinator)
      current = current.addingTimeInterval(120)
      try coordinator.finish()
    }

    var live: SessionCoordinator?
    if stage == .liveSession {
      current = now.addingTimeInterval(-24 * 60)
      let seeding = try SessionCoordinator.start(
        store: environment.logger, gymID: gymID, plan: [], now: clock)
      try perform(liveLifts, in: seeding)
      // Reopened as a relaunch would, with the real clock from here on, so the lifter's own taps
      // in the tour are not stamped with the frozen staging instant.
      guard let resumed = try SessionCoordinator.resume(store: environment.logger) else {
        throw FixtureError(description: "The open workout could not be reopened.")
      }
      live = resumed
    }

    return Staged(
      environment: environment, database: queue, gymID: gymID, gymName: gymName,
      machines: machines, liveSession: live)
  }

  // MARK: - The staged world

  /// A load written once in each unit, in round numbers of that unit, so what the tour shows reads
  /// like a lifter's own training whichever unit they use.
  private struct Load {
    let kg: Double
    let lb: Double

    func `in`(_ unit: WeightUnit) -> Double {
      switch unit {
      case .kilograms: kg
      case .pounds: lb
      }
    }
  }

  private struct MachineSpec {
    let name: String
    let brand: String
    let step: Load

    func step(in unit: WeightUnit) -> Double { step.in(unit) }
  }

  /// One movement in a workout: how many sets it plans and the sets actually logged.
  private struct Lift {
    let movement: String
    /// Index into the gym's machines.
    let machine: Int
    let planned: Int
    let logged: [(load: Load, reps: Int)]
  }

  private struct Workout {
    let daysAgo: Double
    let lifts: [Lift]
  }

  /// Three machines the catalogue has a movement for, each with the stack step a gym machine has.
  private static let machineSpecs: [MachineSpec] = [
    MachineSpec(name: "Leg Press", brand: "Hammer Strength", step: Load(kg: 10, lb: 20)),
    MachineSpec(name: "Chest Press", brand: "Life Fitness", step: Load(kg: 5, lb: 10)),
    MachineSpec(name: "Lat Pulldown", brand: "Cybex", step: Load(kg: 5, lb: 10)),
  ]

  private static let legPress = 0
  private static let chestPress = 1
  private static let latPulldown = 2

  private static func threeSets(_ load: Load) -> [(load: Load, reps: Int)] {
    [(load, 10), (load, 10), (load, 9)]
  }

  private static func lift(_ movement: String, _ machine: Int, _ load: Load) -> Lift {
    Lift(movement: movement, machine: machine, planned: 3, logged: threeSets(load))
  }

  private static let legPressLoad = Load(kg: 100, lb: 225)
  private static let legPressRaised = Load(kg: 105, lb: 235)
  private static let chestPressLoad = Load(kg: 50, lb: 110)
  private static let latPulldownLoad = Load(kg: 45, lb: 100)

  /// Twelve finished workouts, three of them in the last seven days. They rotate through the three
  /// machines at steady weights, and the newest raises the leg press, so the engine finds a record
  /// in it rather than the fixture saying so.
  private static let pastWorkouts: [Workout] = {
    let days: [Double] = [38, 35, 31, 28, 24, 21, 17, 14, 10, 6, 3, 1]
    return days.enumerated().map { index, daysAgo in
      let isNewest = index == days.count - 1
      let leg = isNewest ? legPressRaised : legPressLoad
      let lifts: [Lift]
      switch index % 3 {
      case 0:
        lifts = [lift("Leg Press", legPress, leg), lift("Chest Press", chestPress, chestPressLoad)]
      case 1:
        lifts = [
          lift("Lat Pulldown", latPulldown, latPulldownLoad),
          lift("Chest Press", chestPress, chestPressLoad),
        ]
      default:
        lifts = [lift("Leg Press", legPress, leg), lift("Lat Pulldown", latPulldown, latPulldownLoad)]
      }
      return Workout(daysAgo: daysAgo, lifts: lifts)
    }
  }()

  /// The open workout: two movements of three planned sets, two sets logged on the first and one
  /// on the second, so there is a next set waiting for the tour to log.
  private static let liveLifts: [Lift] = [
    Lift(
      movement: "Leg Press", machine: legPress, planned: 3,
      logged: [(legPressRaised, 10), (legPressRaised, 10)]),
    Lift(
      movement: "Chest Press", machine: chestPress, planned: 3,
      logged: [(Load(kg: 55, lb: 120), 10)]),
  ]
}
