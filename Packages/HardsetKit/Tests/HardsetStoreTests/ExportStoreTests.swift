import Foundation
import GRDB
import HardsetCore
import Testing

@testable import HardsetStore

/// A training log the owner cannot get out of the app is a hostage.
///
/// These check the round trip rather than the string: a header a reader can rely on, one row per
/// logged set, kilograms regardless of display preference, and free text that cannot break the
/// grid.
@Suite("A lifter can take their whole history with them")
struct ExportStoreTests {
  let now = Date(timeIntervalSince1970: 12_000_000)

  private func fixture() throws -> (any DatabaseWriter, LoggerStore, ExportStore) {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    try CatalogSeeder(database: queue).seed(now: now)
    return (queue, LoggerStore(database: queue), ExportStore(database: queue))
  }

  private func exercise(_ db: any DatabaseWriter, _ slug: String) throws -> ExerciseID {
    let row = try db.read { d in try Exercise.where { $0.catalogSlug.eq(slug) }.fetchOne(d) }
    return ExerciseID(rawValue: try #require(row).id)
  }

  private func rows(_ csv: String) -> [String] {
    csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }
  }

  @Test("An empty log exports a header and nothing else")
  func emptyLogIsJustAHeader() throws {
    let (_, _, export) = try fixture()
    let csv = try export.workoutCSV()
    #expect(rows(csv).count == 1)
    #expect(try export.loggedSetCount() == 0)
  }

  @Test("Every logged set becomes exactly one row, oldest first")
  func oneRowPerSet() throws {
    let (db, store, export) = try fixture()
    let press = try exercise(db, "chest-press-machine")
    let session = try store.startSession(title: "Push", at: now)

    for i in 0..<3 {
      _ = try store.logSet(
        sessionID: session, exerciseID: press,
        draft: SetEntryDraft(weightKg: 80 + Double(i) * 2.5, reps: 10 - i),
        setOrdinal: i, kind: .working, at: now.addingTimeInterval(Double(i) * 180)
      )
    }
    try store.finishSession(session, at: now.addingTimeInterval(900))

    let lines = rows(try export.workoutCSV())
    #expect(lines.count == 4)
    #expect(lines[0] == ExportStore.header.joined(separator: ","))
    #expect(try export.loggedSetCount() == 3)
    // Oldest first: a history reads forwards.
    #expect(lines[1].contains("80"))
    #expect(lines[3].contains("85"))
  }

  /// The display unit is a preference; the archive is not. Converting on the way out would put
  /// the lifter's rounding into their own record.
  @Test("Weights export in kilograms, and the column says so")
  func weightsAreCanonicalKilograms() throws {
    let (db, store, export) = try fixture()
    let press = try exercise(db, "chest-press-machine")
    let session = try store.startSession(at: now)
    _ = try store.logSet(
      sessionID: session, exerciseID: press,
      draft: SetEntryDraft(weightKg: 82.5, reps: 8), setOrdinal: 0, kind: .working, at: now
    )

    let csv = try export.workoutCSV()
    #expect(csv.contains("weight_kg"))
    #expect(csv.contains("82.5"))
    // Not the pounds value, whatever the app is displaying.
    #expect(!csv.contains("181.8"))
  }

  @Test("Each kind is named, so a drop is not read back as a working set")
  func kindsAreLabelled() throws {
    let (db, store, export) = try fixture()
    let press = try exercise(db, "chest-press-machine")
    let session = try store.startSession(at: now)

    for (ordinal, kind) in [(0, SetKind.warmup), (1, .working), (2, .drop)] {
      _ = try store.logSet(
        sessionID: session, exerciseID: press,
        draft: SetEntryDraft(weightKg: 60, reps: 8), setOrdinal: ordinal, kind: kind, at: now
      )
    }

    let csv = try export.workoutCSV()
    for kind in SetKind.allCases {
      #expect(csv.contains(kind.rawValue))
    }
  }

