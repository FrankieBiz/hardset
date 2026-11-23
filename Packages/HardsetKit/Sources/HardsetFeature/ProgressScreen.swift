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
  /// The sheet that is up, or `nil`: a movement's progress, or the working behind a row's change. One
  /// value, so the screen carries one presentation and two sheets are never asked for at once.
  @State private var presented: ProgressSheet?
  /// Why the last request for a row's working failed, drawn under that row's control. A control
  /// that appeared to do nothing is what this app is not allowed to have.
  @State private var workingFailure: ProgressBoardView.WorkingFailure?
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
              systemImage: "exclamationmark.triangle",
              style: .quiet
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
          onShowChangeWorking: { showChangeWorking($0) },
          workingFailure: workingFailure,
          onSelect: { row in
            presented = .movement(
              ProgressMovement(exerciseID: row.trend.key.exerciseID, name: row.exerciseName))
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
    .sheet(item: $presented) { sheet in
      switch sheet {
      case .movement(let movement):
        NavigationStack {
          ExerciseProgressScreen(
            store: progression, exerciseID: movement.exerciseID, exerciseName: movement.name,
            unit: unit
          )
          .toolbar {
            ToolbarItem(placement: .confirmationAction) {
              Button("Done") { presented = nil }
            }
          }
        }
        .hardsetSheet()
      case .working(let presentation):
        // The sets behind the six-week change the lifter tapped, read when it was asked for.
        WorkedFromSheet(account: presentation.account)
          .hardsetSheet()
      }
    }
  }

  private var header: some View {
    ScreenHeader(Self.title) {
      if let onShowSettings {
        HeaderIconButton(
          systemImage: "gearshape", accessibilityLabel: "Settings", style: .bare,
          action: onShowSettings)
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

  /// Opens the working behind a row's six-week change. The sets are read when it is asked for, by the
  /// board's own grouping and the very comparison the row's figure came from, so what the sheet says
  /// is what the row did. A failed read, or a change that is no longer there, says so under the row.
  private func showChangeWorking(_ row: ProgressBoard.Row) {
    workingFailure = nil
    let board = board
    let key = row.id
    let format = WorkedFromFormat(unit: unit)
    Task {
      do {
        guard let account = try await board.loadChangeWorking(for: key, format: format) else {
          workingFailure = ProgressBoardView.WorkingFailure(
            key: key,
            message: "This change could not be worked out from the sets on record now. Pull down to refresh.")
          return
        }
        presented = .working(WorkedFromPresentation(account))
      } catch is CancellationError {
        return
      } catch {
        workingFailure = ProgressBoardView.WorkingFailure(
          key: key, message: "Could not read this movement's sets. Your logged sets are safe.")
      }
    }
  }
}

/// The sheets this screen opens, one at a time. `nonisolated` so its computed `id` satisfies
/// `Identifiable` without isolated-conformance inference, as the other screens' sheet enums do.
private nonisolated enum ProgressSheet: Identifiable {
  /// A movement's own progress screen.
  case movement(ProgressMovement)
  /// The working behind a row's six-week change.
  case working(WorkedFromPresentation)

  var id: String {
    switch self {
    case .movement(let movement): "movement-\(movement.exerciseID.rawValue.uuidString)"
    case .working(let presentation): "working-\(presentation.id.uuidString)"
    }
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
