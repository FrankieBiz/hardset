import Foundation

/// One row's worth of state: what is typed, and whether it has been written.
public struct SetSlot: Hashable, Sendable, Identifiable {
  public let id: UUID
  public var draft: SetEntryDraft
  /// Working, warm-up, or a drop continuing the set above it.
  public var kind: SetKind
  /// Non-nil once the set has been persisted. The row shows a filled check and stops being
  /// re-loggable; it is not removed, because the user still wants to see what they did.
  public var loggedSetID: SetID?

  public init(
    id: UUID = UUID(),
    draft: SetEntryDraft,
    kind: SetKind = .working,
    loggedSetID: SetID? = nil
  ) {
    self.id = id
    self.draft = draft
    self.kind = kind
    self.loggedSetID = loggedSetID
  }

  /// Convenience for the many call sites that only ever distinguish warm-up from working.
  public init(
    id: UUID = UUID(),
    draft: SetEntryDraft,
    isWarmup: Bool,
    loggedSetID: SetID? = nil
  ) {
    self.init(
      id: id, draft: draft, kind: isWarmup ? .warmup : .working, loggedSetID: loggedSetID
    )
  }

  /// Read-only on purpose. Changing a row's kind goes through `kind`, because the interesting
  /// transitions are no longer two-valued: turning a drop into a working set and turning a
  /// warm-up into one are different edits, and a `Bool` cannot say which was meant.
  public var isWarmup: Bool { kind == .warmup }

  /// True for a row that continues the set above it rather than being a set of its own.
  public var isDropSet: Bool { kind == .drop }

  /// Whether this row adds one to the working-set count. False for warm-ups and for drops.
  public var countsAsWorkingSet: Bool { kind.countsAsWorkingSet }

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
  /// How the movement is loaded, when known.
  ///
  /// Needed because a bodyweight set is not an unloaded set. Five bodyweight movements ship, and
  /// logging a pull-up produced "0 kg x 8" -- indistinguishable from no load at all. The row uses
  /// this to say "added" instead, so zero reads as bodyweight rather than as nothing.
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
  /// The lifter's own note about this movement: a seat setting, a grip, which bar is bent.
  ///
  /// Distinct from `priorNote`, which is the app explaining where a suggestion came from. This is
  /// the user's text and the app never writes it. Empty means there is no note, not an empty one --
  /// so nothing is rendered and the menu offers to add rather than to edit.
  public var notes: String = ""
  /// Which superset this movement belongs to, or `nil` for a movement performed on its own.
  ///
  /// A plain `Int` scoped to the session rather than an identifier: a superset has no existence
  /// outside the workout it is performed in, and there is nothing to reference it from. The
  /// number is not shown; the UI derives a letter from position within the group.
  ///
  /// The lifter sets this and the app never does. Grouping is an ordering decision about their own
  /// movements — the same kind of arithmetic-over-authored-data that `docs/SPLITS-spec.md` permits
  /// — and it prescribes nothing, because it changes *when the rest timer is armed* and not how
  /// much work is done. Volume, records and history are untouched by it.
  public var supersetGroup: Int?

  private var prior: PriorPerformance?

  /// The heaviest load ever recorded for this movement, when there is any history at all.
  ///
  /// Derived from the prior already stored here, so it costs no extra state and re-bases for free
  /// when `changeMachine` swaps the prior out -- switching equipment should change what "heavy"
  /// means, because 80 kg on another brand's machine is not this machine's 80 kg.
  ///
  /// `nil` means there is nothing to compare against. Callers must treat that as unknown rather
  /// than as light: see `LoadIntensity.fraction(weightKg:heaviestKg:)`.
  public var heaviestPriorKg: Double? { prior?.heaviestSet?.weightKg }

