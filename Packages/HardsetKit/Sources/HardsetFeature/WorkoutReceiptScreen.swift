import HardsetCore
import HardsetStore
import HardsetUI
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// What "Save as workout" needs: the saved-workout store, the movement catalogue for the picker and
/// the volume store for the split balance, and what to do once a workout has been saved. Passed
/// where a receipt can be opened, so the same action is offered from the Train tab and from History.
public struct SaveAsWorkoutTools {
  let templates: TemplateStore
  let catalog: CatalogSeeder
  let volume: VolumeStore
  let onSaved: () -> Void

  public init(
    templates: TemplateStore, catalog: CatalogSeeder, volume: VolumeStore,
    onSaved: @escaping () -> Void
  ) {
    self.templates = templates
    self.catalog = catalog
    self.volume = volume
    self.onSaved = onSaved
  }
}

/// A plan made from a finished workout, waiting to be edited, with the rest of the rotation.
private nonisolated struct SavedWorkoutDraft: Identifiable {
  let template: WorkoutTemplate
  let others: [WorkoutTemplate]
  var id: TemplateID { template.id }
}

/// A past workout's receipt, with the corrections a lifter may need and a way into each movement's
/// load history, and the way to keep it as a saved workout.
///
/// A mis-logged set can be corrected, which changes its weight and reps and nothing else, or
/// removed; a workout started by mistake can be deleted. Removing and deleting each sit behind a
/// destructive confirmation that says what will change. A correction asks no confirmation, because
/// it can be put right with another correction, and it writes first: the receipt is re-read from
/// storage and shows the corrected set only once the write has succeeded. The receipt itself stays
/// a static ledger, because the same view is shared as an image.
struct WorkoutReceiptScreen: View {
  private let sessionID: SessionID
  private let store: ReceiptStore
  private let unit: WeightUnit
  private let progression: ProgressionStore?
  /// Offers "Save as workout" when present.
  private let saveAsWorkout: SaveAsWorkoutTools?
  /// Called after a set was corrected or deleted, or the workout was deleted, so the caller can
  /// re-read what it shows.
  private let onChanged: () -> Void

  @State private var snapshot = SnapshotLoader<WorkoutReceipt>()
  @State private var image: Image?
  /// What the lifter is doing to the sets, when they have asked to do anything: each set shows the
  /// matching control while it is on, and one mode at a time.
  @State private var editing: Editing?
  @State private var pendingSet: WorkoutReceipt.Line?
  /// The set on the correction sheet.
  @State private var correcting: WorkoutReceipt.Line?
  @State private var isSavingCorrection = false
  /// Why the last save failed, shown in the sheet, which stays up with the figures typed.
  @State private var correctionSheetError: String?
  /// What the last correction did, in a plain sentence above the receipt.
  @State private var correctionNote: String?
  /// Counts requests to scroll the sets into view from outside the scroll view, such as the toolbar.
  @State private var scrollToTopRequest = 0
  @State private var isConfirmingWorkoutDeletion = false
  @State private var isDeleting = false
  @State private var correctionError: String?
  @State private var isNamingWorkout = false
  @State private var nameError: String?
  /// The plan waiting for the naming sheet to finish leaving, so the editor is presented after it:
  /// a sheet started while another is still dismissing is dropped.
  @State private var pendingEditor: SavedWorkoutDraft?
  @State private var editor: SavedWorkoutDraft?
  @State private var didSaveWorkout = false
  /// The working behind a record the lifter asked about, while its sheet is up.
  @State private var working: WorkedFromPresentation?
  @Environment(\.syncStatus) private var syncStatus
  @Environment(\.displayScale) private var displayScale
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private static let topID = "receipt-top"

  private enum Editing {
    case correcting
    case removing
  }

  init(
    sessionID: SessionID, store: ReceiptStore, unit: WeightUnit,
    progression: ProgressionStore? = nil, saveAsWorkout: SaveAsWorkoutTools? = nil,
    onChanged: @escaping () -> Void = {}
  ) {
    self.sessionID = sessionID
    self.store = store
    self.unit = unit
    self.progression = progression
    self.saveAsWorkout = saveAsWorkout
    self.onChanged = onChanged
  }

