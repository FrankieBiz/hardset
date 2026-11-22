import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

@Suite("Seeding the catalogue is idempotent and non-destructive")
struct CatalogSeederTests {
  let now = Date(timeIntervalSince1970: 7_000_000)

  private func migratedDatabase() throws -> any DatabaseWriter {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return queue
  }

  private let sample = [
    CatalogExercise(
      id: "11111111-1111-5111-8111-111111111111",
      slug: "leg-press", name: "Leg Press", modality: .machine,
      primaryMuscle: .quadriceps,
      contributions: [
        .init(.quadriceps, role: .direct, certainty: .moderate, source: .anatomy),
        .init(.glutes, role: .indirect, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "22222222-2222-5222-8222-222222222222",
      slug: "pull-up", name: "Pull-up", modality: .bodyweight,
      primaryMuscle: .lats,
      contributions: [
        .init(.lats, role: .direct, certainty: .moderate, source: .anatomy),
        .init(.biceps, role: .indirect, certainty: .moderate, source: .anatomy),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .anatomy),
      ]
    ),
  ]

  @Test("A first seed inserts every entry")
  func firstSeedInserts() throws {
    let database = try migratedDatabase()
    let seeder = CatalogSeeder(database: database)
    #expect(try seeder.seed(sample, now: now) == 2)
    #expect(try seeder.selectableExercises().count == 2)
  }

  /// The reason ids are fixed literals: two devices seeding offline must converge, not duplicate.
  @Test("Seeding twice inserts nothing the second time")
  func seedIsIdempotent() throws {
    let database = try migratedDatabase()
    let seeder = CatalogSeeder(database: database)
    #expect(try seeder.seed(sample, now: now) == 2)
    #expect(try seeder.seed(sample, now: now) == 0)
    #expect(try seeder.selectableExercises().count == 2)
  }

  @Test("An unchanged catalogue performs no row updates", arguments: [false, true])
  func unchangedSeedDoesNotWrite(asynchronous: Bool) async throws {
    let database = try migratedDatabase()
    let seeder = CatalogSeeder(database: database)
    try seeder.seed(now: now)
    // Include user-owned changes in the no-write contract, not just pristine seed rows.
    try await database.write { db in
      try db.execute(sql: "UPDATE exercises SET name = 'My movement', notes = 'Keep', isArchived = 1")
      try db.execute(sql: "CREATE TABLE seedUpdates (id TEXT)")
      try db.execute(sql: "CREATE TRIGGER auditSeed AFTER UPDATE ON exercises BEGIN INSERT INTO seedUpdates VALUES (NEW.id); END")
    }
    let inserted: Int
    if asynchronous {
      inserted = try await seeder.loadCatalog(now: now)
    } else {
      inserted = try seeder.seed(now: now)
    }
    #expect(inserted == 0)
    let updates = try await database.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM seedUpdates")
    }
    #expect(updates == 0)
  }

  @Test("Each changed catalogue-owned field is repaired", arguments: [
    "name = 'Old name', curatedName = 'Old name'",
    "curatedName = 'Old name'", "catalogSlug = 'old-slug'", "isCurated = 0",
    "modality = 'old-modality'", "primaryMuscle = 'old-muscle'", "secondaryMusclesJSON = '[]'",
  ])
  func changedFieldIsRepaired(assignment: String) throws {
    let database = try migratedDatabase()
    let seeder = CatalogSeeder(database: database)
    try seeder.seed(sample, now: now)
    let expected = try database.read { db in try Exercise.order { $0.id }.fetchAll(db) }
    try database.write { db in
      try db.execute(sql: "UPDATE exercises SET \(assignment)")
    }
    #expect(try seeder.seed(sample, now: now) == 0)
    let actual = try database.read { db in try Exercise.order { $0.id }.fetchAll(db) }
    #expect(actual == expected)
  }

  /// A user's rename must survive every subsequent launch.
  @Test("Re-seeding does not overwrite a user's rename")
  func reseedPreservesRename() throws {
    let database = try migratedDatabase()
    let seeder = CatalogSeeder(database: database)
    try seeder.seed(sample, now: now)

    let id = UUID(uuidString: sample[0].id)!
    try database.write { db in
      try Exercise.where { $0.id.eq(id) }.update { $0.name = "Leg Press (angled)" }.execute(db)
    }

    try seeder.seed(sample, now: now)
    let entry = try #require(try seeder.selectableExercises().first { $0.id.rawValue == id })
    #expect(entry.name == "Leg Press (angled)")
    // Catalogue-owned fields are still refreshed.
    #expect(entry.primaryMuscle == MuscleKey(.quadriceps))
    #expect(entry.modality == .machine)
  }

