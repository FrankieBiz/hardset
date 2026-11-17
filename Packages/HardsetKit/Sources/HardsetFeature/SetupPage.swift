import HardsetCore
import HardsetStore
import HardsetUI
import SwiftUI

/// The last page of the first launch: "Before your first set." Units and gym, then "Start logging".
///
/// Units are two selection rows that edit the app's one stored preference directly, so a choice
/// here is the choice Settings shows. A lifter who already has gyms sees them as selection rows
/// with one preselected and no name field, so nothing is typed twice and nothing is duplicated; a
/// new lifter sees a single name field they may leave blank. Saving happens in the model, and a
/// failure stays on this page with its reason.
@MainActor
struct SetupPage: View {
  @Bindable var model: OnboardingModel
  @Binding var useImperial: Bool
  /// Called once the model has saved the choices.
  let onStart: () -> Void

  @FocusState private var isNameFocused: Bool

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Tokens.Spacing.section) {
        Text("Before your first set.")
          .hardsetText(.title)
          .foregroundStyle(Tokens.Color.chalk)
          .accessibilityAddTraits(.isHeader)
        unitsSection
        gymSection
        if let error = model.setupError {
          HardsetBanner(.error, message: error)
            .hardsetArrival()
        }
      }
      .padding(Tokens.Spacing.loose)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .scrollBounceBehavior(.basedOnSize)
    .scrollDismissesKeyboard(.interactively)
    .safeAreaInset(edge: .bottom) {
      Button("Start logging") {
        isNameFocused = false
        if model.completeSetup() { onStart() }
      }
      .buttonStyle(HardsetButtonStyle(.primary, size: .logger))
      .padding(.horizontal, Tokens.Spacing.loose)
      .padding(.vertical, Tokens.Spacing.regular)
      .background(Tokens.Color.canvas)
    }
    .task { model.loadSetup() }
  }

  // MARK: - Units

  private var unitsSection: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      Text("Units")
        .hardsetText(.sectionHeader)
        .foregroundStyle(Tokens.Color.chalkDim)
        .accessibilityAddTraits(.isHeader)
      SelectionRow(title: "Kilograms", isSelected: !useImperial) { useImperial = false }
      SelectionRow(title: "Pounds", isSelected: useImperial) { useImperial = true }
    }
  }

  // MARK: - Gym

  private var gymSection: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      Text("Gym")
        .hardsetText(.sectionHeader)
        .foregroundStyle(Tokens.Color.chalkDim)
        .accessibilityAddTraits(.isHeader)
      Text("Machines are recorded per gym. You can leave this blank and add one later.")
        .hardsetText(.caption)
        .foregroundStyle(Tokens.Color.chalkDim)
        .fixedSize(horizontal: false, vertical: true)
      if model.existingGyms.isEmpty {
        nameField
      } else {
        ForEach(model.existingGyms) { gym in
          SelectionRow(title: gym.name, isSelected: model.selectedGymID == gym.id) {
            model.selectedGymID = gym.id
          }
        }
      }
    }
  }

  private var nameField: some View {
    TextField(
      text: $model.gymName,
      prompt: Text("Where do you train?").foregroundStyle(Tokens.Color.chalkDim)
    ) {
      Text("Gym name")
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
    .hardsetEntryField(isFocused: isNameFocused)
    .onTapGesture { isNameFocused = true }
  }
}
