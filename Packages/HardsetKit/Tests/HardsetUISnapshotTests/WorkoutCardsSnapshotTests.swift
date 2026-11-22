#if canImport(UIKit)
  import Foundation
  import HardsetCore
  import HardsetUI
  import SwiftUI
  import Testing
  import UIKit

  /// Renders the Train tab's saved workouts and the workout editor for review from images. Like the
  /// other render suites it is inert unless `HARDSET_SNAPSHOT_DIR` is set, and it asserts nothing
  /// about pixels: what it protects is that every state draws at all, for a person to read.
  @MainActor
  @Suite("Saved workouts render for review", .serialized)
  struct WorkoutCardsSnapshotTests {
    private static let phone = CGSize(width: 402, height: 874)
    private static let tall = CGSize(width: 402, height: 1800)

    private static func card(
      _ name: String, movements: Int, upNext: Bool, line: String
    ) -> WorkoutCard {
      WorkoutCard(
        id: TemplateID(), name: name, movementCount: movements, isUpNext: upNext, contextLine: line,
        movementsLine: movements == 1 ? "1 movement" : "\(movements) movements")
    }

    private static var rotation: [WorkoutCard] {
      [
        card("Upper B", movements: 6, upNext: true,
          line: "Up next · last done 11 days ago · beat 4 of 6 last time"),
        card("Upper A", movements: 5, upNext: false, line: "Last done 4 days ago"),
        card("Lower", movements: 1, upNext: false, line: "Not done yet"),
      ]
    }

    /// The column as the Train tab draws it: the saved workouts, the empty "Start workout", then the
    /// controls that follow it. The start is drawn here as the screen draws it, primary with nothing
    /// saved and secondary under the workouts, so the render shows the order a lifter meets the
    /// controls in, with the screen's own spacing between the groups.
    private static func cards(_ cards: [WorkoutCard], canRepeatLast: Bool = true) -> some View {
      ScrollView {
        VStack(alignment: .leading, spacing: Tokens.Spacing.block) {
          if !cards.isEmpty {
            WorkoutCardsView(cards: cards, onStart: { _ in }, onEdit: { _ in })
          }
          VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
            Button {
            } label: {
              Label("Start workout", systemImage: "play.fill")
                .labelStyle(.titleAndIcon)
            }
            .buttonStyle(HardsetButtonStyle(cards.isEmpty ? .primary : .secondary, size: .logger))
            WorkoutCardActions(canRepeatLast: canRepeatLast, onRepeatLast: {}, onNew: {})
          }
        }
        .padding(Tokens.Spacing.loose)
      }
      .background(Tokens.Color.canvas.ignoresSafeArea())
    }

    @Test func cardsInEveryAppearance() async throws {
      try await Snapshot.capture("kit-workoutcards-rotation-dark", size: Self.phone) {
        Self.cards(Self.rotation)
      }
      try await Snapshot.capture("kit-workoutcards-rotation-light", size: Self.phone, style: .light) {
        Self.cards(Self.rotation)
      }
      try await Snapshot.capture(
        "kit-workoutcards-rotation-dark-contrast", size: Self.phone, contrast: .high
      ) { Self.cards(Self.rotation) }
    }

    /// With nothing saved there are no cards: the empty start, then the ways to make a workout.
    @Test func noWorkoutsAndNothingToRepeat() async throws {
      try await Snapshot.capture("kit-workoutcards-empty-dark", size: Self.phone) {
        Self.cards([], canRepeatLast: false)
      }
      try await Snapshot.capture("kit-workoutcards-empty-repeat-dark", size: Self.phone) {
        Self.cards([], canRepeatLast: true)
      }
    }

    @Test func cardsAtAccessibilitySize() async throws {
      try await Snapshot.capture(
        "kit-workoutcards-rotation-dark-ax3", size: Self.tall, typeSize: .accessibility3
      ) { Self.cards(Self.rotation) }
    }

    // MARK: - Editor

    private static var catalog: [CatalogEntry] { ExerciseCatalog.v1.compactMap(\.catalogEntry) }

    /// Two movements: one with a rep range and a rest, one with neither.
    private static var draft: WorkoutDraft {
      var draft = WorkoutDraft(newAtPosition: 0)
      draft.name = "Upper A"
      draft.add(catalog[0])
      draft.add(catalog[min(1, catalog.count - 1)])
      draft.enableRepRange(draft.movements[0].id)
      draft.setRest(draft.movements[0].id, to: 90)
      return draft
    }

    private static func balance(for draft: WorkoutDraft) -> SplitBalance {
      SplitBalanceAnalyzer.balance(
        templates: [draft.template], attribution: AttributionIndex(entries: catalog))
    }

    private static func editor(_ draft: WorkoutDraft, balance: SplitBalance? = nil) -> some View {
      NavigationStack {
        WorkoutEditorView(
          draft: .constant(draft), balance: balance, onAddMovement: {}, onSave: {},
          onDelete: draft.isNew ? nil : {}
        )
        .hardsetNavigationTitle(draft.isNew ? "New saved workout" : "Edit saved workout")
      }
      .tint(Tokens.Color.plateBlue)
      .background(Tokens.Color.canvas.ignoresSafeArea())
    }

    /// A new workout with nothing in it, where Save waits and says what for.
    @Test func editorEmpty() async throws {
      try await Snapshot.capture("kit-workouteditor-empty-dark", size: Self.phone) {
        Self.editor(WorkoutDraft(newAtPosition: 0))
      }
    }

    /// Movements with a range and a rest, and the split balance under them, in both appearances.
    @Test func editorWithMovementsAndBalance() async throws {
      let draft = Self.draft
      try await Snapshot.capture("kit-workouteditor-balance-dark", size: Self.tall) {
        Self.editor(draft, balance: Self.balance(for: draft))
      }
      try await Snapshot.capture("kit-workouteditor-balance-light", size: Self.tall, style: .light) {
        Self.editor(draft, balance: Self.balance(for: draft))
      }
    }

    @Test func editorAtAccessibilitySize() async throws {
      let draft = Self.draft
      try await Snapshot.capture(
        "kit-workouteditor-balance-dark-ax3", size: CGSize(width: 402, height: 3600),
        typeSize: .accessibility3
      ) { Self.editor(draft, balance: Self.balance(for: draft)) }
    }
  }
#endif
