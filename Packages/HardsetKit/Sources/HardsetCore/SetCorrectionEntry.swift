import Foundation

/// The two keypad buffers behind correcting a saved set outside the live session, and what they
/// resolve to.
///
/// The live session corrects one figure at a time, because its keypad leaves a figure and writes
/// that figure. A finished workout's set is corrected as a pair, on its own sheet with an explicit
/// Save, so this holds both buffers and answers the two questions the sheet needs: is there a
/// complete set to write, and does it differ from what is saved.
///
/// The one rule worth a type: a figure the lifter did not touch is written back exactly as saved.
/// A set stored as 60 kg and shown in pounds is "132.28"; converting that text back is 59.9999 kg,
/// so a correction of only the reps would quietly rewrite the weight. A buffer whose text is still
/// the text it was seeded with therefore resolves to the saved figure, not to a round trip through
/// the display unit.
public struct SetCorrectionEntry: Hashable, Sendable {
  public var weightBuffer: NumericEntryBuffer
  public var repsBuffer: NumericEntryBuffer
  public let unit: WeightUnit
  public let savedWeightKg: Double
  public let savedReps: Int
  private let weightSeedText: String
  private let repsSeedText: String

  /// Both buffers start on the saved figures, marked so the first key replaces them, as the
  /// keypad does for any prefilled value.
  public init(weightKg: Double, reps: Int, unit: WeightUnit) {
    let weight = NumericEntryBuffer(
      value: unit.fromKilograms(weightKg), maximumIntegerDigits: 4, maximumFractionDigits: 2,
      replaceOnFirstEntry: true)
    let repsField = NumericEntryBuffer(
      value: Double(reps), allowsDecimal: false, maximumIntegerDigits: 3, maximumFractionDigits: 0,
      replaceOnFirstEntry: true)
    self.weightBuffer = weight
    self.repsBuffer = repsField
    self.unit = unit
    self.savedWeightKg = weightKg
    self.savedReps = reps
    self.weightSeedText = weight.text
    self.repsSeedText = repsField.text
  }

  /// Kilograms to write, or `nil` while the weight is empty or unfinished ("100." is not a number
  /// yet). The saved figure, exactly, while the buffer still reads as it was seeded.
  public var weightKg: Double? {
    if weightBuffer.text == weightSeedText { return savedWeightKg }
    return weightBuffer.value.map(unit.toKilograms)
  }

  /// Reps to write, or `nil` while the field is empty or not a whole number.
  public var reps: Int? {
    if repsBuffer.text == repsSeedText { return savedReps }
    return repsBuffer.value.flatMap { Int(exactly: $0) }
  }

  /// The figures as a draft, for the same completeness rule every other write goes through.
  public var draft: SetEntryDraft {
    SetEntryDraft(weightKg: weightKg, reps: reps)
  }

  /// True only for a set the store would accept: a usable weight and at least one rep.
  public var isComplete: Bool { draft.isLoggable }

  /// Whether saving would change anything. Typing the saved figures back is not a correction, and
  /// the sheet leaves Save off for it rather than writing the same numbers again.
  public var changesFigures: Bool {
    guard let resolved = draft.resolved() else { return false }
    return resolved.weightKg != savedWeightKg || resolved.reps != savedReps
  }
}

/// What the receipt says once a finished set has been corrected, in the words of the claim: what
/// the set now is, and whether that made it a record or took a record away. Neutral on purpose. A
/// retroactive correction updates the ledger and does not celebrate, so there is no trophy and no
/// tint, only a plain sentence.
public enum SetCorrectionCopy {
  /// - Parameters:
  ///   - figures: The corrected set as the receipt writes it, such as "Bench, 110 kg × 5".
  ///   - before: The set's records before the correction.
  ///   - after: The set's records after it, recomputed from the corrected figures.
  public static func note(
    figures: String, before: [PersonalRecord], after: [PersonalRecord]
  ) -> String {
    let beforeKinds = Set(before.map(\.kind))
    let afterKinds = Set(after.map(\.kind))
    let ending = "History, volume, records and progress now use the corrected figures."
    if !afterKinds.subtracting(beforeKinds).isEmpty {
      return "Corrected to \(figures). It is now recorded as a best. " + ending
    }
    if afterKinds.isEmpty, !beforeKinds.isEmpty {
      return "Corrected to \(figures). It no longer counts as a record. " + ending
    }
    return "Corrected to \(figures). " + ending
  }
}
