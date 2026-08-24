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
  /// Deletes a workout. `nil` hides the affordance.
  private let onDelete: ((HistoryRow) -> Void)?

  public init(
    rows: [HistoryRow],
    unit: WeightUnit,
    onSelect: ((HistoryRow) -> Void)? = nil,
    onDelete: ((HistoryRow) -> Void)? = nil
  ) {
    self.rows = rows
    self.unit = unit
    self.onSelect = onSelect
    self.onDelete = onDelete
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
          Button {
            onSelect?(row)
          } label: {
            content(row)
              .frame(maxWidth: .infinity, alignment: .leading)
              // Without this the hit area is the glyphs themselves, so most of the row was dead
              // space and the workout only opened if you happened to tap a word.
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .disabled(onSelect == nil)
          // Swipe rather than a menu: this is a `List`, so the gesture is the platform's own and
          // needs no discovery. It discards the workout and every set in it, which is why the
          // label says so rather than just "Delete".
          .swipeActions(edge: .trailing) {
            if let onDelete {
              Button(role: .destructive) {
                onDelete(row)
              } label: {
                Label("Delete workout", systemImage: "trash")
              }
            }
          }
        }
      }
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
    if row.hasImplausibleDuration {
      // The honest statement. A 20-hour span means the session was left open, not that it was
      // trained through, so the number is withheld rather than displayed.
      Label("Length unknown", systemImage: "exclamationmark.circle")
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.certainty(.low))
    } else if let duration = row.duration {
      Text(duration.clockString)
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.textSecondary)
        .monospacedDigit()
    }
  }

  static func dateText(_ date: Date) -> String {
    date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
  }

  static func volumeText(_ volume: SessionVolume, unit: WeightUnit) -> String {
    guard !volume.isEmpty else { return "No sets" }
    // Pluralised by hand, not with `^[...](inflect:)`. That markup is only interpreted inside a
    // `LocalizedStringKey` -- an inline `Text("...")` literal -- and these parts are joined into a
    // `String` that reaches `Text(String)`, which renders the markup verbatim. It shipped on screen
    // as "^[1 set](inflect: true)" for exactly that reason.
    var parts = [
      "\(volume.workingSets) set\(volume.workingSets == 1 ? "" : "s")",
      "\(volume.reps) rep\(volume.reps == 1 ? "" : "s")",
    ]
    if volume.volumeKg > 0 {
      let displayed = unit.fromKilograms(volume.volumeKg)
      parts.append("\(Int(displayed.rounded())) \(unit.abbreviation)")
    }
    if volume.warmupSets > 0 { parts.append("\(volume.warmupSets) warm-up") }
    return parts.joined(separator: " · ")
  }

  static func spokenLabel(_ row: HistoryRow, unit: WeightUnit) -> String {
    var parts = [row.title.isEmpty ? dateText(row.date) : "\(row.title), \(dateText(row.date))"]
    parts.append(volumeText(row.volume, unit: unit))
    if row.hasImplausibleDuration {
      parts.append("length unknown, this session was left open")
    } else if let duration = row.duration {
      parts.append(duration.clockString)
    }
    // The movements are printed on every row and were absent from the spoken label, so the one
    // detail that tells two workouts apart was the one detail VoiceOver did not get.
    if !row.exerciseNames.isEmpty {
      parts.append(row.exerciseNames.joined(separator: ", "))
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
