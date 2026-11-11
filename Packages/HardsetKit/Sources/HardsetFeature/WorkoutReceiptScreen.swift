import HardsetCore
import HardsetStore
import HardsetUI
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A past workout's receipt, with the two corrections a lifter may need and a way into each
/// movement's load history.
///
/// Saved sets are never edited. A mis-logged set can be removed, and a workout started by mistake
/// can be deleted, each behind a destructive confirmation that says what will change. The receipt
/// itself stays a static ledger, because the same view is shared as an image.
struct WorkoutReceiptScreen: View {
  private let sessionID: SessionID
  private let store: ReceiptStore
  private let unit: WeightUnit
  private let progression: ProgressionStore?
  /// Called after a set or the workout was deleted, so the caller can re-read what it shows.
  private let onChanged: () -> Void

  @State private var snapshot = SnapshotLoader<WorkoutReceipt>()
  @State private var image: Image?
  @State private var isEditing = false
  @State private var pendingSet: WorkoutReceipt.Line?
  @State private var isConfirmingWorkoutDeletion = false
  @State private var isDeleting = false
  @State private var correctionError: String?
  @Environment(\.displayScale) private var displayScale
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private static let topID = "receipt-top"

  init(
    sessionID: SessionID, store: ReceiptStore, unit: WeightUnit,
    progression: ProgressionStore? = nil, onChanged: @escaping () -> Void = {}
  ) {
    self.sessionID = sessionID
    self.store = store
    self.unit = unit
    self.progression = progression
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
      .background(Tokens.Color.background)
      .hardsetNavigationTitle("Workout receipt")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          // While editing, Done ends editing rather than closing the receipt, as it does in every
          // other editable list.
          Button("Done") {
            if isEditing { isEditing = false } else { dismiss() }
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
    }
  }

  private func content(_ receipt: WorkoutReceipt) -> some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          Color.clear.frame(height: 0).id(Self.topID)
          if isEditing {
            HardsetBanner(
              .caveat, title: "Removing sets",
              message: "Tap − beside a mis-logged set to delete it. Saved sets are never edited, only removed."
            )
            .padding([.horizontal, .top], Tokens.Spacing.loose)
          }
          WorkoutReceiptView(
            receipt: receipt, unit: unit,
            onDeleteLine: isEditing && !isDeleting ? { pendingSet = $0 } : nil
          )
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
          }
          .padding(Tokens.Spacing.loose)

          if let progression, !receipt.movements.isEmpty {
            loadHistory(receipt.movements, store: progression)
              .padding(.horizontal, Tokens.Spacing.loose)
              .padding(.bottom, Tokens.Spacing.section)
          }

          corrections(receipt) {
            isEditing.toggle()
            if isEditing {
              withAnimation(Tokens.Motion.adaptive(Tokens.Motion.state, reduceMotion: reduceMotion)) {
                proxy.scrollTo(Self.topID, anchor: .top)
              }
            }
          }
          .padding(.horizontal, Tokens.Spacing.loose)
          .padding(.bottom, Tokens.Spacing.block)
        }
      }
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
        .foregroundStyle(Tokens.Color.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
      ForEach(movements) { movement in
        NavigationLink {
          ExerciseProgressScreen(
            store: store, exerciseID: movement.exerciseID, exerciseName: movement.name, unit: unit)
        } label: {
          HStack(spacing: Tokens.Spacing.regular) {
            Image(systemName: "chart.xyaxis.line")
              .font(Tokens.Text.headline)
              .foregroundStyle(Tokens.Color.accent)
              .accessibilityHidden(true)
            Text(movement.name)
              .font(Tokens.Text.label)
              .foregroundStyle(Tokens.Color.textPrimary)
              .multilineTextAlignment(.leading)
              .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
              .font(Tokens.Text.caption.weight(.semibold))
              .foregroundStyle(Tokens.Color.textSecondary)
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

  private func corrections(_ receipt: WorkoutReceipt, toggleEditing: @escaping () -> Void) -> some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
      SectionLabel("Correct this workout")
      Text("Saved sets are never edited. Remove a mis-logged set, or delete the whole workout if it was started by mistake.")
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
      if !receipt.lines.isEmpty {
        Button(action: toggleEditing) {
          Label(isEditing ? "Finish removing sets" : "Remove a set…", systemImage: isEditing ? "checkmark" : "minus.circle")
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
    isDeleting = true
    defer { isDeleting = false }
    do {
      try await store.deleteSet(line.id, inSession: sessionID)
      correctionError = nil
      onChanged()
      await load()
      if snapshot.value?.lines.isEmpty == true { isEditing = false }
    } catch {
      correctionError = "The set could not be deleted. Your workout is unchanged."
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
          shape.fill(Tokens.Color.surface)
          shape.fill(Tokens.Color.surfacePressed)
            .opacity(configuration.isPressed ? 1 : 0)
        }
      }
      .overlay(shape.strokeBorder(Tokens.Color.border, lineWidth: Tokens.Stroke.hairline))
      .contentShape(shape)
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
      .animation(
        Tokens.Motion.adaptive(Tokens.Motion.press, reduceMotion: reduceMotion),
        value: configuration.isPressed
      )
  }
}
