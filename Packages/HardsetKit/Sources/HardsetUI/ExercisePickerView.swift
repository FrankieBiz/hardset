import HardsetCore
import SwiftUI

/// Picks a movement to add to the session.
///
/// Search is handed in as a binding and filtering is the caller's job, because the caller is the
/// one holding the database. This view sorts and groups what it is given, provides an intuitive
/// anatomical region filter rail, and reports choices.
///
/// Grouped by the muscle a movement primarily trains, because that is how a lifter looking at a
/// plan thinks about a gap — "I have nothing for hamstrings" — rather than alphabetically. Before
/// anything is typed, the movements the lifter logged most recently come first: every workout
/// starts empty, so rebuilding a usual session should be a tap per movement, not a search.
///
/// Each row is one 56 pt target: the name, the "also …" credit line beneath it, and the modality
/// as a tag, which is filled but not outlined because it is not something to tap. The picker
/// only offers to create a movement when the caller can actually create one, and then whenever
/// the search has no exact match. A failed read or save is stated in an error banner, never shown
/// as an empty catalogue.
public struct ExercisePickerView: View {
  @Binding private var query: String
  private let entries: [CatalogEntry]
  private let recent: [CatalogEntry]
  private let errorMessage: String?
  private let onCancel: (() -> Void)?
  private let onCreate: ((String) -> Void)?
  private let onSelect: (CatalogEntry) -> Void

  @State private var selectedCategory: MuscleFilterCategory?
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  /// - Parameters:
  ///   - entries: The caller's search results for `query`, in any order.
  ///   - recent: Movements the lifter logged most recently, newest first. Shown above the muscle
  ///     sections while the search is empty, narrowed by the region filter like everything else.
  ///   - errorMessage: A failed read or save, in the lifter's words. Shown as an error banner
  ///     under the search field; while it is set, an empty list is not described as empty.
  ///   - onCancel: Closes the picker without choosing. When set, the picker draws "Cancel" in the
  ///     toolbar's cancellation position, so the caller should not draw its own.
  ///   - onCreate: Adds a movement with the typed, trimmed name. When `nil`, no add is offered.
  public init(
    query: Binding<String>,
    entries: [CatalogEntry],
    recent: [CatalogEntry] = [],
    errorMessage: String? = nil,
    onCancel: (() -> Void)? = nil,
    onCreate: ((String) -> Void)? = nil,
    onSelect: @escaping (CatalogEntry) -> Void
  ) {
    self._query = query
    self.entries = entries
    self.recent = recent
    self.errorMessage = errorMessage
    self.onCancel = onCancel
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

        // Pinned with the search field rather than scrolled with the list, so a failure cannot be
        // scrolled out of sight.
        if let visibleErrorMessage {
          HardsetBanner(.error, message: visibleErrorMessage)
            .padding(.horizontal, Tokens.Spacing.loose)
            .padding(.top, Tokens.Spacing.tight)
        }
      }
      .padding(.top, Tokens.Spacing.snug)
      .background(Tokens.Color.background)

