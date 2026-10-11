import Accessibility
import HardsetCore
import SwiftUI

/// A deletion that can still be undone, as the screen shows it. The caller builds the label ("Set 2
/// deleted") and decides what Undo does; the coordinator alone decides whether it is still allowed.
public struct PendingUndo: Hashable, Sendable {
  public let id: UUID
  public let label: String

  public init(id: UUID, label: String) {
    self.id = id
    self.label = label
  }
}

/// The live workout screen.
///
/// Deliberately knows nothing about storage. It takes the exercise states, reports taps, and
/// renders whatever error the caller hands it — so `HardsetUI` keeps depending on `HardsetCore`
/// alone, and this screen compiles and previews on the host without a database, a CloudKit
/// container or a simulator.
///
/// The app target owns the wiring: it holds the `SessionCoordinator`, passes
/// `$coordinator.exercises` in, and forwards `onLogSet` to `coordinator.logSet`, which is the
/// only thing allowed to mark a row logged.
///
/// What this screen does own is the keypad: which row it is on, what it holds, and where the list
/// scrolls. The pad is the bottom inset, so the row it edits stays in view above it.
///
/// It also plays what the coordinator reports, after the write it describes: one haptic per pulse,
/// a VoiceOver announcement for a record, and the Undo bar for a deletion.
public struct SessionView: View {
  @Binding private var exercises: [ExerciseLogState]
  private let unit: WeightUnit
  private let restState: RestTimerState
  private let restMetadata: RestMetadata?
  private let errorMessage: String?
  private let onLogSet: (UUID, SetSlot) -> Void
  private let onAdjustRest: (Duration) -> Void
  private let onPauseResumeRest: () -> Void
  private let onSkipRest: () -> Void
  private let onAddExercise: (() -> Void)?
  private let onSelectMachine: ((UUID) -> Void)?
  private let onShowHistory: ((UUID) -> Void)?
  private let restChoices: [ExerciseID: Duration]
  private let onChooseRest: ((UUID, Duration?) -> Void)?
  private let onStartRest: ((UUID) -> Void)?
  private let recordsBySlot: [UUID: [PersonalRecord]]
  private let feedback: FeedbackPulse?
  private let pendingUndo: PendingUndo?
  private let onEditSet: ((UUID, UUID, SetEntryDraft) -> Bool)?
  private let onDeleteSet: ((UUID, UUID) -> Void)?
  private let onUndoDelete: (() -> Void)?
  private let onExpireUndo: (() -> Void)?
  private let onFinish: (() -> Void)?

  /// The row the pad is editing. Ids, not indices: rows can be added while the pad is open.
  @State private var focus: KeypadFocus?
  @State private var keypad: SetEntryKeypad?
  /// The pad is correcting a saved set, on a logged row. What it holds stays in the pad, and the
  /// row is unchanged, until the store accepts the correction on Save.
  @State private var editingSaved = false
  /// The set logged last, which decides the active set: the lifter's order, not the plan's.
  @State private var lastLoggedSlotID: UUID?
  /// The sequence of the record pulse each row earned, by `SetSlot.id`, so its trophy bounces once.
  ///
  /// Kept rather than read off `feedback`: a value that fell back to zero when the next pulse named
  /// another row would change again, and bounce the trophy a second time on an ordinary log.
  @State private var recordPulses: [UUID: Int] = [:]
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// Room for the macOS rest bar, which grows with the type (`ScaledMetric`, iOS 14 / macOS 11).
  @ScaledMetric(relativeTo: .body) private var restBarInset: CGFloat = 72

