import Foundation

/// One row's worth of state: what is typed, and whether it has been written.
public struct SetSlot: Hashable, Sendable, Identifiable {
  public let id: UUID
  public var draft: SetEntryDraft
  public var isWarmup: Bool
  /// Non-nil once the set has been persisted. The row shows a filled check and stops being
  /// re-loggable; it is not removed, because the user still wants to see what they did.
  public var loggedSetID: SetID?
  /// The equipment on which this set was completed, preventing cross-machine load bleeding.
  public fileprivate(set) var loggedMachineID: MachineID?
  /// When the write completed, as the save reported it. `nil` while the row is unlogged.
  public fileprivate(set) var loggedAt: Date?
  /// The identity the next write of this row is saved under.
  ///
  /// Equal to `id` until the row is un-logged; then it is replaced, so logging the row again
  /// writes a new record instead of resurrecting the deleted one's primary key. `id` stays put,
  /// so the row keeps its place and its view identity through an undo.
  public fileprivate(set) var commandID: UUID

  public init(
    id: UUID = UUID(),
    draft: SetEntryDraft,
    isWarmup: Bool = false,
    loggedSetID: SetID? = nil,
    loggedMachineID: MachineID? = nil,
    loggedAt: Date? = nil,
    commandID: UUID? = nil
  ) {
    self.id = id
    self.draft = draft
    self.isWarmup = isWarmup
    self.loggedSetID = loggedSetID
    self.loggedMachineID = loggedMachineID
    self.loggedAt = loggedAt
    self.commandID = commandID ?? id
  }

  public var isLogged: Bool { loggedSetID != nil }
}

/// One exercise inside a live session: its rows, their prefills, and where those prefills
/// came from.
///
/// This is a value type on purpose. All of the fiddly logic — which suggestion belongs to
/// which row, what a newly added set should start at, whether the history came from a
/// different machine — is decided here and unit-tested, so the view is left with nothing to
/// get wrong. It holds no database handle, so it cannot query per render.
public struct ExerciseLogState: Hashable, Sendable, Identifiable {
  public let id: UUID
  public let exerciseID: ExerciseID
  /// Mutable, because a lifter can find their usual machine occupied and move mid-exercise.
  /// Changing it re-prefills the unlogged rows from the new machine's history — see
  /// `changeMachine`.
  public private(set) var machineID: MachineID?
  public let exerciseName: String
  /// Shown on the Lock Screen while resting, so the user knows which station they left.
  public private(set) var machineName: String?
  /// Set to the machine's real load step when known, so a suggested load is achievable.
  ///
  /// Mutable for the same reason `machineID` is: carrying the previous machine's step across a
  /// change announces records the new equipment cannot justify, and hides ones it can.
  public private(set) var machineIncrementKg: Double?
  public var slots: [SetSlot]
  /// Set when the prefills came from the same exercise on *different* equipment. Surfaced to
  /// the user verbatim rather than silently: 80 kg on another brand's machine is not this
  /// machine's 80 kg, and pretending otherwise is the kind of quiet lie this app is against.
  public private(set) var priorNote: String?

  private var prior: PriorPerformance?
  /// Updated only from successful log events, reconstruction of persisted sets, or an undo of
  /// one. The values are captured at that event; editing a draft cannot rewrite them.
  private var lastLoggedByKey: [ProgressionKey: PriorSetRecord] = [:]
  /// Every save this exercise has seen, in persistence order, with the values captured at that
  /// moment. Kept so an undo can rebuild `lastLoggedByKey` from what is still saved, rather than
  /// from row order or from drafts that may have been edited since.
  private var loggedEvents: [LoggedEvent] = []

  private struct LoggedEvent: Hashable, Sendable {
    let slotID: UUID
    let key: ProgressionKey
    let isWarmup: Bool
    let record: PriorSetRecord
  }

  public init(
    id: UUID = UUID(),
    exerciseID: ExerciseID,
    machineID: MachineID? = nil,
    exerciseName: String,
    machineName: String? = nil,
    machineIncrementKg: Double? = nil,
    prior: PriorPerformance?,
    priorNote: String? = nil,
    slots: [SetSlot]
  ) {
    self.id = id
    self.exerciseID = exerciseID
    self.machineID = machineID
    self.exerciseName = exerciseName
    self.machineName = machineName
    self.machineIncrementKg = machineIncrementKg
    self.prior = prior
    self.priorNote = priorNote
    self.slots = slots
    for slot in slots {
      rememberLogged(slot, completedAt: slot.loggedAt ?? Date(timeIntervalSince1970: 0))
    }
  }

