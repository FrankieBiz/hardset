import HardsetCore
import SwiftUI

/// The Train tab's saved workouts: the one that is up next, large, then the rest.
///
/// Starting is one tap, on the workout's own button: there is no confirmation and no setup, because
/// the lifter is standing at a machine. The up-next workout reads like a coach's note, which
/// workout, when it was last done, and how that session went against the one before it. Nothing
/// here invents a programme: the order is only whichever workout was done longest ago, so two of
/// them take turns.
///
/// Nothing is boxed. The up-next workout is type on the canvas with the screen's one primary
/// button under it, and the others are rows separated by a hairline, each with its verbs as words:
/// a card's fill and corner said nothing a row's own text did not.
///
/// All of the words come from `WorkoutCard`, which is tested without a view; this draws them. The
/// buttons that sit under the workouts and the empty start are `WorkoutCardActions`, a separate
/// view so the screen can put the empty "Start workout" between the two.
public struct WorkoutCardsView: View {
  private let cards: [WorkoutCard]
  private let onStart: (TemplateID) -> Void
  private let onEdit: (TemplateID) -> Void

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  /// - Parameters:
  ///   - cards: `WorkoutCard.cards`, up next first.
  public init(
    cards: [WorkoutCard],
    onStart: @escaping (TemplateID) -> Void,
    onEdit: @escaping (TemplateID) -> Void
  ) {
    self.cards = cards
    self.onStart = onStart
    self.onEdit = onEdit
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.section) {
      if let upNext = cards.first {
        upNextWorkout(upNext)
      }
      if cards.count > 1 {
        VStack(alignment: .leading, spacing: 0) {
          SectionLabel("Your workouts", count: cards.count - 1)
            .padding(.bottom, Tokens.Spacing.snug)
          ForEach(Array(cards.dropFirst())) { card in
            otherWorkout(card)
          }
        }
      }
    }
  }

  // MARK: - Workouts

  private func upNextWorkout(_ card: WorkoutCard) -> some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
      VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
        Text(card.name)
          .font(Tokens.Text.title)
          .foregroundStyle(Tokens.Color.chalk)
          .fixedSize(horizontal: false, vertical: true)
        Text(card.movementsLine)
          .font(Tokens.Text.label)
          .foregroundStyle(Tokens.Color.chalk)
        Text(card.contextLine)
          .font(Tokens.Text.provenance)
          .foregroundStyle(Tokens.Color.chalkDim)
          .fixedSize(horizontal: false, vertical: true)
      }
      .accessibilityElement(children: .combine)

      Button {
        onStart(card.id)
      } label: {
        Label("Start \(card.name)", systemImage: "play.fill")
          .labelStyle(.titleAndIcon)
      }
      .buttonStyle(HardsetButtonStyle(.primary, size: .logger))

      editButton(card)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// A row: the name and its line, and the two verbs as words at the trailing edge, or under the
  /// text at accessibility sizes so a long name keeps the width. The hairline above it is where it
  /// meets the row before it, or the label.
  private func otherWorkout(_ card: WorkoutCard) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Rectangle()
        .fill(Tokens.Color.hairline)
        .frame(height: Tokens.Stroke.hairline)
        .accessibilityHidden(true)

      rowLayout {
        VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
          Text(card.name)
            .font(Tokens.Text.headline)
            .foregroundStyle(Tokens.Color.chalk)
            .fixedSize(horizontal: false, vertical: true)
          Text("\(card.movementsLine) · \(card.contextLine)")
            .font(Tokens.Text.provenance)
            .foregroundStyle(Tokens.Color.chalkDim)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .frame(maxWidth: .infinity, alignment: .leading)

        HStack(spacing: Tokens.Spacing.regular) {
          Button {
            onStart(card.id)
          } label: {
            Label("Start", systemImage: "play.fill")
              .labelStyle(.titleAndIcon)
              .font(Tokens.Text.headline)
              .foregroundStyle(Tokens.Color.chalk)
          }
          .buttonStyle(InlineControlStyle(minHeight: Tokens.minimumTapTarget, alignment: .leading))
          .accessibilityLabel("Start \(card.name)")

          editButton(card)
        }
      }
      .padding(.vertical, Tokens.Spacing.snug)
    }
  }

  private func editButton(_ card: WorkoutCard) -> some View {
    Button {
      onEdit(card.id)
    } label: {
      Text("Edit")
        .font(Tokens.Text.headline)
        .foregroundStyle(Tokens.Color.chalkDim)
    }
    .buttonStyle(InlineControlStyle(minHeight: Tokens.minimumTapTarget, alignment: .leading))
    .accessibilityLabel("Edit \(card.name)")
  }

  /// Side by side at ordinary sizes, stacked at accessibility sizes, so a long name never squeezes
  /// the verbs.
  private var rowLayout: AnyLayout {
    dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tokens.Spacing.snug))
      : AnyLayout(HStackLayout(alignment: .center, spacing: Tokens.Spacing.regular))
  }
}

