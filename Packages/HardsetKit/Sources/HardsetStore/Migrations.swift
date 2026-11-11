import Foundation
import GRDB
import SQLiteData

/// The frozen v1 schema and additive forward migrations.
///
/// Why one migration and why now: CloudKit's production schema is additive-only, and
/// SQLiteData additionally forbids -- permanently -- removing columns, renaming columns,
/// and renaming tables. Whatever ships is the shape of this app's data forever, so the
/// schema is designed up front and validated by constructing a `SyncEngine` against it in
/// a test rather than discovered incrementally while building screens.
///
/// Rules obeyed by every synchronized table below, each verified against SQLiteData 1.9.0's
/// own documentation:
///
/// 1. A single, non-compound `TEXT` primary key defaulting to `uuid()`, declared
///    `NOT NULL ON CONFLICT REPLACE`. Auto-incrementing integers are not allowed: two
///    devices offline would both mint id 4.
/// 2. No `UNIQUE` constraint on any column other than the primary key. This is validated
///    when the `SyncEngine` is constructed and throws if violated -- two devices creating
///    "Home Gym" offline is a legitimate state, not a conflict to resolve by discarding one.
/// 3. No reserved CloudKit column names. Note `createdAt`, never `creationDate`.
/// 4. `ON DELETE` limited to `CASCADE` / `SET NULL` / `SET DEFAULT`.
/// 5. `STRICT` tables, so a column's declared type is actually enforced.
/// 6. No `CHECK` constraints on synchronized tables. This is a deliberate extension of the
///    reasoning behind the `UNIQUE` ban: any constraint that can reject a row *arriving
///    from a peer* can wedge synchronization. Validation that needs to fail lives in Swift
///    (see `SessionTimeline.finish`), where it can fail on the device that caused it.
/// 7. No stored duration, ever -- see `sessions`.
// `nonisolated` is deliberate. This module defaults to MainActor isolation, which is right
// for view-facing types and wrong for this: schema work runs on GRDB's database queues and
// these declarations are pure. Isolating them to the main actor would both mislead and
// force every caller -- including the test suite -- to hop actors for no reason.
public nonisolated enum HardsetMigrations {
  /// Names of the tables that participate in CloudKit synchronization.
  ///
  /// Kept as data so `SyncSetup` and the schema tests agree by construction instead of by
  /// two lists that drift apart.
  public static let syncedTableNames: [String] = [
    "exercises",
    "gyms",
    "machines",
    "machineExercises",
    "sessions",
    "sessionExercises",
    "loggedSets",
  ]

  /// Device-local tables, permanently excluded from synchronization.
  ///
  /// Keeping them unregistered has a second benefit: SQLiteData's account-change wipe only
  /// empties *registered* tables, so these survive a sign-out regardless.
  public static let deviceLocalTableNames: [String] = [
    "deviceHealthSamples",
    "deviceRestTimer",
    "deviceImportBatches",
    "deviceRestJournal",
  ]

  /// Tables that exist locally but are deliberately NOT synchronized in v1, pending a
  /// decision rather than by design.
  ///
  /// `bodyweightEntries` sits here because of App Review guideline 5.1.3(ii), which forbids
  /// storing personal health information in iCloud. The brief assumed that restriction
  /// attaches to HealthKit *provenance* -- that a user-typed bodyweight is our own data and
  /// may sync. Checking the actual guideline text does not support that: 5.1.3(ii) and
  /// Paid Applications Agreement 3.3.3(D) both describe the category source-agnostically, and
  /// 3.3.3(D) names CloudKit explicitly. A bodyweight attached to a user identity is the same
  /// health information however it was entered.
  ///
  /// The asymmetry decides the default. Turning sync ON for a table later is an additive,
  /// permitted change; turning it OFF later does not remove what already went to iCloud. So
  /// v1 keeps bodyweight on-device, and syncing it is a decision to make deliberately with
  /// the guideline text in hand -- not a default absorbed from an assumption.
  public static let deferredSyncTableNames: [String] = [
    "bodyweightEntries"
  ]

  public static func migrator() -> DatabaseMigrator {
    var migrator = DatabaseMigrator()

    // Preserve training data in every configuration. Historical schema differences
    // are repaired explicitly below; they must never trigger automatic erasure.

    migrator.registerMigration("v1") { db in
      // MARK: Exercises
      //
      // Holds both the curated catalogue and user-created movements in one table, because
      // logged sets reference both through one foreign key.
      //
      // `catalogSlug` is intentionally NOT UNIQUE -- it cannot be. Curated rows instead
      // carry fixed primary keys assigned in the bundled catalogue file, which makes
      // seeding idempotent by primary key on every device without a uniqueness constraint.
      try #sql(
        """
        CREATE TABLE "exercises" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "name" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          -- The name the curated catalogue last shipped for this row, which is what makes
          -- `name` safely user-editable. The seeder must not clobber a rename, but without a
          -- record of what it wrote it cannot tell a rename from an untouched row -- so it
          -- either overwrites the user or, as before, can never correct its own typo on any
          -- install that already seeded. Comparing the two settles it: equal means untouched,
          -- so a curated correction lands; different means the user renamed it, so it stands.
          "curatedName" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "catalogSlug" TEXT,
          "isCurated" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "modality" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT 'unknown',
          "primaryMuscle" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT 'unknown',
          "secondaryMusclesJSON" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '[]',
          "notes" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "isArchived" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "createdAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now', 'subsec'))
        ) STRICT
        """
      )
      .execute(db)

      // MARK: Gyms and machines
      //
      // Per-gym inventory is learned from what the user logs, never asked in a quiz, so
      // these rows are created as a side effect of logging rather than by a setup flow.
      try #sql(
        """
        CREATE TABLE "gyms" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "name" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "isArchived" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "createdAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now', 'subsec'))
        ) STRICT
        """
      )
      .execute(db)

      // A machine is a specific physical unit at a specific gym: 80 kg on this brand's
      // leg press is not 80 kg on another's, which is the whole point of tracking it.
      try #sql(
        """
        CREATE TABLE "machines" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "gymID" TEXT NOT NULL REFERENCES "gyms"("id") ON DELETE CASCADE,
          "name" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "brand" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "loadType" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT 'unknown',
          "stackIncrementKg" REAL,
          "isArchived" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "createdAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now', 'subsec'))
        ) STRICT
        """
      )
      .execute(db)

      // Join table. It carries its own synthetic `id` because every synchronized table
      // needs a single non-compound primary key, even when the app itself would be happy
      // with just the two foreign keys.
      try #sql(
        """
        CREATE TABLE "machineExercises" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "machineID" TEXT NOT NULL REFERENCES "machines"("id") ON DELETE CASCADE,
          "exerciseID" TEXT NOT NULL REFERENCES "exercises"("id") ON DELETE CASCADE,
          "createdAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now', 'subsec'))
        ) STRICT
        """
      )
      .execute(db)

      // MARK: Sessions
      //
      // There is deliberately no "duration" column, and there never will be. Duration is
      // derived from these two immutable instants (see `SessionTimeline`). The ancestor app
      // recomputed elapsed time against the wall clock while rendering and shipped
      // 9,749-minute workouts; a stored duration would have made that permanent instead of
      // merely displayed.
      //
      // `finishedAt` being NULL is the honest representation of "still open" -- it is not
      // backfilled from `Date()`.
      try #sql(
        """
        CREATE TABLE "sessions" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "gymID" TEXT REFERENCES "gyms"("id") ON DELETE SET NULL,
          "title" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "notes" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "startedAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now', 'subsec')),
          "finishedAt" TEXT
        ) STRICT
        """
      )
      .execute(db)

      // Planned/ordered exercises within a session.
      try #sql(
        """
        CREATE TABLE "sessionExercises" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "sessionID" TEXT NOT NULL REFERENCES "sessions"("id") ON DELETE CASCADE,
          "exerciseID" TEXT NOT NULL REFERENCES "exercises"("id") ON DELETE CASCADE,
          "machineID" TEXT REFERENCES "machines"("id") ON DELETE SET NULL,
          "position" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "plannedSets" INTEGER
        ) STRICT
        """
      )
      .execute(db)

      // MARK: Logged sets
      //
      // `weightKg` is canonical: kilograms are stored and conversion happens only at the
      // UI boundary, so no row's meaning depends on which unit the user had selected.
      try #sql(
        """
        CREATE TABLE "loggedSets" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "sessionID" TEXT NOT NULL REFERENCES "sessions"("id") ON DELETE CASCADE,
          "exerciseID" TEXT NOT NULL REFERENCES "exercises"("id") ON DELETE CASCADE,
          "machineID" TEXT REFERENCES "machines"("id") ON DELETE SET NULL,
          -- Which plan row this set belongs to. Nullable, and deliberately NOT a foreign key: it
          -- is a grouping hint for recovery, while sessionID/exerciseID/machineID remain the
          -- authoritative references and carry the constraints.
          --
          -- Without it, recovery cannot tell two blocks of the same movement apart. Grouping by
          -- machine lost sets when a lifter moved mid-exercise; grouping by exercise made BOTH
          -- blocks claim the same sets and double-counted them. Neither is fixable without this.
          "sessionExerciseID" TEXT,
          "setOrdinal" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "weightKg" REAL NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "reps" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "rpe" REAL,
          "isWarmup" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "completedAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now', 'subsec'))
        ) STRICT
        """
      )
      .execute(db)

      // MARK: Bodyweight
      //
      // User-TYPED bodyweight only. This is the app's own data and may synchronize.
      // Anything read out of HealthKit must go to "deviceHealthSamples" instead --
      // see that table's note.
      try #sql(
        """
        CREATE TABLE "bodyweightEntries" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "weightKg" REAL NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "measuredAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now', 'subsec')),
          "enteredBy" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT 'manual'
        ) STRICT
        """
      )
      .execute(db)

      // MARK: Device-local tables -- NEVER synchronized
      //
      // App Review guideline 5.1.3(ii): apps may not store personal health information in
      // iCloud. Any value derived from HealthKit therefore lives here, on one device, and
      // is re-read per device rather than synchronized.
      //
      // HealthKit is out of v1 scope, but the table and the naming boundary are created now
      // on purpose: adding a table later is permitted, whereas discovering that someone
      // added a `sleepHours` column to a *synchronized* table is a rejection. The "device"
      // prefix is asserted against the sync registration in `SchemaTests`.
      try #sql(
        """
        CREATE TABLE "deviceHealthSamples" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "kind" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT 'unknown',
          "value" REAL NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "unit" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "startedAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now', 'subsec')),
          "endedAt" TEXT
        ) STRICT
        """
      )
      .execute(db)

      // Rest-timer state, device-local because a timer running on a phone should not fire
      // on an iPad. Stored as an absolute deadline or a frozen remainder, never a
      // countdown -- and never both at once, which `RestTimerState` enforces in Swift and
      // this table mirrors as two nullable columns.
      try #sql(
        """
        CREATE TABLE "deviceRestTimer" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "sessionID" TEXT,
          "alarmID" TEXT,
          "endsAt" TEXT,
          "pausedRemainingSeconds" REAL,
          "updatedAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now', 'subsec'))
        ) STRICT
        """
      )
      .execute(db)

      // Non-unique indexes are fine -- the ban is on UNIQUE, not on indexing.
      try #sql(
        """
        CREATE INDEX "loggedSets_on_exerciseID_machineID"
          ON "loggedSets"("exerciseID", "machineID")
        """
      )
      .execute(db)
      try #sql(
        """
        CREATE INDEX "loggedSets_on_sessionID" ON "loggedSets"("sessionID")
        """
      )
      .execute(db)
      try #sql(
        """
        CREATE INDEX "sessions_on_startedAt" ON "sessions"("startedAt")
        """
      )
      .execute(db)
    }

    // Keep v1 intact: existing installations must receive the same loading indexes
    // as new databases without rebuilding tables or touching synchronized records.
    migrator.registerMigration("v2_loadingIndexes") { db in
      // Date windows for volume reports should visit only the selected interval.
      try #sql(
        """
        CREATE INDEX "loggedSets_on_completedAt" ON "loggedSets"("completedAt")
        """
      )
      .execute(db)
      // Exercise-wide charts and exact-machine history need separate ordered paths.
      // Keep warm-ups in the indexes so either SQL boolean spelling can use them.
      try #sql(
        """
        CREATE INDEX "loggedSets_on_exerciseID_completedAt"
          ON "loggedSets"("exerciseID", "completedAt" DESC)
        """
      )
      .execute(db)
      try #sql(
        """
        CREATE INDEX "loggedSets_on_exerciseID_machineID_completedAt"
          ON "loggedSets"("exerciseID", "machineID", "completedAt" DESC)
        """
      )
      .execute(db)
      // Recovery reads the plan and its sets in display order, once per session.
      try #sql(
        """
        CREATE INDEX "loggedSets_on_sessionID_setOrdinal"
          ON "loggedSets"("sessionID", "setOrdinal")
        """
      )
      .execute(db)
      try #sql(
        """
        CREATE INDEX "sessionExercises_on_sessionID_position"
          ON "sessionExercises"("sessionID", "position")
        """
      )
      .execute(db)
    }

    // Order all-time benchmarks in the index instead of sorting/decoding a
    // capped recent history. Non-unique and local; no synchronized shape changes.
    migrator.registerMigration("v3_historyBenchmarks") { db in
      try #sql(
        """
        CREATE INDEX "loggedSets_on_workingBenchmark"
          ON "loggedSets"("exerciseID", "machineID", "weightKg" DESC,
                          "reps" DESC, "completedAt" DESC, "id" DESC, "sessionID")
          WHERE NOT "isWarmup"
        """
      )
      .execute(db)
    }

    migrator.registerMigration("v4_recordComparisons") { db in
      // Bounded point lookups for the best evaluable load at each rep count.
      try #sql(
        """
        CREATE INDEX "loggedSets_on_workingReps"
          ON "loggedSets"("exerciseID", "machineID", "reps", "weightKg" DESC)
          WHERE NOT "isWarmup"
        """
      )
      .execute(db)
    }

    // These columns were added by editing v1 in 33c1038. A database already
    // marked v1 never reran that migration. Repair both original and partially
    // repaired databases without rebuilding tables or inferring old plan IDs.
    migrator.registerMigration("v5_legacyV1Columns") { db in
      let exerciseColumns = try db.columns(in: "exercises")
      if !exerciseColumns.contains(where: { $0.name == "curatedName" }) {
        try #sql(
          """
          ALTER TABLE "exercises" ADD COLUMN "curatedName"
            TEXT NOT NULL ON CONFLICT REPLACE DEFAULT ''
          """
        )
        .execute(db)
      }
      let setColumns = try db.columns(in: "loggedSets")
      if !setColumns.contains(where: { $0.name == "sessionExerciseID" }) {
        try #sql(
          """
          ALTER TABLE "loggedSets" ADD COLUMN "sessionExerciseID" TEXT
          """
        )
        .execute(db)
      }
    }

    // Finished history must not be scanned when launch finds no workout to
    // resume. Keep this local, non-unique index small by indexing open rows only.
    migrator.registerMigration("v6_openSessionLookup") { db in
      try #sql(
        """
        CREATE INDEX "sessions_on_openStartedAt"
          ON "sessions"("finishedAt", "startedAt" DESC)
          WHERE "finishedAt" IS NULL
        """
      )
      .execute(db)
    }

    // Device-only replay ledger. CSV contents are training data and stay off CloudKit.
    migrator.registerMigration("v7_importReplayLedger") { db in
      try #sql(
        """
        CREATE TABLE deviceImportBatches (id TEXT PRIMARY KEY NOT NULL, sourceCSV TEXT NOT NULL) STRICT
        """
      ).execute(db)
    }

    migrator.registerMigration("v8_durableRestJournal") { db in
      try #sql(
        """
        CREATE TABLE deviceRestJournal (id INTEGER PRIMARY KEY, checkpointJSON TEXT NOT NULL) STRICT
        """
      ).execute(db)
    }

    // Match the complete chart history's stable tie ordering without a temporary sort.
    migrator.registerMigration("v9_progressionOrder") { db in
      try #sql(
        """
        CREATE INDEX loggedSets_on_progressionOrder
          ON loggedSets(exerciseID, completedAt DESC, setOrdinal DESC, id DESC)
          WHERE NOT isWarmup
        """
      ).execute(db)
    }

    // The replay ledger kept a full copy of every imported file. Strong and Hevy re-export the
    // whole history each time, so every catch-up import added another copy of up to 20 MB, and
    // JSON and SQLite exports carried them all. A digest and byte count recognise the same file;
    // existing copies are hashed and then emptied. The table is device-local and never synced,
    // so this changes no shared schema. `sourceCSV` stays, empty, rather than being dropped.
    migrator.registerMigration("v10_importLedgerDigests") { db in
      try #sql(
        """
        ALTER TABLE deviceImportBatches ADD COLUMN sourceDigest TEXT NOT NULL DEFAULT ''
        """
      ).execute(db)
      try #sql(
        """
        ALTER TABLE deviceImportBatches ADD COLUMN byteCount INTEGER NOT NULL DEFAULT 0
        """
      ).execute(db)
      let stored = try Row.fetchAll(db, sql: "SELECT id, sourceCSV FROM deviceImportBatches")
      for row in stored {
        let bytes = Data((row["sourceCSV"] as String).utf8)
        try db.execute(
          sql: "UPDATE deviceImportBatches SET sourceDigest = ?, byteCount = ?, sourceCSV = '' WHERE id = ?",
          arguments: [SHA256Digest.hex(of: bytes), bytes.count, row["id"] as String])
      }
    }

    return migrator
  }
}