  public init(
    id: UUID = UUID(),
    exerciseID: ExerciseID,
    machineID: MachineID? = nil,
    exerciseName: String,
    modality: ExerciseModality? = nil,
    machineName: String? = nil,
    machineIncrementKg: Double? = nil,
    prior: PriorPerformance?,
    priorNote: String? = nil,
    notes: String = "",
    supersetGroup: Int? = nil,
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
    self.notes = notes
    self.supersetGroup = supersetGroup
    self.slots = slots
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
    modality: ExerciseModality? = nil,
    machineName: String? = nil,
    machineIncrementKg: Double? = nil,
    snapshot: PriorPerformanceSnapshot,
    plannedSets: Int? = nil,
    notes: String = "",
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
      let suggestion = prior?.suggestion(forSetIndex: index)
      // A bodyweight movement with no history starts at zero *added* load, which is the truth
      // rather than a guess -- and it is what makes a pull-up loggable by typing only reps.
      // Without it the weight field is empty, `isLoggable` is false, and the lifter has to type a
      // "0" to record a set that had no added weight.
      if suggestion == nil, modality == .bodyweight {
        return SetSlot(draft: SetEntryDraft(weightKg: 0, reps: nil))
      }
      return SetSlot(draft: SetEntryDraft(suggestion: suggestion))
    }

