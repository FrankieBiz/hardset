import Testing

@testable import HardsetFeature

/// The pitch pages' progress row is a gauge, not a control. What assistive technology is offered is
/// a named progress indicator whose value is the page: "Introduction", "Page 1 of 3". These pin the
/// words; `testOnboardingJourneyDark` pins that the element is a progress indicator carrying them on
/// each pitch page.
@Suite("The pitch progress reads as a gauge with a page value")
struct PitchProgressAccessibilityTests {
  @Test("The gauge is named for what it measures, not for where it stands")
  func label() {
    #expect(PitchProgress.accessibilityLabel == "Introduction")
    #expect(PitchProgress.accessibilityIdentifier == "pitch-progress")
  }

  @Test("The value counts pages from one", arguments: [(0, "Page 1 of 3"), (1, "Page 2 of 3"), (2, "Page 3 of 3")])
  func value(index: Int, expected: String) {
    #expect(PitchProgress.accessibilityValue(index: index, count: 3) == expected)
  }
}