  /// Builds an exercise's rows from a snapshot taken at session start.
  ///
  /// - Parameters:
  ///   - plannedSets: How many rows to open with. Falls back to the number of sets performed
  ///     last time, then to a single row — never to an invented "3 × 10".
  ///   - allowingOtherMachines: When true, an exercise with no history on *this* machine
  ///     borrows from the same exercise elsewhere and says so. When false, an unknown
  ///     machine simply has no suggestion, which is the honest default for a first session
  ///     on new equipment.
  public static func build(
    exerciseID: ExerciseID,
    machineID: MachineID? = nil,
    exerciseName: String,
    machineName: String? = nil,
    machineIncrementKg: Double? = nil,
    snapshot: PriorPerformanceSnapshot,
    plannedSets: Int? = nil,
    allowingOtherMachines: Bool = true
  ) -> ExerciseLogState {
    let key = ProgressionKey(exerciseID: exerciseID, machineID: machineID)

    var prior: PriorPerformance?
    var note: String?
    if let exact = snapshot.prior(for: key) {
      prior = exact
    } else if allowingOtherMachines,
      let fallback = snapshot.priorAllowingOtherMachines(for: key)
    {
      prior = fallback.performance
      if fallback.wasOtherMachine { note = "From another machine" }
    }

    let rowCount = plannedSets ?? prior.map { max($0.lastSets.count, 1) } ?? 1
    let slots = (0..<max(rowCount, 1)).map { index in
      SetSlot(draft: SetEntryDraft(suggestion: prior?.suggestion(forSetIndex: index)))
    }

    return ExerciseLogState(
      exerciseID: exerciseID,
      machineID: machineID,
      exerciseName: exerciseName,
      machineName: machineName,
      machineIncrementKg: machineIncrementKg,
      prior: prior,
      priorNote: note,
      slots: slots
    )
  }

  /// A set already written, as recovery sees it.
  public struct LoggedSetSummary: Hashable, Sendable {
    public let setID: SetID
    public let weightKg: Double
    public let reps: Int
    public let isWarmup: Bool
    public let machineID: MachineID?
    public let completedAt: Date

    public init(
      setID: SetID,
      weightKg: Double,
      reps: Int,
      isWarmup: Bool,
      machineID: MachineID? = nil,
      completedAt: Date = Date(timeIntervalSince1970: 0)
    ) {
      self.setID = setID
      self.weightKg = weightKg
      self.reps = reps
      self.isWarmup = isWarmup
      self.machineID = machineID
      self.completedAt = completedAt
    }
  }

  /// Rebuilds an exercise mid-workout, after the app was killed or the phone died.
  ///
  /// Recovery is reconstruction from what was written, never a guess. Sets that reached the
  /// database come back exactly as they were logged and are already ticked; only the rows that
  /// were never written are open, and those are prefilled from history the same way a fresh
  /// session would prefill them.
  ///
  /// Note what this deliberately does not do: it does not reopen a logged set for editing, and
  /// it does not drop a set because the plan said three and four were performed. The written
  /// record wins over the plan.
  public static func resume(
    exerciseID: ExerciseID,
    machineID: MachineID? = nil,
    exerciseName: String,
    machineName: String? = nil,
    machineIncrementKg: Double? = nil,
    loggedSets: [LoggedSetSummary],
    snapshot: PriorPerformanceSnapshot,
    plannedSets: Int? = nil,
    allowingOtherMachines: Bool = true
  ) -> ExerciseLogState {
    var state = build(
      exerciseID: exerciseID,
      machineID: machineID,
      exerciseName: exerciseName,
      machineName: machineName,
      machineIncrementKg: machineIncrementKg,
      snapshot: snapshot,
      plannedSets: plannedSets,
      allowingOtherMachines: allowingOtherMachines
    )

    // Written sets replace the opening rows, in the order they were performed.
    var slots: [SetSlot] = []
    slots.reserveCapacity(loggedSets.count)
    for logged in loggedSets {
      let slot = SetSlot(
        draft: SetEntryDraft(weightKg: logged.weightKg, reps: logged.reps),
        isWarmup: logged.isWarmup,
        loggedSetID: logged.setID,
        loggedMachineID: logged.machineID,
        loggedAt: logged.completedAt
      )
      slots.append(slot)
      state.rememberLogged(slot, completedAt: logged.completedAt)
    }

    // Then however many the plan still expects, prefilled but open. If more was performed than
    // planned, nothing is added and nothing is discarded.
    let target = plannedSets ?? max(state.slots.count, slots.count)
    let workingLogged = slots.count { !$0.isWarmup }
    if target > workingLogged {
      for index in workingLogged..<target {
        slots.append(SetSlot(draft: SetEntryDraft(suggestion: state.suggestion(forSetIndex: index))))
      }
    }

    state.slots = slots
    return state
  }