  var body: some View {
    NavigationStack {
      Group {
        if let receipt = snapshot.value {
          content(receipt)
        } else if snapshot.loadFailed {
          HardsetEmptyState(title: "Could not read this workout", detail: "Your saved sets are unchanged. Try again.",
            systemImage: "exclamationmark.triangle", actionTitle: "Try again", actionSystemImage: "arrow.clockwise", action: { Task { await load() } })
        } else { HardsetLoadingState("Reading your workout…") }
      }
      .background(Tokens.Color.canvas)
      .hardsetNavigationTitle("Workout receipt")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          // While editing, Done ends editing rather than closing the receipt, as it does in every
          // other editable list.
          Button("Done") {
            if editing != nil { editing = nil } else { dismiss() }
          }
        }
        // The way to a correction is at the top, where the receipt opens, and not only under the
        // share and save buttons at the bottom of a long page.
        if let receipt = snapshot.value, !receipt.lines.isEmpty {
          ToolbarItem(placement: .cancellationAction) {
            correctionsMenu
          }
        }
      }
      .task { await load() }
      .alert(
        "Could not change this workout",
        isPresented: Binding(get: { correctionError != nil }, set: { if !$0 { correctionError = nil } })
      ) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(correctionError ?? "")
      }
      .sheet(
        isPresented: $isNamingWorkout,
        onDismiss: {
          nameError = nil
          if let pending = pendingEditor {
            pendingEditor = nil
            editor = pending
          }
        }
      ) {
        NameEntrySheet(
          title: "Save as workout",
          prompt: "Workout name",
          footnote: "Starts a workout with these movements, in this order, in one tap.",
          confirmLabel: "Continue",
          errorMessage: nameError,
          initialName: snapshot.value?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
          onConfirm: { name in Task { await prepareWorkout(named: name) } },
          onCancel: { isNamingWorkout = false }
        )
        .hardsetSheet()
      }
    }
    // On the stack, not the content: a second sheet on one anchor never presents.
    .sheet(item: $editor) { draft in
      if let tools = saveAsWorkout {
        WorkoutEditorScreen(
          templates: tools.templates, catalog: tools.catalog, volume: tools.volume,
          template: draft.template, isDraft: true, others: draft.others,
          onSaved: {
            didSaveWorkout = true
            tools.onSaved()
          },
          onClose: { editor = nil }
        )
        .hardsetSheet()
      }
    }
  }

  private func content(_ receipt: WorkoutReceipt) -> some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          Color.clear.frame(height: 0).id(Self.topID)
          if let correctionNote {
            // Neutral on purpose: a correction updates the ledger and does not celebrate, even
            // when it made a record, so this is a plain note with no trophy and no tint.
            HardsetBanner(.info, message: correctionNote, onDismiss: { self.correctionNote = nil })
              .padding([.horizontal, .top], Tokens.Spacing.loose)
              .hardsetArrival()
          }
          if editing == .correcting {
            HardsetBanner(
              .info, title: "Correcting sets",
              message: "Tap the pencil beside a set to change its weight or reps. Nothing else about the set changes."
            )
            .padding([.horizontal, .top], Tokens.Spacing.loose)
          }
          if editing == .removing {
            HardsetBanner(
              .caveat, title: "Removing sets",
              message: "Tap − beside a set that should not be there to delete it. A removed set cannot be added back; to change its figures instead, correct it."
            )
            .padding([.horizontal, .top], Tokens.Spacing.loose)
          }
          WorkoutReceiptView(
            receipt: receipt, unit: unit,
            onDeleteLine: editing == .removing && !isDeleting ? { pendingSet = $0 } : nil,
            onCorrectLine: editing == .correcting && !isDeleting ? { beginCorrecting($0) } : nil,
            // Offered while no correction or removal is under way, so the pencil and minus controls
            // are not crowded; the shared image is rendered without it.
            onExplainRecords: editing == nil ? { showRecordWorking(line: $0) } : nil,
            onExplainGain: editing == nil ? { showGainWorking() } : nil
          )
          // On the receipt itself: the stack carries the editor's sheet, the group the naming sheet
          // and the scroll reader the correction sheet, and a second sheet on one anchor never
          // presents.
          .sheet(item: $working) { presentation in
            WorkedFromSheet(account: presentation.account)
              .hardsetSheet()
          }
          .confirmationDialog(
            "Delete this set?",
            isPresented: Binding(get: { pendingSet != nil }, set: { if !$0 { pendingSet = nil } }),
            titleVisibility: .visible,
            presenting: pendingSet
          ) { line in
            Button("Delete set", role: .destructive) { Task { await deleteSet(line) } }
            Button("Cancel", role: .cancel) {}
          } message: { line in
            Text("\(WorkoutReceiptView.spokenSet(line, unit: unit)). It will no longer count in History, weekly volume, load history or records. This cannot be undone.")
          }

          VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
            CertaintyBadge(
              level: CertaintyLevel(rawValue: receipt.certainty.rawValue) ?? .unevaluated,
              methodology: "A receipt of saved user-entered sets. Recorded machines, free weight and bodyweight are evaluated; imported sets and machine movements with no machine recorded are unevaluated. No independent load measurement or technique verification is claimed.")
            ShareLink(item: receipt.text(unit: unit)) { Label("Share text receipt", systemImage: "square.and.arrow.up") }
              .buttonStyle(HardsetButtonStyle(.secondary))
            if let image {
              ShareLink(item: image, preview: SharePreview("Hardset workout receipt", image: image)) {
                Label("Share receipt image", systemImage: "photo")
              }.buttonStyle(HardsetButtonStyle())
            }
            if saveAsWorkout != nil, canSaveAsWorkout(receipt) {
              Button {
                isNamingWorkout = true
              } label: {
                Label("Save as workout", systemImage: "square.and.arrow.down.on.square")
              }
              .buttonStyle(HardsetButtonStyle(.secondary))
              .disabled(isDeleting)
              if didSaveWorkout {
                HardsetBanner(
                  .info, message: "Saved as a workout. It is on the Train tab, ready to start in one tap.")
              }
            }
          }
          .padding(Tokens.Spacing.loose)

          // Where a lifter first meets that their history has no copy off this phone: one quiet line
          // under the buttons, only on a build with no iCloud sync. Outside the receipt view, so the
          // shared image never carries it.
          if let note = DataSafetyCopy.receiptNote(for: syncStatus) {
            Text(note)
              .font(Tokens.Text.caption)
              .foregroundStyle(Tokens.Color.chalkDim)
              .fixedSize(horizontal: false, vertical: true)
              .padding(.horizontal, Tokens.Spacing.loose)
              .padding(.bottom, Tokens.Spacing.section)
          }

          if let progression, !receipt.movements.isEmpty {
            loadHistory(receipt.movements, store: progression)
              .padding(.horizontal, Tokens.Spacing.loose)
              .padding(.bottom, Tokens.Spacing.section)
          }

          corrections(receipt) { mode in
            startOrEnd(mode, scrollingWith: proxy)
          }
          .padding(.horizontal, Tokens.Spacing.loose)
          .padding(.bottom, Tokens.Spacing.block)
        }
      }
      // Starting a mode from the toolbar scrolls to the sets it applies to.
      .onChange(of: scrollToTopRequest) {
        withAnimation(Tokens.Motion.adaptive(Tokens.Motion.state, reduceMotion: reduceMotion)) {
          proxy.scrollTo(Self.topID, anchor: .top)
        }
      }
    }
    // On the content, not on the stack and not on the group: the stack carries the editor's sheet
    // and the group the naming sheet, and a second sheet on one anchor never presents.
    .sheet(item: $correcting, onDismiss: { correctionSheetError = nil }) { line in
      SetCorrectionSheet(
        title: line.exerciseName,
        detail: Self.correctionDetail(line),
        weightKg: line.weightKg, reps: line.reps, unit: unit,
        errorMessage: correctionSheetError, isSaving: isSavingCorrection,
        onSave: { draft in Task { await correctSet(line, to: draft) } },
        onCancel: { correcting = nil }
      )
      .hardsetSheet()
    }
  }

  /// The toolbar's way to a correction, at the top of the receipt. Offered while the receipt has
  /// sets; the destructive delete stays below, behind its own confirmation.
  private var correctionsMenu: some View {
    Menu {
      Button {
        startOrEnd(.correcting, scrollingWith: nil)
      } label: {
        Label("Correct a set", systemImage: "pencil")
      }
      Button {
        startOrEnd(.removing, scrollingWith: nil)
      } label: {
        Label("Remove a set", systemImage: "minus.circle")
      }
    } label: {
      Label("Correct", systemImage: "pencil")
    }
    .disabled(isDeleting)
  }

  /// Turns a mode on, or off when it is already the one that is on, and brings the sets into view.
  private func startOrEnd(_ mode: Editing, scrollingWith proxy: ScrollViewProxy?) {
    correctionNote = nil
    editing = editing == mode ? nil : mode
    guard editing != nil else { return }
    if let proxy {
      withAnimation(Tokens.Motion.adaptive(Tokens.Motion.state, reduceMotion: reduceMotion)) {
        proxy.scrollTo(Self.topID, anchor: .top)
      }
    } else {
      scrollToTopRequest &+= 1
    }
  }

  private func beginCorrecting(_ line: WorkoutReceipt.Line) {
    correctionSheetError = nil
    correcting = line
  }

  /// "Sled A · Warm-up": where the set was done and what kind of set it was, under the movement.
  static func correctionDetail(_ line: WorkoutReceipt.Line) -> String {
    [line.equipmentLabel, line.isWarmup ? "Warm-up" : nil].compactMap { $0 }.joined(separator: " · ")
  }

  // MARK: - Records

  /// Opens the working behind the records on one set, or on the whole workout when `line` is `nil`.
  ///
  /// Derived from the receipt on screen as it is now, found again by id, and never from a copy the
  /// control was drawn with. A correction rewrites a set in place and the screen re-reads, so the
  /// records here are the detector's answer on the corrected figures; a set that is no longer in the
  /// receipt, or no longer has a record, opens nothing. The account states the machine step each
  /// record was decided with, so it explains the trophies on screen.
  private func showRecordWorking(line: WorkoutReceipt.Line?) {
    guard let receipt = snapshot.value else { return }
    var current: WorkoutReceipt.Line?
    if let line {
      guard let found = receipt.lines.first(where: { $0.id == line.id }) else { return }
      current = found
    }
    guard
      let account = RecordWorking.receiptAccount(
        receipt: receipt, line: current, format: WorkedFromFormat(unit: unit))
    else { return }
    working = WorkedFromPresentation(account)
  }

  /// Opens the working behind the scorecard's biggest gain: this workout's sets, last time's, the
  /// formula and everything left out.
  ///
  /// Derived from the receipt on screen as it is now, never from a copy the control was drawn with. A
  /// correction rewrites a set in place and the screen re-reads, so the scorecard here is the corrected
  /// one; a gain that is no longer on it opens nothing. The sets it was computed from travel with the
  /// gain, so no read is needed and the account is the figure's own.
  private func showGainWorking() {
    guard let gain = snapshot.value?.scorecard?.biggestGain,
      let working = ChangeWorking.lastTime(gain: gain)
    else { return }
    self.working = WorkedFromPresentation(working.account(format: WorkedFromFormat(unit: unit)))
  }

  // MARK: - Save as workout

  /// Not offered for a workout with no sets, or one that was imported: an imported movement is kept
  /// apart from the catalogue's own on purpose, and a saved workout started from it would log
  /// against that copy.
  private func canSaveAsWorkout(_ receipt: WorkoutReceipt) -> Bool {
    !receipt.movements.isEmpty && !receipt.lines.contains { $0.isImported }
  }

  /// Makes the plan from this workout and hands it to the editor. A failure stays in the naming
  /// sheet, with the name still typed, so trying again is one tap.
  private func prepareWorkout(named name: String) async {
    guard let tools = saveAsWorkout else { return }
    do {
      let plan = try await tools.templates.draft(fromSession: sessionID, name: name)
      let others = try await tools.templates.loadTemplates()
      nameError = nil
      pendingEditor = SavedWorkoutDraft(template: plan, others: others)
      isNamingWorkout = false
    } catch TemplateStoreError.notFound {
      nameError = "This workout could not be found. It may have been deleted."
    } catch {
      nameError = "A workout could not be made from this one. Try again."
    }
  }

  // MARK: - Load history

  /// One link per movement, in the order first performed, to the same per-machine chart the live
  /// session opens. Pushed inside this sheet, so Back returns to the receipt.
  private func loadHistory(_ movements: [WorkoutReceipt.Movement], store: ProgressionStore) -> some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      SectionLabel("Load history", count: movements.count)
      Text("Each movement's heaviest load and estimated one-rep max over time, one line per machine.")
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.chalkDim)
        .fixedSize(horizontal: false, vertical: true)
      ForEach(movements) { movement in
        NavigationLink {
          ExerciseProgressScreen(
            store: store, exerciseID: movement.exerciseID, exerciseName: movement.name, unit: unit)
        } label: {
          HStack(spacing: Tokens.Spacing.regular) {
            Image(systemName: "chart.xyaxis.line")
              .font(Tokens.Text.headline)
              .foregroundStyle(Tokens.Color.plateBlue)
              .accessibilityHidden(true)
            Text(movement.name)
              .font(Tokens.Text.label)
              .foregroundStyle(Tokens.Color.chalk)
              .multilineTextAlignment(.leading)
              .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
              .font(Tokens.Text.caption.weight(.semibold))
              .foregroundStyle(Tokens.Color.chalkDim)
              .accessibilityHidden(true)
          }
          .padding(.horizontal, Tokens.Spacing.regular)
          .padding(.vertical, Tokens.Spacing.snug)
          .frame(maxWidth: .infinity, minHeight: Tokens.minimumTapTarget, alignment: .leading)
        }
        .buttonStyle(ReceiptLinkRowStyle())
        .accessibilityLabel("Load history, \(movement.name)")
      }
    }
  }

  // MARK: - Corrections

  private func corrections(_ receipt: WorkoutReceipt, start: @escaping (Editing) -> Void) -> some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
      SectionLabel("Correct this workout")
      Text("A finished workout feeds History, volume, records and progress, so a correction changes what they read: correct a set's weight or reps, which changes nothing else about it, remove a set that should not be there, or delete the whole workout if it was started by mistake. A removed set cannot be added back.")
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.chalkDim)
        .fixedSize(horizontal: false, vertical: true)
      if !receipt.lines.isEmpty {
        Button {
          start(.correcting)
        } label: {
          Label(
            editing == .correcting ? "Finish correcting sets" : "Correct a set…",
            systemImage: editing == .correcting ? "checkmark" : "pencil")
        }
        .buttonStyle(HardsetButtonStyle(.secondary))
        .disabled(isDeleting)
        Button {
          start(.removing)
        } label: {
          Label(
            editing == .removing ? "Finish removing sets" : "Remove a set…",
            systemImage: editing == .removing ? "checkmark" : "minus.circle")
        }
        .buttonStyle(HardsetButtonStyle(.secondary))
        .disabled(isDeleting)
      }
      Button {
        isConfirmingWorkoutDeletion = true
      } label: {
        Label("Delete workout", systemImage: "trash")
      }
      .buttonStyle(HardsetButtonStyle(.destructive))
      .disabled(isDeleting)
      .confirmationDialog(
        "Delete this workout?",
        isPresented: $isConfirmingWorkoutDeletion,
        titleVisibility: .visible,
        presenting: receipt
      ) { receipt in
        Button("Delete workout", role: .destructive) { Task { await deleteWorkout() } }
        Button("Cancel", role: .cancel) {}
      } message: { receipt in
        Text(Self.workoutDeletionMessage(setCount: receipt.lines.count))
      }
    }
  }

  static func workoutDeletionMessage(setCount: Int) -> String {
    let sets = setCount == 1 ? "Its 1 set is" : "Its \(setCount) sets are"
    return (setCount == 0 ? "" : "\(sets) deleted with it. ")
      + "History, weekly volume, load history and record baselines will change. A copy already "
      + "sent to Apple Health is not removed. This cannot be undone."
  }

  private func deleteSet(_ line: WorkoutReceipt.Line) async {
    pendingSet = nil
    correctionNote = nil
    isDeleting = true
    defer { isDeleting = false }
    do {
      try await store.deleteSet(line.id, inSession: sessionID)
      correctionError = nil
      onChanged()
      await load()
      if snapshot.value?.lines.isEmpty == true { editing = nil }
    } catch {
      correctionError = "The set could not be deleted. Your workout is unchanged."
    }
  }

  /// Writes the correction, and only then changes what the receipt shows. The store persists in one
  /// transaction; on success the receipt is re-read from storage, so its figures, records and
  /// scorecard are the recomputed ones and never a guess made here, and `onChanged` tells the
  /// screens under it to re-read History, volume and progress. A failure leaves the sheet up with
  /// what was typed and the workout as it was.
  private func correctSet(_ line: WorkoutReceipt.Line, to draft: SetEntryDraft) async {
    isSavingCorrection = true
    defer { isSavingCorrection = false }
    do {
      try await store.correctSet(line.id, inSession: sessionID, to: draft)
    } catch {
      correctionSheetError = "The set could not be corrected. Your workout is unchanged."
      return
    }
    correctionSheetError = nil
    onChanged()
    await load()
    correcting = nil
    // Stated from the re-read receipt, so the sentence is about what is now stored. If the re-read
    // failed the screen already says so and there is nothing true to add.
    if let corrected = snapshot.value?.lines.first(where: { $0.id == line.id }) {
      correctionNote = SetCorrectionCopy.note(
        figures: WorkoutReceiptView.spokenSet(corrected, unit: unit),
        before: line.records, after: corrected.records)
    }
  }

  private func deleteWorkout() async {
    isDeleting = true
    defer { isDeleting = false }
    do {
      try await store.deleteSession(sessionID)
    } catch ReceiptError.sessionNotFound {
      // Already gone, for example removed on another device. Nothing is left to show.
    } catch {
      correctionError = "The workout could not be deleted. Nothing was removed."
      return
    }
    onChanged()
    dismiss()
  }

  private func load() async {
    // Captured as values, so the read closure holds only Sendable stores and identifiers.
    let store = store
    let sessionID = sessionID
    await snapshot.load { try await store.load(sessionID) }
    #if canImport(UIKit)
      guard let receipt = snapshot.value else { return }
      // Keep very long sessions as text rather than allocate an unbounded bitmap.
      guard receipt.lines.count <= 30 else { image = nil; return }
      let renderer = ImageRenderer(content: WorkoutReceiptView(receipt: receipt, unit: unit)
        .frame(width: 540).environment(\.colorScheme, .dark).environment(\.dynamicTypeSize, .large))
      renderer.scale = min(displayScale, 2)
      if let rendered = renderer.uiImage { image = Image(uiImage: rendered) }
    #endif
  }
}

/// A link row to a movement's load history: the card's fill, with the pressed fill faded in over
/// it and the row pressed in slightly. Scale is dropped with Reduce Motion.
private struct ReceiptLinkRowStyle: ButtonStyle {
  // Spelled out rather than `Configuration`, matching the root view: a GRDB `Configuration` in
  // scope would shadow the style's associated type.
  func makeBody(configuration: ButtonStyleConfiguration) -> some View {
    ReceiptLinkRowBody(configuration: configuration)
  }
}

private struct ReceiptLinkRowBody: View {
  let configuration: ButtonStyleConfiguration
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: Tokens.Radius.control)
    configuration.label
      .background {
        ZStack {
          shape.fill(Tokens.Color.steel)
          shape.fill(Tokens.Color.steelPressed)
            .opacity(configuration.isPressed ? 1 : 0)
        }
      }
      .overlay(shape.strokeBorder(Tokens.Color.hairline, lineWidth: Tokens.Stroke.hairline))
      .contentShape(shape)
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
      .animation(
        Tokens.Motion.adaptive(Tokens.Motion.press, reduceMotion: reduceMotion),
        value: configuration.isPressed
      )
  }
}
