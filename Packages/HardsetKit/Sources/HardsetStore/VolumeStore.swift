import Foundation
import HardsetCore
import SQLiteData

/// Reads the sets and the attribution a volume report needs.
///
/// Date-window sets and current exercise attribution are read from one database snapshot,
/// followed by pure arithmetic in `VolumeAnalyzer`. A concurrent edit cannot mix sets from
/// before that edit with attribution from after it.
public nonisolated struct VolumeStore: Sendable {
  private let database: any DatabaseWriter

  public init(database: any DatabaseWriter) {
    self.database = database
  }

  /// Completed sets in `[from, to)`.
  ///
  /// Half-open on purpose. A closed range double-counts any set landing exactly on a week boundary
  /// when two adjacent weeks are compared, which shows up as a phantom set in both.
  public func countableSets(from: Date, to: Date) throws -> [CountableSet] {
    try database.read { db in
      try Self.readCountableSets(from: from, to: to, in: db)
    }
  }

  /// Attribution for every exercise that is not archived.
  ///
  /// Read from the database rather than from `ExerciseCatalog`, so a user's own exercises and any
  /// row a newer app version wrote are both included. An exercise whose stored attribution is
  /// unreadable is deliberately absent, which makes its sets *unattributed* rather than silently
  /// zero — the distinction the report is built on.
  public func attributionIndex() throws -> AttributionIndex {
    let entries = try database.read { db in
      try Self.readAttributionEntries(in: db)
    }
    return AttributionIndex(entries: entries)
  }

  /// The report for one window, using a consistent snapshot for both inputs.
  public func report(from: Date, to: Date) throws -> MuscleVolumeReport {
    let (sets, entries) = try database.read { db in
      (
        try Self.readCountableSets(from: from, to: to, in: db),
        try Self.readAttributionEntries(in: db)
      )
    }
    return VolumeAnalyzer.report(
      sets: sets,
      attribution: AttributionIndex(entries: entries)
    )
  }

  /// Suspends the caller while GRDB reads one consistent, cancellable snapshot.
  public func loadRollingWeek(endingAt now: Date) async throws -> MuscleVolumeReport {
    try Task.checkCancellation()
    let from = now.addingTimeInterval(-7 * 86_400)
    let (sets, entries) = try await database.read { db in
      (
        try Self.readCountableSets(from: from, to: now, in: db),
        try Self.readAttributionEntries(in: db)
      )
    }
    try Task.checkCancellation()
    return VolumeAnalyzer.report(sets: sets, attribution: AttributionIndex(entries: entries))
  }

  /// Suspends the caller while GRDB reads the report for `window` from one snapshot.
  public func loadReport(in window: VolumeWindowRange) async throws -> MuscleVolumeReport {
    try Task.checkCancellation()
    let (sets, entries) = try await database.read { db in
      (
        try Self.readCountableSets(from: window.start, to: window.end, in: db),
        try Self.readAttributionEntries(in: db)
      )
    }
    try Task.checkCancellation()
    return VolumeAnalyzer.report(sets: sets, attribution: AttributionIndex(entries: entries))
  }

  /// The report for `window`, with the sets and attribution it was counted from and the names of the
  /// movements, all read from one snapshot.
  ///
  /// The "Worked from" account for a muscle is derived from these, so it explains the count on
  /// screen and cannot be built from a window that changed after the count was made.
  public func loadWindow(in window: VolumeWindowRange) async throws -> VolumeWindowReading {
    try Task.checkCancellation()
    let (sets, entries, movements) = try await database.read { db in
      (
        try Self.readCountableSets(from: window.start, to: window.end, in: db),
        try Self.readAttributionEntries(in: db),
        try Self.readMovements(in: db)
      )
    }
    try Task.checkCancellation()
    let attribution = AttributionIndex(entries: entries)
    return VolumeWindowReading(
      report: VolumeAnalyzer.report(sets: sets, attribution: attribution),
      sets: sets, attribution: attribution, exerciseNames: movements.names,
      importedMovements: movements.imported)
  }

  /// Every movement's name, archived ones included, and which of them a workout import created.
  private static func readMovements(in db: Database) throws
    -> (names: [ExerciseID: String], imported: Set<ExerciseID>)
  {
    var names: [ExerciseID: String] = [:]
    var imported = Set<ExerciseID>()
    for row in try Exercise.fetchAll(db) {
      let id = ExerciseID(rawValue: row.id)
      names[id] = row.name
      if CatalogSeeder.isImported(row) { imported.insert(id) }
    }
    return (names, imported)
  }

  private static func readCountableSets(from: Date, to: Date, in db: Database) throws
    -> [CountableSet]
  {
    try LoggedSet
      .where { $0.completedAt >= from }
      .where { $0.completedAt < to }
      .order { $0.completedAt }
      .fetchAll(db)
      .map { CountableSet(exerciseID: ExerciseID(rawValue: $0.exerciseID), isWarmup: $0.isWarmup) }
  }

  private static func readAttributionEntries(in db: Database) throws -> [CatalogEntry] {
    try Exercise.where { !$0.isArchived }.fetchAll(db).map(CatalogEntry.init(row:))
  }

  /// The report for the seven days ending at `now`.
  ///
  /// A rolling window, not a calendar week. A calendar week makes Monday morning look like a
  /// catastrophic drop in volume, which is an artefact of the boundary rather than anything about
  /// the training. If a calendar week is ever wanted it should be a separate, named function so
  /// the two can never be confused.
  public func rollingWeek(endingAt now: Date) throws -> MuscleVolumeReport {
    try report(from: now.addingTimeInterval(-7 * 86_400), to: now)
  }
}

