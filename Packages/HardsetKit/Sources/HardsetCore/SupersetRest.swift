import Foundation

/// When a logged set should arm the rest timer.
///
/// This exists because both of the shapes the logger was missing are, at bottom, changes to *when
/// rest starts* rather than to what is recorded. A superset is movements taken back to back with
/// the rest moved to the end of the round; a drop set is a set continued at a lower load with the
/// rest withheld until the chain finishes. Neither asserts anything about training — the app is
/// not choosing a rest length, or a drop percentage, or which movements pair well. It is arming a
/// timer at the moment the lifter's own arrangement says the work has actually stopped.
///
/// Pure and Foundation-only, like every other decision in this module, so the fiddly part is
/// tested directly rather than through a coordinator and a database.
public enum SupersetRest {
  /// Whether logging `slotID` should start the rest timer.
  ///
  /// Call this *after* the slot has been marked logged, since a round is counted in written sets.
  ///
  /// - Parameters:
  ///   - exercise: The movement the set was logged in, in its post-write state.
  ///   - exercises: Every movement in the session, so a superset partner's progress is visible.
  public static func shouldArmRest(
    afterLogging slotID: UUID,
    in exercise: ExerciseLogState,
    session exercises: [ExerciseLogState]
  ) -> Bool {
    guard let index = exercise.slots.firstIndex(where: { $0.id == slotID }) else { return false }

    // Warm-ups never armed rest and still do not. The lifter is still warming up.
    guard exercise.slots[index].kind != .warmup else { return false }

    // A drop follows immediately, with no rest — that is what makes it a drop rather than another
    // set. Withholding here is what the whole feature is: the chain rests once, at its end.
    //
    // Read off the next row rather than from the row just logged, so it holds for a chain of any
    // length and for the last link, which does arm.
    if exercise.slots.indices.contains(index + 1), exercise.slots[index + 1].kind == .drop {
      return false
    }

    guard let group = exercise.supersetGroup else { return true }

    // Inside a superset the round is what rests, not the set. The round is over once every other
    // movement in the group has caught up — or has nothing left to do, which is the case that
    // stops a partner with fewer sets from blocking rest forever once it is finished.
    let rounds = exercise.loggedWorkingSetCount
    let partners = exercises.filter { $0.supersetGroup == group && $0.id != exercise.id }
    let caughtUp = partners.allSatisfy {
      $0.loggedWorkingSetCount >= rounds || !$0.hasRemainingWorkingSets
    }
    return caughtUp
  }
}

/// Reading a session's superset structure back out, for display.
public enum SupersetGrouping {
  /// The letter to show against a movement, or `nil` when it is performed on its own.
  ///
  /// Derived from position within the group rather than stored, so it cannot drift out of step
  /// with the order on screen. The group number itself is never shown: it is an implementation
  /// detail of which movements belong together, and "Superset 7" would mean nothing to anyone.
  public static func letter(
    for exercise: ExerciseLogState,
    in exercises: [ExerciseLogState]
  ) -> String? {
    guard let group = exercise.supersetGroup else { return nil }
    let members = exercises.filter { $0.supersetGroup == group }
    // A group of one is not a superset. This is reachable — remove one of a pair and the other is
    // left holding a group number — and showing a lone "A" would be a promise of a partner that
    // is not there.
    guard members.count > 1,
      let position = members.firstIndex(where: { $0.id == exercise.id })
    else { return nil }
    return letter(at: position)
  }

  /// A, B, … Z, then AA, AB, … for the lifter who supersets twenty-seven movements.
  static func letter(at position: Int) -> String {
    var remaining = position
    var out = ""
    repeat {
      let scalar = UnicodeScalar(UInt8(65 + remaining % 26))
      out = String(Character(scalar)) + out
      remaining = remaining / 26 - 1
    } while remaining >= 0
    return out
  }

  /// The next unused group number in a session.
  public static func nextGroup(in exercises: [ExerciseLogState]) -> Int {
    (exercises.compactMap(\.supersetGroup).max() ?? 0) + 1
  }

  /// Every movement sharing `exercise`'s group, in session order, including it.
  /// Empty when it is not in a superset.
  public static func members(
    of exercise: ExerciseLogState,
    in exercises: [ExerciseLogState]
  ) -> [ExerciseLogState] {
    guard let group = exercise.supersetGroup else { return [] }
    let members = exercises.filter { $0.supersetGroup == group }
    return members.count > 1 ? members : []
  }
}
