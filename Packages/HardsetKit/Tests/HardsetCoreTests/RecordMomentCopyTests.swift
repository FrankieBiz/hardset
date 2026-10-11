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

  @Test("Estimates that display the same are not a movement, in kilograms")
  func equalDisplayedEstimateKilograms() throws {
    // 9.05 kg for 5 reps estimates about 10.56 kg; the previous best was 10.3 kg. Both display
    // as 10.5 kg, so the new value must stand alone rather than read "up from" itself.
    let newKg = try #require(StrengthMath.estimatedOneRepMax(weightKg: 9.05, reps: 5).value)
    let previousKg = 10.3
    #expect(
      StrengthMath.displayRounded(newKg, in: .kilograms)
        == StrengthMath.displayRounded(previousKg, in: .kilograms))
    let record = PersonalRecord(
      kind: .estimatedOneRepMax, weightKg: 9.05, reps: 5, previousWeightKg: previousKg)
    #expect(RecordCopy.detail(for: record, formatter: kilograms) == "about 10.5 kg")
    #expect(
      RecordCopy.line(for: record, formatter: kilograms) == "Best estimated 1RM: about 10.5 kg")
  }

  @Test("Estimates that display the same are not a movement, in pounds")
  func equalDisplayedEstimatePounds() throws {
    // 14 lb for 5 reps estimates about 16.33 lb; the previous best was 15.6 lb. Both display
    // as a whole 16 lb.
    let newKg = try #require(
      StrengthMath.estimatedOneRepMax(weightKg: WeightUnit.pounds.toKilograms(14), reps: 5).value)
    let previousKg = WeightUnit.pounds.toKilograms(15.6)
    #expect(
      StrengthMath.displayRounded(newKg, in: .pounds)
        == StrengthMath.displayRounded(previousKg, in: .pounds))
    let record = PersonalRecord(
      kind: .estimatedOneRepMax, weightKg: WeightUnit.pounds.toKilograms(14), reps: 5,
      previousWeightKg: previousKg)
    let detail = RecordCopy.detail(for: record, formatter: pounds)
    #expect(detail == "about 16 lb")
    #expect(!detail.contains("kg"))
  }

  @Test("Spoken estimates that display the same are not a movement")
  func equalDisplayedEstimateSpoken() throws {
    let previousKg = 10.3
    let record = PersonalRecord(
      kind: .estimatedOneRepMax, weightKg: 9.05, reps: 5, previousWeightKg: previousKg)
    let spoken = RecordCopy.spokenDetail(for: record, formatter: kilograms)
    #expect(spoken == "about 10.5 kilograms")
    #expect(!spoken.contains("up from"))
  }

  @Test("An estimate that displays differently still says up from")
  func differentDisplayedEstimateKeepsMovement() {
    // 100 kg for 5 reps estimates about 116.67 kg (displays 116.5); the previous best was 100 kg.
    let record = PersonalRecord(
      kind: .estimatedOneRepMax, weightKg: 100, reps: 5, previousWeightKg: 100)
    #expect(
      RecordCopy.detail(for: record, formatter: kilograms)
        == "about 116.5 kg, up from about 100 kg")
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
