import Foundation
import SQLiteData

// Every table name is written out explicitly rather than left to the @Table macro's
// pluralisation. Renaming a table is permanently disallowed, so the name must not depend on
// a derivation rule that could differ from what the migration created.
//
// All of these are `nonisolated`: this module defaults to MainActor isolation, and table
// types are read and written from database queues.

@Table("exercises")
nonisolated struct Exercise: Hashable, Identifiable, Sendable {
  let id: UUID
  var name = ""
  /// What the curated catalogue last shipped as this exercise's name. Compared against `name` to
  /// decide whether a catalogue correction may overwrite it. Empty for user-created rows.
  var curatedName = ""
  /// Stable key for curated entries; nil for user-created ones.
  ///
  /// Deliberately not UNIQUE -- it cannot be. Curated rows carry fixed primary keys from the
  /// bundled catalogue instead, which makes seeding idempotent by primary key.
  var catalogSlug: String?
  var isCurated = false
  var modality = "unknown"
  var primaryMuscle = "unknown"
  var secondaryMusclesJSON = "[]"
  var notes = ""
  /// Soft delete. Hard-deleting a curated row would resurrect it on the next seed.
  var isArchived = false
  var createdAt = Date(timeIntervalSince1970: 0)
}

@Table("gyms")
nonisolated struct Gym: Hashable, Identifiable, Sendable {
  let id: UUID
  var name = ""
  var isArchived = false
  var createdAt = Date(timeIntervalSince1970: 0)
}

@Table("machines")
nonisolated struct Machine: Hashable, Identifiable, Sendable {
  let id: UUID
  var gymID: UUID
  var name = ""
  /// Smallest load step this machine allows, when known. Drives honest progression
  /// suggestions: proposing +2.5 kg on a stack that moves in 5 kg jumps is a lie.
  ///
  /// This is the whole load description of a machine. A `loadType` column sat beside it holding
  /// the literal "unknown" for every row ever written -- nothing set it and nothing read it, and
  /// what it would have described (how the thing is loaded) only ever mattered as the step size,
  /// which is this. It was removed before the schema froze, because SQLiteData forbids removing a
  /// column afterwards and permits adding one, so the asymmetry runs in favour of deleting now.
  var stackIncrementKg: Double?
  var isArchived = false
  var createdAt = Date(timeIntervalSince1970: 0)
}

@Table("machineExercises")
nonisolated struct MachineExercise: Hashable, Identifiable, Sendable {
  /// Present only because every synchronized table needs a single non-compound primary key.
  let id: UUID
  var machineID: UUID
  var exerciseID: UUID
  var createdAt = Date(timeIntervalSince1970: 0)
}

extension MachineExercise {
  /// The existing association between one machine and one exercise, if there is one.
  ///
  /// A named `static func` taking `db` rather than an inline query, because inside
  /// `database.write { db in ... }` an anonymous `$0` in a nested StructuredQueries closure binds
  /// to the OUTER `db` and type-checks far enough to produce a misleading diagnostic. It also gives
  /// the predicate one definition instead of one per caller.
  nonisolated static func existing(machineID: UUID, exerciseID: UUID, in db: Database) throws
    -> MachineExercise?
  {
    try MachineExercise
      .where { $0.machineID.eq(machineID) && $0.exerciseID.eq(exerciseID) }
      .fetchOne(db)
  }
}

@Table("sessions")
nonisolated struct Session: Hashable, Identifiable, Sendable {
  let id: UUID
  var gymID: UUID?
  var title = ""
  var notes = ""
  /// Immutable. Together with `finishedAt` this is the only source of duration.
  var startedAt = Date(timeIntervalSince1970: 0)
  /// nil means the session is still open. Never backfilled from `Date()`.
  var finishedAt: Date?
}

@Table("sessionExercises")
nonisolated struct SessionExercise: Hashable, Identifiable, Sendable {
  let id: UUID
  var sessionID: UUID
  var exerciseID: UUID
  var machineID: UUID?
  var position = 0
  var plannedSets: Int?
  /// Which superset this movement is part of within this session, or nil when it stands alone.
  ///
  /// Session-scoped and meaningless outside it, which is why it is a plain number rather than a
  /// reference to a `supersets` table -- there is nothing else that would ever point at one. It
  /// changes only when the rest timer is armed, never what is recorded.
  var supersetGroup: Int?
}

