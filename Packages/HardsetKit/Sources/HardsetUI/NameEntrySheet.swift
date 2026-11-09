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
///
/// Laid out by hand rather than as a stock `Form`: one field in the same outline as the search
/// field, the note under it, and the confirm action as a full-width 56 pt button in the content,
/// where a thumb reaches it, instead of a small word in the navigation bar.
///
/// When saving fails, the caller keeps the sheet up and passes the reason in: it appears above the
/// field, and the name typed is still in it, so trying again is one tap rather than a retype.
public struct NameEntrySheet: View {
  private let title: String
  private let prompt: String
  private let footnote: String?
  private let confirmLabel: String
  private let errorMessage: String?
  private let onConfirm: (String) -> Void
  private let onCancel: () -> Void

  @State private var name = ""
  @FocusState private var isFocused: Bool

  public init(
    title: String,
    prompt: String,
    footnote: String? = nil,
    confirmLabel: String = "Add",
    errorMessage: String? = nil,
    onConfirm: @escaping (String) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.title = title
    self.prompt = prompt
    self.footnote = footnote
    self.confirmLabel = confirmLabel
    self.errorMessage = errorMessage
    self.onConfirm = onConfirm
    self.onCancel = onCancel
  }

  private var trimmed: String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: Tokens.Spacing.loose) {
          if let errorMessage, !errorMessage.isEmpty {
            HardsetBanner(.error, message: errorMessage)
          }

          VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
            nameField

            if let footnote, !footnote.isEmpty {
              Text(footnote)
                .font(Tokens.Text.caption)
                .foregroundStyle(Tokens.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
          }

          Button(action: confirm) {
            Text(confirmLabel)
          }
          .buttonStyle(HardsetButtonStyle(.primary, size: .logger))
          // Nothing to save is not an error worth explaining; the button simply waits.
          .disabled(trimmed.isEmpty)
        }
        .padding(.horizontal, Tokens.Spacing.loose)
        .padding(.top, Tokens.Spacing.loose)
        .padding(.bottom, Tokens.Spacing.section)
      }
      .scrollBounceBehavior(.basedOnSize)
      .background(Tokens.Color.background)
      .hardsetNavigationTitle(title)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: onCancel)
        }
      }
      .onAppear { isFocused = true }
      // The sheet staying up is the only other sign that saving failed, so VoiceOver says why.
      .onChange(of: errorMessage) { _, message in
        guard let message, !message.isEmpty else { return }
        AccessibilityNotification.Announcement(message).post()
      }
    }
    .presentationDetents([.medium])
  }

  private var nameField: some View {
    TextField(text: $name, prompt: Text(prompt).foregroundStyle(Tokens.Color.textSecondary)) {
      Text(prompt)
    }
    .font(Tokens.Text.label)
    .foregroundStyle(Tokens.Color.textPrimary)
    .tint(Tokens.Color.accent)
    .focused($isFocused)
    .submitLabel(.done)
    .onSubmit(confirm)
    .padding(.horizontal, Tokens.Spacing.regular)
    .padding(.vertical, Tokens.Spacing.snug)
    .frame(maxWidth: .infinity, minHeight: Tokens.loggerTapTarget, alignment: .leading)
    .entryFieldChrome(isFocused: isFocused)
    .onTapGesture { isFocused = true }
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
    .hardsetSheet()
  }

  #Preview("Name entry, save failed") {
    NameEntrySheet(
      title: "Add a gym",
      prompt: "Name",
      footnote: "Machines are recorded per gym, so this is what groups them.",
      errorMessage: "“Iron Temple” could not be saved. Try again.",
      onConfirm: { _ in },
      onCancel: {}
    )
    .hardsetSheet()
  }

  #Preview("Name entry, no footnote") {
    NameEntrySheet(
      title: "Add a gym",
      prompt: "Name",
      onConfirm: { _ in },
      onCancel: {}
    )
    .hardsetSheet()
  }
#endif
