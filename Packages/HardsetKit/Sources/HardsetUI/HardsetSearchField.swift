import SwiftUI

/// A tactile, token-styled search field replacing generic system search chrome.
///
/// Elevated above the background with a charcoal hairline border, explicit clear button,
/// and a comfortable touch area for one-handed gym-floor operation.
public struct HardsetSearchField: View {
  @Binding private var text: String
  private let prompt: String

  public init(text: Binding<String>, prompt: String = "Search movements") {
    self._text = text
    self.prompt = prompt
  }

  public var body: some View {
    HStack(spacing: Tokens.Spacing.snug) {
      Image(systemName: "magnifyingglass")
        .font(Tokens.Text.caption.weight(.medium))
        .foregroundStyle(Tokens.Color.textSecondary)

      TextField(prompt, text: $text)
        .font(Tokens.Text.label)
        .foregroundStyle(Tokens.Color.textPrimary)
        .autocorrectionDisabled()
        #if os(iOS)
          .textInputAutocapitalization(.never)
        #endif

      if !text.isEmpty {
        Button {
          text = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(Tokens.Text.caption)
            .foregroundStyle(Tokens.Color.textSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear search")
      }
    }
    .padding(.horizontal, Tokens.Spacing.regular)
    .frame(height: 48)
    .background(Tokens.Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Tokens.Radius.control))
    .overlay(
      RoundedRectangle(cornerRadius: Tokens.Radius.control)
        .strokeBorder(Tokens.Color.border, lineWidth: Tokens.Stroke.hairline)
    )
  }
}

#if DEBUG
  #Preview("Search Field") {
    struct Harness: View {
      @State private var query = "Bench"
      var body: some View {
        VStack {
          HardsetSearchField(text: $query)
        }
        .padding()
        .background(Tokens.Color.background)
      }
    }
    return Harness()
  }
#endif
