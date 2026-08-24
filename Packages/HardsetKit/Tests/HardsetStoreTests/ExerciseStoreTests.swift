import Foundation
import GRDB
import HardsetCore
import Testing

@testable import HardsetStore

/// The lifter's own movements. Nothing outside `CatalogSeeder` ever inserted an `exercises` row, so
/// a movement the shipped 81-entry catalogue lacks could not be logged at all.
@Suite("A lifter can define their own movement")
struct ExerciseStoreTests {
  let now = Date(timeIntervalSince1970: 12_000_000)

  private func fixture() throws -> (any DatabaseWriter, ExerciseStore, LoggerStore, VolumeStore) {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    try CatalogSeeder(database: queue).seed(now: now)
    return (
      queue, ExerciseStore(database: queue), LoggerStore(database: queue),
      VolumeStore(database: queue)
    )
  }

  @Test("A created movement is stored as the lifter's own, not as curated")
  func createdMovementIsNotCurated() throws {
    let (db, store, _, _) = try fixture()
    let id = try store.createExercise(
      name: "Panatta chest press", modality: .machine, primaryMuscle: .chest, now: now
    )

    let row = try #require(try db.read { d in
      try Exercise.where { $0.id.eq(id.rawValue) }.fetchOne(d)
    })
    #expect(row.name == "Panatta chest press")
    #expect(row.isCurated == false)
    // No slug and no curated name: nothing shipped this row, so no catalogue correction owns it.
    #expect(row.catalogSlug == nil)
    #expect(row.curatedName.isEmpty)
  }

  @Test("The name is trimmed and a blank name is refused")
  func blankNameRefused() throws {
    let (_, store, _, _) = try fixture()
    let id = try store.createExercise(
      name: "  Reverse hyper  ", modality: nil, primaryMuscle: .glutes, now: now
    )
    #expect(try store.exists(id) == true)

    #expect(throws: ExerciseStoreError.blankName) {
      _ = try store.createExercise(name: "   ", modality: nil, primaryMuscle: .chest, now: now)
    }
  }

  /// The whole point of asking for a muscle: the sets have to actually count.
  @Test("Sets on a created movement are attributed, not merely counted")
  func createdMovementIsAttributed() throws {
    let (_, store, logger, volume) = try fixture()
    let id = try store.createExercise(
      name: "Panatta chest press", modality: .machine, primaryMuscle: .chest, now: now
    )

    let session = try logger.startSession(at: now)
    for ordinal in 0..<3 {
      _ = try logger.logSet(
        sessionID: session, exerciseID: id,
        draft: SetEntryDraft(weightKg: 60, reps: 10), setOrdinal: ordinal,
        at: now.addingTimeInterval(Double(ordinal) * 120)
      )
    }
    try logger.finishSession(session, at: now.addingTimeInterval(600))

    let report = try volume.report(for: session)
    #expect(report.hardSets == 3)
    // A direct credit, so a full set each -- not a lower bound with everything unaccounted for.
    #expect(report.sets(for: .chest) == 3)
    #expect(report.unattributedHardSets == 0)
    #expect(!report.isLowerBound)
  }

  /// Contrast: a row with no attribution is honest but far less useful, which is why the muscle is
  /// required rather than optional.
  @Test("A row with no attribution makes the week a lower bound instead")
  func unattributedRowIsALowerBound() throws {
    let (db, _, logger, volume) = try fixture()
    let orphan = ExerciseID()
    try db.write { d in
      try Exercise.insert { Exercise.Draft(id: orphan.rawValue, name: "Contraption") }.execute(d)
    }

    let session = try logger.startSession(at: now)
    _ = try logger.logSet(
      sessionID: session, exerciseID: orphan,
      draft: SetEntryDraft(weightKg: 60, reps: 10), setOrdinal: 0, at: now
    )
    try logger.finishSession(session, at: now.addingTimeInterval(60))

    let report = try volume.report(for: session)
    #expect(report.unattributedHardSets == 1)
    #expect(report.isLowerBound)
  }

  @Test("The lifter's attribution is marked as theirs, not as a citation")
  func attributionIsMarkedAsTheirs() throws {
    let (db, store, _, _) = try fixture()
    let id = try store.createExercise(
      name: "Panatta chest press", modality: .machine, primaryMuscle: .chest, now: now
    )
    let row = try #require(try db.read { d in
      try Exercise.where { $0.id.eq(id.rawValue) }.fetchOne(d)
    })
    let entry = CatalogEntry(row: row)
    let credited = try #require(entry.creditedMuscles.first)
    #expect(credited.key == MuscleKey(.chest))
    #expect(credited.role == .direct)
    // Labelled as one person's judgement rather than as literature.
    #expect(credited.certainty == .low)
    #expect(credited.sourceID == ExerciseStore.userSourceID)
    #expect(credited.citation == nil)
    // And it is readable back as attributed at all, which is what `isUnattributed` gates.
    #expect(!entry.isUnattributed)
  }

  @Test("A movement the lifter owns can be renamed; a curated one cannot")
  func renameRules() throws {
    let (db, store, _, _) = try fixture()
    let mine = try store.createExercise(
      name: "Panatta chest press", modality: .machine, primaryMuscle: .chest, now: now
    )
    try store.rename(mine, to: "Panatta incline press")
    #expect(try store.name(of: mine) == "Panatta incline press")

    let curated = try #require(try db.read { d in
      try Exercise.where { $0.catalogSlug.eq("barbell-bench-press") }.fetchOne(d)
    })
    #expect(throws: ExerciseStoreError.curatedRowIsNotEditable) {
      try store.rename(ExerciseID(rawValue: curated.id), to: "My bench")
    }
  }

  @Test("Renaming something that does not exist is refused rather than silently doing nothing")
  func renameMissingIsRefused() throws {
    let (_, store, _, _) = try fixture()
    #expect(throws: ExerciseStoreError.notFound) {
      try store.rename(ExerciseID(), to: "Anything")
    }
  }

  /// Archiving means "stop offering me this", never "pretend I did not do it".
  @Test("Retiring a movement keeps the sets already logged against it")
  func archivingKeepsLoggedSets() throws {
    let (_, store, logger, volume) = try fixture()
    let id = try store.createExercise(
      name: "Panatta chest press", modality: .machine, primaryMuscle: .chest, now: now
    )
    let session = try logger.startSession(at: now)
    _ = try logger.logSet(
      sessionID: session, exerciseID: id,
      draft: SetEntryDraft(weightKg: 60, reps: 10), setOrdinal: 0, at: now
    )
    try logger.finishSession(session, at: now.addingTimeInterval(60))

    try store.setArchived(true, for: id)

    let report = try volume.report(for: session)
    // Still three-quarters of a fact: the set happened and is counted.
    #expect(report.hardSets == 1)
    // And its attribution is now withheld rather than invented, which is the documented behaviour
    // for an archived row.
    #expect(report.unattributedHardSets == 1)
    #expect(try logger.sets(in: session).count == 1)
  }
}
