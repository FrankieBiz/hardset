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

/// The widgets' background: the app's surface on the Home Screen, and nothing on the Lock Screen.
/// The Lock Screen draws accessory widgets vibrant, desaturated to a monochrome version
/// (`WidgetRenderingMode.vibrant`), where a fixed colour would only be a slab behind the text.
struct SnapshotBackground: View {
  @Environment(\.widgetFamily) private var family

  var body: some View {
    if family == .accessoryRectangular {
      Color.clear
    } else {
      Tokens.Color.surface
    }
  }
}

/// A line's last part, kept whole: the line's other text is what gets cut. For a date, which a
/// widget must always show.
struct UncutSuffix: View {
  let text: String

  var body: some View {
    HStack(spacing: Tokens.Spacing.tight) {
      Text(verbatim: "·").accessibilityHidden(true)
      Text(text)
    }
    .layoutPriority(1)
  }
}

/// The last finished time on the machines used most recently: one in the small widget and on
/// the Lock Screen, three in the medium. Dates are dates (`WidgetSnapshot.dayText`).
struct LastTimeWidget: Widget {
  static let kind = "com.hardset.app.widget.last-time"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
      LastTimeView(reading: entry.reading)
        .containerBackground(for: .widget) { SnapshotBackground() }
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
          LastTimeColumn(lastTime: lastTime, formatter: snapshot.formatter)
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
  @Environment(\.widgetFamily) private var family

  var body: some View {
    Group {
      if family == .accessoryRectangular {
        lockScreenLines
      } else {
        homeScreenLines
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(spokenLabel)
  }

  /// The name, the machine, up to two sets, and the date.
  ///
  /// A small or medium widget is about 158 pt tall, with some 126 pt inside its margins. The name,
  /// the machine, two sets, "+N more sets" and the date are six rows, about 122 pt at the default
  /// text size. Three sets made seven, about 142 pt, and the name and the date were cut. Where six
  /// rows do not fit, at larger text, one set is shown, and at the largest sizes the "+N more sets"
  /// row goes too, leaving four. A set line goes, never the date.
  private var homeScreenLines: some View {
    let oneSet = lastTime.lines(formatter: formatter, limit: 1)
    return ViewThatFits(in: .vertical) {
      homeScreenStack(lastTime.lines(formatter: formatter, limit: 2))
      homeScreenStack(oneSet)
      // The last choice is also the one shown when none fits.
      homeScreenStack(Array(oneSet.prefix(1)))
    }
  }

  private func homeScreenStack(_ lines: [String]) -> some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
      Text(lastTime.exerciseName).font(.headline).lineLimit(1)
      Text(lastTime.equipmentText).font(Tokens.Text.caption).foregroundStyle(.secondary).lineLimit(1)
      // By position, not by text: two sets of "100 kg × 8" are two lines, not one.
      ForEach(lines.indices, id: \.self) { index in
        Text(lines[index]).font(Tokens.Text.caption).monospacedDigit()
      }
      Text(WidgetSnapshot.dayText(lastTime.performedAt))
        .font(Tokens.Text.caption).foregroundStyle(.secondary)
    }
  }

  /// Three caption lines, what the rectangular slot holds: the name; the machine and the date,
  /// where the machine's name is what gets cut (in the middle, so "(2)" stays); and one set, with
  /// "+2 more sets" only when it fits.
  @ViewBuilder private var lockScreenLines: some View {
    let lines = lastTime.lines(formatter: formatter, limit: 1)
    VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
      Text(lastTime.exerciseName).font(Tokens.Text.caption.weight(.semibold)).lineLimit(1)
      HStack(spacing: Tokens.Spacing.tight) {
        Text(lastTime.equipmentText).foregroundStyle(.secondary).truncationMode(.middle)
        UncutSuffix(text: WidgetSnapshot.dayText(lastTime.performedAt))
      }
      .font(Tokens.Text.caption)
      .lineLimit(1)
      if let first = lines.first {
        ViewThatFits(in: .horizontal) {
          Text(lines.joined(separator: " · "))
          Text(first)
        }
        .font(Tokens.Text.caption)
        .monospacedDigit()
        .lineLimit(1)
      }
    }
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
        .containerBackground(for: .widget) { SnapshotBackground() }
    }
    .configurationDisplayName("Last workout")
    .description("Your last finished workout, as it was saved.")
    .supportedFamilies([.systemSmall, .accessoryRectangular])
  }
}

struct LastWorkoutView: View {
  let reading: WidgetSnapshotReading
  @Environment(\.widgetFamily) private var family

  var body: some View {
    if case .snapshot(let snapshot) = reading, let workout = snapshot.lastWorkout {
      Group {
        if family == .accessoryRectangular {
          // Three caption lines: the title and the date (kept whole), the totals, the length.
          VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
            HStack(spacing: Tokens.Spacing.tight) {
              Text(WidgetCopy.lastWorkoutTitle).foregroundStyle(.secondary)
              UncutSuffix(text: WidgetSnapshot.dayText(workout.finishedAt))
                .font(Tokens.Text.caption.weight(.semibold))
            }
            .lineLimit(1)
            Text(workout.totalsText(formatter: snapshot.formatter)).lineLimit(1)
            Text(workout.lengthText).monospacedDigit().lineLimit(1)
          }
          .font(Tokens.Text.caption)
        } else {
          VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
            Text(WidgetCopy.lastWorkoutTitle).font(Tokens.Text.caption).foregroundStyle(.secondary)
            Text(WidgetSnapshot.dayText(workout.finishedAt)).font(.headline)
            Text(workout.totalsText(formatter: snapshot.formatter)).font(Tokens.Text.caption)
            Text(workout.lengthText).font(Tokens.Text.caption).monospacedDigit()
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .combine)
    } else {
      SnapshotEmptyView(reading: reading)
    }
  }
}
