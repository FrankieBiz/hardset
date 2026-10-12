import HardsetCore
import HardsetUI
import SwiftUI
import WidgetKit

/// `nonisolated`, as the provider is: WidgetKit's timeline protocols are not main-actor, and this
/// target's default isolation is.
nonisolated struct SnapshotEntry: TimelineEntry {
  let date: Date
  let reading: WidgetSnapshotReading
}

/// Reads the app's file and nothing else: never the database (`DECISIONS.md` §25). One entry and
/// no schedule, because the app reloads the timelines whenever it writes.
///
/// `nonisolated` so its conformance is not main-actor: WidgetKit calls these from its own queue.
/// The completions are `@Sendable`, exactly as the SDK declares them.
nonisolated struct SnapshotProvider: TimelineProvider {
  func placeholder(in context: Context) -> SnapshotEntry {
    SnapshotEntry(date: .now, reading: .nothingYet)
  }

  func getSnapshot(in context: Context, completion: @escaping @Sendable (SnapshotEntry) -> Void) {
    completion(entry())
  }

  func getTimeline(
    in context: Context, completion: @escaping @Sendable (Timeline<SnapshotEntry>) -> Void
  ) {
    completion(Timeline(entries: [entry()], policy: .never))
  }

  private func entry() -> SnapshotEntry {
    let container = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: WidgetSnapshotFile.appGroupIdentifier)
    return SnapshotEntry(
      date: .now, reading: WidgetSnapshotFile(containerURL: container)?.read() ?? .nothingYet)
  }
}

/// Shown for "nothing yet" and "unreadable": calm, counting nothing.
struct SnapshotEmptyView: View {
  let reading: WidgetSnapshotReading

  var body: some View {
    Text(reading == .unreadable ? WidgetCopy.unreadable : WidgetCopy.nothingYet)
      .font(Tokens.Text.caption)
      .foregroundStyle(.secondary)
  }
}

/// The last finished time on the machines used most recently: one in the small widget and on
/// the Lock Screen, three in the medium. Dates are dates (`WidgetSnapshot.dayText`).
struct LastTimeWidget: Widget {
  static let kind = "com.hardset.app.widget.last-time"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
      LastTimeView(reading: entry.reading)
        .containerBackground(Tokens.Color.surface, for: .widget)
    }
    .configurationDisplayName("Last time")
    .description("What you lifted last time on the machines you used most recently.")
    .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
  }
}

struct LastTimeView: View {
  let reading: WidgetSnapshotReading
  @Environment(\.widgetFamily) private var family

  var body: some View {
    if case .snapshot(let snapshot) = reading, !snapshot.lastTimes.isEmpty {
      let shown = family == .systemMedium ? snapshot.lastTimes : Array(snapshot.lastTimes.prefix(1))
      HStack(alignment: .top, spacing: Tokens.Spacing.regular) {
        ForEach(shown) { lastTime in
          LastTimeColumn(
            lastTime: lastTime, formatter: snapshot.formatter,
            lineLimit: family == .accessoryRectangular ? 2 : 3)
        }
      }
    } else {
      SnapshotEmptyView(reading: reading)
    }
  }
}

struct LastTimeColumn: View {
  let lastTime: WidgetSnapshot.LastTime
  let formatter: WeightFormatter
  let lineLimit: Int

  var body: some View {
    // By position, not by text: three sets of "100 kg × 8" are three lines, not one.
    let lines = lastTime.lines(formatter: formatter, limit: lineLimit)
    VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
      Text(lastTime.exerciseName).font(.headline).lineLimit(1)
      Text(lastTime.equipmentText).font(Tokens.Text.caption).foregroundStyle(.secondary).lineLimit(1)
      ForEach(lines.indices, id: \.self) { index in
        Text(lines[index]).font(Tokens.Text.caption).monospacedDigit()
      }
      Text(WidgetSnapshot.dayText(lastTime.performedAt))
        .font(Tokens.Text.caption).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(spokenLabel)
  }

  /// "Last time, Tue 7 Oct. Leg Press on Hammer Strength Leg Press: 100 kilograms for 8 reps, …"
  private var spokenLabel: String {
    let day = WidgetSnapshot.dayText(lastTime.performedAt)
    return "\(WidgetCopy.lastTimeTitle), \(day). \(lastTime.spokenSummary(formatter: formatter))"
  }
}

/// The last finished workout: when, how many working sets, the volume, and its length or
/// "Length unknown". No comparison and no count of days since.
struct LastWorkoutWidget: Widget {
  static let kind = "com.hardset.app.widget.last-workout"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
      LastWorkoutView(reading: entry.reading)
        .containerBackground(Tokens.Color.surface, for: .widget)
    }
    .configurationDisplayName("Last workout")
    .description("Your last finished workout, as it was saved.")
    .supportedFamilies([.systemSmall, .accessoryRectangular])
  }
}

struct LastWorkoutView: View {
  let reading: WidgetSnapshotReading

  var body: some View {
    if case .snapshot(let snapshot) = reading, let workout = snapshot.lastWorkout {
      VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
        Text(WidgetCopy.lastWorkoutTitle).font(Tokens.Text.caption).foregroundStyle(.secondary)
        Text(WidgetSnapshot.dayText(workout.finishedAt)).font(.headline)
        Text(workout.totalsText(formatter: snapshot.formatter)).font(Tokens.Text.caption)
        Text(workout.lengthText).font(Tokens.Text.caption).monospacedDigit()
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .combine)
    } else {
      SnapshotEmptyView(reading: reading)
    }
  }
}