// MARK: - Actions under the workouts

/// The two controls below the empty "Start workout": "Repeat last workout", which starts a session
/// at once, and "New saved workout", which opens the plan editor and starts nothing.
///
/// They are named for what they do and sit below the start, never above it: a lifter in a hurry
/// meets the controls that start a workout first, and the one that opens an editor says it makes a
/// saved workout, so it cannot be mistaken for starting a session. Repeat is the one that starts, so
/// it comes first, and it keeps the logger's 56 pt region because a missed tap there starts
/// nothing at a machine. Both are words and a symbol with no face, as the live session's actions
/// are.
public struct WorkoutCardActions: View {
  private let canRepeatLast: Bool
  private let onRepeatLast: () -> Void
  private let onNew: () -> Void

  /// - Parameters:
  ///   - canRepeatLast: Whether a finished workout exists to repeat. "Repeat last workout" is only
  ///     offered when it does, so it is never a control that has nothing to do.
  public init(
    canRepeatLast: Bool,
    onRepeatLast: @escaping () -> Void,
    onNew: @escaping () -> Void
  ) {
    self.canRepeatLast = canRepeatLast
    self.onRepeatLast = onRepeatLast
    self.onNew = onNew
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if canRepeatLast {
        Button(action: onRepeatLast) {
          Label("Repeat last workout", systemImage: "arrow.counterclockwise")
            .labelStyle(.titleAndIcon)
            .font(Tokens.Text.headline)
            .foregroundStyle(Tokens.Color.chalk)
            // Inside the region: at accessibility sizes both labels wrap, and the region's minimum
            // height alone left the two touching.
            .padding(.vertical, Tokens.Spacing.snug)
        }
        .buttonStyle(
          InlineControlStyle(minHeight: Tokens.loggerTapTarget, alignment: .leading, fullWidth: true)
        )
      }

      Button(action: onNew) {
        Label("New saved workout", systemImage: "plus")
          .labelStyle(.titleAndIcon)
          .font(Tokens.Text.headline)
          .foregroundStyle(Tokens.Color.chalk)
          .padding(.vertical, Tokens.Spacing.snug)
      }
      .buttonStyle(
        InlineControlStyle(minHeight: Tokens.minimumTapTarget, alignment: .leading, fullWidth: true)
      )
    }
  }
}

#if DEBUG
  #Preview("Workout cards") {
    ScrollView {
      WorkoutCardsView(
        cards: [
          WorkoutCard(
            id: TemplateID(), name: "Upper B", movementCount: 6, isUpNext: true,
            contextLine: "Up next · last done 11 days ago · beat 4 of 6 last time",
            movementsLine: "6 movements"),
          WorkoutCard(
            id: TemplateID(), name: "Upper A", movementCount: 1, isUpNext: false,
            contextLine: "Last done 4 days ago", movementsLine: "1 movement"),
        ],
        onStart: { _ in }, onEdit: { _ in }
      )
      .padding(Tokens.Spacing.loose)
    }
    .background(Tokens.Color.canvas)
  }
#endif
