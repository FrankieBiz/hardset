import SwiftUI

/// A tactile, token-styled search field replacing generic system search chrome.
///
/// Raised above the canvas with a measured control edge, so it reads as a field before anything is
/// typed into it, and a 2 pt plate blue ring while it has focus. The clear button has the full
/// 44 pt hit area, and the whole field focuses on tap, for one-handed gym-floor operation.
public struct HardsetSearchField: View {
  @Binding private var text: String
  private let prompt: String
  private let requestsFocus: Bool

  @FocusState private var isFocused: Bool

  /// - Parameter requestsFocus: Focuses the field, raising the keyboard, whenever this becomes
  ///   true, including on first appearance. A screen whose answer is usually typed passes true;
  ///   one that is browsed first leaves it false, so the keyboard does not cover the list.
  public init(
    text: Binding<String>, prompt: String = "Search movements", requestsFocus: Bool = false
  ) {
    self._text = text
    self.prompt = prompt
    self.requestsFocus = requestsFocus
  }

  public var body: some View {
    HStack(spacing: Tokens.Spacing.snug) {
      Image(systemName: "magnifyingglass")
        .font(Tokens.Text.headline)
        .foregroundStyle(isFocused ? Tokens.Color.plateBlue : Tokens.Color.chalkDim)
        .accessibilityHidden(true)

      // The prompt is drawn in `chalkDim` rather than the system placeholder grey, which is
      // not measured against these surfaces.
      TextField(text: $text, prompt: Text(prompt).foregroundStyle(Tokens.Color.chalkDim)) {
        Text(prompt)
      }
      .font(Tokens.Text.label)
      .foregroundStyle(Tokens.Color.chalk)
      .tint(Tokens.Color.plateBlue)
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
            .foregroundStyle(Tokens.Color.chalkDim)
            // Inside the label, so the visible symbol stays small and the hit area is 44 pt.
            .frame(minWidth: Tokens.minimumTapTarget, minHeight: Tokens.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(HardsetPressStyle())
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
    .onChange(of: requestsFocus, initial: true) { _, requested in
      if requested { isFocused = true }
    }
  }
}

// MARK: - Field chrome

extension View {
  /// The outline every text entry field in the app wears: a raised fill that steps off its
  /// surface, the measured control edge, and a 2 pt plate blue ring on top while the field has
  /// focus. An input keeps its outline in every setting, because it is identified by its box, and
  /// it is the one control whose outline the affordance rule does not wait to be asked for.
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
    let shape = Tokens.Shape.control
    return content
      .modifier(ControlFaceModifier(shape: shape, isPressed: false, outline: .always))
      .overlay(
        shape
          .strokeBorder(Tokens.Color.plateBlue, lineWidth: Tokens.Stroke.selected)
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
      .background(Tokens.Color.canvas)
    }
  }

  #Preview("Search field") {
    SearchFieldHarness()
  }
#endif
