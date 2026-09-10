import HardsetCore
import HardsetStore
import HardsetUI
import SwiftUI

/// The planner, wired to the store.
///
/// Composition only: every decision about what may be said about a plan lives in
/// `SplitPlanAssessment`, and the arrangement itself is computed by `SplitDealer`. This screen
/// reads, renders, and writes back.
@MainActor
public struct SplitPlannerScreen: View {
  private let splits: SplitStore
  private let catalog: CatalogSeeder
  private let gyms: GymStore
  private let volume: VolumeStore
  /// Defines the lifter's own movements. Optional for the same reason the logger's is: the create
  /// affordance is hidden rather than shown-and-broken when there is no store to write to.
  private let exercises: ExerciseStore?
  /// What machine stack steps are shown in. The planner's machine sheet printed them in kilograms
  /// regardless of the lifter's setting.
  private let unit: WeightUnit

  @State private var plans: [SplitRecord] = []
  @State private var isLoading = true
  @State private var isLoadingPlan = false
  @State private var loadFailed = false
  @State private var selected: SplitID?
  @State private var days: [PlannedDay] = []
  @State private var coverage = PlanCoverageSummary(
    movementCount: 0, dayCount: 0, uncreditedMuscleNames: [],
    leastCreditedModelledNames: [], isLowerBound: false
  )

  /// Completed-workout movements available when the lifter explicitly chooses to build a first
  /// plan from history. Held in state so rendering never queries the database.
  @State private var completedHistoryMovementCount = 0
  /// The gym's machines, read once per reload. Resolving a machine name per row would be a database
  /// read per render -- the exact thing `PriorPerformanceSnapshot` exists to make unrepresentable in
  /// the logger, and no more acceptable here.
  @State private var machineCache: [MachineRecord] = []

  /// Plans put away, so archiving is a round trip. Held in state rather than read in `body`.
  @State private var archived: [SplitRecord] = []

  @State private var isNamingPlan = false
  @State private var isRenamingPlan = false
  @State private var isConfirmingArchive = false
  @State private var renamingDay: PlannedDay?
  @State private var addingToDay: DayTarget?
  @State private var choosingMachineFor: PlannedMovementRow?
  /// The slot whose movement is being replaced. Distinct from `addingToDay` because the picker's
  /// selection means something different: it rewrites a slot rather than appending one.
  @State private var swappingMovement: PlannedMovementRow?
  /// The movement being renamed from the plan. Only ever a row the lifter owns.
  @State private var renamingMovement: PlannedMovementRow?
  @State private var pickerQuery = ""
  /// The picker's contents, read once per query rather than once per render. Both source reads
  /// used to sit in the sheet's ViewBuilder, so every keystroke in the search field was two table
  /// scans.
  @State private var pickerEntries: [CatalogEntry] = []
  @State private var isPickerLoading = false
  @State private var pickerRecent: [ExerciseID] = []
  /// Movements this gym is known to have equipment for, and its name for the heading. The logger
  /// showed this section and the planner did not, though planning is the one moment the lifter is
  /// choosing without standing at the rack.
  @State private var availableHere: Set<ExerciseID> = []
  @State private var gymName: String?
  @State private var isCreatingExercise = false
  @State private var isAddingMachine = false
  @State private var machineNameSuggestions: [MachineNameSheet.MachineNameSuggestionRow] = []
  @State private var machineOptions: (recent: [MachineOption], others: [MachineOption]) = ([], [])
  @State private var isMachinePickerLoading = false
  /// Movements offerable as a template for one the lifter defines. Curated only.
  @State private var templates: [CatalogEntry] = []
  /// Why the last write failed, in the lifter's words. A `try?` here would leave a button that
  /// appears to do nothing, which is the failure mode this codebase has already shipped once.
  @State private var failure: String?
  @State private var startingDayID: SplitDayID?

  /// Starts a day as today's workout. Supplied by the root, which owns the session, and nil while a
  /// workout is already open.
  private let onStartDay: ((PlannedDayStart) -> Void)?

  /// Where the next workout will be, owned by the root.
  ///
  /// Passed in rather than read here. This screen used to resolve its own gym with
  /// `lastUsedGym()` in three places, which is a *different* question from "where am I training
  /// next" — the lifter changes that on the Train tab. So after switching gyms the planner went on
  /// offering the old gym's machines and marking the old gym's movements as available here, while
  /// the workout it started would be somewhere else. One owner, one answer.
  private let gymID: GymID?

