import HardsetCore
import SwiftUI

/// One movement on a plan's day, as the planner draws it.
public struct PlannedMovementRow: Hashable, Sendable, Identifiable {
  public let id: SplitEntryID
  public let exerciseID: ExerciseID
  public let name: String
  /// What the movement credits, for the line that makes this more than a list of names.
  public let creditedMuscleNames: [String]
  /// The machine this is planned on, when the lifter has named one.
  public let machineName: String?
  /// True when the app cannot attribute the movement at all, so the row must say so rather than
  /// render an empty muscle list as though it meant "trains nothing".
  public let isUnattributed: Bool

  public init(
    id: SplitEntryID,
    exerciseID: ExerciseID,
    name: String,
    creditedMuscleNames: [String],
    machineName: String?,
    isUnattributed: Bool
  ) {
    self.id = id
    self.exerciseID = exerciseID
    self.name = name
    self.creditedMuscleNames = creditedMuscleNames
    self.machineName = machineName
    self.isUnattributed = isUnattributed
  }
}

/// One day of a plan, as the planner draws it.
public struct PlannedDay: Hashable, Sendable, Identifiable {
  public let id: SplitDayID
  public let name: String
  /// Describes what is on the day. Never a training archetype -- see `SplitPlanDay.dominantGroups`.
  public let subtitle: String
  public let movements: [PlannedMovementRow]

  public init(id: SplitDayID, name: String, subtitle: String, movements: [PlannedMovementRow]) {
    self.id = id
    self.name = name
    self.subtitle = subtitle
    self.movements = movements
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

  public init(
    movementCount: Int,
    dayCount: Int,
    uncreditedMuscleNames: [String],
    leastCreditedModelledNames: [String],
    isLowerBound: Bool
  ) {
    self.movementCount = movementCount
    self.dayCount = dayCount
    self.uncreditedMuscleNames = uncreditedMuscleNames
    self.leastCreditedModelledNames = leastCreditedModelledNames
    self.isLowerBound = isLowerBound
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
  /// Re-deals the plan across a chosen number of days. `nil` hides the affordance.
  private let onRedeal: ((Int) -> Void)?
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

  @State private var redealDayCount: Int
  @State private var isConfirmingRedeal = false

  public init(
    days: [PlannedDay],
    coverage: PlanCoverageSummary,
    onRedeal: ((Int) -> Void)? = nil,
    onAddMovement: ((SplitDayID) -> Void)? = nil,
    onRemoveMovement: ((PlannedMovementRow) -> Void)? = nil,
    onChooseMachine: ((PlannedMovementRow) -> Void)? = nil,
    onRenameDay: ((PlannedDay) -> Void)? = nil,
    onAddDay: (() -> Void)? = nil,
    onDeleteDay: ((PlannedDay) -> Void)? = nil,
    onMoveMovement: ((PlannedMovementRow, SplitDayID) -> Void)? = nil
  ) {
    self.days = days
    self.coverage = coverage
    self.onRedeal = onRedeal
    self.onAddMovement = onAddMovement
    self.onRemoveMovement = onRemoveMovement
    self.onChooseMachine = onChooseMachine
    self.onRenameDay = onRenameDay
    self.onAddDay = onAddDay
    self.onDeleteDay = onDeleteDay
    self.onMoveMovement = onMoveMovement
    self._redealDayCount = State(initialValue: max(1, days.count))
  }

  public var body: some View {
    List {
      if days.isEmpty {
        ContentUnavailableView {
          Label("No days yet", systemImage: "square.split.2x2")
        } description: {
          Text("Add a day, or deal the movements you already train across a few of them.")
        }
      } else {
        ForEach(days) { day in
          daySection(day)
        }
        coverageSection
      }
      redealSection
    }
  }

  // MARK: - Days

  @ViewBuilder private func daySection(_ day: PlannedDay) -> some View {
    Section {
      if day.movements.isEmpty {
        Text("Nothing planned")
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.textTertiary)
      }
      ForEach(day.movements) { movement in
        movementRow(movement, on: day)
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
      }
      Spacer(minLength: Tokens.Spacing.snug)
      if onRenameDay != nil || onDeleteDay != nil {
        Menu {
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
        }
        // A menu label is a glyph, so it needs a name of its own for VoiceOver.
        .accessibilityLabel("Options for \(day.name)")
        .frame(minWidth: Tokens.minimumTapTarget, minHeight: Tokens.minimumTapTarget)
      }
    }
    .textCase(nil)
  }

  // MARK: - Movements

  @ViewBuilder private func movementRow(_ movement: PlannedMovementRow, on day: PlannedDay)
    -> some View
  {
    VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
      Text(movement.name)
        .font(Tokens.Text.label)
        .foregroundStyle(Tokens.Color.textPrimary)

      // The line that makes this more than a list of names, and the reason it must not be
      // truncated: it is the attribution the whole app is built on.
      if movement.isUnattributed {
        Text("Not attributed")
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.textTertiary)
      } else if !movement.creditedMuscleNames.isEmpty {
        Text(movement.creditedMuscleNames.joined(separator: " · "))
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.textSecondary)
      }