/// A window's report and everything it was counted from.
public nonisolated struct VolumeWindowReading: Sendable {
  public let report: MuscleVolumeReport
  /// The window's sets, warm-ups included, as the report was given them.
  public let sets: [CountableSet]
  public let attribution: AttributionIndex
  /// Every movement's name, archived ones included: their sets are in the window too.
  public let exerciseNames: [ExerciseID: String]
  /// The movements a workout import created. Their sets are counted like any other's, and the
  /// account says which lines they are.
  public let importedMovements: Set<ExerciseID>

  public init(
    report: MuscleVolumeReport, sets: [CountableSet], attribution: AttributionIndex,
    exerciseNames: [ExerciseID: String], importedMovements: Set<ExerciseID> = []
  ) {
    self.report = report
    self.sets = sets
    self.attribution = attribution
    self.exerciseNames = exerciseNames
    self.importedMovements = importedMovements
  }

  /// A movement's name, or the same words the history uses for one that no longer exists.
  public func name(for id: ExerciseID) -> String { exerciseNames[id] ?? "Unknown movement" }
}

/// Seven local days of volume, rolling rather than a calendar week, aligned to midnight so the
/// days a heading names are exactly the days counted.
///
/// The current window is today and the six days before it, up to `now`. Each earlier window is
/// the seven whole days before the next one, midnight to midnight, so adjacent windows meet
/// without overlapping. Days are added with the calendar, so a daylight-saving change moves the
/// boundary by no wall-clock hour. A window that began at the current time of day instead moved a
/// set logged on the boundary day between two windows that both named that day.
public nonisolated struct VolumeWindowRange: Hashable, Sendable {
  /// Local midnight that opens the window, inclusive.
  public let start: Date
  /// Exclusive: `now` for the current window, otherwise the next window's `start`.
  public let end: Date
  /// An instant on the last day counted, for labelling: `now`, or noon on the day before `end`.
  public let lastDay: Date
  /// Whole weeks before the current window. Zero is the current window.
  public let weeksBack: Int

  public init(endingAt now: Date, weeksBack: Int, calendar: Calendar = .current) {
    let today = calendar.startOfDay(for: now)
    let currentStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
    self.weeksBack = max(weeksBack, 0)
    if self.weeksBack == 0 {
      start = currentStart
      end = now
      lastDay = now
    } else {
      let weeks = self.weeksBack
      let end = calendar.date(byAdding: .day, value: -7 * (weeks - 1), to: currentStart) ?? currentStart
      self.end = end
      start = calendar.date(byAdding: .day, value: -7, to: end) ?? end
      let previousDay = calendar.date(byAdding: .day, value: -1, to: end) ?? end
      lastDay = calendar.date(byAdding: .hour, value: 12, to: previousDay) ?? previousDay
    }
  }
}