  /// Archiving is how a user hides a movement. Re-seeding must not resurrect it.
  @Test("Re-seeding does not un-archive")
  func reseedPreservesArchive() throws {
    let database = try migratedDatabase()
    let seeder = CatalogSeeder(database: database)
    try seeder.seed(sample, now: now)

    let id = UUID(uuidString: sample[1].id)!
    try database.write { db in
      try Exercise.where { $0.id.eq(id) }.update { $0.isArchived = true }.execute(db)
    }

    try seeder.seed(sample, now: now)
    #expect(try seeder.selectableExercises().count == 1)
  }

  /// Roles have to survive storage, because the role IS the arithmetic: direct credits a set,
  /// indirect a half, stabiliser nothing.
  @Test("Attribution round-trips through the column with roles intact")
  func attributionRoundTrips() throws {
    let database = try migratedDatabase()
    let seeder = CatalogSeeder(database: database)
    try seeder.seed(sample, now: now)

    let pullUp = try #require(try seeder.selectableExercises().first { $0.slug == "pull-up" })
    #expect(pullUp.primaryMuscle == MuscleKey(.lats))
    #expect(pullUp.contributions.count == 3)
    #expect(pullUp.unreadableEntryCount == 0)

    // Grip is stabilising: present, and credited nothing.
    let forearms = try #require(pullUp.contributions.first { $0.key == MuscleKey(.forearms) })
    #expect(forearms.role == .stabilizer)
    #expect(forearms.setWeight == 0)

    // Credited muscles exclude it entirely.
    #expect(pullUp.creditedMuscles.map(\.key) == [MuscleKey(.lats), MuscleKey(.biceps)])
    #expect(pullUp.creditedMuscles.map(\.setWeight) == [1.0, 0.5])
  }

  @Test("Search is case- and diacritic-insensitive, and empty means everything")
  func searching() throws {
    let database = try migratedDatabase()
    let seeder = CatalogSeeder(database: database)
    try seeder.seed(sample, now: now)

    #expect(try seeder.search("leg").count == 1)
    #expect(try seeder.search("LEG PRESS").count == 1)
    #expect(try seeder.search("press").count == 1)
    #expect(try seeder.search("").count == 2)
    #expect(try seeder.search("   ").count == 2)
    #expect(try seeder.search("deadlift").isEmpty)
  }

  /// The picker's search goes through the store. Each of these found nothing with a literal
  /// substring, so the picker claimed the movement was not in the catalogue.
  @Test("Searching the seeded catalogue finds gym names and abbreviations")
  func searchingTypedNames() throws {
    let database = try migratedDatabase()
    let seeder = CatalogSeeder(database: database)
    try seeder.seed(now: now)
    let cases = [
      ("rdl", "Romanian Deadlift"), ("ohp", "Overhead Press"), ("pull up", "Pull-up"),
      ("seated row", "Seated Cable Row"), ("incline bench", "Incline Barbell Bench Press"),
      ("db bench", "Dumbbell Bench Press"), ("squats", "Barbell Back Squat"),
      ("adductor machine", "Hip Adduction Machine"),
      ("abductor machine", "Hip Abduction Machine"),
      ("glute drive", "Machine Hip Thrust"),
      ("plate loaded pulldown", "Pulldown Machine"),
    ]
    for (query, expected) in cases {
      #expect(try seeder.search(query).first?.name == expected, "\(query)")
    }
    #expect(try seeder.search("benhc").isEmpty)
  }

  @Test("The real catalogue seeds cleanly")
  func realCatalogueSeeds() throws {
    let database = try migratedDatabase()
    let seeder = CatalogSeeder(database: database)
    let count = try seeder.seed(now: now)
    #expect(count == ExerciseCatalog.v1.count)
    #expect(try seeder.selectableExercises().count == ExerciseCatalog.v1.count)
    // And again, to prove the shipped data is genuinely idempotent, not just the fixture.
    #expect(try seeder.seed(now: now) == 0)
  }

