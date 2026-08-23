import HardsetCore
import SwiftUI

/// What one past workout actually consisted of.
///
/// History listed workouts and stopped there: `HistoryView` has always taken an `onSelect` and
/// nothing ever passed one, so every row was a disabled button. A logger that can tell you a
/// session happened but not what was in it is answering the less useful half of the question.
///
/// Grouped by movement in the order the sets were logged, because that is the order the workout
/// happened in. Machine names are shown per group: 80 kg on one leg press is not 80 kg on another,
/// and this is the screen where that distinction is read back.
/// One logged set, as this screen needs it.
///
/// Declared here rather than reusing the store's row type, because `HardsetUI` depends on
/// `HardsetCore` only and never on `HardsetStore` -- the same reason `HistoryRow` exists. The
/// feature layer maps across the boundary.
public struct LoggedSetRow: Identifiable, Hashable, Sendable {
  public let id: UUID
  public let exerciseName: String
  /// True when the movement is loaded by the lifter's own body, so zero means bodyweight and not
  /// nothing -- the same distinction the set row draws while logging.
  public let isBodyweight: Bool
  /// `nil` for free weights, or a machine whose row has been removed.
  public let machineName: String?
  public let weightKg: Double
  public let reps: Int
  /// Effort as recorded, or `nil`. Shown only when it exists -- an absent RPE is not a zero.
  public let rpe: Double?
  public let isWarmup: Bool

  public init(
    id: UUID,
    exerciseName: String,
    isBodyweight: Bool = false,
    machineName: String?,
    weightKg: Double,
    reps: Int,
    rpe: Double? = nil,
    isWarmup: Bool
  ) {
    self.id = id
    self.exerciseName = exerciseName
    self.isBodyweight = isBodyweight
    self.machineName = machineName
    self.weightKg = weightKg
    self.reps = reps
    self.rpe = rpe
    self.isWarmup = isWarmup
  }
}

public struct SessionDetailView: View {
  public struct Group_: Identifiable, Hashable {
    public let exerciseName: String
    public let machineName: String?
    public let sets: [LoggedSetRow]
    public var id: String { "\(exerciseName)|\(machineName ?? "")" }
  }

  private let title: String
  private let date: Date
  private let duration: Duration?
  private let hasImplausibleDuration: Bool
  private let sets: [LoggedSetRow]
  private let unit: WeightUnit

