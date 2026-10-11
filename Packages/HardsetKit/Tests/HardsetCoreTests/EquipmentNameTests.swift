import Foundation
import Testing

@testable import HardsetCore

@Suite("A typed name is tidied, and a blank one is refused")
struct EquipmentNameTests {
  @Test("Spaces at the ends go, and runs inside collapse to one")
  func tidied() {
    #expect(EquipmentName.normalized("  Iron   Temple ") == "Iron Temple")
    #expect(EquipmentName.normalized("Leg Press") == "Leg Press")
    #expect(EquipmentName.normalized("Hammer\u{00A0}Strength") == "Hammer Strength")
  }

  @Test("Nothing but whitespace is no name at all")
  func blank() {
    #expect(EquipmentName.normalized("") == nil)
    #expect(EquipmentName.normalized("   ") == nil)
    #expect(EquipmentName.normalized("\n\t ") == nil)
  }
}
