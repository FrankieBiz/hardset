import HardsetCore
import SwiftUI

/// Everything the sheet collected, as one value.
///
/// A struct rather than a fourth closure parameter: the call sites already pass three, and a
/// `(String, ExerciseModality?, Muscle, [MuscleContribution]) -> Void` is a signature nobody can
/// read at the call site without counting.
public struct NewExerciseDraft: Hashable, Sendable {
  public let name: String
  public let modality: ExerciseModality?
  public let primaryMuscle: Muscle
  /// The template's contributions the lifter left switched on. Empty when they described the
  /// movement from scratch. Still carries curated provenance at this point — the store rewrites it,
  /// deliberately, so no caller can skip that step.
  public let inheriting: [MuscleContribution]

  public init(
    name: String,
    modality: ExerciseModality?,
    primaryMuscle: Muscle,
    inheriting: [MuscleContribution] = []
  ) {
    self.name = name
    self.modality = modality
    self.primaryMuscle = primaryMuscle
    self.inheriting = inheriting
  }
}

/// Defining a movement the catalogue does not have.
///
/// The muscle is required. That requirement is the whole reason this sheet is not just a name box:
/// a movement with no attribution is counted but not attributed, so its sets land in
/// `unattributedHardSets`, the week becomes a lower bound, and every per-muscle figure grows a "≥".
/// One muscle turns that into a real credit.
///
/// # Why "Based on" exists
///
/// One muscle is also all a hand-typed movement ever credited, and that is its own quiet
/// under-count: `Nautilus High Lever Row` credited lats while the `Chest Supported Row` it is
/// obviously a variant of credits rear delts, upper back and biceps too. Naming a template carries
/// those over.
///
/// # Why they are shown, and switchable
///
/// Inheriting silently would mint up to eight per-muscle arithmetic facts the lifter never saw —
/// strictly worse than the single honest guess it replaced, because the single guess *under*-claims
/// and a silent copy over-claims. So every inherited muscle is a row here, on by default and
/// switchable off, and what gets written is what they left on. The provenance swap the store
/// performs is invisible and cannot be endorsed; this is the part they can actually see.
///
/// Equipment is optional and genuinely so: it decides how a set reads back ("Body" rather than
/// "0 kg") and the step the keypad's ± offers, and none of that is worth blocking on.
public struct NewExerciseSheet: View {
  private let initialName: String
  /// Movements offerable as a template. Curated only, chosen by the caller: a template exists to
  /// carry a *researched* attribution across, and inheriting from another hand-typed row would
  /// copy one person's guess twice while looking like corroboration.
  private let templates: [CatalogEntry]
  private let onCreate: (NewExerciseDraft) -> Void
  private let onCancel: () -> Void

  @State private var name: String
  @State private var muscle: Muscle = .chest
  @State private var modality: ExerciseModality?
  @State private var templateID: ExerciseID?
  /// Muscles the lifter switched off. Tracked as the exclusions rather than the inclusions so that
  /// changing template starts everything on again without a second bookkeeping step.
  @State private var excluded: Set<MuscleKey> = []
  @FocusState private var isNameFocused: Bool

  /// - Parameter initialName: Prefilled from the search that found nothing, so a lifter who typed a
  ///   name and got no results does not type it a second time.
  public init(
    initialName: String = "",
    templates: [CatalogEntry] = [],
    onCreate: @escaping (NewExerciseDraft) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.initialName = initialName
    self.templates = templates
    self.onCreate = onCreate
    self.onCancel = onCancel
    self._name = State(initialValue: initialName)
  }

  private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

  private var template: CatalogEntry? {
    templateID.flatMap { id in templates.first { $0.id == id } }
  }

  /// The template's credited muscles minus the chosen primary, which has its own row above and
  /// would otherwise appear twice saying two different things.
  private var inheritable: [MuscleContribution] {
    guard let template else { return [] }
    return template.creditedMuscles.filter { $0.key != MuscleKey(muscle) }
  }

