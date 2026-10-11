import Foundation
import Testing

@testable import HardsetCore

@Suite("One haptic per thing that happened")
struct FeedbackEventTests {
  @Test("A record outranks an ordinary log")
  func recordOutranksLog() {
    #expect(FeedbackEvent.afterLogging(records: []) == .log)
    let record = PersonalRecord(kind: .heaviestLoad, weightKg: 105, reps: 5, previousWeightKg: 100)
    #expect(FeedbackEvent.afterLogging(records: [record]) == .record)
  }

  @Test("Two identical events in a row are still two pulses")
  func pulsesAreDistinct() {
    let row = UUID()
    let first = FeedbackPulse.following(nil, event: .log, slotID: row)
    let second = FeedbackPulse.following(first, event: .log, slotID: row)
    #expect(first.sequence == 1)
    #expect(second.sequence == 2)
    #expect(first != second)
    #expect(second.slotID == row)
  }
}

@Suite("A record states what it beat, in the lifter's unit")
struct RecordCopyTests {
  let posix = Locale(identifier: "en_US_POSIX")
  var kilograms: WeightFormatter { WeightFormatter(unit: .kilograms, locale: posix) }
  var pounds: WeightFormatter { WeightFormatter(unit: .pounds, locale: posix) }

  let heaviest = PersonalRecord(kind: .heaviestLoad, weightKg: 105, reps: 5, previousWeightKg: 100)
  let reps = PersonalRecord(
    kind: .repsAtLoad, weightKg: 100, reps: 9, previousWeightKg: 100, previousReps: 8)
  // 100 × 5 estimates 116.67 kg; the best before was 110 kg.
  let estimate = PersonalRecord(
    kind: .estimatedOneRepMax, weightKg: 100, reps: 5, previousWeightKg: 110)

  @Test("Heaviest weight names the new load and the old one")
  func heaviestCopy() {
    #expect(RecordCopy.detail(for: heaviest, formatter: kilograms) == "105 kg, up from 100 kg")
    #expect(
      RecordCopy.line(for: heaviest, formatter: kilograms)
        == "Heaviest weight: 105 kg, up from 100 kg")
    #expect(
      RecordCopy.detail(for: heaviest, formatter: pounds) == "231.49 lb, up from 220.46 lb")
  }

  @Test("Reps at a load names the load and the old count")
  func repsCopy() {
    #expect(RecordCopy.detail(for: reps, formatter: kilograms) == "9 reps at 100 kg, up from 8")
  }

  @Test("An estimate states the new estimate, called an estimate, never in kilograms in pounds mode")
  func estimateCopy() {
    #expect(
      RecordCopy.detail(for: estimate, formatter: kilograms)
        == "about 116.5 kg, up from about 110 kg")
    let inPounds = RecordCopy.detail(for: estimate, formatter: pounds)
    #expect(inPounds == "about 257 lb, up from about 243 lb")
    #expect(!inPounds.contains("kg"))
  }

  @Test("VoiceOver hears the movement and the units in full")
  func announcement() {
    #expect(
      RecordCopy.announcement(for: [heaviest], exerciseName: "Leg Press", formatter: kilograms)
        == "New record on Leg Press. Heaviest weight: 105 kilograms, up from 100 kilograms.")
    let both = RecordCopy.announcement(
      for: [heaviest, estimate], exerciseName: "Leg Press", formatter: pounds)
    #expect(both?.hasPrefix("New records on Leg Press.") == true)
    #expect(both?.contains("Best estimated 1RM: about 257 pounds") == true)
    #expect(both?.contains("lb") == false)
  }

  @Test("Nothing to announce is nil, not an empty string")
  func nothing() {
    #expect(RecordCopy.announcement(for: [], exerciseName: "Leg Press", formatter: kilograms) == nil)
  }
}