      if hasRows {
        movementList
      } else if isAwaitingFirstRead {
        HardsetLoadingState("Reading your movements…")
      } else if visibleErrorMessage != nil {
        failureState
      } else {
        emptyState
      }
    }
    .background(Tokens.Color.background)
    .pickerCancelAction(onCancel)
    // A swipe down closes the sheet without passing through Cancel, and the search used to survive
    // it, so the next "Add movement" opened on a stale filter. Cleared on every way out.
    .onDisappear { query = "" }
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
        if !displayedRecent.isEmpty {
          Section {
            rowStack(displayedRecent)
          } header: {
            sectionHeader("Recent", count: displayedRecent.count)
          }
        }

        ForEach(sections) { section in
          Section {
            rowStack(section.entries)
          } header: {
            sectionHeader(Self.displayName(section.key), count: section.entries.count)
          }
        }

        // After the matches, not above them: a partial match ("bench") is usually the movement
        // the lifter meant, and the first row should not be the one that makes a duplicate.
        if let createAction {
          VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
            SectionLabel("Not on the list")
            createButton(createAction)
          }
          .padding(.horizontal, Tokens.Spacing.loose)
          .padding(.bottom, Tokens.Spacing.section)
        }
      }
      .padding(.top, Tokens.Spacing.tight)
    }
    .scrollDismissesKeyboard(.interactively)
  }

  private func rowStack(_ rowEntries: [CatalogEntry]) -> some View {
    VStack(spacing: Tokens.Spacing.snug) {
      ForEach(rowEntries) { entry in
        row(entry)
      }
    }
    .padding(.horizontal, Tokens.Spacing.loose)
    .padding(.bottom, Tokens.Spacing.section)
  }

  private func sectionHeader(_ title: String, count: Int) -> some View {
    SectionLabel(title, count: count)
      .padding(.horizontal, Tokens.Spacing.loose)
      .padding(.vertical, Tokens.Spacing.snug)
      // Opaque, because the header is pinned and rows scroll underneath it.
      .background(Tokens.Color.background)
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
        if isHiddenByFilter {
          // The movement may well exist under another region, so looking there is the first
          // offer, and adding one of the lifter's own is the second.
          HardsetEmptyState(
            title: "No movement found",
            detail: emptyStateDetail,
            systemImage: "magnifyingglass",
            actionTitle: "Show all regions",
            actionSystemImage: "line.3.horizontal.decrease",
            action: { selectedCategory = nil }
          )

          if let createAction {
            createButton(createAction, fullWidth: false)
              .padding(.horizontal, Tokens.Spacing.section)
          }
        } else {
          HardsetEmptyState(
            title: "No movement found",
            detail: emptyStateDetail,
            systemImage: "magnifyingglass",
            actionTitle: createAction == nil ? nil : createTitle,
            action: createAction
          )
        }
      }
      .frame(maxWidth: .infinity)
      .padding(.top, Tokens.Spacing.section)
    }
    .scrollDismissesKeyboard(.interactively)
  }

  /// What sits under the error banner when there are no rows to show.
  ///
  /// Claims nothing about the catalogue: after a failed read, "nothing matches" or "the catalogue
  /// is empty" would be a statement about the lifter's data that the app could not check. The add
  /// action stays, because a failed save is retried from here.
  private var failureState: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
        if let createAction {
          createButton(createAction)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, Tokens.Spacing.loose)
      .padding(.top, Tokens.Spacing.section)
    }
    .scrollDismissesKeyboard(.interactively)
  }

  /// "Add “…” as a custom movement", drawn like "Add a machine": a plainly styled action rather
  /// than a row pretending to be a movement.
  private func createButton(_ action: @escaping () -> Void, fullWidth: Bool = true) -> some View {
    Button(action: action) {
      Label {
        Text(createTitle)
      } icon: {
        Image(systemName: "plus")
          .foregroundStyle(Tokens.Color.accent)
      }
    }
    .buttonStyle(HardsetButtonStyle(.secondary, size: .logger, fullWidth: fullWidth))
  }

  private var createTitle: String {
    "Add “\(trimmedQuery)” as a custom movement"
  }

  /// The create action, or `nil` when there is nothing honest to offer.
  ///
  /// Offered only when the caller supplied `onCreate`. The live session once passed none, and the
  /// empty state used to show "Add as movement" anyway: a button that did nothing when tapped.
  /// Withheld when a movement already has exactly this name, ignoring case and accents, because a
  /// duplicate would split its history in two; a partial match ("bench" for "Barbell Bench
  /// Press") still offers it, below the matches. When the region filter is what emptied the list,
  /// it comes second, after "Show all regions", because the movement may exist under another
  /// region.
  private var createAction: (() -> Void)? {
    guard let onCreate else { return nil }
    let name = trimmedQuery
    guard !name.isEmpty, !hasExactMatch(for: name) else { return nil }
    return { onCreate(name) }
  }

  private func hasExactMatch(for name: String) -> Bool {
    (entries + recent).contains {
      $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
        .compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
  }

  /// True when the caller found movements and only the region filter is hiding them.
  private var isHiddenByFilter: Bool {
    selectedCategory != nil && !entries.isEmpty
  }

  private var trimmedQuery: String {
    query.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var visibleErrorMessage: String? {
    guard let errorMessage else { return nil }
    let trimmed = errorMessage.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  /// True while there is something to list: a recent movement or a match the filter lets through.
  private var hasRows: Bool {
    !displayedEntries.isEmpty || !displayedRecent.isEmpty
  }

  /// True before the caller's first read has come back.
  ///
  /// The curated catalogue is seeded before a workout can be started, so an unfiltered,
  /// error-free and completely empty list is not a fact about the catalogue: it is a read still in
  /// flight. That frame used to say "The movement catalogue is empty." DESIGN.md: never an empty
  /// state before a read has succeeded.
  private var isAwaitingFirstRead: Bool {
    entries.isEmpty && recent.isEmpty && trimmedQuery.isEmpty && visibleErrorMessage == nil
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
    // Reached only through an edge such as recent movements with no catalogue rows; the empty
    // first frame is `isAwaitingFirstRead`, and a failed read is `failureState`.
    return "No movements to show."
  }

  // MARK: - Data grouping & filtering

  private var displayedEntries: [CatalogEntry] {
    if let selectedCategory {
      return entries.filter { selectedCategory.matches($0.primaryMuscle) }
    }
    return entries
  }

  /// The recent movements to list first: only while nothing is typed, because once there is a
  /// query the matches are the answer; narrowed by the region filter like every other row; in the
  /// caller's newest-first order, without repeats.
  ///
  /// They also stay in their muscle section below, so the catalogue reads the same with or
  /// without a history.
  private var displayedRecent: [CatalogEntry] {
    guard trimmedQuery.isEmpty else { return [] }
    var seen = Set<ExerciseID>()
    return recent.filter { entry in
      guard seen.insert(entry.id).inserted else { return false }
      guard let selectedCategory else { return true }
      return selectedCategory.matches(entry.primaryMuscle)
    }
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
    private let hasHistory: Bool
    private let readFails: Bool
    @State private var query: String

    init(
      query: String = "", allowsCreate: Bool = true, hasHistory: Bool = false,
      readFails: Bool = false
    ) {
      self.allowsCreate = allowsCreate
      self.hasHistory = hasHistory
      self.readFails = readFails
      self._query = State(initialValue: query)
    }

    private var catalogue: [CatalogEntry] {
      readFails ? [] : ExerciseCatalog.v1.compactMap(\.catalogEntry)
    }

    private var entries: [CatalogEntry] {
      catalogue.filter {
        query.isEmpty
          || $0.name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
      }
    }

    var body: some View {
      NavigationStack {
        ExercisePickerView(
          query: $query,
          entries: entries,
          recent: hasHistory ? Array(catalogue.prefix(3)) : [],
          errorMessage: readFails
            ? "Your movements could not be read. Close this and try again." : nil,
          onCancel: {},
          onCreate: allowsCreate ? { (_: String) in } : nil
        ) { _ in }
        .hardsetNavigationTitle("Add movement")
      }
    }
  }

  #Preview("Exercise picker") {
    ExercisePickerHarness()
  }

  #Preview("Exercise picker, recent first") {
    ExercisePickerHarness(hasHistory: true)
  }

  #Preview("Exercise picker, partial match, can create") {
    // Matches are listed first; "Add “bench” as a custom movement" follows them.
    ExercisePickerHarness(query: "bench")
  }

  #Preview("Exercise picker, no match, can create") {
    ExercisePickerHarness(query: "Zercher carry")
  }

  #Preview("Exercise picker, no match, cannot create") {
    // A caller with no `onCreate`: the empty state offers no button.
    ExercisePickerHarness(query: "Zercher carry", allowsCreate: false)
  }

  #Preview("Exercise picker, read failed") {
    // The banner says what happened; nothing claims the catalogue is empty.
    ExercisePickerHarness(readFails: true)
  }
#endif
