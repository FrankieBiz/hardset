import Foundation
import GRDB
import HardsetCore
import Testing

@testable import HardsetStore

/// The two shapes the logger was missing, through storage.
///
/// The Core tests cover the rules. These cover the hops that this codebase actually gets wrong:
/// a field the store carries and a caller forgets, and a query that quietly includes rows it
/// should not.
@Suite("Supersets and drops survive the database")
struct SupersetAndDropStoreTests {
  let now = Date(timeIntervalSince1970: 12_000_000)

  private func fixture() throws -> (any DatabaseWriter, LoggerStore, VolumeStore) {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    try CatalogSeeder(database: queue).seed(now: now)
    return (queue, LoggerStore(database: queue), VolumeStore(database: queue))
  }

  private func progression(_ db: any DatabaseWriter) -> ProgressionStore {
    ProgressionStore(database: db)
  }

  private func history(_ db: any DatabaseWriter) -> HistoryStore {
    HistoryStore(database: db)
  }

  private func exercise(_ db: any DatabaseWriter, _ slug: String) throws -> ExerciseID {
    let row = try db.read { d in try Exercise.where { $0.catalogSlug.eq(slug) }.fetchOne(d) }
    return ExerciseID(rawValue: try #require(row).id)
  }

  // MARK: - Drops

  @Test("A drop is written as a drop and read back as one")
  func dropRoundTrips() throws {
    let (db, store, _) = try fixture()
    let press = try exercise(db, "chest-press-machine")
    let session = try store.startSession(at: now)

    _ = try store.logSet(
      sessionID: session, exerciseID: press,
      draft: SetEntryDraft(weightKg: 80, reps: 8), setOrdinal: 0, kind: .working, at: now
    )
    _ = try store.logSet(
      sessionID: session, exerciseID: press,
      draft: SetEntryDraft(weightKg: 60, reps: 6), setOrdinal: 1, kind: .drop, at: now
    )

    let sets = try store.sets(in: session)
    #expect(sets.map(\.kind) == [.working, .drop])
    // The legacy flag stays false, so nothing that filters on warm-ups changes meaning.
    #expect(sets.allSatisfy { !$0.isWarmup })
  }

  /// The most dangerous of the lot. A drop is the lightest load of the session by construction,
  /// so if it reaches the prefill snapshot the opening row gets lighter every hard session.
  @Test("A drop never becomes next session's suggested load")
  func dropsDoNotPollutePrefill() throws {
    let (db, store, _) = try fixture()
    let press = try exercise(db, "chest-press-machine")
    let session = try store.startSession(at: now)

    _ = try store.logSet(
      sessionID: session, exerciseID: press,
      draft: SetEntryDraft(weightKg: 80, reps: 8), setOrdinal: 0, kind: .working, at: now
    )
    _ = try store.logSet(
      sessionID: session, exerciseID: press,
      draft: SetEntryDraft(weightKg: 40, reps: 12), setOrdinal: 1, kind: .drop,
      at: now.addingTimeInterval(30)
    )
    try store.finishSession(session, at: now.addingTimeInterval(600))

    let snapshot = try store.priorPerformanceSnapshot(
      for: [ProgressionKey(exerciseID: press, machineID: nil)],
      asOf: now.addingTimeInterval(86_400)
    )
    let prior = try #require(snapshot.prior(for: ProgressionKey(exerciseID: press, machineID: nil)))
    #expect(prior.lastSets.map(\.weightKg) == [80])
    #expect(prior.heaviestSet?.weightKg == 80)
  }

  @Test("A drop is not a record candidate and not a benchmark")
  func dropsAreNotRecords() throws {
    let (db, store, _) = try fixture()
    let press = try exercise(db, "chest-press-machine")
    let session = try store.startSession(at: now)

    _ = try store.logSet(
      sessionID: session, exerciseID: press,
      draft: SetEntryDraft(weightKg: 80, reps: 8), setOrdinal: 0, kind: .working, at: now
    )
    _ = try store.logSet(
      sessionID: session, exerciseID: press,
      draft: SetEntryDraft(weightKg: 50, reps: 20), setOrdinal: 1, kind: .drop, at: now
    )

    let completed = try store.completedSets(for: ProgressionKey(exerciseID: press, machineID: nil))
    #expect(completed.count == 1)
    #expect(completed.first?.weightKg == 80)
  }

  @Test("The chart plots the working sets, not the bottom of a chain")
  func dropsAreNotProgressionSamples() throws {
    let (db, store, _) = try fixture()
    let press = try exercise(db, "chest-press-machine")
    let session = try store.startSession(at: now)

    _ = try store.logSet(
      sessionID: session, exerciseID: press,
      draft: SetEntryDraft(weightKg: 80, reps: 8), setOrdinal: 0, kind: .working, at: now
    )
    _ = try store.logSet(
      sessionID: session, exerciseID: press,
      draft: SetEntryDraft(weightKg: 40, reps: 15), setOrdinal: 1, kind: .drop, at: now
    )

    let samples = try progression(db).samples(for: press)
    #expect(samples.count == 1)
    #expect(samples.first?.weightKg == 80)
  }

  /// The counting convention, at the layer that reports a week.
  @Test("A set dropped twice credits one set, and all of its tonnage")
  func dropsCountOnceButLiftFully() throws {
    let (db, store, volume) = try fixture()
    let press = try exercise(db, "chest-press-machine")
    let session = try store.startSession(at: now)

    _ = try store.logSet(
      sessionID: session, exerciseID: press,
      draft: SetEntryDraft(weightKg: 100, reps: 10), setOrdinal: 0, kind: .working, at: now
    )
    for (ordinal, load) in [(1, 80.0), (2, 60.0)] {
      _ = try store.logSet(
        sessionID: session, exerciseID: press,
        draft: SetEntryDraft(weightKg: load, reps: 5), setOrdinal: ordinal, kind: .drop, at: now
      )
    }

    let countable = try volume.countableSets(in: session)
    let counted = countable.count { $0.kind.countsAsWorkingSet }
    #expect(countable.count == 3)
    #expect(counted == 1)

    try store.finishSession(session, at: now.addingTimeInterval(600))
    let summary = try #require(try history(db).recentSessions().first)
    #expect(summary.volume.workingSets == 1)
    #expect(summary.volume.dropSets == 2)
    // 100x10 + 80x5 + 60x5 -- every rep the lifter moved.
    #expect(summary.volume.volumeKg == 1_700)
    #expect(summary.volume.reps == 20)
  }

  @MainActor
  @Test("A drop comes back from a crash as a drop, not promoted to a working set")
  func recoveryKeepsDropKind() throws {
    let (db, store, _) = try fixture()
    let press = try exercise(db, "chest-press-machine")

    let opened = try SessionCoordinator.start(
      store: store,
      plan: [PlannedExercise(exerciseID: press, exerciseName: "Chest Press")],
      now: { self.now }
    )
    let stateID = opened.exercises[0].id
    opened.exercises[0].slots[0].draft = SetEntryDraft(weightKg: 80, reps: 8)
    #expect(opened.logSet(slotID: opened.exercises[0].slots[0].id, inExercise: stateID))

    let dropID = try #require(opened.addDropSet(inExercise: stateID))
    let dropIndex = try #require(opened.exercises[0].slots.firstIndex { $0.id == dropID })
    opened.exercises[0].slots[dropIndex].draft.reps = 12
    #expect(opened.logSet(slotID: dropID, inExercise: stateID))

    let recovered = try #require(try SessionCoordinator.resume(store: store, now: { self.now }))
    #expect(recovered.exercises[0].slots.map(\.kind) == [.working, .drop])
    // And the count it reports is still one, after the round trip.
    #expect(recovered.exercises[0].workingSetCount == 1)
  }

  // MARK: - Supersets

  @MainActor
  @Test("Pairing two movements persists, and survives a crash")
  func supersetSurvivesRecovery() throws {
    let (db, store, _) = try fixture()
    let press = try exercise(db, "chest-press-machine")
    let row = try exercise(db, "seated-cable-row")

    let opened = try SessionCoordinator.start(
      store: store,
      plan: [
        PlannedExercise(exerciseID: press, exerciseName: "Chest Press"),
        PlannedExercise(exerciseID: row, exerciseName: "Cable Row"),
      ],
      now: { self.now }
    )
    #expect(opened.joinSupersetWithNext(exerciseStateID: opened.exercises[0].id))
    let group = try #require(opened.exercises[0].supersetGroup)
    #expect(opened.exercises[1].supersetGroup == group)

    let recovered = try #require(try SessionCoordinator.resume(store: store, now: { self.now }))
    #expect(recovered.exercises[0].supersetGroup == group)
    #expect(recovered.exercises[1].supersetGroup == group)
    #expect(
      SupersetGrouping.letter(for: recovered.exercises[1], in: recovered.exercises) == "B"
    )
  }

