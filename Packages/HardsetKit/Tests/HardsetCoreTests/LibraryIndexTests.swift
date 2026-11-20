import Foundation
import Testing

@testable import HardsetCore

@Suite("Library sections by body part")
struct LibraryIndexTests {
  private func entry(_ name: String, _ muscle: MuscleKey) -> CatalogEntry {
    CatalogEntry(
      id: ExerciseID(), name: name, slug: nil, isCurated: false,
      modality: .machine, primaryMuscle: muscle, contributions: []
    )
  }

  @Test func untaggedComeFirst() {
    let sections = LibraryIndex.sections([
      entry("Bench press", MuscleKey(.chest)),
      entry("Mystery machine", MuscleKey(stored: "unknown")),
    ])
    #expect(sections.count == 2)
    #expect(sections[0].kind == .needsBodyPart)
    #expect(sections[0].entries.map(\.name) == ["Mystery machine"])
    #expect(sections[1].kind == .category(.chest))
  }

  @Test func sectionsFollowCategoryOrderAndSkipEmpty() {
    let sections = LibraryIndex.sections([
      entry("Curl", MuscleKey(.biceps)),
      entry("Bench press", MuscleKey(.chest)),
      entry("Row", MuscleKey(.lats)),
    ])
    #expect(sections.map(\.kind) == [.category(.chest), .category(.back), .category(.arms)])
  }

  @Test func entriesSortedByName() {
    let sections = LibraryIndex.sections([
      entry("lever row", MuscleKey(.lats)),
      entry("Lat pulldown", MuscleKey(.lats)),
    ])
    #expect(sections.first?.entries.map(\.name) == ["Lat pulldown", "lever row"])
  }

  @Test func countsIncludeZeros() {
    let counts = LibraryIndex.counts([
      entry("Bench press", MuscleKey(.chest)),
      entry("Mystery machine", MuscleKey(stored: "unknown")),
    ])
    #expect(counts.count == MuscleFilterCategory.allCases.count)
    #expect(counts.first { $0.category == .chest }?.count == 1)
    #expect(counts.first { $0.category == .neck }?.count == 0)
  }
}
