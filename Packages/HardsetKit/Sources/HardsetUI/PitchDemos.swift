import HardsetCore
import SwiftUI

// MARK: - Page anatomy

/// The anatomy every pitch page shares so the three read as one set: a headline, a line or two of
/// plain copy, and one live element that is the real component with real behaviour, never a picture.
public struct PitchPage<Element: View>: View {
  private let title: String
  private let copy: String
  private let element: Element

  public init(title: String, copy: String, @ViewBuilder element: () -> Element) {
    self.title = title
    self.copy = copy
    self.element = element()
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Tokens.Spacing.section) {
        VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
          Text(title)
            .hardsetText(.title)
            .foregroundStyle(Tokens.Color.chalk)
            .accessibilityAddTraits(.isHeader)
          Text(copy)
            .hardsetText(.label)
            .foregroundStyle(Tokens.Color.chalkDim)
            .fixedSize(horizontal: false, vertical: true)
        }
        element
      }
      .padding(Tokens.Spacing.loose)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .scrollBounceBehavior(.basedOnSize)
  }
}

// MARK: - Pitch 1: one tap per set

/// "One tap per set." A real set row for "Chest press", filled in from last time's 60 kg for 10.
/// Tapping its check logs the set: the stamp, a `clank` then the success haptic the row plays, the
/// row settling onto the logged tint, and the next row appearing with its own prefill.
public struct PitchSetRowPage: View {
  private let unit: WeightUnit
  private let isFirstLogged: Bool

  /// - Parameter isFirstLogged: Starts with the first set already logged, for a capture.
  public init(unit: WeightUnit, isFirstLogged: Bool = false) {
    self.unit = unit
    self.isFirstLogged = isFirstLogged
  }

  public var body: some View {
    PitchPage(
      title: "One tap per set.",
      copy:
        "Weight and reps are already filled in from last time. If the set went as planned, one tap logs it."
    ) {
      PitchSetRowDemo(unit: unit, isFirstLogged: isFirstLogged)
    }
  }
}

/// The live element of pitch 1. Starts with the first row next up; logging it adds the second.
public struct PitchSetRowDemo: View {
  private let unit: WeightUnit
  @State private var first: SetEntryDraft
  @State private var second: SetEntryDraft
  @State private var firstLogged: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private static let lastTime = PriorSetRecord(
    weightKg: 60, reps: 10, completedAt: Date().addingTimeInterval(-7 * 86_400))

  /// - Parameter isFirstLogged: Starts with the first set already logged, for a capture.
  public init(unit: WeightUnit, isFirstLogged: Bool = false) {
    self.unit = unit
    _first = State(initialValue: SetEntryDraft(suggestion: Self.lastTime))
    _second = State(initialValue: SetEntryDraft(suggestion: Self.lastTime))
    _firstLogged = State(initialValue: isFirstLogged)
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
      Text("Chest press")
        .hardsetText(.headline)
        .foregroundStyle(Tokens.Color.chalk)
      SetRowView(
        draft: $first, ordinal: 0, isLogged: firstLogged, isNext: !firstLogged, unit: unit,
        previous: Self.lastTime,
        onLog: {
          ClankPlayer.shared.play()
          withAnimation(Tokens.Motion.adaptive(Tokens.Motion.reveal, reduceMotion: reduceMotion)) {
            firstLogged = true
          }
        })
      if firstLogged {
        SetRowView(
          draft: $second, ordinal: 1, isNext: true, unit: unit, previous: Self.lastTime,
          onLog: { ClankPlayer.shared.play() }
        )
        .transition(.opacity)
      }
    }
  }
}

// MARK: - Pitch 2: honest numbers

/// "Honest numbers." An estimated one-rep max from the same 60 kg set at four rep counts. The
/// figure, the badge and the provenance line all come from the engine's own rule, so the four
/// segments walk high, moderate, low and not evaluated because `StrengthMath` says so, not because
/// the page does.
public struct PitchEstimatePage: View {
  private let unit: WeightUnit
  private let initialReps: Int