  @MainActor
  @Test("A third movement joins the pair rather than starting a second group")
  func joiningExtendsTheGroup() throws {
    let (db, store, _) = try fixture()
    let plan = ["chest-press-machine", "seated-cable-row", "lat-pulldown"].map {
      try! exercise(db, $0)
    }

    let opened = try SessionCoordinator.start(
      store: store,
      plan: plan.map { PlannedExercise(exerciseID: $0, exerciseName: "Movement") },
      now: { self.now }
    )
    #expect(opened.joinSupersetWithNext(exerciseStateID: opened.exercises[0].id))
    #expect(opened.joinSupersetWithNext(exerciseStateID: opened.exercises[1].id))

    let groups = Set(opened.exercises.compactMap(\.supersetGroup))
    #expect(groups.count == 1)
    #expect(opened.exercises.allSatisfy { $0.supersetGroup != nil })
  }

  /// A group of one is not a superset, and leaving the number behind would keep the survivor
  /// lettered while the rest rule waited for a round that can never complete.
  @MainActor
  @Test("Leaving a pair ungroups the movement left behind")
  func leavingAPairDissolvesIt() throws {
    let (db, store, _) = try fixture()
    let press = try exercise(db, "chest-press-machine")
    let row = try exercise(db, "seated-cable-row")

    let opened = try SessionCoordinator.start(
      store: store,
      plan: [
        PlannedExercise(exerciseID: press, exerciseName: "Chest Press"),
        PlannedExercise(exerciseID: row, exerciseName: "Cable Row"),
      ],
      now: { self.now }
    )
    #expect(opened.joinSupersetWithNext(exerciseStateID: opened.exercises[0].id))
    #expect(opened.leaveSuperset(exerciseStateID: opened.exercises[0].id))

    #expect(opened.exercises.allSatisfy { $0.supersetGroup == nil })

    // And the database agrees, so a crash does not resurrect a half-group.
    let recovered = try #require(try SessionCoordinator.resume(store: store, now: { self.now }))
    #expect(recovered.exercises.allSatisfy { $0.supersetGroup == nil })
  }

