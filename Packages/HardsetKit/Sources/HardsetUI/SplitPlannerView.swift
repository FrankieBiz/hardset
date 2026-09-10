import HardsetCore
import SwiftUI

/// What a row must say about the machine planned on it, beyond the machine's name.
///
/// Two different facts, and the app is certain of both. A machine belongs to one gym, so one
/// named at another gym will not be the machine used. And with no gym chosen at all
/// `plannedExercises(for:at:)` drops the machine outright, because a session with no gym can only
/// ever log `machineID == nil` -- so a named machine on the row is a promise the start would break.
public enum PlannedMachineNote: Hashable, Sendable {
  /// Nothing to say: the machine is at the gym the next workout will be at, or none is named.
  case none
  /// The machine named here is at a different gym.
  case elsewhere
  /// No gym is chosen, so no machine can be resolved, named, or carried into a workout.
  case noGym
}

/// One movement on a plan's day, as the planner draws it.
public struct PlannedMovementRow: Hashable, Sendable, Identifiable {
  public let id: SplitEntryID
  public let exerciseID: ExerciseID
  public let name: String
  /// What the movement credits, for the line that makes this more than a list of names.
  public let creditedMuscleNames: [String]
  /// The machine this is planned on, when the lifter has named one.
  public let machineID: MachineID?
  /// Its name, resolved by the caller so a row never reads the database to draw itself.
  public let machineName: String?
  /// True when the app cannot attribute the movement at all, so the row must say so rather than
  /// render an empty muscle list as though it meant "trains nothing".
  public let isUnattributed: Bool
  /// Working sets the lifter said they intend here, or nil when they have not said.
  ///
  /// Theirs, never the app's. nil renders as nothing at all rather than a suggested number.
  public let targetSets: Int?
  /// True when the movement has been retired, so it is still in the plan but no longer offered.
  public let isRetired: Bool
  /// What the row must say about the machine planned on it, beyond its name.
  public let machineNote: PlannedMachineNote
  /// True when the lifter owns this movement and may rename it.
  ///
  /// False for curated rows, whose names come from the catalogue and are compared against
  /// `curatedName` on every seed -- `ExerciseStore.rename` refuses them, so a rename control on one
  /// would be an affordance that cannot finish.
  public let isEditable: Bool

  public init(
    id: SplitEntryID,
    exerciseID: ExerciseID,
    name: String,
    creditedMuscleNames: [String],
    machineID: MachineID?,
    machineName: String?,
    isUnattributed: Bool,
    targetSets: Int? = nil,
    isRetired: Bool = false,
    machineNote: PlannedMachineNote = .none,
    isEditable: Bool = false
  ) {
    self.id = id
    self.exerciseID = exerciseID
    self.name = name
    self.creditedMuscleNames = creditedMuscleNames
    self.machineID = machineID
    self.machineName = machineName
    self.isUnattributed = isUnattributed
    self.targetSets = targetSets
    self.isRetired = isRetired
    self.machineNote = machineNote
    self.isEditable = isEditable
  }

  /// The intended-set line, or nil when the lifter has not said.
  ///
  /// Singular/plural spelled out rather than interpolated: `^[\(n) set](inflect: true)` is only
  /// honoured for a `LocalizedStringKey`, and putting it in a `String` shipped the markup once.
  public var targetSetsText: String? {
    guard let targetSets, targetSets > 0 else { return nil }
    return targetSets == 1 ? "1 set planned" : "\(targetSets) sets planned"
  }
}

/// One modelled muscle and the number of a plan's days that credit it.
///
/// A count, deliberately not a rank -- see `SplitPlanAssessment.modelledDayCredits`.
public struct MuscleDayCount: Hashable, Sendable, Identifiable {
  public var id: String { name }
  public let name: String
  public let days: Int

  public init(name: String, days: Int) {
    self.name = name
    self.days = days
  }
}

/// One day of a plan, as the planner draws it.
public struct PlannedDay: Hashable, Sendable, Identifiable {
  public let id: SplitDayID
  public let name: String
  /// Describes what is on the day. Never a training archetype -- see `SplitPlanDay.dominantGroups`.
  public let subtitle: String
  public let movements: [PlannedMovementRow]
  /// When a workout was last started from this day, or nil when none ever has.
  ///
  /// A fact read from `sessions.splitDayID`, never inferred from what a session contained.
  public let lastTrained: Date?
  /// Whether this is the day of the plan that has gone longest without being trained.
  ///
  /// Decided by `SplitRotation.longestSinceTrained`, which refuses to answer for a plan of one day
  /// or a plan nothing has been trained from. It is a statement about the lifter's own history and
  /// deliberately not a recommendation -- the app still never says what to train.
  public let isLongestSinceTrained: Bool

