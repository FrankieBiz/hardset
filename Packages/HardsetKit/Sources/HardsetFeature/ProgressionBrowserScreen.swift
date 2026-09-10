import HardsetCore
import HardsetStore
import HardsetUI
import SwiftUI

/// Lets the lifter reach any movement's load history without first finding an old workout.
@MainActor
public struct ProgressionBrowserScreen: View {
  @State private var exercises: [ProgressionExercise] = []
  @State private var isLoading = true
  @State private var loadFailed = false
  @State private var query = ""
  @State private var opened: ProgressionExercise?

  private let store: ProgressionStore
  private let unit: WeightUnit

  public init(store: ProgressionStore, unit: WeightUnit) {
    self.store = store
    self.unit = unit
  }

  public var body: some View {
    Group {
      if isLoading && exercises.isEmpty {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if loadFailed {
        ContentUnavailableView {
          Label("Could not read your progress", systemImage: "exclamationmark.triangle")
        } description: {
          Text("Your logged sets are safe. Pull down to try again.")
        }
      } else if exercises.isEmpty {
        ContentUnavailableView {
          Label("No load history yet", systemImage: "chart.line.uptrend.xyaxis")
        } description: {
          Text("Log a working set to see a movement's history here.")
        }
      } else if filteredExercises.isEmpty {
        ContentUnavailableView {
          Label("No movement found", systemImage: "magnifyingglass")
        } description: {
          Text("Nothing in your load history matches “\(query)”.")
        }
      } else {
        List(filteredExercises) { exercise in
          Button { opened = exercise } label: {
            VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
              Text(exercise.name)
                .font(Tokens.Text.label.weight(.semibold))
                .foregroundStyle(Tokens.Color.textPrimary)
              // Same phrasing as a plan day's rotation line. See `TrainingRecency` for why the
              // system's named format is not used here.
              Text("Last trained \(TrainingRecency.phrase(since: exercise.lastTrained, asOf: .now))")
                .font(Tokens.Text.caption)
                .foregroundStyle(Tokens.Color.textSecondary)
            }
            // `maxWidth: .infinity` as well as the height: without it the shape being made tappable
            // is only as wide as the longest of the two lines, so a tap anywhere right of the
            // movement's name landed on the row and did nothing.
            .frame(maxWidth: .infinity, minHeight: Tokens.minimumTapTarget, alignment: .leading)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityHint("Double tap to view load history.")
        }
      }
    }
    .background(Tokens.Color.ground)
    .navigationTitle("Progress")
    .modifier(SearchableWhenPopulated(isActive: !exercises.isEmpty, query: $query))
    // A movement search is matched case- and diacritic-insensitively, so the shift key does nothing
    // but put a capital in the field and in the "nothing matches ..." sentence that quotes it back.
    // Autocorrect is worse: gym vocabulary is not in the dictionary, and "pec" was being offered
    // corrections over a list that already had Pec Deck in it.
    //
    // Capitalisation is iOS-only, the same reason `NameEntrySheet` guards `keyboardType`.
    #if os(iOS)
      .textInputAutocapitalization(.never)
    #endif
    .autocorrectionDisabled()
    .navigationDestination(item: $opened) { exercise in
      ExerciseProgressScreen(
        store: store, exerciseID: exercise.id, exerciseName: exercise.name, unit: unit
      )
    }
    .task { await load() }
    .refreshable { await load() }
  }

  private var filteredExercises: [ProgressionExercise] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return exercises }
    return exercises.filter {
      $0.name.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
  }

  private func load() async {
    isLoading = true
    let store = store
    let result = await readOffMain { try store.exercisesWithHistory() }
    guard !Task.isCancelled else { return }

    switch result {
    case .success(let loaded):
      exercises = loaded
      loadFailed = false
    case .failure:
      exercises = []
      loadFailed = true
    }
    isLoading = false
  }
}

/// Applies `.searchable` only when there is something to search.
///
/// Gated on the data rather than on the rendered branch. Attaching `.searchable` to the populated
/// list alone would take the field away the moment a query matched nothing -- which is the one state
/// reached *by typing*, leaving no way to clear the query that caused it. So the field covers both
/// the list and the no-match state, and is absent only over the empty and failed states, where a
/// search field is an affordance over nothing.
private struct SearchableWhenPopulated: ViewModifier {
  let isActive: Bool
  @Binding var query: String

  func body(content: Content) -> some View {
    if isActive {
      content.searchable(text: $query, prompt: "Search movements")
    } else {
      content
    }
  }
}
