import HardsetCore
import SwiftUI

/// Defining a movement the catalogue does not have.
///
/// Three fields, and the muscle is required. That requirement is the whole reason this sheet is not
/// just a name box: a movement with no attribution is counted but not attributed, so its sets land
/// in `unattributedHardSets`, the week becomes a lower bound, and every per-muscle figure grows a
/// "≥". One muscle turns that into a real credit. Only one is asked for, because the lifter is
/// standing in a gym and the app has no basis for guessing the rest.
///
/// Equipment is optional and genuinely so: it decides how a set reads back ("Body" rather than
/// "0 kg") and the step the keypad's ± offers, and none of that is worth blocking on.
public struct NewExerciseSheet: View {
  private let initialName: String
  private let onCreate: (String, ExerciseModality?, Muscle) -> Void
  private let onCancel: () -> Void

  @State private var name: String
  @State private var muscle: Muscle = .chest
  @State private var modality: ExerciseModality?
  @FocusState private var isNameFocused: Bool

  /// - Parameter initialName: Prefilled from the search that found nothing, so a lifter who typed a
  ///   name and got no results does not type it a second time.
  public init(
    initialName: String = "",
    onCreate: @escaping (String, ExerciseModality?, Muscle) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.initialName = initialName
    self.onCreate = onCreate
    self.onCancel = onCancel
    self._name = State(initialValue: initialName)
  }

  private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

  public var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Name", text: $name)
            .focused($isNameFocused)
            .submitLabel(.done)
            // Autocorrect off, and this is not a preference. Almost everything typed here is a
            // proper noun -- Panatta, Hammer Strength, Cybex, Nautilus -- which is precisely what
            // autocorrect rewrites. Typing "Panatta chest press" produced "Panama chest press",
            // and the lifter would then be searching for a machine under a name they did not
            // choose. Capitalised by word because these are names.
            .autocorrectionDisabled()
            // Guarded: this module builds for the host too, so the suite can run there, and
            // `textInputAutocapitalization` does not exist on macOS.
            #if os(iOS)
              .textInputAutocapitalization(.words)
            #endif
        } header: {
          Text("Movement")
        } footer: {
          Text("Whatever you would recognise it by \u{2014} the brand, the machine, your own name for it.")
        }

        Section {
          Picker("Trains", selection: $muscle) {
            ForEach(Muscle.allCases, id: \.self) { option in
              Text(ExercisePickerView.displayName(MuscleKey(option))).tag(option)
            }
          }
        } header: {
          Text("Muscle")
        } footer: {
          // Says why it is being asked, because a required field with no reason reads as a form for
          // the app's benefit rather than the lifter's.
          Text(
            "Required, so these sets count toward that muscle's week. Without it they would be "
              + "counted but unattributed, and every figure in your report would become a minimum."
          )
        }

        Section {
          Picker("Loaded by", selection: $modality) {
            Text("Not sure").tag(ExerciseModality?.none)
            ForEach(ExerciseModality.allCases, id: \.self) { option in
              Text(option.label).tag(ExerciseModality?.some(option))
            }
          }
        } header: {
          Text("Equipment")
        } footer: {
          Text(
            "Optional. It decides whether a set reads back as \u{201C}Body\u{201D} rather than zero, "
              + "and the step the +/- buttons offer."
          )
        }
      }
      .navigationTitle("Your own movement")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: onCancel)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Add") { onCreate(trimmed, modality, muscle) }
            // Nothing to save is not an error worth explaining; the button waits.
            .disabled(trimmed.isEmpty)
        }
      }
      // Focused only when there is nothing to start from. Arriving with a name already filled in and
      // the keyboard up hides the two fields that are the actual reason for this screen.
      .onAppear { isNameFocused = initialName.isEmpty }
    }
  }
}

#if DEBUG
  #Preview("New exercise") {
    NewExerciseSheet(initialName: "Panatta chest press", onCreate: { _, _, _ in }, onCancel: {})
  }
#endif
