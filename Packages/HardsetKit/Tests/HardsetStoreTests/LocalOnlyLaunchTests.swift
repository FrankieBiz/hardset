import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

/// The app must open its database on a build that has no iCloud entitlement.
///
/// # The bug this pins
///
/// `HardsetDatabase.open` attached SQLiteData's sync metadatabase unconditionally.
/// `attachMetadatabase` resolves its container from the **iCloud entitlement** and throws
/// `SchemaError.noCloudKitContainer` when there is none — so on a build signed without it, `open()`
/// threw, `HardsetApp` recorded a store failure, and the app launched directly into
/// `StoreUnavailableView`: *"Can't open your training history."* Not a degraded app. No app.
///
/// That is precisely the build `Tools/generate_project.py --local` produces, and the only build a
/// free personal team can install, because iCloud and push are paid-membership capabilities. The
/// generator's own comment promised `--local` "costs exactly one thing: sync". It cost everything.
///
/// # Why nothing caught it
///
/// The host suite runs in a non-`.live` dependency context, where SQLiteData substitutes a
/// synthetic `"container"` and the attach always succeeds. The throw is reachable *only* from a
/// signed build on real hardware — so no amount of testing the real call could have found it, and
/// the first device launch the app ever had is what did.
///
/// Hence the injected `attachMetadatabase`: it is the only way to put this failure in front of a
/// test at all.
@Suite("The app opens without an iCloud container")
struct LocalOnlyLaunchTests {
  private struct NoCloudKitContainer: Error {}

  /// Mirrors what SQLiteData raises when the entitlement is absent.
  private static let refuseToAttach: @Sendable (Database, String?) throws -> Void = { _, _ in
    throw NoCloudKitContainer()
  }

  @Test("A database whose metadatabase cannot attach still opens")
  func opensWithoutContainer() throws {
    let database = try HardsetDatabase.open(attachMetadatabase: Self.refuseToAttach)
    // Reached at all means `open()` did not rethrow. Before the fix this line was unreachable.
    #expect(try database.read { try Gym.fetchAll($0) }.isEmpty)
  }

  /// Opening is not enough. The lifter has to be able to *train* into it — a store that opens and
  /// then refuses every write would show a working app that quietly loses the session.
  @Test("Everything a workout touches still works local-only")
  func writesWorkLocalOnly() throws {
    let database = try HardsetDatabase.open(attachMetadatabase: Self.refuseToAttach)
    let gyms = GymStore(database: database)
    let logger = LoggerStore(database: database)
    let now = Date(timeIntervalSince1970: 20_000_000)

    let exercise = ExerciseID()
    try database.write { db in
      try Exercise.insert { Exercise.Draft(id: exercise.rawValue, name: "Chest Press") }.execute(db)
    }

    let gym = try gyms.createGym(name: "PureGym Holborn", now: now)
    let machine = try gyms.createMachine(at: gym, name: "Hammer Chest Press", now: now)
    let session = try logger.startSession(gymID: gym, at: now)
    _ = try logger.logSet(
      sessionID: session, exerciseID: exercise, machineID: machine,
      draft: SetEntryDraft(weightKg: 80, reps: 8), isWarmup: false, at: now
    )
    try logger.finishSession(session, at: now.addingTimeInterval(3600))

    // The whole chain: a gym, a machine, a finished session, and a set keyed to that machine.
    #expect(try gyms.machines(at: gym).count == 1)
    #expect(try logger.sets(in: session).count == 1)
    #expect(try gyms.machineLibrary(at: gym).first?.workingSetCount == 1)
  }

  /// The normal path must be unchanged — a tolerated failure is worthless if it also swallows the
  /// success case.
  @Test("An attachable metadatabase is still attached")
  func attachesWhenAvailable() throws {
    let attached = LockIsolated(false)
    let database = try HardsetDatabase.open(attachMetadatabase: { db, id in
      attached.setValue(true)
      try db.attachMetadatabase(containerIdentifier: id)
    })
    #expect(attached.value, "The real attach must still be called when it can succeed.")
    #expect(try database.read { try Gym.fetchAll($0) }.isEmpty)
  }
}

/// Minimal box so the closure can report back without tripping `@Sendable` capture rules.
private final class LockIsolated<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: Value
  init(_ value: Value) { stored = value }
  var value: Value { lock.withLock { stored } }
  func setValue(_ value: Value) { lock.withLock { stored = value } }
}