  public init(
    title: String,
    date: Date,
    duration: Duration?,
    hasImplausibleDuration: Bool,
    sets: [LoggedSetRow],
    unit: WeightUnit
  ) {
    self.title = title
    self.date = date
    self.duration = duration
    self.hasImplausibleDuration = hasImplausibleDuration
    self.sets = sets
    self.unit = unit
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Tokens.Spacing.section) {
        header
        if groups.isEmpty {
          Text("No sets were recorded in this workout.")
            .font(Tokens.Text.label)
            .foregroundStyle(Tokens.Color.textSecondary)
        } else {
          ForEach(groups) { group in
            groupView(group)
          }
        }
      }
      .padding(.horizontal, Tokens.Spacing.edge)
      .padding(.vertical, Tokens.Spacing.loose)
    }
    .background(Tokens.Color.ground)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
      Text(date.formatted(date: .complete, time: .shortened))
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.textSecondary)
      HStack(spacing: Tokens.Spacing.regular) {
        Text("^[\(workingSetCount) working set](inflect: true)")
          .font(Tokens.Text.readout)
          .foregroundStyle(Tokens.Color.textPrimary)
        Text(lengthText)
          .font(Tokens.Text.label)
          .foregroundStyle(Tokens.Color.textSecondary)
      }
    }
    .accessibilityElement(children: .combine)
  }

  /// Withheld rather than displayed when the span is not one we believe -- the same rule the
  /// history list and the summary follow, because a 44-hour workout is a forgotten session.
  private var lengthText: String {
    guard !hasImplausibleDuration, let duration else { return "Length unknown" }
    return duration.clockString
  }

  private var workingSetCount: Int { sets.count { !$0.isWarmup } }

  @ViewBuilder private func groupView(_ group: Group_) -> some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
        Text(group.exerciseName)
          .font(Tokens.Text.title)
          .foregroundStyle(Tokens.Color.textPrimary)
        if let machine = group.machineName {
          Label(machine, systemImage: "dumbbell")
            .font(Tokens.Text.caption)
            .foregroundStyle(Tokens.Color.textSecondary)
        }
      }

      ForEach(Array(group.sets.enumerated()), id: \.element.id) { index, set in
        HStack(spacing: Tokens.Spacing.regular) {
          Text(set.isWarmup ? "W" : "\(workingOrdinal(of: set, in: group) ?? index + 1)")
            .font(Tokens.Text.label)
            .monospacedDigit()
            .foregroundStyle(Tokens.Color.textSecondary)
            .frame(minWidth: 22, alignment: .leading)
          Text(loadText(set))
            .font(Tokens.Text.setEntry)
            .foregroundStyle(Tokens.Color.textPrimary)
          Text("\u{00D7} \(set.reps)")
            .font(Tokens.Text.setEntry)
            .foregroundStyle(Tokens.Color.textPrimary)
          if let rpe = set.rpe {
            Text("RPE \(Self.format(rpe))")
              .font(Tokens.Text.caption)
              .foregroundStyle(Tokens.Color.textSecondary)
          }
          Spacer(minLength: 0)
          if set.isWarmup {
            // Marked, and excluded from the count above, because a warm-up is not training volume.
            Text("warm-up")
              .font(Tokens.Text.caption)
              .foregroundStyle(Tokens.Color.textSecondary)
          }
        }
        .padding(.horizontal, Tokens.Spacing.regular)
        .padding(.vertical, Tokens.Spacing.snug)
        .background(
          Tokens.Color.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.control)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spokenLabel(for: set, in: group, fallbackIndex: index))
      }
    }
  }

  /// "Body" for a bodyweight set with no added load, "Body + 10 kg" when there was some, and the
  /// plain load otherwise. Reading a pull-up back as "0 kg" is the same lie the set row refuses
  /// while logging it.
  private func loadText(_ set: LoggedSetRow) -> String {
    let value = Self.format(unit.fromKilograms(set.weightKg))
    guard set.isBodyweight else { return "\(value) \(unit.abbreviation)" }
    return set.weightKg == 0 ? "Body" : "Body + \(value) \(unit.abbreviation)"
  }

  private func workingOrdinal(of set: LoggedSetRow, in group: Group_) -> Int? {
    guard !set.isWarmup else { return nil }
    let working = group.sets.filter { !$0.isWarmup }
    guard let index = working.firstIndex(where: { $0.id == set.id }) else { return nil }
    return index + 1
  }

  private func spokenLabel(
    for set: LoggedSetRow, in group: Group_, fallbackIndex: Int
  ) -> String {
    let which = set.isWarmup
      ? "Warm-up set"
      : "Set \(workingOrdinal(of: set, in: group) ?? fallbackIndex + 1)"
    let effort = set.rpe.map { ", RPE \(Self.format($0))" } ?? ""
    return "\(which), \(loadText(set)), \(set.reps) reps\(effort)"
  }

  /// Grouped in logging order, and a machine change inside one movement starts a new group --
  /// because it is a different piece of equipment and merging them is the thing this app refuses
  /// to do everywhere else.
  private var groups: [Group_] {
    var result: [Group_] = []
    for set in sets {
      if let last = result.last,
        last.exerciseName == set.exerciseName,
        last.machineName == set.machineName
      {
        result[result.count - 1] = Group_(
          exerciseName: last.exerciseName,
          machineName: last.machineName,
          sets: last.sets + [set]
        )
      } else {
        result.append(
          Group_(exerciseName: set.exerciseName, machineName: set.machineName, sets: [set])
        )
      }
    }
    return result
  }

  private static func format(_ value: Double) -> String {
    value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
  }
}
