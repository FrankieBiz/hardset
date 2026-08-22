import HardsetCore
import Testing

@testable import HardsetUI

/// The sentence a personal record is stated in.
///
/// This exists because the estimated-1RM case shipped copy that read as a *regression*: it printed
/// the set's load next to the previous *estimate* -- "70 kg × 10, beating 80 kg" -- so a genuine
/// record looked like going backwards. Two different quantities side by side with no label.
@Suite("A record states what it beat, in the same quantity")
struct RecordCopyTests {
  @Test("Heaviest load compares load to load")
  func heaviestLoad() {
    let record = PersonalRecord(
      kind: .heaviestLoad, weightKg: 70, reps: 10, previousWeightKg: 60
    )
    let text = SessionSummaryView.recordDetail(record, unit: .kilograms)
    #expect(text == "70 kg × 10, beating 60 kg")
  }

  @Test("Reps at a load compares reps to reps")
  func repsAtLoad() {
    let record = PersonalRecord(
      kind: .repsAtLoad, weightKg: 70, reps: 12, previousWeightKg: 70, previousReps: 10
    )
    let text = SessionSummaryView.recordDetail(record, unit: .kilograms)
    #expect(text.contains("up from 10 reps"))
  }

  @Test("An estimated 1RM compares estimate to estimate, and never load to estimate")
  func estimateComparesLikeWithLike() {
    // 70 kg x 10 estimates well above 70. The previous best estimate was 80.
    let record = PersonalRecord(
      kind: .estimatedOneRepMax, weightKg: 70, reps: 10, previousWeightKg: 80
    )
    let text = SessionSummaryView.recordDetail(record, unit: .kilograms)

    // The regression this test exists to prevent: the bare set load presented as the achievement.
    #expect(text != "70 kg × 10, beating 80 kg")

    // Both sides hedged, because neither is a lift that happened.
    #expect(text.contains("about"))

    // And the new estimate must actually exceed the old one in the text, or the sentence is still
    // telling the lifter they went backwards.
    let estimate = StrengthMath.estimatedOneRepMax(weightKg: 70, reps: 10).value
    #expect(estimate != nil)
    let estimated = SessionSummaryView.format(estimate ?? 0)
    #expect(text.contains(estimated))
    #expect((estimate ?? 0) > 80)
  }

  @Test("An estimate with no previous value still reads as a statement, not a comparison")
  func estimateWithoutPrevious() {
    let record = PersonalRecord(kind: .estimatedOneRepMax, weightKg: 70, reps: 10)
    let text = SessionSummaryView.recordDetail(record, unit: .kilograms)
    #expect(!text.contains("beating"))
    #expect(text.contains("estimated from"))
  }

  @Test("Pounds are converted, not relabelled")
  func respectsUnit() {
    let record = PersonalRecord(
      kind: .heaviestLoad, weightKg: 100, reps: 5, previousWeightKg: 90
    )
    let text = SessionSummaryView.recordDetail(record, unit: .pounds)
    #expect(text.contains("lb"))
    #expect(!text.contains("100 lb"))  // 100 kg is not 100 lb
  }
}
