import HardsetCore
import SwiftUI

/// Names a movement of the lifter's own and says which muscles it trains.
///
/// The rules live in `MovementEditorDraft`, which is tested without a view; this draws them. The
/// lifter picks a body part, then a muscle where the part has more than one, optionally up to three
/// more muscles the movement works, and what the load is applied with. Nothing is inferred from the
/// name, and Save waits until there is a name and a primary muscle, saying which is missing, so a
/// movement is never half tagged.
///
/// Long, so it scrolls, and a failed save is a native alert rather than a banner at the top: the
/// banner would be scrolled out of sight beside the Save button it answers. The sheet stays up with
/// everything typed, so trying again is one tap.
public struct MovementEditorSheet: View {
  private let title: String
  private let confirmLabel: String
  @Binding private var errorMessage: String?
  private let onSave: (String, CustomAttribution) -> Void
  private let onCancel: () -> Void

  @State private var draft: MovementEditorDraft
  @State private var choosesSecondaries = false
  @FocusState private var isNameFocused: Bool
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  /// - Parameters:
  ///   - draft: Where the sheet starts: a typed name for a new movement, or an existing movement
  ///     read through `MovementEditorDraft(entry:)` for retagging it.
  ///   - errorMessage: A failed save, in the lifter's words. Shown in an alert; cleared when it is
  ///     dismissed.
  ///   - onSave: Called with the trimmed name and the lifter's choice, only when both are complete.
  public init(
    title: String,
    confirmLabel: String = "Save",
    errorMessage: Binding<String?> = .constant(nil),
    draft: MovementEditorDraft,
    onSave: @escaping (String, CustomAttribution) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.title = title
    self.confirmLabel = confirmLabel
    self._errorMessage = errorMessage
    self._draft = State(initialValue: draft)
    self.onSave = onSave
    self.onCancel = onCancel
  }

