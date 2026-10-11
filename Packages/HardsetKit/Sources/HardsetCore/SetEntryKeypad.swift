import Foundation

/// The logger's keypad, as a value: two fields, which one is focused, and what each key does.
///
/// It lives here, not in a view, because every rule in it is a way the number on screen and the
/// number saved could part company, and those rules have to be tested where a compiler can run
/// them. The view renders `weight`, `reps` and `composedText`, and writes `draft` back.
public struct SetEntryKeypad: Hashable, Sendable {
  public enum Field: Hashable, Sendable { case weight, reps }
  public enum Direction: Hashable, Sendable { case down, up }

  public private(set) var weight: NumericEntryBuffer
  public private(set) var reps: NumericEntryBuffer
  public private(set) var field: Field
  public let unit: WeightUnit
  public let loadStep: LoadStep

  private let base: SetEntryDraft
  private var weightEdited = false
  private var repsEdited = false

  public init(
    draft: SetEntryDraft, unit: WeightUnit, machineIncrementKg: Double?, field: Field = .weight
  ) {
    self.base = draft
    self.unit = unit
    self.loadStep = LoadStep(machineIncrementKg: machineIncrementKg, unit: unit)
    self.weight = Self.weightBuffer(draft.weightKg.map(unit.fromKilograms))
    self.reps = Self.repsBuffer(draft.reps.map(Double.init))
    self.field = field
  }

  public var focused: NumericEntryBuffer { field == .weight ? weight : reps }

  public mutating func type(digit: Int) { edit { $0.append(digit: digit) } }
  public mutating func typeDecimalSeparator() { edit { $0.appendDecimalSeparator() } }
  public mutating func deleteBackward() { edit { $0.deleteBackward() } }
  /// Empties the focused field only. The draft then has no value there, not zero.
  public mutating func clear() { edit { $0.clear() } }

  /// ± on the focused field: `loadStep` for weight, one rep for reps. Refused, leaving everything
  /// as it was, when there is no value to move or the result would not be a valid entry.
  public mutating func step(_ direction: Direction) {
    let steps = direction == .up ? 1 : -1
    switch field {
    case .weight:
      // Four integer digits is what the field displays; a step past it would show a number the
      // keypad itself could never have produced.
      guard let moved = loadStep.moved(weight.value, by: steps), moved < 10_000 else { return }
      weight = Self.weightBuffer(moved)
      weightEdited = true
    case .reps:
      guard let current = reps.value else { return }
      let next = Int(current) + steps
      guard (1...999).contains(next) else { return }
      reps = Self.repsBuffer(Double(next))
      repsEdited = true
    }
  }

  /// Weight → reps. Returns false when there is no next field: the pad's cue to close.
  @discardableResult
  public mutating func advance() -> Bool {
    guard field == .weight else { return false }
    focus(.reps)
    return true
  }

  /// Focusing a field selects it, so the first key replaces what it shows.
  public mutating func focus(_ field: Field) {
    self.field = field
    switch field {
    case .weight: weight.selectForReplacement()
    case .reps: reps.selectForReplacement()
    }
  }

  /// What the fields describe, in canonical kilograms.
  ///
  /// A field the lifter did not change keeps the draft's own value. Re-deriving it from the
  /// rounded display would turn a 60 kg set into 60.0013 kg the moment a pounds user changed
  /// only the reps, and the row would then save a weight nobody entered.
  public var draft: SetEntryDraft {
    SetEntryDraft(
      weightKg: weightEdited ? weight.value.map(unit.toKilograms) : base.weightKg,
      reps: repsEdited ? reps.value.map { Int($0) } : base.reps,
      suggestion: base.suggestion
    )
  }

  /// The value being composed, for the pad's header: "102.5 kg × 8". An empty field shows "—",
  /// never "0". The stored text always uses ".", so the locale's separator is substituted here.
  public func composedText(locale: Locale = .current) -> String {
    let weightText = weight.isEmpty ? "—" : weight.displayText(locale: locale)
    let repsText = reps.isEmpty ? "—" : reps.displayText
    return "\(weightText) \(unit.abbreviation) × \(repsText)"
  }

  /// Applies a key to the focused field. A key that changes no text (the inert decimal on reps,
  /// delete on an empty field) is not an edit, so it cannot trigger a re-derivation.
  private mutating func edit(_ change: (inout NumericEntryBuffer) -> Void) {
    switch field {
    case .weight:
      let before = weight.text
      change(&weight)
      if weight.text != before { weightEdited = true }
    case .reps:
      let before = reps.text
      change(&reps)
      if reps.text != before { repsEdited = true }
    }
  }

  private static func weightBuffer(_ value: Double?) -> NumericEntryBuffer {
    NumericEntryBuffer(value: value, maximumIntegerDigits: 4, maximumFractionDigits: 2)
  }

  private static func repsBuffer(_ value: Double?) -> NumericEntryBuffer {
    NumericEntryBuffer(
      value: value, allowsDecimal: false, maximumIntegerDigits: 3, maximumFractionDigits: 0
    )
  }
}
