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
  /// Changing it re-prefills the open rows the lifter has not typed into — see `changeMachine`.
  public private(set) var machineID: MachineID?
  public let exerciseName: String
  /// How the load is applied, when the movement's row names a known modality. The live screen
  /// reads it to decide whether a machine is a meaningful thing to record: a barbell, dumbbell or
  /// bodyweight movement has none, so it is offered no machine chip.
  public let modality: ExerciseModality?
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
  /// The reps the plan asks for, when it asks for any. Targets and the rep-range floor of a
  /// "beat last time" mark exist only with one.
  public private(set) var repRange: RepRange?

  private var prior: PriorPerformance?
  private var weightUnit: WeightUnit
  /// False for work with no added load to step up, which only ever adds reps.
  private var addsLoad: Bool
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
    modality: ExerciseModality? = nil,
    prior: PriorPerformance?,
    priorNote: String? = nil,
    repRange: RepRange? = nil,
    weightUnit: WeightUnit = .kilograms,
    addsLoad: Bool = true,
    slots: [SetSlot]
  ) {
    self.id = id
    self.exerciseID = exerciseID
    self.machineID = machineID
    self.exerciseName = exerciseName
    self.modality = modality
    self.machineName = machineName
    self.machineIncrementKg = machineIncrementKg
    self.prior = prior
    self.priorNote = priorNote
    self.repRange = repRange
    self.weightUnit = weightUnit
    self.addsLoad = addsLoad
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
    modality: ExerciseModality? = nil,
    snapshot: PriorPerformanceSnapshot,
    plannedSets: Int? = nil,
    allowingOtherMachines: Bool = true,
    repRange: RepRange? = nil,
    weightUnit: WeightUnit = .kilograms,
    addsLoad: Bool = true
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

    let rowCount = max(plannedSets ?? prior.map { max($0.lastSets.count, 1) } ?? 1, 1)
    let targets = Self.targets(
      prior: prior, priorNote: note, repRange: repRange, count: rowCount,
      incrementKg: machineIncrementKg, unit: weightUnit, addsLoad: addsLoad
    )
    let slots = (0..<rowCount).map { index in
      SetSlot(draft: Self.draft(prior: prior, workingIndex: index, target: targets[index]))
    }

    return ExerciseLogState(
      exerciseID: exerciseID,
      machineID: machineID,
      exerciseName: exerciseName,
      machineName: machineName,
      machineIncrementKg: machineIncrementKg,
      modality: modality,
      prior: prior,
      priorNote: note,
      repRange: repRange,
      weightUnit: weightUnit,
      addsLoad: addsLoad,
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
    modality: ExerciseModality? = nil,
    loggedSets: [LoggedSetSummary],
    snapshot: PriorPerformanceSnapshot,
    plannedSets: Int? = nil,
    allowingOtherMachines: Bool = true,
    repRange: RepRange? = nil,
    weightUnit: WeightUnit = .kilograms,
    addsLoad: Bool = true
  ) -> ExerciseLogState {
    var state = build(
      exerciseID: exerciseID,
      machineID: machineID,
      exerciseName: exerciseName,
      machineName: machineName,
      machineIncrementKg: machineIncrementKg,
      modality: modality,
      snapshot: snapshot,
      plannedSets: plannedSets,
      allowingOtherMachines: allowingOtherMachines,
      repRange: repRange,
      weightUnit: weightUnit,
      addsLoad: addsLoad
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
    // `build` never creates warm-up rows, so its row count is a working-row count; comparing it
    // with every logged set would turn each logged warm-up into a phantom working row.
    let workingLogged = slots.count { !$0.isWarmup }
    let target = max(plannedSets ?? max(state.slots.count, workingLogged), 1)
    if target > workingLogged {
      // Targets go to the rows still open, each at its own working position. A set already written
      // is a fact and keeps the values it was logged with.
      let targets = Self.targets(
        prior: state.prior, priorNote: state.priorNote, repRange: repRange, count: target,
        incrementKg: machineIncrementKg, unit: weightUnit, addsLoad: addsLoad
      )
      for index in workingLogged..<target {
        slots.append(
          SetSlot(draft: Self.draft(prior: state.prior, workingIndex: index, target: targets[index]))
        )
      }
    }

    state.slots = slots
    return state
  }

  public var progressionKey: ProgressionKey {
    ProgressionKey(exerciseID: exerciseID, machineID: machineID)
  }

  /// Whether recording a machine is a meaningful choice for this movement.
  ///
  /// A barbell, dumbbell or bodyweight movement has no machine: the bar, the dumbbells or the body
  /// is the equipment, so the live screen offers no machine chip for it. A movement whose modality
  /// is unknown keeps the chip, because a machine may still be what it was done on, and one that
  /// already records a machine keeps it so the record can be corrected.
  public var canChooseMachine: Bool {
    if machineID != nil { return true }
    switch modality {
    case .barbell, .dumbbell, .bodyweight: return false
    case .machine, .cable, nil: return true
    }
  }

  /// What the row at `index` should be prefilled with. Past last session's count it repeats the
  /// final set, which is a reasonable draft but not history; the "Last time" column uses
  /// `previousSet(forSlotID:)`, which never repeats.
  public func suggestion(forSetIndex index: Int) -> PriorSetRecord? {
    prior?.suggestion(forSetIndex: index)
  }

  /// What a row's "Last time" column should show: the working set at the same position last
  /// time, or `nil` for a warm-up. History excludes warm-ups, so a warm-up has no honest
  /// counterpart, and a working load beside it reads as a target it is not. A row beyond last
  /// session's count is `nil` too: no such set was performed, so none is stated.
  public func previousSet(forSlotID id: UUID) -> PriorSetRecord? {
    guard let index = slots.firstIndex(where: { $0.id == id }), !slots[index].isWarmup else {
      return nil
    }
    return prior?.recorded(atSetIndex: slots[..<index].count { !$0.isWarmup })
  }

  /// How a logged set compares with the same set last time on this machine, or `nil` when there is
  /// nothing honest to say.
  ///
  /// It says nothing for a row not yet logged, for a warm-up, when the history was borrowed from
  /// other equipment, and for a set done on a machine the lifter has since left: that set was
  /// performed somewhere this history does not describe. Otherwise it compares the values the set
  /// was saved with against its partner, with the movement's rep floor deciding whether a heavier
  /// set with fewer reps still counts.
  public func comparison(forSlotID id: UUID) -> SetComparison? {
    guard priorNote == nil,
      let slot = slots.first(where: { $0.id == id }),
      slot.isLogged, !slot.isWarmup,
      slot.loggedMachineID == machineID,
      let resolved = slot.draft.resolved()
    else { return nil }
    return SetComparison.compare(
      weightKg: resolved.weightKg, reps: resolved.reps,
      against: previousSet(forSlotID: id), repFloor: repRange?.lower
    )
  }

  /// One target per working row, or nil for every row when targets do not apply.
  ///
  /// They apply only to a movement with a rep range, and only when the history is this exact
  /// machine's: a prior carrying a note was borrowed from other equipment, and another machine's
  /// 80 kg is not a base this machine's next step can be added to.
  private static func targets(
    prior: PriorPerformance?, priorNote: String?, repRange: RepRange?, count: Int,
    incrementKg: Double?, unit: WeightUnit, addsLoad: Bool
  ) -> [SetTarget?] {
    guard let repRange, let prior, priorNote == nil, !prior.lastSets.isEmpty else {
      return Array(repeating: nil, count: max(count, 0))
    }
    return OverloadTarget.targets(
      lastSets: prior.lastSets, range: repRange, setCount: count,
      incrementKg: incrementKg, unit: unit, addsLoad: addsLoad
    )
  }

  /// A row's draft: its target when there is one, and otherwise what history suggests, as before.
  private static func draft(
    prior: PriorPerformance?, workingIndex: Int, target: SetTarget?
  ) -> SetEntryDraft {
    let suggestion = prior?.suggestion(forSetIndex: workingIndex)
    if let target { return SetEntryDraft(target: target, suggestion: suggestion) }
    return SetEntryDraft(suggestion: suggestion)
  }

  public var loggedCount: Int { slots.count(where: \.isLogged) }

  /// When the sets the "Last time" column quotes were done, and whether they came from this
  /// machine. `nil` when there is no prior, or the prior has no sets. It reports the source; it
  /// never changes the prefill or the target.
  public var lastTimeSource: LastTimeSource? {
    LastTimeSource(prior: prior, borrowed: priorNote != nil)
  }

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
  /// machine, and rewriting them would be falsifying the record.
  ///
  /// Open rows re-prefill, because that is what the lifter is about to do, with two rules about
  /// whose numbers they are:
  ///
  /// - A row the lifter has typed into is theirs and is left alone, whole. Re-prefilling is for a row
  ///   still holding the number the app put there; a number the lifter chose is never replaced
  ///   without asking, and a machine change is not a question.
  /// - What was just done on the destination in this workout wins over its history, as it does for
  ///   `appendSlot`, so the card never says two different things. A machine with a set saved
  ///   today is also never "borrowed": that label is for a machine with nothing of its own.
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

    // The destination's own sets from this workout, newest working set. A note means the caller
    // fell back to other equipment's history; with sets of its own saved today the destination has
    // no use for that fallback, neither for prefill nor for the "Last time" column, so both go
    // rather than leave another machine's numbers standing as this one's.
    let today = lastLoggedByKey[progressionKey]
    let borrowedIsUnneeded = today != nil && newNote != nil
    let prior = borrowedIsUnneeded ? nil : newPrior
    let note = borrowedIsUnneeded ? nil : newNote
    self.prior = prior
    self.priorNote = note

    // Before any working set, the machine is usually being chosen as the lifter reaches it, so
    // open as many rows as last time on that machine, as `build` would have. Rows are only ever
    // added here, never removed, and never once work on this movement has been saved. They are
    // prefilled with the rest, just below.
    if !slots.contains(where: { $0.isLogged && !$0.isWarmup }), let prior {
      var working = workingSetCount
      while working < prior.lastSets.count {
        slots.append(SetSlot(draft: SetEntryDraft(suggestion: nil)))
        working += 1
      }
    }

    // Warm-ups keep their drafts: history holds no warm-ups, and a working load in a warm-up row
    // is one tap from recording a warm-up at working weight (see `appendSlot`). Open working rows
    // re-prefill unless typed into: from today's set on this machine if there is one, otherwise
    // from the machine's history, with a target when that can build one.
    let targets = Self.targets(
      prior: prior, priorNote: note, repRange: repRange, count: workingSetCount,
      incrementKg: newIncrement, unit: weightUnit, addsLoad: addsLoad
    )
    for index in slots.indices where !slots[index].isLogged && !slots[index].isWarmup {
      guard !slots[index].draft.holdsTypedValues else { continue }
      if let today {
        slots[index].draft = SetEntryDraft(suggestion: today)
      } else {
        let workingIndex = slots[..<index].count { !$0.isWarmup }
        slots[index].draft = Self.draft(
          prior: prior, workingIndex: workingIndex, target: targets[workingIndex])
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
    rebuildLastLogged()
    return true
  }

  /// Corrects the weight and reps of a saved row, after the correction was written.
  ///
  /// The counterpart of `markLogged` for a number that was wrong, with the same rule about order:
  /// call it only once the write has succeeded. Unlike `unmarkLogged` the row never leaves its
  /// saved state: it keeps its id, its place, its set id, the machine it was saved on, its save
  /// time and its write identity, and only the two figures change. What the next row opens at and
  /// what the row is compared with follow the corrected figures, because the values captured at
  /// the save are replaced by them. The draft's suggestion and target, which say where the row's
  /// numbers first came from, are left alone.
  ///
  /// Returns `false`, and changes nothing, for an unknown or unlogged row, and for a draft that is
  /// not a complete set: the same predicate that gates writing one.
  @discardableResult
  public mutating func correctLogged(slotID: UUID, to draft: SetEntryDraft) -> Bool {
    guard let index = slots.firstIndex(where: { $0.id == slotID }), slots[index].isLogged,
      let resolved = draft.resolved()
    else { return false }
    slots[index].draft.weightKg = resolved.weightKg
    slots[index].draft.reps = resolved.reps
    if let eventIndex = loggedEvents.firstIndex(where: { $0.slotID == slotID }) {
      let event = loggedEvents[eventIndex]
      loggedEvents[eventIndex] = LoggedEvent(
        slotID: event.slotID, key: event.key, isWarmup: event.isWarmup,
        record: PriorSetRecord(
          weightKg: resolved.weightKg, reps: resolved.reps, completedAt: event.record.completedAt
        )
      )
      rebuildLastLogged()
    }
    return true
  }

  /// The last working save per machine, rebuilt from the saves that remain, in the order they
  /// were made.
  private mutating func rebuildLastLogged() {
    lastLoggedByKey = [:]
    for event in loggedEvents where !event.isWarmup {
      lastLoggedByKey[event.key] = event.record
    }
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

extension ExerciseLogState {
  /// The row that is the workout's primary action: the first row, in workout order, that is not
  /// logged and can be, or `nil` when there is none.
  ///
  /// "Can be" is the predicate that gates writing a set, `SetEntryDraft.isLoggable`, so the answer
  /// is always a row one tap will log. That is not the same as `nextUnloggedSlotID`, the first row
  /// not yet written, which may be a blank warm-up with nothing to log; the primary action skips
  /// it for the working set behind it. A screen with one accent gives it to this row.
  public static func primarySlotID(in exercises: [ExerciseLogState]) -> UUID? {
    for exercise in exercises {
      if let slot = exercise.slots.first(where: { !$0.isLogged && $0.draft.isLoggable }) {
        return slot.id
      }
    }
    return nil
  }
}

extension SetEntryDraft {
  /// Whether the lifter has put a number in this row that the app did not.
  ///
  /// A draft is seeded from a target or a suggestion and carries it, so "typed" is "differs from
  /// the seed": it needs no flag for every writer (keypad, steppers, a restored undo) to remember
  /// to raise. A row blank by seeding is typed once either field has a value. A value typed back to
  /// exactly the seed is indistinguishable from it, and is the same number either way.
  fileprivate var holdsTypedValues: Bool {
    let seedWeight = target?.weightKg ?? suggestion?.weightKg
    let seedReps = target?.reps ?? suggestion?.reps
    return weightKg != seedWeight || reps != seedReps
  }
}