/// Reads load history for one exercise, per machine.
public nonisolated struct ProgressionStore: Sendable {
  private let database: any DatabaseWriter

  public init(database: any DatabaseWriter) {
    self.database = database
  }

  /// Completed working sets for one exercise, across every machine, oldest first.
  ///
  /// Warm-ups are excluded in SQL. A warm-up reaching the analyser would be a bug, so it is not
  /// filtered defensively there — that would hide it.
  public func samples(for exerciseID: ExerciseID, limit: Int = 2_000) throws
    -> [ProgressionSample]
  {
    try database.read { db in
      try Self.readSamples(for: exerciseID, limit: limit, in: db)
    }
  }

  /// Machine names, for labelling the series. A machine the user deleted resolves to `nil` and the
  /// series is labelled generically rather than dropped — the sets were still performed.
  public func machineNames(_ ids: [MachineID]) throws -> [MachineID: String] {
    guard !ids.isEmpty else { return [:] }
    return try database.read { db in
      try Self.readMachineNames(ids, in: db)
    }
  }

  /// Everything a load-history chart needs, read from one consistent snapshot.
  public func history(for exerciseID: ExerciseID) throws -> ProgressionHistory {
    let inputs = try database.read { db in
      try Self.readHistoryInputs(for: exerciseID, in: db)
    }
    return Self.analyze(inputs, exerciseID: exerciseID)
  }

  /// Suspends the caller while GRDB reads samples and labels in one snapshot.
  public func loadHistory(for exerciseID: ExerciseID) async throws -> ProgressionHistory {
    try Task.checkCancellation()
    // Analyse on the database queue so decoding and record replay release the caller's actor,
    // just as the Progress board does. The replay uses incremental all-time comparisons.
    let history = try await database.read { db in
      Self.analyze(try Self.readHistoryInputs(for: exerciseID, in: db), exerciseID: exerciseID)
    }
    try Task.checkCancellation()
    return history
  }

  private struct HistoryInputs: Sendable {
    let samples: [ProgressionSample]
    /// The exercise's warm-ups, kept apart from `samples` so no analysis can count one, and read so
    /// the "Worked from" account can list them as left out rather than leave them missing.
    let warmups: [ProgressionSample]
    let names: [MachineID: String]
    /// Each machine's real load step, so a record on a 5 kg stack needs a genuine 5 kg.
    let increments: [MachineID: Double]
    let estimatesOneRepMax: Bool
    let assumesAddedLoad: Bool
    let requiresMachineIdentity: Bool
  }

  private static func readHistoryInputs(for exerciseID: ExerciseID, in db: Database) throws
    -> HistoryInputs
  {
    let samples = try readSamples(for: exerciseID, limit: Int.max, in: db)
    let warmups = try readWarmupSamples(for: exerciseID, in: db)
    let ids = Array(Set(samples.compactMap(\.machineID)))
    // The movement's modality decides whether its load may be estimated at all. An unknown or
    // missing modality cannot establish the whole load moved.
    let modality = try Exercise.where { $0.id.eq(exerciseID.rawValue) }.select(\.modality).fetchOne(db)
    let knownModality = modality.flatMap(ExerciseModality.init(rawValue:))
    let estimates = knownModality?.estimatesOneRepMax ?? false
    // One read for both, so labelling a history stays a single query however much it carries.
    let machines = try readMachines(ids, in: db)
    return HistoryInputs(
      samples: samples, warmups: warmups, names: machines.names, increments: machines.increments,
      estimatesOneRepMax: estimates,
      assumesAddedLoad: knownModality == nil,
      requiresMachineIdentity: knownModality == .machine || knownModality == .cable
    )
  }

  private static func analyze(_ inputs: HistoryInputs, exerciseID: ExerciseID) -> ProgressionHistory {
    let series = ProgressionAnalyzer.series(
      from: inputs.samples, exerciseID: exerciseID, estimatesOneRepMax: inputs.estimatesOneRepMax
    )
    let changes = ProgressionAnalyzer.machineChanges(from: inputs.samples)
    // Per series, never merged across machines: each machine's records are measured against its own
    // history and its own step. This replays every session, which the single-exercise screen needs
    // for every record mark; the progress board, which replays every movement, caps it instead.
    var recordSessions: [ProgressionKey: Set<SessionID>] = [:]
    var ledgers: [ProgressionKey: [BestAtWeight]] = [:]
    for one in series {
      let samples = inputs.samples.filter { $0.machineID == one.key.machineID && $0.isImported == one.key.isImported }
      recordSessions[one.key] = ProgressTrendAnalyzer.recordSessionIDs(
        samples: samples, incrementKg: one.key.machineID.flatMap { inputs.increments[$0] },
        estimatesOneRepMax: inputs.estimatesOneRepMax
      )
      ledgers[one.key] = RepMaxLedger.bests(from: samples)
    }
    return ProgressionHistory(
      series: series, machineChanges: changes, machineNames: inputs.names,
      estimatesOneRepMax: inputs.estimatesOneRepMax,
      assumesAddedLoad: inputs.assumesAddedLoad,
      requiresMachineIdentity: inputs.requiresMachineIdentity,
      recordSessionIDs: recordSessions, bestAtWeight: ledgers,
      samples: inputs.samples, warmupSamples: inputs.warmups, incrementsKg: inputs.increments
    )
  }

  private static func readSamples(for exerciseID: ExerciseID, limit: Int, in db: Database) throws
    -> [ProgressionSample]
  {
    let rows = try LoggedSet
      .where { $0.exerciseID.eq(exerciseID.rawValue) }
      .where { !$0.isWarmup }
      .order { ($0.completedAt.desc(), $0.setOrdinal.desc(), $0.id.desc()) }
      .limit(limit)
      .fetchAll(db)
    return try samples(from: rows.reversed(), in: db)
  }

  /// The exercise's warm-up sets, oldest first. Never fed to the analysers.
  private static func readWarmupSamples(for exerciseID: ExerciseID, in db: Database) throws
    -> [ProgressionSample]
  {
    let rows = try LoggedSet
      .where { $0.exerciseID.eq(exerciseID.rawValue) }
      .where { $0.isWarmup }
      .order { ($0.completedAt, $0.setOrdinal, $0.id) }
      .fetchAll(db)
    return try samples(from: rows, in: db)
  }

  /// Rows as samples, in the order given, with imported sessions marked.
  private static func samples(from rows: [LoggedSet], in db: Database) throws
    -> [ProgressionSample]
  {
    let sessionIDs = Array(Set(rows.map(\.sessionID)))
    let imported = Set(try Session.where { $0.id.in(sessionIDs) && $0.notes.like("Imported from %") }
      .select(\.id).fetchAll(db))
    return rows.map {
        ProgressionSample(
          sessionID: SessionID(rawValue: $0.sessionID),
          machineID: $0.machineID.map(MachineID.init(rawValue:)),
          weightKg: $0.weightKg,
          reps: $0.reps,
          completedAt: $0.completedAt,
          isImported: imported.contains($0.sessionID)
        )
      }
  }

  private static func readMachineNames(_ ids: [MachineID], in db: Database) throws
    -> [MachineID: String]
  {
    try readMachines(ids, in: db).names
  }

  /// Names and real load steps for the given machines, from a single query.
  private static func readMachines(_ ids: [MachineID], in db: Database) throws
    -> (names: [MachineID: String], increments: [MachineID: Double])
  {
    guard !ids.isEmpty else { return ([:], [:]) }
    let raws = ids.map(\.rawValue)
    var names: [MachineID: String] = [:]
    var increments: [MachineID: Double] = [:]
    for row in try Machine.where({ $0.id.in(raws) }).fetchAll(db) {
      let id = MachineID(rawValue: row.id)
      names[id] = row.name
      if let step = row.stackIncrementKg { increments[id] = step }
    }
    return (names, increments)
  }
}