  @Test("Expanding the original seed preserves user edits and performs no old-row updates")
  func expansionPreservesOriginalRows() throws {
    let database = try migratedDatabase()
    let seeder = CatalogSeeder(database: database)
    let original = Array(ExerciseCatalog.v1.prefix(50))
    #expect(try seeder.seed(original, now: now) == 50)
    try database.write { db in
      try db.execute(sql: "UPDATE exercises SET name = 'My movement', notes = 'Keep', isArchived = 1")
      try db.execute(sql: "CREATE TABLE expansionUpdates (id TEXT)")
      try db.execute(sql: "CREATE TRIGGER auditExpansion AFTER UPDATE ON exercises BEGIN INSERT INTO expansionUpdates VALUES (NEW.id); END")
    }
    let before = try database.read { db in try Exercise.order { $0.id }.fetchAll(db) }
    #expect(try seeder.seed(now: now.addingTimeInterval(100)) == ExerciseCatalog.v1.count - 50)
    let after = try database.read { db in try Exercise.order { $0.id }.fetchAll(db) }
    let originalIDs = Set(before.map(\.id))
    #expect(after.filter { originalIDs.contains($0.id) } == before)
    let updates = try database.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM expansionUpdates")
    }
    #expect(updates == 0)
    #expect(try seeder.seed(now: now) == 0)
    // An older catalogue must not prune entries authored by the newer build.
    #expect(try seeder.seed(original, now: now) == 0)
    #expect(try seeder.selectableExercises().count == ExerciseCatalog.v1.count - 50)
  }

  @Test("Every new movement's complete attribution survives real seeding")
  func expansionAttributionRoundTrips() throws {
    let database = try migratedDatabase()
    let seeder = CatalogSeeder(database: database)
    try seeder.seed(now: now)
    let stored = Dictionary(uniqueKeysWithValues: try seeder.selectableExercises().map { ($0.slug, $0) })
    for expected in ExerciseCatalog.v1.dropFirst(50) {
      let actual = try #require(stored[expected.slug])
      #expect(actual.modality == expected.modality)
      #expect(actual.primaryMuscle == MuscleKey(expected.primaryMuscle))
      #expect(Set(actual.contributions) == Set(expected.contributions))
      #expect(actual.unreadableEntryCount == 0)
      #expect(try seeder.search(expected.name).first?.id == actual.id)
    }
  }
}

