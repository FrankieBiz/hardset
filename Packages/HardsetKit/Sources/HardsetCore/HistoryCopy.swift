import Foundation

/// The words History says while it is being searched, held apart from any view so they are tested
/// without one and the screen cannot say something the search did not do.
///
/// Search looks at three kinds of name, movement, machine and gym, and says so. It never says a
/// workout was not found when the truth is that nothing was searched, and "no match" is an answer
/// with its own message rather than a blank screen.
public enum HistoryCopy {
  public static let searchPrompt = "Search movement, machine or gym"

  /// Under the header while a search is showing: how many workouts matched, and when the list is a
  /// page of them, how many of the matches are shown. "Latest 50 of 120 workouts match “bench”".
  public static func searchSubtitle(query: String, shown: Int, total: Int) -> String {
    let words = "“\(query)”"
    if total == 1 { return "1 workout matches \(words)" }
    if shown < total { return "Latest \(shown) of \(total) workouts match \(words)" }
    return "\(total) workouts match \(words), newest first"
  }

  public static func noMatchTitle(for query: String) -> String {
    "No workouts match “\(query)”"
  }

  public static let noMatchDetail =
    "Search reads movement, machine and gym names. Try fewer or different words."

  public static let searching = "Searching your history…"

  public static let searchFailedTitle = "Could not search your history"
  public static let searchFailedDetail = "Your logged sets are safe. Try again."

  public static let showOlderMatches = "Show older matches"
  public static let readingOlderMatches = "Reading older matches…"
}