  /// - Parameter restChoices: Each exercise's chosen rest. An exercise with no entry has no rest,
  ///   and its chip reads "Off" — there is no default.
  /// - Parameter onChooseRest: Reports a rest chosen for an exercise (by its state id), or `nil`
  ///   for Off. Passing `nil` hides the rest chips.
  /// - Parameter onStartRest: Starts an exercise's chosen rest now.
  /// - Parameter recordsBySlot: The records each row earned, by `SetSlot.id`, kept for the
  ///   workout. The only source of trophies.
  /// - Parameter feedback: The coordinator's latest pulse. Each new one plays one haptic; a record
  ///   also bounces its row's trophy and is announced to VoiceOver.
  /// - Parameter pendingUndo: The deletion that can still be undone. Non-nil shows the Undo bar.
  /// - Parameter onEditSet: Writes a correction: (exercise state id, slot id, draft). Returns
  ///   whether the store accepted it. `nil` offers no Edit.
  /// - Parameter onDeleteSet: Deletes a logged set: (exercise state id, slot id). `nil` offers no
  ///   Delete.
  /// - Parameter onUndoDelete: The Undo bar's button.
  /// - Parameter onExpireUndo: The Undo bar timed out.
  /// - Parameter onFinish: The in-list "Finish workout" button. `nil` hides it.
  public init(
    exercises: Binding<[ExerciseLogState]>,
    unit: WeightUnit,
    restState: RestTimerState = .idle,
    restMetadata: RestMetadata? = nil,
    errorMessage: String? = nil,
    onLogSet: @escaping (UUID, SetSlot) -> Void,
    onAdjustRest: @escaping (Duration) -> Void = { _ in },
    onPauseResumeRest: @escaping () -> Void = {},
    onSkipRest: @escaping () -> Void = {},
    onAddExercise: (() -> Void)? = nil,
    onSelectMachine: ((UUID) -> Void)? = nil,
    onShowHistory: ((UUID) -> Void)? = nil,
    restChoices: [ExerciseID: Duration] = [:],
    onChooseRest: ((UUID, Duration?) -> Void)? = nil,
    onStartRest: ((UUID) -> Void)? = nil,
    recordsBySlot: [UUID: [PersonalRecord]] = [:],
    feedback: FeedbackPulse? = nil,
    pendingUndo: PendingUndo? = nil,
    onEditSet: ((UUID, UUID, SetEntryDraft) -> Bool)? = nil,
    onDeleteSet: ((UUID, UUID) -> Void)? = nil,
    onUndoDelete: (() -> Void)? = nil,
    onExpireUndo: (() -> Void)? = nil,
    onFinish: (() -> Void)? = nil
  ) {
    self._exercises = exercises
    self.unit = unit
    self.restState = restState
    self.restMetadata = restMetadata
    self.errorMessage = errorMessage
    self.onLogSet = onLogSet
    self.onAdjustRest = onAdjustRest
    self.onPauseResumeRest = onPauseResumeRest
    self.onSkipRest = onSkipRest
    self.onAddExercise = onAddExercise
    self.onSelectMachine = onSelectMachine
    self.onShowHistory = onShowHistory
    self.restChoices = restChoices
    self.onChooseRest = onChooseRest
    self.onStartRest = onStartRest
    self.recordsBySlot = recordsBySlot
    self.feedback = feedback
    self.pendingUndo = pendingUndo
    self.onEditSet = onEditSet
    self.onDeleteSet = onDeleteSet
    self.onUndoDelete = onUndoDelete
    self.onExpireUndo = onExpireUndo
    self.onFinish = onFinish
  }