      machineLabel(movement)
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
      if let onChooseMachine {
        Button {
          onChooseMachine(movement)
        } label: {
          Label(
            movement.machineName == nil ? "Name the machine" : "Change machine",
            systemImage: "dumbbell"
          )
        }
      }
      if let onMoveMovement {
        // Moving between days is the interaction this screen exists for. A menu rather than a drag
        // because a drag has no discoverable affordance and no VoiceOver equivalent.
        ForEach(days.filter { $0.id != day.id }) { destination in
          Button {
            onMoveMovement(movement, destination.id)
          } label: {
            Label("Move to \(destination.name)", systemImage: "arrow.right")
          }
        }
      }
    }
  }

  @ViewBuilder private func machineLabel(_ movement: PlannedMovementRow) -> some View {
    if let machineName = movement.machineName {
      Label(machineName, systemImage: "dumbbell")
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.textSecondary)
    }
  }

  // MARK: - Coverage

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
          statement(
            title: "Fewest movements",
            detail: coverage.leastCreditedModelledNames.joined(separator: ", ")
          )
        }

        if coverage.isLowerBound {
          // The caveat has to be readable AND announced. A visual-only caveat is silent to
          // VoiceOver, which is how a lower bound gets read as a total.
          Text("Some movements could not be attributed, so this is a floor, not a total.")
            .font(Tokens.Text.caption)
            .foregroundStyle(Tokens.Color.textTertiary)
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
        .foregroundStyle(Tokens.Color.textTertiary)
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

  @ViewBuilder private var redealSection: some View {
    if let onRedeal {
      Section {
        Stepper(value: $redealDayCount, in: 1...7) {
          // The count is the readout, so it is monospaced-digit to stop the row reflowing as it
          // changes.
          Text("\(redealDayCount) days")
            .font(Tokens.Text.label)
            .monospacedDigit()
        }
        Button {
          isConfirmingRedeal = true
        } label: {
          Label("Deal across \(redealDayCount) days", systemImage: "rectangle.3.group")
            .font(Tokens.Text.label)
        }
        .disabled(coverage.movementCount == 0 && days.allSatisfy { $0.movements.isEmpty })
      } header: {
        Text("Rearrange")
          .font(Tokens.Text.caption)
          .textCase(nil)
      } footer: {
        Text("Spreads the movements already in this plan across the days you choose, evening out "
          + "what each day trains. It does not add movements or decide how many sets you do.")
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.textTertiary)
      }
      // Replacing an arrangement someone built by hand is worth one tap of confirmation. It is not
      // destructive to training history -- nothing logged is touched -- so the wording says what it
      // actually replaces.
      .confirmationDialog(
        "Deal across \(redealDayCount) days?",
        isPresented: $isConfirmingRedeal,
        titleVisibility: .visible
      ) {
        Button("Deal again") { onRedeal(redealDayCount) }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("This replaces the current arrangement. Your logged workouts are not affected.")
      }
    }
  }

  // MARK: - Copy

  static func arrangementText(_ coverage: PlanCoverageSummary) -> String {
    let movements = coverage.movementCount == 1 ? "1 movement" : "\(coverage.movementCount) movements"
    let days = coverage.dayCount == 1 ? "1 day" : "\(coverage.dayCount) days"
    return "\(movements) across \(days)."
  }
}