@Suite("The shipped catalogue is well formed")
struct ExerciseCatalogTests {
  // BEGIN PERMANENT CATALOGUE IDENTITIES
  @Test("Shipped slugs keep their permanent ids")
  func permanentIdentities() {
    let pinned = """
      barbell-back-squat 2141aeb9-8b67-5832-91dd-0884206173a6
      barbell-front-squat 46b7b2d2-42f2-51e9-8535-d00134b5473b
      hack-squat ae073606-c6d4-5ff9-8043-cddc202f5a5d
      leg-press 806fa1fa-8da3-5fae-b3ad-113e91d9fe98
      leg-extension 3ff3622c-e166-581d-ab47-bdbee49afa0a
      romanian-deadlift e15f932c-bd9f-5182-abc7-442763cfbce9
      conventional-deadlift 4d6fab67-0dfd-5304-ad2d-09710c22ecae
      seated-leg-curl 049c5267-2be5-5e29-9aa5-9ddd5d4b5aac
      lying-leg-curl f442b84c-cc45-5437-97a3-b5fdde3f4327
      hip-thrust 7665ad74-7f11-566b-be9a-bd8e9feb9d95
      bulgarian-split-squat 3b270010-5d55-506b-8199-0f53b80440c0
      standing-calf-raise 940029be-c7e6-5d22-87f7-bbcef1d2143f
      seated-calf-raise 686670d7-855d-5b7e-8242-487e501b53ed
      barbell-bench-press 668d15d9-1181-534e-b8e7-b3aece6c914a
      incline-barbell-bench-press 29c5f886-e58a-5c94-9a20-a9e1a0485ec6
      dumbbell-bench-press 446a021e-d536-5b7d-96f2-d54f0141f73f
      incline-dumbbell-press a0623ea0-682f-55d1-ad7a-0a720703ed7d
      chest-press-machine f19e9ce0-67c8-5d82-a2dd-6b1b5e1ada13
      pec-deck 32ec43d7-a514-5845-98f0-7eae2a9e35ae
      cable-fly 6fd64ea9-2b23-5cec-bebe-ffd6caa409eb
      dip 2bccda58-87f0-5418-b61f-2815619a73b5
      pull-up 259d7c14-500b-5c05-a39a-edc859c28a20
      chin-up b9cfb919-457c-5873-b001-8a842d065545
      lat-pulldown df0d3510-25f3-5f98-a63e-232a13f30ef3
      seated-cable-row 611b1ae7-fc7e-5aba-a9b3-441b5684d30d
      barbell-row 0a21aac0-209b-5627-bf6d-80120ceb3a5b
      chest-supported-row 9afbe580-9c2d-554e-bd5a-b5e98c523ca8
      single-arm-dumbbell-row 1f1b4e17-b104-51a6-98c2-96510a5d8c18
      straight-arm-pulldown 9236077a-6784-5e79-969e-811b9f3aa16f
      overhead-press a5449d5a-4bd2-5b60-881c-dcbe4fd2ffad
      seated-dumbbell-press af2a4a3b-01c7-5f3e-9c03-9c88e9f1a450
      lateral-raise 6b823bc2-186c-5022-9f4a-ece3d2b16d8b
      cable-lateral-raise 513144a3-3f12-562b-af79-6673fddeb061
      reverse-pec-deck ee726368-4213-5624-a385-170afbbc61af
      face-pull 332c9e5f-caf6-5820-87bb-eea1033c0705
      barbell-curl 8668ff40-3999-5eca-8b89-32c33747ec7a
      dumbbell-curl 58ea086e-223d-5d81-afbe-c1df1be63ef3
      incline-dumbbell-curl 95df7daa-8ada-52ff-b4ab-a4d0a27ae525
      preacher-curl 78054ad4-73ab-540f-8a7b-995046cf6b88
      hammer-curl 9eb4470d-e452-5e57-a8d6-0308ea34f0fb
      cable-triceps-pushdown f8c888ce-a223-5025-8f87-a9c12de07a5a
      overhead-cable-extension dc10175f-308b-56d7-8e8b-0e79f8c05190
      skull-crusher 8ff53fd6-a4e6-5115-a5fd-b48e9674c34b
      close-grip-bench-press 0b8342ec-7bd7-5b49-acea-077aec8249fd
      shrug 8e9234e6-6ef4-5e84-8814-4fae767c0e83
      cable-crunch 4bb8fb96-0fac-5e37-8f55-073860eefd4b
      hanging-leg-raise d804c206-70be-559d-aade-02cbb159c723
      back-extension 404f7e81-5a0d-5a6b-bbf6-6eb72e85489d
      wrist-curl 472004ef-5b01-52f6-8550-519880c45d6c
      reverse-wrist-curl 0b0f4101-98b5-5e8e-8ece-fb8681e0ca21
      horizontal-leg-press e2905df6-184f-5223-991c-6f2a05e5b83c
      single-leg-press 1c253d38-2b2c-5e8f-b2ba-c8fd251d7a0e
      smith-machine-squat f67ec066-8c46-58b1-bbb1-d56af7359f88
      pendulum-squat 6a413ea2-8cb5-5c34-b885-c0187fdb9046
      belt-squat ae6add92-5dbc-5bd9-aa07-d4f4b2dab2f8
      goblet-squat bb2fd281-bf5f-5500-930c-82922cd1020f
      dumbbell-front-squat df7a6ec9-6fc5-5aaa-80aa-7fff94c9d536
      barbell-split-squat 895392c5-5946-5f9e-9f9f-76c008df9b1e
      dumbbell-reverse-lunge 8fb3f86c-3cbc-595c-af59-613e84dbac1d
      dumbbell-walking-lunge 7570b68a-f102-5e79-9b60-19ba38555d92
      dumbbell-step-up ee1fb1dc-5b63-5f4d-9485-5366d71bc0ae
      smith-machine-split-squat fbcecc62-157d-5354-bbf5-98753130806f
      single-leg-extension 5b7ccc74-a76f-58f1-825f-a9bdb8f8123c
      standing-leg-curl 0c1d994a-d6d4-5ec9-a755-ba541c72f0ec
      single-leg-seated-leg-curl 0b15b0cd-dda9-5cab-9233-3d1b8487442a
      nordic-hamstring-curl f73a70bc-6b4a-5c17-9026-c1adbc7cb4e0
      dumbbell-romanian-deadlift 3e104211-da92-5539-970f-881c37d4db81
      single-leg-romanian-deadlift 8d6fb9df-f678-513a-aef3-0e8174e77185
      smith-machine-romanian-deadlift 11c23621-900c-59d0-971c-a121bd9c4fb3
      barbell-good-morning b552ae66-dc15-5daf-aef9-b277d51281cc
      cable-pull-through 4e4b080d-cdb4-5459-8874-ae20b72e4e3b
      machine-hip-thrust 10c199d7-67b5-5df1-90cc-afc8e50e3f64
      dumbbell-hip-thrust 27bdb80a-58ce-5111-aa5c-a1c810e34ce4
      glute-bridge 5f01f79c-9a48-53f8-9471-8d3591f11bf4
      cable-glute-kickback 44f3fdec-f2ea-5781-9701-65edd7964be2
      hip-extension-machine 15f95a02-7a92-5cbd-865c-a0bb3e22d265
      hip-adduction-machine dd2e5975-a0e2-5982-8c72-4820006f649f
      hip-abduction-machine 065406b1-f7a6-5351-811e-7b2ed18c0ea7
      standing-cable-hip-abduction 02057a33-45d9-532d-ac2e-da0d1a72c5f9
      leg-press-calf-raise 49be22e8-1366-5cdd-a555-6c80bd6d10cc
      single-leg-dumbbell-calf-raise 23ab8549-58d8-5254-8618-f0e69fa5d398
      smith-machine-calf-raise cb2361b3-5909-5633-baae-259a0be878e3
      decline-barbell-bench-press ec8578c4-366d-5977-a80a-93070d631405
      decline-dumbbell-bench-press b939d71c-f5fe-5508-b4ec-64fe360234c5
      smith-machine-bench-press 24503c7a-041f-5b53-8c7a-b8cdb79554aa
      incline-smith-machine-press 3ebf28e1-450d-5ea1-bea7-beccced28baf
      incline-chest-press-machine 9ffce5c0-923a-59d4-93ca-2cd1745d978f
      single-arm-chest-press-machine 78b378ae-a39a-5cdb-afe3-f3bab040564e
      cable-chest-press 4f0768b2-122f-5ff7-9bfc-4bda84e71cf9
      single-arm-cable-chest-press 5b56ffb4-1518-5d75-a9de-697b1e3ad616
      dumbbell-floor-press 0e44d160-2616-54a8-8379-146931df1522
      push-up edeebedb-a3f6-586e-a06e-7c066f1a6ed6
      feet-elevated-push-up 21bb7b64-594f-57d9-9429-a9f919bc0283
      dumbbell-fly 7c7632c3-b753-56e1-a68b-9b9098834d33
      incline-dumbbell-fly 102c6f8b-83f8-53ad-bbcd-09891518c99b
      single-arm-cable-fly 57001253-2efa-5f56-b266-8e40e7cabe1c
      shoulder-press-machine d1179d9f-d9c8-5ace-8688-0314c5ebbba4
      smith-machine-shoulder-press 5b56a6b3-6433-520a-b5ea-a2b57655060c
      standing-dumbbell-press 5089c302-cd90-5970-b686-dc94bb3c13e1
      single-arm-dumbbell-press e5a401b2-eff5-5c17-b529-570c75394b7a
      single-arm-landmine-press 03a64531-3141-50e5-8e75-d4953a624bb2
      lateral-raise-machine 2d6ec09b-84a6-53e6-bfd7-f5b1c174f800
      cable-front-raise 9654efee-6e33-5729-b4e8-bafe5b2ce9a1
      dumbbell-front-raise 981ce31e-f2f3-5009-aff9-335dcd5282f0
      bent-over-dumbbell-reverse-fly 13294f04-2b27-5bd1-bc9b-48a66b6f525c
      cable-reverse-fly bb498c3b-4669-59b8-8d9f-f38bc4856406
      single-arm-pulldown-machine a439709b-9e00-55dc-89a3-51006d7aa2db
      chest-supported-t-bar-row ca8408a6-5e08-5223-b38a-0b487ea8f5de
      pulldown-machine 8a47a1b5-b34e-5814-98c0-c4989ad8b2d8
      single-arm-cable-pulldown f66e9f9c-2d6d-5e84-b11b-635a3d478886
      seated-row-machine b906a1f7-1a0b-5ac0-aae7-cb41887a9141
      single-arm-seated-row-machine 85ab49da-e9a5-5131-8dab-19562938dde8
      t-bar-row 433e2872-1109-5a55-a8d2-ee2ce8cc870d
      chest-supported-dumbbell-row 5f9f76ed-8791-5895-ab0c-2b946c6d3fb8
      inverted-row 12e269f5-477f-5026-a374-325ca13e9514
      single-arm-cable-row 24a1df97-f6d8-558c-9cc4-87025dcc70e1
      dumbbell-shrug 6066e5f1-1c3d-5750-83e8-e839f2521af0
      smith-machine-shrug 909b81f8-499f-59d2-b7b2-41747a6cf63c
      cable-shrug 3e652709-04a8-59e2-a6d1-84a7fe708a2b
      cable-curl ffe80dbf-440e-5cf0-b4ce-20319316af55
      high-cable-curl 35bed3c3-bd3c-5498-aeec-8bac4aa722ca
      bayesian-cable-curl d9ddd21f-cfae-5c45-8609-64bdb7c72b16
      dumbbell-preacher-curl 90da314f-d29c-5af3-ae93-bc8786b6bd88
      concentration-curl bc9b0302-8e79-595e-a3c5-7695fb71c4ee
      spider-curl 07733656-d105-5448-ba9b-abc6f13a78df
      triceps-extension-machine fee28904-aaeb-55db-95c1-6daf95ca8c03
      single-arm-cable-pushdown e12543f3-ad3a-5c01-89c4-c2272d4c1f47
      dumbbell-overhead-triceps-extension 43b1256b-d26a-57f9-8d24-804fec6a46a7
      single-arm-dumbbell-overhead-extension 78dc1ab8-854e-5150-b415-d20b0c0af8c5
      lying-dumbbell-triceps-extension 413e31b3-de6e-5033-aa4a-fd7a7df41cf8
      dumbbell-triceps-kickback 186a2884-b83b-5357-9c86-128d0dddd8fc
      cable-triceps-kickback c9b06f22-eb1a-58c9-930a-12535b1dfd0a
      barbell-wrist-curl 0f4eac20-91a3-547d-8375-b064c621e985
      barbell-reverse-wrist-curl 665d4bf6-6894-5a87-b955-5bb4f62a4e05
      abdominal-crunch-machine 392c4e77-6962-5ed8-9eb1-78ab0424a819
      crunch 63a792dd-9bf9-531f-9343-7d646d4ea032
      decline-crunch 8ed5e592-a011-5427-bbc0-ffbd1fda4d3d
      reverse-crunch 9c30f353-e4f2-510a-b20f-05b695579b23
      hanging-knee-raise 73c92a83-b756-5912-ae46-9331df327436
      captain-chair-knee-raise d2cdd936-f46b-5fc9-9915-0eb94aba174e
      cable-wood-chop 99b2ad89-5f54-542b-9350-48d01e481ea2
      cable-side-bend 9e189aab-e44d-542e-9552-f6ed89606d03
      dumbbell-side-bend 87b1cf07-3b2c-579e-9a8d-cf1a9ec8d4cc
      torso-rotation-machine a8b4591b-d778-5b1d-b534-5adb0d2723d7
      back-extension-machine 85c64763-220c-5dc2-b2d3-7f080feb0078
      reverse-hyperextension 53a45ab3-4189-5f09-8907-379aed53a06a
      cable-hip-adduction 4e9814cc-dee7-5973-815a-713b863c7bad
      cable-external-rotation c8fc3b4d-5cfc-5c35-9903-43c944f76e2d
      side-lying-dumbbell-external-rotation 77641a42-7038-5e34-93a7-c589ac780e12
      cable-wrist-curl 9b7c42e0-adaa-564c-a34d-a10ef48f8587
      """.split(separator: "\n").map { $0.split(separator: " ").map(String.init) }
    let expected = Dictionary(uniqueKeysWithValues: pinned.map { ($0[0], $0[1]) })
    let actual = Dictionary(uniqueKeysWithValues: ExerciseCatalog.v1.map { ($0.slug, $0.id) })
    #expect(actual == expected)
  }
  // END PERMANENT CATALOGUE IDENTITIES