  public init(
    id: SplitDayID,
    name: String,
    subtitle: String,
    movements: [PlannedMovementRow],
    lastTrained: Date? = nil,
    isLongestSinceTrained: Bool = false
  ) {
    self.id = id
    self.name = name
    self.subtitle = subtitle
    self.movements = movements
    self.lastTrained = lastTrained
    self.isLongestSinceTrained = isLongestSinceTrained
  }

  /// One line saying when this day was last trained, and whether it is the one waiting longest.
  ///
  /// Phrased through `TrainingRecency` so the load-history browser words the same fact identically,
  /// and so the second week reads in days -- "10 days ago" and "7 days ago" are the two a lifter on
  /// a weekly split is choosing between, and the system's named format calls both "last week".
  ///
  /// Returns nil for a day with nothing to say, so the caller renders no line rather than an empty
  /// one. Takes `now` rather than reading the clock, so what it says is testable.
  public func rotationText(asOf now: Date = Date()) -> String? {
    let recency: String? =
      lastTrained.map { "Last trained \(TrainingRecency.phrase(since: $0, asOf: now))" }
    switch (recency, isLongestSinceTrained) {
    case (let recency?, true): return "\(recency) · longest since trained"
    case (let recency?, false): return recency
    case (nil, true): return "Not trained yet · longest since trained"
    case (nil, false): return "Not trained yet"
    }
  }
}

/// What the plan covers, and what it leaves out.
///
/// Two statements, because two are all that survive the evidence: which muscles nothing credits,
/// and which of the six modelled muscles this plan credits least. No grade, no target, no bar
/// against a threshold. See `SplitPlanAssessment`.
public struct PlanCoverageSummary: Hashable, Sendable {
  public let movementCount: Int
  public let dayCount: Int
  /// Display names of muscles nothing in the plan credits.
  public let uncreditedMuscleNames: [String]
  /// Display names of the least-credited among the six modelled muscles.
  public let leastCreditedModelledNames: [String]
  /// Some movements could not be attributed, so every statement here is a floor.
  public let isLowerBound: Bool
  /// How many of the plan's days credit each modelled muscle. A readout, never sorted by size.
  public let modelledDayCredits: [MuscleDayCount]

  public init(
    movementCount: Int,
    dayCount: Int,
    uncreditedMuscleNames: [String],
    leastCreditedModelledNames: [String],
    isLowerBound: Bool,
    modelledDayCredits: [MuscleDayCount] = []
  ) {
    self.movementCount = movementCount
    self.dayCount = dayCount
    self.uncreditedMuscleNames = uncreditedMuscleNames
    self.leastCreditedModelledNames = leastCreditedModelledNames
    self.isLowerBound = isLowerBound
    self.modelledDayCredits = modelledDayCredits
  }
}

/// Where a deal's movements come from.
///
/// An empty plan has nothing to rearrange, so dealing it draws on the movements the lifter has
/// actually logged -- which is what its own empty state promises, and is still only ever their own
/// training. Once a plan has movements, dealing rearranges *those*: pulling extra movements into a
/// plan someone curated would be the app editing their training rather than arranging it.
public enum PlanDealSource: Hashable, Sendable {
  /// Rearrange what is already in the plan.
  case planContents(count: Int)
  /// Seed an empty plan from what the lifter has logged.
  case loggedHistory(count: Int)

  var count: Int {
    switch self {
    case .planContents(let count), .loggedHistory(let count): count
    }
  }
}

/// Which straightforward job the planner can offer right now.
///
/// An empty plan can be built deliberately, either from scratch or from completed training
/// history. A populated plan can only be redistributed; it must never silently pull more
/// movements in from history.
public enum PlanBuilderMode: Hashable, Sendable {
  case empty(historyCount: Int)
  case populated

  public init(planMovementCount: Int, historyMovementCount: Int) {
    self = planMovementCount > 0 ? .populated : .empty(historyCount: max(0, historyMovementCount))
  }
}

