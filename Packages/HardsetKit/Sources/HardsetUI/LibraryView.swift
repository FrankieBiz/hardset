import HardsetCore
import SwiftUI

/// Every movement the lifter can pick, grouped by body part, with how many there are in each.
///
/// Movements with no body part come first under a warning header, because that is the gap worth
/// closing: until one is tagged, its sets count toward no muscle and volume says so. Tapping one of
/// the lifter's own movements opens the editor, tagged or not. A curated movement is the
/// catalogue's finding, shows a "Curated" tag and does not open it, so nothing that looks tappable
/// does nothing and nothing that is not the lifter's can be retagged.
///
/// The footer is a ledger of the count in every body part, zeros included, so a part with nothing
/// in it reads as nothing rather than being left out. It sums to the number of movements that have
/// a body part; the ones still waiting for one are counted in their own section, not in a part.
///
/// Draws only its scrolling content. The screen that hosts it owns the title, the reads and the
/// editor, because those need storage this view does not have.
public struct LibraryView: View {
  private let sections: [LibrarySection]
  private let counts: [(category: MuscleFilterCategory, count: Int)]
  private let onSelect: (CatalogEntry) -> Void

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  /// - Parameters:
  ///   - sections: `LibraryIndex.sections`, in the order to draw them.
  ///   - counts: `LibraryIndex.counts`, one entry per body part.
  ///   - onSelect: Called for a movement the lifter can edit. Never called for a curated one.
  public init(
    sections: [LibrarySection],
    counts: [(category: MuscleFilterCategory, count: Int)],
    onSelect: @escaping (CatalogEntry) -> Void
  ) {
    self.sections = sections
    self.counts = counts
    self.onSelect = onSelect
  }

