import Foundation
import Testing

@testable import HardsetCore

@Suite("Every muscle has a written name, and an unknown token is never shown raw")
struct MuscleNamesTests {
  @Test("The names are the ones the app has always shown")
  func names() {
    let expected: [Muscle: String] = [
      .chest: "Chest", .frontDelts: "Front delts", .sideDelts: "Side delts",
      .rearDelts: "Rear delts", .rotatorCuff: "Rotator cuff", .lats: "Lats",
      .upperBack: "Upper back", .traps: "Traps", .lowerBack: "Lower back",
      .biceps: "Biceps", .triceps: "Triceps", .forearms: "Forearms",
      .abs: "Abs", .obliques: "Obliques", .neck: "Neck",
      .quadriceps: "Quads", .hamstrings: "Hamstrings", .glutes: "Glutes",
      .adductors: "Adductors", .hipAbductors: "Hip abductors",
      .gastrocnemius: "Gastrocnemius", .soleus: "Soleus",
    ]
    #expect(expected.count == Muscle.allCases.count)
    for muscle in Muscle.allCases {
      #expect(muscle.displayName == expected[muscle])
    }
  }

  @Test("No two muscles share a name, and none is its raw token")
  func distinct() {
    let names = Muscle.allCases.map(\.displayName)
    #expect(Set(names).count == names.count)
    for muscle in Muscle.allCases where muscle.rawValue.contains(where: \.isUppercase) {
      #expect(muscle.displayName != muscle.rawValue)
    }
  }

  @Test("A key names its muscle, or says plainly that it has none")
  func keys() {
    #expect(MuscleKey(.quadriceps).displayName == "Quads")
    #expect(MuscleKey(stored: MuscleKey.notAttributedRawValue).displayName == "Not attributed")
    #expect(MuscleKey(stored: "serratusAnterior").displayName == "Not recognised")
  }
}
