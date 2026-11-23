import Foundation

/// Every trained movement, grouped by body part, ready to list on the Progress tab.
///
/// A row is one movement on one machine: the same movement on two machines is two rows, as it is
/// two series everywhere else, and is never merged. Movements are filed under the body part the
/// lifter or the catalogue gave them. One with none is not guessed into a group; it sits last,
/// where it can be seen and tagged.
public struct ProgressBoard: Hashable, Sendable {
  public let sections: [Section]
  /// The largest six-week estimated-max gains across movements, whichever section each is in.
  /// Added-load changes have their own list and never compete with these percentages.
  public let mostImproved: [Row]
  /// Added-load percentages are ranked only within this separate list.
  public let mostImprovedAddedLoad: [Row]

  public struct Row: Hashable, Sendable, Identifiable {
    public let trend: MovementTrend
    public let exerciseName: String
    public let machineName: String?

    public var id: ProgressionKey { trend.key }

    public init(trend: MovementTrend, exerciseName: String, machineName: String? = nil) {
      self.trend = trend
      self.exerciseName = exerciseName
      self.machineName = machineName
    }
  }

  public struct Section: Hashable, Sendable, Identifiable {
    /// `nil` is the movements with no body part yet.
    public let category: MuscleFilterCategory?
    public let rows: [Row]

    public var id: MuscleFilterCategory? { category }

    public init(category: MuscleFilterCategory?, rows: [Row]) {
      self.category = category
      self.rows = rows
    }
  }

  /// A row with the body part its movement is filed under, before grouping.
  public struct Entry: Hashable, Sendable {
    public let row: Row
    public let bodyPart: MuscleFilterCategory?

    public init(row: Row, bodyPart: MuscleFilterCategory?) {
      self.row = row
      self.bodyPart = bodyPart
    }
  }

  public static let empty = ProgressBoard(sections: [], mostImproved: [])

  /// Every row on the board, in section order.
  public var rows: [Row] { sections.flatMap(\.rows) }

  /// Whether any row is imported history, so the board says once that imported rows stand apart.
  public var hasImportedHistory: Bool { rows.contains { $0.id.isImported } }

  /// How each imported row, and each logged row beside an imported one, relates to the other
  /// source, for the rows that have something true to say.
  ///
  /// An imported series is never merged into a native one: it has its own key, its machine is
  /// unknown, and a rewrite of history would be worse than a split. What the app can say honestly
  /// is read from identity alone. A movement with both an imported series and a logged one (an
  /// import whose name matched the catalogue's) says on both rows that the other is separate. An
  /// imported movement of its own, whose name the app does not match to any other, says it is not
  /// combined with what is logged here. A logged row with no imported series says nothing, because
  /// it has nothing to point at, and two names that look alike are not evidence they are one lift.
  public var sourceNotes: [ProgressionKey: String] {
    let rows = self.rows
    let imported = Set(rows.filter { $0.id.isImported }.map { $0.id.exerciseID })
    let logged = Set(rows.filter { !$0.id.isImported }.map { $0.id.exerciseID })
    var notes: [ProgressionKey: String] = [:]
    for row in rows {
      let movement = row.id.exerciseID
      if row.id.isImported {
        notes[row.id] = logged.contains(movement) ? ProgressCopy.importedBesideLogged : ProgressCopy.importedAlone
      } else if imported.contains(movement) {
        notes[row.id] = ProgressCopy.loggedBesideImported
      }
    }
    return notes
  }

  public init(sections: [Section], mostImproved: [Row], mostImprovedAddedLoad: [Row] = []) {
    self.sections = sections
    self.mostImproved = mostImproved.filter { $0.trend.metric == .estimatedMax }
    self.mostImprovedAddedLoad = mostImprovedAddedLoad.filter { $0.trend.metric == .addedLoad }
  }

  /// Groups entries in body-part order with the untagged last, newest-trained movement first in
  /// each, and picks the movements that improved most. Empty sections are left out.
  public static func make(_ entries: [Entry]) -> ProgressBoard {
    let byBodyPart = Dictionary(grouping: entries, by: \.bodyPart)
    let order: [MuscleFilterCategory?] = MuscleFilterCategory.allCases.map { $0 } + [nil]
    let sections = order.compactMap { category -> Section? in
      guard let group = byBodyPart[category], !group.isEmpty else { return nil }
      return Section(category: category, rows: group.map(\.row).sorted(by: isListedBefore))
    }

    let rowsByKey = Dictionary(
      entries.map { ($0.row.id, $0.row) }, uniquingKeysWith: { first, _ in first })
    let improved = ProgressTrendAnalyzer.mostImproved(entries.map(\.row.trend))
      .compactMap { rowsByKey[$0.key] }
    let addedLoad = ProgressTrendAnalyzer.mostImproved(entries.map(\.row.trend), metric: .addedLoad)
      .compactMap { rowsByKey[$0.key] }
    return ProgressBoard(sections: sections, mostImproved: improved, mostImprovedAddedLoad: addedLoad)
  }

  /// Newest-trained first. Ties are broken by name, then machine, then identity, so the order never
  /// depends on how the rows were read.
  private static func isListedBefore(_ lhs: Row, _ rhs: Row) -> Bool {
    if lhs.trend.latestDate != rhs.trend.latestDate {
      return lhs.trend.latestDate > rhs.trend.latestDate
    }
    let byName = lhs.exerciseName.localizedStandardCompare(rhs.exerciseName)
    if byName != .orderedSame { return byName == .orderedAscending }
    let byMachine = (lhs.machineName ?? "").localizedStandardCompare(rhs.machineName ?? "")
    if byMachine != .orderedSame { return byMachine == .orderedAscending }
    return identity(lhs.id) < identity(rhs.id)
  }

  private static func identity(_ key: ProgressionKey) -> String {
    key.exerciseID.description + "/" + (key.machineID?.description ?? "") + "/" + String(key.isImported)
  }
}