  @Test("Expansion citations distinguish anatomical inference from trial evidence")
  func expansionSourcesAreExplicit() throws {
    for entry in ExerciseCatalog.v1.dropFirst(50) {
      for contribution in entry.contributions {
        let citation = try #require(contribution.citation, "\(entry.slug) lacks a source")
        #expect(contribution.certainty == .moderate || contribution.certainty == .low)
        if contribution.role == .stabilizer {
          #expect(contribution.sourceID == AttributionSourceID.convention.rawValue)
          #expect(citation.contains("docs/MuscleTaxonomy-spec.md §5 G2"))
          #expect(contribution.setWeight == 0)
        } else {
          #expect(contribution.sourceID == AttributionSourceID.anatomy.rawValue)
          #expect(citation.contains("docs/research/tax-spec.md §1 and §5 G1–G3"))
          #expect(citation.contains("not a variant-specific growth trial"))
        }
      }
    }
  }

  /// A malformed UUID literal would fail at seed time on a user's device, so it is caught here.
  @Test("Every id is a valid UUID, lowercase, and unique")
  func idsAreValid() {
    for entry in ExerciseCatalog.v1 {
      #expect(entry.uuid != nil, "\(entry.slug) has a malformed id")
      #expect(entry.id == entry.id.lowercased(), "\(entry.slug) has an uppercase id")
    }
    #expect(Set(ExerciseCatalog.v1.map(\.id)).count == ExerciseCatalog.v1.count)
    #expect(Set(ExerciseCatalog.v1.map(\.slug)).count == ExerciseCatalog.v1.count)
  }

