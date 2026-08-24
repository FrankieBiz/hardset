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

  @State private var plans: [SplitRecord] = []
  @State private var selected: SplitID?
  @State private var days: [PlannedDay] = []
  @State private var coverage = PlanCoverageSummary(
    movementCount: 0, dayCount: 0, uncreditedMuscleNames: [],
    leastCreditedModelledNames: [], isLowerBound: false
  )

  /// What a deal would draw on. Held in state rather than recomputed in `body`, so reading the
  /// lifter's logged movements is not a query per render.
  @State private var dealSource: PlanDealSource = .planContents(count: 0)
  /// The gym's machines, read once per reload. Resolving a machine name per row would be a database
  /// read per render -- the exact thing `PriorPerformanceSnapshot` exists to make unrepresentable in
  /// the logger, and no more acceptable here.
  @State private var machineCache: [MachineRecord] = []

  @State private var isNamingPlan = false
  @State private var renamingDay: PlannedDay?
  @State private var addingToDay: DayTarget?
  @State private var choosingMachineFor: PlannedMovementRow?
  @State private var pickerQuery = ""
  /// Why the last write failed, in the lifter's words. A `try?` here would leave a button that
  /// appears to do nothing, which is the failure mode this codebase has already shipped once.
  @State private var failure: String?

  /// Starts a day as today's workout. Supplied by the root, which owns the session, and nil while a
  /// workout is already open.
  private let onStartDay: (([PlannedExercise]) -> Void)?

  public init(
    splits: SplitStore,
    catalog: CatalogSeeder,
    gyms: GymStore,
    volume: VolumeStore,
    onStartDay: (([PlannedExercise]) -> Void)? = nil
  ) {
    self.splits = splits
    self.catalog = catalog
    self.gyms = gyms
    self.volume = volume
    self.onStartDay = onStartDay
  }

  public var body: some View {
    content
      .task { reload() }
      .sheet(isPresented: $isNamingPlan) { namePlanSheet }
      .sheet(item: $renamingDay) { day in renameDaySheet(day) }
      .sheet(item: $addingToDay) { target in movementPicker(for: target.id) }
      .sheet(item: $choosingMachineFor) { movement in machinePicker(for: movement) }
      .alert("Could not save", isPresented: .constant(failure != nil)) {
        Button("OK") { failure = nil }
      } message: {
        Text(failure ?? "")
      }
  }

  @ViewBuilder private var content: some View {
    if plans.isEmpty {
      ContentUnavailableView {
        Label("No plans yet", systemImage: "square.split.2x2")
      } description: {
        Text("A plan arranges movements you already train across the days you choose.")
      } actions: {
        Button("New plan") { isNamingPlan = true }
      }
    } else {
      planner
    }
  }

  @ViewBuilder private var planner: some View {
    SplitPlannerView(
      days: days,
      coverage: coverage,
      dealSource: dealSource,
      onRedeal: redeal,
      onAddMovement: { addingToDay = DayTarget(id: $0) },
      onRemoveMovement: removeMovement,
      onChooseMachine: { choosingMachineFor = $0 },
      onRenameDay: { renamingDay = $0 },
      onAddDay: addDay,
      onDeleteDay: deleteDay,
      onMoveMovement: moveMovement,
      onStartDay: startDayHandler
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
        } label: {
          Label("Plans", systemImage: "ellipsis.circle")
        }
      }
    }
    .onChange(of: selected) { _, _ in reloadPlan() }
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
    let entries = (try? catalog.selectableExercises()) ?? []
    let recent = (try? splits.loggedMovements(limit: 8)) ?? []
    NavigationStack {
      ExercisePickerView(
        query: $pickerQuery,
        entries: filtered(entries),
        recent: recent,
        onSelect: { entry in
          addingToDay = nil
          pickerQuery = ""
          write { try splits.addEntry(to: dayID, exercise: entry.id) }
        }
      )
      .navigationTitle("Add movement")
      // Inline, not large: a large title truncates rather than wraps, and at accessibility text
      // sizes this sheet was headed "Add movem...".
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
    }
  }

  @ViewBuilder private func machinePicker(for movement: PlannedMovementRow) -> some View {
    // Split into the two lists the picker actually means. Passing every machine in the building as
    // `recent` put them all under "You've used these", which is a false statement about equipment
    // the lifter may never have touched for this movement -- and found only by reading the sheet.
    let options = machineOptions(for: movement.exerciseID)
    NavigationStack {
      MachinePickerView(
        recent: options.recent,
        others: options.others,
        // The machine already named must show as chosen, or reopening the sheet looks like nothing
        // was ever set.
        selected: movement.machineID,
        onSelect: { machineID in
          choosingMachineFor = nil
          write {
            try splits.setMachine(machineID, forEntry: movement.id)
          }
        }
      )
      .navigationTitle("Machine")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
    }
  }

  /// Machines this movement has actually been performed on, and then the rest of the gym.
  ///
  /// Same split as the live session's picker, so "You've used these" means the same thing in both
  /// places.
  private func machineOptions(for exerciseID: ExerciseID)
    -> (recent: [MachineOption], others: [MachineOption])
  {
    guard let gym = try? gyms.lastUsedGym() else { return ([], []) }
    do {
      let recent = try gyms.recentMachines(for: exerciseID, at: gym)
      let recentIDs = Set(recent.map(\.id))
      let others = try gyms.machines(at: gym).filter { !recentIDs.contains($0.id) }
      return (recent.map(Self.option(for:)), others.map(Self.option(for:)))
    } catch {
      // An unreadable gym must not block planning. The picker then offers only "Not recorded",
      // which is a true statement about what can be offered rather than a fabricated list.
      return ([], [])
    }
  }

  private static func option(for record: MachineRecord) -> MachineOption {
    MachineOption(
      id: record.id, displayName: record.displayName, stackIncrementKg: record.stackIncrementKg
    )
  }

  /// Every machine at the current gym, for turning a stored id back into a name.
  private func allMachines() -> [MachineRecord] {
    guard let gym = try? gyms.lastUsedGym() else { return [] }
    return (try? gyms.machines(at: gym)) ?? []
  }

  private func filtered(_ entries: [CatalogEntry]) -> [CatalogEntry] {
    let query = pickerQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return entries }
    return (try? catalog.search(query)) ?? entries
  }

  // MARK: - Writes

  /// Runs a write and surfaces its failure instead of swallowing it.
  private func write(_ work: () throws -> Void) {
    do {
      try work()
      reload()
    } catch {
      failure = error.localizedDescription
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
    guard let onStartDay else { return }
    do {
      let plan = try splits.plannedExercises(for: day.id)
      guard !plan.isEmpty else {
        failure = "There is nothing on \(day.name) to start."
        return
      }
      onStartDay(plan)
    } catch {
      failure = error.localizedDescription
    }
  }

  private func redeal(_ dayCount: Int) {
    guard let selected else { return }
    write {
      let attribution = try volume.attributionIndex()
      // An empty plan has nothing to rearrange, so it is seeded from what the lifter has actually
      // logged -- which is exactly what the empty state promises, and is still only their own
      // training. Once a plan has movements, dealing rearranges *those*: pulling extra movements
      // into a plan someone curated would be the app editing their training, not arranging it.
      //
      // This was the defect found by running the screen: the empty state said "deal the movements
      // you already train" and the button read from the empty plan, so it did nothing at all.
      let existing = try splits.plan(for: selected).allMovements
      let movements = existing.isEmpty ? try splits.loggedMovements() : existing
      guard !movements.isEmpty else { return }
      let plan = SplitDealer.deal(
        movements: movements,
        across: dayCount,
        attribution: attribution
      )
      try splits.replace(selected, with: plan)
    }
  }

  // MARK: - Reads

  private func reload() {
    plans = (try? splits.splits()) ?? []
    if selected == nil || !plans.contains(where: { $0.id == selected }) {
      selected = plans.first?.id
    }
    reloadPlan()
  }

  private func reloadPlan() {
    guard let selected else {
      days = []
      dealSource = .planContents(count: 0)
      coverage = PlanCoverageSummary(
        movementCount: 0, dayCount: 0, uncreditedMuscleNames: [],
        leastCreditedModelledNames: [], isLowerBound: false
      )
      return
    }

    let attribution = (try? volume.attributionIndex()) ?? AttributionIndex([:])
    machineCache = allMachines()
    let entries = (try? catalog.selectableExercises()) ?? []
    let byID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let dayRecords = (try? splits.days(in: selected)) ?? []

    days = dayRecords.map { day in
      let entryRecords = (try? splits.entries(in: day.id)) ?? []
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
          row(entry, entry: byID[entry.exerciseID])
        }
      )
    }

    let plan = (try? splits.plan(for: selected)) ?? SplitPlan(days: [])
    let assessment = plan.assessed(with: attribution)
    dealSource =
      plan.movementCount > 0
      ? .planContents(count: plan.movementCount)
      : .loggedHistory(count: ((try? splits.loggedMovements()) ?? []).count)
    coverage = PlanCoverageSummary(
      movementCount: assessment.movementCount,
      dayCount: assessment.dayCount,
      uncreditedMuscleNames: assessment
        .uncreditedMuscles(excluding: ExerciseCatalog.unauthoredDirectTokens)
        .map(MuscleVocabulary.displayName),
      leastCreditedModelledNames: assessment.leastCreditedModelledMuscles.map(MuscleVocabulary.displayName),
      isLowerBound: assessment.isLowerBound
    )
  }

  private func row(_ record: SplitEntryRecord, entry: CatalogEntry?) -> PlannedMovementRow {
    PlannedMovementRow(
      id: record.id,
      exerciseID: record.exerciseID,
      name: entry?.name ?? "Unknown movement",
      creditedMuscleNames: (entry?.creditedMuscles ?? []).compactMap {
        $0.key.muscle.map(MuscleVocabulary.displayName)
      },
      machineID: record.machineID,
      machineName: machineName(record.machineID),
      isUnattributed: entry?.isUnattributed ?? true
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
