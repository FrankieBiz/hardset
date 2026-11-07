import HardsetCore
import SwiftUI

/// Picks a movement to add to the session.
///
/// Search is handed in as a binding and filtering is the caller's job, because the caller is the
/// one holding the database. This view sorts and groups what it is given, provides an intuitive
/// anatomical region filter rail, and reports choices.
///
/// Grouped by the muscle a movement primarily trains, because that is how a lifter looking at a
/// plan thinks about a gap — "I have nothing for hamstrings" — rather than alphabetically.
///
/// Each row is one 56 pt target: the name, the "also …" credit line beneath it, and the modality
/// as a tag, which is filled but not outlined because it is not something to tap. The empty state
/// only offers to create a movement when the caller can actually create one.
public struct ExercisePickerView: View {
  @Binding private var query: String
  private let entries: [CatalogEntry]
  private let onCreate: ((String) -> Void)?
  private let onSelect: (CatalogEntry) -> Void

  @State private var selectedCategory: MuscleFilterCategory?
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  public init(
    query: Binding<String>,
    entries: [CatalogEntry],
    onCreate: ((String) -> Void)? = nil,
    onSelect: @escaping (CatalogEntry) -> Void
  ) {
    self._query = query
    self.entries = entries
    self.onCreate = onCreate
    self.onSelect = onSelect
  }

