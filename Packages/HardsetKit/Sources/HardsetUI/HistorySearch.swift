import HardsetCore
import SwiftUI

/// What the History screen hands its list to make old workouts findable: the text being typed,
/// what the rows on screen currently answer, and the way back to the newest workouts.
///
/// A value rather than a set of loose parameters because the list's behaviour hangs off one fact,
/// the state, and the three of them must change together: a search that is still being read must
/// not draw "No workouts yet", and a search that found nothing must not draw "No workouts match"
/// before it has looked.
public struct HistorySearch {
  /// What the rows on screen are.
  public enum State: Equatable, Sendable {
    /// No search is showing: the rows are the whole history, newest first.
    case idle
    /// Something searchable is typed and no answer has arrived yet.
    case searching(String)
    /// The rows answer this query. There may be none, and that is an answer.
    case answered(String)
    /// The search could not be read. Nothing was removed from history.
    case failed(String)
  }

  public let text: Binding<String>
  public let state: State
  /// Draws the control that opens the month picker. `nil` hides it, while a search is showing (a
  /// search spans all of history, so there is nowhere to jump to) or when there is no history.
  public let onJumpToMonth: (() -> Void)?
  /// Draws "Back to latest workouts". `nil` when the list already starts at the newest.
  public let onBackToLatest: (() -> Void)?

  public init(
    text: Binding<String>,
    state: State,
    onJumpToMonth: (() -> Void)? = nil,
    onBackToLatest: (() -> Void)? = nil
  ) {
    self.text = text
    self.state = state
    self.onJumpToMonth = onJumpToMonth
    self.onBackToLatest = onBackToLatest
  }
}

/// The search field and, beside it, the control that jumps to a month, with the way back to the
/// newest workouts under them when the list does not start there.
///
/// The field is the app's own `HardsetSearchField`, so it has the outline an input keeps in every
/// setting, a 44 pt clear button, and focus that survives the list below it changing. The jump
/// control is a header icon button, which is capped at xxxLarge with the Large Content Viewer in
/// its place, so the row holds together at accessibility sizes without wrapping.
struct HistorySearchBar: View {
  let search: HistorySearch

  var body: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      HStack(alignment: .center, spacing: Tokens.Spacing.regular) {
        HardsetSearchField(text: search.text, prompt: HistoryCopy.searchPrompt)
        if let onJumpToMonth = search.onJumpToMonth {
          HeaderIconButton(
            systemImage: "calendar", accessibilityLabel: HistoryCopy.jumpToMonth, action: onJumpToMonth)
        }
      }
      if let onBackToLatest = search.onBackToLatest {
        Button(action: onBackToLatest) {
          Label(HistoryCopy.backToLatest, systemImage: "arrow.up.to.line")
        }
        .buttonStyle(HardsetButtonStyle(.quiet))
      }
    }
    .padding(.horizontal, Tokens.Spacing.loose)
  }
}
