import HardsetCore
import SwiftUI

/// Picks a movement to add to the session.
///
/// Search is handed in as a binding and filtering is the caller's job, because the caller is the
/// one holding the database. This view sorts and groups what it is given, and reports a choice.
///
/// Grouped by the muscle a movement primarily trains, because that is how a lifter looking at a
/// plan thinks about a gap — "I have nothing for hamstrings" — rather than alphabetically, which
/// only helps someone who already knows the exact name they want. The search field covers that
/// case.
public struct ExercisePickerView: View {
  @Binding private var query: String
  private let entries: [CatalogEntry]
  private let onSelect: (CatalogEntry) -> Void

  public init(
    query: Binding<String>,
    entries: [CatalogEntry],
    onSelect: @escaping (CatalogEntry) -> Void
  ) {
    self._query = query
    self.entries = entries
    self.onSelect = onSelect
  }

  public var body: some View {
    List {
      if entries.isEmpty {
        // Names the query rather than showing a bare "No results", and offers the action that
        // actually resolves it.
        ContentUnavailableView {
          Label("No movement found", systemImage: "magnifyingglass")
        } description: {
          Text(
            query.isEmpty
              ? "The catalogue is empty."
              : "Nothing in the catalogue matches “\(query)”."
          )
        }
      } else {
        ForEach(groups, id: \.muscle) { group in
          Section(Self.title(for: group.muscle)) {
            ForEach(group.entries) { entry in
              row(entry)
            }
          }
        }
      }
    }
    .searchable(text: $query, prompt: "Search movements")
  }

  private func row(_ entry: CatalogEntry) -> some View {
    Button {
      onSelect(entry)
    } label: {
      HStack(spacing: Tokens.Spacing.regular) {
        VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
          Text(entry.name)
            .font(Tokens.Text.label)
            .foregroundStyle(Tokens.Color.textPrimary)
          if !entry.secondaryMuscles.isEmpty {
            Text("also \(entry.secondaryMuscles.map(Self.title(for:)).joined(separator: ", "))")
              .font(Tokens.Text.caption)
              .foregroundStyle(Tokens.Color.textSecondary)
              .lineLimit(1)
          }
        }
        Spacer(minLength: 0)
        if let modality = entry.modality {
          Text(modality.label)
            .font(Tokens.Text.caption)
            .foregroundStyle(Tokens.Color.textSecondary)
        }
        // A movement the user created is marked, so a typo'd duplicate of a curated entry is
        // visibly theirs rather than looking official.
        if !entry.isCurated {
          Image(systemName: "person.crop.circle")
            .font(Tokens.Text.caption)
            .foregroundStyle(Tokens.Color.textSecondary)
            .accessibilityLabel("Your own movement")
        }
      }
      .frame(minHeight: Tokens.minimumTapTarget)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(Self.spokenLabel(for: entry))
    .accessibilityHint("Double tap to add to this workout.")
  }

  private struct Group {
    let muscle: String
    let entries: [CatalogEntry]
  }

  /// Muscles ordered by how they appear in a body, not alphabetically, so scanning the list
  /// mirrors how a lifter reads their own plan.
  private static let muscleOrder = [
    "chest", "lats", "upperBack", "traps", "frontDelts", "sideDelts", "rearDelts",
    "biceps", "triceps", "forearms", "quadriceps", "hamstrings", "glutes", "calves",
    "abs", "lowerBack",
  ]

  private var groups: [Group] {
    let grouped = Dictionary(grouping: entries, by: \.primaryMuscle)
    return grouped
      .map { Group(muscle: $0.key, entries: $0.value.sorted { $0.name < $1.name }) }
      .sorted { lhs, rhs in
        let l = Self.muscleOrder.firstIndex(of: lhs.muscle) ?? Self.muscleOrder.count
        let r = Self.muscleOrder.firstIndex(of: rhs.muscle) ?? Self.muscleOrder.count
        // Anything unrecognised sorts last, alphabetically, rather than being hidden.
        return l == r ? lhs.muscle < rhs.muscle : l < r
      }
  }

  /// Turns a stored muscle key into words. An unrecognised key is shown as-is rather than being
  /// dropped — an unknown muscle is a data problem to see, not to hide.
  static func title(for muscle: String) -> String {
    switch muscle {
    case "upperBack": "Upper back"
    case "lowerBack": "Lower back"
    case "frontDelts": "Front delts"
    case "sideDelts": "Side delts"
    case "rearDelts": "Rear delts"
    case "lats": "Lats"
    case "abs": "Abs"
    default: muscle.prefix(1).uppercased() + muscle.dropFirst()
    }
  }

  static func spokenLabel(for entry: CatalogEntry) -> String {
    var parts = [entry.name, title(for: entry.primaryMuscle)]
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
        ExerciseCatalog.v1.compactMap { entry in
          guard let uuid = entry.uuid else { return nil }
          return CatalogEntry(
            id: ExerciseID(rawValue: uuid),
            name: entry.name,
            slug: entry.slug,
            isCurated: true,
            modality: entry.modality,
            primaryMuscle: entry.primaryMuscle,
            secondaryMuscles: entry.secondaryMuscles
          )
        }
        .filter {
          query.isEmpty
            || $0.name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
      }

      var body: some View {
        NavigationStack {
          ExercisePickerView(query: $query, entries: entries) { _ in }
            .navigationTitle("Add movement")
        }
      }
    }
    return Harness()
  }
#endif