  public var progressionKey: ProgressionKey {
    ProgressionKey(exerciseID: exerciseID, machineID: machineID)
  }

  /// What the row at `index` should display in its "Last time" column.
  public func suggestion(forSetIndex index: Int) -> PriorSetRecord? {
    prior?.suggestion(forSetIndex: index)
  }

  /// What a row's "Last time" column should show: the working set at the same position last
  /// time, or `nil` for a warm-up. History excludes warm-ups, so a warm-up has no honest
  /// counterpart, and a working load beside it reads as a target it is not.
  public func previousSet(forSlotID id: UUID) -> PriorSetRecord? {
    guard let index = slots.firstIndex(where: { $0.id == id }), !slots[index].isWarmup else {
      return nil
    }
    return suggestion(forSetIndex: slots[..<index].count { !$0.isWarmup })
  }

  public var loggedCount: Int { slots.count(where: \.isLogged) }

  /// When the most recent of this exercise's saved sets was written, or `nil` when none is.
  public var lastLoggedAt: Date? { slots.compactMap(\.loggedAt).max() }

  /// Working sets only. Warm-ups are not part of the prescription.
  public var workingSetCount: Int { slots.count { !$0.isWarmup } }

  /// 1-based working-set number for a slot, skipping warm-ups, for display and for the
  /// Live Activity's "Set 2 of 4".
  public func workingOrdinal(ofSlotID id: UUID) -> Int? {
    guard let index = slots.firstIndex(where: { $0.id == id }), !slots[index].isWarmup
    else { return nil }
    return slots[..<index].count { !$0.isWarmup } + 1
  }

  /// The first row not yet written — what the log control should act on.
  public var nextUnloggedSlotID: UUID? {
    slots.first { !$0.isLogged }?.id
  }

  /// Adds a row.
  ///
  /// Within a session, the honest suggestion is what the user just did, not what they did
  /// last week: after logging 100 × 8, the next row opens at 100 × 8. Only when nothing has
  /// been logged yet does this fall back to history.
  ///
  /// A warm-up is different on both counts. It goes where it is performed: before the first
  /// working row still to do, so it becomes the next row rather than sitting under set 3 and
  /// jumping up after a relaunch, when recovery orders by save. And it is never prefilled from a
  /// working load: history holds no warm-ups, and a filled row is one tap from being saved, so a
  /// working load there would record a warm-up at working weight. It opens at the warm-up just
  /// logged on this equipment, if there is one, and otherwise empty.
  public mutating func appendSlot(isWarmup: Bool = false) {
    if isWarmup {
      let lastWarmup = loggedEvents.last { $0.isWarmup && $0.key == progressionKey }?.record
      let position = slots.firstIndex { !$0.isLogged && !$0.isWarmup } ?? slots.endIndex
      slots.insert(SetSlot(draft: SetEntryDraft(suggestion: lastWarmup), isWarmup: true), at: position)
      return
    }
    let suggestion: PriorSetRecord?
    if let logged = lastLoggedByKey[progressionKey] {
      suggestion = logged
    } else {
      suggestion = prior?.suggestion(forSetIndex: workingSetCount)
    }
    slots.append(SetSlot(draft: SetEntryDraft(suggestion: suggestion)))
  }

  /// Removes a row that was never saved. Refuses a logged row: removing saved training is a
  /// store operation, after which `unmarkLogged` reopens the row, not something a value type may
  /// decide on its own. Returns whether a row was removed.
  @discardableResult
  public mutating func removeSlot(id: UUID) -> Bool {
    guard let index = slots.firstIndex(where: { $0.id == id }), !slots[index].isLogged else {
      return false
    }
    slots.remove(at: index)
    return true
  }