  public init(
    splits: SplitStore,
    catalog: CatalogSeeder,
    gyms: GymStore,
    volume: VolumeStore,
    exercises: ExerciseStore? = nil,
    unit: WeightUnit = .kilograms,
    gymID: GymID? = nil,
    onStartDay: ((PlannedDayStart) -> Void)? = nil
  ) {
    self.splits = splits
    self.catalog = catalog
    self.gyms = gyms
    self.volume = volume
    self.exercises = exercises
    self.unit = unit
    self.gymID = gymID
    self.onStartDay = onStartDay
  }

  public var body: some View {
    content
      .task { await reload() }
      // Changing gyms on the Train tab changes which machines this screen may offer and which
      // movements it can say there is equipment for. Without this the planner kept the old gym's
      // answers until it was rebuilt.
      .onChange(of: gymID) { _, _ in Task { await reload() } }
      .sheet(isPresented: $isNamingPlan) { namePlanSheet }
      .sheet(isPresented: $isRenamingPlan) { renamePlanSheet }
      .sheet(item: $renamingDay) { day in renameDaySheet(day) }
      .sheet(item: $addingToDay) { target in movementPicker(for: target.id) }
      .sheet(item: $choosingMachineFor) { movement in machinePicker(for: movement) }
      .sheet(item: $swappingMovement) { movement in movementSwapPicker(for: movement) }
      .sheet(item: $renamingMovement) { movement in renameMovementSheet(movement) }
      .alert(
        "Could not complete that",
        isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
      ) {
        Button("OK") { failure = nil }
      } message: {
        Text(failure ?? "")
      }
  }

