import HardsetCore
import SwiftUI

/// The rest countdown, and the controls for it.
///
/// The countdown is rendered by `Text(timerInterval:)`, which the system animates from an
/// absolute deadline. That is not a stylistic choice — it is the reason this view has no timer,
/// no `TimelineView`, and no `@State` that ticks. A 1 Hz publisher redrawing the screen is what
/// made the ancestor app re-run its database queries thirty times a second, and a
/// remaining-seconds counter is what makes a timer wrong after backgrounding.
///
/// The paused case cannot use `Text(timerInterval:)` at all: AlarmKit's paused presentation
/// carries only durations and no dates, so there is no deadline to hand SwiftUI. It renders as
/// static text from the frozen remainder instead, which is why `RestTimerState` models paused
/// as a `Duration` rather than as a stopped clock.
///
/// Laid out as one line when the countdown, its caption and four 56 pt controls fit, and as two
/// lines — countdown above, controls below at equal widths — when they do not. Four 56 pt
/// controls with 8 pt gaps reserve 248 pt on their own, so on most phones the second form is the
/// one in use, and the countdown keeps its full size instead of being squeezed into what is left.
///
/// With a chooser (`onChooseNextRest`), the bar also offers the length of the rest after the next
/// set: a quiet "Next rest" row under the controls opens a row of choices, and a drag up on the bar
/// opens it as well and a drag down closes it, so the length can be changed without reaching for a
/// menu on the card. Choosing changes the next set's rest, not the one running.
public struct RestBarView: View {
  private let state: RestTimerState
  private let metadata: RestMetadata?
  private let referenceDate: Date
  private let nextRest: Duration?
  private let restChoices: [Duration]
  private let onChooseNextRest: ((Duration) -> Void)?
  private let onAdjust: (Duration) -> Void
  private let onPauseResume: () -> Void
  private let onSkip: () -> Void

  @State private var isChoosing = false
  @State private var chosenCount = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  /// - Parameters:
  ///   - nextRest: The length the next rest will have, marked among the choices.
  ///   - restChoices: The lengths offered. Empty, or without `onChooseNextRest`, the bar has no
  ///     chooser.
  ///   - onChooseNextRest: Called with the length the lifter picks.
  ///   - isChoosingInitially: Opens the choices as the bar appears, for a capture or a preview.
  public init(
    state: RestTimerState,
    metadata: RestMetadata? = nil,
    referenceDate: Date = Date(),
    nextRest: Duration? = nil,
    restChoices: [Duration] = [],
    onChooseNextRest: ((Duration) -> Void)? = nil,
    isChoosingInitially: Bool = false,
    onAdjust: @escaping (Duration) -> Void,
    onPauseResume: @escaping () -> Void,
    onSkip: @escaping () -> Void
  ) {
    self.state = state
    self.metadata = metadata
    self.referenceDate = referenceDate
    self.nextRest = nextRest
    self.restChoices = restChoices
    self.onChooseNextRest = onChooseNextRest
    _isChoosing = State(initialValue: isChoosingInitially)
    self.onAdjust = onAdjust
    self.onPauseResume = onPauseResume
    self.onSkip = onSkip
  }

  private var hasChooser: Bool { onChooseNextRest != nil && !restChoices.isEmpty }

