import Foundation

/// What the widgets show, written by the app into the App Group container.
///
/// The widget never opens the database: `SyncEngine`'s triggers call into the app process, so a
/// write from the widget would fail and a read could race a migration. The app writes this file
/// after launch and after each workout ends; the widget only reads it (`DECISIONS.md` §25).
///
/// Weights stay in kilograms with the lifter's unit beside them, so the widget formats with the
/// same `WeightFormatter` as every screen. Dates are instants; the widget shows them as dates,
/// never as "3 days ago" (spec 4.5: no "days since" counts).
public struct WidgetSnapshot: Codable, Hashable, Sendable {
  public static let currentVersion = 1
  /// Movements kept for "last time": what fits the medium widget.
  public static let lastTimeLimit = 3

  public struct LastWorkout: Codable, Hashable, Sendable {
    public let startedAt: Date
    public let finishedAt: Date
    /// Nil when the length is unknown (`DECISIONS.md` §21).
    public let lengthSeconds: Double?
    public let workingSets: Int
    public let volumeKg: Double
    public let movementCount: Int

    public init(
      startedAt: Date, finishedAt: Date, lengthSeconds: Double?, workingSets: Int, volumeKg: Double,
      movementCount: Int
    ) {
      self.startedAt = startedAt
      self.finishedAt = finishedAt
      self.lengthSeconds = lengthSeconds
      self.workingSets = workingSets
      self.volumeKg = volumeKg
      self.movementCount = movementCount
    }

    /// "18 sets · 9400 kg"
    public func totalsText(formatter: WeightFormatter) -> String {
      "\(CountText.sets(workingSets)) · \(formatter.total(kilograms: volumeKg))"
    }

    /// "52:10", or "Length unknown".
    public var lengthText: String {
      lengthSeconds.map { Duration.seconds($0).clockString } ?? "Length unknown"
    }
  }

  public struct SetLine: Codable, Hashable, Sendable {
    public let weightKg: Double
    public let reps: Int

    public init(weightKg: Double, reps: Int) {
      self.weightKg = weightKg
      self.reps = reps
    }
  }

  /// The last finished session on one movement and one machine.
  public struct LastTime: Codable, Hashable, Sendable, Identifiable {
    public let exerciseID: ExerciseID
    public let machineID: MachineID?
    public let exerciseName: String
    /// The machine's display name, numbered when two in the snapshot share one. Nil for free weight.
    public let machineName: String?
    public let performedAt: Date
    /// Working sets only, in the order they were done.
    public let sets: [SetLine]

    public init(
      exerciseID: ExerciseID, machineID: MachineID?, exerciseName: String, machineName: String?,
      performedAt: Date, sets: [SetLine]
    ) {
      self.exerciseID = exerciseID
      self.machineID = machineID
      self.exerciseName = exerciseName
      self.machineName = machineName
      self.performedAt = performedAt
      self.sets = sets
    }

    public var id: ProgressionKey { ProgressionKey(exerciseID: exerciseID, machineID: machineID) }

    /// "Free weight" rather than blank, as the chart names it.
    public var equipmentText: String { machineName ?? "Free weight" }

    /// "100 kg × 8" per set, at most `limit` of them, then "+2 more sets".
    public func lines(formatter: WeightFormatter, limit: Int) -> [String] {
      let shown = sets.prefix(max(0, limit)).map {
        "\(formatter.load(kilograms: $0.weightKg)) × \($0.reps)"
      }
      let hidden = sets.count - shown.count
      guard hidden > 0 else { return shown }
      return shown + ["+\(hidden) more \(CountText.setNoun(hidden))"]
    }

    /// For VoiceOver: "Leg Press on Hammer Strength Leg Press: 100 kilograms for 8 reps, …".
    public func spokenSummary(formatter: WeightFormatter) -> String {
      let sets = sets.map { "\(formatter.spoken(kilograms: $0.weightKg)) for \(CountText.reps($0.reps))" }
      return "\(exerciseName) on \(equipmentText): \(sets.joined(separator: ", "))"
    }
  }

  public let version: Int
  public let writtenAt: Date
  public let unit: WeightUnit
  public let lastWorkout: LastWorkout?
  /// Most recently trained first.
  public let lastTimes: [LastTime]

  public init(
    version: Int = WidgetSnapshot.currentVersion, writtenAt: Date, unit: WeightUnit,
    lastWorkout: LastWorkout?, lastTimes: [LastTime]
  ) {
    self.version = version
    self.writtenAt = writtenAt
    self.unit = unit
    self.lastWorkout = lastWorkout
    self.lastTimes = lastTimes
  }

  public var formatter: WeightFormatter { WeightFormatter(unit: unit) }

  /// "Tue 7 Oct" in the lifter's locale: a date, never a count of days.
  ///
  /// Takes no "now", so it cannot become relative.
  public static func dayText(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current)
    -> String
  {
    var style = Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, timeZone: timeZone)
    style = style.weekday(.abbreviated).day().month(.abbreviated)
    return date.formatted(style)
  }
}

/// What the widget found in the App Group container.
public enum WidgetSnapshotReading: Hashable, Sendable {
  case snapshot(WidgetSnapshot)
  /// No file yet: no workout has been finished on this device since install.
  case nothingYet
  /// A file that cannot be read, or one written by a newer build. Shown calmly, never as an error.
  case unreadable
}

/// The calm words a widget shows when it has nothing to show.
public enum WidgetCopy {
  public static let nothingYet = "Your last workout shows here once you finish one."
  public static let unreadable = "Open Hardset to bring this up to date."
  public static let lastTimeTitle = "Last time"
  public static let lastWorkoutTitle = "Last workout"
}

/// The snapshot file, written whole and atomically so the widget never reads half of one.
public struct WidgetSnapshotFile: Sendable {
  /// Also in both targets' entitlements (`com.apple.security.application-groups`).
  public static let appGroupIdentifier = "group.com.hardset.app"
  public static let fileName = "widget-snapshot.json"

  public let url: URL

  public init(url: URL) {
    self.url = url
  }

  /// `containerURL(forSecurityApplicationGroupIdentifier:)` is nil when the group is not in the
  /// entitlements; the file is then simply not written, and the widget says "nothing yet".
  public init?(containerURL: URL?) {
    guard let containerURL else { return nil }
    self.init(url: containerURL.appendingPathComponent(Self.fileName))
  }

  public func write(_ snapshot: WidgetSnapshot) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(snapshot).write(to: url, options: .atomic)
  }

  public func read() -> WidgetSnapshotReading {
    guard FileManager.default.fileExists(atPath: url.path) else { return .nothingYet }
    guard let data = try? Data(contentsOf: url) else { return .unreadable }
    return Self.decode(data)
  }

  public static func decode(_ data: Data) -> WidgetSnapshotReading {
    // The version is read alone first: a newer build may have changed the rest of the shape, and
    // a body this build cannot decode is then still "newer, ignored", never half-understood.
    struct Header: Decodable { let version: Int }
    guard let header = try? JSONDecoder().decode(Header.self, from: data),
      header.version == WidgetSnapshot.currentVersion,
      let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    else { return .unreadable }
    return .snapshot(snapshot)
  }
}
