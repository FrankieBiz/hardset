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
  /// Which movement this was. Carried so a heading can open that movement's load history: the chart
  /// was previously reachable only from inside a live workout, so seeing your bench progression
  /// meant starting a session first.
  public let exerciseID: ExerciseID?
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
  /// Working, warm-up or drop. History has to distinguish them or a chain reads back as three
  /// unexplained sets at falling loads, which looks like a bad session rather than a hard one.
  public let kind: SetKind

  public var isWarmup: Bool { kind == .warmup }

  public init(
    id: UUID,
    exerciseID: ExerciseID? = nil,
    exerciseName: String,
    isBodyweight: Bool = false,
    machineName: String?,
    weightKg: Double,
    reps: Int,
    rpe: Double? = nil,
    kind: SetKind
  ) {
    self.id = id
    self.exerciseID = exerciseID
    self.exerciseName = exerciseName
    self.isBodyweight = isBodyweight
    self.machineName = machineName
    self.weightKg = weightKg
    self.reps = reps
    self.rpe = rpe
    self.kind = kind
  }

  // Deliberately no `isWarmup:` convenience. This type is built by mapping stored rows, and a
  // Bool cannot carry a drop -- an `isWarmup: false` shortcut would quietly render every drop in
  // history as a working set, which is the one thing the counting convention promises it is not.
}

public struct SessionDetailView: View {
  public struct Group_: Identifiable, Hashable {
    public let exerciseName: String
    public let machineName: String?
    public let sets: [LoggedSetRow]
    /// The movement, for opening its load history from the heading.
    public var exerciseID: ExerciseID? { sets.first?.exerciseID }
    /// The first set's id, not the movement name.
    ///
    /// A movement can legitimately appear in two separate runs -- benching, doing something else,
    /// then coming back -- and a name-based id is then duplicated inside one `ForEach`. SwiftUI does
    /// not merge those; it renders the first group again for every later duplicate, so the page
    /// showed the same three movements over and over with most sets missing. Set ids are unique.
    ///
    /// Stored rather than computed off `sets.first`, so identity cannot depend on a collection that
    /// is allowed to be empty and cannot change as sets are appended to the group being built.
    public let id: UUID
  }

  private let title: String
  private let date: Date
  private let duration: Duration?
  private let hasImplausibleDuration: Bool
  private let sets: [LoggedSetRow]
  /// The workout's own note, empty when there is none.
  private let notes: String
  private let unit: WeightUnit
  /// Opens one movement's load history. `nil` leaves the headings inert.
  private let onShowProgress: ((ExerciseID) -> Void)?

  @Environment(\.dynamicTypeSize) private var typeSize
  /// Scales with the text beside it, rather than pinning the column at 22 pt while the digits grow.
  @ScaledMetric(relativeTo: .subheadline) private var ordinalWidth: CGFloat = 22

  public init(
    title: String,
    date: Date,
    duration: Duration?,
    hasImplausibleDuration: Bool,
    sets: [LoggedSetRow],
    notes: String = "",
    unit: WeightUnit,
    onShowProgress: ((ExerciseID) -> Void)? = nil
  ) {
    self.title = title
    self.date = date
    self.duration = duration
    self.hasImplausibleDuration = hasImplausibleDuration
    self.sets = sets
    self.notes = notes
    self.unit = unit
    self.onShowProgress = onShowProgress
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Tokens.Spacing.section) {
        header
        if !notes.isEmpty {
          // The lifter's own account of the session, shown above the sets because it is the context
          // the numbers are read in -- "felt awful, slept four hours" changes what 84 kg means.
          Label(notes, systemImage: "note.text")
            .font(Tokens.Text.label)
            .foregroundStyle(Tokens.Color.textSecondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(Tokens.Spacing.regular)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
              Tokens.Color.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.card)
            )
            .accessibilityLabel("Note on this workout: \(notes)")
        }
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

  /// Working sets, so a past workout's headline agrees with the week that contains it. Counting
  /// every non-warm-up row reported a drop chain as three sets where the volume report said one.
  private var workingSetCount: Int { sets.count { $0.kind.countsAsWorkingSet } }

  @ViewBuilder private func groupView(_ group: Group_) -> some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
        // The heading is the way into this movement's load history, mirroring the live session's
        // header. Reviewing a past workout is exactly when "how have I been doing on this" gets
        // asked, and the chart used to be unreachable without starting a workout.
        Button {
          if let id = group.exerciseID { onShowProgress?(id) }
        } label: {
          HStack(spacing: Tokens.Spacing.tight) {
            Text(group.exerciseName)
              .font(Tokens.Text.title)
              .foregroundStyle(Tokens.Color.textPrimary)
            if canShowProgress(group) {
              Image(systemName: "chart.xyaxis.line")
                .font(Tokens.Text.caption)
                .foregroundStyle(Tokens.Color.accent)
            }
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canShowProgress(group))
        .accessibilityLabel(
          canShowProgress(group)
            ? "\(group.exerciseName). Show load history." : group.exerciseName
        )
        if let machine = group.machineName {
          Label(machine, systemImage: "dumbbell")
            .font(Tokens.Text.caption)
            .foregroundStyle(Tokens.Color.textSecondary)
        }
      }

