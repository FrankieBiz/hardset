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
}

@Suite("The shipped catalogue is well formed")
struct ExerciseCatalogTests {
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
