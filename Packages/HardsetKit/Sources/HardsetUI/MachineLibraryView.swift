import HardsetCore
import SwiftUI

/// Reviewing the machines you have named, outside a workout.
///
/// # Why this is a review surface and not a setup flow
///
/// Equipment in this app is learned by naming it at the rack, deliberately: the ancestor app opened
/// with a gym-setup screen that nobody completed, and every set after it was logged against nothing.
/// So **nothing here prompts you to fill anything in, and nothing is blocked by it being empty.**
/// Naming at the rack stays the only path that matters; this is where you fix a typo, set a stack
/// step you learned later, see what you have, and put away a machine you no longer use.
///
/// # Why archive and never delete
///
/// Sets logged against a machine keep their reference, and invariant #10 forbids merging two
/// machines' history — so hard-deleting one would orphan a real series that the lifter performed.
/// Archiving hides it from the pickers and keeps the history intact, and it is reversible from the
/// "Put away" section, which is the part that makes it safe to offer at all.
public struct MachineLibraryView: View {
  /// A gym, for the chooser.
  public struct GymChoice: Hashable, Sendable, Identifiable {
    public let id: GymID
    public let name: String

    public init(id: GymID, name: String) {
      self.id = id
      self.name = name
    }
  }

  /// One machine, already assembled by the caller. The view performs no lookups: a list that
  /// resolves each row's detail lazily is how twenty machines become eighty queries.
  public struct Row: Hashable, Sendable, Identifiable {
    public let id: MachineID
    public let name: String
    public let stackIncrementKg: Double?
    public let isArchived: Bool
    public let linkedExerciseNames: [String]
    public let lastUsed: Date?
    public let heaviestKg: Double?
    public let heaviestReps: Int?
    public let workingSetCount: Int

    public init(
      id: MachineID,
      name: String,
      stackIncrementKg: Double?,
      isArchived: Bool,
      linkedExerciseNames: [String],
      lastUsed: Date?,
      heaviestKg: Double?,
      heaviestReps: Int?,
      workingSetCount: Int
    ) {
      self.id = id
      self.name = name
      self.stackIncrementKg = stackIncrementKg
      self.isArchived = isArchived
      self.linkedExerciseNames = linkedExerciseNames
      self.lastUsed = lastUsed
      self.heaviestKg = heaviestKg
      self.heaviestReps = heaviestReps
      self.workingSetCount = workingSetCount
    }
  }

  private let gyms: [GymChoice]
  @Binding private var selectedGym: GymID?
  private let rows: [Row]
  private let unit: WeightUnit
  private let onAddMachine: () -> Void
  private let onRename: (Row) -> Void
  private let onSetStep: (Row) -> Void
  private let onSetArchived: (Row, Bool) -> Void

  public init(
    gyms: [GymChoice],
    selectedGym: Binding<GymID?>,
    rows: [Row],
    unit: WeightUnit,
    onAddMachine: @escaping () -> Void,
    onRename: @escaping (Row) -> Void,
    onSetStep: @escaping (Row) -> Void,
    onSetArchived: @escaping (Row, Bool) -> Void
  ) {
    self.gyms = gyms
    self._selectedGym = selectedGym
    self.rows = rows
    self.unit = unit
    self.onAddMachine = onAddMachine
    self.onRename = onRename
    self.onSetStep = onSetStep
    self.onSetArchived = onSetArchived
  }

  private var active: [Row] { rows.filter { !$0.isArchived } }
  private var archived: [Row] { rows.filter(\.isArchived) }

