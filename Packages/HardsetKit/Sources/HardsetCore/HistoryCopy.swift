import Foundation

/// The words History says while it is being searched, held apart from any view so they are tested
/// without one and the screen cannot say something the search did not do.
///
/// Search looks at three kinds of name, movement, machine and gym, and says so. It never says a
/// workout was not found when the truth is that nothing was searched, and "no match" is an answer
/// with its own message rather than a blank screen.
public enum HistoryCopy {
  /// What the field shows while it is empty: short enough to be read whole in a single-line field
  /// beside the month button at the default size. The longer "Search movement, machine or gym" was
  /// clipped after "machine".
  public static let searchPrompt = "Movement, machine or gym"

  /// What the field shows at a size too large for `searchPrompt` to fit on one line. The scopes are
  /// then said by `searchScopes`, wrapped, on a line of their own.
  public static let searchPromptCompact = "Search"

  /// The accessible name of the search field, whatever its placeholder shows.
  public static let searchLabel = "Search workouts"

  /// What search reads, in full. It is the field's accessibility hint at every size, and at
  /// accessibility sizes also a visible line under the field, which wraps where a placeholder
  /// cannot.
  public static let searchScopes = "Searches movement, machine and gym names."

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

  // MARK: - Jumping to a month

  public static let jumpToMonth = "Jump to a month"
  public static let backToLatest = "Back to latest workouts"
  public static let monthSheetLoading = "Reading your months…"
  public static let monthSheetFailedTitle = "Could not read your months"
  public static let monthSheetFailedDetail = "Your logged sets are safe. Close this and try again."
  public static let monthSheetEmptyTitle = "No workouts yet"
  public static let monthSheetEmptyDetail = "Finished workouts appear here, month by month."

  /// "14 workouts", for a month's row.
  public static func workoutCount(_ count: Int) -> String {
    count == 1 ? "1 workout" : "\(count) workouts"
  }

  /// Under the header when the list starts at a chosen month: where it starts, and how many of the
  /// workouts from there back are shown. It says "and earlier" because newer workouts are not on
  /// this list, and the lifter must not read it as the whole history.
  public static func anchoredSubtitle(month: String, shown: Int, total: Int) -> String {
    if total == 1 { return "1 workout from \(month) and earlier" }
    if shown < total { return "Showing \(shown) of \(total) workouts from \(month) and earlier" }
    return "\(total) workouts from \(month) and earlier, newest first"
  }
}
