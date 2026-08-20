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
  private let onConfirm: (String) -> Void
  private let onCancel: () -> Void

  @State private var name = ""
  @FocusState private var isFocused: Bool

  public init(
    title: String,
    prompt: String,
    footnote: String? = nil,
    confirmLabel: String = "Add",
    onConfirm: @escaping (String) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.title = title
    self.prompt = prompt
    self.footnote = footnote
    self.confirmLabel = confirmLabel
    self.onConfirm = onConfirm
    self.onCancel = onCancel
  }

  private var trimmed: String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField(prompt, text: $name)
            .focused($isFocused)
            .submitLabel(.done)
            .onSubmit(confirm)
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
            // Nothing to save is not an error worth explaining; the button simply waits.
            .disabled(trimmed.isEmpty)
        }
      }
      .onAppear { isFocused = true }
    }
    .presentationDetents([.medium])
  }

  private func confirm() {
    guard !trimmed.isEmpty else { return }
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
