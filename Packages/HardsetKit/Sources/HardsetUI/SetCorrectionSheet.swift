import HardsetCore
import SwiftUI

/// Corrects the weight and reps of a set in a finished workout.
///
/// The live session corrects a figure where it is written, on its own keypad. A finished workout is
/// read on a receipt, a static ledger that is also rendered into a shared image, so the correction
/// has a sheet of its own: both figures, one pad, and an explicit Save that is the only thing that
/// writes. Nothing is written as keys are pressed, and the sheet stays up with everything typed when
/// a save fails, so trying again is one tap.
///
/// It says what the correction reaches before it is made. A finished workout is what History,
/// volume, records and progress read, so the set is not edited quietly: the line under the title
/// names those, and the note that later workouts' comparisons with this one are recalculated too.
/// It is neutral about records. A correction updates the ledger and does not celebrate.
///
/// The keypad is the logger's own `NumericPad`, in a sheet, as the machine's load-step editor uses
/// it, so a lifter who has typed a weight on the gym floor has typed one here.
public struct SetCorrectionSheet: View {
  private let title: String
  private let detail: String
  private let unit: WeightUnit
  private let errorMessage: String?
  private let isSaving: Bool
  private let onSave: (SetEntryDraft) -> Void
  private let onCancel: () -> Void

  @State private var entry: SetCorrectionEntry
  @State private var field: SetRowField = .weight

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  /// - Parameter title: The movement, as the receipt names it.
  /// - Parameter detail: Where it was done and anything else that identifies the set, such as
  ///   "Sled A · Warm-up".
  /// - Parameter weightKg: The saved weight, in canonical kilograms. It is shown in `unit`, and
  ///   written back exactly as saved unless the lifter types a new one.
  /// - Parameter errorMessage: Why the last save failed. The sheet stays up and keeps what was typed.
  /// - Parameter isSaving: A save is in flight, so the primary action waits.
  /// - Parameter onSave: Handed the corrected figures, in kilograms, once the lifter confirms. The
  ///   host writes them and closes the sheet only after the write has succeeded.
  public init(
    title: String, detail: String, weightKg: Double, reps: Int, unit: WeightUnit,
    errorMessage: String? = nil, isSaving: Bool = false,
    onSave: @escaping (SetEntryDraft) -> Void, onCancel: @escaping () -> Void
  ) {
    self.title = title
    self.detail = detail
    self.unit = unit
    self.errorMessage = errorMessage
    self.isSaving = isSaving
    self.onSave = onSave
    self.onCancel = onCancel
    self._entry = State(initialValue: SetCorrectionEntry(weightKg: weightKg, reps: reps, unit: unit))
  }

  public var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
          VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
            Text(title)
              .font(Tokens.Text.title)
              .foregroundStyle(Tokens.Color.chalk)
              .fixedSize(horizontal: false, vertical: true)
            if !detail.isEmpty {
              Text(detail)
                .hardsetText(.provenance)
                .foregroundStyle(Tokens.Color.chalkDim)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
          .accessibilityElement(children: .combine)
          .accessibilityAddTraits(.isHeader)

          Text(
            "Only the weight and reps change. History, volume, records and progress are recalculated from the corrected figures, including how later workouts compare with this one."
          )
          .hardsetText(.provenance)
          .foregroundStyle(Tokens.Color.chalkDim)
          .fixedSize(horizontal: false, vertical: true)

          if let errorMessage, !errorMessage.isEmpty {
            HardsetBanner(.error, message: errorMessage)
              .hardsetArrival()
          }

          figures

          // One commit action, the pad's own footer: "Next" on the weight, "Save correction" on the
          // reps. A separate Save beside a pad with its own Done would be two commits.
          NumericPad(
            buffer: activeBuffer,
            title: field == .weight ? "Weight" : "Reps",
            unit: field == .weight ? unit.abbreviation : "reps",
            doneTitle: field == .weight ? "Next" : "Save correction",
            isDoneEnabled: field == .weight ? entry.weightKg != nil : canSave,
            onDone: primaryAction
          )
        }
        .padding(Tokens.Spacing.loose)
      }
      .background(Tokens.Color.canvas)
      .tint(Tokens.Color.plateBlue)
      .hardsetNavigationTitle("Correct set")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: onCancel)
            .disabled(isSaving)
        }
      }
    }
    // Typed figures survive a brushed swipe; Cancel is the explicit way out.
    .interactiveDismissDisabled(entry.changesFigures || isSaving)
  }

  // MARK: - Pieces

  private var canSave: Bool { entry.isComplete && entry.changesFigures && !isSaving }

  /// "Next" on the weight, which moves the pad to the reps; "Save correction" on the reps, which
  /// hands the figures to the host. Nothing is written before that.
  private func primaryAction() {
    if field == .weight {
      field = .reps
    } else {
      guard canSave else { return }
      onSave(entry.draft)
    }
  }

  private var activeBuffer: Binding<NumericEntryBuffer> {
    Binding(
      get: { field == .weight ? entry.weightBuffer : entry.repsBuffer },
      set: { updated in
        if field == .weight {
          entry.weightBuffer = updated
        } else {
          entry.repsBuffer = updated
        }
      })
  }

  /// Both figures as type, the one the pad is on in `chalk` with a rule under it and the other in
  /// `chalkDim`, each a 56 pt control that puts the pad on it. Side by side at ordinary sizes and
  /// one above the other at accessibility sizes, where two readouts would not share a line.
  private var figures: some View {
    let layout: AnyLayout =
      dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tokens.Spacing.snug))
      : AnyLayout(HStackLayout(alignment: .top, spacing: Tokens.Spacing.loose))
    return layout {
      figure(.weight)
      figure(.reps)
    }
  }

  private func figure(_ target: SetRowField) -> some View {
    let isActive = field == target
    let buffer = target == .weight ? entry.weightBuffer : entry.repsBuffer
    let name = target == .weight ? "Weight (\(unit.abbreviation))" : "Reps"
    let shown = buffer.isEmpty ? "—" : LoadFigure.typed(buffer.displayText)
    return Button {
      field = target
    } label: {
      VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
        Text(name)
          .hardsetText(.caption)
          .foregroundStyle(Tokens.Color.chalkDim)
        Text(shown)
          .hardsetText(.readout)
          .foregroundStyle(isActive ? Tokens.Color.chalk : Tokens.Color.chalkDim)
          .lineLimit(1)
        Rectangle()
          .fill(isActive ? Tokens.Color.chalk : Color.clear)
          .frame(height: Tokens.Stroke.selected)
          .accessibilityHidden(true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .buttonStyle(
      InlineControlStyle(minHeight: Tokens.loggerTapTarget, alignment: .leading, fullWidth: true)
    )
    .accessibilityLabel("\(name), \(buffer.isEmpty ? "empty" : buffer.displayText)")
    .accessibilityAddTraits(isActive ? .isSelected : [])
  }
}

#if DEBUG
  #Preview("Correct a finished set, kg") {
    SetCorrectionSheet(
      title: "Barbell Bench Press", detail: "Free weight", weightKg: 80, reps: 5, unit: .kilograms,
      onSave: { _ in }, onCancel: {})
  }

  #Preview("Correct a finished set, lb, failed save, accessibility size") {
    SetCorrectionSheet(
      title: "Cybex Chest Press", detail: "Sled A · Warm-up", weightKg: 60, reps: 100, unit: .pounds,
      errorMessage: "The set could not be corrected. Your workout is unchanged.",
      onSave: { _ in }, onCancel: {}
    )
    .environment(\.dynamicTypeSize, .accessibility3)
  }
#endif
