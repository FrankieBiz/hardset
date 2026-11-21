import HardsetCore
import SwiftUI

/// Every state of the set row, for review from images: the four log control states and their
/// presses, the value fields at rest, pressed, editing and read-only, and whole rows.
///
/// Static: no state, no I/O. A `ButtonStyle` cannot be forced pressed in a render, so each pressed
/// sample is the style's own face, `SetRowFieldFace` or `SetLogControlFace`, drawn with its pressed
/// state. Whole rows are the live `SetRowView` on constant drafts.
public struct SetRowCatalogView: View {
  public enum Section: String, CaseIterable, Sendable {
    case logControl, fields, rows
  }

  private let section: Section?

  public init(section: Section? = nil) {
    self.section = section
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Tokens.Spacing.section) {
        if let section {
          sectionView(section)
        } else {
          ForEach(Section.allCases, id: \.self) { sectionView($0) }
        }
      }
      .padding(.horizontal, Tokens.Spacing.loose)
      .padding(.vertical, Tokens.Spacing.loose)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(Tokens.Color.canvas.ignoresSafeArea())
  }

  @ViewBuilder
  private func sectionView(_ section: Section) -> some View {
    switch section {
    case .logControl: LogControlStates()
    case .fields: FieldStates()
    case .rows: RowStates()
    }
  }
}

// MARK: - Shared helpers

private func setRowNote(_ text: String) -> some View {
  Text(text)
    .hardsetText(.caption)
    .foregroundStyle(Tokens.Color.chalkDim)
    .fixedSize(horizontal: false, vertical: true)
}

/// A sample with its caption underneath, left aligned so a fixed-size control and a full-width
/// stacked one read the same way.
private func setRowSample<Content: View>(
  _ caption: String, @ViewBuilder content: () -> Content
) -> some View {
  VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
    content()
    setRowNote(caption)
  }
}

private func setRowPrior(_ weightKg: Double, _ reps: Int) -> PriorSetRecord {
  PriorSetRecord(weightKg: weightKg, reps: reps, completedAt: .distantPast)
}

// MARK: - Log control

private struct LogControlStates: View {
  var body: some View {
    CatalogSection("Log control") {
      VStack(alignment: .leading, spacing: Tokens.Spacing.loose) {
        setRowNote(
          "Four states, never confused: one SF Symbol of one weight and one size in each. A square "
            + "logs a set and a circle is a set that is logged, so logged and next up differ in shape "
            + "and not only in hue. Ready and next up press with the opacity press; incomplete and "
            + "logged are disabled and show no press."
        )
        setRowSample("Incomplete: an empty square in controlEdge, disabled") {
          SetLogControlFace(state: .incomplete, isPressed: false)
        }
        setRowSample("Ready: a checked square in chalkDim") {
          SetLogControlFace(state: .ready, isPressed: false)
        }
        setRowSample("Ready, pressed: sinks to 0.97 and dims to 80%") {
          SetLogControlFace(state: .ready, isPressed: true)
        }
        setRowSample("Next up: the square filled with plate blue, the screen's one accent") {
          SetLogControlFace(state: .nextUp, isPressed: false)
        }
        setRowSample("Next up, pressed: same fill, 0.97 and 80%") {
          SetLogControlFace(state: .nextUp, isPressed: true)
        }
        setRowSample("Logged: a round plate green seal, no tint behind it") {
          SetLogControlFace(state: .logged, isPressed: false)
        }
      }
    }
  }
}

// MARK: - Fields