  /// - Parameter initialReps: The segment selected first; a capture passes each in turn.
  public init(unit: WeightUnit, initialReps: Int = 3) {
    self.unit = unit
    self.initialReps = initialReps
  }

  public var body: some View {
    PitchPage(
      title: "Honest numbers.",
      copy:
        "Every estimate says how sure it is. When Hardset can't tell, it says so instead of guessing."
    ) {
      PitchEstimateDemo(unit: unit, initialReps: initialReps)
    }
  }
}

public struct PitchEstimateDemo: View {
  /// The reps shown, chosen so the engine's rule reaches every level: high at three, moderate at
  /// eight, low at twelve (low is only eleven and twelve), and not evaluated at fifteen.
  public static let repOptions = [3, 8, 12, 15]
  /// The weight of the set every segment shows.
  public static let weightKg = 60.0

  private let unit: WeightUnit
  @State private var reps: Int

  public init(unit: WeightUnit, initialReps: Int = 3) {
    self.unit = unit
    _reps = State(initialValue: initialReps)
  }

  private var claim: Claim<Double> {
    StrengthMath.estimatedOneRepMax(weightKg: Self.weightKg, reps: reps)
  }

  public var body: some View {
    let claim = claim
    VStack(alignment: .leading, spacing: Tokens.Spacing.loose) {
      Text("\(LoadText.entered(Self.weightKg, in: unit)) \(unit.abbreviation) for \(reps) reps")
        .hardsetText(.provenance)
        .foregroundStyle(Tokens.Color.chalkDim)
      if let value = claim.value {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.tight) {
          Text(LoadText.estimate(value, in: unit))
            .hardsetText(.readout)
            .foregroundStyle(Tokens.Color.chalk)
            .contentTransition(.numericText())
          Text("\(unit.abbreviation), estimated one-rep max")
            .hardsetText(.unit)
            .foregroundStyle(Tokens.Color.chalkDim)
        }
      } else {
        UnevaluatedReadout(explanation: claim.source.validRange ?? claim.source.title)
      }
      CertaintyBadge(
        level: CertaintyLevel(claim.certainty), methodology: claim.source.methodology,
        citation: claim.source.citation)
      HardsetSegmentedControl(
        selection: $reps,
        segments: Self.repOptions.map { HardsetSegment("\($0) reps", value: $0) })
      Text("\(claim.source.title). \(claim.source.validRange ?? "")")
        .hardsetText(.caption)
        .foregroundStyle(Tokens.Color.chalkDim)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

// MARK: - Pitch 3: rest that keeps time

/// "Rest that keeps time." The real rest bar counting down from 90 seconds, with the four controls
/// live and each giving the selection haptic, over an in-memory timer that never touches the
/// lifter's own rest.
public struct PitchRestPage: View {
  private let timer: DemoRestTimer

  /// - Parameter timer: Defaults to a fresh 90 second rest; a capture passes a paused one.
  public init(timer: DemoRestTimer = DemoRestTimer()) {
    self.timer = timer
  }

  public var body: some View {
    PitchPage(
      title: "Rest that keeps time.",
      copy: "Rest runs as an alarm, so it finishes on time even if the phone is in your pocket."
    ) {
      PitchRestDemo(timer: timer)
    }
  }
}

public struct PitchRestDemo: View {
  @State private var timer: DemoRestTimer

  /// - Parameter timer: Defaults to a fresh 90 second rest; a capture passes a paused one.
  public init(timer: DemoRestTimer = DemoRestTimer()) {
    _timer = State(initialValue: timer)
  }

  public var body: some View {
    RestBarView(
      state: timer.state,
      onAdjust: { timer.adjust(by: $0) },
      onPauseResume: { timer.pauseOrResume() },
      onSkip: { timer.skip() }
    )
    .sensoryFeedback(Tokens.Haptic.selection, trigger: timer.commands)
    .task {
      // A slow tick so a rest that runs out starts again: the demo is never left on an empty bar.
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1))
        timer.restartIfElapsed()
      }
    }
  }
}
