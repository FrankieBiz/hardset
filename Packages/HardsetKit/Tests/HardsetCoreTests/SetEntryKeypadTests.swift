import Foundation
import Testing

@testable import HardsetCore

@Suite("The first key replaces a prefill; deleting edits it")
struct ReplaceOnFirstInputTests {
  @Test("A digit typed over a prefill replaces it")
  func digitReplaces() {
    var buffer = NumericEntryBuffer(value: 100)
    #expect(buffer.replacesOnNextInput)
    buffer.append(digit: 9)
    #expect(buffer.displayText == "9")
    #expect(!buffer.replacesOnNextInput)
  }

  @Test("102.5 over a 100 prefill takes five presses, not ten")
  func fivePresses() {
    var buffer = NumericEntryBuffer(value: 100)
    buffer.append(digit: 1)
    buffer.append(digit: 0)
    buffer.append(digit: 2)
    buffer.appendDecimalSeparator()
    buffer.append(digit: 5)
    #expect(buffer.value == 102.5)
  }

  @Test("A decimal point over a prefill starts a fresh 0.")
  func separatorReplaces() {
    var buffer = NumericEntryBuffer(value: 100)
    buffer.appendDecimalSeparator()
    #expect(buffer.displayText == "0.")
  }

  @Test("Delete edits the prefill instead of replacing it")
  func deleteEdits() {
    var buffer = NumericEntryBuffer(value: 100)
    buffer.deleteBackward()
    #expect(buffer.displayText == "10")
    buffer.append(digit: 5)
    #expect(buffer.displayText == "105")
  }

  @Test("The inert decimal key on reps does not clear the prefill")
  func inertDecimalKeepsPrefill() {
    var reps = NumericEntryBuffer(
      value: 8, allowsDecimal: false, maximumIntegerDigits: 3, maximumFractionDigits: 0
    )
    reps.appendDecimalSeparator()
    #expect(reps.displayText == "8")
    reps.append(digit: 1)
    reps.append(digit: 0)
    #expect(reps.displayText == "10")
  }

  @Test("Only a prefill is replaced: an empty field and typed text append")
  func onlyPrefillsAreReplaced() {
    var empty = NumericEntryBuffer(value: nil)
    #expect(!empty.replacesOnNextInput)
    empty.append(digit: 6)
    empty.append(digit: 0)
    #expect(empty.displayText == "60")

    var typed = NumericEntryBuffer(text: "6")
    typed.append(digit: 2)
    #expect(typed.displayText == "62")
  }

  @Test("Selecting an empty field selects nothing")
  func selectingEmpty() {
    var buffer = NumericEntryBuffer()
    buffer.selectForReplacement()
    #expect(!buffer.replacesOnNextInput)
  }

  @Test("Clearing leaves no value and nothing to replace")
  func clearing() {
    var buffer = NumericEntryBuffer(value: 100)
    buffer.clear()
    #expect(buffer.value == nil)
    #expect(!buffer.replacesOnNextInput)
    buffer.append(digit: 7)
    #expect(buffer.displayText == "7")
  }
}

@Suite("± moves by what the equipment moves by")
struct LoadStepTests {
  @Test("A machine's stack increment wins")
  func machineWins() {
    let step = LoadStep(machineIncrementKg: 5, unit: .kilograms)
    #expect(step.amount == 5)
    #expect(step.source == .machine)
  }

  @Test("With no machine increment: 2.5 kg, or 5 lb")
  func unitDefault() {
    #expect(LoadStep(machineIncrementKg: nil, unit: .kilograms).amount == 2.5)
    #expect(LoadStep(machineIncrementKg: nil, unit: .pounds).amount == 5)
    #expect(LoadStep(machineIncrementKg: nil, unit: .pounds).source == .unitDefault)
  }

  @Test("A kilogram stack read in pounds steps by its real size")
  func machineStepInPounds() {
    let step = LoadStep(machineIncrementKg: 5, unit: .pounds)
    #expect(abs(step.amount - 11.023_113_1) < 1e-6)
  }

  @Test(
    "A nonsense increment falls back to the unit's step",
    arguments: [0.0, -2.5, Double.nan, Double.infinity]
  )
  func nonsenseIncrement(increment: Double) {
    let step = LoadStep(machineIncrementKg: increment, unit: .kilograms)
    #expect(step.amount == 2.5)
    #expect(step.source == .unitDefault)
  }

  @Test("A step never creates a value from nothing")
  func nilStaysNil() {
    #expect(LoadStep(machineIncrementKg: nil, unit: .kilograms).moved(nil, by: 1) == nil)
  }

  @Test("Below zero is refused; down to exactly zero is allowed")
  func floorAtZero() {
    let step = LoadStep(machineIncrementKg: nil, unit: .kilograms)
    #expect(step.moved(1, by: -1) == nil)
    #expect(step.moved(2.5, by: -1) == 0)
  }
}

@Suite("The keypad edits a set the way a lifter expects")
struct SetEntryKeypadTests {
  let posix = Locale(identifier: "en_US_POSIX")