/// One exercise's load history, ready to plot.
public nonisolated struct ProgressionHistory: Hashable, Sendable {
  public let series: [ProgressionSeries]
  public let machineChanges: [MachineChange]
  public let machineNames: [MachineID: String]
  /// `false` for a movement whose logged load is not the load moved, such as bodyweight work, so
  /// a chart can say why no one-rep max is estimated rather than blame the rep range.
  public let estimatesOneRepMax: Bool
  public let assumesAddedLoad: Bool
  /// Machine/cable movements cannot call nil equipment "Free weight".
  public let requiresMachineIdentity: Bool
  /// For each series, the sessions in which at least one record was set, so the chart can mark
  /// them. Records are the detector's alone, measured against that machine's own history.
  public let recordSessionIDs: [ProgressionKey: Set<SessionID>]
  /// For each series, the most reps ever done at each weight, heaviest first.
  public let bestAtWeight: [ProgressionKey: [BestAtWeight]]
  /// Every working set the series above were built from, across machines, oldest first. The
  /// "Worked from" account derives from these, so it explains the sets the chart used and no others.
  public let samples: [ProgressionSample]
  /// The exercise's warm-up sets, which the analysers never see. Held so an account can list them
  /// as left out.
  public let warmupSamples: [ProgressionSample]
  /// Each machine's real load step, as the record replay was given it, so the account of a record
  /// states the margin that was applied.
  public let incrementsKg: [MachineID: Double]

  public init(
    series: [ProgressionSeries],
    machineChanges: [MachineChange],
    machineNames: [MachineID: String],
    estimatesOneRepMax: Bool = true,
    assumesAddedLoad: Bool = false,
    requiresMachineIdentity: Bool = false,
    recordSessionIDs: [ProgressionKey: Set<SessionID>] = [:],
    bestAtWeight: [ProgressionKey: [BestAtWeight]] = [:],
    samples: [ProgressionSample] = [],
    warmupSamples: [ProgressionSample] = [],
    incrementsKg: [MachineID: Double] = [:]
  ) {
    self.series = series
    self.machineChanges = machineChanges
    self.machineNames = machineNames
    self.estimatesOneRepMax = estimatesOneRepMax && !assumesAddedLoad
    self.assumesAddedLoad = assumesAddedLoad
    self.requiresMachineIdentity = requiresMachineIdentity
    self.recordSessionIDs = recordSessionIDs
    self.bestAtWeight = bestAtWeight
    self.samples = samples
    self.warmupSamples = warmupSamples
    self.incrementsKg = incrementsKg
  }

  /// The load step the record replay used for a series: its machine's own, or `nil` when it has
  /// none saved, where the detector assumes one 5 lb plate.
  public func incrementKg(for key: ProgressionKey) -> Double? {
    key.machineID.flatMap { incrementsKg[$0] }
  }

  /// Label for a series. Free-weight work and a deleted machine are named rather than blank.
  public func label(for key: ProgressionKey) -> String {
    if key.isImported { return ProgressCopy.importedHistory }
    guard let machineID = key.machineID else {
      return requiresMachineIdentity || assumesAddedLoad ? ProgressCopy.noMachineRecorded : "Free weight"
    }
    return machineNames[machineID] ?? "Unnamed machine"
  }

  public var isEmpty: Bool { series.isEmpty }
}