  public var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: Tokens.Spacing.snug, pinnedViews: [.sectionHeaders]) {
        if sections.isEmpty {
          HardsetEmptyState(
            title: "No movements yet",
            detail: "Movements you add to a workout appear here, grouped by body part.",
            systemImage: "books.vertical"
          )
        }
        ForEach(sections) { section in
          Section {
            ForEach(section.entries) { entry in
              row(entry)
                .padding(.horizontal, Tokens.Spacing.loose)
            }
          } header: {
            header(for: section)
              .padding(.horizontal, Tokens.Spacing.loose)
              .padding(.top, Tokens.Spacing.loose)
              .padding(.bottom, Tokens.Spacing.snug)
              // Opaque, because the header is pinned and rows scroll underneath it.
              .background(Tokens.Color.canvas)
          }
        }
        if !sections.isEmpty {
          footer
            .padding(.horizontal, Tokens.Spacing.loose)
            .padding(.top, Tokens.Spacing.section)
        }
      }
      .padding(.top, Tokens.Spacing.snug)
      .padding(.bottom, Tokens.Spacing.block)
    }
    .background(Tokens.Color.canvas)
  }

  // MARK: - Sections

  @ViewBuilder private func header(for section: LibrarySection) -> some View {
    switch section.kind {
    case .needsBodyPart:
      HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.snug) {
        Image(systemName: "exclamationmark.triangle")
          .accessibilityHidden(true)
        Text("Needs a body part")
        Text(section.entries.count, format: .number)
          .monospacedDigit()
        Spacer(minLength: 0)
      }
      .font(Tokens.Text.sectionHeader)
      .foregroundStyle(Tokens.Color.warning)
      .accessibilityElement(children: .combine)
      .accessibilityAddTraits(.isHeader)
    case .category(let category):
      SectionLabel(ExercisePickerView.categoryTitle(for: category), count: section.entries.count)
    }
  }

  // MARK: - Rows

  /// A movement the lifter owns is a button; a curated one is a flat card that says what it is.
  @ViewBuilder private func row(_ entry: CatalogEntry) -> some View {
    if entry.isCurated {
      rowContent(entry)
        .padding(.horizontal, Tokens.Spacing.regular)
        .padding(.vertical, Tokens.Spacing.snug)
        .frame(maxWidth: .infinity, minHeight: Tokens.loggerTapTarget, alignment: .leading)
        .hardsetCard(cornerRadius: Tokens.Radius.control)
        .accessibilityElement(children: .combine)
    } else {
      Button {
        onSelect(entry)
      } label: {
        rowContent(entry)
          .padding(.horizontal, Tokens.Spacing.regular)
          .padding(.vertical, Tokens.Spacing.snug)
          .frame(maxWidth: .infinity, minHeight: Tokens.loggerTapTarget, alignment: .leading)
          .contentShape(RoundedRectangle(cornerRadius: Tokens.Radius.control))
      }
      .buttonStyle(SelectionCardButtonStyle(isSelected: false))
      .accessibilityElement(children: .combine)
      .accessibilityHint(entry.primaryMuscle.isAttributed ? "Edits its muscles" : "Choose its body part")
    }
  }

  private func rowContent(_ entry: CatalogEntry) -> some View {
    HStack(alignment: .center, spacing: Tokens.Spacing.regular) {
      VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
        Text(entry.name)
          .font(Tokens.Text.headline)
          .foregroundStyle(Tokens.Color.chalk)
        Text(Self.detail(for: entry))
          .font(Tokens.Text.provenance)
          .foregroundStyle(Tokens.Color.chalkDim)
        if dynamicTypeSize.isAccessibilitySize {
          HStack(spacing: Tokens.Spacing.tight) { tags(for: entry) }
            .padding(.top, Tokens.Spacing.tight)
        }
      }
      .multilineTextAlignment(.leading)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)

      if !dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .trailing, spacing: Tokens.Spacing.tight) { tags(for: entry) }
      }
    }
  }

  @ViewBuilder private func tags(for entry: CatalogEntry) -> some View {
    if let modality = entry.modality {
      HardsetTag(modality.label)
    }
    if entry.isCurated {
      HardsetTag("Curated")
    } else {
      HardsetTag("Custom", systemImage: "person.crop.circle")
    }
  }

  /// "Lats, also biceps", or the plain fact that nothing says what it trains.
  static func detail(for entry: CatalogEntry) -> String {
    guard entry.primaryMuscle.isAttributed else { return "No body part yet" }
    let primary = ExercisePickerView.displayName(entry.primaryMuscle)
    let others = entry.creditedMuscles.filter { $0.key != entry.primaryMuscle }
    guard !others.isEmpty else { return primary }
    return primary + ", also " + others.map { ExercisePickerView.displayName($0.key) }.joined(separator: ", ")
  }

  // MARK: - Footer ledger

  private var footer: some View {
    VStack(alignment: .leading, spacing: 0) {
      SectionLabel("Movements by body part", count: counts.reduce(0) { $0 + $1.count })
        .padding(.bottom, Tokens.Spacing.snug)
      ForEach(Array(counts.enumerated()), id: \.offset) { item in
        let entry = item.element
        HStack(alignment: .firstTextBaseline) {
          Text(ExercisePickerView.categoryTitle(for: entry.category))
            .font(Tokens.Text.label)
            .foregroundStyle(entry.count == 0 ? Tokens.Color.chalkDim : Tokens.Color.chalk)
          Spacer(minLength: Tokens.Spacing.regular)
          Text(entry.count, format: .number)
            .font(Tokens.Text.figure)
            .foregroundStyle(entry.count == 0 ? Tokens.Color.chalkDim : Tokens.Color.chalk)
        }
        .padding(.vertical, Tokens.Spacing.snug)
        .overlay(alignment: .top) {
          Rectangle().fill(Tokens.Color.hairline).frame(height: Tokens.Stroke.hairline)
        }
        .accessibilityElement(children: .combine)
      }
    }
  }
}

#if DEBUG
  #Preview("Library") {
    let entries = [
      CatalogEntry(
        id: ExerciseID(), name: "Nautilus lever row", slug: nil, isCurated: false,
        modality: .machine, primaryMuscle: MuscleKey(.lats),
        contributions: [
          MuscleContribution(.lats, role: .direct, certainty: .moderate, source: .user),
          MuscleContribution(.biceps, role: .indirect, certainty: .moderate, source: .user),
        ]),
      CatalogEntry(
        id: ExerciseID(), name: "Pendulum squat", slug: nil, isCurated: false, modality: nil,
        primaryMuscle: MuscleKey(stored: MuscleKey.notAttributedRawValue), contributions: []),
    ]
    return LibraryView(
      sections: LibraryIndex.sections(entries), counts: LibraryIndex.counts(entries),
      onSelect: { _ in }
    )
  }
#endif