  public var body: some View {
    VStack(spacing: 0) {
      // Search and the region rail stay put while the list scrolls beneath them.
      VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
        HardsetSearchField(text: $query, prompt: "Search movements")
          .padding(.horizontal, Tokens.Spacing.loose)

        filterRail
      }
      .padding(.top, Tokens.Spacing.snug)
      .background(Tokens.Color.background)

      if displayedEntries.isEmpty {
        emptyState
      } else {
        movementList
      }
    }
    .background(Tokens.Color.background)
  }

  // MARK: - Anatomical filter rail

  private var filterRail: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: Tokens.Spacing.snug) {
        HardsetChip("All", isSelected: selectedCategory == nil) {
          selectedCategory = nil
        }

        ForEach(MuscleFilterCategory.allCases, id: \.rawValue) { category in
          HardsetChip(
            Self.categoryTitle(for: category),
            isSelected: selectedCategory == category
          ) {
            // A second tap on the active chip clears it, so "All" is never more than one tap away.
            if selectedCategory == category {
              selectedCategory = nil
            } else {
              selectedCategory = category
            }
          }
        }
      }
      .padding(.horizontal, Tokens.Spacing.loose)
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Filter by body region")
  }

  // MARK: - Movement list

  private var movementList: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
        ForEach(sections) { section in
          Section {
            VStack(spacing: Tokens.Spacing.snug) {
              ForEach(section.entries) { entry in
                row(entry)
              }
            }
            .padding(.horizontal, Tokens.Spacing.loose)
            .padding(.bottom, Tokens.Spacing.section)
          } header: {
            SectionLabel(Self.displayName(section.key), count: section.entries.count)
              .padding(.horizontal, Tokens.Spacing.loose)
              .padding(.vertical, Tokens.Spacing.snug)
              // Opaque, because the header is pinned and rows scroll underneath it.
              .background(Tokens.Color.background)
          }
        }
      }
      .padding(.top, Tokens.Spacing.tight)
    }
    .scrollDismissesKeyboard(.interactively)
  }

  // MARK: - Exercise row

  private func row(_ entry: CatalogEntry) -> some View {
    Button {
      onSelect(entry)
    } label: {
      HStack(alignment: .center, spacing: Tokens.Spacing.regular) {
        VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
          Text(entry.name)
            .font(Tokens.Text.headline)
            .foregroundStyle(Tokens.Color.textPrimary)

          if let alsoTrains = supportingText(for: entry) {
            Text(alsoTrains)
              .font(Tokens.Text.provenance)
              .foregroundStyle(Tokens.Color.textSecondary)
          }

          // At accessibility text sizes the tags move under the name instead of squeezing it
          // into a column one word wide.
          if stacksTags, hasTags(entry) {
            HStack(spacing: Tokens.Spacing.tight) {
              tags(for: entry)
            }
            .padding(.top, Tokens.Spacing.tight)
          }
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)

        if !stacksTags, hasTags(entry) {
          VStack(alignment: .trailing, spacing: Tokens.Spacing.tight) {
            tags(for: entry)
          }
        }
      }
      .padding(.horizontal, Tokens.Spacing.regular)
      .padding(.vertical, Tokens.Spacing.snug)
      // Inside the label, so the 56 pt frame and the tappable shape are the same rectangle.
      .frame(maxWidth: .infinity, minHeight: Tokens.loggerTapTarget, alignment: .leading)
      .contentShape(RoundedRectangle(cornerRadius: Tokens.Radius.control))
    }
    .buttonStyle(SelectionCardButtonStyle(isSelected: false))
    .accessibilityElement(children: .combine)
    .accessibilityLabel(rowSpokenLabel(for: entry))
    .accessibilityHint("Adds it to this workout")
  }

  @ViewBuilder
  private func tags(for entry: CatalogEntry) -> some View {
    if let modality = entry.modality {
      SelectionTag(modality.label)
    }
    if !entry.isCurated {
      SelectionTag("Custom", systemImage: "person.crop.circle")
        .accessibilityLabel("Your own movement")
    }
  }

  private func hasTags(_ entry: CatalogEntry) -> Bool {
    entry.modality != nil || !entry.isCurated
  }

  private var stacksTags: Bool { dynamicTypeSize.isAccessibilitySize }

  /// The public spoken label plus the credit line, so VoiceOver hears what the row shows.
  private func rowSpokenLabel(for entry: CatalogEntry) -> String {
    [Self.spokenLabel(for: entry), supportingText(for: entry)]
      .compactMap { $0 }
      .joined(separator: ", ")
  }

  // MARK: - Empty state

  private var emptyState: some View {
    ScrollView {
      VStack(spacing: Tokens.Spacing.regular) {
        HardsetEmptyState(
          title: "No movement found",
          detail: emptyStateDetail,
          systemImage: "magnifyingglass",
          actionTitle: createAction == nil ? nil : "Add “\(trimmedQuery)” as a movement",
          action: createAction
        )

        if isHiddenByFilter {
          Button("Show all regions") {
            selectedCategory = nil
          }
          .buttonStyle(HardsetButtonStyle(.secondary, fullWidth: false))
        }
      }
      .frame(maxWidth: .infinity)
      .padding(.top, Tokens.Spacing.section)
    }
    .scrollDismissesKeyboard(.interactively)
  }

  /// The create action, or `nil` when there is nothing honest to offer.
  ///
  /// Offered only when the caller supplied `onCreate`. The live session passes none, and the
  /// empty state used to show "Add as movement" anyway: a button that did nothing when tapped.
  /// Also withheld when the region filter is what emptied the list, because the movement may well
  /// exist under another region, and a duplicate would split its history in two.
  private var createAction: (() -> Void)? {
    guard let onCreate, !isHiddenByFilter else { return nil }
    let name = trimmedQuery
    guard !name.isEmpty else { return nil }
    return { onCreate(name) }
  }

  /// True when the caller found movements and only the region filter is hiding them.
  private var isHiddenByFilter: Bool {
    selectedCategory != nil && !entries.isEmpty
  }

  private var trimmedQuery: String {
    query.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var emptyStateDetail: String {
    let name = trimmedQuery
    if let selectedCategory, !entries.isEmpty {
      let region = Self.categoryTitle(for: selectedCategory)
      if name.isEmpty {
        return "No movements are filed under \(region)."
      }
      return "Nothing under \(region) matches “\(name)”. Other regions have matches."
    }
    if !name.isEmpty {
      return "Nothing in the catalogue matches “\(name)”."
    }
    return "The movement catalogue is empty."
  }

  // MARK: - Data grouping & filtering

  private var displayedEntries: [CatalogEntry] {
    if let selectedCategory {
      return entries.filter { selectedCategory.matches($0.primaryMuscle) }
    }
    return entries
  }

  private struct MuscleSection: Identifiable {
    let key: MuscleKey
    let entries: [CatalogEntry]
    var id: String { key.storedValue }
  }

  private var sections: [MuscleSection] {
    let grouped = Dictionary(grouping: displayedEntries, by: \.primaryMuscle)
    let index = Dictionary(uniqueKeysWithValues: Muscle.allCases.enumerated().map { ($1, $0) })
    return grouped
      .map { MuscleSection(key: $0.key, entries: $0.value.sorted { $0.name < $1.name }) }
      .sorted { lhs, rhs in
        let l = lhs.key.muscle.map { index[$0] ?? Int.max } ?? Int.max
        let r = rhs.key.muscle.map { index[$0] ?? Int.max } ?? Int.max
        if l != r { return l < r }
        return lhs.key.storedValue < rhs.key.storedValue
      }
  }

  private func supportingText(for entry: CatalogEntry) -> String? {
    let others = entry.creditedMuscles.filter { $0.key != entry.primaryMuscle }
    guard !others.isEmpty else { return nil }
    return "also " + others.map { Self.displayName($0.key) }.joined(separator: ", ")
  }

  // MARK: - Display Names & Localisation Seams

  public static func categoryTitle(for category: MuscleFilterCategory) -> String {
    switch category {
    case .chest: "Chest"
    case .shoulders: "Shoulders"
    case .back: "Back"
    case .arms: "Arms"
    case .core: "Core"
    case .quads: "Quads"
    case .hamstrings: "Hamstrings"
    case .glutes: "Glutes"
    case .hips: "Hips"
    case .calves: "Calves"
    case .neck: "Neck"
    }
  }

  public static func displayName(_ key: MuscleKey) -> String {
    if let muscle = key.muscle { return Self.copy[muscle] ?? muscle.rawValue }
    return key.isReservedSentinel ? "Not attributed" : "Not recognised"
  }

  private static let copy: [Muscle: String] = [
    .chest: "Chest", .frontDelts: "Front delts", .sideDelts: "Side delts",
    .rearDelts: "Rear delts", .rotatorCuff: "Rotator cuff", .lats: "Lats",
    .upperBack: "Upper back", .traps: "Traps", .lowerBack: "Lower back",
    .biceps: "Biceps", .triceps: "Triceps", .forearms: "Forearms",
    .abs: "Abs", .obliques: "Obliques", .neck: "Neck",
    .quadriceps: "Quads", .hamstrings: "Hamstrings", .glutes: "Glutes",
    .adductors: "Adductors", .hipAbductors: "Hip abductors",
    .gastrocnemius: "Gastrocnemius", .soleus: "Soleus",
  ]

  public static func spokenLabel(for entry: CatalogEntry) -> String {
    var parts = [entry.name, displayName(entry.primaryMuscle)]
    if let modality = entry.modality { parts.append(modality.label) }
    if !entry.isCurated { parts.append("your own movement") }
    return parts.joined(separator: ", ")
  }
}

#if DEBUG
  private struct ExercisePickerHarness: View {
    private let allowsCreate: Bool
    @State private var query: String

    init(query: String = "", allowsCreate: Bool = true) {
      self.allowsCreate = allowsCreate
      self._query = State(initialValue: query)
    }

    private var entries: [CatalogEntry] {
      ExerciseCatalog.v1
        .compactMap(\.catalogEntry)
        .filter {
          query.isEmpty
            || $0.name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    var body: some View {
      NavigationStack {
        ExercisePickerView(
          query: $query,
          entries: entries,
          onCreate: allowsCreate ? { (_: String) in } : nil
        ) { _ in }
        .hardsetNavigationTitle("Add movement")
      }
    }
  }

  #Preview("Exercise picker") {
    ExercisePickerHarness()
  }

  #Preview("Exercise picker, no match, can create") {
    ExercisePickerHarness(query: "Zercher carry")
  }

  #Preview("Exercise picker, no match, cannot create") {
    // The live session's configuration: no `onCreate`, so the empty state offers no button.
    ExercisePickerHarness(query: "Zercher carry", allowsCreate: false)
  }
#endif