  public var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: Tokens.Spacing.section) {
          nameSection
          bodyPartSection
          if draft.asksForSpecificMuscle {
            muscleSection
          }
          secondarySection
          equipmentSection
          saveSection
        }
        .padding(.horizontal, Tokens.Spacing.loose)
        .padding(.top, Tokens.Spacing.loose)
        .padding(.bottom, Tokens.Spacing.section)
      }
      .scrollBounceBehavior(.basedOnSize)
      .scrollDismissesKeyboard(.interactively)
      .background(Tokens.Color.canvas)
      .hardsetNavigationTitle(title)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: onCancel)
        }
      }
      .alert(
        "Could not save this movement",
        isPresented: Binding(
          get: { errorMessage != nil },
          set: { if !$0 { errorMessage = nil } }
        )
      ) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(errorMessage ?? "")
      }
    }
    // A brushed swipe must not throw away what was typed. Cancel stays the explicit way out.
    .interactiveDismissDisabled(!draft.trimmedName.isEmpty)
  }

  // MARK: - Sections

  private var nameSection: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      SectionLabel("Name")
      if draft.nameIsFixed {
        // Plain text, not a field: nothing that looks typeable should refuse typing.
        Text(draft.name)
          .font(Tokens.Text.label)
          .foregroundStyle(Tokens.Color.chalk)
          .fixedSize(horizontal: false, vertical: true)
        Text(MovementEditorDraft.fixedNameNote)
          .hardsetText(.caption)
          .foregroundStyle(Tokens.Color.chalkDim)
          .fixedSize(horizontal: false, vertical: true)
      } else {
        nameField
      }
    }
  }

  private var nameField: some View {
    TextField(
      text: $draft.name,
      prompt: Text("Movement name").foregroundStyle(Tokens.Color.chalkDim)
    ) {
      Text("Movement name")
    }
    .font(Tokens.Text.label)
    .foregroundStyle(Tokens.Color.chalk)
    .tint(Tokens.Color.plateBlue)
    .focused($isNameFocused)
    .hardsetNameInput()
    .submitLabel(.done)
    .padding(.horizontal, Tokens.Spacing.regular)
    .padding(.vertical, Tokens.Spacing.snug)
    .frame(maxWidth: .infinity, minHeight: Tokens.loggerTapTarget, alignment: .leading)
    .entryFieldChrome(isFocused: isNameFocused)
    .onTapGesture { isNameFocused = true }
  }

  private var bodyPartSection: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      SectionLabel("Body part")
      chipGrid {
        ForEach(MuscleFilterCategory.allCases, id: \.rawValue) { category in
          HardsetChip(
            ExercisePickerView.categoryTitle(for: category),
            isSelected: draft.bodyPart == category
          ) {
            draft.choose(bodyPart: category)
          }
        }
      }
    }
  }

  /// Shown only where the body part has more than one muscle. One tap each, as rows, because the
  /// choice decides what the movement counts toward.
  private var muscleSection: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      SectionLabel("Which muscle it trains most")
      ForEach(draft.specificMuscles, id: \.rawValue) { muscle in
        SelectionRow(
          title: ExercisePickerView.displayName(MuscleKey(muscle)),
          isSelected: draft.primary == muscle
        ) {
          draft.choose(primary: muscle)
        }
      }
    }
  }

  private var secondarySection: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      SectionLabel("Also works (optional)")
      Text(
        "Up to \(CustomAttribution.maximumSecondaries). Each counts as half a set of the movement."
      )
      .hardsetText(.caption)
      .foregroundStyle(Tokens.Color.chalkDim)
      .fixedSize(horizontal: false, vertical: true)

      if !draft.secondary.isEmpty {
        chipGrid {
          ForEach(draft.secondary, id: \.rawValue) { muscle in
            let name = ExercisePickerView.displayName(MuscleKey(muscle))
            HardsetChip(name, isSelected: true) {
              draft.toggleSecondary(muscle)
            }
            .accessibilityLabel("\(name), remove")
          }
        }
      }

      Button {
        choosesSecondaries.toggle()
      } label: {
        Label(
          choosesSecondaries ? "Done choosing" : "Choose muscles",
          systemImage: choosesSecondaries ? "checkmark" : "plus"
        )
      }
      .buttonStyle(HardsetButtonStyle(.secondary))

      if choosesSecondaries {
        secondaryChoices
      }
    }
  }

  /// Every muscle but the primary, by body part. A muscle already chosen can always be unchosen;
  /// the rest wait once three are chosen.
  private var secondaryChoices: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
      ForEach(MuscleFilterCategory.allCases, id: \.rawValue) { category in
        let options = category.members.filter { $0 != draft.primary }
        if !options.isEmpty {
          VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
            Text(ExercisePickerView.categoryTitle(for: category))
              .font(Tokens.Text.provenance)
              .foregroundStyle(Tokens.Color.chalkDim)
            chipGrid {
              ForEach(options, id: \.rawValue) { muscle in
                let isChosen = draft.secondary.contains(muscle)
                let isWaiting = !isChosen && draft.secondaryLimitReached
                HardsetChip(
                  ExercisePickerView.displayName(MuscleKey(muscle)), isSelected: isChosen
                ) {
                  draft.toggleSecondary(muscle)
                }
                .disabled(isWaiting)
                // A chip's style never reads isEnabled, so the wait is dimmed here, as every
                // disabled control is.
                .opacity(isWaiting ? 0.4 : 1)
              }
            }
          }
        }
      }
    }
  }

  private var equipmentSection: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      SectionLabel("Equipment")
      if draft.equipmentIsUnset {
        Text(MovementEditorDraft.equipmentUnsetNote)
          .hardsetText(.caption)
          .foregroundStyle(Tokens.Color.chalkDim)
          .fixedSize(horizontal: false, vertical: true)
      }
      chipGrid {
        ForEach(MovementEditorDraft.equipment, id: \.rawValue) { modality in
          HardsetChip(modality.label, isSelected: draft.modality == modality) {
            draft.modality = modality
          }
        }
      }
    }
  }

  private var saveSection: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      Button {
        guard draft.canSave, let attribution = draft.attribution else { return }
        onSave(draft.trimmedName, attribution)
      } label: {
        Text(confirmLabel)
      }
      .buttonStyle(HardsetButtonStyle(.primary, size: .logger))
      .disabled(!draft.canSave)

      if let missing = draft.whatIsMissing {
        Text(missing)
          .hardsetText(.provenance)
          .foregroundStyle(Tokens.Color.chalkDim)
          .fixedSize(horizontal: false, vertical: true)
      } else {
        Text(draft.savedNote)
          .hardsetText(.caption)
          .foregroundStyle(Tokens.Color.chalkDim)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  // MARK: - Layout

  /// Chips that wrap into rows at ordinary sizes, and stack one to a line at accessibility sizes,
  /// where a row of chips would clip the longer names.
  private func chipGrid<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    let columns =
      dynamicTypeSize.isAccessibilitySize
      ? [GridItem(.flexible(), alignment: .leading)]
      : [GridItem(.adaptive(minimum: 104), spacing: Tokens.Spacing.snug, alignment: .leading)]
    return LazyVGrid(columns: columns, alignment: .leading, spacing: Tokens.Spacing.snug) {
      content()
    }
  }
}

#if DEBUG
  #Preview("New movement") {
    MovementEditorSheet(
      title: "New movement", confirmLabel: "Add to workout",
      draft: MovementEditorDraft(name: "Nautilus lever row"), onSave: { _, _ in }, onCancel: {}
    )
    .hardsetSheet()
  }

  #Preview("Retag a movement") {
    MovementEditorSheet(
      title: "Movement", draft: {
        var draft = MovementEditorDraft(name: "Lever row")
        draft.choose(bodyPart: .back)
        draft.choose(primary: .lats)
        draft.toggleSecondary(.biceps)
        return draft
      }(), onSave: { _, _ in }, onCancel: {}
    )
    .hardsetSheet()
  }
#endif