  private var kept: [MuscleContribution] {
    inheritable.filter { !excluded.contains($0.key) }
  }

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

        if !templates.isEmpty {
          Section {
            Picker("Based on", selection: $templateID) {
              Text("Nothing \u{2014} I'll describe it").tag(ExerciseID?.none)
              ForEach(templates) { entry in
                Text(entry.name).tag(ExerciseID?.some(entry.id))
              }
            }
            #if os(iOS)
              .pickerStyle(.navigationLink)
            #endif
          } header: {
            Text("Based on")
          } footer: {
            Text(
              "Optional. Pick the movement yours is a variant of and it starts with the same "
                + "muscles. It stays your movement \u{2014} a later change to the original will "
                + "not rewrite it."
            )
          }
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

        if !inheritable.isEmpty {
          Section {
            ForEach(inheritable, id: \.key) { contribution in
              inheritedRow(contribution)
            }
          } header: {
            Text("Also trains")
          } footer: {
            // States the honesty rule in the lifter's terms. The citation is dropped on the way in
            // and there is no screen that would otherwise say so.
            Text(
              "Carried over from \(template?.name ?? "the original"), and counted as your own "
                + "judgement rather than as research about your machine. Switch off anything "
                + "yours does not train."
            )
          }
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
          Button("Add") {
            onCreate(
              NewExerciseDraft(
                name: trimmed, modality: modality, primaryMuscle: muscle, inheriting: kept
              )
            )
          }
          // Nothing to save is not an error worth explaining; the button waits.
          .disabled(trimmed.isEmpty)
        }
      }
      // Choosing a template adopts its primary muscle, because the lifter picked it as "mine is a
      // variant of this" and its prime mover is the best answer available. Exclusions reset so a
      // switch flipped against the previous template does not silently apply to this one.
      .onChange(of: templateID) { _, _ in
        excluded = []
        if let adopted = template?.primaryMuscle.muscle { muscle = adopted }
      }
      // Focused only when there is nothing to start from. Arriving with a name already filled in and
      // the keyboard up hides the fields that are the actual reason for this screen.
      .onAppear { isNameFocused = initialName.isEmpty }
    }
  }

  /// One inherited muscle, on or off.
  ///
  /// A toggle rather than swipe-to-delete: removal has to be reversible and visible here, and a
  /// swipe affordance that only exists once would leave a lifter who switched one off by accident
  /// with no way back short of starting the sheet again.
  private func inheritedRow(_ contribution: MuscleContribution) -> some View {
    let isKept = !excluded.contains(contribution.key)
    return Button {
      if isKept {
        excluded.insert(contribution.key)
      } else {
        excluded.remove(contribution.key)
      }
    } label: {
      HStack {
        VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
          Text(ExercisePickerView.displayName(contribution.key))
            .foregroundStyle(Tokens.Color.textPrimary)
          Text(Self.roleLabel(contribution.role))
            .font(Tokens.Text.caption)
            .foregroundStyle(Tokens.Color.textSecondary)
        }
        Spacer(minLength: 0)
        Image(systemName: isKept ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(isKept ? Tokens.Color.accent : Tokens.Color.textSecondary)
      }
      .frame(minHeight: Tokens.minimumTapTarget)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(isKept ? [.isSelected, .isButton] : .isButton)
    .accessibilityHint(isKept ? "Double tap to stop crediting this muscle." : "Double tap to credit this muscle.")
  }

  /// Says what the role means in sets, because "indirect" is the app's word and half a set is the
  /// thing the lifter can actually check.
  static func roleLabel(_ role: MuscleRole) -> String {
    switch role {
    case .direct: "Counts a full set"
    case .indirect: "Counts half a set"
    case .stabilizer: "Counts nothing"
    }
  }
}

#if DEBUG
  #Preview("New exercise") {
    NewExerciseSheet(
      initialName: "Panatta chest press",
      templates: ExerciseCatalog.v1.compactMap(\.catalogEntry).filter(\.isCurated),
      onCreate: { _ in },
      onCancel: {}
    )
  }
#endif