  @MainActor
  @Test("The last movement has nothing to pair with")
  func lastMovementCannotJoin() throws {
    let (db, store, _) = try fixture()
    let press = try exercise(db, "chest-press-machine")

    let opened = try SessionCoordinator.start(
      store: store,
      plan: [PlannedExercise(exerciseID: press, exerciseName: "Chest Press")],
      now: { self.now }
    )
    #expect(!opened.joinSupersetWithNext(exerciseStateID: opened.exercises[0].id))
    #expect(opened.exercises[0].supersetGroup == nil)
  }

  /// Grouping changes rest timing and nothing else. If it ever changed what was recorded, it
  /// would be a prescription rather than an arrangement.
  @MainActor
  @Test("A superset records exactly what the same sets record apart")
  func supersetsChangeNoRecord() throws {
    let (db, store, volume) = try fixture()
    let press = try exercise(db, "chest-press-machine")
    let row = try exercise(db, "seated-cable-row")

    let opened = try SessionCoordinator.start(
      store: store,
      plan: [
        PlannedExercise(exerciseID: press, exerciseName: "Chest Press"),
        PlannedExercise(exerciseID: row, exerciseName: "Cable Row"),
      ],
      now: { self.now }
    )
    #expect(opened.joinSupersetWithNext(exerciseStateID: opened.exercises[0].id))

    for index in 0..<2 {
      opened.exercises[index].slots[0].draft = SetEntryDraft(weightKg: 60, reps: 10)
      #expect(
        opened.logSet(
          slotID: opened.exercises[index].slots[0].id,
          inExercise: opened.exercises[index].id
        )
      )
    }

    let sets = try store.sets(in: opened.sessionID)
    #expect(sets.count == 2)
    #expect(sets.allSatisfy { $0.kind == .working })
    let countable = try volume.countableSets(in: opened.sessionID)
    #expect(countable.count { $0.kind.countsAsWorkingSet } == 2)
  }
}

/// Numbers the suite could not see, found by driving the screen with a seeded database.
///
/// Both are the same mistake in two places: counting written *rows* where the question is how many
/// *sets* were performed. They only diverge once a drop can be written, which is why nothing
/// caught them before.
@Suite("The counts on screen agree with the counting convention")
struct DropSetCountingSurfaceTests {
  let now = Date(timeIntervalSince1970: 12_000_000)

  private func fixture() throws -> (any DatabaseWriter, LoggerStore) {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    try CatalogSeeder(database: queue).seed(now: now)
    return (queue, LoggerStore(database: queue))
  }

  /// The live workout bar. A lifter who dropped twice watched it jump from three sets to five.
  @MainActor
  @Test("The workout bar counts sets, not written rows")
  func loggedSetCountExcludesDrops() throws {
    let (db, store) = try fixture()
    let row = try db.read { d in try Exercise.where { $0.catalogSlug.eq("leg-press") }.fetchOne(d) }
    let press = ExerciseID(rawValue: try #require(row).id)

    let opened = try SessionCoordinator.start(
      store: store,
      plan: [PlannedExercise(exerciseID: press, exerciseName: "Leg Press")],
      now: { self.now }
    )
    let stateID = opened.exercises[0].id
    opened.exercises[0].slots[0].draft = SetEntryDraft(weightKg: 200, reps: 10)
    #expect(opened.logSet(slotID: opened.exercises[0].slots[0].id, inExercise: stateID))

    for load in [160.0, 120.0] {
      let dropID = try #require(opened.addDropSet(inExercise: stateID))
      let index = try #require(opened.exercises[0].slots.firstIndex { $0.id == dropID })
      opened.exercises[0].slots[index].draft = SetEntryDraft(weightKg: load, reps: 6)
      #expect(opened.logSet(slotID: dropID, inExercise: stateID))
    }

    // Three rows written, one set performed.
    #expect(opened.exercises[0].loggedCount == 3)
    #expect(opened.loggedSetCount == 1)
    // And the session's own volume agrees, so the bar cannot contradict the summary.
    #expect(opened.outcome.volume.workingSets == 1)
    #expect(opened.outcome.volume.dropSets == 2)
  }
}