/// A plan: days, the movements on them, and what that covers.
///
/// ## What this screen refuses to draw
///
/// There is no score, no ring, no progress bar against a target, and the word "balanced" appears
/// nowhere. Not for restraint -- because none of it is computable. `SplitCalibrationProbe` showed
/// every conventional split leaves 6-8 muscles at zero (five of them the same five), that two
/// legitimate plans differ two-fold in weekly sets, and that only 6 of 22 muscles can be placed on
/// the dose-response curve at all. A number here would be invented, and this app's whole claim is
/// that its numbers are not.
///
/// What it does draw is a readback: your movements, arranged, with the gaps named.
public struct SplitPlannerView: View {
  private let days: [PlannedDay]
  private let coverage: PlanCoverageSummary
  private let historyMovementCount: Int
  private let onRedistribute: ((Int) -> Void)?
  private let onStartFromHistory: ((Int) -> Void)?
  /// Adds a movement to a day.
  private let onAddMovement: ((SplitDayID) -> Void)?
  private let onRemoveMovement: ((PlannedMovementRow) -> Void)?
  /// Names the machine a movement is planned on -- which is also what adds it to the gym's library.
  private let onChooseMachine: ((PlannedMovementRow) -> Void)?
  private let onRenameDay: ((PlannedDay) -> Void)?
  private let onAddDay: (() -> Void)?
  private let onDeleteDay: ((PlannedDay) -> Void)?
  /// Moves a movement to another day. The arrangement is a starting point, not a verdict.
  private let onMoveMovement: ((PlannedMovementRow, SplitDayID) -> Void)?
  /// Reorders a movement within its own day. The store has always supported a target position; the
  /// only interaction offered dropped it, so what the lifter does first when fresh was unorderable.
  private let onReorderMovement: ((PlannedMovementRow, Int) -> Void)?
  /// Records the lifter's own intended set count, or clears it with nil.
  private let onSetTargetSets: ((PlannedMovementRow, Int?) -> Void)?
  /// Changes which movement a slot holds, keeping its place in the day and the sets intended on it.
  ///
  /// Every other property of a planned movement was editable in place; the movement itself was not,
  /// so fixing a wrong one meant removing it and adding the right one -- which appends at the bottom
  /// and forgets the intended sets.
  private let onSwapMovement: ((PlannedMovementRow) -> Void)?
  /// Renames a movement the lifter owns, from the plan they are looking at.
  ///
  /// Offered only for rows where `isEditable` is true. `ExerciseStore.rename` refuses curated rows,
  /// so showing it on one would be a control that cannot finish.
  private let onRenameMovement: ((PlannedMovementRow) -> Void)?
  /// Moves a day within the plan. Day order is the order the plan reads in.
  private let onMoveDay: ((PlannedDay, Int) -> Void)?
  /// Starts this day as today's workout. `nil` hides the affordance -- which is what happens while
  /// a workout is already open, because offering it would either abandon that session or do
  /// nothing.
  private let onStartDay: ((PlannedDay) -> Void)?
  /// The day whose workout payload is being prepared. Exposed so the tapped row gives immediate
  /// feedback and all other start buttons stop accepting duplicate taps during that short read.
  private let startingDayID: SplitDayID?

  @State private var redealDayCount: Int
  @State private var isConfirmingRedeal = false

