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
public struct ExercisePickerView: View {
  @Binding private var query: String
  private let entries: [CatalogEntry]
  private let onCreate: ((String) -> Void)?
  private let onSelect: (CatalogEntry) -> Void

  @State private var selectedCategory: MuscleFilterCategory?

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
      // Top search & anatomical filter header
      VStack(spacing: Tokens.Spacing.snug) {
        HardsetSearchField(text: $query, prompt: "Search movements")
          .padding(.horizontal, Tokens.Spacing.loose)
          .padding(.top, Tokens.Spacing.tight)

        filterChipsRail
      }
      .padding(.bottom, Tokens.Spacing.snug)
      .background(Tokens.Color.background)

      // Exercise List or Empty State
      if displayedEntries.isEmpty {
        ScrollView {
          VStack {
            Spacer(minLength: Tokens.Spacing.loose)

            HardsetEmptyState(
              title: "No movement found",
              detail: emptyStateDetail,
              systemImage: "magnifyingglass",
              actionTitle: query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : "Add “\(query.trimmingCharacters(in: .whitespacesAndNewlines))” as movement",
              action: {
                let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { onCreate?(trimmed) }
              }
            )

            Spacer(minLength: Tokens.Spacing.loose)
          }
          .padding(.top, Tokens.Spacing.section)
        }
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: Tokens.Spacing.loose, pinnedViews: [.sectionHeaders]) {
            ForEach(groups) { group in
              Section {
                VStack(spacing: Tokens.Spacing.tight) {
                  ForEach(group.entries) { entry in
                    row(entry)
                  }
                }
                .padding(.horizontal, Tokens.Spacing.loose)
              } header: {
                sectionHeader(group.key)
              }
            }
          }
          .padding(.top, Tokens.Spacing.snug)
          .padding(.bottom, Tokens.Spacing.section)
        }
      }
    }
    .background(Tokens.Color.background)
  }

  // MARK: - Anatomical Filter Rail

  private var filterChipsRail: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: Tokens.Spacing.tight) {
        chip(title: "All", isSelected: selectedCategory == nil) {
          selectedCategory = nil
        }

        ForEach(MuscleFilterCategory.allCases, id: \.rawValue) { category in
          chip(
            title: Self.categoryTitle(for: category),
            isSelected: selectedCategory == category
          ) {
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
  }

  private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title)
        .font(Tokens.Text.caption.weight(isSelected ? .semibold : .medium))
        .foregroundStyle(isSelected ? Tokens.Color.background : Tokens.Color.textPrimary)
        .padding(.horizontal, Tokens.Spacing.regular)
        .padding(.vertical, 6)
        .background(
          isSelected ? Tokens.Color.accent : Tokens.Color.surfaceRaised,
          in: Capsule()
        )
        .overlay(
          Capsule()
            .strokeBorder(
              isSelected ? Tokens.Color.accent : Tokens.Color.border,
              lineWidth: Tokens.Stroke.hairline
            )
        )
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
  }

  // MARK: - Section Header

  private func sectionHeader(_ key: MuscleKey) -> some View {
    HStack {
      Text(sectionTitle(key).uppercased())
        .font(Tokens.Text.sectionHeader)
        .foregroundStyle(Tokens.Color.textSecondary)
        .tracking(0.5)

      Spacer()
    }
    .padding(.horizontal, Tokens.Spacing.loose)
    .padding(.vertical, Tokens.Spacing.tight)
    .background(Tokens.Color.background.opacity(0.95))
  }

  // MARK: - Exercise Row

  private func row(_ entry: CatalogEntry) -> some View {
    Button {
      onSelect(entry)
    } label: {
      HStack(spacing: Tokens.Spacing.regular) {
        VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
          Text(entry.name)
            .font(Tokens.Text.rowTitle.weight(.medium))
            .foregroundStyle(Tokens.Color.textPrimary)

          if !supportingText(for: entry).isEmpty {
            Text(supportingText(for: entry))
              .font(Tokens.Text.caption)
              .foregroundStyle(Tokens.Color.textSecondary)
              .lineLimit(1)
          }
        }

        Spacer(minLength: Tokens.Spacing.snug)

        if let modality = entry.modality {
          Text(modality.label)
            .font(Tokens.Text.caption.weight(.medium))
            .foregroundStyle(Tokens.Color.textSecondary)
            .padding(.horizontal, Tokens.Spacing.snug)
            .padding(.vertical, 3)
            .background(
              Tokens.Color.surfaceRaised,
              in: RoundedRectangle(cornerRadius: Tokens.Radius.control / 2)
            )
            .overlay(
              RoundedRectangle(cornerRadius: Tokens.Radius.control / 2)
                .strokeBorder(Tokens.Color.border, lineWidth: Tokens.Stroke.hairline)
            )
        }

        if !entry.isCurated {
          Image(systemName: "person.crop.circle.fill")
            .font(.system(size: 14))
            .foregroundStyle(Tokens.Color.accent)
            .accessibilityLabel("Custom movement")
        }
      }
      .padding(.horizontal, Tokens.Spacing.regular)
      .padding(.vertical, Tokens.Spacing.snug)
      .frame(minHeight: Tokens.loggerTapTarget)
      .contentShape(Rectangle())
      .hardsetCard(cornerRadius: Tokens.Radius.control)
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(Self.spokenLabel(for: entry))
    .accessibilityHint("Double tap to add to this workout.")
  }

  // MARK: - Data Grouping & Filtering

  private var displayedEntries: [CatalogEntry] {
    if let selectedCategory {
      return entries.filter { selectedCategory.matches($0.primaryMuscle) }
    }
    return entries
  }

  private var emptyStateDetail: String {
    if !query.isEmpty {
      return "Nothing in the catalogue matches “\(query)”."
    }
    if let selectedCategory {
      return "No movements recorded for \(Self.categoryTitle(for: selectedCategory))."
    }
    return "The movement catalogue is empty."
  }

  private struct Group: Identifiable {
    let key: MuscleKey
    let entries: [CatalogEntry]
    var id: String { key.storedValue }
  }

  private var groups: [Group] {
    let grouped = Dictionary(grouping: displayedEntries, by: \.primaryMuscle)
    let index = Dictionary(uniqueKeysWithValues: Muscle.allCases.enumerated().map { ($1, $0) })
    return grouped
      .map { Group(key: $0.key, entries: $0.value.sorted { $0.name < $1.name }) }
      .sorted { lhs, rhs in
        let l = lhs.key.muscle.map { index[$0] ?? Int.max } ?? Int.max
        let r = rhs.key.muscle.map { index[$0] ?? Int.max } ?? Int.max
        if l != r { return l < r }
        return lhs.key.storedValue < rhs.key.storedValue
      }
  }

  private func sectionTitle(_ key: MuscleKey) -> String {
    Self.displayName(key)
  }

  private func supportingText(for entry: CatalogEntry) -> String {
    let others = entry.creditedMuscles.filter { $0.key != entry.primaryMuscle }
    guard !others.isEmpty else { return "" }
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
  #Preview("Exercise picker") {
    struct Harness: View {
      @State private var query = ""

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
            onCreate: { _ in }
          ) { _ in }
          .navigationTitle("Add movement")
        }
      }
    }
    return Harness()
  }
#endif
