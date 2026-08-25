import Foundation
import SQLiteData

/// The entire v1 schema, as one migration, written before any UI exists.
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
    "splits",
    "splitDays",
    "splitEntries",
  ]

  /// Device-local tables, permanently excluded from synchronization.
  ///
  /// Keeping them unregistered has a second benefit: SQLiteData's account-change wipe only
  /// empties *registered* tables, so these survive a sign-out regardless.
  public static let deviceLocalTableNames: [String] = [
    "deviceHealthSamples",
    "deviceRestTimer",
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

    // Only ever safe before the first release. Once a build is in anyone's hands this
    // must be gone, or a schema tweak silently destroys their history.
    #if DEBUG
      migrator.eraseDatabaseOnSchemaChange = true
    #endif

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
          "plannedSets" INTEGER,
          -- Which superset this movement belongs to within this session. Nullable, and
          -- deliberately not a foreign key: a superset has no existence outside the workout it is
          -- performed in, so there is no row for it to reference.
          --
          -- Note what this does NOT do. It changes when the rest timer is armed -- once per round
          -- rather than once per set -- and nothing else. It is not a prescription: the lifter
          -- pairs their own movements, and the set counts are still theirs. See
          -- `docs/SUPERSETS-spec.md`.
          "supersetGroup" INTEGER
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
          -- A set continuing the one above it at a reduced load, with no rest between.
          --
          -- A second flag beside `isWarmup` rather than one `kind` column, because `isWarmup` has
          -- existed since this table was written and is filtered on in SQL in half a dozen
          -- places. `SetKind` in HardsetCore is the write-side type, and it is what keeps
          -- "a warm-up that is also a drop" from ever being written -- STRICT tables forbid
          -- CHECK, so that constraint cannot live here.
          --
          -- A drop does not add to any set count: it is counted as part of the set it continues.
          -- That is an adopted convention rather than a finding, and `SetCounting.dropSetConvention`
          -- is the text that says so where App Review reads it.
          "isDropSet" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "completedAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now', 'subsec'))
        ) STRICT
        """
      )
      .execute(db)

      // MARK: Splits
      //
      // A split is a PARTITION of movements the lifter already trains, across days they chose.
      // It is not a program and it does not prescribe. See `docs/SPLITS-spec.md`.
      //
      // Note what is absent: there is no `plannedSets` column anywhere below, and there never
      // will be. `sessionExercises` has one because that is the lifter typing what they intend to
      // do today; a split is the surface where the APP does the arranging, so a set-count column
      // here is the hole a prescription engine climbs through. The app has no weekly set target
      // for any muscle -- `VolumeAnalyzer.weeklyTarget` returns `.unevaluated` for all 22, and
      // that is a finding rather than a gap -- so a generated set count would be invented. Leaving
      // the column out makes it unrepresentable rather than merely discouraged, which is the same
      // move as `sessions` having no duration.
      //
      // Adding a column later is the permitted direction under the rules at the top of this file,
      // so recording a lifter's OWN per-movement set target stays available as a deliberate
      // additive change.
      try #sql(
        """
        CREATE TABLE "splits" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "name" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "isArchived" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "createdAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now', 'subsec'))
        ) STRICT
        """
      )
      .execute(db)

      // `position` orders the days and is the only thing that does. Day names are the lifter's,
      // and two days may legitimately share one -- so ordering may not be derived from the name.
      try #sql(
        """
        CREATE TABLE "splitDays" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "splitID" TEXT NOT NULL REFERENCES "splits"("id") ON DELETE CASCADE,
          "name" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "position" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "createdAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now', 'subsec'))
        ) STRICT
        """
      )
      .execute(db)

      // Three foreign keys, which puts this table in the set SQLiteData's own ON DELETE validator
      // SKIPS -- that check is gated on `foreignKeys.count == 1`. `SchemaTests` covers it instead.
      //
      // `machineID` is SET NULL rather than CASCADE, mirroring `sessionExercises`: retiring a
      // machine must not silently delete the movement from someone's plan.
      try #sql(
        """
        CREATE TABLE "splitEntries" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "splitDayID" TEXT NOT NULL REFERENCES "splitDays"("id") ON DELETE CASCADE,
          "exerciseID" TEXT NOT NULL REFERENCES "exercises"("id") ON DELETE CASCADE,
          "machineID" TEXT REFERENCES "machines"("id") ON DELETE SET NULL,
          "position" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "createdAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now', 'subsec'))
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
      // Loading a split reads every day of one split, then every entry of those days.
      try #sql(
        """
        CREATE INDEX "splitDays_on_splitID" ON "splitDays"("splitID")
        """
      )
      .execute(db)
      try #sql(
        """
        CREATE INDEX "splitEntries_on_splitDayID" ON "splitEntries"("splitDayID")
        """
      )
      .execute(db)
    }

    return migrator
  }
}