  public init(
    days: [PlannedDay],
    coverage: PlanCoverageSummary,
    historyMovementCount: Int = 0,
    onRedistribute: ((Int) -> Void)? = nil,
    onStartFromHistory: ((Int) -> Void)? = nil,
    onAddMovement: ((SplitDayID) -> Void)? = nil,
    onRemoveMovement: ((PlannedMovementRow) -> Void)? = nil,
    onChooseMachine: ((PlannedMovementRow) -> Void)? = nil,
    onRenameDay: ((PlannedDay) -> Void)? = nil,
    onAddDay: (() -> Void)? = nil,
    onDeleteDay: ((PlannedDay) -> Void)? = nil,
    onMoveMovement: ((PlannedMovementRow, SplitDayID) -> Void)? = nil,
    onReorderMovement: ((PlannedMovementRow, Int) -> Void)? = nil,
    onSetTargetSets: ((PlannedMovementRow, Int?) -> Void)? = nil,
    onSwapMovement: ((PlannedMovementRow) -> Void)? = nil,
    onRenameMovement: ((PlannedMovementRow) -> Void)? = nil,
    onMoveDay: ((PlannedDay, Int) -> Void)? = nil,
    onStartDay: ((PlannedDay) -> Void)? = nil,
    startingDayID: SplitDayID? = nil
  ) {
    self.days = days
    self.coverage = coverage
    self.historyMovementCount = historyMovementCount
    self.onRedistribute = onRedistribute
    self.onStartFromHistory = onStartFromHistory
    self.onAddMovement = onAddMovement
    self.onRemoveMovement = onRemoveMovement
    self.onChooseMachine = onChooseMachine
    self.onRenameDay = onRenameDay
    self.onAddDay = onAddDay
    self.onDeleteDay = onDeleteDay
    self.onMoveMovement = onMoveMovement
    self.onReorderMovement = onReorderMovement
    self.onSetTargetSets = onSetTargetSets
    self.onSwapMovement = onSwapMovement
    self.onRenameMovement = onRenameMovement
    self.onMoveDay = onMoveDay
    self.onStartDay = onStartDay
    self.startingDayID = startingDayID
    self._redealDayCount = State(initialValue: max(1, days.count))
  }

  public var body: some View {
    List {
      if days.isEmpty {
        emptyPlanSection(showsManualBuild: true)
      } else {
        ForEach(days) { day in
          daySection(day)
        }
        switch Self.builderMode(for: days, historyMovementCount: historyMovementCount) {
        case .empty:
          emptyPlanSection(showsManualBuild: false)
        case .populated:
          coverageSection
          frequencySection
          redistributionSection
        }
      }
    }
  }

  public static func builderMode(
    for days: [PlannedDay], historyMovementCount: Int
  ) -> PlanBuilderMode {
    PlanBuilderMode(
      planMovementCount: days.reduce(0) { $0 + $1.movements.count },
      historyMovementCount: historyMovementCount
    )
  }

  // MARK: - Days