/// One past session, summarised for a list.
public nonisolated struct SessionSummary: Hashable, Sendable, Identifiable {
  public let id: SessionID
  public let title: String
  public let timeline: SessionTimeline
  /// Distinct movements performed, in the order they were first logged.
  public let exerciseNames: [String]
  public let volume: SessionVolume

  public init(
    id: SessionID,
    title: String,
    timeline: SessionTimeline,
    exerciseNames: [String],
    volume: SessionVolume
  ) {
    self.id = id
    self.title = title
    self.timeline = timeline
    self.exerciseNames = exerciseNames
    self.volume = volume
  }

  /// A session recorded as implausibly long is quarantined rather than displayed as an
  /// achievement. The ancestor shipped 9,749-minute workouts to its history screen.
  public var hasImplausibleDuration: Bool { timeline.isImplausible }
}

/// The newest finished sessions, and how many finished sessions exist in total.
public nonisolated struct HistoryPage: Hashable, Sendable {
  /// Newest first.
  public let sessions: [SessionSummary]
  /// Every finished session, including those beyond this page.
  public let totalCount: Int

  public init(sessions: [SessionSummary], totalCount: Int) {
    self.sessions = sessions
    self.totalCount = totalCount
  }

  /// True when older finished sessions exist beyond this page.
  public var hasMore: Bool { sessions.count < totalCount }
}

