import HardsetCore
import SwiftUI

/// What the workout amounted to, shown once, when it ends.
///
/// This screen did not exist until now, and its absence was hiding a shipped feature:
/// `PersonalRecordDetector` has been detecting records -- with a margin rule careful enough to
/// refuse the ancestor's habit of announcing a PR for repeating last week -- and no view had ever
/// read them. A record nobody is told about is not a feature.
///
/// Two rules from `docs/UI-GUIDELINES.md` shape the layout rather than decorate it:
///
/// - **One hero number.** Working sets, because fractional hard sets is the unit the rest of the
///   app actually believes in. Tonnage is *shown* but not elevated: it is a weak proxy for
///   hypertrophy and putting it in the largest type on the screen would be a claim the app does
///   not want to make.
/// - **A number and its certainty share one transition.** The coverage badge is a sibling of the
///   hero number inside the same container, so the two cannot appear separately -- not even for
///   300 ms, and not by the good luck of matching animation timings.
public struct SessionSummaryView: View {
  private let outcome: SessionOutcome
  private let muscles: MuscleVolumeReport?
  private let unit: WeightUnit
  private let onDone: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var shownSets = 0
  @State private var revealed = false

  /// - Parameter muscles: Where the work went, or `nil` when it could not be computed. Rendered as
  ///   an absence in that case rather than as an empty chart, which reads as "no work".
  public init(
    outcome: SessionOutcome,
    muscles: MuscleVolumeReport?,
    unit: WeightUnit,
    onDone: @escaping () -> Void
  ) {
    self.outcome = outcome
    self.muscles = muscles
    self.unit = unit
    self.onDone = onDone
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Tokens.Spacing.section) {
        headline
        if outcome.isEmpty {
          emptyState
        } else {
          readouts
          if !outcome.records.isEmpty { recordsSection }
          payout
        }
      }
      .padding(.horizontal, Tokens.Spacing.edge)
      .padding(.vertical, Tokens.Spacing.hero)
    }
    .background(Tokens.Color.ground)
    .safeAreaInset(edge: .bottom) { doneButton }
    .task {
      // Count-up on a value the app computed, which is what `.numericText` is for. Never on a
      // value the user typed.
      withAnimation(reduceMotion ? nil : Tokens.Motion.reveal) {
        shownSets = outcome.volume.workingSets
      }
      withAnimation(reduceMotion ? nil : Tokens.Motion.surface) { revealed = true }
    }
  }

  // MARK: - Hero

  /// The hero number and its certainty, in one container on purpose.
  ///
  /// Sequencing the caveat after the number would be a way of burying it, and letting the number
  /// land alone would put an unqualified figure on screen. Being siblings makes both impossible.
  private var headline: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      Text("Workout complete")
        .font(Tokens.Text.label)
        .foregroundStyle(Tokens.Color.textSecondary)

      HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.snug) {
        Text("\(shownSets)")
          .font(Tokens.Text.hero)
          .tracking(Tokens.Tracking.hero)
          .contentTransition(.numericText(value: Double(shownSets)))
          .foregroundStyle(Tokens.Color.textPrimary)
        Text(outcome.volume.workingSets == 1 ? "working set" : "working sets")
          .font(Tokens.Text.label)
          .foregroundStyle(Tokens.Color.textSecondary)
      }

      if let coverageBadge {
        CertaintyBadge(level: coverageBadge.level, methodology: coverageBadge.detail)
      }
    }
  }

  /// How much of this session the app could actually attribute, as a certainty rather than a
  /// percentage dressed up as precision.
  private var coverageBadge: (level: CertaintyLevel, detail: String)? {
    guard let muscles, !outcome.isEmpty else { return nil }
    if muscles.unattributedHardSets == 0 {
      return (.high, "Every set attributed to a muscle.")
    }
    let n = muscles.unattributedHardSets
    return (
      .low,
      "^[\(n) set](inflect: true) had no muscles recorded, so the breakdown below is a floor."
    )
  }

  // MARK: - Readouts

  /// Deliberately secondary. Duration is a fact; tonnage is a number lifters like that means less
  /// than it looks like it means. Neither gets hero treatment.
  private var readouts: some View {
    HStack(alignment: .top, spacing: Tokens.Spacing.section) {
      readout(durationText, label: "Length")
      readout("\(outcome.volume.reps)", label: "Reps")
      readout(tonnageText, label: "Volume")
    }
  }

  private func readout(_ value: String, label: String) -> some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
      Text(value)
        .font(Tokens.Text.readout)
        .tracking(Tokens.Tracking.readout)
        .foregroundStyle(Tokens.Color.textPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
      Text(label)
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.textSecondary)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(label), \(value)")
  }

  /// "Unknown" rather than a number, when the span is not one we believe. The ancestor shipped
  /// 9,749-minute workouts to its history as achievements.
  private var durationText: String {
    guard let duration = outcome.duration else { return "Unknown" }
    return duration.clockString
  }

  private var tonnageText: String {
    let value = unit.fromKilograms(outcome.volume.volumeKg)
    return "\(Self.format(value)) \(unit.abbreviation)"
  }

  // MARK: - Records

  /// The first time a record has ever been shown to anyone using this app.
  ///
  /// No confetti and no sound. A record is stated, in the brightest ink on the screen, and it says
  /// what it beat -- which is the part that makes it a record rather than a compliment.
  private var recordsSection: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      Text(outcome.records.count == 1 ? "Personal record" : "Personal records")
        .font(Tokens.Text.title)
        .foregroundStyle(Tokens.Color.textPrimary)

      ForEach(Array(outcome.records.enumerated()), id: \.offset) { index, record in
        VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
          Text(record.kind.label)
            .font(Tokens.Text.label.weight(.semibold))
            .foregroundStyle(Tokens.Color.textPrimary)
          Text(recordDetail(record))
            .font(Tokens.Text.caption)
            .foregroundStyle(Tokens.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Tokens.Spacing.regular)
        .background(
          Tokens.Color.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.card)
        )
        .overlay {
          RoundedRectangle(cornerRadius: Tokens.Radius.card)
            .strokeBorder(Tokens.Color.hairline, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
      }
    }
  }

  private func recordDetail(_ record: PersonalRecord) -> String {
    Self.recordDetail(record, unit: unit)
  }

  /// The sentence a record is stated in.
  ///
  /// Split out as a static function taking its inputs so it can be tested: the estimated-1RM case
  /// shipped a string that read as a regression, and a screenshot walkthrough is not a regression
  /// test.
  static func recordDetail(_ record: PersonalRecord, unit: WeightUnit) -> String {
    let weight = format(unit.fromKilograms(record.weightKg))
    let now = "\(weight) \(unit.abbreviation) × \(record.reps)"
    switch record.kind {
    case .repsAtLoad:
      guard let previousReps = record.previousReps else { return now }
      return "\(now), up from \(previousReps) reps at the same load"
    case .heaviestLoad:
      guard let previous = record.previousWeightKg else { return now }
      let was = format(unit.fromKilograms(previous))
      return "\(now), beating \(was) \(unit.abbreviation)"

    case .estimatedOneRepMax:
      // Both sides have to be estimates. `weightKg` is the *set*, `previousWeightKg` is the
      // previous *estimate*, so putting them side by side read as "70 kg, beating 80 kg" -- which
      // looks like a regression and is comparing two different quantities. The estimate is
      // recomputed here from the same function that detected the record.
      let estimate = StrengthMath.estimatedOneRepMax(
        weightKg: record.weightKg, reps: record.reps
      )
      guard let newValue = estimate.value else { return now }
      let newText = format(unit.fromKilograms(newValue))
      guard let previous = record.previousWeightKg else {
        return "about \(newText) \(unit.abbreviation), estimated from \(now)"
      }
      let was = format(unit.fromKilograms(previous))
      // "about" on both sides, because both are estimates and neither is a lift that happened.
      return "about \(newText) \(unit.abbreviation) from \(now), beating about \(was) \(unit.abbreviation)"
    }
  }

  // MARK: - Payout

  /// Where the work went, in the proportions the engine actually assigned.
  ///
  /// This is the app's most distinctive machinery and it has only ever surfaced as a bar chart on
  /// another tab. Fractional credit is the point: a chest press paying chest 1.0 and triceps 0.5 is
  /// a claim no other logger makes, so the halves are shown as halves.
  ///
  /// Bars grow by animating their **value**, never a `scaleEffect` -- a scaled bar carries a
  /// distorted stroke and a stretched label. The stagger is capped rather than escapable: at 40 ms
  /// a row it would run past the budget on a long session, so total delay is bounded and no
  /// skip-the-animation affordance is needed.
  @ViewBuilder private var payout: some View {
    if let muscles, !shares.isEmpty {
      VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
        Text("Where the work went")
          .font(Tokens.Text.title)
          .foregroundStyle(Tokens.Color.textPrimary)
        Text(
          muscles.isLowerBound
            ? "Fractional sets per muscle. At least this much -- some sets could not be attributed."
            : "Fractional sets per muscle. Indirect work counts as half a set."
        )
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.textSecondary)

        ForEach(Array(shares.enumerated()), id: \.element.muscle) { index, share in
          shareRow(share, index: index, isLowerBound: muscles.isLowerBound)
        }
      }
    }
  }

  private struct Share: Hashable {
    let muscle: Muscle
    let sets: Double
  }

  /// Descending, so the biggest contribution reads first and the halves are visibly halves.
  private var shares: [Share] {
    guard let muscles else { return [] }
    return Muscle.allCases
      .map { Share(muscle: $0, sets: muscles.sets(for: $0)) }
      .filter { $0.sets > 0 }
      .sorted { $0.sets > $1.sets }
  }

  private var maxShare: Double { max(shares.first?.sets ?? 1, 1) }

  private func shareRow(_ share: Share, index: Int, isLowerBound: Bool) -> some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
      HStack(alignment: .firstTextBaseline) {
        Text(ExercisePickerView.displayName(MuscleKey(share.muscle)))
          .font(Tokens.Text.label)
          .foregroundStyle(Tokens.Color.textPrimary)
        Spacer(minLength: Tokens.Spacing.snug)
        // The ">=" is load-bearing, not decorative.
        Text("\(isLowerBound ? "\u{2265} " : "")\(Self.format(share.sets))")
          .font(Tokens.Text.label)
          .monospacedDigit()
          .foregroundStyle(Tokens.Color.textSecondary)
      }
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          RoundedRectangle(cornerRadius: 4)
            .fill(Tokens.Color.surface)
          RoundedRectangle(cornerRadius: 4)
            .fill(Tokens.Color.textPrimary)
            .frame(width: barWidth(in: proxy.size.width, sets: share.sets))
        }
      }
      .frame(height: 10)
      .animation(revealAnimation(index: index), value: revealed)
    }
    .padding(.vertical, Tokens.Spacing.tight)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      "\(ExercisePickerView.displayName(MuscleKey(share.muscle))), "
        + "\(isLowerBound ? "at least " : "")\(Self.format(share.sets)) sets"
    )
  }

  private func barWidth(in total: CGFloat, sets: Double) -> CGFloat {
    let full = max(2, total * sets / maxShare)
    return revealed || reduceMotion ? full : 0
  }

  private func revealAnimation(index: Int) -> Animation? {
    guard !reduceMotion else { return nil }
    // Capped, not escapable: a long session would otherwise stagger past the motion budget.
    return Tokens.Motion.surface.delay(min(Double(index) * 0.04, 0.28))
  }

  // MARK: - Chrome

  private var emptyState: some View {
    Text("No sets were logged, so there is nothing to summarise.")
      .font(Tokens.Text.label)
      .foregroundStyle(Tokens.Color.textSecondary)
  }

  private var doneButton: some View {
    Button(action: onDone) {
      Text("Done")
        .font(Tokens.Text.label.weight(.semibold))
        .frame(maxWidth: .infinity, minHeight: Tokens.loggerTapTarget)
        .foregroundStyle(Tokens.Color.ground)
        .background(
          Tokens.Color.accent, in: RoundedRectangle(cornerRadius: Tokens.Radius.control)
        )
    }
    .buttonStyle(CommitButtonStyle())
    .padding(.horizontal, Tokens.Spacing.edge)
    .padding(.bottom, Tokens.Spacing.regular)
    .background(.clear)
  }

  static func format(_ value: Double) -> String {
    value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
  }
}

#if DEBUG
  #Preview("Summary") {
    SessionSummaryView(
      outcome: SessionOutcome(
        volume: SessionVolume(workingSets: 14, warmupSets: 3, volumeKg: 8_420, reps: 132),
        duration: .seconds(63 * 60),
        records: [
          PersonalRecord(
            kind: .heaviestLoad, weightKg: 105, reps: 5, previousWeightKg: 100
          )
        ],
        exerciseCount: 4
      ),
      muscles: nil,
      unit: .kilograms,
      onDone: {}
    )
  }
#endif
