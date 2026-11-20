import Foundation
import Testing

@testable import HardsetCore

@Suite("A lifter's own choice of muscles for a movement")
struct CustomAttributionTests {
  @Test("Up to three secondary muscles are allowed, and none is fine")
  func acceptsZeroToThreeSecondaries() {
    #expect(CustomAttribution(primary: .lats, secondary: []) != nil)
    #expect(CustomAttribution(primary: .lats, secondary: [.biceps]) != nil)
    #expect(CustomAttribution(primary: .lats, secondary: [.biceps, .forearms, .rearDelts]) != nil)
  }

  @Test("More than three, a repeat, or the primary again is refused")
  func customAttributionRejectsDuplicates() {
    #expect(
      CustomAttribution(primary: .lats, secondary: [.biceps, .forearms, .rearDelts, .traps]) == nil)
    #expect(CustomAttribution(primary: .lats, secondary: [.biceps, .biceps]) == nil)
    #expect(CustomAttribution(primary: .lats, secondary: [.lats]) == nil)
  }

  @Test("It is stored as the lifter's own word: primary direct, secondaries indirect, moderate")
  func contributionsAreTheLiftersChoice() {
    let attribution = CustomAttribution(primary: .lats, secondary: [.biceps, .rearDelts])!

    let contributions = attribution.contributions

    #expect(contributions.map(\.key.storedValue) == ["lats", "biceps", "rearDelts"])
    #expect(contributions.map(\.role) == [.direct, .indirect, .indirect])
    #expect(contributions.allSatisfy { $0.certainty == .moderate })
    #expect(contributions.allSatisfy { $0.sourceID == AttributionSourceID.user.rawValue })
  }

  @Test("The equipment type travels with it, and may be left unsaid")
  func modalityIsOptional() {
    #expect(CustomAttribution(primary: .chest, modality: .cable)?.modality == .cable)
    #expect(CustomAttribution(primary: .chest)?.modality == nil)
  }
}