@Table("loggedSets")
nonisolated struct LoggedSet: Hashable, Identifiable, Sendable {
  let id: UUID
  var sessionID: UUID
  var exerciseID: UUID
  /// Which physical machine. This is what makes progression machine-level rather than
  /// exercise-level.
  var machineID: UUID?
  /// The `sessionExercises` row this set was logged against. Nullable for rows written before the
  /// column existed, and for any path that does not know its plan row.
  var sessionExerciseID: UUID?
  var setOrdinal = 0
  /// Canonical kilograms. Conversion to pounds happens only at the UI boundary.
  var weightKg = 0.0
  var reps = 0
  var rpe: Double?
  var isWarmup = false
  /// A set continuing the one above it at a reduced load, taken with no rest between.
  ///
  /// Two flags rather than one `kind` column because `isWarmup` predates this and is filtered on
  /// in SQL in half a dozen places; `SetKind` is the write-side type that keeps the fourth
  /// combination from being written, since `STRICT` tables cannot carry a `CHECK`.
  var isDropSet = false
  var completedAt = Date(timeIntervalSince1970: 0)
}

// MARK: - Splits
//
// A partition of movements the lifter already trains, across days they chose. Note the absence of
// any set-count column on `SplitEntry`: see the migration's note, and `docs/SPLITS-spec.md`.

@Table("splits")
nonisolated struct Split: Hashable, Identifiable, Sendable {
  let id: UUID
  var name = ""
  /// Soft delete, so a plan can be put away without taking its history of edits with it.
  var isArchived = false
  var createdAt = Date(timeIntervalSince1970: 0)
}

@Table("splitDays")
nonisolated struct SplitDay: Hashable, Identifiable, Sendable {
  let id: UUID
  var splitID: UUID
  /// The lifter's. Two days may share a name, so this may never be used for ordering.
  var name = ""
  var position = 0
  var createdAt = Date(timeIntervalSince1970: 0)
}

@Table("splitEntries")
nonisolated struct SplitEntry: Hashable, Identifiable, Sendable {
  let id: UUID
  var splitDayID: UUID
  var exerciseID: UUID
  /// Which physical machine this movement is planned on, when the lifter has said. Naming one here
  /// is what adds it to the gym's library — see `SplitStore.addEntry`.
  var machineID: UUID?
  var position = 0
  var createdAt = Date(timeIntervalSince1970: 0)
}

@Table("bodyweightEntries")
nonisolated struct BodyweightEntry: Hashable, Identifiable, Sendable {
  let id: UUID
  var weightKg = 0.0
  var measuredAt = Date(timeIntervalSince1970: 0)
  /// Always "manual" in v1. Present so a future HealthKit-sourced row is distinguishable
  /// without a schema change -- adding a column later is allowed, renaming one is not.
  var enteredBy = "manual"
}

// MARK: - Device-local tables
//
// These are never registered with the SyncEngine. Note that SQLiteData's account-change
// wipe only empties *registered* tables, so keeping these out of the sync list also keeps
// them safe from `deleteLocalData()`.

@Table("deviceHealthSamples")
nonisolated struct DeviceHealthSample: Hashable, Identifiable, Sendable {
  let id: UUID
  var kind = "unknown"
  var value = 0.0
  var unit = ""
  var startedAt = Date(timeIntervalSince1970: 0)
  var endedAt: Date?
}

@Table("deviceRestTimer")
nonisolated struct DeviceRestTimer: Hashable, Identifiable, Sendable {
  let id: UUID
  var sessionID: UUID?
  /// The AlarmKit alarm currently backing this timer, so it can be cancelled on relaunch.
  var alarmID: UUID?
  /// Exactly one of `endsAt` / `pausedRemainingSeconds` is non-nil, or both are nil when
  /// idle. `RestTimerState` is the only thing that should construct these two values.
  var endsAt: Date?
  var pausedRemainingSeconds: Double?
  var updatedAt = Date(timeIntervalSince1970: 0)
}
