import Foundation

/// Finds movements by the names lifters actually type at the rack.
///
/// A literal substring over the catalogue name missed most of them: "pull up" is not in
/// "Pull-up", "squats" is not in "Barbell Back Squat", and "ohp" is nowhere. The picker then said
/// nothing in the catalogue matched, which was false. This search stays exact rather than fuzzy:
/// it folds spelling that does not change meaning (case, diacritics, hyphens, spacing, plurals),
/// expands a short curated list of gym abbreviations, and otherwise requires every typed word to
/// begin a word of the name or of a curated alias. Nothing is guessed from edit distance, because
/// a near miss that surfaces the wrong movement is worse than an honest "nothing matches".
///
/// Hand-written and kept apart from `ExerciseCatalog.swift`, so the alias data and the matching
/// rules can change without touching the catalogue.
public enum CatalogSearch {
  /// Names and abbreviations for curated movements, keyed by catalogue slug. Each alias names the
  /// same movement, never a neighbour: "shoulder press" is listed for the two shoulder presses
  /// and nothing else.
  public static let aliases: [String: [String]] = [
    "barbell-back-squat": ["squat", "back squat"],
    "romanian-deadlift": ["rdl"],
    "conventional-deadlift": ["deadlift"],
    "seated-leg-curl": ["hamstring curl", "ham curl"],
    "lying-leg-curl": ["hamstring curl", "ham curl", "prone leg curl"],
    "leg-extension": ["quad extension"],
    "bulgarian-split-squat": ["bss", "split squat"],
    "standing-calf-raise": ["calves", "calf raise"],
    "seated-calf-raise": ["calves", "calf raise"],
    "barbell-bench-press": ["bench", "bench press", "flat bench"],
    "chest-press-machine": ["machine chest press", "chest press machine"],
    "pec-deck": ["pec fly", "machine fly", "butterfly"],
    "cable-fly": ["chest fly", "cable crossover", "crossover"],
    "dip": ["chest dip", "parallel bar dip"],
    "pull-up": ["pullup"],
    "chin-up": ["chinup"],
    "lat-pulldown": ["pulldown"],
    "seated-cable-row": ["cable row", "low row"],
    "barbell-row": ["bent over row", "bent over barbell row"],
    "single-arm-dumbbell-row": ["one arm row", "one arm dumbbell row", "dumbbell row"],
    "overhead-press": ["ohp", "shoulder press", "military press", "standing press"],
    "seated-dumbbell-press": ["shoulder press", "dumbbell shoulder press"],
    "lateral-raise": ["side raise", "side lateral raise", "lat raise"],
    "cable-lateral-raise": ["cable side raise"],
    "reverse-pec-deck": ["rear delt fly", "reverse fly"],
    "barbell-curl": ["bicep curl"],
    "dumbbell-curl": ["bicep curl"],
    "cable-triceps-pushdown": ["pushdown", "tricep pushdown", "pressdown", "rope pushdown"],
    "overhead-cable-extension": ["overhead tricep extension"],
    "skull-crusher": ["skullcrusher", "lying tricep extension"],
    "close-grip-bench-press": ["close grip bench"],
    "shrug": ["trap shrug"],
    "hanging-leg-raise": ["leg raise"],
    "back-extension": ["hyperextension", "hyper"],
    "wrist-curl": ["forearm curl"],
  ]

  /// Gym shorthand for a whole word, expanded before matching.
  public static let abbreviations: [String: String] = [
    "db": "dumbbell",
    "dbs": "dumbbell",
    "bb": "barbell",
  ]

  /// Matches for `query`, best first; an empty query returns `entries` unchanged.
  ///
  /// Tiers, each keeping the incoming order: the whole query equals the name or an alias; every
  /// word begins a word of the name; every word begins a word of an alias; and finally the old
  /// literal substring of the name, so no earlier hit is lost.
  public static func rank(_ entries: [CatalogEntry], query: String) -> [CatalogEntry] {
    let words = queryWords(query)
    guard !words.isEmpty else { return entries }
    let literal = query.trimmingCharacters(in: .whitespacesAndNewlines)
    var tiers: [[CatalogEntry]] = [[], [], [], []]
    for entry in entries {
      let name = phraseWords(entry.name)
      let aliasPhrases = (entry.slug.flatMap { aliases[$0] } ?? []).map(phraseWords)
      if name == words || aliasPhrases.contains(words) {
        tiers[0].append(entry)
      } else if matches(words, name) {
        tiers[1].append(entry)
      } else if aliasPhrases.contains(where: { matches(words, $0) }) {
        tiers[2].append(entry)
      } else if entry.name.range(of: literal, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
        tiers[3].append(entry)
      }
    }
    return tiers.flatMap { $0 }
  }

  /// True when every query word begins some word of the phrase, or the query with its spaces
  /// removed begins the phrase at one of its word starts ("pullup", "lat pull down").
  static func matches(_ query: [String], _ phrase: [String]) -> Bool {
    guard !query.isEmpty, !phrase.isEmpty else { return false }
    if query.allSatisfy({ word in phrase.contains { $0.hasPrefix(word) } }) { return true }
    let joined = query.joined()
    return phrase.indices.contains { phrase[$0...].joined().hasPrefix(joined) }
  }

  /// A typed query as comparable words, with abbreviations expanded.
  static func queryWords(_ text: String) -> [String] {
    phraseWords(text).map { abbreviations[$0].map(stem) ?? $0 }
  }

  /// Case and diacritics folded, anything but letters and digits treated as a space, and each
  /// word reduced to its singular so "squats" meets "squat" and "presses" meets "press".
  static func phraseWords(_ text: String) -> [String] {
    text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
      .split { !$0.isLetter && !$0.isNumber }
      .map { stem(String($0)) }
  }

  /// A plural reduced to its singular, applied identically to names and queries, so a mismatch
  /// in the rule cannot hide a movement. Two-letter words are left alone; "ups" becomes "up".
  static func stem(_ word: String) -> String {
    guard word.count > 2 else { return word }
    for (suffix, replacement) in [("ies", "y"), ("sses", "ss"), ("ches", "ch"), ("shes", "sh"), ("yes", "y")]
    where word.hasSuffix(suffix) {
      return String(word.dropLast(suffix.count)) + replacement
    }
    if word.hasSuffix("ss") || word.hasSuffix("us") { return word }
    if word.hasSuffix("s") { return String(word.dropLast()) }
    return word
  }
}
