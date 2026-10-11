import Foundation

/// What Finish should do, decided from the rows rather than from a view's guess.
public enum FinishDecision: Hashable, Sendable {
  /// Every row holding a set was logged. Finish without asking.
  case finish
  /// Rows hold complete values that were never logged. Ask, and say how many will be lost.
  case confirmUnlogged(count: Int)
  /// Nothing was logged at all. There is nothing to save, so the choice is to discard.
  case discardEmpty
}

public enum FinishFlow {
  /// Counts rows that look like sets, meaning complete and loggable, that were never logged.
  /// Empty and half-typed rows are not sets and are not counted. Zero logged sets is never a
  /// "finish": an empty workout in history is noise that looks like a session that happened.
  public static func decision(for exercises: [ExerciseLogState]) -> FinishDecision {
    let slots = exercises.flatMap(\.slots)
    guard slots.contains(where: \.isLogged) else { return .discardEmpty }
    let unlogged = slots.count { !$0.isLogged && $0.draft.isLoggable }
    return unlogged == 0 ? .finish : .confirmUnlogged(count: unlogged)
  }

  public static func unloggedTitle(count: Int) -> String {
    count == 1
      ? "1 set wasn't logged and won't be saved"
      : "\(count) sets weren't logged and won't be saved"
  }

  public static let discardTitle = "Nothing was logged"
  public static let discardMessage = "There's nothing to save, so this workout will be discarded."
}

/// The set the lifter is about to do: the one the screen emphasises and scrolls to.
public struct ActiveSet: Hashable, Sendable {
  /// `ExerciseLogState.id`.
  public let exerciseID: UUID
  /// `SetSlot.id`.
  public let slotID: UUID

  public init(exerciseID: UUID, slotID: UUID) {
    self.exerciseID = exerciseID
    self.slotID = slotID
  }

  /// The first unlogged row after `lastLogged` in session order, wrapping to the first unlogged
  /// row from the top.
  ///
  /// It follows the lifter rather than the plan: someone who jumps to a free machine is doing
  /// that set now. With nothing logged yet, or a `lastLogged` that was since deleted, it is the
  /// first open row. Nil when everything is logged.
  public static func next(in exercises: [ExerciseLogState], after lastLogged: UUID?) -> ActiveSet? {
    let rows = exercises.flatMap { exercise in
      exercise.slots.map { (exercise: exercise.id, slot: $0) }
    }
    let start = lastLogged.flatMap { id in rows.firstIndex { $0.slot.id == id } }.map { $0 + 1 } ?? 0
    let ordered = rows[start...] + rows[..<start]
    return ordered.first { !$0.slot.isLogged }.map {
      ActiveSet(exerciseID: $0.exercise, slotID: $0.slot.id)
    }
  }
}
