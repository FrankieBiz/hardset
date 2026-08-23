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
  /// Drives the row layout: see `row(_:)`.
  @Environment(\.dynamicTypeSize) private var typeSize

  /// Movements logged most recently, newest first. Carried over from the ancestor app's smart
  /// sort, which was the right idea: what someone trains is overwhelmingly what they trained last
  /// week, and that needs no modelling -- only their own history.
  private let recent: [ExerciseID]
  /// Movements this gym is known to have equipment for, and the gym's name for the heading.
  ///
  /// The ancestor's research concluded that the defensible version of this ranks by the equipment
  /// a gym actually has, and that doing so needed a machine-to-exercise join it did not have. This
  /// app has one.
  private let availableHere: Set<ExerciseID>
  private let gymName: String?

  @Binding private var query: String
  private let entries: [CatalogEntry]
  private let onSelect: (CatalogEntry) -> Void

  public init(
    query: Binding<String>,
    entries: [CatalogEntry],
    recent: [ExerciseID] = [],
    availableHere: Set<ExerciseID> = [],
    gymName: String? = nil,
    onSelect: @escaping (CatalogEntry) -> Void
  ) {
    self._query = query
    self.entries = entries
    self.recent = recent
    self.availableHere = availableHere
    self.gymName = gymName
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
        // Relevance first, vocabulary second. Neither of these sections is a recommendation --
        // one is the user's own history and the other is what the building contains. The app still
        // declines to say what anyone should train.
        if !recentEntries.isEmpty {
          Section("Recent") {
            ForEach(recentEntries) { row($0) }
          }
        }
        if !hereEntries.isEmpty {
          Section(gymName.map { "At \($0)" } ?? "Equipment you have") {
            ForEach(hereEntries) { row($0) }
          }
        }
        ForEach(groups) { group in
          Section(sectionTitle(group.key)) {
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
      SwiftUI.Group {
        if typeSize.isAccessibilitySize {
          // Stacked, because at accessibility sizes the name and the equipment label were
          // competing for one line and both lost: "Machine" rendered as "Ma-" and the muscle list
          // as "also Fro...". The equipment moves under the name rather than beside it.
          VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
            nameAndMuscles(entry)
            HStack(spacing: Tokens.Spacing.snug) {
              modalityLabel(entry)
              ownMovementMark(entry)
            }
          }
        } else {
          HStack(spacing: Tokens.Spacing.regular) {
            nameAndMuscles(entry)
            Spacer(minLength: 0)
            modalityLabel(entry)
            ownMovementMark(entry)
          }
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

  private struct Group: Identifiable {
    let key: MuscleKey
    let entries: [CatalogEntry]
    var id: String { key.storedValue }
  }

  /// Grouped by the muscle a movement primarily trains, ordered by the vocabulary's own
  /// declaration order.
  ///
  /// The hand-maintained `muscleOrder` array this replaced was a second source of truth that could
  /// silently omit a token — a new muscle would have sorted last with no warning. `Muscle.allCases`
  /// cannot drift from the enum.
  /// Recently logged, in recency order, and only while the user is not searching -- a query means
  /// they know what they want and relevance sections just push it down the screen.
  private var recentEntries: [CatalogEntry] {
    guard query.isEmpty else { return [] }
    let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
    return recent.compactMap { byID[$0] }
  }

  /// Equipment at this gym, minus anything already shown under Recent, so nothing appears twice.
  private var hereEntries: [CatalogEntry] {
    guard query.isEmpty else { return [] }
    let alreadyShown = Set(recentEntries.map(\.id))
    return entries
      .filter { availableHere.contains($0.id) && !alreadyShown.contains($0.id) }
      .sorted { $0.name < $1.name }
  }

  private var groups: [Group] {
    let grouped = Dictionary(grouping: entries, by: \.primaryMuscle)
    let index = Dictionary(uniqueKeysWithValues: Muscle.allCases.enumerated().map { ($1, $0) })
    return grouped
      .map { Group(key: $0.key, entries: $0.value.sorted { $0.name < $1.name }) }
      .sorted { lhs, rhs in
        // Unrecognised and unattributed tokens sort last rather than being hidden: a row nobody
        // has attributed is a data problem to see.
        let l = lhs.key.muscle.map { index[$0] ?? Int.max } ?? Int.max
        let r = rhs.key.muscle.map { index[$0] ?? Int.max } ?? Int.max
        if l != r { return l < r }
        return lhs.key.storedValue < rhs.key.storedValue
      }
  }

  /// Section title. Comes from the vocabulary, so there is no title-casing fallback that would
  /// make an unrecognised token look like an authored muscle name.
  private func sectionTitle(_ key: MuscleKey) -> String {
    Self.displayName(key)
  }

  @ViewBuilder private func nameAndMuscles(_ entry: CatalogEntry) -> some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
      Text(entry.name)
        .font(Tokens.Text.label)
        .foregroundStyle(Tokens.Color.textPrimary)
      // Credited muscles only. Grip and bracing are stabilisers and are deliberately not
      // listed here: showing them as "also trains" is the claim the role split exists to stop.
      //
      // Deliberately NOT line-limited. This line is the whole reason the picker is more useful
      // than a list of names, and truncating it to "also Fro..." throws away the differentiator
      // to save a few points of height.
      if !supportingText(for: entry).isEmpty {
        Text(supportingText(for: entry))
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  @ViewBuilder private func modalityLabel(_ entry: CatalogEntry) -> some View {
    if let modality = entry.modality {
      Text(modality.label)
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.textSecondary)
        // Never hyphenated mid-word: "Machine" became "Ma-" when it had to share a line.
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
  }

  /// A movement the user created is marked, so a typo'd duplicate of a curated entry is visibly
  /// theirs rather than looking official.
  @ViewBuilder private func ownMovementMark(_ entry: CatalogEntry) -> some View {
    if !entry.isCurated {
      Image(systemName: "person.crop.circle")
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.textSecondary)
        .accessibilityLabel("Your own movement")
    }
  }

  private func supportingText(for entry: CatalogEntry) -> String {
    let others = entry.creditedMuscles.filter { $0.key != entry.primaryMuscle }
    guard !others.isEmpty else { return "" }
    return "also " + others.map { Self.displayName($0.key) }.joined(separator: ", ")
  }

  /// Placeholder resolution of the String Catalog key.
  ///
  /// The real lookup is `String(localized:)` once a catalog exists; until then this is the ONE
  /// place that turns a key into words, so localisation is a change here and nowhere else. It
  /// deliberately does not title-case an unknown raw value.
  static func displayName(_ key: MuscleKey) -> String {
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

  static func spokenLabel(for entry: CatalogEntry) -> String {
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
          ExercisePickerView(query: $query, entries: entries) { _ in }
            .navigationTitle("Add movement")
        }
      }
    }
    return Harness()
  }
#endif
