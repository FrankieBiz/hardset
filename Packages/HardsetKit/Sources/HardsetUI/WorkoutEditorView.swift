import HardsetCore
import SwiftUI

/// Makes or changes a saved workout: its name, and its movements in order, each with a set count,
/// an optional rep range, an optional rest and, if it was saved with one, a machine.
///
/// The rules live in `WorkoutDraft`, which is tested without a view; this draws them and sends the
/// lifter's taps back. Set counts and rep ranges are stepped with large controls rather than typed:
/// a plan is made sitting down, not between sets, and a stepper cannot hold a number the plan
/// refuses.
///
/// Below the movements, the split balance states what the whole rotation plans for each body
/// group: the sets that touch it, or that nothing is planned. It judges nothing and sets no target,
/// and it says so when some planned sets sit on movements with no muscles recorded, since those
/// count toward no group.
///
/// Draws only the scrolling content. The screen that hosts it owns the title, the Cancel action,
/// the movement picker and what happens on save, because those need storage this view does not have.
public struct WorkoutEditorView: View {
  @Binding private var draft: WorkoutDraft
  private let balance: SplitBalance?
  private let onAddMovement: () -> Void
  private let onSave: () -> Void
  private let onDelete: (() -> Void)?

  @FocusState private var isNameFocused: Bool
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  /// - Parameters:
  ///   - balance: What the rotation plans per body group, including this draft. Nil draws none.
  ///   - onDelete: Offered only for a saved workout. The caller confirms it.
  public init(
    draft: Binding<WorkoutDraft>,
    balance: SplitBalance?,
    onAddMovement: @escaping () -> Void,
    onSave: @escaping () -> Void,
    onDelete: (() -> Void)? = nil
  ) {
    self._draft = draft
    self.balance = balance
    self.onAddMovement = onAddMovement
    self.onSave = onSave
    self.onDelete = onDelete
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Tokens.Spacing.section) {
        nameSection
        movementsSection
        if let balance {
          balanceSection(balance)
        }
        saveSection
      }
      .padding(.horizontal, Tokens.Spacing.loose)
      .padding(.top, Tokens.Spacing.loose)
      .padding(.bottom, Tokens.Spacing.block)
    }
    .scrollBounceBehavior(.basedOnSize)
    .scrollDismissesKeyboard(.interactively)
    .background(Tokens.Color.canvas)
  }

  // MARK: - Name

  private var nameSection: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      SectionLabel("Name")
      TextField(
        text: $draft.name,
        prompt: Text("Upper A").foregroundStyle(Tokens.Color.chalkDim)
      ) {
        Text("Workout name")
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
  }

  // MARK: - Movements

  private var movementsSection: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
      SectionLabel("Movements", count: draft.movements.count)
      ForEach(draft.movements) { movement in
        movementCard(movement)
      }
      addMovementSlot
    }
  }

  private func movementCard(_ movement: WorkoutDraft.Movement) -> some View {
    let isFirst = draft.movements.first?.id == movement.id
    let isLast = draft.movements.last?.id == movement.id
    return VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
      headerLayout {
        VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
          Text(movement.exerciseName)
            .font(Tokens.Text.headline)
            .foregroundStyle(Tokens.Color.chalk)
            .fixedSize(horizontal: false, vertical: true)
          if movement.machineID != nil {
            HardsetTag(movement.machineName ?? "Saved machine", systemImage: "gearshape.2")
            Button {
              draft.clearMachine(movement.id)
            } label: {
              Text("Use the usual machine")
            }
            .buttonStyle(HardsetButtonStyle(.quiet, size: .regular, fullWidth: false))
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        HStack(spacing: Tokens.Spacing.snug) {
          iconButton("chevron.up", "Move \(movement.exerciseName) up", enabled: !isFirst) {
            draft.move(movement.id, by: -1)
          }
          iconButton("chevron.down", "Move \(movement.exerciseName) down", enabled: !isLast) {
            draft.move(movement.id, by: 1)
          }
          iconButton("trash", "Remove \(movement.exerciseName)", enabled: true) {
            draft.remove(movement.id)
          }
        }
      }

      stepperRow(
        "Sets", value: "\(movement.plannedSets)",
        decreaseLabel: "Fewer sets for \(movement.exerciseName)",
        increaseLabel: "More sets for \(movement.exerciseName)",
        canDecrease: movement.plannedSets > WorkoutDraft.minimumSets,
        canIncrease: movement.plannedSets < WorkoutDraft.maximumSets,
        decrease: { draft.stepSets(movement.id, by: -1) },
        increase: { draft.stepSets(movement.id, by: 1) }
      )
      repRangeSection(movement)
      restSection(movement)
    }
    .padding(Tokens.Spacing.loose)
    .frame(maxWidth: .infinity, alignment: .leading)
    .hardsetCard(cornerRadius: Tokens.Radius.control)
  }

  @ViewBuilder private func repRangeSection(_ movement: WorkoutDraft.Movement) -> some View {
    if let range = movement.repRange {
      VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
        Text("Rep range \(range.label)")
          .font(Tokens.Text.headline)
          .foregroundStyle(Tokens.Color.chalk)
        stepperRow(
          "From", value: "\(range.lower)",
          decreaseLabel: "Lower the bottom of the rep range for \(movement.exerciseName)",
          increaseLabel: "Raise the bottom of the rep range for \(movement.exerciseName)",
          canDecrease: range.lower > 1, canIncrease: range.lower < range.upper,
          decrease: { draft.stepRepLower(movement.id, by: -1) },
          increase: { draft.stepRepLower(movement.id, by: 1) }
        )
        stepperRow(
          "To", value: "\(range.upper)",
          decreaseLabel: "Lower the top of the rep range for \(movement.exerciseName)",
          increaseLabel: "Raise the top of the rep range for \(movement.exerciseName)",
          canDecrease: range.upper > range.lower, canIncrease: range.upper < 50,
          decrease: { draft.stepRepUpper(movement.id, by: -1) },
          increase: { draft.stepRepUpper(movement.id, by: 1) }
        )
        Text("When every set reaches the top at the same weight, the next target adds a step.")
          .hardsetText(.caption)
          .foregroundStyle(Tokens.Color.chalkDim)
          .fixedSize(horizontal: false, vertical: true)
        Button {
          draft.clearRepRange(movement.id)
        } label: {
          Text("Remove the rep range")
        }
        .buttonStyle(HardsetButtonStyle(.quiet, size: .regular, fullWidth: false))
      }
    } else {
      Button {
        draft.enableRepRange(movement.id)
      } label: {
        Label("Add a rep range", systemImage: "plus")
      }
      .buttonStyle(HardsetButtonStyle(.quiet, size: .regular, fullWidth: false))
    }
  }

  private func restSection(_ movement: WorkoutDraft.Movement) -> some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      Text("Rest")
        .font(Tokens.Text.label)
        .foregroundStyle(Tokens.Color.chalk)
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: Tokens.Spacing.snug) {
          ForEach(WorkoutDraft.restChoices, id: \.self) { choice in
            HardsetChip(
              WorkoutDraft.restLabel(choice), isSelected: movement.restSeconds == choice
            ) {
              draft.setRest(movement.id, to: choice)
            }
          }
        }
      }
      .accessibilityElement(children: .contain)
      .accessibilityLabel("Rest for \(movement.exerciseName)")
    }
  }

  // MARK: - Controls

  /// A label, then a minus, the value in tabular figures, and a plus. Each button is a 44 pt
  /// target, and one that cannot go further is dimmed as every disabled control is. The buttons are
  /// icons, so what VoiceOver and Voice Control hear is spelled out, naming the movement: several
  /// cards share one screen, and "Fewer sets" alone would not say whose.
  private func stepperRow(
    _ title: String, value: String, decreaseLabel: String, increaseLabel: String,
    canDecrease: Bool, canIncrease: Bool,
    decrease: @escaping () -> Void, increase: @escaping () -> Void
  ) -> some View {
    HStack(spacing: Tokens.Spacing.regular) {
      Text(title)
        .font(Tokens.Text.label)
        .foregroundStyle(Tokens.Color.chalk)
      Spacer(minLength: Tokens.Spacing.regular)
      iconButton("minus", decreaseLabel, enabled: canDecrease, action: decrease)
      Text(value)
        .font(Tokens.Text.figure)
        .monospacedDigit()
        .foregroundStyle(Tokens.Color.chalk)
        .frame(minWidth: Tokens.minimumTapTarget)
        .accessibilityLabel("\(title) \(value)")
      iconButton("plus", increaseLabel, enabled: canIncrease, action: increase)
    }
  }

  private func iconButton(
    _ systemImage: String, _ label: String, enabled: Bool, action: @escaping () -> Void
  ) -> some View {
    HeaderIconButton(systemImage: systemImage, accessibilityLabel: label, action: action)
      .disabled(!enabled)
      .opacity(enabled ? 1 : 0.4)
  }

  /// The place the next movement goes. Dashed, like every empty slot in the app.
  private var addMovementSlot: some View {
    let shape = RoundedRectangle(cornerRadius: Tokens.Radius.card)
    return Button(action: onAddMovement) {
      Label("Add movement", systemImage: "plus")
        .font(Tokens.Text.headline)
        .foregroundStyle(Tokens.Color.plateBlue)
        .frame(maxWidth: .infinity, minHeight: Tokens.loggerTapTarget)
        .contentShape(shape)
        .overlay(
          shape.strokeBorder(
            Tokens.Color.controlEdge,
            style: StrokeStyle(lineWidth: Tokens.Stroke.hairline, dash: [5, 4])
          )
        )
    }
    .buttonStyle(HardsetPressStyle())
  }

  /// The name and the reorder controls share a line at ordinary sizes, and stack at accessibility
  /// sizes, where the controls would leave the name a column one word wide.
  private var headerLayout: AnyLayout {
    dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tokens.Spacing.snug))
      : AnyLayout(HStackLayout(alignment: .top, spacing: Tokens.Spacing.regular))
  }

  // MARK: - Split balance

  private func balanceSection(_ balance: SplitBalance) -> some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      SectionLabel("Split balance")
      Text("Planned sets across one rotation, with each saved workout done once. It says what is planned and judges nothing.")
        .hardsetText(.caption)
        .foregroundStyle(Tokens.Color.chalkDim)
        .fixedSize(horizontal: false, vertical: true)
      VStack(alignment: .leading, spacing: 0) {
        ForEach(balance.rows) { row in
          HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.snug) {
            Text(row.title)
              .font(Tokens.Text.label)
              .foregroundStyle(Tokens.Color.chalk)
            Spacer(minLength: Tokens.Spacing.regular)
            if row.isEmpty {
              Image(systemName: "exclamationmark.triangle")
                .accessibilityHidden(true)
            }
            Text(row.line)
              .font(Tokens.Text.provenance)
          }
          .foregroundStyle(row.isEmpty ? Tokens.Color.warning : Tokens.Color.chalkDim)
          .padding(.vertical, Tokens.Spacing.snug)
          .overlay(alignment: .top) {
            Rectangle().fill(Tokens.Color.hairline).frame(height: Tokens.Stroke.hairline)
          }
          .accessibilityElement(children: .combine)
        }
      }
      if let note = balance.unattributedNote {
        HardsetBanner(.caveat, message: note)
      }
    }
  }

  // MARK: - Save

  private var saveSection: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      Button(action: onSave) {
        Text(draft.isNew ? "Save workout" : "Save changes")
      }
      .buttonStyle(HardsetButtonStyle(.primary, size: .logger))
      .disabled(!draft.canSave)

      if let missing = draft.whatIsMissing {
        Text(missing)
          .hardsetText(.provenance)
          .foregroundStyle(Tokens.Color.chalkDim)
          .fixedSize(horizontal: false, vertical: true)
      }

      if let onDelete {
        Button(action: onDelete) {
          Label("Delete workout", systemImage: "trash")
            .labelStyle(.titleAndIcon)
        }
        .buttonStyle(HardsetButtonStyle(.destructive, size: .regular))
        .padding(.top, Tokens.Spacing.regular)
      }
    }
  }
}

#if DEBUG
  #Preview("Workout editor") {
    WorkoutEditorPreview()
  }

  private struct WorkoutEditorPreview: View {
    @State private var draft: WorkoutDraft = {
      var draft = WorkoutDraft(newAtPosition: 0)
      draft.name = "Upper A"
      draft.add(
        CatalogEntry(
          id: ExerciseID(), name: "Chest press", slug: nil, isCurated: false, modality: .machine,
          primaryMuscle: MuscleKey(.chest), contributions: []))
      draft.enableRepRange(draft.movements[0].id)
      return draft
    }()

    var body: some View {
      WorkoutEditorView(draft: $draft, balance: nil, onAddMovement: {}, onSave: {})
    }
  }
#endif
