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
    let inputs = try await database.read { db in
      try Self.readHistoryInputs(for: exerciseID, in: db)
    }
    try Task.checkCancellation()
    return Self.analyze(inputs, exerciseID: exerciseID)
  }

  private struct HistoryInputs: Sendable {
    let samples: [ProgressionSample]
    let names: [MachineID: String]
    let estimatesOneRepMax: Bool
  }

  private static func readHistoryInputs(for exerciseID: ExerciseID, in db: Database) throws
    -> HistoryInputs
  {
    let samples = try readSamples(for: exerciseID, limit: Int.max, in: db)
    let ids = Array(Set(samples.compactMap(\.machineID)))
    // The movement's modality decides whether its load may be estimated at all. An unknown or
    // missing modality is not assumed to be bodyweight.
    let modality = try Exercise.where { $0.id.eq(exerciseID.rawValue) }.select(\.modality).fetchOne(db)
    let estimates = modality.flatMap(ExerciseModality.init(rawValue:))?.estimatesOneRepMax ?? true
    return HistoryInputs(
      samples: samples, names: try readMachineNames(ids, in: db), estimatesOneRepMax: estimates
    )
  }

  private static func analyze(_ inputs: HistoryInputs, exerciseID: ExerciseID) -> ProgressionHistory {
    let series = ProgressionAnalyzer.series(
      from: inputs.samples, exerciseID: exerciseID, estimatesOneRepMax: inputs.estimatesOneRepMax
    )
    let changes = ProgressionAnalyzer.machineChanges(from: inputs.samples)
    return ProgressionHistory(
      series: series, machineChanges: changes, machineNames: inputs.names,
      estimatesOneRepMax: inputs.estimatesOneRepMax
    )
  }

  private static func readSamples(for exerciseID: ExerciseID, limit: Int, in db: Database) throws
    -> [ProgressionSample]
  {
    try LoggedSet
      .where { $0.exerciseID.eq(exerciseID.rawValue) }
      .where { !$0.isWarmup }
      .order { ($0.completedAt.desc(), $0.setOrdinal.desc(), $0.id.desc()) }
      .limit(limit)
      .fetchAll(db)
      .reversed()
      .map {
        ProgressionSample(
          sessionID: SessionID(rawValue: $0.sessionID),
          machineID: $0.machineID.map(MachineID.init(rawValue:)),
          weightKg: $0.weightKg,
          reps: $0.reps,
          completedAt: $0.completedAt
        )
      }
  }

  private static func readMachineNames(_ ids: [MachineID], in db: Database) throws
    -> [MachineID: String]
  {
    guard !ids.isEmpty else { return [:] }
    let raws = ids.map(\.rawValue)
    return try Machine
      .where { $0.id.in(raws) }
      .fetchAll(db)
      .reduce(into: [MachineID: String]()) { $0[MachineID(rawValue: $1.id)] = $1.name }
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

  public init(
    series: [ProgressionSeries],
    machineChanges: [MachineChange],
    machineNames: [MachineID: String],
    estimatesOneRepMax: Bool = true
  ) {
    self.series = series
    self.machineChanges = machineChanges
    self.machineNames = machineNames
    self.estimatesOneRepMax = estimatesOneRepMax
  }

  /// Label for a series. Free-weight work and a deleted machine are named rather than blank.
  public func label(for key: ProgressionKey) -> String {
    guard let machineID = key.machineID else { return "Free weight" }
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
      .order { $0.startedAt.desc() }
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

  /// Reuses `SessionVolume`'s rules so the history screen and the live screen cannot disagree
  /// about what a session contained.
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
