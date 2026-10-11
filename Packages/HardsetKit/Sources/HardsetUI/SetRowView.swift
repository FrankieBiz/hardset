import HardsetCore
import SwiftUI

/// Which value a row is editing. `nil` means the row is idle.
public enum SetRowField: Hashable, Sendable {
  case weight
  case reps
}

/// How much a row stands out (spec 2.2, "the current set is the hero").
public enum SetRowEmphasis: Hashable, Sendable {
  /// The set the lifter is about to do: its weight is the largest type on screen.
  case active
  /// A set still to come, at the ordinary size.
  case upcoming
  /// Done: compact, and read-only.
  case logged
}

/// One set, ready to log in a single tap.
///
/// Three rules this view exists to hold:
///
/// 1. **The prefill is a committed value, never placeholder text.** The reference app put last
///    session's numbers in `TextField(prompt:)`, so a row that visibly read "60" reported an
///    empty field and logged 0 kg. Here the suggestion is written into the draft, and the
///    "Last time" column is rendered *outside* the fields — so what looks filled is filled, and
///    what is only a hint cannot be mistaken for one.
/// 2. **The log control cannot fire on an incomplete row.** It is bound to
///    `SetEntryDraft.isLoggable`, which is the same predicate `LoggerStore.logSet` enforces. A
///    disagreement between them is impossible because there is only one predicate.
/// 3. **The row is one accessibility element.** A 40-set session with five separately focusable
///    controls per row costs roughly 280 VoiceOver swipes to review. The row reads as a
///    sentence and exposes its actions as named custom actions instead.
public struct SetRowView: View {
  // No editable state lives here. The row used to keep its own weight and reps buffers, and every
  // Phase 1 display bug came from those copies going stale: a unit change left pounds under a
  // "kg" suffix (spec 1.5), and a machine change left the field showing a number the row would
  // not save (spec 1.6). Now an unfocused row renders the draft directly, so there is no copy to
  // go stale, and the focused row renders the keypad, which `SessionView` owns and rebuilds when
  // the draft changes from outside.
  private let draft: SetEntryDraft
  private let ordinal: Int
  private let isWarmup: Bool
  private let isLogged: Bool
  private let unit: WeightUnit
  private let previous: PriorSetRecord?
  private let priorNote: String?
  private let emphasis: SetRowEmphasis
  private let keypad: SetEntryKeypad?
  private let records: [PersonalRecord]
  private let recordPulse: Int
  private let isEditingSaved: Bool
  private let exerciseName: String
  private let onFocus: (SetRowField) -> Void
  private let onLog: () -> Void
  private let onEdit: (() -> Void)?
  private let onDelete: (() -> Void)?

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var typeSize
  // Widths that hold text scale with it: a fixed 28 pt column clips "12" at the largest sizes.
  // `ScaledMetric` is iOS 14 / macOS 11.
  @ScaledMetric(relativeTo: .subheadline) private var ordinalWidth: CGFloat = 28
  @ScaledMetric(relativeTo: .caption) private var lastTimeWidth: CGFloat = 78
  // The tap targets grow with the type as well, and never fall below the 44 pt and 56 pt floors.
  // Capped at 88 pt (the pad's key cap): uncapped, 56 pt reaches about 170 pt at the largest size,
  // and the reps field plus the check mark would leave the hero weight no room (it would shrink
  // to its 0.6 floor or truncate). The floors stay 56 and 44.
  @ScaledMetric(relativeTo: .body) private var scaledLoggerTarget: CGFloat = Tokens.loggerTapTarget
  @ScaledMetric(relativeTo: .body) private var scaledMinimumTarget: CGFloat =
    Tokens.minimumTapTarget
  private var loggerTarget: CGFloat { min(scaledLoggerTarget, Self.targetCap) }
  private var minimumTarget: CGFloat { min(scaledMinimumTarget, Self.targetCap) }
  private static let targetCap: CGFloat = 88
  @State private var isExplainingEstimate = false