/// Reads finished sessions for the history screen.
public nonisolated struct HistoryStore: Sendable {
  private let database: any DatabaseWriter

  public init(database: any DatabaseWriter) {
    self.database = database
  }

  /// Finished sessions, newest first.
  ///
  /// Open sessions are excluded: an unfinished workout belongs in the recovery path, not in
  /// history, and showing it with no duration invites the reader to think it lasted zero minutes.
  public func recentSessions(limit: Int = 50) throws -> [SessionSummary] {
    try database.read { db in try Self.readRecentSessions(limit: limit, in: db) }
  }

  /// Suspends the caller while GRDB reads the history snapshot and summaries.
  public func loadRecentSessions(limit: Int = 50) async throws -> [SessionSummary] {
    try Task.checkCancellation()
    let rows = try await database.read { db in try Self.readRecentSessions(limit: limit, in: db) }
    try Task.checkCancellation()
    return rows
  }

  /// The newest `limit` finished sessions and the count of all of them, from one snapshot, so the
  /// screen can say "latest 50 of 312" and offer the older ones rather than implying fifty is all.
  public func loadHistory(limit: Int) async throws -> HistoryPage {
    try Task.checkCancellation()
    let page = try await database.read { db in
      HistoryPage(
        sessions: try Self.readRecentSessions(limit: limit, in: db),
        totalCount: try Session.where { $0.finishedAt.isNot(nil) }.fetchCount(db)
      )
    }
    try Task.checkCancellation()
    return page
  }

  private static func readRecentSessions(limit: Int, in db: Database) throws -> [SessionSummary] {
    let sessions = try Session
      .where { $0.finishedAt.isNot(nil) }
      .order { ($0.startedAt.desc(), $0.id.desc()) }
      .limit(limit)
      .fetchAll(db)
    guard !sessions.isEmpty else { return [] }

    let sessionIDs = sessions.map(\.id)
    // Performed order. Every movement numbers its sets from zero, so ordinal alone leaves the
    // "first logged" order of two movements to however SQLite returns the tie.
    let sets = try LoggedSet
      .where { $0.sessionID.in(sessionIDs) }
      .order { ($0.completedAt, $0.setOrdinal, $0.id) }
      .fetchAll(db)

    let exerciseIDs = Array(Set(sets.map(\.exerciseID)))
    let names = exerciseIDs.isEmpty
      ? [:]
      : try Exercise
        .where { $0.id.in(exerciseIDs) }
        .fetchAll(db)
        .reduce(into: [UUID: String]()) { $0[$1.id] = $1.name }

    let setsBySession = Dictionary(grouping: sets, by: \.sessionID)

    return sessions.map { session in
      let own = setsBySession[session.id] ?? []
      var seen = Set<UUID>()
      var ordered: [String] = []
      for set in own where !seen.contains(set.exerciseID) {
        seen.insert(set.exerciseID)
        ordered.append(names[set.exerciseID] ?? "Unknown movement")
      }
      return SessionSummary(
        id: SessionID(rawValue: session.id),
        title: session.title,
        timeline: SessionTimeline(startedAt: session.startedAt, finishedAt: session.finishedAt),
        exerciseNames: ordered,
        volume: Self.volume(of: own)
      )
    }
  }

  /// Applies `SessionVolume`'s rules so the history screen and the live screen cannot disagree
  /// about what a session contained. Kept here as arithmetic over rows the query already read,
  /// rather than rebuilding `ExerciseLogState` values.
  private static func volume(of sets: [LoggedSet]) -> SessionVolume {
    var workingSets = 0
    var warmupSets = 0
    var volumeKg = 0.0
    var reps = 0
    for set in sets {
      if set.isWarmup {
        warmupSets += 1
      } else {
        workingSets += 1
        volumeKg += set.weightKg * Double(set.reps)
        reps += set.reps
      }
    }
    return SessionVolume(
      workingSets: workingSets, warmupSets: warmupSets, volumeKg: volumeKg, reps: reps
    )
  }
}
