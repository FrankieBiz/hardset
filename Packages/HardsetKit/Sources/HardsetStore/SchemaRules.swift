import Foundation

/// The rules the v1 schema is permanently bound by, encoded so tests can enforce them.
///
/// Read out of SQLiteData 1.10.0's documentation and validation code rather than recalled.
/// The CloudKit directory is byte-identical between 1.9.0 and 1.10.0, so these hold for both.
///
/// Critically, the library validates only *some* of these. The rest fail silently at sync
/// time or at ship time, which is why they are written down here and asserted in tests.
// `nonisolated` is deliberate. This module defaults to MainActor isolation, which is right
// for view-facing types and wrong for this: schema work runs on GRDB's database queues and
// these declarations are pure. Isolating them to the main actor would both mislead and
// force every caller -- including the test suite -- to hop actors for no reason.
public nonisolated enum SchemaRules {
  /// CloudKit's own reserved `CKRecord` field names.
  ///
  /// Source: SQLiteData `Documentation.docc/Articles/CloudKitSync.md`, "Avoid reserved
  /// CloudKit keywords". Nothing in the library validates these -- there is no reserved-name
  /// list in its source at all -- so a collision surfaces as a sync failure in the field,
  /// never as a build or construction error. That makes this list a review checklist, not a
  /// safety net. Apple has not published an exhaustive list, so treat it as a floor.
  public static let cloudKitReservedColumnNames: Set<String> = [
    "creationDate",
    "creatorUserRecordID",
    "etag",
    "lastModifiedUserRecordID",
    "modificationDate",
    "modifiedByDevice",
    "recordChangeTag",
    "recordID",
    "recordType",
  ]

  /// Names SQLiteData itself writes into every `CKRecord` alongside your columns.
  ///
  /// The library adds `sqlitedata_icloud_userModificationTime`, a per-column
  /// `sqlitedata_icloud_userModificationTime_<column>`, a `<column>_hash` for every BLOB
  /// column, and `_recordChangeTag`. It also owns the attached schema name
  /// `sqlitedata_icloud` and every `sqlitedata_icloud_*` trigger and SQL function.
  ///
  /// The practical consequences for column naming: never prefix a column
  /// `sqlitedata_icloud`, and never name a column `<somethingElse>_hash` where the app also
  /// has a BLOB column called `<somethingElse>`.
  public static let libraryReservedPrefixes: Set<String> = ["sqlitedata_icloud", "_"]

  /// `ON DELETE` actions SQLiteData supports. Anything else -- including *omitting*
  /// `ON DELETE`, since SQLite then defaults to `NO ACTION` -- throws at construction.
  public static let supportedDeleteActions: Set<String> = ["CASCADE", "SET NULL", "SET DEFAULT"]

  /// Tables whose names begin with this prefix are device-local and must never be handed to
  /// the `SyncEngine`. Asserted in `SchemaTests`.
  public static let deviceLocalTablePrefix = "device"

  /// Constraints the library validates at `SyncEngine.init`, before any network access.
  /// Listed so the validation test's coverage is explicit rather than assumed.
  public static let validatedAtConstruction = """
    - UNIQUE anywhere but the primary key (any index whose pragma origin is not "pk", \
    which includes CREATE UNIQUE INDEX, inline UNIQUE, UNIQUE(a,b) and partial unique indexes)
    - Foreign key cycles, INCLUDING a table that references itself
    - A foreign key pointing at a table not registered for sync
    - An ON DELETE action outside CASCADE / SET NULL / SET DEFAULT
    """

  /// Constraints that are NOT validated and therefore need human review or a bespoke test.
  ///
  /// Every item here is a way to ship a permanently broken schema with a green test suite.
  public static let notValidatedAnywhere = """
    - Removing a column, renaming a column, renaming a table. Documented as permanently \
    disallowed; nothing detects it. Fails silently at sync time.
    - Reserved CloudKit column names. No validation exists in the library.
    - Compound primary keys. Documented as disallowed, but a composite PK's pragma origin is \
    "pk" so it slips past the uniqueness check.
    - NOT NULL columns lacking a default. The library's own check for this is dead code.
    - ON DELETE actions on tables with 2 or more foreign keys. The validator is gated on \
    `foreignKeys.count == 1`, so multi-FK tables are skipped entirely and must be audited \
    by hand -- in this schema that means machineExercises, sessionExercises and loggedSets.
    """

  /// Primary keys are encoded into a `CKRecord`'s `recordName` as `<primaryKey>:<tableName>`,
  /// which must be ASCII, under 255 bytes, and must not begin with an underscore. Enforced by
  /// a `RAISE(ABORT)` trigger on insert and update -- at write time, not at construction.
  public static func isValidRecordName(primaryKey: String, tableName: String) -> Bool {
    let composed = "\(primaryKey):\(tableName)"
    return !primaryKey.isEmpty
      && !tableName.contains(":")
      && composed.utf8.count < 255
      && !composed.hasPrefix("_")
      && composed.allSatisfy(\.isASCII)
  }

  /// Screens a column name against everything known to be unusable.
  public static func isValidColumnName(_ name: String) -> Bool {
    guard !cloudKitReservedColumnNames.contains(name) else { return false }
    return !libraryReservedPrefixes.contains { name.hasPrefix($0) }
  }
}