  /// - Parameter keypad: The pad editing this row, or `nil` when the row is not focused. While it
  ///   is set the row shows what is being typed, which `SessionView` also writes into the draft,
  ///   except during a correction (`isEditingSaved`), which stays in the pad until Save.
  /// - Parameter records: What this row's set earned, as the coordinator holds it. Non-empty shows
  ///   the trophy. Only the caller decides; the row never judges a record.
  /// - Parameter recordPulse: Changes once, on the log that earned the records, which bounces the
  ///   trophy. It stays put afterwards, so a later log elsewhere does not bounce it again.
  /// - Parameter isEditingSaved: The pad is correcting this saved set. What it shows is not saved
  ///   until the store accepts it, and the row says so.
  /// - Parameter exerciseName: Only for what VoiceOver says about a record ("New record on Leg
  ///   Press"). Empty reads as "this set".
  /// - Parameter onFocus: A field was tapped. The caller opens the pad on it.
  /// - Parameter onEdit: Corrects a logged set. `nil`, or an unlogged row, offers no Edit.
  /// - Parameter onDelete: Deletes a logged set. `nil`, or an unlogged row, offers no Delete.
  public init(
    draft: SetEntryDraft,
    ordinal: Int,
    isWarmup: Bool = false,
    isLogged: Bool = false,
    unit: WeightUnit,
    previous: PriorSetRecord? = nil,
    priorNote: String? = nil,
    emphasis: SetRowEmphasis = .upcoming,
    keypad: SetEntryKeypad? = nil,
    records: [PersonalRecord] = [],
    recordPulse: Int = 0,
    isEditingSaved: Bool = false,
    exerciseName: String = "",
    onFocus: @escaping (SetRowField) -> Void,
    onLog: @escaping () -> Void,
    onEdit: (() -> Void)? = nil,
    onDelete: (() -> Void)? = nil
  ) {
    self.draft = draft
    self.ordinal = ordinal
    self.isWarmup = isWarmup
    self.isLogged = isLogged
    self.unit = unit
    self.previous = previous
    self.priorNote = priorNote
    self.emphasis = emphasis
    self.keypad = keypad
    self.records = records
    self.recordPulse = recordPulse
    self.isEditingSaved = isEditingSaved
    self.exerciseName = exerciseName
    self.onFocus = onFocus
    self.onLog = onLog
    self.onEdit = onEdit
    self.onDelete = onDelete
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
      rowContent
      rowNotes
    }
    .padding(.horizontal, Tokens.Spacing.regular)
    .padding(.vertical, emphasis == .logged ? Tokens.Spacing.tight : Tokens.Spacing.snug)
    // Opaque. Dense numeric rows are the one surface glass is actively wrong for.
    .background(Tokens.Color.surface)
    // The current set is marked by size and an outline, never by dimming the others: every row
    // keeps full-contrast text.
    .overlay {
      if emphasis == .active {
        RoundedRectangle(cornerRadius: Tokens.Radius.control)
          .strokeBorder(Tokens.Color.accent, lineWidth: 2)
      }
    }
    // A saved set is corrected or removed from here (spec 2.3). An unlogged row has nothing to
    // correct, since it is edited by typing into it, so its menu is empty and none is shown.
    .contextMenu {
      if isLogged {
        if let onEdit { Button("Edit", systemImage: "pencil", action: onEdit) }
        if let onDelete {
          Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(SetRowSpeech.label(number: ordinal + 1, isWarmup: isWarmup))
    .accessibilityValue(spokenValue)
    // A logged row is read-only (see `valueField`), so Core gives it no hint.
    .accessibilityHint(SetRowSpeech.hint(isLoggable: draft.isLoggable, isLogged: isLogged) ?? "")
    .accessibilityAddTraits(isLogged ? .isSelected : .isButton)
    // The default action: a double tap anywhere on the row logs what the row shows, through the
    // same `onLog` as the check mark. Nothing is logged that the lifter cannot see.
    .accessibilityAction {
      if !isLogged && draft.isLoggable { onLog() }
    }
    .accessibilityAction(named: Text("Log set")) {
      if draft.isLoggable { onLog() }
    }
    // The row is one combined element, so `.disabled` on the field buttons does not reach these.
    // Left in place on a logged row they would still open the pad and edit an unsaved draft.
    .accessibilityActions {
      if isLogged {
        // The context menu's two actions, by name, for VoiceOver.
        if let onEdit { Button("Edit set", action: onEdit) }
        if let onDelete { Button("Delete set", action: onDelete) }
      } else {
        Button("Edit weight") { onFocus(.weight) }
        Button("Edit reps") { onFocus(.reps) }
      }
      if estimateCertainty != nil {
        Button("How this estimate is calculated") { isExplainingEstimate = true }
      }
    }
    .sheet(isPresented: $isExplainingEstimate) {
      if let certainty = estimateCertainty {
        MethodologySheet(source: StrengthMath.epleySource, certainty: certainty)
      }
    }
  }

  // MARK: - Pieces

  /// The active row puts "Last time" on its own line under the fields, and its reps field takes
  /// only the width its digits need, so the weight gets the rest.
  ///
  /// In the five-column row a 375 pt phone left about 44 pt for the number, and "102.5" in the
  /// hero size needs about 90: it truncated to "10…", so the screen no longer showed what Log
  /// would save. The active row's weight now gets about 140 pt (worked through in the Task 13
  /// report). Other rows keep the columns, where the smaller `setEntry` type fits.
  @ViewBuilder private var rowContent: some View {
    if typeSize.isAccessibilitySize {
      // At accessibility sizes five columns cannot hold the numbers. Stacked, the weight gets the
      // whole width of its own line, for every emphasis.
      VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.regular) {
          ordinalBadge
          lastTimeColumn
        }
        HStack(spacing: Tokens.Spacing.regular) {
          valueField(.weight, suffix: unit.abbreviation)
          valueField(.reps, suffix: "reps")
        }
        // On its own line: weight, reps and the check mark do not share one at these sizes.
        // Width on a 375 pt phone at the largest size: 351 pt inside the row's padding. Weight
        // and reps alone leave 351 - 12 (gap) - 88 (reps, at the cap) = 251 pt for the weight.
        // With the check beside them it was 351 - 24 - 88 - 88 = 151 pt.
        HStack(spacing: 0) {
          Spacer(minLength: 0)
          logButton
        }
      }
    } else if emphasis == .active {
      VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
        HStack(spacing: Tokens.Spacing.regular) {
          ordinalBadge
          valueField(.weight, suffix: unit.abbreviation)
          valueField(.reps, suffix: "reps")
          logButton
        }
        lastTimeLine
          // Under the weight, past the ordinal badge.
          .padding(.leading, ordinalWidth + Tokens.Spacing.regular)
      }
    } else {
      HStack(spacing: Tokens.Spacing.regular) {
        ordinalBadge
        lastTimeColumn
          .frame(minWidth: lastTimeWidth, alignment: .leading)
        valueField(.weight, suffix: unit.abbreviation)
        valueField(.reps, suffix: "reps")
        logButton
      }
    }
  }

  /// What the row earned, and whether what it shows is saved, under the values.
  @ViewBuilder private var rowNotes: some View {
    if !records.isEmpty {
      // Names what was beaten, so the trophy is a checkable claim. In the record colour, which is
      // tested as text, and never colour alone: the words say what the colour means.
      VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
        Text(recordText)
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.record)
          .lineLimit(2)
        if let certainty = estimateCertainty {
          // How sure the estimated record is, in a glyph and a word. Not a button: the row's taps
          // belong to logging, so the explanation is the row's named action instead.
          HStack(spacing: Tokens.Spacing.tight) {
            Image(systemName: certainty.mark.symbolName)
            Text(certainty.mark.shortWord)
          }
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.certainty(certainty))
        }
      }
      .padding(.leading, ordinalWidth + Tokens.Spacing.regular)
    }
    if isEditingSaved {
      // The pad holds a correction the store has not accepted yet. Said in words, so an unsaved
      // value beside a check mark is never mistaken for the saved set.
      Text("Not saved yet")
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.caution)
        .padding(.leading, ordinalWidth + Tokens.Spacing.regular)
    }
  }

  /// "Heaviest weight: 105 kg, up from 100 kg", one per record.
  private var recordText: String {
    records.map { RecordCopy.line(for: $0, formatter: formatter) }.joined(separator: " · ")
  }

  /// The row's trophy (spec 2.5): the app's one celebration, kept on the row that earned it.
  ///
  /// Always in the hierarchy, at no width and invisible while the row has no record. A symbol
  /// effect plays when its value changes, and an image inserted in the same update as the change
  /// has no earlier value to change from, so a trophy that only appeared with its record could
  /// never bounce.
  private var trophy: some View {
    Image(systemName: "trophy.fill")
      .font(Tokens.Text.label)
      .foregroundStyle(Tokens.Color.record)
      // Inside the bounce on purpose. This removes the effects a view inherits, so placed after
      // `.symbolEffect` it would leave the bounce playing under Reduce Motion.
      .symbolEffectsRemoved(reduceMotion)
      .symbolEffect(.bounce, value: recordPulse)  // gated by symbolEffectsRemoved(reduceMotion)
      .padding(.trailing, records.isEmpty ? 0 : Tokens.Spacing.hairline)
      .frame(width: records.isEmpty ? 0 : nil)
      .opacity(records.isEmpty ? 0 : 1)
      .accessibilityHidden(true)
  }

  private var ordinalBadge: some View {
    Text(isWarmup ? "W" : String(ordinal + 1))
      .font(Tokens.Text.label.weight(.semibold))
      .monospacedDigit()
      .foregroundStyle(isWarmup ? Tokens.Color.textSecondary : Tokens.Color.textPrimary)
      .frame(width: ordinalWidth)
  }

  /// "Last time" as a column beside the fields.
  private var lastTimeColumn: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
      Text("Last time")
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.textSecondary)
      Text(previousDescription)
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.textSecondary)
        .monospacedDigit()
      priorNoteText
    }
  }

  /// "Last time" as one line, under the active row's fields.
  private var lastTimeLine: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
      Text("Last time \(previousDescription)")
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.textSecondary)
        .monospacedDigit()
      priorNoteText
    }
  }

  @ViewBuilder private var priorNoteText: some View {
    if let priorNote {
      // An assumption the user should be able to see, not a number presented as fact.
      Text(priorNote)
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.caveat)
    }
  }

  private func valueField(_ field: SetRowField, suffix: String) -> some View {
    let shown = value(field)
    // On the active row the reps field is as wide as its digits (at least one key wide), so the
    // hero weight beside it takes the rest of the row.
    let hugsContent = emphasis == .active && field == .reps
    return Button {
      onFocus(field)
    } label: {
      HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.tight) {
        // An empty field shows an em dash, never "0" — a zero on screen reads as a value.
        Text(shown ?? "—")
          .font(valueFont(field))
          .foregroundStyle(shown == nil ? Tokens.Color.textSecondary : Tokens.Color.textPrimary)
          // Kilograms fit in four characters; pounds need six ("132.28"), and the field wrapped
          // mid-number onto a second line. Shrinking beats wrapping for a value read at a glance
          // between sets.
          .lineLimit(1)
          .minimumScaleFactor(0.6)
        Text(suffix)
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.textSecondary)
      }
      .frame(
        minWidth: hugsContent ? loggerTarget : nil,
        maxWidth: .infinity,
        minHeight: controlHeight
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .fixedSize(horizontal: hugsContent, vertical: false)
    // Editing a logged set changed only the in-memory draft, never the database, so the row showed
    // a check mark beside an unsaved value. Logged rows stay read-only here: a correction goes
    // through Edit, which writes only on Save (spec 2.3).
    .disabled(isLogged)
    .background(
      Tokens.Color.background,
      in: RoundedRectangle(cornerRadius: Tokens.Radius.control)
    )
    .overlay {
      if focusedField == field {
        RoundedRectangle(cornerRadius: Tokens.Radius.control)
          .strokeBorder(Tokens.Color.accent, lineWidth: 2)
      }
    }
  }

  private var logButton: some View {
    Button(action: onLog) {
      HStack(spacing: 0) {
        // Beside the check, inside its fixed column, so a row with a trophy lines up with the rest.
        trophy
        Image(systemName: isLogged ? "checkmark.circle.fill" : "circle")
          .font(.title2)
          // The check swaps as a symbol, and only inside the gated animation below.
          .contentTransition(.symbolEffect(.replace))  // animates only via quick(reduceMotion)
          .animation(Tokens.Motion.quick(reduceMotion), value: isLogged)
      }
      // The width stays fixed so the value columns line up between compact and full rows.
      .frame(width: loggerTarget, height: controlHeight)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(isLogged ? Tokens.Color.success : Tokens.Color.accent)
    // The same predicate the store enforces. There is no second definition of "complete".
    .disabled(!draft.isLoggable)
    .opacity(draft.isLoggable || isLogged ? 1 : 0.35)
    // No haptic here. `SessionView` plays one per log, from the coordinator's pulse, after the
    // write: a distinct one for a record and a quiet one otherwise (spec 2.6).
  }

  // MARK: - Values

  /// What a field shows, or `nil` when it is empty.
  ///
  /// While the pad is on this row, its text: what is being typed, exactly as typed, with the
  /// locale's decimal separator. Otherwise the draft, through the one weight formatter, so a 60 kg
  /// set reads "132.28" in pounds and never the raw conversion.
  private func value(_ field: SetRowField) -> String? {
    if let keypad {
      let buffer = field == .weight ? keypad.weight : keypad.reps
      guard !buffer.isEmpty else { return nil }
      return buffer.displayText(locale: .current)
    }
    switch field {
    case .weight: return draft.weightKg.map { formatter.number(kilograms: $0) }
    case .reps: return draft.reps.map { String($0) }
    }
  }

  /// The field the pad is typing into, in the row's own terms.
  private var focusedField: SetRowField? {
    keypad.map { $0.field == .weight ? SetRowField.weight : SetRowField.reps }
  }

  private func valueFont(_ field: SetRowField) -> Font {
    switch emphasis {
    case .active: field == .weight ? Tokens.Text.hero : Tokens.Text.setEntry
    case .upcoming: Tokens.Text.setEntry
    case .logged: Tokens.Text.label
    }
  }

  /// A logged row is compact: its fields are read-only, so they keep only the system's 44 pt
  /// floor instead of the logger's 56.
  private var controlHeight: CGFloat {
    emphasis == .logged ? minimumTarget : loggerTarget
  }

  private var formatter: WeightFormatter { WeightFormatter(unit: unit) }

  private var previousDescription: String {
    guard let previous else { return "—" }
    return "\(formatter.load(kilograms: previous.weightKg)) × \(previous.reps)"
  }

  /// The weakest certainty among this row's estimated records, or `nil` when none is estimated.
  private var estimateCertainty: Certainty? {
    records.compactMap(\.estimateCertainty).min()
  }

  /// What VoiceOver reads after the label, in Core's words, with units in full.
  private var spokenValue: String {
    // While the pad is open its draft is what the row shows: the same value as the row's draft,
    // except during a correction, which stays in the pad until Save.
    let shown = keypad?.draft ?? draft
    var parts = [
      SetRowSpeech.value(
        weightKg: shown.weightKg, reps: shown.reps, isLogged: isLogged, formatter: formatter)
    ]
    if let lastTime = SetRowSpeech.previous(previous, formatter: formatter) {
      parts.append(lastTime)
    }
    if let priorNote { parts.append(priorNote) }
    // The record in spoken units ("105 kilograms"), not the caption's "105 kg".
    if let record = RecordCopy.announcement(
      for: records, exerciseName: exerciseName.isEmpty ? "this set" : exerciseName,
      formatter: formatter)
    {
      parts.append(record)
    }
    if let certainty = estimateCertainty { parts.append(certainty.mark.word) }
    if isEditingSaved { parts.append("not saved yet") }
    return parts.joined(separator: ", ")
  }
}

#if DEBUG
  #Preview("Set rows") {
    struct Harness: View {
      @State private var suggested = SetEntryDraft(
        suggestion: PriorSetRecord(weightKg: 100, reps: 8, completedAt: .distantPast)
      )
      @State private var blank = SetEntryDraft(suggestion: nil)

      var body: some View {
        VStack(spacing: Tokens.Spacing.snug) {
          // Prefilled from history: loggable immediately, one tap. The current set, so its
          // weight is the hero.
          SetRowView(
            draft: suggested,
            ordinal: 0,
            unit: .kilograms,
            previous: PriorSetRecord(weightKg: 100, reps: 8, completedAt: .distantPast),
            emphasis: .active,
            onFocus: { _ in },
            onLog: {}
          )
          // No history: genuinely empty, and the log control is disabled rather than
          // silently writing zero.
          SetRowView(draft: blank, ordinal: 1, unit: .kilograms, onFocus: { _ in }, onLog: {})
        }
        .padding()
        .background(Tokens.Color.background)
      }
    }
    return Harness()
  }
#endif
