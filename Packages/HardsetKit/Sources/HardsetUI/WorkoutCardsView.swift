import HardsetCore
import SwiftUI

/// The Train tab's saved workouts: the one that is up next, large, then the rest.
///
/// Starting is one tap, on the card's own button: there is no confirmation and no setup, because the
/// lifter is standing at a machine. The up-next card reads like a coach's note, which workout, when
/// it was last done, and how that session went against the one before it. Nothing here invents a
/// programme: the order is only whichever workout was done longest ago, so two of them take turns.
///
/// All of the words come from `WorkoutCard`, which is tested without a view; this draws them. The
/// buttons that sit under the cards and the empty start are `WorkoutCardActions`, a separate view so
/// the screen can put the empty "Start workout" between the two.
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

  /// Side by side at ordinary sizes, stacked at accessibility sizes, so a long name never squeezes
  /// the buttons.
  private var buttonLayout: AnyLayout {
    dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tokens.Spacing.snug))
      : AnyLayout(HStackLayout(alignment: .center, spacing: Tokens.Spacing.regular))
  }
}

// MARK: - Actions under the cards

/// The two buttons below the empty "Start workout": "Repeat last workout", which starts a session at
/// once, and "New saved workout", which opens the plan editor and starts nothing.
///
/// They are named for what they do and sit below the start, never above it: a lifter in a hurry
/// meets the buttons that start a workout first, and the one that opens an editor says it makes a
/// saved workout, so it cannot be mistaken for starting a session. Repeat is the one that starts, so
/// it comes first.
public struct WorkoutCardActions: View {
  private let canRepeatLast: Bool
  private let onRepeatLast: () -> Void
  private let onNew: () -> Void

  /// - Parameters:
  ///   - canRepeatLast: Whether a finished workout exists to repeat. "Repeat last workout" is only
  ///     offered when it does, so it is never a button that has nothing to do.
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
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      if canRepeatLast {
        Button(action: onRepeatLast) {
          Label("Repeat last workout", systemImage: "arrow.counterclockwise")
            .labelStyle(.titleAndIcon)
        }
        .buttonStyle(HardsetButtonStyle(.secondary, size: .regular))
      }

      Button(action: onNew) {
        Label("New saved workout", systemImage: "plus")
          .labelStyle(.titleAndIcon)
      }
      .buttonStyle(HardsetButtonStyle(.secondary, size: .regular))
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
