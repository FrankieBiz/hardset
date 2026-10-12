import HardsetStore
import SQLiteData

/// Everything the app needs, constructed once.
///
/// Assembled here rather than in the app target because the app target cannot be compiled from a
/// sandboxed command line, so anything that lives there is unverifiable. This builds and previews
/// on the host.
@MainActor
public struct HardsetEnvironment {
  public let logger: LoggerStore
  public let catalog: CatalogSeeder
  public let volume: VolumeStore
  public let history: HistoryStore
  public let progression: ProgressionStore
  public let gyms: GymStore
  /// Reads a finished workout's summary back from the database.
  public let summaries: WorkoutSummaryStore
  /// The picker's Recent movements, and "Repeat this workout".
  public let shortcuts: WorkoutShortcutsStore
  /// Reads a past workout back, by movement and machine, with its records.
  public let sessionDetails: SessionDetailStore

  /// Whether the first screen shows, and ends it.
  public let firstRun: FirstRunStore
  /// The widgets' snapshot, from finished workouts only. The app writes it; the widget only
  /// reads the file (`DECISIONS.md` §25).
  public let widgetSnapshots: WidgetSnapshotStore

  /// `firstRunFlag` defaults to the real one, so the app's `HardsetEnvironment(database:)` persists
  /// the flag without passing anything.
  public init(
    database: any DatabaseWriter,
    firstRunFlag: any FirstRunFlag = UserDefaultsFirstRunFlag()
  ) {
    self.logger = LoggerStore(database: database)
    self.catalog = CatalogSeeder(database: database)
    self.volume = VolumeStore(database: database)
    self.history = HistoryStore(database: database)
    self.progression = ProgressionStore(database: database)
    self.gyms = GymStore(database: database)
    self.summaries = WorkoutSummaryStore(database: database)
    self.shortcuts = WorkoutShortcutsStore(database: database)
    self.sessionDetails = SessionDetailStore(database: database)
    self.firstRun = FirstRunStore(database: database, flag: firstRunFlag)
    self.widgetSnapshots = WidgetSnapshotStore(database: database)
  }
}