  public var body: some View {
    List {
      if gyms.count > 1 {
        Section {
          Picker("Gym", selection: $selectedGym) {
            ForEach(gyms) { gym in
              Text(gym.name).tag(GymID?.some(gym.id))
            }
          }
        }
      }

      if rows.isEmpty {
        Section {
          // States how machines actually arrive, so this reads as "nothing yet" rather than as a
          // form the lifter has failed to fill in.
          ContentUnavailableView {
            Label("No machines here yet", systemImage: "dumbbell")
          } description: {
            Text(
              "Machines appear here as you name them while logging. You can add one now if you "
                + "would rather, but nothing needs setting up first."
            )
          } actions: {
            Button("Add a machine", action: onAddMachine)
          }
        }
      } else {
        Section {
          ForEach(active) { row($0) }
        } header: {
          Text("Machines")
        } footer: {
          Text(
            "Loads are tracked per machine and never combined \u{2014} two chest presses are two "
              + "histories, on purpose."
          )
        }

        if !archived.isEmpty {
          Section {
            ForEach(archived) { row($0) }
          } header: {
            Text("Put away")
          } footer: {
            // The reassurance that makes archiving safe to tap.
            Text("Hidden from the pickers. Every set you logged on them is still counted.")
          }
        }
      }
    }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button(action: onAddMachine) {
          Label("Add a machine", systemImage: "plus")
        }
      }
    }
  }

  private func row(_ row: Row) -> some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
      HStack(spacing: Tokens.Spacing.snug) {
        Text(row.name)
          .font(Tokens.Text.label)
          .foregroundStyle(Tokens.Color.textPrimary)
        Spacer(minLength: 0)
        Menu {
          Button("Rename") { onRename(row) }
          Button(row.stackIncrementKg == nil ? "Set stack step" : "Change stack step") {
            onSetStep(row)
          }
          if row.isArchived {
            Button("Put back") { onSetArchived(row, false) }
          } else {
            Button("Put away") { onSetArchived(row, true) }
          }
        } label: {
          Label("Options", systemImage: "ellipsis.circle")
            .labelStyle(.iconOnly)
            .foregroundStyle(Tokens.Color.textSecondary)
            // Inside the label and shaped, not applied to the `Menu`: a menu's hit region is its
            // label's content shape, so a frame hung on the `Menu` grew the layout footprint and
            // left the added area untappable. This is the only route to rename, set the stack step,
            // or put a machine away. Same pattern as ExerciseSectionView.swift:244.
            .frame(minWidth: Tokens.minimumTapTarget, minHeight: Tokens.minimumTapTarget)
            .contentShape(Rectangle())
        }
      }

      if !detail(row).isEmpty {
        Text(detail(row))
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(.vertical, Tokens.Spacing.hairline)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(spokenLabel(row))
  }

  /// What this machine is for, what you press on it, and when you were last there.
  ///
  /// Assembled as one wrapping line rather than a grid of labelled fields: at accessibility text
  /// sizes a four-column row of tiny values is unreadable, and every part of this is optional
  /// anyway — a machine named and never used has none of it, which is a real and useful state.
  private func detail(_ row: Row) -> String {
    var parts: [String] = []
    if !row.linkedExerciseNames.isEmpty {
      parts.append(row.linkedExerciseNames.joined(separator: ", "))
    }
    if let kg = row.heaviestKg, let reps = row.heaviestReps {
      let value = unit.displayValue(fromKilograms: kg)
      parts.append("Best \(Self.trimmed(value)) \(unit.abbreviation) \u{00D7} \(reps)")
    }
    if let step = row.stackIncrementKg {
      let value = unit.displayValue(fromKilograms: step)
      parts.append("Steps \(Self.trimmed(value)) \(unit.abbreviation)")
    }
    if let last = row.lastUsed {
      parts.append("Last used \(last.formatted(.relative(presentation: .named)))")
    } else if row.workingSetCount == 0 {
      // Named and never trained on. Worth saying plainly: it is usually a duplicate created by a
      // typo, and this list is where a lifter finds it.
      parts.append("Never used")
    }
    return parts.joined(separator: " \u{2022} ")
  }

  private func spokenLabel(_ row: Row) -> String {
    var parts = [row.name]
    if row.isArchived { parts.append("put away") }
    let detail = detail(row)
    if !detail.isEmpty {
      parts.append(detail.replacingOccurrences(of: " \u{2022} ", with: ", "))
    }
    return parts.joined(separator: ", ")
  }

  /// Drops a trailing ".0" so a whole number reads as one. The rounding itself already happened in
  /// `displayValue`, which is the single place conversion and precision live.
  public static func trimmed(_ value: Double) -> String {
    value == value.rounded()
      ? String(Int(value.rounded()))
      : String(format: "%.1f", value)
  }
}
