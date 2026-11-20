import Foundation

/// The rules of the saved-workout editor, held apart from any view so they are tested without one.
///
/// A draft is a saved workout being made or changed: a name, and movements in order, each with a
/// set count, an optional rep range and rest, and the machine it was saved with, which can be
/// cleared so the start uses the one last used. It never knows when the workout was last done, or
/// any session: a plan is a plan, and what was done is the sessions' own.
public struct WorkoutDraft: Hashable, Sendable {
  public static let minimumSets = 1
  public static let maximumSets = 10
  /// The rest lengths offered, in seconds, nil first for "none". A saved rest is the lifter's own
  /// choice for the movement, never a default the app picked.
  public static let restChoices: [Int?] = [nil, 30, 45, 60, 90, 120, 180, 240, 300]
  /// What turning a rep range on starts from, the usual hypertrophy range.
  public static let defaultRepRange = RepRange(lower: 8, upper: 12)!
  /// What an added movement starts with: a plain three sets, which the lifter changes.
  public static let defaultSets = 3

  /// A rest length as the editor words it: "None", "30 s", "1 min", "90 s".
  public static func restLabel(_ seconds: Int?) -> String {
    guard let seconds else { return "None" }
    return seconds >= 60 && seconds % 60 == 0 ? "\(seconds / 60) min" : "\(seconds) s"
  }

  public struct Movement: Hashable, Sendable, Identifiable {
    public let id: UUID
    public let exerciseID: ExerciseID
    public let exerciseName: String
    public fileprivate(set) var machineID: MachineID?
    public fileprivate(set) var machineName: String?
    public fileprivate(set) var plannedSets: Int
    public fileprivate(set) var repRange: RepRange?
    public fileprivate(set) var restSeconds: Int?
  }

  public var name: String
  public let isNew: Bool
  public private(set) var movements: [Movement]
  private let id: TemplateID
  public let position: Int

  /// A workout being made, last in the rotation.
  public init(newAtPosition position: Int) {
    self.name = ""
    self.isNew = true
    self.movements = []
    self.id = TemplateID()
    self.position = position
  }

  /// A saved workout being changed. Its identity, place in the rotation and each movement's own
  /// identity are kept, so saving updates the plan rather than replacing it.
  ///
  /// `isNew` is for a plan that has not been saved yet but arrives complete, such as one made from a
  /// finished workout: it is edited and saved like any new workout, with no delete to offer.
  public init(template: WorkoutTemplate, isNew: Bool = false) {
    self.name = template.name
    self.isNew = isNew
    self.id = template.id
    self.position = template.position
    self.movements = template.exercises.map {
      Movement(
        id: $0.id, exerciseID: $0.exerciseID, exerciseName: $0.exerciseName,
        machineID: $0.machineID, machineName: $0.machineName, plannedSets: $0.plannedSets,
        repRange: $0.repRange, restSeconds: $0.restSeconds)
    }
  }

  public var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

  public var canSave: Bool { !trimmedName.isEmpty && !movements.isEmpty }

  /// The next thing a disabled Save is waiting for, name first.
  public var whatIsMissing: String? {
    if trimmedName.isEmpty { return "Name the workout." }
    if movements.isEmpty { return "Add a movement." }
    return nil
  }

  /// What the store saves. `lastDoneAt` is left out: it is read from sessions, never written here.
  public var template: WorkoutTemplate {
    WorkoutTemplate(
      id: id, name: trimmedName, position: position,
      exercises: movements.map {
        TemplateExercise(
          id: $0.id, exerciseID: $0.exerciseID, exerciseName: $0.exerciseName,
          machineID: $0.machineID, machineName: $0.machineName, plannedSets: $0.plannedSets,
          repRange: $0.repRange, restSeconds: $0.restSeconds)
      })
  }

  // MARK: - Movements

  /// Adds a movement with no machine, range or rest. The same movement may be added again, as a
  /// second block.
  public mutating func add(_ entry: CatalogEntry) {
    movements.append(
      Movement(
        id: UUID(), exerciseID: entry.id, exerciseName: entry.name, machineID: nil,
        machineName: nil, plannedSets: Self.defaultSets, repRange: nil, restSeconds: nil))
  }

  public mutating func remove(_ movementID: UUID) {
    movements.removeAll { $0.id == movementID }
  }

  /// Moves a movement by `offset` places, stopping at either end.
  public mutating func move(_ movementID: UUID, by offset: Int) {
    guard let index = movements.firstIndex(where: { $0.id == movementID }) else { return }
    let target = min(max(index + offset, 0), movements.count - 1)
    guard target != index else { return }
    movements.insert(movements.remove(at: index), at: target)
  }

  // MARK: - Sets, reps, rest, machine

  public mutating func setSets(_ movementID: UUID, to count: Int) {
    update(movementID) { $0.plannedSets = min(max(count, Self.minimumSets), Self.maximumSets) }
  }

  public mutating func stepSets(_ movementID: UUID, by delta: Int) {
    guard let current = movements.first(where: { $0.id == movementID })?.plannedSets else { return }
    setSets(movementID, to: current + delta)
  }

  /// Turns a rep range on at `defaultRepRange`. A movement that has one keeps it.
  public mutating func enableRepRange(_ movementID: UUID) {
    update(movementID) { if $0.repRange == nil { $0.repRange = Self.defaultRepRange } }
  }

  public mutating func clearRepRange(_ movementID: UUID) {
    update(movementID) { $0.repRange = nil }
  }

  /// Steps the bottom of the range, never below one rep or above the top.
  public mutating func stepRepLower(_ movementID: UUID, by delta: Int) {
    update(movementID) {
      guard let range = $0.repRange else { return }
      $0.repRange = RepRange(lower: min(max(range.lower + delta, 1), range.upper), upper: range.upper)
    }
  }

  /// Steps the top of the range, never below the bottom or above fifty.
  public mutating func stepRepUpper(_ movementID: UUID, by delta: Int) {
    update(movementID) {
      guard let range = $0.repRange else { return }
      $0.repRange = RepRange(lower: range.lower, upper: min(max(range.upper + delta, range.lower), 50))
    }
  }

  /// A rest of zero or less is no rest.
  public mutating func setRest(_ movementID: UUID, to seconds: Int?) {
    update(movementID) { $0.restSeconds = (seconds ?? 0) > 0 ? seconds : nil }
  }

  /// Forgets the saved machine, so a start uses the one last used for the movement at that gym.
  public mutating func clearMachine(_ movementID: UUID) {
    update(movementID) {
      $0.machineID = nil
      $0.machineName = nil
    }
  }

  private mutating func update(_ movementID: UUID, _ change: (inout Movement) -> Void) {
    guard let index = movements.firstIndex(where: { $0.id == movementID }) else { return }
    change(&movements[index])
  }
}
