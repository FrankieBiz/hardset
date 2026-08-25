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

  // MARK: - Based on a movement it resembles

  /// A seeded curated movement that credits several muscles **and** cites something.
  ///
  /// Both halves are load-bearing. Only 26 of the 81 catalogue entries carry a citation at all --
  /// many are `anatomy` with none -- so `first { creditedMuscles.count > 2 }` lands on
  /// `Back Extension`, whose contributions cite nothing. A laundering test against that template
  /// would pass while proving nothing, because there was no evidence to launder.
  private func citingTemplate(in db: any DatabaseWriter) throws -> CatalogEntry {
    let seeded = try CatalogSeeder(database: db).selectableExercises()
    return try #require(
      seeded.first {
        $0.isCurated && $0.creditedMuscles.count > 2
          && $0.contributions.contains { $0.citation != nil }
      },
      "The catalogue must contain a multi-muscle, citing movement for these tests to mean anything."
    )
  }

  /// The under-count this fixes: a hand-typed movement credited one muscle while the curated row it
  /// is a variant of credits several, so every weekly figure it touched was quietly short.
  @Test("A movement based on a template inherits the template's muscles")
  func inheritsMusclesFromTemplate() throws {
    let (db, store, _, _) = try fixture()
    // Taken from the seeded catalogue rather than hand-built, so this exercises what ships.
    let template = try citingTemplate(in: db)

    let id = try store.createExercise(
      name: "Nautilus High Lever Row",
      modality: .machine,
      primaryMuscle: try #require(template.primaryMuscle.muscle),
      inheriting: template.contributions,
      now: now
    )

    let row = try #require(try db.read { d in
      try Exercise.where { $0.id.eq(id.rawValue) }.fetchOne(d)
    })
    let mine = CatalogEntry(row: row)
    #expect(mine.creditedMuscles.count == template.creditedMuscles.count)
    #expect(
      Set(mine.creditedMuscles.map(\.key)) == Set(template.creditedMuscles.map(\.key)),
      "The muscles are what carries over."
    )
    #expect(!mine.isUnattributed)
  }

  /// The rewrite is the store's job, not the sheet's, so no future caller can skip it. If this
  /// fails, the app is citing a trial for a machine the trial never looked at.
  @Test("An inherited movement never claims the template's evidence")
  func inheritedMovementNeverClaimsCuratedEvidence() throws {
    let (db, store, _, _) = try fixture()
    let template = try citingTemplate(in: db)
    // The template really does carry citations, or this test would prove nothing.
    #expect(template.contributions.contains { $0.citation != nil })

    let id = try store.createExercise(
      name: "Nautilus High Lever Row",
      modality: .machine,
      primaryMuscle: try #require(template.primaryMuscle.muscle),
      inheriting: template.contributions,
      now: now
    )
    let row = try #require(try db.read { d in
      try Exercise.where { $0.id.eq(id.rawValue) }.fetchOne(d)
    })

    for contribution in CatalogEntry(row: row).contributions {
      #expect(contribution.citation == nil)
      #expect(contribution.sourceID == ExerciseStore.userSourceID)
      #expect(contribution.certainty <= InheritedAttribution.ceiling)
    }
  }

  /// The sheet shows inherited muscles as rows that can be switched off. Switching one off has to
  /// mean it is not written -- otherwise the endorsement is theatre.
  @Test("A muscle the lifter switched off is not credited")
  func removedMuscleIsNotWritten() throws {
    let (db, store, _, _) = try fixture()
    let template = try citingTemplate(in: db)
    let primary = try #require(template.primaryMuscle.muscle)
    let dropped = try #require(
      template.creditedMuscles.first { $0.key != MuscleKey(primary) }
    ).key

    let id = try store.createExercise(
      name: "Nautilus High Lever Row",
      modality: .machine,
      primaryMuscle: primary,
      inheriting: template.contributions.filter { $0.key != dropped },
      now: now
    )
    let row = try #require(try db.read { d in
      try Exercise.where { $0.id.eq(id.rawValue) }.fetchOne(d)
    })
    #expect(!CatalogEntry(row: row).contributions.contains { $0.key == dropped })
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
