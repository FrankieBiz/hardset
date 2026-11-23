import HardsetCore
import SwiftUI

/// Every movement the app knows, grouped by body part, with how many there are in each.
///
/// Movements with no body part come first under a warning header, because that is the gap worth
/// closing: until one is tagged, its sets count toward no muscle and volume says so. Tapping one of
/// the lifter's own movements opens the editor, tagged or not. A movement a workout import created
/// is listed here too, with an "Imported" tag, because this is the only place its body part and
/// equipment can be set; it opens the same editor, with its name fixed. A curated movement is the
/// catalogue's finding, shows a "Curated" tag and does not open it, so nothing that looks tappable
/// does nothing and nothing that is not the lifter's can be retagged.
///
/// The footer is a ledger of the count in every body part, zeros included, so a part with nothing
/// in it reads as nothing rather than being left out. It sums to the number of movements that have
/// a body part; the ones still waiting for one are counted in their own section, not in a part.
///
/// Nothing is boxed. A movement is a row under a hairline: its name, what it trains and, at the
/// trailing edge, its equipment and whose it is as plain words. A movement the lifter can edit ends
/// in a chevron, which is what says it opens; a curated one has none and carries no "Curated" word
/// on screen, because a word repeated on every row says nothing, though its spoken label still says
/// it. The one warning on the screen is a small glyph beside "Needs a body part".
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
      LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
        if sections.isEmpty {
          HardsetEmptyState(
            title: "No movements yet",
            detail: "Movements you add to a workout appear here, grouped by body part.",
            systemImage: "books.vertical",
            style: .quiet
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
          .foregroundStyle(Tokens.Color.warning)
          .accessibilityHidden(true)
        Text("Needs a body part")
          .foregroundStyle(Tokens.Color.chalk)
        Text(section.entries.count, format: .number)
          .monospacedDigit()
          .foregroundStyle(Tokens.Color.chalkDim)
        Spacer(minLength: 0)
      }
      .font(Tokens.Text.sectionHeader)
      .accessibilityElement(children: .combine)
      .accessibilityAddTraits(.isHeader)
    case .category(let category):
      SectionLabel(ExercisePickerView.categoryTitle(for: category), count: section.entries.count)
    }
  }

  // MARK: - Rows

  /// A movement the lifter owns is a button that ends in a chevron; a curated one is plain type
  /// that says nothing it cannot do. Each sits under a hairline, where it meets the row before it.
  @ViewBuilder private func row(_ entry: CatalogEntry) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Rectangle()
        .fill(Tokens.Color.hairline)
        .frame(height: Tokens.Stroke.hairline)
        .accessibilityHidden(true)
      if entry.isCurated {
        rowContent(entry)
          .padding(.vertical, Tokens.Spacing.snug)
          .frame(maxWidth: .infinity, minHeight: Tokens.loggerTapTarget, alignment: .leading)
          // Said as a whole, with the word the screen does not draw, so a curated movement still
          // announces what it is.
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(Self.curatedSpokenLabel(entry))
      } else {
        Button {
          onSelect(entry)
        } label: {
          HStack(alignment: .center, spacing: Tokens.Spacing.regular) {
            rowContent(entry)
            Image(systemName: "chevron.right")
              .font(Tokens.Text.caption.weight(.semibold))
              .foregroundStyle(Tokens.Color.chalkDim)
              .accessibilityHidden(true)
          }
          .padding(.vertical, Tokens.Spacing.snug)
          .frame(maxWidth: .infinity, minHeight: Tokens.loggerTapTarget, alignment: .leading)
        }
        .buttonStyle(
          InlineControlStyle(
            minHeight: Tokens.loggerTapTarget, alignment: .leading, fullWidth: true)
        )
        .accessibilityElement(children: .combine)
        .accessibilityHint(entry.primaryMuscle.isAttributed ? "Edits its muscles" : "Choose its body part")
      }
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
          HStack(spacing: Tokens.Spacing.regular) { marks(for: entry) }
            .padding(.top, Tokens.Spacing.tight)
        }
      }
      .multilineTextAlignment(.leading)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)

      if !dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .trailing, spacing: Tokens.Spacing.hairline) { marks(for: entry) }
      }
    }
  }

  /// The equipment, and whose the movement is, as plain `caption` words in `chalkDim`: no capsule,
  /// no fill. A curated movement says only its equipment, because "Curated" on every one of them
  /// tells the lifter nothing.
  @ViewBuilder private func marks(for entry: CatalogEntry) -> some View {
    if let modality = entry.modality {
      Text(modality.label)
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.chalkDim)
    }
    if entry.isImported {
      Label("Imported", systemImage: "square.and.arrow.down")
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.chalkDim)
    } else if !entry.isCurated {
      Label("Custom", systemImage: "person.crop.circle")
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.chalkDim)
    }
  }

  /// "Barbell Back Squat, Quads, also Glutes, Barbell, Curated": what the row draws, plus the word it
  /// leaves out.
  static func curatedSpokenLabel(_ entry: CatalogEntry) -> String {
    [entry.name, detail(for: entry), entry.modality?.label, "Curated"]
      .compactMap { $0 }
      .joined(separator: ", ")
  }

  /// "Lats, also biceps", or the plain fact that nothing says what it trains. A movement of the
  /// lifter's with no equipment on record says so too: an imported one has none until they say, and
  /// no max is estimated for it, which the tag row cannot say by leaving something out.
  static func detail(for entry: CatalogEntry) -> String {
    let muscles = muscleDetail(for: entry)
    guard entry.modality == nil, !entry.isCurated else { return muscles }
    return muscles + " · Equipment not set"
  }

  private static func muscleDetail(for entry: CatalogEntry) -> String {
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