  @ViewBuilder private var content: some View {
    if isLoading, plans.isEmpty {
      ProgressView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if loadFailed, plans.isEmpty {
      ContentUnavailableView {
        Label("Could not read your plans", systemImage: "exclamationmark.triangle")
      } description: {
        Text("Your plans and logged workouts are safe.")
      } actions: {
        Button("Try again") { Task { await reload() } }
      }
    } else if plans.isEmpty {
      UnavailableStateView(
        title: "No plans yet",
        systemImage: "square.split.2x2",
        message: "A plan arranges movements you already train across the days you choose."
      ) {
        Button {
          isNamingPlan = true
        } label: {
          Text("New plan")
            .frame(
              minWidth: Tokens.minimumTapTarget,
              minHeight: Tokens.minimumTapTarget
            )
            .contentShape(Rectangle())
        }
      }
      .frame(maxHeight: .infinity)
    } else {
      planner
    }
  }

  @ViewBuilder private var planner: some View {
    SplitPlannerView(
      days: days,
      coverage: coverage,
      historyMovementCount: completedHistoryMovementCount,
      onRedistribute: redistribute,
      onStartFromHistory: startFromHistory,
      onAddMovement: { addingToDay = DayTarget(id: $0) },
      onRemoveMovement: removeMovement,
      onChooseMachine: { choosingMachineFor = $0 },
      onRenameDay: { renamingDay = $0 },
      onAddDay: addDay,
      onDeleteDay: deleteDay,
      onMoveMovement: moveMovement,
      onReorderMovement: reorderMovement,
      onSetTargetSets: setTargetSets,
      onSwapMovement: { swappingMovement = $0 },
      // Nil when the catalogue store is absent, for the same reason `onCreate` is: the rename
      // cannot be performed, so the control must not appear.
      onRenameMovement: exercises == nil ? nil : { renamingMovement = $0 },
      onMoveDay: moveDay,
      onStartDay: startDayHandler,
      startingDayID: startingDayID
    )
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Menu {
          Picker("Plan", selection: $selected) {
            ForEach(plans) { plan in
              Text(plan.name).tag(Optional(plan.id))
            }
          }
          Divider()
          Button {
            isNamingPlan = true
          } label: {
            Label("New plan", systemImage: "plus")
          }
          Button {
            addDay()
          } label: {
            Label("Add day", systemImage: "calendar.badge.plus")
          }
          // Renaming and putting a plan away were both unreachable: a plan created by mistake, or
          // named in a hurry, was permanent. The store could do both all along.
          Button {
            isRenamingPlan = true
          } label: {
            Label("Rename plan", systemImage: "pencil")
          }
          if !archived.isEmpty {
            Menu {
              ForEach(archived) { plan in
                Button {
                  restore(plan)
                } label: {
                  Label(plan.name, systemImage: "arrow.uturn.backward")
                }
              }
            } label: {
              Label("Archived plans", systemImage: "archivebox")
            }
          }
          Button(role: .destructive) {
            isConfirmingArchive = true
          } label: {
            Label("Put this plan away", systemImage: "archivebox")
          }
        } label: {
          Label("Plans", systemImage: "ellipsis.circle")
        }
      }
    }
    .confirmationDialog(
      "Put this plan away?",
      isPresented: $isConfirmingArchive,
      titleVisibility: .visible
    ) {
      Button("Put away") { archiveCurrent() }
      Button("Cancel", role: .cancel) {}
    } message: {
      // Says what actually happens, which is not deletion. The restore path is in the same menu.
      Text(
        "It moves to Archived plans and can be brought back. Your logged workouts are not "
          + "affected.")
    }
    .onChange(of: selected) { _, _ in Task { await reloadPlan() } }
    .overlay {
      if isLoadingPlan {
        ProgressView("Updating plan…")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(Tokens.Color.ground.opacity(0.9))
      }
    }
  }

  // MARK: - Sheets

  @ViewBuilder private var namePlanSheet: some View {
    NameEntrySheet(
      title: "New plan",
      prompt: "Plan name",
      footnote: "A plan arranges movements you already train. It does not prescribe sets.",
      confirmLabel: "Create",
      onConfirm: { name in
        isNamingPlan = false
        write { selected = try splits.createSplit(name: name) }
      },
      onCancel: { isNamingPlan = false }
    )
  }

  @ViewBuilder private var renamePlanSheet: some View {
    // Prefilled. "Rename workout" once opened blank and made the lifter retype a name the app
    // already had, which is what `split(_:)` is read for here.
    let current = selected.flatMap { id in plans.first { $0.id == id } }
    NameEntrySheet(
      title: "Rename plan",
      prompt: "Plan name",
      confirmLabel: "Save",
      initialValue: current?.name ?? "",
      onConfirm: { name in
        isRenamingPlan = false
        guard let selected else { return }
        write { try splits.renameSplit(selected, to: name) }
      },
      onCancel: { isRenamingPlan = false }
    )
  }

  /// Replaces the movement in one slot, keeping the slot.
  ///
  /// The same picker as adding, with two differences that matter: selecting rewrites the entry
  /// rather than appending one, and creating a movement here swaps to the new movement instead of
  /// adding a second row. `onCreate` is passed for the same reason every other picker passes it --
  /// searching for a movement the catalogue lacks must not be a dead end, which is what
  /// `AffordanceWiringTests` sweeps the source for.
  @ViewBuilder private func movementSwapPicker(for movement: PlannedMovementRow) -> some View {
    NavigationStack {
      ExercisePickerView(
        query: $pickerQuery,
        entries: pickerEntries,
        isLoading: isPickerLoading,
        recent: pickerRecent,
        availableHere: availableHere,
        gymName: gymName,
        onSelect: { entry in
          swappingMovement = nil
          pickerQuery = ""
          // Selecting the movement already in the slot is a no-op the store would happily perform,
          // clearing the machine for nothing. Cheaper to not ask.
          guard entry.id != movement.exerciseID else { return }
          write { try splits.setExercise(entry.id, forEntry: movement.id) }
        },
        onCreate: exercises == nil ? nil : { isCreatingExercise = true }
      )
      .sheet(isPresented: $isCreatingExercise) {
        NewExerciseSheet(
          initialName: pickerQuery,
          templates: templates,
          gymName: gymName,
          onCreate: { draft in
            isCreatingExercise = false
            createExercise(draft, swappingInto: movement)
          },
          onCancel: { isCreatingExercise = false }
        )
      }
      .navigationTitle("Swap movement")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            swappingMovement = nil
            pickerQuery = ""
          }
        }
      }
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
    }
    // The same two loads the add picker does, and for the same reason. Attaching them to only one
    // of two pickers is this codebase's dominant defect shape -- capability built in full, one call
    // site forgetting the last hop -- and here it would open the sheet on an empty catalogue.
    .task(id: pickerQuery) { await refreshPickerEntries() }
    .task { await refreshPickerRelevance() }
  }

  /// Renames a movement the lifter owns, without leaving the plan.
  ///
  /// Reachable from Settings → Machines too. Offered here because the plan is where a wrong name is
  /// actually read, and walking to another screen to fix a typo is how a typo stays.
  @ViewBuilder private func renameMovementSheet(_ movement: PlannedMovementRow) -> some View {
    NameEntrySheet(
      title: "Rename movement",
      prompt: "Movement name",
      confirmLabel: "Save",
      initialValue: movement.name,
      onConfirm: { name in
        renamingMovement = nil
        guard let exercises else { return }
        write { try exercises.rename(movement.exerciseID, to: name) }
      },
      onCancel: { renamingMovement = nil }
    )
  }

  @ViewBuilder private func renameDaySheet(_ day: PlannedDay) -> some View {
    NameEntrySheet(
      title: "Rename day",
      prompt: "Day name",
      confirmLabel: "Save",
      initialValue: day.name,
      onConfirm: { name in
        renamingDay = nil
        write { try splits.renameDay(day.id, to: name) }
      },
      onCancel: { renamingDay = nil }
    )
  }

  @ViewBuilder private func movementPicker(for dayID: SplitDayID) -> some View {
    // The lifter's own movements first is handled inside the picker by `recent`. The full catalogue
    // stays reachable, because planning is exactly when someone adds a movement they have not done
    // yet -- and choosing it themselves is not the app recommending it.
    NavigationStack {
      ExercisePickerView(
        query: $pickerQuery,
        entries: pickerEntries,
        isLoading: isPickerLoading,
        recent: pickerRecent,
        availableHere: availableHere,
        gymName: gymName,
        onSelect: { entry in
          addingToDay = nil
          pickerQuery = ""
          write { try splits.addEntry(to: dayID, exercise: entry.id) }
        },
        // The dead end this screen shipped with. Both create affordances live inside the picker
        // and both are gated on `onCreate`; the logger passed it and this call site passed
        // nothing, so searching the planner for a movement the catalogue lacks ended at
        // "Nothing matches" with no way forward. Reproduced on device before it was fixed.
        onCreate: exercises == nil ? nil : { isCreatingExercise = true }
      )
      // Attached to the picker, not beside the enclosing sheet: two `.sheet` modifiers on one
      // anchor silently drop the second, which has already cost this codebase a screen that never
      // presented.
      .sheet(isPresented: $isCreatingExercise) {
        NewExerciseSheet(
          // Prefilled from the search that found nothing, so the name is not typed twice.
          initialName: pickerQuery,
          templates: templates,
          gymName: gymName,
          onCreate: { draft in
            isCreatingExercise = false
            createExercise(draft, addingTo: dayID)
          },
          onCancel: { isCreatingExercise = false }
        )
      }
      .navigationTitle("Add movement")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            addingToDay = nil
            pickerQuery = ""
          }
        }
      }
      // Inline, not large: a large title truncates rather than wraps, and at accessibility text
      // sizes this sheet was headed "Add movem...".
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
    }
    // Searching hits the database, so it happens here rather than inside the picker, which stays
    // free of storage. Re-run on change rather than filtered in memory, so a movement created
    // from the empty state appears without reopening the sheet.
    .task(id: pickerQuery) { await refreshPickerEntries() }
    // Once per presentation. Relevance does not change while the sheet is open.
    .task { await refreshPickerRelevance() }
  }

  @ViewBuilder private func machinePicker(for movement: PlannedMovementRow) -> some View {
    NavigationStack {
      MachinePickerView(
        recent: machineOptions.recent,
        others: machineOptions.others,
        // The machine already named must show as chosen, or reopening the sheet looks like nothing
        // was ever set.
        selected: movement.machineID,
        unit: unit,
        onSelect: { machineID in
          choosingMachineFor = nil
          write {
            try splits.setMachine(machineID, forEntry: movement.id)
          }
        },
        // The planner used the same picker as the live workout but omitted its creation path, so a
        // machine named while planning had to be created somewhere else and then found again.
        onAddMachine: gymID == nil ? nil : { isAddingMachine = true }
      )
      .navigationTitle("Machine")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { choosingMachineFor = nil }
        }
      }
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .sheet(isPresented: $isAddingMachine) {
        MachineNameSheet(
          suggestions: machineNameSuggestions,
          onConfirm: { name in addMachine(named: name, for: movement) },
          onCancel: { isAddingMachine = false }
        )
      }
      .overlay {
        if isMachinePickerLoading {
          ProgressView("Loading machines…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Tokens.Color.ground.opacity(0.92))
        }
      }
      .task(id: movement.id) { await refreshMachinePicker(for: movement.exerciseID) }
    }
  }

  /// Machines this movement has actually been performed on, and then the rest of the gym.
  ///
  /// Same split as the live session's picker, so "You've used these" means the same thing in both
  /// places.
  private static func option(for record: MachineRecord) -> MachineOption {
    MachineOption(
      id: record.id, displayName: record.displayName, stackIncrementKg: record.stackIncrementKg
    )
  }

  /// What the row must say about a planned machine, beyond its name.
  ///
  /// The two cases are different claims. `.elsewhere` is a comparison between two gyms, so it needs
  /// both. `.noGym` needs neither: `SplitStore.machine(_:usableAt:counterparts:)` returns nil the
  /// moment there is no gym, so the day opens unbound and the named machine on the row is not the
  /// machine the workout will use. The app knows that with certainty, and used to drop it silently.
  private func machineNote(_ id: MachineID?) -> PlannedMachineNote {
    guard let id else { return .none }
    guard let gymID else { return .noGym }
    guard let machine = machineCache.first(where: { $0.id == id }) else { return .none }
    return machine.gymID == gymID ? .none : .elsewhere
  }

  private func refreshPickerEntries() async {
    let query = pickerQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    isPickerLoading = true
    if !query.isEmpty {
      try? await Task.sleep(for: .milliseconds(120))
    }
    guard !Task.isCancelled else { return }
    let catalog = catalog
    let result = await readOffMain {
      query.isEmpty ? try catalog.selectableExercises() : try catalog.search(query)
    }
    guard !Task.isCancelled, query == pickerQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    else { return }
    switch result {
    case .success(let entries):
      pickerEntries = entries
    case .failure:
      // An unreadable catalogue must not block planning: the picker says it has nothing and the
      // create affordance is still there, which is the one path that does not need the catalogue.
      pickerEntries = []
    }
    isPickerLoading = false
  }

  /// What to surface above the alphabet. Both inputs are facts -- the lifter's own history and the
  /// building's inventory -- so neither turns the picker into a recommendation.
  private func refreshPickerRelevance() async {
    let splits = splits
    let catalog = catalog
    let gyms = gyms
    let gymID = gymID
    let result = await readOffMain {
      let recent = try splits.loggedMovements(limit: 8)
      // Curated only, for the reason the logger's copy states: inheriting from another hand-typed
      // row copies one person's guess twice while looking like corroboration.
      let templates = try catalog.selectableExercises().filter(\.isCurated)
      guard let gymID else {
        return (recent, templates, Set<ExerciseID>(), String?.none)
      }
      let available = try gyms.exercisesWithEquipment(at: gymID)
      let name = try gyms.gyms().first { $0.id == gymID }?.name
      return (recent, templates, available, name)
    }
    guard !Task.isCancelled else { return }
    switch result {
    case .success(let loaded):
      pickerRecent = loaded.0
      templates = loaded.1
      availableHere = loaded.2
      gymName = loaded.3
    case .failure:
      pickerRecent = []
      templates = []
      availableHere = []
      gymName = nil
    }
  }

  private func refreshMachinePicker(for exerciseID: ExerciseID) async {
    guard let gymID else {
      machineOptions = ([], [])
      machineNameSuggestions = []
      isMachinePickerLoading = false
      return
    }
    isMachinePickerLoading = true
    let gyms = gyms
    let result = await readOffMain {
      let recent = try gyms.recentMachines(for: exerciseID, at: gymID)
      let recentIDs = Set(recent.map(\.id))
      let others = try gyms.machines(at: gymID).filter { !recentIDs.contains($0.id) }
      let suggestions = try gyms.machineNameSuggestions(at: gymID)
      return (recent, others, suggestions)
    }
    guard !Task.isCancelled else { return }
    switch result {
    case .success(let loaded):
      machineOptions = (loaded.0.map(Self.option(for:)), loaded.1.map(Self.option(for:)))
      machineNameSuggestions = loaded.2.map {
        MachineNameSheet.MachineNameSuggestionRow(
          name: $0.name,
          isAlreadyHere: $0.existingHere != nil,
          otherGymNames: $0.otherGymNames
        )
      }
    case .failure:
      // An unreadable gym must not block planning. The picker still offers "Not recorded" and the
      // plan itself stays intact.
      machineOptions = ([], [])
      machineNameSuggestions = []
    }
    isMachinePickerLoading = false
  }

  // MARK: - Writes

  /// Records a movement the lifter defined, then puts it straight on the day they were filling.
  ///
  /// Added rather than handed back to the list, for the reason the logger does the same: they
  /// described it in order to plan it, and making them find it again afterwards is a second
  /// decision for no reason.
  private func createExercise(_ draft: NewExerciseDraft, addingTo dayID: SplitDayID) {
    guard let exercises else { return }
    addingToDay = nil
    pickerQuery = ""
    write {
      let id = try exercises.createExercise(
        name: draft.name,
        modality: draft.modality,
        primaryMuscle: draft.primaryMuscle,
        inheriting: draft.inheriting
      )
      let machineID: MachineID?
      if let machineName = draft.machineName, let gymID {
        machineID = try gyms.resolveMachine(
          at: gymID, named: machineName, forExercise: id
        ).id
      } else {
        machineID = nil
      }
      try splits.addEntry(to: dayID, exercise: id, machine: machineID)
    }
  }

  /// Creates a movement the catalogue lacks and swaps the slot onto it.
  ///
  /// The machine half of the draft is honoured exactly as it is when adding: a machine named here
  /// is resolved within this gym and linked to the new movement, so the swap can land on a slot that
  /// already knows its machine rather than one that lost the old one and gained nothing.
  private func createExercise(_ draft: NewExerciseDraft, swappingInto movement: PlannedMovementRow) {
    guard let exercises else { return }
    swappingMovement = nil
    pickerQuery = ""
    write {
      let id = try exercises.createExercise(
        name: draft.name,
        modality: draft.modality,
        primaryMuscle: draft.primaryMuscle,
        inheriting: draft.inheriting
      )
      try splits.setExercise(id, forEntry: movement.id)
      if let machineName = draft.machineName, let gymID {
        let machineID = try gyms.resolveMachine(at: gymID, named: machineName, forExercise: id).id
        try splits.setMachine(machineID, forEntry: movement.id)
      }
    }
  }

  /// Creates or reuses a machine without leaving the planner, links it to this movement, selects
  /// it, and closes both sheets. The typed name is resolved within this gym, so choosing an
  /// existing Panatta row cannot create a duplicate empty history.
  private func addMachine(named name: String, for movement: PlannedMovementRow) {
    guard let gymID else { return }
    do {
      let machineID = try gyms.resolveMachine(
        at: gymID, named: name, forExercise: movement.exerciseID
      ).id
      try splits.setMachine(machineID, forEntry: movement.id)
      isAddingMachine = false
      choosingMachineFor = nil
      failure = nil
      Task { await reload() }
    } catch {
      failure = error.localizedDescription
    }
  }

  /// Runs a write and surfaces its failure instead of swallowing it.
  private func write(_ work: () throws -> Void) {
    do {
      try work()
      failure = nil
      Task { await reload() }
    } catch {
      failure = error.localizedDescription
    }
  }

  private func archiveCurrent() {
    guard let selected else { return }
    write {
      try splits.archiveSplit(selected)
      // Drop the selection so `reload` picks whatever is left rather than showing a plan the
      // lifter just put away.
      self.selected = nil
    }
  }

  private func restore(_ plan: SplitRecord) {
    write {
      try splits.unarchiveSplit(plan.id)
      selected = plan.id
    }
  }

  private func addDay() {
    guard let selected else { return }
    let next = days.count + 1
    write { try splits.addDay(to: selected, name: "Day \(next)") }
  }

  private func deleteDay(_ day: PlannedDay) {
    write { try splits.deleteDay(day.id) }
  }

  private func removeMovement(_ movement: PlannedMovementRow) {
    write { try splits.removeEntry(movement.id) }
  }

  private func moveMovement(_ movement: PlannedMovementRow, to dayID: SplitDayID) {
    write { try splits.moveEntry(movement.id, toDay: dayID) }
  }

  /// Reorders within the movement's own day. `moveEntry` has always taken a target position; the
  /// only interaction that reached it passed a day and dropped the position.
  private func reorderMovement(_ movement: PlannedMovementRow, to position: Int) {
    guard let dayID = dayID(containing: movement) else { return }
    write { try splits.moveEntry(movement.id, toDay: dayID, at: position) }
  }

  /// Which day a row is on. Read from the rendered days rather than the database: the view already
  /// holds the answer, and a query here would be one per menu tap.
  private func dayID(containing movement: PlannedMovementRow) -> SplitDayID? {
    days.first { $0.movements.contains(movement) }?.id
  }

  private func setTargetSets(_ movement: PlannedMovementRow, to sets: Int?) {
    write { try splits.setTargetSets(sets, forEntry: movement.id) }
  }

  private func moveDay(_ day: PlannedDay, to position: Int) {
    write { try splits.moveDay(day.id, to: position) }
  }

  /// `nil` when the root supplied no handler, so the button is absent rather than inert.
  ///
  /// Spelled as a property with an explicit type rather than
  /// `onStartDay == nil ? nil : startDay` inline: a ternary between a method reference and `nil`
  /// needs an optional-closure conversion the type checker cannot do, and it fails with "failed to
  /// produce diagnostic" rather than naming a cause. The same trap is recorded for `repeatHandler`.
  private var startDayHandler: ((PlannedDay) -> Void)? {
    guard onStartDay != nil else { return nil }
    return { day in startDay(day) }
  }

  /// Hands the day's movements to the root, which owns the session.
  ///
  /// A failure here must be stated rather than swallowed: a "Start this day" that silently does
  /// nothing is the same defect class as the empty-plan deal button.
  private func startDay(_ day: PlannedDay) {
    guard let onStartDay, startingDayID == nil else { return }
    startingDayID = day.id
    let dayID = day.id
    let dayName = day.name
    Task {
      defer { startingDayID = nil }
      let result = await readOffMain { try splits.plannedExercises(for: dayID, at: gymID) }
      switch result {
      case .success(let plan):
        guard !plan.isEmpty else {
          failure = "There is nothing on \(dayName) to start."
          return
        }
        onStartDay(PlannedDayStart(dayID: dayID, name: dayName, exercises: plan))
      case .failure(let error):
        failure = error.localizedDescription
      }
    }
  }

  private func redistribute(_ dayCount: Int) {
    guard let selected else { return }
    write {
      let attribution = try volume.attributionIndex()
      let existing = try splits.plan(for: selected).allMovements
      guard !existing.isEmpty else { return }
      let plan = SplitDealer.deal(
        movements: existing,
        across: dayCount,
        attribution: attribution
      )
      try splits.replace(selected, with: plan)
    }
  }

  private func startFromHistory(_ dayCount: Int) {
    guard let selected else { return }
    write {
      let movements = try splits.completedWorkoutMovements()
      guard !movements.isEmpty else { return }
      let plan = SplitDealer.deal(
        movements: movements, across: dayCount, attribution: try volume.attributionIndex())
      try splits.replace(selected, with: plan)
    }
  }

  // MARK: - Reads

  private func reload() async {
    isLoading = true
    loadFailed = false
    let splits = splits
    let result = await readOffMain { (try splits.splits(), try splits.archivedSplits()) }
    guard !Task.isCancelled else { return }
    switch result {
    case .success(let loaded):
      plans = loaded.0
      archived = loaded.1
      if selected == nil || !plans.contains(where: { $0.id == selected }) {
        selected = plans.first?.id
      }
      isLoading = false
      await reloadPlan()
    case .failure:
      plans = []
      archived = []
      loadFailed = true
      isLoading = false
    }
  }

  private func reloadPlan() async {
    guard let selected else {
      days = []
      completedHistoryMovementCount = 0
      coverage = PlanCoverageSummary(
        movementCount: 0, dayCount: 0, uncreditedMuscleNames: [],
        leastCreditedModelledNames: [], isLowerBound: false
      )
      isLoadingPlan = false
      return
    }

    isLoadingPlan = true
    let splits = splits
    let catalog = catalog
    let gyms = gyms
    let volume = volume
    let result = await readOffMain {
      let attribution = try volume.attributionIndex()
      let machines = try gyms.machinesEverywhere()
      let selectable = try catalog.selectableExercises()
      let dayRecords = try splits.days(in: selected)
      let lastTrained = try splits.lastTrainedByDay(in: selected)
      var entriesByDay: [SplitDayID: [SplitEntryRecord]] = [:]
      var retiredByDay: [SplitDayID: Set<ExerciseID>] = [:]
      var allExerciseIDs: Set<ExerciseID> = []
      for day in dayRecords {
        let entries = try splits.entries(in: day.id)
        entriesByDay[day.id] = entries
        retiredByDay[day.id] = try splits.retiredMovements(in: day.id)
        allExerciseIDs.formUnion(entries.map(\.exerciseID))
      }
      let named = try catalog.entries(for: Array(allExerciseIDs))
      let plan = try splits.plan(for: selected)
      let completedHistoryCount =
        plan.movementCount == 0 ? try splits.completedWorkoutMovements().count : 0
      return (
        attribution, machines, selectable, dayRecords, lastTrained, entriesByDay, retiredByDay,
        named, plan, completedHistoryCount
      )
    }
    guard !Task.isCancelled, selected == self.selected else { return }
    guard case .success(let loaded) = result else {
      isLoadingPlan = false
      failure = "That plan could not be read. Nothing was changed."
      return
    }

    let attribution = loaded.0
    machineCache = loaded.1
    let byID = Dictionary(loaded.2.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let dayRecords = loaded.3
    let lastTrained = loaded.4
    let entriesByDay = loaded.5
    let retiredByDay = loaded.6
    let named = Dictionary(loaded.7.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    // One read for the whole plan, not one per visible render. The remaining per-day queries run
    // together on the database queue and their exercise names are resolved in one batch.
    let waitingLongest = SplitRotation.longestSinceTrained(
      among: dayRecords.map {
        SplitRotation.Day(id: $0.id, position: $0.position, lastTrained: lastTrained[$0.id])
      }
    )

    days = dayRecords.map { day in
      let entryRecords = entriesByDay[day.id] ?? []
      let retired = retiredByDay[day.id] ?? []
      let planDay = SplitPlanDay(
        position: day.position,
        name: day.name,
        movements: entryRecords.map(\.exerciseID)
      )
      return PlannedDay(
        id: day.id,
        name: day.name,
        subtitle: Self.subtitle(planDay.dominantGroups(with: attribution)),
        movements: entryRecords.map { entry in
          row(entry, entry: byID[entry.exerciseID] ?? named[entry.exerciseID], retired: retired)
        },
        lastTrained: lastTrained[day.id],
        isLongestSinceTrained: day.id == waitingLongest
      )
    }

    let plan = loaded.8
    let assessment = plan.assessed(with: attribution)
    completedHistoryMovementCount = loaded.9
    coverage = PlanCoverageSummary(
      movementCount: assessment.movementCount,
      dayCount: assessment.dayCount,
      uncreditedMuscleNames:
        assessment
        .uncreditedMuscles(excluding: ExerciseCatalog.unauthoredDirectTokens)
        .map(MuscleVocabulary.displayName),
      leastCreditedModelledNames: assessment.leastCreditedModelledMuscles.map(
        MuscleVocabulary.displayName),
      isLowerBound: assessment.isLowerBound,
      // A readout, in the taxonomy's own order. Never sorted by count -- see `modelledDayCredits`.
      modelledDayCredits: assessment.modelledDayCredits.map {
        MuscleDayCount(name: MuscleVocabulary.displayName($0.muscle), days: $0.days)
      }
    )
    failure = nil
    isLoadingPlan = false
  }

  private func row(
    _ record: SplitEntryRecord, entry: CatalogEntry?, retired: Set<ExerciseID>
  ) -> PlannedMovementRow {
    PlannedMovementRow(
      id: record.id,
      exerciseID: record.exerciseID,
      name: entry?.name ?? "Unknown movement",
      creditedMuscleNames: (entry?.creditedMuscles ?? []).compactMap {
        $0.key.muscle.map(MuscleVocabulary.displayName)
      },
      machineID: record.machineID,
      machineName: machineName(record.machineID),
      isUnattributed: entry?.isUnattributed ?? true,
      targetSets: record.targetSets,
      isRetired: retired.contains(record.exerciseID),
      machineNote: machineNote(record.machineID),
      // A missing catalogue row reads as not editable: `rename` would throw `notFound`, and an
      // unknown row is exactly where a control that cannot finish would otherwise appear.
      isEditable: entry.map { !$0.isCurated } ?? false
    )
  }

  private func machineName(_ id: MachineID?) -> String? {
    guard let id else { return nil }
    return machineCache.first { $0.id == id }?.displayName
  }

  // MARK: - Copy

  /// Describes a day by its contents. Never an archetype -- the app did not choose a split style.
  static func subtitle(_ groups: [MuscleGroup]) -> String {
    groups.prefix(3).map(MuscleVocabulary.displayName).joined(separator: " \u{00B7} ")
  }
}

// MARK: - Sheet presentation over an optional

/// Wraps a day id so it can drive `sheet(item:)`.
///
/// A local wrapper rather than an `Identifiable` conformance on `SplitDayID` itself: that would be a
/// retroactive conformance on a type from another module, and `@retroactive` in this package has
/// already cost one build -- it is an error on a same-package conformance and the compiler's advice
/// to add it is wrong as often as it is right. A struct here is unambiguous.
private struct DayTarget: Identifiable {
  let id: SplitDayID
}

extension View {
  /// `sheet(item:)` over any `Identifiable`, so an optional piece of state is the presentation
  /// source rather than a separate boolean.
  ///
  /// Two `.sheet` modifiers on one anchor silently drop the second, which has already cost this
  /// codebase a screen that never presented, so every sheet on this screen is driven by its own
  /// optional through this one path.
  fileprivate func sheet<Item: Identifiable, Content: View>(
    item: Binding<Item?>,
    @ViewBuilder content: @escaping (Item) -> Content
  ) -> some View {
    let isPresented = Binding(
      get: { item.wrappedValue != nil },
      set: { if !$0 { item.wrappedValue = nil } }
    )
    return sheet(isPresented: isPresented) {
      if let value = item.wrappedValue {
        content(value)
      }
    }
  }
}
