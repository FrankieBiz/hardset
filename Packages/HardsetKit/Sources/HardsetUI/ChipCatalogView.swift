import SwiftUI

/// Every chip, tag and segment state, for review from images. Static: no state, no I/O.
///
/// Pressed samples are drawn through the internal faces, because a `ButtonStyle` cannot be forced
/// pressed in a render. Each section is laid out so it reflows at accessibility text sizes the way
/// the live control does.
public struct ChipCatalogView: View {
  /// The three catalogue sections, in page order. The snapshot suite renders them one at a time
  /// so that each image is as tall as its own section and nothing is cropped.
  public enum Section: String, CaseIterable, Sendable {
    case chips, tags, segments
  }

  private let section: Section?

  /// Pass `nil` for the whole page, which is what previews want; pass a section to render only
  /// that section under its label.
  public init(section: Section? = nil) {
    self.section = section
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Tokens.Spacing.section) {
        if let section {
          sectionView(section)
        } else {
          ForEach(Section.allCases, id: \.self) { sectionView($0) }
        }
      }
      .padding(.horizontal, Tokens.Spacing.loose)
      .padding(.vertical, Tokens.Spacing.loose)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(Tokens.Color.canvas.ignoresSafeArea())
  }

  @ViewBuilder
  private func sectionView(_ section: Section) -> some View {
    switch section {
    case .chips: ChipStates()
    case .tags: TagStates()
    case .segments: SegmentStates()
    }
  }
}

// MARK: - Chips

private struct ChipStates: View {
  var body: some View {
    CatalogSection("Chips") {
      VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
        HStack(spacing: Tokens.Spacing.snug) {
          HardsetChip("Unselected", isSelected: false) {}
          HardsetChip("Selected", isSelected: true) {}
        }
        HStack(spacing: Tokens.Spacing.snug) {
          HardsetChipFace(isSelected: false, isPressed: true) { Text("Pressed") }
          HardsetChipFace(isSelected: true, isPressed: true) { Text("Pressed") }
        }
        HardsetChip("Hammer Strength Leg Press", isSelected: false) {}
        // A filter rail, as the exercise picker draws it: one line per chip, scrolling sideways.
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: Tokens.Spacing.snug) {
            HardsetChip("All", isSelected: true) {}
            HardsetChip("Chest", isSelected: false) {}
            HardsetChip("Back", isSelected: false) {}
            HardsetChip("Shoulders", isSelected: false) {}
            HardsetChip("Legs", isSelected: false) {}
          }
        }
      }
    }
  }
}

// MARK: - Tags

private struct TagStates: View {
  var body: some View {
    CatalogSection("Tags") {
      VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
        HardsetTag("Barbell")
        HardsetTag("Custom", systemImage: "person.crop.circle")
        HardsetTag("Plate loaded, selectorized and cable stack")
        HardsetTag("Your own movement", systemImage: "person.crop.circle")
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

// MARK: - Segments

private struct SegmentStates: View {
  var body: some View {
    CatalogSection("Segments") {
      VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
        HardsetSegmentedControl(
          selection: .constant("kg"),
          segments: [
            HardsetSegment("kg", value: "kg"),
            HardsetSegment("lb", value: "lb"),
          ]
        )
        HardsetSegmentedControl(
          selection: .constant("lb"),
          segments: [
            HardsetSegment("kg", value: "kg"),
            HardsetSegment("lb", value: "lb"),
          ]
        )
        HardsetSegmentedControl(
          selection: .constant(8),
          segments: [
            HardsetSegment("3", value: 3),
            HardsetSegment("8", value: 8),
            HardsetSegment("12", value: 12),
            HardsetSegment("15", value: 15),
          ]
        )
        HardsetSegmentedControl(
          selection: .constant("estimated"),
          segments: [
            HardsetSegment("Heaviest load", value: "heaviest"),
            HardsetSegment("Estimated one-rep max", value: "estimated"),
          ]
        )
        // A pressed segment, selected and unselected, drawn through the shared opacity press.
        HStack(spacing: Tokens.Spacing.hairline) {
          HardsetPressFace(isPressed: true, reduceMotion: false) {
            HardsetSegmentFace(isSelected: true) { Text("kg") }
          }
          HardsetPressFace(isPressed: true, reduceMotion: false) {
            HardsetSegmentFace(isSelected: false) { Text("lb") }
          }
        }
        .hardsetSegmentTrack()
      }
    }
  }
}

#if DEBUG
  #Preview("Chips, all states") {
    ChipCatalogView()
  }
#endif
