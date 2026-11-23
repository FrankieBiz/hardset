import Foundation

/// How a "Worked from" account writes loads and dates.
///
/// One value carries the lifter's unit, locale and time zone, so every derivation writes the same
/// set as the same words, and a test can pin all three and compare exact strings.
public struct WorkedFromFormat: Hashable, Sendable {
  public let unit: WeightUnit
  public let locale: Locale
  public let timeZone: TimeZone

  public init(unit: WeightUnit, locale: Locale = .current, timeZone: TimeZone = .current) {
    self.unit = unit
    self.locale = locale
    self.timeZone = timeZone
  }

  /// An entered load with its unit, at the precision it was entered with: "102.5 kg".
  public func load(_ kilograms: Double) -> String {
    "\(LoadText.entered(kilograms, in: unit, locale: locale)) \(unit.abbreviation)"
  }

  /// An estimated load with its unit, rounded the way every estimate is: "116.5 kg".
  public func estimate(_ kilograms: Double) -> String {
    "\(LoadText.estimate(kilograms, in: unit, locale: locale)) \(unit.abbreviation)"
  }

  /// A set as it is written everywhere: "100 kg × 5".
  public func set(weightKg: Double, reps: Int) -> String {
    "\(load(weightKg)) × \(reps)"
  }

  /// A count of fractional sets as the volume rows write it: "8.5", or "8" when it is whole.
  public func sets(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
  }

  /// The credit one set gives a muscle, always to one place so "1.0" and "0.5" line up: "0.5".
  public func credit(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(1)).locale(locale))
  }

  /// "Nov 4, 2026", in the lifter's own time zone, so the day named is the day it was lifted.
  public func day(_ date: Date) -> String {
    date.formatted(
      Date.FormatStyle(locale: locale, timeZone: timeZone).month(.abbreviated).day().year())
  }

  /// The unit as a word, for a sentence that is read aloud.
  public var unitSpoken: String {
    switch unit {
    case .kilograms: "kilograms"
    case .pounds: "pounds"
    }
  }

  /// A load read aloud: "102.5 kilograms".
  public func loadSpoken(_ kilograms: Double) -> String {
    "\(LoadText.entered(kilograms, in: unit, locale: locale)) \(unitSpoken)"
  }

  /// An estimate read aloud: "116.5 kilograms".
  public func estimateSpoken(_ kilograms: Double) -> String {
    "\(LoadText.estimate(kilograms, in: unit, locale: locale)) \(unitSpoken)"
  }

  /// A set read aloud: "100 kilograms for 5 reps".
  public func setSpoken(weightKg: Double, reps: Int) -> String {
    "\(loadSpoken(weightKg)) for \(reps) \(reps == 1 ? "rep" : "reps")"
  }
}

/// An answer to "which sets produced this number, by what arithmetic, and what was left out".
///
/// Each surface derives its own account in Core, from the same inputs and through the same
/// functions its number came from, and this is the one shape they all return. A view renders it and
/// does no arithmetic of its own, so the explanation cannot drift from the figure it explains, and a
/// test can pin both without a screen.
///
/// A set that did not contribute is a line in the section for what was left out, with its reason.
/// Silent absence is how an explanation turns into a plausible fiction.
public struct WorkedFromAccount: Hashable, Sendable {
  /// Where a line stands against the figure. Carried by a word and a symbol on screen, never by
  /// colour alone.
  public enum Standing: String, Hashable, Sendable {
    /// Produced the figure.
    case produced
    /// Took part and did not decide the figure.
    case counted
    /// Was left out, for the reason the line states.
    case excluded
  }

  public struct Line: Hashable, Sendable, Identifiable {
    public let id: String
    public let standing: Standing
    /// The thing itself, in figures: "100 kg × 5", or a movement's name.
    public let headline: String
    /// Where and when, in `provenance`: "Nov 4, 2026 · Hammer Strength".
    public let context: String?
    /// The arithmetic or the reason, as one or two short sentences.
    public let detail: String
    /// The whole line as a sentence, for VoiceOver.
    public let spoken: String
    /// The words that say where the line stands, when the surface has better ones than the shared
    /// "Produced the figure", "Counted" and "Left out": a record's set "Set the record".
    public let standingWord: String?

    public init(
      id: String, standing: Standing, headline: String, context: String? = nil,
      detail: String, spoken: String, standingWord: String? = nil
    ) {
      self.id = id
      self.standing = standing
      self.headline = headline
      self.context = context
      self.detail = detail
      self.spoken = spoken
      self.standingWord = standingWord
    }
  }

  public struct Section: Hashable, Sendable, Identifiable {
    public let id: String
    public let heading: String
    /// What the section is about, in a sentence, said even when it has no lines.
    public let note: String?
    public let lines: [Line]

    public init(id: String, heading: String, note: String? = nil, lines: [Line]) {
      self.id = id
      self.heading = heading
      self.note = note
      self.lines = lines
    }
  }

  /// What is being explained: "Estimated one-rep max".
  public let title: String
  /// The figure itself, as the screen shows it: "116.5 kg", or "No estimate".
  public let figure: String
  /// What qualifies the figure: how far to trust it, and where it is from.
  public let figureCaption: String
  /// The heading over the rule, naming what kind of rule it is: "Formula", "Credit", "Rule".
  public let ruleHeading: String
  /// The arithmetic or the rule, stated in full.
  public let rule: String
  public let sections: [Section]
  /// The whole account as a sentence or two, for VoiceOver.
  public let spoken: String

  public init(
    title: String, figure: String, figureCaption: String, ruleHeading: String, rule: String,
    sections: [Section], spoken: String
  ) {
    self.title = title
    self.figure = figure
    self.figureCaption = figureCaption
    self.ruleHeading = ruleHeading
    self.rule = rule
    self.sections = sections
    self.spoken = spoken
  }
}