  /// Test 1 from the spec. Replaces a hard-coded 13-string list that would have passed unchanged
  /// while a typo introduced a 23rd muscle value.
  @Test("Every attributed muscle is a known token")
  func everyTokenIsKnown() {
    for entry in ExerciseCatalog.v1 {
      #expect(
        shippedMuscleKeys.contains(entry.primaryMuscle.rawValue),
        "\(entry.slug) primary \(entry.primaryMuscle.rawValue) is not a shipped token"
      )
      for contribution in entry.contributions {
        #expect(
          contribution.key.isAttributed,
          "\(entry.slug) credits unknown token \(contribution.key.storedValue)"
        )
      }
    }
  }

  /// Test 2. One muscle may not occupy two buckets in one entry — that would double-count it.
  @Test("No muscle appears twice in one entry under any role")
  func noDuplicateMuscles() {
    for entry in ExerciseCatalog.v1 {
      let keys = entry.contributions.map(\.key)
      #expect(Set(keys).count == keys.count, "\(entry.slug) lists a muscle twice")
    }
  }

  /// Test 3. The display key and the arithmetic must agree about what the movement trains.
  @Test("The primary muscle is present as a direct contribution")
  func primaryIsDirect() {
    for entry in ExerciseCatalog.v1 {
      let directKeys = entry.contributions.filter { $0.role == .direct }.map(\.key)
      #expect(!directKeys.isEmpty, "\(entry.slug) credits nothing directly")
      #expect(
        directKeys.contains(MuscleKey(entry.primaryMuscle)),
        "\(entry.slug) primary \(entry.primaryMuscle.rawValue) is not among its direct muscles"
      )
    }
  }

  /// Test 4. Two-primaries drift inflates every large-muscle total by up to 100%, and an
  /// unbounded fanout makes the dashboard a movement appears on meaningless.
  @Test("Role caps and credited fanout hold")
  func capsHold() {
    var totalFanout = 0.0
    for entry in ExerciseCatalog.v1 {
      let direct = entry.contributions.filter { $0.role == .direct }
      let indirect = entry.contributions.filter { $0.role == .indirect }
      let stabilising = entry.contributions.filter { $0.role == .stabilizer }
      #expect(direct.count <= 2, "\(entry.slug) has \(direct.count) direct muscles")
      #expect(indirect.count <= 3, "\(entry.slug) has \(indirect.count) indirect muscles")
      #expect(stabilising.count <= 3, "\(entry.slug) has \(stabilising.count) stabilisers")

      let fanout = entry.contributions.reduce(0.0) { $0 + $1.setWeight }
      #expect(fanout <= 3.5, "\(entry.slug) credits \(fanout) sets per set")
      totalFanout += fanout
    }
    let mean = totalFanout / Double(ExerciseCatalog.v1.count)
    #expect(mean <= 2.0, "catalogue mean credited fanout is \(mean)")
  }

  /// Test 6. `.high` requires a trial measuring that muscle's growth from that movement.
  @Test("Only a trial may justify high certainty, and every source is on the allowlist")
  func sourcesAreAllowed() {
    let allowed = Set(AttributionSourceID.allCases.map(\.rawValue))
    for entry in ExerciseCatalog.v1 {
      for contribution in entry.contributions {
        #expect(
          allowed.contains(contribution.sourceID),
          "\(entry.slug) uses unknown source \(contribution.sourceID)"
        )
        if contribution.certainty == .high {
          #expect(
            contribution.sourceID == AttributionSourceID.trial.rawValue,
            "\(entry.slug) claims high certainty from \(contribution.sourceID)"
          )
          #expect(contribution.citation != nil, "\(entry.slug) claims a trial with no citation")
        }
      }
    }
  }

  /// Grip is a stabiliser, never trained work. This is the seed's original defect, now asserted.
  @Test("Grip and bracing are stabilisers, not credited muscles")
  func gripAndBracingAreStabilisers() throws {
    let gripSites = [
      "pull-up", "chin-up", "lat-pulldown", "barbell-curl", "dumbbell-curl",
      "incline-dumbbell-curl", "preacher-curl", "hammer-curl", "shrug", "hanging-leg-raise",
    ]
    for slug in gripSites {
      let entry = try #require(ExerciseCatalog.v1.first { $0.slug == slug })
      let forearms = try #require(
        entry.contributions.first { $0.key == MuscleKey(.forearms) },
        "\(slug) dropped forearms entirely instead of recording it as a stabiliser"
      )
      #expect(forearms.role == .stabilizer, "\(slug) credits grip as trained work")
      #expect(forearms.setWeight == 0)
    }
    // And where the wrist is the loaded joint, forearms ARE direct.
    for slug in ["wrist-curl", "reverse-wrist-curl"] {
      let entry = try #require(ExerciseCatalog.v1.first { $0.slug == slug })
      let forearms = try #require(entry.contributions.first { $0.key == MuscleKey(.forearms) })
      #expect(forearms.role == .direct)
    }
    // Isometric bracing likewise credits nothing.
    for slug in ["barbell-back-squat", "barbell-front-squat", "overhead-press"] {
      let entry = try #require(ExerciseCatalog.v1.first { $0.slug == slug })
      let abs = try #require(entry.contributions.first { $0.key == MuscleKey(.abs) })
      #expect(abs.role == .stabilizer, "\(slug) credits bracing as trained work")
    }
  }

  /// The one split with outcome evidence behind it, asserted so a later edit cannot quietly
  /// re-merge the two calf muscles.
  @Test("The calf split follows the knee position")
  func calfSplitIsCorrect() throws {
    let standing = try #require(ExerciseCatalog.v1.first { $0.slug == "standing-calf-raise" })
    #expect(Set(standing.contributions.map(\.key)) == [MuscleKey(.gastrocnemius), MuscleKey(.soleus)])

    let seated = try #require(ExerciseCatalog.v1.first { $0.slug == "seated-calf-raise" })
    // Omitting gastrocnemius IS the dissociation: seated produced +0.6% and +1.7%, both n.s.
    #expect(seated.contributions.map(\.key) == [MuscleKey(.soleus)])
    #expect(seated.primaryMuscle == .soleus)
  }

  /// A floor, not a completeness claim: an accidental deletion of half the file should fail.
  @Test("Every muscle group has at least one movement training it directly")
  func coversEveryGroup() {
    let directlyTrained = Set(
      ExerciseCatalog.v1.flatMap { entry in
        entry.contributions.filter { $0.role == .direct }.compactMap(\.key.muscle)
      }
    )
    for group in MuscleGroup.allCases where group != .neck {
      let hit = group.members.contains { directlyTrained.contains($0) }
      #expect(hit, "no movement directly trains anything in \(group.rawValue)")
    }
  }

  /// Content debt, held as a shrinking allowlist so it cannot be forgotten. Every token here is
  /// one the 240-entry pass must author a direct movement for.
  @Test("The unauthored-token list matches reality")
  func unauthoredTokensAreAccurate() {
    let directlyTrained = Set(
      ExerciseCatalog.v1.flatMap { entry in
        entry.contributions.filter { $0.role == .direct }.compactMap(\.key.muscle)
      }
    )
    let missing = Set(Muscle.allCases).subtracting(directlyTrained)
    #expect(
      missing == ExerciseCatalog.unauthoredDirectTokens,
      "unauthoredDirectTokens says \(ExerciseCatalog.unauthoredDirectTokens) but reality is \(missing)"
    )
  }
}