  public var body: some View {
    if case .idle = state {
      EmptyView()
    } else {
      VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
        ViewThatFits(in: .horizontal) {
          HStack(spacing: Tokens.Spacing.regular) {
            status
            Spacer(minLength: Tokens.Spacing.snug)
            controls
              .fixedSize()
          }
          VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
            status
            controls
          }
        }
        if hasChooser {
          chooser
        }
      }
      .padding(Tokens.Spacing.regular)
      .background(Tokens.Color.steelRaised, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
      .overlay(
        RoundedRectangle(cornerRadius: Tokens.Radius.card)
          .strokeBorder(Tokens.Color.hairline, lineWidth: Tokens.Stroke.hairline)
      )
      .padding(.horizontal, Tokens.Spacing.regular)
      .padding(.bottom, Tokens.Spacing.snug)
      // The countdown is one element and each control is its own, so a VoiceOver user can hear
      // the time and still reach "Plus 15 seconds" directly. Combining the whole bar made the
      // controls unreachable.
      .accessibilityElement(children: .contain)
      .gesture(chooserDrag)
      .sensoryFeedback(Tokens.Haptic.selection, trigger: chosenCount)
    }
  }

  // MARK: - Next rest

  /// The chooser's two parts: a row that says what the next rest is and opens the choices, and the
  /// choices themselves. They arrive with an insertion-only opacity reveal and no animated layout,
  /// so the bar does not slide the set rows above it.
  @ViewBuilder private var chooser: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      Button {
        isChoosing.toggle()
      } label: {
        HStack(spacing: Tokens.Spacing.snug) {
          Text(nextRest.map { "Next rest \($0.clockString)" } ?? "Next rest")
            .hardsetText(.caption)
          Image(systemName: isChoosing ? "chevron.down" : "chevron.up")
            .font(Tokens.Text.caption.weight(.semibold))
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: Tokens.minimumTapTarget, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(HardsetPressStyle())
      .foregroundStyle(Tokens.Color.plateBlue)
      .accessibilityLabel(
        nextRest.map { "Next rest, \(ExerciseSectionView.spoken($0))" } ?? "Choose the next rest")
      .accessibilityHint(isChoosing ? "Hides the lengths" : "Shows the lengths to choose from")

      if isChoosing {
        // At accessibility sizes four labels cannot share one line without truncating, so the
        // choices take a two-column grid and each keeps its whole word.
        Group {
          if dynamicTypeSize.isAccessibilitySize {
            LazyVGrid(
              columns: [
                GridItem(.flexible(), spacing: Tokens.Spacing.snug),
                GridItem(.flexible(), spacing: Tokens.Spacing.snug),
              ],
              spacing: Tokens.Spacing.snug
            ) {
              chooserChips
            }
          } else {
            HStack(spacing: Tokens.Spacing.snug) {
              chooserChips
              Spacer(minLength: 0)
            }
          }
        }
        .hardsetArrival()
      }
    }
  }

  @ViewBuilder private var chooserChips: some View {
    ForEach(restChoices, id: \.self) { duration in
      HardsetChip(duration.clockString, isSelected: duration == nextRest) {
        chosenCount += 1
        onChooseNextRest?(duration)
        isChoosing = false
      }
      .accessibilityLabel(ExerciseSectionView.spoken(duration))
    }
  }

  /// A drag up on the bar opens the choices and a drag down closes them. The row above is the same
  /// control for anyone who does not drag.
  private var chooserDrag: some Gesture {
    DragGesture(minimumDistance: 16).onEnded { value in
      guard hasChooser else { return }
      if value.translation.height < -24 {
        isChoosing = true
      } else if value.translation.height > 24 {
        isChoosing = false
      }
    }
  }

  /// The countdown and what it is resting after.
  private var status: some View {
    HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.regular) {
      countdown
      VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
        Text(state.isRunning ? "Resting" : "Paused")
          .font(Tokens.Text.sectionHeader)
          .foregroundStyle(state.isRunning ? Tokens.Color.plateBlue : Tokens.Color.chalkDim)
        if let metadata {
          Text("\(metadata.exerciseName), \(metadata.setLabel.lowercased())")
            .hardsetText(.caption)
            .foregroundStyle(Tokens.Color.chalkDim)
            .lineLimit(2)
        }
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(spokenLabel)
  }

  /// The countdown, in `chalk` whether it runs or is paused: the paused state is carried by the
  /// word "Paused" and the play key, never by a dimmer colour. It is drawn straight on the panel,
  /// with no tile or texture behind it: the figure is the largest on the screen and needs nothing
  /// to stand on.
  @ViewBuilder private var countdown: some View {
    switch state {
    case .idle:
      EmptyView()
    case .running(let endsAt):
      // System-rendered from the deadline. Costs zero updates and survives backgrounding,
      // because there is nothing of ours to keep running.
      Text(timerInterval: referenceDate...max(endsAt, referenceDate), countsDown: true)
        .hardsetText(.hero)
        .foregroundStyle(Tokens.Color.chalk)
        .lineLimit(1)
        .fixedSize()
    case .paused(let remaining):
      Text(remaining.clockString)
        .hardsetText(.hero)
        .foregroundStyle(Tokens.Color.chalk)
        .lineLimit(1)
        .fixedSize()
    }
  }

  /// The ±15 labels begin with what the keys show, "−15" read as "Minus 15", so a Voice Control
  /// user can say what they see; the older "Subtract 15 seconds" still answers.
  private var controls: some View {
    HStack(spacing: Tokens.Spacing.snug) {
      control(
        title: "−15",
        systemImage: nil,
        accessibilityLabel: "Minus 15 seconds",
        inputLabels: ["Minus 15", "Subtract 15 seconds"]
      ) { onAdjust(.seconds(-15)) }
      control(
        title: "+15",
        systemImage: nil,
        accessibilityLabel: "Plus 15 seconds",
        inputLabels: ["Plus 15", "Add 15 seconds"]
      ) { onAdjust(.seconds(15)) }
      control(
        title: nil,
        systemImage: state.isRunning ? "pause.fill" : "play.fill",
        accessibilityLabel: state.isRunning ? "Pause rest" : "Resume rest",
        action: onPauseResume
      )
      control(
        title: nil,
        systemImage: "forward.end.fill",
        accessibilityLabel: "Skip rest",
        action: onSkip
      )
    }
  }

  /// A rest control: a figure or a symbol in a 56 pt region, with no key face. Four of them share
  /// the bar's width, so each is wide enough that the whole region is the target.
  private func control(
    title: String?,
    systemImage: String?,
    accessibilityLabel: String,
    inputLabels: [String] = [],
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Group {
        if let title {
          Text(title)
            .font(Tokens.Text.figure)
        } else if let systemImage {
          Image(systemName: systemImage)
            .font(Tokens.Text.headline)
        }
      }
      .foregroundStyle(Tokens.Color.chalk)
      .frame(minWidth: Tokens.loggerTapTarget)
    }
    .buttonStyle(InlineControlStyle(minHeight: Tokens.loggerTapTarget, alignment: .center))
    .accessibilityLabel(accessibilityLabel)
    .accessibilityInputLabels(inputLabels.isEmpty ? [accessibilityLabel] : inputLabels)
  }

  /// What VoiceOver reads for the countdown.
  ///
  /// The running case embeds the same system-rendered timer as the visible countdown. Nothing
  /// re-renders this view while a rest runs, so a time computed here would be the time left when
  /// the bar was drawn, read back unchanged a minute later. The paused remainder is frozen, so a
  /// fixed string is already correct.
  private var spokenLabel: Text {
    let after = metadata.map { ", after \($0.exerciseName), \($0.setLabel)" } ?? ""
    switch state {
    case .idle:
      return Text(verbatim: "Not resting")
    case .running(let endsAt):
      let left = Text(timerInterval: referenceDate...max(endsAt, referenceDate), countsDown: true)
      return Text("Resting, \(left) remaining\(after)")
    case .paused(let remaining):
      return Text(
        verbatim: "Rest paused, \(ExerciseSectionView.spoken(remaining)) remaining\(after)")
    }
  }

}