  /// Moves this exercise to a different machine mid-session.
  ///
  /// Already-logged rows are left exactly as they are: those sets were performed on the previous
  /// machine, and rewriting them would be falsifying the record. Only the unlogged rows re-prefill,
  /// from the new machine's history, because that is what the lifter is about to do.
  ///
  /// `prior` is the new machine's history, which only the store can supply — this type holds no
  /// database handle and must not start pretending otherwise.
  public mutating func changeMachine(
    to machineID: MachineID?,
    machineName: String?,
    machineIncrementKg newIncrement: Double?,
    prior newPrior: PriorPerformance?,
    priorNote newNote: String? = nil
  ) {
    self.machineID = machineID
    self.machineName = machineName
    // Refreshed, not carried. A 2.5 kg plate step and a 10 kg selectorized stack demand different
    // margins before a load counts as a record.
    self.machineIncrementKg = newIncrement
    self.prior = newPrior
    self.priorNote = newNote

    for index in slots.indices where !slots[index].isLogged {
      let workingIndex = slots[..<index].count { !$0.isWarmup }
      slots[index].draft = SetEntryDraft(suggestion: newPrior?.suggestion(forSetIndex: workingIndex))
    }

    // Before any working set, the machine is usually being chosen as the lifter reaches it, so
    // open as many rows as last time on that machine, as `build` would have. Rows are only ever
    // added here, never removed, and never once work on this movement has been saved.
    if !slots.contains(where: { $0.isLogged && !$0.isWarmup }), let newPrior {
      var working = workingSetCount
      while working < newPrior.lastSets.count {
        slots.append(
          SetSlot(draft: SetEntryDraft(suggestion: newPrior.suggestion(forSetIndex: working)))
        )
        working += 1
      }
    }
  }

  /// Adopt an explicitly saved equipment constraint without re-prefilling any draft.
  public mutating func updateMachineIncrement(_ incrementKg: Double?) {
    machineIncrementKg = incrementKg
  }

  /// Marks a row written. Ignores an unknown id rather than trapping — a stale callback from
  /// a dismissed view should not crash a workout.
  public mutating func markLogged(
    slotID: UUID, setID: SetID, completedAt: Date = Date(timeIntervalSince1970: 0)
  ) {
    guard let index = slots.firstIndex(where: { $0.id == slotID }), !slots[index].isLogged else { return }
    slots[index].loggedSetID = setID
    slots[index].loggedMachineID = self.machineID
    slots[index].loggedAt = completedAt
    rememberLogged(slots[index], completedAt: completedAt)
  }

  /// Returns a saved row to unlogged, keeping its values as the draft, after its set was deleted.
  ///
  /// The counterpart of `markLogged`, with the same rule about order: call it only once the
  /// delete has succeeded. The row keeps its id and place, so editing a saved set is undo, then
  /// log again. It gets a fresh `commandID`, so that log writes a new record. The next-row
  /// prefill is rebuilt from the saves that remain, in the order they were made.
  ///
  /// Returns `false`, and changes nothing, for an unknown or unlogged row.
  @discardableResult
  public mutating func unmarkLogged(slotID: UUID) -> Bool {
    guard let index = slots.firstIndex(where: { $0.id == slotID }), slots[index].isLogged else {
      return false
    }
    slots[index].loggedSetID = nil
    slots[index].loggedMachineID = nil
    slots[index].loggedAt = nil
    slots[index].commandID = UUID()
    loggedEvents.removeAll { $0.slotID == slotID }
    lastLoggedByKey = [:]
    for event in loggedEvents where !event.isWarmup {
      lastLoggedByKey[event.key] = event.record
    }
    return true
  }

  /// Calls arrive in persistence order, independently of the row's display index.
  /// Recovery supplies the saved order and equipment, including a nil equipment ID.
  private mutating func rememberLogged(
    _ slot: SetSlot, completedAt: Date = Date(timeIntervalSince1970: 0)
  ) {
    guard slot.isLogged, let resolved = slot.draft.resolved() else { return }
    let key = ProgressionKey(exerciseID: exerciseID, machineID: slot.loggedMachineID)
    let record = PriorSetRecord(
      weightKg: resolved.weightKg, reps: resolved.reps, completedAt: completedAt
    )
    loggedEvents.append(
      LoggedEvent(slotID: slot.id, key: key, isWarmup: slot.isWarmup, record: record)
    )
    guard !slot.isWarmup else { return }
    lastLoggedByKey[key] = record
  }
}