  @ViewBuilder private func daySection(_ day: PlannedDay) -> some View {
    Section {
      if day.movements.isEmpty {
        Text("Nothing planned")
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.textSecondary)
      }
      ForEach(day.movements) { movement in
        movementRow(movement, on: day)
      }
      if let onStartDay, !day.movements.isEmpty {
        Button {
          onStartDay(day)
        } label: {
          HStack(spacing: Tokens.Spacing.snug) {
            if startingDayID == day.id {
              ProgressView().controlSize(.small)
            } else {
              Image(systemName: "figure.strengthtraining.traditional")
            }
            Text(startingDayID == day.id ? "Starting…" : "Start this day")
          }
          .font(Tokens.Text.label.weight(.semibold))
        }
        .disabled(startingDayID != nil)
      }
      if let onAddMovement {
        Button {
          onAddMovement(day.id)
        } label: {
          Label("Add movement", systemImage: "plus")
            .font(Tokens.Text.label)
        }
      }
    } header: {
      dayHeader(day)
    }
  }

  @ViewBuilder private func dayHeader(_ day: PlannedDay) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.snug) {
      VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
        Text(day.name)
          .font(Tokens.Text.label.weight(.semibold))
          .foregroundStyle(Tokens.Color.textPrimary)
        if !day.subtitle.isEmpty {
          // Describes the contents. Not an archetype -- the app did not choose a split style.
          Text(day.subtitle)
            .font(Tokens.Text.caption)
            .foregroundStyle(Tokens.Color.textSecondary)
            .textCase(nil)
        }
        if let rotationText = day.rotationText() {
          // Brighter for the day waiting longest, rather than a second hue. Chrome in this app is
          // achromatic and the accent is the brightest thing, so "scan for the bright line" is the
          // cue the design already teaches -- see `docs/UI-GUIDELINES.md`.
          Text(rotationText)
            .font(Tokens.Text.caption)
            .foregroundStyle(
              day.isLongestSinceTrained ? Tokens.Color.textPrimary : Tokens.Color.textTertiary
            )
            .textCase(nil)
        }
      }
      Spacer(minLength: Tokens.Spacing.snug)
      if onRenameDay != nil || onDeleteDay != nil || onMoveDay != nil {
        Menu {
          if let onMoveDay, let index = days.firstIndex(of: day) {
            if index > 0 {
              Button {
                onMoveDay(day, index - 1)
              } label: {
                Label("Move earlier", systemImage: "arrow.up")
              }
            }
            if index < days.count - 1 {
              Button {
                onMoveDay(day, index + 1)
              } label: {
                Label("Move later", systemImage: "arrow.down")
              }
            }
          }
          if let onRenameDay {
            Button {
              onRenameDay(day)
            } label: {
              Label("Rename day", systemImage: "pencil")
            }
          }
          if let onDeleteDay {
            Button(role: .destructive) {
              onDeleteDay(day)
            } label: {
              Label("Delete day", systemImage: "trash")
            }
          }
        } label: {
          Image(systemName: "ellipsis.circle")
            .font(Tokens.Text.glyph)
            // Inside the label and shaped, not applied to the `Menu`. A menu's hit region is its
            // label's content shape, so a frame hung on the `Menu` grows the layout footprint and
            // leaves the added area untappable -- the glyph itself stays around 20 pt, on the only
            // route to renaming or deleting a day. `contentShape` is what makes the whole 44 pt
            // rectangle hit-test, rather than just the drawn glyph inside it.
            .frame(minWidth: Tokens.minimumTapTarget, minHeight: Tokens.minimumTapTarget)
            .contentShape(Rectangle())
        }
        // A menu label is a glyph, so it needs a name of its own for VoiceOver.
        .accessibilityLabel("Options for \(day.name)")
      }
    }
    .textCase(nil)
  }

  // MARK: - Movements

  @ViewBuilder private func movementRow(_ movement: PlannedMovementRow, on day: PlannedDay)
    -> some View
  {
    HStack(alignment: .top, spacing: Tokens.Spacing.snug) {
      VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
        Text(movement.name)
          .font(Tokens.Text.label)
          .foregroundStyle(Tokens.Color.textPrimary)

        // The line that makes this more than a list of names, and the reason it must not be
        // truncated: it is the attribution the whole app is built on.
        if movement.isUnattributed {
          Text("Not attributed")
            .font(Tokens.Text.caption)
            .foregroundStyle(Tokens.Color.textSecondary)
        } else if !movement.creditedMuscleNames.isEmpty {
          Text(movement.creditedMuscleNames.joined(separator: " · "))
            .font(Tokens.Text.caption)
            .foregroundStyle(Tokens.Color.textSecondary)
        }

        machineLabel(movement)

        if let targetSetsText = movement.targetSetsText {
          Text(targetSetsText)
            .font(Tokens.Text.caption)
            .foregroundStyle(Tokens.Color.textSecondary)
        }

        if movement.isRetired {
          // Said, not silently removed. The plan is the lifter's; the app only reports that this
          // movement is no longer one it will offer them.
          Text("Retired — still starts, no longer offered")
            .font(Tokens.Text.caption)
            .foregroundStyle(Tokens.Color.certainty(.low))
        }
      }
      Spacer(minLength: Tokens.Spacing.hairline)
      // Moving used to exist only in a long-press context menu. This visible control makes the
      // common edit a normal tap and keeps the whole row free for readable, multiline attribution.
      Menu {
        movementActionItems(movement, on: day)
      } label: {
        Image(systemName: "arrow.up.arrow.down.circle")
          .font(Tokens.Text.glyph)
          .frame(minWidth: Tokens.minimumTapTarget, minHeight: Tokens.minimumTapTarget)
          // The frame was already in the right place here; without a content shape only the drawn
          // glyph hit-tests, so the declared 44 pt was still not the tappable area.
          .contentShape(Rectangle())
      }
      .accessibilityLabel("Move or edit \(movement.name)")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
    .swipeActions(edge: .trailing) {
      if let onRemoveMovement {
        Button(role: .destructive) {
          onRemoveMovement(movement)
        } label: {
          Label("Remove", systemImage: "trash")
        }
      }
    }
    .contextMenu {
      movementActionItems(movement, on: day)
    }
  }

  /// The visible row menu and the long-press menu intentionally share one action list. The visible
  /// one is for discovery; the context menu remains the fast path for someone already using it.
  @ViewBuilder private func movementActionItems(_ movement: PlannedMovementRow, on day: PlannedDay)
    -> some View
  {
    if let onReorderMovement, let index = day.movements.firstIndex(of: movement) {
      if index > 0 {
        Button {
          onReorderMovement(movement, index - 1)
        } label: {
          Label("Move up", systemImage: "arrow.up")
        }
      }
      if index < day.movements.count - 1 {
        Button {
          onReorderMovement(movement, index + 1)
        } label: {
          Label("Move down", systemImage: "arrow.down")
        }
      }
    }
    if let onMoveMovement {
      ForEach(days.filter { $0.id != day.id }) { destination in
        Button {
          onMoveMovement(movement, destination.id)
        } label: {
          Label("Move to \(destination.name)", systemImage: "arrow.right")
        }
      }
    }
    if let onSwapMovement {
      Button {
        onSwapMovement(movement)
      } label: {
        Label("Swap movement", systemImage: "arrow.triangle.2.circlepath")
      }
    }
    if let onRenameMovement, movement.isEditable {
      Button {
        onRenameMovement(movement)
      } label: {
        Label("Rename movement", systemImage: "pencil")
      }
    }
    if let onChooseMachine {
      Button {
        onChooseMachine(movement)
      } label: {
        Label(
          movement.machineName == nil ? "Add machine" : "Change machine",
          systemImage: "dumbbell"
        )
      }
    }
    if let onSetTargetSets {
      Menu {
        Button("Not set") { onSetTargetSets(movement, nil) }
        ForEach(1...Self.offeredTargetSets, id: \.self) { count in
          Button(count == 1 ? "1 set" : "\(count) sets") { onSetTargetSets(movement, count) }
        }
      } label: {
        Label(movement.targetSets == nil ? "Sets you intend" : "Change sets", systemImage: "number")
      }
    }
    if let onRemoveMovement {
      Button(role: .destructive) {
        onRemoveMovement(movement)
      } label: {
        Label("Remove movement", systemImage: "trash")
      }
    }
  }

  /// How many set counts the menu offers. A menu length, not a training range -- `setTargetSets`
  /// accepts up to `SplitStore.maximumTargetSets`, and nothing compares any of them to a target.
  static let offeredTargetSets = 10

  @ViewBuilder private func machineLabel(_ movement: PlannedMovementRow) -> some View {
    if let machineName = movement.machineName {
      Button {
        onChooseMachine?(movement)
      } label: {
        VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
          Label(machineName, systemImage: "dumbbell")
            .font(Tokens.Text.caption)
            .foregroundStyle(Tokens.Color.textSecondary)
          switch movement.machineNote {
          case .none:
            EmptyView()
          case .elsewhere:
            // Said here rather than discovered mid-workout. A machine belongs to one gym, so this
            // one will not be the machine used -- the day will open on a same-named machine here if
            // there is one, and unbound if there is not.
            Text("Not at the gym you are training at next")
              .font(Tokens.Text.caption)
              .foregroundStyle(Tokens.Color.textSecondary)
          case .noGym:
            // A different statement from the one above, and a certain one: with no gym chosen there
            // is no gym to resolve this machine against, so the day opens unbound whatever its name
            // says. The row named a machine the workout will not use, silently, until now.
            Text("No gym chosen — this day starts without a machine")
              .font(Tokens.Text.caption)
              .foregroundStyle(Tokens.Color.textSecondary)
          }
        }
      }
      .buttonStyle(.plain)
    } else if let onChooseMachine {
      Button {
        onChooseMachine(movement)
      } label: {
        Label("Add machine", systemImage: "dumbbell")
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.textSecondary)
      }
      .buttonStyle(.plain)
    }
  }

  // MARK: - Coverage

  /// The days-credited readout.
  ///
  /// Counts, presented in the taxonomy's own order and never sorted by size: the app has no
  /// registered finding about training frequency, so `SplitPlanAssessment.creditingDays` may be
  /// shown and may not be ranked. The footnote says so on the face of it, because a bare list of
  /// numbers invites being read as a score.
  @ViewBuilder private var frequencySection: some View {
    if !coverage.modelledDayCredits.isEmpty, coverage.dayCount > 1 {
      Section {
        ForEach(coverage.modelledDayCredits) { credit in
          HStack(spacing: Tokens.Spacing.snug) {
            Text(credit.name)
              .font(Tokens.Text.caption)
              .foregroundStyle(Tokens.Color.textSecondary)
            Spacer(minLength: Tokens.Spacing.snug)
            Text(Self.dayCreditText(credit.days, of: coverage.dayCount))
              .font(Tokens.Text.caption)
              .monospacedDigit()
              .foregroundStyle(Tokens.Color.textPrimary)
          }
        }
      } header: {
        Text("Days credited, among the six the evidence covers")
          .font(Tokens.Text.caption)
          .textCase(nil)
      } footer: {
        Text(
          "A count of this arrangement, not a target. No training frequency is established, so "
            + "these are not ranked and none is better than another."
        )
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.textSecondary)
      }
    }
  }

  @ViewBuilder private var coverageSection: some View {
    Section {
      VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
        Text(Self.arrangementText(coverage))
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.textSecondary)

        if !coverage.uncreditedMuscleNames.isEmpty {
          statement(
            title: coverage.isLowerBound
              ? "Nothing the app recognises trains" : "Nothing here trains",
            detail: coverage.uncreditedMuscleNames.joined(separator: ", ")
          )
        }

        if !coverage.leastCreditedModelledNames.isEmpty {
          // The scope has to be in the label. Bare "Fewest movements" reads as "fewest in the
          // whole plan", when the claim is much narrower: of the six muscles the dose-response
          // model covers, these get the fewest. Without the qualifier it looks like an arbitrary
          // callout, or worse, like a verdict.
          statement(
            title: "Fewest movements, among the six the evidence covers",
            detail: coverage.leastCreditedModelledNames.joined(separator: ", ")
          )
        }

        if coverage.isLowerBound {
          // The caveat has to be readable AND announced. A visual-only caveat is silent to
          // VoiceOver, which is how a lower bound gets read as a total.
          Text("Some movements could not be attributed, so this is a floor, not a total.")
            .font(Tokens.Text.caption)
            .foregroundStyle(Tokens.Color.textSecondary)
        }
      }
      .padding(.vertical, Tokens.Spacing.tight)
    } header: {
      Text("What this covers")
        .font(Tokens.Text.caption)
        .textCase(nil)
    } footer: {
      // The refusal, stated where a score would otherwise go. A lifter who wonders why there is no
      // rating deserves the reason rather than the absence.
      Text("No plan is graded. No weekly set target is established for any muscle, so the app "
        + "reports what your arrangement covers rather than scoring it.")
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.textSecondary)
    }
  }

  @ViewBuilder private func statement(title: String, detail: String) -> some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
      Text(title)
        .font(Tokens.Text.caption.weight(.semibold))
        .foregroundStyle(Tokens.Color.textSecondary)
      Text(detail)
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.textPrimary)
    }
    // One announcement rather than two fragments read out of context.
    .accessibilityElement(children: .combine)
  }

  // MARK: - Re-dealing

  @ViewBuilder private func emptyPlanSection(showsManualBuild: Bool) -> some View {
    Section {
      if showsManualBuild {
        Text(Self.planPurposeText)
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.textSecondary)
        if let onAddDay {
          Button(Self.manualBuildButtonText) { onAddDay() }
        }
      }
      if let onStartFromHistory {
        Stepper(value: $redealDayCount, in: 1...7) {
          Text(Self.dayCountText(redealDayCount)).monospacedDigit()
        }
        Button(Self.historyStartButtonText) { isConfirmingRedeal = true }
          .disabled(historyMovementCount == 0)
        Text(Self.historyStartExplanation(movementCount: historyMovementCount))
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.textSecondary)
        .confirmationDialog(
          "Start from training history?", isPresented: $isConfirmingRedeal,
          titleVisibility: .visible
        ) {
          Button("Build plan") { onStartFromHistory(redealDayCount) }
          Button("Cancel", role: .cancel) {}
        } message: {
          Text(Self.historyStartExplanation(movementCount: historyMovementCount))
        }
      }
    } header: {
      Text("Build a plan").textCase(nil)
    }
  }

  @ViewBuilder private var redistributionSection: some View {
    if let onRedistribute {
      Section {
        Stepper(value: $redealDayCount, in: 1...7) {
          Text(Self.dayCountText(redealDayCount)).monospacedDigit()
        }
        Button(Self.redistributionButtonText(redealDayCount)) { isConfirmingRedeal = true }
        Text(
          Self.redistributionExplanation(
            movementCount: days.flatMap(\.movements).count,
            currentDayCount: days.count,
            targetDayCount: redealDayCount
          )
        )
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.textSecondary)
        .confirmationDialog(
          Self.redistributionButtonText(redealDayCount) + "?", isPresented: $isConfirmingRedeal,
          titleVisibility: .visible
        ) {
          Button("Redistribute") { onRedistribute(redealDayCount) }
          Button("Cancel", role: .cancel) {}
        } message: {
          Text(
            Self.redistributionExplanation(
              movementCount: days.flatMap(\.movements).count,
              currentDayCount: days.count,
              targetDayCount: redealDayCount
            )
          )
        }
      } header: {
        Text(Self.redistributionSectionTitle).textCase(nil)
      }
    }
  }

  // MARK: - Copy

  static func arrangementText(_ coverage: PlanCoverageSummary) -> String {
    "\(movementCountText(coverage.movementCount)) across \(dayCountText(coverage.dayCount))."
  }

  // Plurals are spelled out with a ternary on purpose. `^[\(n) day](inflect: true)` is only
  // interpreted for a `LocalizedStringKey`, and putting it in an interpolated `String` shipped the
  // markup to the screen verbatim -- which this app has already done once.
  static func dayCountText(_ count: Int) -> String {
    count == 1 ? "1 day" : "\(count) days"
  }

  static func movementCountText(_ count: Int) -> String {
    count == 1 ? "1 movement" : "\(count) movements"
  }

  static func dealButtonText(_ days: Int) -> String {
    "Deal across \(dayCountText(days))"
  }

  public static let planPurposeText =
    "A plan is a reusable weekly structure for exercises you already train."
  public static let manualBuildButtonText = "Build it myself"
  public static let historyStartButtonText = "Start from training history"
  public static let redistributionSectionTitle = "Redistribute exercises"

  public static func redistributionButtonText(_ days: Int) -> String {
    "Redistribute across \(dayCountText(days))"
  }

  public static func redistributionExplanation(movementCount: Int) -> String {
    "Spreads the \(movementCountText(movementCount)) already in this plan across the days you choose, keeping similar-muscle work apart where possible. It does not add or remove movements, does not decide your sets, or change named machines. Your logged weights and reps stay."
  }

  public static func redistributionExplanation(
    movementCount: Int, currentDayCount: Int, targetDayCount: Int
  ) -> String {
    let base = redistributionExplanation(movementCount: movementCount)
    guard targetDayCount < currentDayCount else { return base }
    return base
      + " Workouts linked to a removed day will no longer count toward this plan's rotation history."
  }

  public static func historyStartExplanation(movementCount: Int) -> String {
    movementCount > 0
      ? "Arranges \(movementCountText(movementCount)) from completed workouts across the days you choose. It does not change completed workouts."
      : "Complete a workout first, then you can build a plan from its movements."
  }

  /// Says which movements a deal would use, because "deal" means two different things depending on
  /// whether the plan already has any.
  static func dealFootnote(_ source: PlanDealSource) -> String {
    switch source {
    case .planContents(let count) where count > 0:
      return "Spreads the \(movementCountText(count)) already in this plan across the days you "
        + "choose, evening out what each day trains. It does not add movements or decide how many "
        + "sets you do."
    case .planContents:
      return "Add a movement, or log a workout, and this will spread them across the days you "
        + "choose."
    case .loggedHistory(let count):
      return "This plan is empty, so dealing starts from the \(movementCountText(count)) you have "
        + "logged. It adds nothing you have not trained, and decides no set counts."
    }
  }

  /// What dealing actually does, in full.
  ///
  /// This used to say only that the arrangement was replaced and logged workouts were safe. Both
  /// true, and materially incomplete: dealing discarded every machine the lifter had named and
  /// renamed their days back to "Day 1". Those are now carried across, and the wording says so --
  /// a confirmation has to describe what the button really does, or agreeing to it means nothing.
  static func dealConfirmation(_ source: PlanDealSource) -> String {
    let kept =
      "Machines you have named, the sets you intend and your day names are kept. "
      + "Your logged workouts are not affected."
    switch source {
    case .planContents:
      return "This moves the movements already in this plan onto different days. \(kept)"
    case .loggedHistory:
      return "The movements you have logged will be arranged across these days. Nothing is added "
        + "that you have not trained. \(kept)"
    }
  }

  static func dayCreditText(_ days: Int, of total: Int) -> String {
    "\(days) of \(total)"
  }
}