    return ExerciseLogState(
      exerciseID: exerciseID,
      machineID: machineID,
      exerciseName: exerciseName,
      modality: modality,
      machineName: machineName,
      machineIncrementKg: machineIncrementKg,
      prior: prior,
      priorNote: note,
      notes: notes,
      slots: slots
    )
  }

  /// A set already written, as recovery sees it.
  public struct LoggedSetSummary: Hashable, Sendable {
    public let setID: SetID
    public let weightKg: Double
    public let reps: Int
    /// Effort as recorded, when the lifter recorded any.
    ///
    /// Absent here, a recovered workout showed every logged set as having no effort against it. The
    /// value was safe in the database the whole time -- the row on screen simply stopped agreeing
    /// with it, which for a field the lifter typed by hand reads exactly like losing it.
    public let rpe: Double?
    /// Which kind of row this was. Carried so a recovered workout puts a drop back as a drop
    /// rather than promoting it to a working set — which would silently add sets to the week.
    public let kind: SetKind

    public var isWarmup: Bool { kind == .warmup }

    public init(
      setID: SetID, weightKg: Double, reps: Int, rpe: Double? = nil, kind: SetKind
    ) {
      self.setID = setID
      self.weightKg = weightKg
      self.reps = reps
      self.rpe = rpe
      self.kind = kind
    }

    public init(
      setID: SetID, weightKg: Double, reps: Int, rpe: Double? = nil, isWarmup: Bool
    ) {
      self.init(
        setID: setID, weightKg: weightKg, reps: reps, rpe: rpe,
        kind: isWarmup ? .warmup : .working
      )
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
  /// - Parameter modality: How the movement is loaded. Absent here, every recovered bodyweight
  ///   movement came back as a loaded one: the row showed an empty weight field instead of "Body",
  ///   and a logged pull-up at zero added load read as no load at all. `PlannedExerciseRecord`
  ///   carries it and says in its own comment that it exists so a recovered session still knows a
  ///   pull-up is bodyweight -- it was simply never passed on from here.
  /// - Parameter notes: The lifter's own note for this movement, which otherwise vanished on
  ///   recovery even though it is stored on the exercise and reread on every other path.
  public static func resume(
    exerciseID: ExerciseID,
    machineID: MachineID? = nil,
    exerciseName: String,
    modality: ExerciseModality? = nil,
    machineName: String? = nil,
    machineIncrementKg: Double? = nil,
    loggedSets: [LoggedSetSummary],
    snapshot: PriorPerformanceSnapshot,
    plannedSets: Int? = nil,
    notes: String = "",
    allowingOtherMachines: Bool = true
  ) -> ExerciseLogState {
    var state = build(
      exerciseID: exerciseID,
      machineID: machineID,
      exerciseName: exerciseName,
      modality: modality,
      machineName: machineName,
      machineIncrementKg: machineIncrementKg,
      snapshot: snapshot,
      plannedSets: plannedSets,
      notes: notes,
      allowingOtherMachines: allowingOtherMachines
    )

    // Written sets replace the opening rows, in the order they were performed.
    var slots: [SetSlot] = loggedSets.map { logged in
      SetSlot(
        draft: SetEntryDraft(weightKg: logged.weightKg, reps: logged.reps, rpe: logged.rpe),
        kind: logged.kind,
        loggedSetID: logged.setID
      )
    }

    // Then however many the plan still expects, prefilled but open. If more was performed than
    // planned, nothing is added and nothing is discarded.
    //
    // Both sides of this are counted in WORKING SETS. `slots.count` was the raw row count, which
    // is a different unit from the `workingLogged` it is compared against -- so every warm-up or
    // drop already written added a phantom open row to the recovered movement. Log a warm-up and
    // three working sets, force-quit, and the workout came back asking for a fourth.
    let workingLogged = slots.count { $0.countsAsWorkingSet }
    let target = plannedSets ?? max(state.workingSetCount, workingLogged)
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

  /// Rows written, of any kind.
  ///
  /// This is a count of *records*, not of sets, and the two stopped agreeing once a drop could be
  /// written. Use it where the question is how much data an action destroys; use
  /// `loggedWorkingSetCount` where the question is how many sets were performed.
  public var loggedCount: Int { slots.count(where: \.isLogged) }

  /// Working sets only. Warm-ups are not part of the prescription, and a drop is part of the set
  /// it continues rather than a set of its own — so a set dropped twice still counts one.
  public var workingSetCount: Int { slots.count { $0.countsAsWorkingSet } }

  /// How many working sets have actually been written. What a superset round is counted in.
  public var loggedWorkingSetCount: Int {
    slots.count { $0.isLogged && $0.countsAsWorkingSet }
  }

  /// True while any non-warm-up row is still unwritten.
  ///
  /// Drops count here even though they do not count as sets: a chain with its drop still open is
  /// unfinished work, and a superset partner should not be waiting on it.
  public var hasRemainingWorkingSets: Bool {
    slots.contains { !$0.isLogged && $0.kind != .warmup }
  }

  /// 1-based working-set number for a slot, skipping warm-ups, for display and for the
  /// Live Activity's "Set 2 of 4".
  ///
  /// A drop reports the ordinal of the set it continues, because that is what it is part of.
  /// Numbering it separately would put a "Set 5 of 4" on the Lock Screen.
  public func workingOrdinal(ofSlotID id: UUID) -> Int? {
    guard let index = slots.firstIndex(where: { $0.id == id }) else { return nil }
    let slot = slots[index]
    guard slot.kind != .warmup else { return nil }
    let preceding = slots[..<index].count { $0.countsAsWorkingSet }
    // A working set is one past everything before it; a drop shares its parent's number, and the
    // parent is already inside `preceding`.
    return slot.countsAsWorkingSet ? preceding + 1 : max(preceding, 1)
  }

  /// Whether a drop row can be added right now.
  ///
  /// A drop continues the set above it, so there has to be one: the last row must be a working set
  /// or another drop. Offering it under a warm-up, or on an empty movement, would produce a row
  /// that continues nothing.
  public var canAppendDropSet: Bool {
    guard let last = slots.last else { return false }
    return last.kind != .warmup
  }

  /// Adds a drop continuing the last row.
  ///
  /// The load is seeded from the row it continues and the reps are left empty, and both halves of
  /// that are deliberate. The app does not choose the drop: no reduction percentage is established,
  /// and seeding the parent's load makes the reduction an edit the lifter makes rather than a
  /// number the app picked. Reps stay empty because a drop is taken to whatever it is taken to, and
  /// last week's rep count is not a prediction of that.
  ///
  /// Returns the new row's id, or `nil` when there is nothing to continue.
  @discardableResult
  public mutating func appendDropSet() -> UUID? {
    guard canAppendDropSet, let parent = slots.last else { return nil }
    let slot = SetSlot(
      draft: SetEntryDraft(weightKg: parent.draft.weightKg, reps: nil),
      kind: .drop
    )
    slots.append(slot)
    return slot.id
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
  public mutating func appendSlot(isWarmup: Bool = false) {
    // The *working-set* index, not the raw row count.
    //
    // History is indexed by working set -- last week's set 1, set 2, set 3 -- so counting warm-up
    // rows into the index shifted every later prefill by one per warm-up. Add a warm-up, then add a
    // working row, and the row that is working set 1 was prefilled from last week's set 2. The
    // badge already numbers rows this way (`ordinal(of:)` in the section view); this makes the
    // suggestion agree with the number printed next to it.
    let index = slots.count { $0.countsAsWorkingSet }
    let suggestion: PriorSetRecord? =
      lastLoggedRecord() ?? prior?.suggestion(forSetIndex: index)
    slots.append(SetSlot(draft: SetEntryDraft(suggestion: suggestion), isWarmup: isWarmup))
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
      // A drop continues the row above it, so it re-seeds from that row rather than from history.
      // There is no per-machine history of drops to read, and leaving one holding the previous
      // machine's load is the same lie `changeMachine` exists to prevent on every other row.
      if slots[index].kind == .drop {
        let parentWeight = index > 0 ? slots[index - 1].draft.weightKg : nil
        slots[index].draft = SetEntryDraft(weightKg: parentWeight, reps: nil)
        continue
      }
      let workingIndex = slots[..<index].count { $0.countsAsWorkingSet }
      slots[index].draft = SetEntryDraft(suggestion: newPrior?.suggestion(forSetIndex: workingIndex))
    }
  }

  /// Marks a row written. Ignores an unknown id rather than trapping — a stale callback from
  /// a dismissed view should not crash a workout.
  /// Removes an unlogged slot.
  ///
  /// Refuses a logged one: taking a set back is `markUnlogged`, and conflating the two would let a
  /// tap that means "I added a row by mistake" quietly delete a recorded set.
  @discardableResult
  public mutating func removeSlot(slotID: UUID) -> Bool {
    guard let index = slots.firstIndex(where: { $0.id == slotID }), !slots[index].isLogged else {
      return false
    }
    slots.remove(at: index)
    return true
  }

  /// Returns a slot to editable, keeping whatever numbers it holds.
  ///
  /// The values survive on purpose: un-logging is overwhelmingly how a typo gets corrected, so
  /// landing back on the row with 500 kg still in the field is what lets the lifter fix the digit
  /// rather than retype the set. Removing the row entirely is a separate action.
  ///
  /// Returns the set that was logged, so the caller knows what to delete from storage.
  @discardableResult
  public mutating func markUnlogged(slotID: UUID) -> SetID? {
    guard let index = slots.firstIndex(where: { $0.id == slotID }) else { return nil }
    let previous = slots[index].loggedSetID
    slots[index].loggedSetID = nil
    return previous
  }

  public mutating func markLogged(slotID: UUID, setID: SetID) {
    guard let index = slots.firstIndex(where: { $0.id == slotID }) else { return }
    slots[index].loggedSetID = setID
  }

  /// The most recent values actually written in this session, used to seed the next row.
  /// Warm-ups are skipped: a warm-up load must not become a working-set suggestion.
  private func lastLoggedRecord() -> PriorSetRecord? {
    for slot in slots.reversed() where slot.isLogged && slot.countsAsWorkingSet {
      if let resolved = slot.draft.resolved() {
        return PriorSetRecord(
          weightKg: resolved.weightKg,
          reps: resolved.reps,
          completedAt: Date(timeIntervalSince1970: 0)
        )
      }
    }
    return nil
  }
}
