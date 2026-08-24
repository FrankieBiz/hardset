import SwiftUI

/// Asks for a single name and hands it back as an argument.
///
/// This exists because the obvious version — a `TextField` inside `.alert` bound to the parent's
/// `@State` — silently did not work: the field showed the typed text, the confirm button fired, and
/// the parent read an empty string, so nothing was ever created. Whatever the precise cause, the
/// shape is the problem: the action reads state it does not own, across a presentation boundary.
///
/// Here the text is owned by this view and delivered as a parameter, so there is no cross-boundary
/// read to get wrong. It also affords what an alert cannot: the confirm button is disabled until
/// there is something to save, and the keyboard is up on appear.
public struct NameEntrySheet: View {
  private let title: String
  private let prompt: String
  private let footnote: String?
  private let confirmLabel: String
  /// Whether confirming with an empty field is meaningful.
  ///
  /// `false` for naming something that must have a name. `true` wherever clearing the text is a
  /// real action -- unnaming a workout, deleting a note -- because otherwise the only way to remove
  /// something is to leave a single space in the field.
  private let allowsEmpty: Bool
  /// Lets the field grow, for text that is a sentence rather than a label.
  private let isMultiline: Bool
  /// Presents the decimal keypad, for a field that holds a number rather than a name.
  private let isDecimal: Bool
  private let onConfirm: (String) -> Void
  private let onCancel: () -> Void

  @State private var name: String
  @FocusState private var isFocused: Bool

  /// - Parameter initialValue: What the field opens with. Empty when creating something; the
  ///   current text when editing it -- "Rename workout" opened blank and made the user retype a
  ///   name the app already knew.
  public init(
    title: String,
    prompt: String,
    footnote: String? = nil,
    confirmLabel: String = "Add",
    initialValue: String = "",
    allowsEmpty: Bool = false,
    isMultiline: Bool = false,
    isDecimal: Bool = false,
    onConfirm: @escaping (String) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.title = title
    self.prompt = prompt
    self.footnote = footnote
    self.confirmLabel = confirmLabel
    self.allowsEmpty = allowsEmpty
    self.isMultiline = isMultiline
    self.isDecimal = isDecimal
    self.onConfirm = onConfirm
    self.onCancel = onCancel
    self._name = State(initialValue: initialValue)
  }

  private var trimmed: String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField(prompt, text: $name, axis: isMultiline ? .vertical : .horizontal)
            .focused($isFocused)
            // A multiline field needs Return to insert a line, so it cannot also submit.
            .submitLabel(isMultiline ? .return : .done)
            .onSubmit { if !isMultiline { confirm() } }
            .lineLimit(isMultiline ? 3...8 : 1...1)
            // Guarded because this module builds for the host too, so the suite can run
            // there, and `keyboardType` does not exist on macOS.
            #if os(iOS)
              .keyboardType(isDecimal ? .decimalPad : .default)
              // Autocorrect follows what the field holds, inferred from `isMultiline`: a single line
              // here is always a *name* -- a machine, a gym, a workout -- and names are proper nouns,
              // which is exactly what autocorrect rewrites. "Panatta" became "Panama" in the sibling
              // sheet. A multiline field is prose, where autocorrect is wanted and capitalising every
              // word would be wrong.
              .autocorrectionDisabled(!isMultiline)
              .textInputAutocapitalization(isMultiline ? .sentences : .words)
            #endif
        } footer: {
          if let footnote {
            Text(footnote)
          }
        }
      }
      .navigationTitle(title)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: onCancel)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(confirmLabel, action: confirm)
            // Nothing to save is not an error worth explaining; the button simply waits. Unless
            // clearing is itself the point, in which case an empty field is a valid thing to save.
            .disabled(trimmed.isEmpty && !allowsEmpty)
        }
      }
      .onAppear { isFocused = true }
    }
    .presentationDetents([.medium])
  }

  private func confirm() {
    guard allowsEmpty || !trimmed.isEmpty else { return }
    onConfirm(trimmed)
  }
}

#if DEBUG
  #Preview("Name entry") {
    NameEntrySheet(
      title: "Add a machine",
      prompt: "Name or brand",
      footnote: "Whatever you'd recognise it by.",
      onConfirm: { _ in },
      onCancel: {}
    )
  }
#endif
