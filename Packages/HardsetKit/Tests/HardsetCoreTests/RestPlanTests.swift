import Foundation
import Testing

@testable import HardsetCore

@Suite("Rest is the lifter's choice, never the app's")
struct RestPlanTests {
  @Test("With no choice, nothing is requested — there is no default rest")
  func noChoiceNoRest() {
    #expect(RestPlan.restAfterLogging(isWarmup: false, choice: nil) == nil)
  }

  @Test("A chosen rest is requested after a working set")
  func choiceIsRequested() {
    #expect(RestPlan.restAfterLogging(isWarmup: false, choice: .seconds(120)) == .seconds(120))
  }

  @Test("A warm-up never starts a rest, even with a choice")
  func warmupNeverRests() {
    #expect(RestPlan.restAfterLogging(isWarmup: true, choice: .seconds(120)) == nil)
  }

  @Test("Presets are offered as choices; none of them is a default")
  func presetsAreChoicesOnly() {
    #expect(RestPlan.presets == [60, 90, 120, 180, 240, 300].map { Duration.seconds($0) })
    // The refusal is structural: there is no `default` member to reach for.
    #expect(RestPlan.restAfterLogging(isWarmup: false, choice: nil) == nil)
  }

  @Test(
    "Out-of-range choices are refused, not clamped",
    arguments: [0, 5, 14, 1801, 7200]
  )
  func outOfRangeRefused(seconds: Int) {
    #expect(RestPlan.validated(.seconds(seconds)) == nil)
  }

  @Test("In-range choices pass through unchanged", arguments: [15, 61, 120, 1800])
  func inRangeAccepted(seconds: Int) {
    #expect(RestPlan.validated(.seconds(seconds)) == .seconds(seconds))
  }

  @Test("A rest is whole seconds: a fraction is refused, never rounded")
  func wholeSecondsOnly() {
    #expect(RestPlan.validated(.seconds(90.4)) == nil)
    #expect(RestPlan.validated(.seconds(90.0)) == .seconds(90))
  }

  @Test("The chip reads Off or a clock time")
  func labels() {
    #expect(RestPlan.label(for: nil) == "Off")
    #expect(RestPlan.label(for: .seconds(90)) == "1:30")
    #expect(RestPlan.label(for: .seconds(120)) == "2:00")
  }
}