  /// Gym and machine names are free text the lifter types. This is the case that silently shifts
  /// every later column if escaping is wrong.
  @Test("A machine name containing a comma cannot break the grid")
  func freeTextIsEscaped() throws {
    let (db, store, export) = try fixture()
    let press = try exercise(db, "chest-press-machine")
    let gyms = GymStore(database: db)
    let gym = try gyms.createGym(name: "PureGym", now: now)
    let machine = try gyms.createMachine(
      at: gym, name: "Hammer Strength, row 2", forExercise: press, now: now
    )
    let session = try store.startSession(at: now)
    _ = try store.logSet(
      sessionID: session, exerciseID: press, machineID: machine,
      draft: SetEntryDraft(weightKg: 80, reps: 8), setOrdinal: 0, kind: .working, at: now
    )

    let lines = rows(try export.workoutCSV())
    #expect(lines.count == 2)
    #expect(lines[1].contains("\"Hammer Strength, row 2\""))
    // Every row still has the same number of unquoted commas as the header.
    let headerCommas = lines[0].count { $0 == "," }
    let unquoted = unquotedCommaCount(lines[1])
    #expect(unquoted == headerCommas)
  }

  /// Counts commas outside quoted fields, which is what a reader uses to split columns.
  private func unquotedCommaCount(_ line: String) -> Int {
    var inQuotes = false
    var count = 0
    for character in line {
      if character == "\"" { inQuotes.toggle() }
      if character == ",", !inQuotes { count += 1 }
    }
    return count
  }

  /// An unfinished workout has no end. Inventing one is the bug that shipped 9,749-minute
  /// sessions in the ancestor, and it must not be reintroduced through an export.
  @Test("A workout still open exports with an empty finish, not a made-up one")
  func openSessionsHaveNoFinish() throws {
    let (db, store, export) = try fixture()
    let press = try exercise(db, "chest-press-machine")
    let session = try store.startSession(at: now)
    _ = try store.logSet(
      sessionID: session, exerciseID: press,
      draft: SetEntryDraft(weightKg: 80, reps: 8), setOrdinal: 0, kind: .working, at: now
    )

    let lines = rows(try export.workoutCSV())
    let fields = lines[1].components(separatedBy: ",")
    let finishIndex = try #require(ExportStore.header.firstIndex(of: "session_finished_at"))
    #expect(fields[finishIndex].isEmpty)
    // The set itself is still there: an export taken at the gym must not omit today.
    #expect(lines.count == 2)
  }

  @Test("The filename sorts chronologically and names the app")
  func filenameIsSortable() {
    let name = ExportStore.filename(on: Date(timeIntervalSince1970: 1_756_000_000))
    #expect(name.hasPrefix("hardset-"))
    #expect(name.hasSuffix(".csv"))
    #expect(name.contains("2025-"))
  }
}

/// Truncating a history has to drop the far end, not the near one.
///
/// `ProgressionStore.samples` paired an ascending `order` with a `limit`, so past the cap it kept
/// the OLDEST rows and dropped the newest: the chart stopped years ago and "last trained" reported
/// a date from the beginning of the log. Invisible until someone has more sets than the cap, which
/// is why no existing test saw it.
@Suite("A capped load history keeps the most recent sets")
struct ProgressionSampleCapTests {
  let now = Date(timeIntervalSince1970: 12_000_000)

  @Test("Past the cap it is the oldest sets that are dropped")
  func capKeepsNewest() throws {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    try CatalogSeeder(database: queue).seed(now: now)
    let store = LoggerStore(database: queue)

    let row = try queue.read { d in
      try Exercise.where { $0.catalogSlug.eq("leg-press") }.fetchOne(d)
    }
    let press = ExerciseID(rawValue: try #require(row).id)
    let session = try store.startSession(at: now)

    // Ten sets, one per day, ascending load so each is identifiable.
    for index in 0..<10 {
      _ = try store.logSet(
        sessionID: session, exerciseID: press,
        draft: SetEntryDraft(weightKg: 100 + Double(index), reps: 5),
        setOrdinal: index, kind: .working,
        at: now.addingTimeInterval(Double(index) * 86_400)
      )
    }

    // A cap smaller than the history: the newest four must survive.
    let capped = try ProgressionStore(database: queue).samples(for: press, limit: 4)
    #expect(capped.count == 4)
    let loads = capped.map(\.weightKg)
    #expect(loads == [106, 107, 108, 109])

    // And they are still handed back oldest-first, which is the contract
    // `ProgressionAnalyzer.machineChanges` breaks timestamp ties against.
    let ascending = zip(capped, capped.dropFirst()).allSatisfy { $0.completedAt <= $1.completedAt }
    #expect(ascending)
  }
}
