import CloudKit
import Foundation
import GRDB
import SQLiteData
import Testing

@testable import HardsetStore

/// Blocker 4: the schema is permanent at ship, so it is validated before any UI exists.
///
/// `SyncEngine.init` runs `validateSchema()` synchronously, before any network activity, and
/// throws on an invalid schema. That makes it usable as an offline ship gate with no CloudKit
/// account, no entitlement and no container.
// `.serialized`: each test attaches a metadatabase, and Swift Testing runs tests in
// parallel by default. Even with per-test container identifiers, serialising keeps SQLite
// lock contention out of the results.
@Suite("The migrated schema is CloudKit-safe", .serialized)
struct SchemaTests {
  /// Builds a migrated in-memory database.
  ///
  /// `DatabaseQueue()` is constructed directly rather than via `defaultDatabase()`, which
  /// returns a temp-file `DatabasePool` even in test contexts.
  /// A unique container per test. The metadatabase path derives from this identifier, so
  /// sharing one across tests makes them fight over the same SQLite file.
  private func uniqueContainer() -> String { "iCloud.hardset.tests.\(UUID().uuidString)" }

  /// Builds a migrated in-memory database.
  ///
  /// `DatabaseQueue()` is constructed directly rather than via `defaultDatabase()`, which
  /// returns a temp-file `DatabasePool` even in test contexts.
  private func migratedDatabase(container: String) throws -> any DatabaseWriter {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    // Deliberately NOT calling `attachMetadatabase` here, unlike production.
    //
    // In a non-live context `SyncEngine.init` prepares its own in-memory metadatabase at
    // `file:sqlitedata_icloud?mode=memory&cache=shared`, and attaching one in
    // `prepareDatabase` as well throws `.metadatabaseMismatch`. SQLiteData's own suite
    // suppresses the attach with a `package` task local (`$attachMetadatabase.set(false)`)
    // that is not reachable from outside the package, so the equivalent here is simply to
    // let the engine do the attaching.
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return queue
  }

  /// The gate. If this throws, the schema cannot ship.
  ///
  /// The trap this avoids: `validateSchema()` reads `pragma_index_list` and
  /// `pragma_foreign_key_list` per table, so constructing the engine against an *unmigrated*
  /// database makes every pragma return empty and the validation pass vacuously. The migration
  /// must run first, which is why `migratedDatabase()` exists.
  @Test("Constructing a SyncEngine against the real migrated schema does not throw")
  func syncEngineAcceptsSchema() throws {
    try withDependencies {
      $0.context = .test
    } operation: {
      let container = uniqueContainer()
      let database = try migratedDatabase(container: container)
      let delegate = HardsetSyncDelegate()
      // `SchemaError` is `package`, so its `.reason` cannot be matched from here. The
      // assertion is simply that construction succeeds; on failure the description carries
      // the library's debugDescription, which names the offending table.
      do {
        _ = try HardsetDatabase.makeSyncEngine(
          for: database, delegate: delegate, containerIdentifier: container)
      } catch {
        Issue.record("Schema rejected by SyncEngine: \(String(describing: error))")
        throw error
      }
    }
  }

  @Test("Every migrated table actually exists after the migration")
  func allTablesExist() throws {
    let container = uniqueContainer()
      let database = try migratedDatabase(container: container)
    let expected =
      HardsetMigrations.syncedTableNames
      + HardsetMigrations.deviceLocalTableNames
      + HardsetMigrations.deferredSyncTableNames
    try database.read { db in
      for table in expected {
        let exists = try Bool.fetchOne(
          db,
          sql: "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name=?)",
          arguments: [table]
        )
        #expect(exists == true, "missing table: \(table)")
      }
    }
  }

  @Test("An installed v1 database gains split rotation without losing its sessions")
  func v1UpgradeAddsSplitDayLink() throws {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let database = try DatabaseQueue(configuration: configuration)
    let migrator = HardsetMigrations.migrator()
    try migrator.migrate(database, upTo: "v1")

    let sessionID = UUID().uuidString.lowercased()
    try database.write { db in
      let beforeColumns = try db.columns(in: "sessions").map(\.name)
      #expect(!beforeColumns.contains("splitDayID"))
      try db.execute(
        sql: """
          INSERT INTO sessions (id, title, notes, startedAt)
          VALUES (?, 'Existing workout', 'keep me', '2026-08-25T12:00:00Z')
          """,
        arguments: [sessionID]
      )
    }

    try migrator.migrate(database)

    try database.read { db in
      let afterColumns = try db.columns(in: "sessions").map(\.name)
      #expect(afterColumns.contains("splitDayID"))
      let fetched = try Row.fetchOne(
        db, sql: "SELECT * FROM sessions WHERE id = ?", arguments: [sessionID]
      )
      let row = try #require(fetched)
      #expect(row["title"] as String == "Existing workout")
      #expect(row["notes"] as String == "keep me")
      #expect(row["splitDayID"] as String? == nil)

      let foreignKeys = try Row.fetchAll(db, sql: "SELECT * FROM pragma_foreign_key_list('sessions')")
      #expect(foreignKeys.contains { ($0["from"] as String?) == "splitDayID" })
    }
  }

