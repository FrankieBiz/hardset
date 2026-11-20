import HardsetCore
import HardsetStore
import HardsetUI
import SwiftUI

/// The Progress tab, wired.
///
/// Draws its own header in every state, because the tab hides the stock navigation bar. Until the
/// first read finishes it says it is reading rather than claiming there is no progress: "No
/// progress to show yet" for the instant before the board arrives would be a small lie. A failed
/// read says so instead of drawing an empty board, and pull-to-refresh tries again.
///
/// A row opens the movement's own progress screen, the per-machine chart with its record marks and
/// its best at each weight. The board re-reads when the app returns to the foreground and whenever
/// saved history changed somewhere this screen cannot see, such as a workout finished on the Train
/// tab or an import in Settings.
@MainActor
public struct ProgressScreen: View {
  @State private var snapshot = SnapshotLoader<ProgressBoard>()
  @State private var selectedMovement: ProgressMovement?
  /// Bumped to re-read when the app comes back to the foreground.
  @State private var reloadToken = 0
  @Environment(\.scenePhase) private var scenePhase

  private let board: ProgressBoardStore
  private let progression: ProgressionStore
  private let unit: WeightUnit
  private let onShowSettings: (() -> Void)?
  /// Changes when saved history changed somewhere this screen cannot see. Each change re-reads,
  /// keeping the board on screen while it does.
  private let dataRevision: Int

  private static let title = "Progress"

  public init(
    board: ProgressBoardStore,
    progression: ProgressionStore,
    unit: WeightUnit,
    onShowSettings: (() -> Void)? = nil,
    dataRevision: Int = 0
  ) {
    self.board = board
    self.progression = progression
    self.unit = unit
    self.onShowSettings = onShowSettings
    self.dataRevision = dataRevision
  }

  public var body: some View {
    Group {
      if snapshot.loadFailed {
        // Scrollable so the pull-to-refresh the message promises actually works.
        ScrollView {
          VStack(alignment: .leading, spacing: Tokens.Spacing.section) {
            header
            HardsetEmptyState(
              title: "Could not read your progress",
              detail: "Your logged sets are safe. Pull down to try again.",
              systemImage: "exclamationmark.triangle"
            )
          }
          .padding(.bottom, Tokens.Spacing.block)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Tokens.Color.canvas)
      } else if let value = snapshot.value {
        ProgressBoardView(
          board: value,
          title: Self.title,
          subtitle: Self.subtitle(value),
          onShowSettings: onShowSettings,
          onSelect: { row in
            selectedMovement = ProgressMovement(
              exerciseID: row.trend.key.exerciseID, name: row.exerciseName)
          }
        )
      } else {
        VStack(alignment: .leading, spacing: 0) {
          header
          HardsetLoadingState("Reading your progress…")
        }
        .background(Tokens.Color.canvas)
      }
    }
    // Keyed on the token and the revision, so a return to the foreground and an outside change each
    // re-read, and a superseded read is cancelled.
    .task(id: LoadKey(token: reloadToken, revision: dataRevision)) { await load() }
    .refreshable { await load() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { reloadToken &+= 1 }
    }
    .sheet(item: $selectedMovement) { movement in
      NavigationStack {
        ExerciseProgressScreen(
          store: progression, exerciseID: movement.exerciseID, exerciseName: movement.name,
          unit: unit
        )
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") { selectedMovement = nil }
          }
        }
      }
      .hardsetSheet()
    }
  }

  private var header: some View {
    ScreenHeader(Self.title) {
      if let onShowSettings {
        HeaderIconButton(systemImage: "gearshape", accessibilityLabel: "Settings", action: onShowSettings)
      }
    }
  }

  /// "12 movements", counting one per movement and machine, once the board has any.
  private static func subtitle(_ board: ProgressBoard) -> String? {
    let count = board.sections.reduce(0) { $0 + $1.rows.count }
    guard count > 0 else { return nil }
    return count == 1 ? "1 movement" : "\(count) movements"
  }

  private func load() async {
    let board = board
    await snapshot.load { try await board.loadBoard() }
  }
}

/// The movement whose progress screen is open, so `sheet(item:)` has something `Identifiable`.
private nonisolated struct ProgressMovement: Identifiable {
  let exerciseID: ExerciseID
  let name: String
  var id: ExerciseID { exerciseID }
}

private nonisolated struct LoadKey: Hashable, Sendable {
  let token: Int
  let revision: Int
}
