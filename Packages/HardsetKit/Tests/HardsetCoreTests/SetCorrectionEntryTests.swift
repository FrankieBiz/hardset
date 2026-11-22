import Testing

@testable import HardsetCore

/// Correcting a finished set is a pair of figures typed on a sheet. These hold the arithmetic the
/// sheet relies on: an untouched figure is written back exactly, a typed one is converted from the
/// display unit, and nothing incomplete reaches the store.
@Suite("A correction typed for a saved set resolves exactly and completely")
struct SetCorrectionEntryTests {
  private func type(_ text: String, into buffer: inout NumericEntryBuffer) {
    for character in text {
      if character == "." {
        buffer.appendDecimalSeparator()
      } else if let digit = character.wholeNumberValue {
        buffer.append(digit: digit)
      }
    }
  }

  @Test("Both figures start on the saved set, and nothing has changed yet")
  func seededFromTheSavedSet() {
    let entry = SetCorrectionEntry(weightKg: 100, reps: 5, unit: .kilograms)
    #expect(entry.weightBuffer.text == "100")
    #expect(entry.repsBuffer.text == "5")
    #expect(entry.weightKg == 100)
    #expect(entry.reps == 5)
    #expect(entry.isComplete)
    #expect(!entry.changesFigures)
  }

  @Test("Typing a new weight replaces the saved one and leaves the reps exactly as saved")
  func newWeightKeepsReps() {
    var entry = SetCorrectionEntry(weightKg: 100, reps: 5, unit: .kilograms)
    type("110", into: &entry.weightBuffer)
    #expect(entry.weightBuffer.text == "110")
    #expect(entry.weightKg == 110)
    #expect(entry.reps == 5)
    #expect(entry.changesFigures)
  }

  @Test("A pound lifter who corrects only the reps does not rewrite the weight through rounding")
  func untouchedWeightIsNotRoundTripped() throws {
    // 60 kg reads "132.28" lb. Converting that text back is not 60, and a reps-only correction
    // must not be the thing that moves it.
    var entry = SetCorrectionEntry(weightKg: 60, reps: 8, unit: .pounds)
    #expect(entry.weightBuffer.text == "132.28")
    let roundTripped = WeightUnit.pounds.toKilograms(try #require(Double(entry.weightBuffer.text)))
    #expect(roundTripped != 60)

    type("10", into: &entry.repsBuffer)
    #expect(entry.weightKg == 60)
    #expect(entry.reps == 10)
    #expect(entry.draft.resolved()?.weightKg == 60)
    #expect(entry.changesFigures)
  }

  @Test("A weight typed in pounds is stored in kilograms")
  func typedPoundsBecomeKilograms() throws {
    var entry = SetCorrectionEntry(weightKg: 60, reps: 8, unit: .pounds)
    type("225", into: &entry.weightBuffer)
    let kilograms = try #require(entry.weightKg)
    #expect(abs(kilograms - WeightUnit.pounds.toKilograms(225)) < 1e-9)
  }

  @Test("Typing the saved figures back is not a correction")
  func typingBackIsNoChange() {
    var entry = SetCorrectionEntry(weightKg: 100, reps: 5, unit: .kilograms)
    type("90", into: &entry.weightBuffer)
    #expect(entry.changesFigures)
    entry.weightBuffer.clear()
    type("100", into: &entry.weightBuffer)
    #expect(!entry.changesFigures)
    #expect(entry.weightKg == 100)
  }

  @Test("An empty or unfinished figure is not a set, and is never coerced to zero")
  func incompleteIsNotASet() {
    var entry = SetCorrectionEntry(weightKg: 100, reps: 5, unit: .kilograms)
    entry.weightBuffer.clear()
    #expect(entry.weightKg == nil)
    #expect(!entry.isComplete)
    #expect(!entry.changesFigures)

    // "100." is a number still being typed.
    entry.weightBuffer.clear()
    type("100.", into: &entry.weightBuffer)
    #expect(entry.weightKg == nil)
    #expect(!entry.isComplete)

    var emptyReps = SetCorrectionEntry(weightKg: 100, reps: 5, unit: .kilograms)
    emptyReps.repsBuffer.clear()
    #expect(emptyReps.reps == nil)
    #expect(!emptyReps.isComplete)
  }

  @Test("Zero reps is not a set; zero added load is")
  func zeroRulesMatchLogging() {
    var noReps = SetCorrectionEntry(weightKg: 100, reps: 5, unit: .kilograms)
    noReps.repsBuffer.clear()
    type("0", into: &noReps.repsBuffer)
    #expect(noReps.reps == 0)
    #expect(!noReps.isComplete)

    var bodyweight = SetCorrectionEntry(weightKg: 20, reps: 8, unit: .kilograms)
    bodyweight.weightBuffer.clear()
    type("0", into: &bodyweight.weightBuffer)
    #expect(bodyweight.weightKg == 0)
    #expect(bodyweight.isComplete)
    #expect(bodyweight.changesFigures)
  }
}

@Suite("A corrected finished set is reported neutrally, never celebrated")
struct SetCorrectionCopyTests {
  private func record(_ kind: PersonalRecordKind) -> PersonalRecord {
    PersonalRecord(kind: kind, weightKg: 110, reps: 5, previousWeightKg: 100, previousReps: 5)
  }

  @Test("A correction that earns a record says so, in the ledger's words")
  func gainedRecord() {
    let note = SetCorrectionCopy.note(
      figures: "Bench, 110 kg × 5", before: [], after: [record(.heaviestLoad)])
    #expect(note.hasPrefix("Corrected to Bench, 110 kg × 5. It is now recorded as a best."))
    #expect(note.contains("History, volume, records and progress now use the corrected figures."))
  }

  @Test("A correction that takes a record away says that too")
  func lostRecord() {
    let note = SetCorrectionCopy.note(
      figures: "Bench, 80 kg × 5", before: [record(.heaviestLoad)], after: [])
    #expect(note.contains("It no longer counts as a record."))
  }

  @Test("A correction that changes no record claims none")
  func unchangedRecords() {
    let none = SetCorrectionCopy.note(figures: "Bench, 80 kg × 5", before: [], after: [])
    #expect(!none.contains("record as a best") && !none.contains("no longer"))
    let same = SetCorrectionCopy.note(
      figures: "Bench, 110 kg × 5", before: [record(.heaviestLoad)], after: [record(.heaviestLoad)])
    #expect(!same.contains("record as a best") && !same.contains("no longer"))
  }

  @Test("The note never uses celebratory words")
  func neverCelebrates() {
    let note = SetCorrectionCopy.note(
      figures: "Bench, 110 kg × 5", before: [], after: [record(.heaviestLoad)]).lowercased()
    for word in ["pr!", "congrat", "new record", "great", "!"] {
      #expect(!note.contains(word))
    }
  }
}