  public var body: some View {
    // Pure: the next unlogged row after the last one logged. No storage is read to draw this.
    let active = ActiveSet.next(in: exercises, after: lastLoggedSlotID)

    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: Tokens.Spacing.regular) {
          if let errorMessage {
            // A failed write is stated, not swallowed. The row it belongs to is still unlogged,
            // so the user can retry rather than discovering the gap days later.
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
              .font(Tokens.Text.label)
              .foregroundStyle(Tokens.Color.critical)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(Tokens.Spacing.regular)
              .background(Tokens.Color.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
              .padding(.horizontal, Tokens.Spacing.regular)
          }

          // No records banner: the trophy on the row that earned it is the only celebration
          // (spec §3, item 5).
          ForEach($exercises) { $exercise in
            ExerciseSectionView(
              state: $exercise,
              unit: unit,
              onLogSet: { slot in logSet(exerciseID: exercise.id, slot: slot, proxy: proxy) },
              onSelectMachine: onSelectMachine.map { select in
                { select(exercise.id) }
              },
              onShowHistory: onShowHistory.map { show in
                { show(exercise.id) }
              },
              restChoice: restChoices[exercise.exerciseID],
              onChooseRest: onChooseRest.map { choose in
                { choice in choose(exercise.id, choice) }
              },
              onStartRest: onStartRest.map { start in
                { start(exercise.id) }
              },
              activeSlotID: active?.slotID,
              focusedSlotID: focusedSlotID(in: exercise.id),
              keypad: keypadState(in: exercise.id),
              onFocus: { slot, field in
                focusRow(exerciseID: exercise.id, slotID: slot.id, field: field, proxy: proxy)
              },
              recordsBySlot: recordsBySlot,
              recordPulses: recordPulses,
              editingSlotID: editingSlotID(in: exercise.id),
              onEdit: editAction(in: exercise.id, proxy: proxy),
              onDelete: deleteAction(in: exercise.id)
            )
            .background(Tokens.Color.surface.opacity(0.4), in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
            .padding(.horizontal, Tokens.Spacing.snug)
            // A section the lazy stack has not built yet has no rows to scroll to, but it can be
            // scrolled to itself (see `logSet`).
            .id(exercise.id)
          }

          if let onAddExercise {
            Button(action: onAddExercise) {
              Label("Add movement", systemImage: "plus")
                .font(Tokens.Text.label)
                .frame(maxWidth: .infinity, minHeight: Tokens.loggerTapTarget)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Tokens.Color.accent)
            .background(
              Tokens.Color.surface,
              in: RoundedRectangle(cornerRadius: Tokens.Radius.control)
            )
            .padding(.horizontal, Tokens.Spacing.regular)
          }

          // An empty workout says so, and says what to do about it, rather than rendering a bare
          // "Finish" button under nothing.
          if exercises.isEmpty {
            ContentUnavailableView {
              Label("Nothing added yet", systemImage: "dumbbell")
            } description: {
              Text("Add a movement to start logging sets.")
            }
          }

          summary
        }
        .padding(.vertical, Tokens.Spacing.regular)
        #if !os(iOS)
          // Room for the rest bar so the last row is never trapped underneath it. On iOS the rest
          // cluster is in the tab bar's accessory (Task 19), and the tab view makes room for it.
          .safeAreaPadding(.bottom, restState == .idle ? 0 : restBarInset)
        #endif
      }
      .background(Tokens.Color.background)
      // Above the pad inset, which this is applied inside of, so a deletion's Undo is never under
      // the pad.
      .overlay(alignment: .bottom) { undoOverlay }
      // The pad is an inset, not a sheet, so the scroll view shrinks above it and the row being
      // edited can be scrolled into view instead of sitting under the pad.
      .safeAreaInset(edge: .bottom, spacing: 0) {
        if let binding = keypadBinding {
          NumericPad(
            keypad: binding, commit: commitLabel,
            onCommit: { commitKey() }, onDismiss: { closeKeypad() }
          )
          .transition(Tokens.Motion.edgeTransition(reduceMotion))
        } else {
          #if !os(iOS)
            // On iOS the rest cluster lives in the tab bar's accessory (Task 19), so the countdown
            // is drawn once. The host build keeps the inline bar for previews.
            RestBarView(
              state: restState, metadata: restMetadata, onAdjust: onAdjustRest,
              onPauseResume: onPauseResumeRest, onSkip: onSkipRest)
          #endif
        }
      }
    }
    // A draft changed by something other than the pad: a machine change re-prefills the unlogged
    // rows and brings its own step, and a unit change rewrites how both fields read. The pad is
    // rebuilt from the row each time, or it would show one value while the row saved another.
    .onChange(of: focusedDraft) { reseedKeypad() }
    .onChange(of: focusedMachineIncrementKg) { reseedKeypad() }
    .onChange(of: unit) { reseedKeypad() }
    // A logged row is read-only, so the pad never stays on one, whichever path logged it. The one
    // exception is correcting a saved set, which opens the pad on a logged row on purpose and
    // writes only through Save.
    .onChange(of: focusedSlotIsLogged) {
      if focusedSlotIsLogged && !editingSaved { closeKeypad() }
    }
    // A log, and a record with it, is announced and its trophy bounced only from the coordinator's
    // pulse, which it emits after the write. Resume and corrections emit none, so neither
    // celebrates or speaks. One announcement per pulse: a record is part of the log's sentence.
    .onChange(of: feedback) { _, pulse in
      guard let pulse, pulse.event == .log || pulse.event == .record, let slotID = pulse.slotID
      else { return }
      if pulse.event == .record { recordPulses[slotID] = pulse.sequence }
      announceLog(onSlot: slotID)
    }
    // One haptic per pulse (spec 2.6): a record plays only the record haptic, an ordinary log a
    // quiet impact, and a failure an error. Keys and corrections play nothing of their own.
    .sensoryFeedback(trigger: feedback) { feedback.map { Tokens.Haptic.feedback(for: $0.event) } }
  }

  // MARK: - Keypad

  /// Which row the pad is on, by id.
  private struct KeypadFocus: Hashable {
    let exercise: UUID
    let slot: UUID
  }

  // Only the focused exercise sees the pad, so a keystroke redraws one section. Helpers rather
  // than inline ternaries, to keep the section's initialiser cheap to type-check.
  private func focusedSlotID(in exerciseID: UUID) -> UUID? {
    focus?.exercise == exerciseID ? focus?.slot : nil
  }

  private func keypadState(in exerciseID: UUID) -> SetEntryKeypad? {
    focus?.exercise == exerciseID ? keypad : nil
  }

  /// The logged row being corrected, if it is in this exercise.
  private func editingSlotID(in exerciseID: UUID) -> UUID? {
    editingSaved ? focusedSlotID(in: exerciseID) : nil
  }

  /// Edit opens the pad on the saved set. Offered only when the caller can write a correction.
  private func editAction(in exerciseID: UUID, proxy: ScrollViewProxy) -> ((SetSlot) -> Void)? {
    guard onEditSet != nil else { return nil }
    return { slot in editSavedSet(exerciseID: exerciseID, slotID: slot.id, proxy: proxy) }
  }

  /// Delete goes straight to the caller, which writes first and then removes the row.
  private func deleteAction(in exerciseID: UUID) -> ((SetSlot) -> Void)? {
    onDeleteSet.map { delete in { slot in delete(exerciseID, slot.id) } }
  }

  /// Next on weight. On reps, Save when correcting a saved set, because that key writes, and Done
  /// otherwise, because it only closes the pad.
  private var commitLabel: NumericPad.Commit {
    if keypad?.field == .weight { return .next }
    return editingSaved ? .save : .done
  }

  /// The focused row's position, looked up fresh, or `nil` when the pad is closed or its row is
  /// gone.
  private var focusedIndices: (exercise: Int, slot: Int)? {
    guard let focus,
      let e = exercises.firstIndex(where: { $0.id == focus.exercise }),
      let s = exercises[e].slots.firstIndex(where: { $0.id == focus.slot })
    else { return nil }
    return (e, s)
  }

  private var focusedDraft: SetEntryDraft? {
    focusedIndices.map { exercises[$0.exercise].slots[$0.slot].draft }
  }

  private var focusedSlotIsLogged: Bool {
    focusedIndices.map { exercises[$0.exercise].slots[$0.slot].isLogged } == true
  }

  /// Watched only so a machine change rebuilds the pad's step even when the prefill is unchanged.
  private var focusedMachineIncrementKg: Double? {
    focusedIndices.flatMap { exercises[$0.exercise].machineIncrementKg }
  }

  /// Every keystroke goes straight into the focused row's draft, as the row's own buffers used to,
  /// so the row, the pad and what Log writes are one value. `nil` while the pad is closed.
  ///
  /// A correction is the exception: its keystrokes stay in the pad, and the saved set changes only
  /// when the store accepts the correction on Save.
  private var keypadBinding: Binding<SetEntryKeypad>? {
    guard let current = keypad else { return nil }
    return Binding(
      // The snapshot only covers the frames in which the pad is animating away after closing.
      get: { keypad ?? current },
      set: { newValue in
        keypad = newValue
        guard !editingSaved, let index = focusedIndices else { return }
        // A logged row is read-only: only the store changes a saved set.
        guard !exercises[index.exercise].slots[index.slot].isLogged else { return }
        exercises[index.exercise].slots[index.slot].draft = newValue.draft
      }
    )
  }

  /// Opens the pad on a field, with that field selected so the first key replaces the prefill.
  private func focusRow(
    exerciseID: UUID, slotID: UUID, field: SetRowField, proxy: ScrollViewProxy
  ) {
    openPad(exerciseID: exerciseID, slotID: slotID, field: field, correcting: false, proxy: proxy)
  }

  /// Opens the pad on a saved set, on its weight, to correct it (spec 2.3).
  private func editSavedSet(exerciseID: UUID, slotID: UUID, proxy: ScrollViewProxy) {
    openPad(exerciseID: exerciseID, slotID: slotID, field: .weight, correcting: true, proxy: proxy)
  }

  /// An unlogged row is typed into. A logged row opens only to be corrected, and is never written
  /// by a keystroke.
  private func openPad(
    exerciseID: UUID, slotID: UUID, field: SetRowField, correcting: Bool, proxy: ScrollViewProxy
  ) {
    guard let e = exercises.firstIndex(where: { $0.id == exerciseID }),
      let slot = exercises[e].slots.first(where: { $0.id == slotID }),
      slot.isLogged == correcting
    else { return }
    // `SetRowField` is the UI's name for a field; the keypad has its own.
    let keypadField: SetEntryKeypad.Field = field == .weight ? .weight : .reps
    var pad = SetEntryKeypad(
      draft: slot.draft, unit: unit,
      machineIncrementKg: exercises[e].machineIncrementKg, field: keypadField)
    pad.focus(keypadField)
    withAnimation(Tokens.Motion.quick(reduceMotion)) {
      keypad = pad
      focus = KeypadFocus(exercise: exerciseID, slot: slotID)
      editingSaved = correcting
      // Centred in the space above the pad, so the row being edited is never under it.
      proxy.scrollTo(slotID, anchor: .center)
    }
  }

  /// Next moves weight → reps. On reps the key closes the pad, or, for a correction, saves it.
  private func commitKey() {
    guard let current = keypad else { return }
    if current.field == .weight {
      _ = keypad?.advance()
    } else if editingSaved {
      saveCorrection()
    } else {
      closeKeypad()
    }
  }

  /// Writes the correction, the store first. Accepted, and the coordinator has already updated the
  /// row, so the pad closes. Refused, and nothing changes: the pad keeps what was typed, and the
  /// error shows above. A correction never celebrates: the coordinator emits no pulse for one.
  private func saveCorrection() {
    guard let focus, let pad = keypad, let onEditSet else { return }
    if onEditSet(focus.exercise, focus.slot, pad.draft) { closeKeypad() }
  }

  /// Closing the pad any way but Save discards a correction: it was only ever in the pad.
  private func closeKeypad() {
    withAnimation(Tokens.Motion.quick(reduceMotion)) {
      keypad = nil
      focus = nil
      editingSaved = false
    }
  }

  /// Rebuilds the open pad from its row when the row changed from outside. The pad's own
  /// keystrokes land here too, and are recognised because the draft then already matches.
  private func reseedKeypad() {
    guard let current = keypad else { return }
    guard let index = focusedIndices else {
      // The row went away under the pad. There is nothing left to edit.
      closeKeypad()
      return
    }
    let exercise = exercises[index.exercise]
    // A correction's typing is in the pad alone, so the pad is rebuilt from its own draft and
    // keeps it. Rebuilding from the saved set would silently drop what the lifter typed.
    let draft = editingSaved ? current.draft : exercise.slots[index.slot].draft
    let step = LoadStep(machineIncrementKg: exercise.machineIncrementKg, unit: unit)
    guard draft != current.draft || step != current.loadStep || unit != current.unit
    else { return }
    var pad = SetEntryKeypad(
      draft: draft, unit: unit, machineIncrementKg: exercise.machineIncrementKg,
      field: current.field)
    pad.focus(current.field)
    keypad = pad
  }

  // MARK: - Logging

  /// Logs through the caller, then follows the lifter to the next set.
  ///
  /// `onLogSet` is synchronous on the main actor (`SessionCoordinator.logSet`), so the bound rows
  /// already say whether the write succeeded. Only a row that has just become logged moves the
  /// screen: a failed write leaves the lifter where they are, with the error above.
  private func logSet(exerciseID: UUID, slot: SetSlot, proxy: ScrollViewProxy) {
    let wasLogged = isLogged(slot.id)
    onLogSet(exerciseID, slot)
    guard !wasLogged, isLogged(slot.id) else { return }
    lastLoggedSlotID = slot.id
    let next = ActiveSet.next(in: exercises, after: slot.id)
    withAnimation(Tokens.Motion.quick(reduceMotion)) {
      // A logged row is read-only, so a pad left on it would be editing nothing.
      if focus?.slot == slot.id {
        keypad = nil
        focus = nil
        editingSaved = false
      }
      guard let next else { return }
      // The next set may sit in a section the lazy stack has not built, whose rows cannot be
      // found yet. Scrolling to the section first brings it in; the row scroll then lands on the
      // set itself, or leaves the section's top in view if the row is still unbuilt.
      if next.exerciseID != exerciseID {
        proxy.scrollTo(next.exerciseID, anchor: .top)
      }
      proxy.scrollTo(next.slotID, anchor: .center)
    }
  }

  private func isLogged(_ slotID: UUID) -> Bool {
    exercises.contains { exercise in
      exercise.slots.contains { $0.id == slotID && $0.isLogged }
    }
  }

  private var summary: some View {
    VStack(spacing: Tokens.Spacing.snug) {
      Text(volumeDescription)
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.textSecondary)
        .monospacedDigit()
        // The totals roll to their new values; under Reduce Motion they simply change.
        .contentTransition(.numericText())
        .animation(Tokens.Motion.quick(reduceMotion), value: volumeDescription)
      // Hidden when the caller puts Finish elsewhere (the toolbar).
      if let onFinish {
        Button(action: onFinish) {
          Text("Finish workout")
            .font(Tokens.Text.label.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: Tokens.loggerTapTarget)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Tokens.Color.accent)
        .background(
          Tokens.Color.surface,
          in: RoundedRectangle(cornerRadius: Tokens.Radius.control)
        )
      }
    }
    .padding(.horizontal, Tokens.Spacing.regular)
    .padding(.top, Tokens.Spacing.snug)
  }

  // MARK: - Moments

  /// Tells VoiceOver what was logged, and the record it earned, once, in units spoken in full.
  /// Posted with `AccessibilityNotification.Announcement(_:).post()` (iOS 17, macOS 14).
  ///
  /// The values are the draft's `resolved()` pair, which is what `LoggerStore.logSet` wrote, so
  /// the announcement states what was saved. The number is the working-set count the row shows.
  private func announceLog(onSlot slotID: UUID) {
    guard let exercise = exercises.first(where: { $0.slots.contains { $0.id == slotID } }),
      let index = exercise.slots.firstIndex(where: { $0.id == slotID }),
      let resolved = exercise.slots[index].draft.resolved()
    else { return }
    let slot = exercise.slots[index]
    let number = exercise.slots[..<index].count { !$0.isWarmup } + 1
    let text = SetRowSpeech.logAnnouncement(
      number: number, isWarmup: slot.isWarmup, weightKg: resolved.weightKg, reps: resolved.reps,
      exerciseName: exercise.exerciseName, records: recordsBySlot[slotID] ?? [],
      formatter: WeightFormatter(unit: unit))
    AccessibilityNotification.Announcement(text).post()
  }

  /// The Undo bar's container. It stays in place so the bar's arrival and departure animate.
  private var undoOverlay: some View {
    ZStack {
      if let pendingUndo {
        undoBar(pendingUndo)
      }
    }
    .animation(Tokens.Motion.quick(reduceMotion), value: pendingUndo?.id)
  }

  /// A deletion, and the way back from it, for five seconds (spec 2.3). The coordinator holds the
  /// real window, so a tap after it, or after Finish, does nothing.
  private func undoBar(_ undo: PendingUndo) -> some View {
    HStack(spacing: Tokens.Spacing.regular) {
      Text(undo.label)
        .font(Tokens.Text.label)
        .foregroundStyle(Tokens.Color.textPrimary)
      Spacer(minLength: 0)
      Button {
        onUndoDelete?()
      } label: {
        Text("Undo")
          .font(Tokens.Text.label.weight(.semibold))
          .frame(minWidth: Tokens.minimumTapTarget, minHeight: Tokens.minimumTapTarget)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .foregroundStyle(Tokens.Color.accent)
    }
    .padding(.horizontal, Tokens.Spacing.loose)
    .padding(.vertical, Tokens.Spacing.tight)
    .modifier(UndoBarBackground())
    .padding(.horizontal, Tokens.Spacing.regular)
    .padding(.bottom, Tokens.Spacing.snug)
    // Restarted for each deletion. A newer one cancels this wait, so the newer one is not expired.
    .task(id: undo.id) {
      let text = "\(undo.label). Undo is available."
      AccessibilityNotification.Announcement(text).post()
      do {
        // The coordinator's `undoWindow`.
        try await Task.sleep(for: .seconds(5))
        onExpireUndo?()
      } catch {
        // Cancelled because a newer deletion replaced this one, or the bar went: do not expire.
      }
    }
    .transition(Tokens.Motion.edgeTransition(reduceMotion))
  }

  /// Counted by `SessionVolume`, which is tested. The rules that matter — unlogged rows and
  /// warm-ups excluded — live there rather than here, so this screen cannot disagree with the
  /// history screen about what the session contained.
  private var volumeDescription: String {
    let volume = SessionVolume(exercises: exercises)
    guard !volume.isEmpty else { return "No sets logged yet" }
    var parts = [CountText.sets(volume.workingSets), CountText.reps(volume.reps)]
    if volume.volumeKg > 0 {
      parts.append("\(WeightFormatter(unit: unit).total(kilograms: volume.volumeKg)) volume")
    }
    if volume.warmupSets > 0 { parts.append("\(volume.warmupSets) warm-up") }
    return parts.joined(separator: " · ")
  }
}