  private func keypad(
    _ weightKg: Double?, _ reps: Int?, unit: WeightUnit = .kilograms, increment: Double? = nil
  ) -> SetEntryKeypad {
    SetEntryKeypad(
      draft: SetEntryDraft(weightKg: weightKg, reps: reps), unit: unit,
      machineIncrementKg: increment
    )
  }

  @Test("100 to 102.5 is one ± press on plates")
  func onePress() {
    var pad = keypad(100, 8)
    pad.step(.up)
    #expect(pad.draft.weightKg == 102.5)
    #expect(pad.draft.reps == 8)
  }

  @Test("On a 5 kg stack, ± moves 5 kg")
  func stackStep() {
    var pad = keypad(100, 8, increment: 5)
    pad.step(.up)
    #expect(pad.draft.weightKg == 105)
    pad.step(.down)
    pad.step(.down)
    #expect(pad.draft.weightKg == 95)
  }

  @Test("± never invents a weight for an empty field")
  func noValueFromNil() {
    var pad = keypad(nil, 8)
    pad.step(.up)
    #expect(pad.draft.weightKg == nil)
    #expect(!pad.draft.isLoggable)
  }

  @Test("Typing replaces the prefill: 102.5 in five presses")
  func typed() {
    var pad = keypad(100, 8)
    pad.type(digit: 1)
    pad.type(digit: 0)
    pad.type(digit: 2)
    pad.typeDecimalSeparator()
    pad.type(digit: 5)
    #expect(pad.draft.weightKg == 102.5)
  }

  @Test("A stepped value is replaced by the next digit, like a prefill")
  func stepResultIsSelected() {
    var pad = keypad(100, 8)
    pad.step(.up)
    pad.type(digit: 9)
    pad.type(digit: 0)
    #expect(pad.draft.weightKg == 90)
  }

  @Test("Next moves weight to reps and selects it; from reps there is nothing next")
  func next() {
    var pad = keypad(100, 8)
    #expect(pad.field == .weight)
    let advanced = pad.advance()
    #expect(advanced)
    #expect(pad.field == .reps)
    pad.type(digit: 1)
    pad.type(digit: 0)
    #expect(pad.draft.reps == 10)
    let advancedAgain = pad.advance()
    #expect(!advancedAgain)
    #expect(pad.field == .reps)
  }

  @Test("Clear empties only the focused field and leaves no zero behind")
  func clearFocusedOnly() {
    var pad = keypad(100, 8)
    pad.clear()
    #expect(pad.draft.weightKg == nil)
    #expect(pad.draft.reps == 8)
    #expect(!pad.draft.isLoggable)
  }

  @Test("Reps step by one, never below one")
  func repsStep() {
    var pad = keypad(100, 1)
    pad.advance()
    pad.step(.down)
    #expect(pad.draft.reps == 1)
    pad.step(.up)
    pad.step(.up)
    #expect(pad.draft.reps == 3)
  }

  @Test("A weight past what the field can hold is refused")
  func ceiling() {
    var pad = keypad(9_998, 5)
    pad.step(.up)
    #expect(pad.draft.weightKg == 9_998)
  }

  /// Review Focus: the display holds 132.28 lb; storage holds 60 kg. Touching only the reps must
  /// not rewrite the weight from the rounded display.
  @Test("Changing only the reps in pounds leaves the stored kilograms exactly as they were")
  func untouchedWeightKeepsCanonicalValue() {
    var pad = keypad(60, 8, unit: .pounds)
    #expect(pad.weight.displayText == "132.28")
    pad.advance()
    pad.type(digit: 9)
    #expect(pad.draft.weightKg == 60)
    #expect(pad.draft.reps == 9)
  }

  @Test("A key that changes nothing, and moving between fields, are not edits")
  func noOpIsNotAnEdit() {
    var pad = keypad(60, 8, unit: .pounds)
    pad.advance()
    pad.typeDecimalSeparator()  // inert on reps
    pad.focus(.weight)  // focusing selects; it does not edit
    #expect(pad.draft.weightKg == 60)
    #expect(pad.draft.reps == 8)
  }

  @Test("Typed pounds are stored as kilograms")
  func poundsToKilograms() throws {
    var pad = keypad(nil, nil, unit: .pounds)
    pad.type(digit: 2)
    pad.type(digit: 2)
    pad.type(digit: 5)
    let kilograms = try #require(pad.draft.weightKg)
    #expect(abs(kilograms - 102.058_283_25) < 1e-6)
  }

  @Test("The header shows what is being composed, in the locale's notation")
  func header() {
    var pad = keypad(100, 8)
    #expect(pad.composedText(locale: posix) == "100 kg × 8")
    pad.step(.up)
    #expect(pad.composedText(locale: posix) == "102.5 kg × 8")
    #expect(pad.composedText(locale: Locale(identifier: "de_DE")) == "102,5 kg × 8")
    #expect(keypad(nil, nil).composedText(locale: posix) == "— kg × —")
  }

  @Test("The draft's suggestion survives editing")
  func suggestionKept() {
    let last = PriorSetRecord(weightKg: 100, reps: 8, completedAt: .distantPast)
    var pad = SetEntryKeypad(
      draft: SetEntryDraft(suggestion: last), unit: .kilograms, machineIncrementKg: nil
    )
    pad.step(.up)
    #expect(pad.draft.suggestion == last)
  }
}