      ForEach(Array(group.sets.enumerated()), id: \.element.id) { index, set in
        Group {
          if typeSize.isAccessibilitySize {
            stackedSetRow(set, in: group, index: index)
          } else {
            compactSetRow(set, in: group, index: index)
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

  private func canShowProgress(_ group: Group_) -> Bool {
    onShowProgress != nil && group.exerciseID != nil
  }

  /// Up to five columns on one line, which fits at ordinary text sizes.
  @ViewBuilder private func compactSetRow(
    _ set: LoggedSetRow, in group: Group_, index: Int
  ) -> some View {
    HStack(spacing: Tokens.Spacing.regular) {
      ordinal(set, in: group, index: index)
        .frame(minWidth: ordinalWidth, alignment: .leading)
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
      if let tag = kindTag(set) { tag }
    }
  }

  /// The same values, stacked, so none of them truncates.
  ///
  /// Five columns of growing text on one line is the layout that produced "Las / t / tim / e" in the
  /// live set row at AX5. This screen had the same shape and never got the same treatment.
  @ViewBuilder private func stackedSetRow(
    _ set: LoggedSetRow, in group: Group_, index: Int
  ) -> some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
      HStack(spacing: Tokens.Spacing.snug) {
        ordinal(set, in: group, index: index)
        if let tag = kindTag(set) { tag }
      }
      Text("\(loadText(set)) \u{00D7} \(set.reps)")
        .font(Tokens.Text.setEntry)
        .foregroundStyle(Tokens.Color.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
      if let rpe = set.rpe {
        Text("RPE \(Self.format(rpe))")
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.textSecondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder private func ordinal(
    _ set: LoggedSetRow, in group: Group_, index: Int
  ) -> some View {
    Text(badge(for: set, in: group, index: index))
      .font(Tokens.Text.label)
      .monospacedDigit()
      .foregroundStyle(Tokens.Color.textSecondary)
  }

  /// The word beside a row that is not a plain working set, or nothing.
  ///
  /// Both kinds are marked and both are excluded from the count above, for the same reason: one
  /// is not training volume and the other is already counted inside the set it continues.
  private func kindTag(_ set: LoggedSetRow) -> Text? {
    let word: String
    switch set.kind {
    case .working: return nil
    case .warmup: word = "warm-up"
    case .drop: word = "drop"
    }
    return Text(word)
      .font(Tokens.Text.caption)
      .foregroundStyle(Tokens.Color.textSecondary)
  }

  /// A drop carries an arrow instead of a number, matching the live logger, because it does not
  /// have a number of its own.
  private func badge(for set: LoggedSetRow, in group: Group_, index: Int) -> String {
    switch set.kind {
    case .warmup: "W"
    case .drop: "\u{2193}"
    case .working: "\(workingOrdinal(of: set, in: group) ?? index + 1)"
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
    guard set.kind.countsAsWorkingSet else { return nil }
    let working = group.sets.filter { $0.kind.countsAsWorkingSet }
    guard let index = working.firstIndex(where: { $0.id == set.id }) else { return nil }
    return index + 1
  }

  private func spokenLabel(
    for set: LoggedSetRow, in group: Group_, fallbackIndex: Int
  ) -> String {
    let which =
      switch set.kind {
      case .warmup: "Warm-up set"
      case .drop: "Drop set"
      case .working: "Set \(workingOrdinal(of: set, in: group) ?? fallbackIndex + 1)"
      }
    let effort = set.rpe.map { ", RPE \(Self.format($0))" } ?? ""
    return "\(which), \(loadText(set)), \(set.reps) reps\(effort)"
  }

  /// Grouped in logging order, and a machine change inside one movement starts a new group --
  /// because it is a different piece of equipment and merging them is the thing this app refuses
  /// to do everywhere else.
  private var groups: [Group_] { Self.groups(from: sets) }

  /// Exposed as a pure function so the run-length rule can be tested without a view.
  ///
  /// It was only ever a private computed property, and the one test that covered this screen used a
  /// single movement -- where every grouping rule looks identical. Three movements of three sets is
  /// what exposed both the interleaved input order and the duplicate group ids.
  public static func groups(from sets: [LoggedSetRow]) -> [Group_] {
    var result: [Group_] = []
    for set in sets {
      if let last = result.last,
        last.exerciseName == set.exerciseName,
        last.machineName == set.machineName
      {
        result[result.count - 1] = Group_(
          exerciseName: last.exerciseName,
          machineName: last.machineName,
          sets: last.sets + [set],
          id: last.id
        )
      } else {
        result.append(
          Group_(
            exerciseName: set.exerciseName,
            machineName: set.machineName,
            sets: [set],
            id: set.id
          )
        )
      }
    }
    return result
  }

  private static func format(_ value: Double) -> String {
    value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
  }
}