private struct FieldStates: View {
  var body: some View {
    CatalogSection("Value fields") {
      VStack(alignment: .leading, spacing: Tokens.Spacing.loose) {
        setRowNote(
          "Plain figures with no box. A figure still to be logged is dimmed; a saved one is full "
            + "chalk. Pressed sinks to 0.97 and dims to 80%. Editing adds a caret and a 2 pt "
            + "underline, drawn still. Increase Contrast and Button Shapes bring the outline back."
        )
        setRowSample("Rest: weight and reps") {
          pair(.rest, weight: "100", reps: "8")
        }
        setRowSample("Pressed") {
          pair(.pressed, weight: "100", reps: "8")
        }
        setRowSample("Editing weight, mid-entry \"100.\"") {
          pair(.editing, weight: "100.", reps: "8", editingBoth: false)
        }
        setRowSample("Editing reps") {
          HStack(spacing: Tokens.Spacing.snug) {
            field(.rest, text: "100", suffix: "kg")
            field(.editing, text: "8", suffix: "reps")
          }
        }
        setRowSample("Empty: an em dash, never zero") {
          pair(.rest, weight: nil, reps: nil)
        }
        setRowSample("Read-only: saved values keep full contrast") {
          pair(.readOnly, weight: "100", reps: "8")
        }
      }
    }
  }

  /// A weight field and a reps field in the same state; `editingBoth: false` leaves the reps field
  /// at rest so only one field wears the caret.
  private func pair(
    _ state: SetRowFieldState, weight: String?, reps: String?, editingBoth: Bool = true
  ) -> some View {
    HStack(spacing: Tokens.Spacing.snug) {
      field(state, text: weight, suffix: "kg")
      field(editingBoth ? state : .rest, text: reps, suffix: "reps")
    }
  }

  private func field(_ state: SetRowFieldState, text: String?, suffix: String) -> some View {
    SetRowFieldFace(state: state, reduceMotion: false) {
      // Only the read-only sample stands for a saved figure; every other state is still to log.
      SetRowFieldValue(text: text, suffix: suffix, state: state, isLogged: state == .readOnly)
    }
  }
}

// MARK: - Rows

private struct RowStates: View {
  var body: some View {
    CatalogSection("Rows") {
      VStack(alignment: .leading, spacing: Tokens.Spacing.loose) {
        setRowNote("The live row on constant drafts, in the order a set moves through the card.")
        setRowSample("Logged: the seal, saved figures in full chalk, no tint") {
          row(
            draft(100, 8), ordinal: 0, isLogged: true, previous: setRowPrior(100, 8),
            onUndo: {}, onEdit: {})
        }
        setRowSample("Next up and ready: filled square, step buttons in kg") {
          row(
            draft(105, 6), ordinal: 1, isNext: true, increment: 2.5, previous: setRowPrior(105, 6),
            editable: true)
        }
        setRowSample("Next up in pounds: step buttons in lb") {
          row(
            draft(100, 8), ordinal: 1, isNext: true, unit: .pounds, increment: 2.26796185,
            previous: setRowPrior(100, 8), editable: true)
        }
        setRowSample("Ready, not next: checked square") {
          row(draft(105, 6), ordinal: 2, previous: setRowPrior(105, 6), editable: true)
        }
        setRowSample("Next row, incomplete: empty square, not blue") {
          row(blank, ordinal: 3, isNext: true, editable: true)
        }
        setRowSample("Warm-up, blank") {
          row(blank, ordinal: 0, isWarmup: true, editable: true)
        }
        setRowSample("Warm-up, filled") {
          row(draft(40, 10), ordinal: 0, isWarmup: true, previous: setRowPrior(40, 10), editable: true)
        }
        setRowSample("Editing weight, mid-entry \"100.\"") {
          row(
            draft(100, 8), ordinal: 1, previous: setRowPrior(100, 8), editingField: .weight,
            editingText: "100.", editable: true)
        }
        setRowSample("Editing reps") {
          row(
            draft(100, 8), ordinal: 1, previous: setRowPrior(100, 8), editingField: .reps,
            editingText: "8", editable: true)
        }
        setRowSample("Read-only: no keypad host, so no field can be tapped") {
          row(draft(100, 8), ordinal: 1, previous: setRowPrior(100, 8))
        }
        setRowSample("Prior note: an assumption the lifter can see") {
          row(
            draft(100, 8), ordinal: 1, previous: setRowPrior(100, 8),
            priorNote: "Borrowed from another machine", editable: true)
        }
        setRowSample("No previous: an em dash in Last time") {
          row(blank, ordinal: 4, editable: true)
        }
        setRowSample("Target, one more rep: the line says where the numbers came from") {
          row(
            targeted(40, 11, .addRep, last: (40, 10)), ordinal: 1, isNext: true, increment: 2.5,
            previous: setRowPrior(40, 10), editable: true)
        }
        setRowSample("Target, every set at the top: add one step") {
          row(
            targeted(42.5, 8, .addLoad(stepKg: 2.5, isAssumedStep: false), last: (40, 12)),
            ordinal: 1, isNext: true, previous: setRowPrior(40, 12), editable: true)
        }
        setRowSample("Target in pounds, assumed step: one plate") {
          row(
            targeted(43.09, 8, .addLoad(stepKg: 2.26796185, isAssumedStep: true), last: (40.82, 12)),
            ordinal: 1, isNext: true, unit: .pounds, previous: setRowPrior(40.82, 12),
            editable: true)
        }
        setRowSample("Beat mark: a rep more than last time") {
          row(
            draft(40, 11), ordinal: 1, isLogged: true, previous: setRowPrior(40, 10),
            comparison: .beat(addedKg: 0, addedReps: 1), onUndo: {}, onEdit: {})
        }
        setRowSample("Beat mark: more load and a rep") {
          row(
            draft(42.5, 11), ordinal: 1, isLogged: true, previous: setRowPrior(40, 10),
            comparison: .beat(addedKg: 2.5, addedReps: 1), onUndo: {}, onEdit: {})
        }
        setRowSample("Beat mark in pounds: ten pounds more") {
          row(
            draft(45.359237, 8), ordinal: 1, isLogged: true, unit: .pounds,
            previous: setRowPrior(40.8233133, 8), comparison: .beat(addedKg: 4.5359237, addedReps: 0),
            onUndo: {}, onEdit: {})
        }
        setRowSample("Matched: neutral, equals sign") {
          row(
            draft(40, 10), ordinal: 1, isLogged: true, previous: setRowPrior(40, 10),
            comparison: .matched, onUndo: {}, onEdit: {})
        }
        setRowSample("Fell short, or no partner: no mark at all") {
          row(
            draft(40, 9), ordinal: 1, isLogged: true, previous: setRowPrior(40, 10),
            onUndo: {}, onEdit: {})
        }
      }
    }
  }