  @Test("A historical v1 that already has splitDayID still completes later migrations")
  func historicalV1WithSplitDayLinkStillUpgrades() throws {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let database = try DatabaseQueue(configuration: configuration)
    let migrator = HardsetMigrations.migrator()
    try migrator.migrate(database, upTo: "v1")

    let sessionID = UUID().uuidString.lowercased()
    try database.write { db in
      // Reproduce the schema installed on physical devices by the build that briefly shipped
      // `splitDayID` inside v1 before v2 was registered. Its migration ledger says v1 even though
      // the column is already present.
      try db.execute(
        sql: """
          ALTER TABLE sessions
            ADD COLUMN splitDayID TEXT REFERENCES splitDays(id) ON DELETE SET NULL
          """
      )
      try db.execute(
        sql: """
          INSERT INTO sessions (id, title, notes, startedAt)
          VALUES (?, 'Existing workout', 'keep me', '2026-08-25T12:00:00Z')
          """,
        arguments: [sessionID]
      )
    }

    try migrator.migrate(database)

    try database.read { db in
      let sessionColumns = try db.columns(in: "sessions").map(\.name)
      let splitEntryColumns = try db.columns(in: "splitEntries").map(\.name)
      let notes = try String.fetchOne(
        db, sql: "SELECT notes FROM sessions WHERE id = ?", arguments: [sessionID])
      let applied = try String.fetchAll(
        db, sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid")

      #expect(sessionColumns.contains("splitDayID"))
      #expect(splitEntryColumns.contains("targetSets"))
      #expect(notes == "keep me")
      #expect(applied == ["v1", "v2-session-split-day", "v3-split-entry-target-sets"])
    }
  }

  @Test("A historical v1 that already has both later columns records both migrations")
  func historicalV1WithBothLaterColumnsStillUpgrades() throws {
    let database = try DatabaseQueue()
    let migrator = HardsetMigrations.migrator()
    try migrator.migrate(database, upTo: "v1")

    try database.write { db in
      try db.execute(sql: "ALTER TABLE sessions ADD COLUMN splitDayID TEXT")
      try db.execute(sql: "ALTER TABLE splitEntries ADD COLUMN targetSets INTEGER")
    }

    try migrator.migrate(database)

    let applied = try database.read { db in
      try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid")
    }
    #expect(applied == ["v1", "v2-session-split-day", "v3-split-entry-target-sets"])
  }

  /// App Review guideline 5.1.3(ii): personal health information may not be stored in iCloud.
  /// The `device` prefix is the enforceable boundary, so it is asserted rather than trusted.
  @Test("No device-local table is registered for synchronization")
  func deviceTablesAreNotSynced() {
    for table in HardsetMigrations.deviceLocalTableNames {
      #expect(
        table.hasPrefix(SchemaRules.deviceLocalTablePrefix),
        "device-local table \(table) must carry the prefix that marks it unsyncable"
      )
      #expect(
        !HardsetMigrations.syncedTableNames.contains(table),
        "\(table) holds device-local data and must never be synchronized"
      )
    }
  }

  @Test("Tables deferred from sync are not registered either")
  func deferredTablesAreNotSynced() {
    for table in HardsetMigrations.deferredSyncTableNames {
      #expect(!HardsetMigrations.syncedTableNames.contains(table))
    }
  }

  /// There is no reserved-name validation anywhere in SQLiteData -- a collision surfaces as a
  /// sync failure in the field, never as a build error. So the check lives here.
  @Test("No column in the schema uses a reserved CloudKit name")
  func noReservedColumnNames() throws {
    let container = uniqueContainer()
      let database = try migratedDatabase(container: container)
    let allTables =
      HardsetMigrations.syncedTableNames
      + HardsetMigrations.deviceLocalTableNames
      + HardsetMigrations.deferredSyncTableNames

    try database.read { db in
      for table in allTables {
        let columns = try String.fetchAll(
          db, sql: "SELECT name FROM pragma_table_info(?)", arguments: [table]
        )
        #expect(!columns.isEmpty, "\(table) reported no columns")
        for column in columns {
          #expect(
            SchemaRules.isValidColumnName(column),
            "\(table).\(column) is a reserved or library-owned name"
          )
        }
      }
    }
  }

  /// SQLiteData throws on any unique index whose pragma origin is not "pk" -- which covers
  /// CREATE UNIQUE INDEX, inline UNIQUE, UNIQUE(a,b) and partial unique indexes.
  @Test("No table carries a UNIQUE index outside its primary key")
  func noUniqueOutsidePrimaryKey() throws {
    let container = uniqueContainer()
      let database = try migratedDatabase(container: container)
    try database.read { db in
      for table in HardsetMigrations.syncedTableNames {
        let rows = try Row.fetchAll(
          db, sql: "SELECT name, origin, \"unique\" FROM pragma_index_list(?)", arguments: [table]
        )
        for row in rows {
          let isUnique: Bool = row["unique"] ?? false
          let origin: String = row["origin"] ?? ""
          if isUnique {
            #expect(origin == "pk", "\(table) has a UNIQUE index (\(row["name"] ?? "?")) outside its primary key")
          }
        }
      }
    }
  }

  /// SQLite defaults a foreign key to `NO ACTION`, which SQLiteData rejects -- so omitting
  /// `ON DELETE` is itself the bug. Critically, the library's own check is gated on
  /// `foreignKeys.count == 1`, so it silently skips tables with two or more foreign keys.
  /// In this schema that is machineExercises, sessionExercises and loggedSets -- exactly the
  /// tables most likely to be wrong. This test covers what the library will not.
  @Test("Every foreign key declares a supported ON DELETE action")
  func everyForeignKeyHasSupportedAction() throws {
    let container = uniqueContainer()
      let database = try migratedDatabase(container: container)
    var checked = 0
    try database.read { db in
      for table in HardsetMigrations.syncedTableNames {
        let rows = try Row.fetchAll(
          db, sql: "SELECT \"table\", \"on_delete\" FROM pragma_foreign_key_list(?)",
          arguments: [table]
        )
        for row in rows {
          let action: String = row["on_delete"] ?? ""
          let target: String = row["table"] ?? ""
          checked += 1
          #expect(
            SchemaRules.supportedDeleteActions.contains(action.uppercased()),
            "\(table) -> \(target) uses unsupported ON DELETE \"\(action)\""
          )
          // A synced table may only point at another synced table.
          #expect(
            HardsetMigrations.syncedTableNames.contains(target),
            "\(table) has a foreign key to \(target), which is not registered for sync"
          )
        }
      }
    }
    #expect(checked > 0, "no foreign keys were examined -- the test is not actually running")
  }

  /// A self-reference or any FK cycle makes SyncEngine construction fail outright with
  /// `.cycleDetected`, so it is worth catching as its own named failure.
  @Test("No table references itself")
  func noSelfReferences() throws {
    let container = uniqueContainer()
      let database = try migratedDatabase(container: container)
    try database.read { db in
      for table in HardsetMigrations.syncedTableNames {
        let targets = try String.fetchAll(
          db, sql: "SELECT \"table\" FROM pragma_foreign_key_list(?)", arguments: [table]
        )
        #expect(!targets.contains(table), "\(table) references itself, which forbids sync")
      }
    }
  }

  @Test("Every synchronized table has a single, non-compound primary key")
  func singleColumnPrimaryKeys() throws {
    let container = uniqueContainer()
      let database = try migratedDatabase(container: container)
    try database.read { db in
      for table in HardsetMigrations.syncedTableNames {
        let pkColumns = try String.fetchAll(
          db,
          sql: "SELECT name FROM pragma_table_info(?) WHERE pk > 0 ORDER BY pk",
          arguments: [table]
        )
        // Compound primary keys slip past the library's uniqueness check, because their
        // pragma origin is still "pk". So this must be asserted directly.
        #expect(pkColumns.count == 1, "\(table) has a compound primary key: \(pkColumns)")
        #expect(pkColumns.first == "id", "\(table) primary key should be \"id\"")
      }
    }
  }

  @Test("Primary keys compose into valid CloudKit record names")
  func recordNamesAreValid() {
    let uuid = UUID().uuidString.lowercased()
    for table in HardsetMigrations.syncedTableNames {
      #expect(SchemaRules.isValidRecordName(primaryKey: uuid, tableName: table))
    }
    // Guard the rules themselves against being trivially true.
    #expect(!SchemaRules.isValidRecordName(primaryKey: "_leading", tableName: "sessions"))
    #expect(!SchemaRules.isValidRecordName(primaryKey: uuid, tableName: "bad:name"))
    #expect(!SchemaRules.isValidColumnName("creationDate"))
    #expect(!SchemaRules.isValidColumnName("recordID"))
  }

  /// The refusal, asserted at the layer that makes it permanent.
  ///
  /// A split may not carry a set count. The app has no weekly set target for any muscle --
  /// `VolumeAnalyzer.weeklyTarget` is `.unevaluated` for all 22 -- so a set count the app itself
  /// dealt out would be invented. `columnInventoryIsPinned` would catch the column arriving, but it
  /// would read as one more inventory line; this says why out loud, so a future session adding
  /// `plannedSets` to a split table has to argue with a named test rather than edit a list.
  ///
  /// `sessionExercises.plannedSets` is deliberately exempt: that is the lifter typing what they
  /// intend to do today, not the app arranging their week.
  ///
  /// **`splitEntries.targetSets` is exempt on exactly that reasoning, and the argument is made here
  /// rather than by editing the list.** This test's own note says a future session adding a set
  /// count must argue with a named test; this is that argument.
  ///
  /// The refusal was never "no number may exist" — it is "the app may not author one". The spec's
  /// section 3 objected to a column *the dealer could fill*: "a set-count column there is the hole a
  /// prescription engine climbs through". Section 6 then named this exact extension — "per-movement
  /// set targets of the lifter's own. Additive later if asked for" — and it was asked for. Nothing
  /// derives it, no default supplies it, and `weeklyTarget` stays `.unevaluated`, so no screen
  /// compares it to anything.
  ///
  /// So the ban stays on every name the app could plausibly deal out, and the exemption is guarded
  /// harder than the ban was: `targetSetsIsNullableAndUndefaulted` proves the schema cannot author a
  /// value, and `appNeverAuthorsATargetSetCount` proves no source file assigns a literal one.
  @Test("No split table carries a set count the app could author")
  func splitsCarryNoPrescription() throws {
    let queue = try DatabaseQueue()
    try HardsetMigrations.migrator().migrate(queue)
    let forbidden = ["plannedSets", "sets", "setCount", "reps", "weightKg"]
    try queue.read { db in
      for table in ["splits", "splitDays", "splitEntries"] {
        let columns = try db.columns(in: table).map(\.name)
        for column in columns {
          #expect(
            !forbidden.contains(column),
            "\(table).\(column) makes the app able to prescribe volume it has no basis for"
          )
        }
      }
    }
  }

  /// The schema itself must not be able to supply a set count.
  ///
  /// Nullable with no default is what makes "the lifter has not said" representable, and it is the
  /// difference between recording intent and having an opinion. A `NOT NULL DEFAULT 3` here would
  /// prescribe three sets to every movement anyone ever planned, without a line of code.
  @Test("An intended set count is nullable and has no default")
  func targetSetsIsNullableAndUndefaulted() throws {
    let queue = try DatabaseQueue()
    try HardsetMigrations.migrator().migrate(queue)
    try queue.read { db in
      let column = try #require(
        try db.columns(in: "splitEntries").first { $0.name == "targetSets" }
      )
      #expect(!column.isNotNull, "an intended set count must be able to be absent")
      #expect(column.defaultValueSQL == nil, "a default here would prescribe volume")
    }
  }

  /// No source file may assign a set count the lifter did not type.
  ///
  /// The column is permissible only because every value in it came from the lifter. A literal
  /// anywhere in `Sources` would be the app authoring volume — the precise thing section 3 refused —
  /// and it would not show up as a schema change, so the schema tests above could not catch it.
  ///
  /// Swept from source in the same spirit as `IsolationContractTests`: the invariant is about what
  /// the code says, so the test reads the code.
  @Test("The app never authors an intended set count")
  func appNeverAuthorsATargetSetCount() throws {
    let sources = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // HardsetStoreTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // HardsetKit
      .appendingPathComponent("Sources")

    let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?
      .compactMap { $0 as? URL }
      .filter { $0.pathExtension == "swift" } ?? []
    #expect(!files.isEmpty, "found no sources to sweep — the path above is wrong")

    // `targetSets` followed by `=` or `:` and then a digit: an authored number. A variable, an
    // optional or a `#bind` of either is fine, which is every legitimate write.
    //
    // Comments are stripped before matching. This file and the column's own documentation discuss
    // "targetSets = 3" as the thing not to do, and a ban that trips on its own explanation is the
    // trap HANDOFF section 9 records for the "score" substring test: strip the prose, scan the code.
    let authored = try Regex(#"targetSets\s*[:=]\s*\d"#)
    var offenders: [String] = []
    for file in files {
      let text = try String(contentsOf: file, encoding: .utf8)
      let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
      for (index, line) in lines.enumerated() {
        let code = line.range(of: "//").map { line[line.startIndex..<$0.lowerBound] } ?? line[...]
        guard code.firstMatch(of: authored) != nil else { continue }
        offenders.append(
          "\(file.lastPathComponent):\(index + 1) \(code.trimmingCharacters(in: .whitespaces))"
        )
      }
    }
    #expect(offenders.isEmpty, "the app authored a set count: \(offenders.joined(separator: "; "))")
  }

  /// The exact column inventory, pinned.
  ///
  /// Not a structural rule like the tests above -- an inventory, and deliberately tedious to
  /// update. SQLiteData forbids removing a column permanently, so the only moment a column can be
  /// reconsidered is before it ships; the failure mode is a column that nobody notices is dead until
  /// it is frozen. `machines.loadType` reached that state: written as the literal "unknown" at every
  /// insert, read nowhere, and structurally valid by all ten rules above.
  ///
  /// Adding a column now costs one edit here, which is the cheapest possible moment to be asked
  /// "and what reads this?".
  @Test("The schema's columns are exactly the ones intended to be frozen")
  func columnInventoryIsPinned() throws {
    let expected: [String: [String]] = [
      "bodyweightEntries": ["id", "weightKg", "measuredAt", "enteredBy"],
      "deviceHealthSamples": ["id", "kind", "value", "unit", "startedAt", "endedAt"],
      "deviceRestTimer": [
        "id", "sessionID", "alarmID", "endsAt", "pausedRemainingSeconds", "updatedAt",
      ],
      "exercises": [
        "id", "name", "curatedName", "catalogSlug", "isCurated", "modality", "primaryMuscle",
        "secondaryMusclesJSON", "notes", "isArchived", "createdAt",
      ],
      "gyms": ["id", "name", "isArchived", "createdAt"],
      "loggedSets": [
        "id", "sessionID", "exerciseID", "machineID", "sessionExerciseID", "setOrdinal",
        "weightKg", "reps", "rpe", "isWarmup", "isDropSet", "completedAt",
      ],
      "machineExercises": ["id", "machineID", "exerciseID", "createdAt"],
      "machines": ["id", "gymID", "name", "stackIncrementKg", "isArchived", "createdAt"],
      "sessionExercises": [
        "id", "sessionID", "exerciseID", "machineID", "position", "plannedSets", "supersetGroup",
      ],
      "sessions": ["id", "gymID", "title", "notes", "startedAt", "finishedAt", "splitDayID"],
      "splitDays": ["id", "splitID", "name", "position", "createdAt"],
      // `targetSets` is the lifter's own intended set count, nullable, and never written by the
      // app. The migration's note records why that distinction is what makes the column permissible
      // where an app-authored one would not be.
      // `targetSets` sits last because it arrived by ALTER TABLE, which appends. Its position in
      // this list is the migration's fingerprint, not a preference.
      "splitEntries": [
        "id", "splitDayID", "exerciseID", "machineID", "position", "createdAt", "targetSets",
      ],
      "splits": ["id", "name", "isArchived", "createdAt"],
    ]

    let queue = try DatabaseQueue()
    try HardsetMigrations.migrator().migrate(queue)
    let actual = try queue.read { db -> [String: [String]] in
      var found: [String: [String]] = [:]
      for table in expected.keys {
        found[table] = try db.columns(in: table).map(\.name)
      }
      return found
    }

    for table in expected.keys.sorted() {
      #expect(actual[table] == expected[table], "column inventory changed for \(table)")
    }

    // And no table exists that this inventory does not describe, so a whole new table cannot be
    // added without passing through here either.
    let tables = try queue.read { db in
      try String.fetchAll(
        db,
        sql: """
          SELECT name FROM sqlite_master
          WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'grdb_%'
          """
      )
    }
    #expect(Set(tables) == Set(expected.keys))
  }
}
