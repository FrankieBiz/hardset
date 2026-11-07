import SwiftUI

/// A tactile, token-styled search field replacing generic system search chrome.
///
/// Raised above the background with a measured control border, so it reads as a field before
/// anything is typed into it, and a 2 pt accent ring while it has focus. The clear button has the
/// full 44 pt hit area, and the whole field focuses on tap, for one-handed gym-floor operation.
public struct HardsetSearchField: View {
  @Binding private var text: String
  private let prompt: String

  @FocusState private var isFocused: Bool

  public init(text: Binding<String>, prompt: String = "Search movements") {
    self._text = text
    self.prompt = prompt
  }

  public var body: some View {
    HStack(spacing: Tokens.Spacing.snug) {
      Image(systemName: "magnifyingglass")
        .font(Tokens.Text.labelEmphasis)
        .foregroundStyle(isFocused ? Tokens.Color.accent : Tokens.Color.textSecondary)
        .accessibilityHidden(true)

      // The prompt is drawn in `textSecondary` rather than the system placeholder grey, which is
      // not measured against these surfaces.
      TextField(text: $text, prompt: Text(prompt).foregroundStyle(Tokens.Color.textSecondary)) {
        Text(prompt)
      }
      .font(Tokens.Text.label)
      .foregroundStyle(Tokens.Color.textPrimary)
      .tint(Tokens.Color.accent)
      .focused($isFocused)
      .submitLabel(.search)
      .autocorrectionDisabled()
      #if os(iOS)
        .textInputAutocapitalization(.never)
      #endif

      if !text.isEmpty {
        Button {
          text = ""
          isFocused = true
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(Tokens.Text.headline)
            .foregroundStyle(Tokens.Color.textSecondary)
            // Inside the label, so the visible symbol stays small and the hit area is 44 pt.
            .frame(minWidth: Tokens.minimumTapTarget, minHeight: Tokens.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear search")
      }
    }
    .frame(minHeight: Tokens.minimumTapTarget)
    .padding(.leading, Tokens.Spacing.regular)
    // The clear button's own 44 pt square supplies the trailing room when it is showing.
    .padding(.trailing, text.isEmpty ? Tokens.Spacing.regular : Tokens.Spacing.tight)
    .padding(.vertical, Tokens.Spacing.tight)
    .entryFieldChrome(isFocused: isFocused)
    .onTapGesture { isFocused = true }
  }
}

// MARK: - Field chrome

extension View {
  /// The outline every text entry field in the app wears: a raised fill, the measured control
  /// border, and a 2 pt accent ring on top while the field has focus.
  ///
  /// Internal so the search field and `NameEntrySheet` cannot drift apart. The ring fades in on
  /// `Motion.state` -- only its opacity changes, so nothing reflows -- and appears instantly with
  /// Reduce Motion on.
  func entryFieldChrome(isFocused: Bool) -> some View {
    modifier(EntryFieldChrome(isFocused: isFocused))
  }
}

private struct EntryFieldChrome: ViewModifier {
  let isFocused: Bool

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: Tokens.Radius.control)
    return content
      .background(Tokens.Color.surfaceRaised, in: shape)
      .overlay(shape.strokeBorder(Tokens.Color.controlBorder, lineWidth: Tokens.Stroke.hairline))
      .overlay(
        shape
          .strokeBorder(Tokens.Color.accent, lineWidth: Tokens.Stroke.selected)
          .opacity(isFocused ? 1 : 0)
          .animation(
            Tokens.Motion.adaptive(Tokens.Motion.state, reduceMotion: reduceMotion),
            value: isFocused
          )
      )
      // The padding around the text is part of the field: a tap anywhere inside the outline
      // should land, not only a tap on the line of text.
      .contentShape(shape)
  }
}

#if DEBUG
  private struct SearchFieldHarness: View {
    @State private var empty = ""
    @State private var filled = "Bench"

    var body: some View {
      VStack(spacing: Tokens.Spacing.loose) {
        HardsetSearchField(text: $empty)
        HardsetSearchField(text: $filled, prompt: "Search gyms")
      }
      .padding(Tokens.Spacing.loose)
      .frame(maxHeight: .infinity, alignment: .top)
      .background(Tokens.Color.background)
    }
  }

  #Preview("Search field") {
    SearchFieldHarness()
  }
#endif