  private func targeted(
    _ weightKg: Double, _ reps: Int, _ rule: SetTarget.Rule, last: (Double, Int)
  ) -> SetEntryDraft {
    SetEntryDraft(
      target: SetTarget(weightKg: weightKg, reps: reps, rule: rule),
      suggestion: setRowPrior(last.0, last.1))
  }

  private var blank: SetEntryDraft { SetEntryDraft(suggestion: nil) }

  private func draft(_ weightKg: Double, _ reps: Int) -> SetEntryDraft {
    SetEntryDraft(weightKg: weightKg, reps: reps)
  }

  private func row(
    _ draft: SetEntryDraft,
    ordinal: Int,
    isWarmup: Bool = false,
    isLogged: Bool = false,
    isNext: Bool = false,
    unit: WeightUnit = .kilograms,
    increment: Double? = nil,
    previous: PriorSetRecord? = nil,
    priorNote: String? = nil,
    comparison: SetComparison? = nil,
    editingField: SetRowField? = nil,
    editingText: String? = nil,
    editable: Bool = false,
    onUndo: (() -> Void)? = nil,
    onEdit: (() -> Void)? = nil
  ) -> some View {
    SetRowView(
      draft: .constant(draft),
      ordinal: ordinal,
      isWarmup: isWarmup,
      isLogged: isLogged,
      isNext: isNext,
      unit: unit,
      machineIncrementKg: increment,
      previous: previous,
      priorNote: priorNote,
      comparison: comparison,
      editingField: editingField,
      editingText: editingText,
      onLog: {},
      onBeginEditing: editable ? { _ in } : nil,
      onUndo: onUndo,
      onEdit: onEdit
    )
  }
}

#if DEBUG
  #Preview("Set row, all states") {
    SetRowCatalogView()
  }
#endif
