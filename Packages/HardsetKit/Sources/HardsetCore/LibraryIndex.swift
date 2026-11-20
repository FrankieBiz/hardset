import Foundation

/// One section of the movement library.
public struct LibrarySection: Hashable, Sendable, Identifiable {
  public enum Kind: Hashable, Sendable {
    /// Movements with no usable body part, shown first so they can be tagged.
    case needsBodyPart
    case category(MuscleFilterCategory)
  }

  public let kind: Kind
  public let entries: [CatalogEntry]

  public var id: Kind { kind }

  public init(kind: Kind, entries: [CatalogEntry]) {
    self.kind = kind
    self.entries = entries
  }
}

/// Groups the catalogue by body part for the library screen.
///
/// Untagged movements are never folded into a guessed category: they get their own first
/// section so the coverage gap is visible and fixable. Entries sort by name with the system's
/// standard comparison, so "Lat pulldown" precedes "lever row".
public enum LibraryIndex {
  public static func sections(_ entries: [CatalogEntry]) -> [LibrarySection] {
    var untagged: [CatalogEntry] = []
    var byCategory: [MuscleFilterCategory: [CatalogEntry]] = [:]

    for entry in entries {
      if let category = MuscleFilterCategory.category(for: entry.primaryMuscle) {
        byCategory[category, default: []].append(entry)
      } else {
        untagged.append(entry)
      }
    }

    var sections: [LibrarySection] = []
    if !untagged.isEmpty {
      sections.append(LibrarySection(kind: .needsBodyPart, entries: sorted(untagged)))
    }
    for category in MuscleFilterCategory.allCases {
      guard let categoryEntries = byCategory[category], !categoryEntries.isEmpty else { continue }
      sections.append(LibrarySection(kind: .category(category), entries: sorted(categoryEntries)))
    }
    return sections
  }

  /// Every category in `allCases` order, including zeros. Unattributed entries are not counted.
  public static func counts(
    _ entries: [CatalogEntry]
  ) -> [(category: MuscleFilterCategory, count: Int)] {
    MuscleFilterCategory.allCases.map { category in
      (category, entries.filter { category.matches($0.primaryMuscle) }.count)
    }
  }

  private static func sorted(_ entries: [CatalogEntry]) -> [CatalogEntry] {
    entries.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }
}