#if DEBUG
  #Preview("Rest bar") {
    VStack(spacing: Tokens.Spacing.loose) {
      RestBarView(
        state: .running(endsAt: Date().addingTimeInterval(96)),
        metadata: RestMetadata(
          exerciseName: "Leg Press", setOrdinal: 2, plannedSets: 4,
          machineName: "Hammer Strength"
        ),
        onAdjust: { _ in }, onPauseResume: {}, onSkip: {}
      )
      RestBarView(
        state: .paused(remaining: .seconds(75)),
        metadata: RestMetadata(exerciseName: "Leg Press", setOrdinal: 2, plannedSets: 4),
        onAdjust: { _ in }, onPauseResume: {}, onSkip: {}
      )
    }
    .padding(.vertical)
    .background(Tokens.Color.canvas)
  }

  private func previewRestBar(paused: Bool = true, withMetadata: Bool = true) -> some View {
    RestBarView(
      state: paused
        ? .paused(remaining: .seconds(96)) : .running(endsAt: Date().addingTimeInterval(96)),
      metadata: withMetadata
        ? RestMetadata(
          exerciseName: "Leg Press", setOrdinal: 2, plannedSets: 4, machineName: "Hammer Strength")
        : nil,
      onAdjust: { _ in }, onPauseResume: {}, onSkip: {}
    )
  }

  #Preview("Rest bar, paused at 402 pt with metadata (two lines)") {
    previewRestBar()
      .frame(width: 402)
      .padding(.vertical)
      .background(Tokens.Color.canvas)
  }

  #Preview("Rest bar, paused at 402 pt without metadata") {
    previewRestBar(withMetadata: false)
      .frame(width: 402)
      .padding(.vertical)
      .background(Tokens.Color.canvas)
  }

  #Preview("Rest bar, paused at 440 pt with metadata") {
    previewRestBar()
      .frame(width: 440)
      .padding(.vertical)
      .background(Tokens.Color.canvas)
  }

  #Preview("Rest bar, paused at 440 pt without metadata") {
    previewRestBar(withMetadata: false)
      .frame(width: 440)
      .padding(.vertical)
      .background(Tokens.Color.canvas)
  }

  #Preview("Rest bar, paused at accessibility3") {
    previewRestBar()
      .frame(width: 402)
      .environment(\.dynamicTypeSize, .accessibility3)
      .padding(.vertical)
      .background(Tokens.Color.canvas)
  }

  #Preview("Rest bar, running at 440 pt") {
    previewRestBar(paused: false)
      .frame(width: 440)
      .padding(.vertical)
      .background(Tokens.Color.canvas)
  }
#endif
