import HardsetCore
import SwiftUI

/// A row's worth of a past session, with no dependency on storage.
public struct HistoryRow: Hashable, Sendable, Identifiable {
  public let id: SessionID
  public let title: String
  public let date: Date
  public let duration: Duration?
  public let exerciseNames: [String]
  public let volume: SessionVolume
  /// A recorded span longer than any real workout. Rendered as a caveat rather than a boast.
  public let hasImplausibleDuration: Bool

  public init(
    id: SessionID,
    title: String,
    date: Date,
    duration: Duration?,
    exerciseNames: [String],
    volume: SessionVolume,
    hasImplausibleDuration: Bool
  ) {
    self.id = id
    self.title = title
    self.date = date
    self.duration = duration
    self.exerciseNames = exerciseNames
    self.volume = volume
    self.hasImplausibleDuration = hasImplausibleDuration
  }
}

/// Past workouts, newest first.
///
/// The one thing this screen must not do is present a broken record as an achievement. The
/// ancestor app shipped 9,749-minute workouts here — a session left running overnight, its
/// duration recomputed against the wall clock — and rendered them as personal bests. A session
/// whose recorded span is longer than any real workout is shown with the span replaced by a
/// caveat, because the honest thing to say is "we do not know how long this took", not "20 hours".
public struct HistoryView: View {
  private let rows: [HistoryRow]
  private let unit: WeightUnit
  private let onSelect: ((HistoryRow) -> Void)?
  private let onRepeat: ((HistoryRow) -> Void)?

  public init(
    rows: [HistoryRow],
    unit: WeightUnit,
    onSelect: ((HistoryRow) -> Void)? = nil,
    onRepeat: ((HistoryRow) -> Void)? = nil
  ) {
    self.rows = rows
    self.unit = unit
    self.onSelect = onSelect
    self.onRepeat = onRepeat
  }

  public var body: some View {
    List {
      if rows.isEmpty {
        ContentUnavailableView {
          Label("No workouts yet", systemImage: "clock.arrow.circlepath")
        } description: {
          Text("Finished workouts appear here.")
        }
      } else {
        ForEach(rows) { row in
          if let onRepeat {
            // Offered only when the caller asks for it, and never preselected or suggested: the
            // lifter starts a repeat deliberately, from one row.
            selectable(row)
              .contextMenu {
                Button("Repeat this workout", systemImage: "arrow.clockwise") { onRepeat(row) }
              }
              .accessibilityAction(named: Text("Repeat this workout")) { onRepeat(row) }
          } else {
            selectable(row)
          }
        }
      }
    }
  }

  /// A button only when there is something to select. A disabled button made VoiceOver read every
  /// row as "dimmed", so a read-only row is plain content instead.
  @ViewBuilder private func selectable(_ row: HistoryRow) -> some View {
    if let onSelect {
      Button {
        onSelect(row)
      } label: {
        content(row)
      }
      .buttonStyle(.plain)
    } else {
      content(row)
    }
  }

  private func content(_ row: HistoryRow) -> some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
      HStack(alignment: .firstTextBaseline) {
        Text(row.title.isEmpty ? Self.dateText(row.date) : row.title)
          .font(Tokens.Text.label.weight(.semibold))
        Spacer(minLength: Tokens.Spacing.snug)
        durationLabel(row)
      }

      if !row.title.isEmpty {
        Text(Self.dateText(row.date))
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.textSecondary)
      }

      Text(Self.volumeText(row.volume, unit: unit))
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.textSecondary)
        .monospacedDigit()

      if !row.exerciseNames.isEmpty {
        Text(row.exerciseNames.joined(separator: " · "))
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.textSecondary)
          .lineLimit(2)
      }
    }
    .padding(.vertical, Tokens.Spacing.tight)
    .frame(minHeight: Tokens.minimumTapTarget, alignment: .leading)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(Self.spokenLabel(row, unit: unit))
  }

  @ViewBuilder private func durationLabel(_ row: HistoryRow) -> some View {
    if let duration = row.duration, !row.hasImplausibleDuration {
      Text(duration.clockString)
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.textSecondary)
        .monospacedDigit()
    } else {
      // The honest statement. A 20-hour span means the session was left open, not that it was
      // trained through, so the number is withheld rather than displayed. A finish stamped before
      // the start (the clock moved) has no length at all, and used to show nothing, which read
      // as if the length had been left off rather than unknown.
      Label(CaveatMark.lengthUnknown.word, systemImage: CaveatMark.lengthUnknown.symbolName)
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.caveat)
    }
  }

  static func dateText(_ date: Date) -> String {
    date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
  }

  static func volumeText(_ volume: SessionVolume, unit: WeightUnit) -> String {
    SessionVolumeText.written(volume, formatter: WeightFormatter(unit: unit))
  }

  static func spokenLabel(_ row: HistoryRow, unit: WeightUnit) -> String {
    var parts = [row.title.isEmpty ? dateText(row.date) : "\(row.title), \(dateText(row.date))"]
    parts.append(SessionVolumeText.spoken(row.volume, formatter: WeightFormatter(unit: unit)))
    if row.hasImplausibleDuration {
      parts.append("length unknown, this session was left open")
    } else if let duration = row.duration {
      parts.append(duration.clockString)
    } else {
      parts.append("length unknown")
    }
    return parts.joined(separator: ", ")
  }
}

#if DEBUG
  private struct HistoryPreviewHarness: View {
    private let day = Date(timeIntervalSince1970: 15_000_000)

    var body: some View {
      HistoryView(
        rows: [
          HistoryRow(
            id: SessionID(), title: "Push", date: day,
            duration: .seconds(4_320),
            exerciseNames: ["Bench Press", "Overhead Press", "Cable Triceps Pushdown"],
            volume: SessionVolume(workingSets: 12, warmupSets: 2, volumeKg: 9_400, reps: 96),
            hasImplausibleDuration: false
          ),
          // Left running overnight: the span is withheld rather than shown as a 20-hour workout.
          HistoryRow(
            id: SessionID(), title: "Legs", date: day.addingTimeInterval(-172_800),
            duration: .seconds(72_000),
            exerciseNames: ["Barbell Back Squat", "Romanian Deadlift"],
            volume: SessionVolume(workingSets: 8, warmupSets: 3, volumeKg: 11_200, reps: 64),
            hasImplausibleDuration: true
          ),
          // Finished before it started, by the clock: no length at all, and said so.
          HistoryRow(
            id: SessionID(), title: "Pull", date: day.addingTimeInterval(-345_600),
            duration: nil,
            exerciseNames: ["Lat Pulldown"],
            volume: SessionVolume(workingSets: 4, warmupSets: 0, volumeKg: 2_400, reps: 40),
            hasImplausibleDuration: false
          ),
        ],
        unit: .kilograms,
        onSelect: { _ in }
      )
    }
  }

  #Preview("History") {
    HistoryPreviewHarness()
  }
#endif