/// The Undo bar is the functional layer, so it may be glass. Glass is iOS 26 and macOS 26, and the
/// package also builds for macOS 15, which gets an opaque capsule.
private struct UndoBarBackground: ViewModifier {
  @ViewBuilder func body(content: Content) -> some View {
    if #available(iOS 26.0, macOS 26.0, *) {
      content.glassEffect(.regular, in: .capsule)
    } else {
      content.background(Tokens.Color.surface, in: Capsule())
    }
  }
}

#if DEBUG
  #Preview("Live session") {
    struct Harness: View {
      @State private var exercises: [ExerciseLogState]
      @State private var restChoices: [ExerciseID: Duration] = [:]

      init() {
        let press = ExerciseID()
        let machine = MachineID()
        let key = ProgressionKey(exerciseID: press, machineID: machine)
        let records = [
          PriorSetRecord(weightKg: 100, reps: 10, completedAt: .distantPast),
          PriorSetRecord(weightKg: 105, reps: 8, completedAt: .distantPast),
        ]
        let snapshot = PriorPerformanceSnapshot(
          entries: [key: PriorPerformance(key: key, lastSets: records, heaviestSet: records.last)],
          capturedAt: .distantPast
        )
        _exercises = State(
          initialValue: [
            .build(
              exerciseID: press, machineID: machine, exerciseName: "Leg Press",
              machineName: "Hammer Strength", snapshot: snapshot
            ),
            // No history: one empty row, nothing loggable, no invented numbers.
            .build(
              exerciseID: ExerciseID(), exerciseName: "Standing Calf Raise",
              snapshot: .empty(capturedAt: .distantPast)
            ),
          ]
        )
      }

      var body: some View {
        SessionView(
          exercises: $exercises,
          unit: .kilograms,
          restState: .running(endsAt: Date().addingTimeInterval(96)),
          restMetadata: RestMetadata(
            exerciseName: "Leg Press", setOrdinal: 1, plannedSets: 2,
            machineName: "Hammer Strength"
          ),
          onLogSet: { stateID, slot in
            guard let index = exercises.firstIndex(where: { $0.id == stateID }) else { return }
            exercises[index].markLogged(slotID: slot.id, setID: SetID())
          },
          restChoices: restChoices,
          onChooseRest: { stateID, choice in
            guard let exercise = exercises.first(where: { $0.id == stateID }) else { return }
            restChoices[exercise.exerciseID] = choice
          },
          onStartRest: { _ in }
        )
      }
    }
    return Harness()
  }
#endif
