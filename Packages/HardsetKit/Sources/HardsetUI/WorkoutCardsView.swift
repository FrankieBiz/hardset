import HardsetCore
import SwiftUI

/// The Train tab's saved workouts: the one that is up next, large, then the rest, then the two ways
/// to make a workout without building one.
///
/// Starting is one tap, on the card's own button: there is no confirmation and no setup, because the
/// lifter is standing at a machine. The up-next card reads like a coach's note, which workout, when
/// it was last done, and how that session went against the one before it. Nothing here invents a
/// programme: the order is only whichever workout was done longest ago, so two of them take turns.
///
/// All of the words come from `WorkoutCard`, which is tested without a view; this draws them.
public struct WorkoutCardsView: View {
  private let cards: [WorkoutCard]
  private let canRepeatLast: Bool
  private let onStart: (TemplateID) -> Void
  private let onEdit: (TemplateID) -> Void
  private let onNew: () -> Void
  private let onRepeatLast: () -> Void

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  /// - Parameters:
  ///   - cards: `WorkoutCard.cards`, up next first.
  ///   - canRepeatLast: Whether a finished workout exists to repeat. "Repeat last workout" is only
  ///     offered when it does, so it is never a button that has nothing to do.
  public init(
    cards: [WorkoutCard],
    canRepeatLast: Bool,
    onStart: @escaping (TemplateID) -> Void,
    onEdit: @escaping (TemplateID) -> Void,
    onNew: @escaping () -> Void,
    onRepeatLast: @escaping () -> Void
  ) {
    self.cards = cards
    self.canRepeatLast = canRepeatLast
    self.onStart = onStart
    self.onEdit = onEdit
    self.onNew = onNew
    self.onRepeatLast = onRepeatLast
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
      if let upNext = cards.first {
        upNextCard(upNext)
      }
      if cards.count > 1 {
        SectionLabel("Your workouts", count: cards.count - 1)
          .padding(.top, Tokens.Spacing.snug)
        ForEach(Array(cards.dropFirst())) { card in
          otherCard(card)
        }
      }
      actions
    }
  }

  // MARK: - Cards

  private func upNextCard(_ card: WorkoutCard) -> some View {
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
    .padding(Tokens.Spacing.loose)
    .frame(maxWidth: .infinity, alignment: .leading)
    .hardsetCard()
  }

  private func otherCard(_ card: WorkoutCard) -> some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
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

      buttonLayout {
        Button {
          onStart(card.id)
        } label: {
          Label("Start", systemImage: "play.fill")
            .labelStyle(.titleAndIcon)
        }
        .buttonStyle(HardsetButtonStyle(.secondary, size: .regular, fullWidth: false))
        .accessibilityLabel("Start \(card.name)")

        editButton(card)
      }
    }
    .padding(Tokens.Spacing.loose)
    .frame(maxWidth: .infinity, alignment: .leading)
    .hardsetCard(cornerRadius: Tokens.Radius.control)
  }

  private func editButton(_ card: WorkoutCard) -> some View {
    Button {
      onEdit(card.id)
    } label: {
      Text("Edit")
    }
    .buttonStyle(HardsetButtonStyle(.quiet, size: .regular, fullWidth: false))
    .accessibilityLabel("Edit \(card.name)")
  }

  // MARK: - Making a workout

  private var actions: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      Button(action: onNew) {
        Label("New workout", systemImage: "plus")
          .labelStyle(.titleAndIcon)
      }
      .buttonStyle(HardsetButtonStyle(.secondary, size: .regular))

      if canRepeatLast {
        Button(action: onRepeatLast) {
          Label("Repeat last workout", systemImage: "arrow.counterclockwise")
            .labelStyle(.titleAndIcon)
        }
        .buttonStyle(HardsetButtonStyle(.secondary, size: .regular))
      }
    }
    .padding(.top, Tokens.Spacing.snug)
  }

  /// Side by side at ordinary sizes, stacked at accessibility sizes, so a long name never squeezes
  /// the buttons.
  private var buttonLayout: AnyLayout {
    dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tokens.Spacing.snug))
      : AnyLayout(HStackLayout(alignment: .center, spacing: Tokens.Spacing.regular))
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
        canRepeatLast: true, onStart: { _ in }, onEdit: { _ in }, onNew: {}, onRepeatLast: {}
      )
      .padding(Tokens.Spacing.loose)
    }
    .background(Tokens.Color.canvas)
  }
#endif
