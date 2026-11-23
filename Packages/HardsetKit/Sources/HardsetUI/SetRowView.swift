import HardsetCore
import SwiftUI

/// Which value a row is editing. `nil` means the row is idle.
public enum SetRowField: Hashable, Sendable {
  case weight
  case reps
}

/// One set, ready to log in a single tap.
///
/// Three rules this view exists to hold:
///
/// 1. **The prefill is a committed value, never placeholder text.** The reference app put last
///    session's numbers in `TextField(prompt:)`, so a row that visibly read "60" reported an
///    empty field and logged 0 kg. Here the suggestion is written into the draft and the keypad is
///    seeded from it, and the "Last time" column is rendered *outside* the fields — so what looks
///    filled is filled, and what is only a hint cannot be mistaken for one.
/// 2. **The log control cannot fire on an incomplete row.** It is bound to
///    `SetEntryDraft.isLoggable`, which is the same predicate `LoggerStore.logSet` enforces. A
///    disagreement between them is impossible because there is only one predicate.
/// 3. **The row is one accessibility element.** A 40-set session with five separately focusable
///    controls per row costs roughly 280 VoiceOver swipes to review. The row reads as a
///    sentence and exposes its actions as named custom actions instead.
///
/// The row does not own a keypad. Each row used to present its own, so a tap on another row's
/// field while one was up highlighted that row and kept typing into the first: digits went into a
/// set the lifter was not looking at. `SessionView` hosts the only keypad and tells the row which
/// field it is editing; the row reports taps with `onBeginEditing`.
///
/// Two layouts, chosen from Dynamic Type rather than by shrinking text: a single line of columns
/// at ordinary sizes, and a stack at accessibility sizes, where the values take the full width and
/// carry their own labels.
///
/// The figures are the content. Weight and reps are the largest text on the card, at `figureXL`
/// (44 pt) in a 64 pt row, set against a quiet multiply sign; the ordinal and last time are small and
/// dim; nothing is boxed, tinted or outlined, and a hairline exists only between rows. They are
/// numbers the lifter typed, so they are measurements and earn the size; an estimate on the same
/// screen is never drawn this large.
///
/// A row that carries its own labels (`showsInlineLabels`) has no column header to name its
/// columns and puts a unit beside each figure, which the 44 pt figures leave no room for on a
/// narrow host such as a pitch page. It keeps the compact `readout` size and 56 pt row it always
/// had.
public struct SetRowView: View {
  @Binding private var draft: SetEntryDraft
  @State private var adjustmentFeedback = 0

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private let ordinal: Int
  private let isWarmup: Bool
  private let isLogged: Bool
  private let isNext: Bool
  private let accentOverride: Bool?
  private let allowsCorrection: Bool
  private let isSeparated: Bool
  private let showsInlineLabels: Bool
  private let unit: WeightUnit
  private let machineIncrementKg: Double?
  private let previous: PriorSetRecord?
  private let priorNote: String?
  private let comparison: SetComparison?
  private let editingField: SetRowField?
  private let editingText: String?
  private let onLog: () -> Void
  private let onBeginEditing: ((SetRowField) -> Void)?
  private let onUndo: (() -> Void)?
  private let onEdit: (() -> Void)?
  private let onRemove: (() -> Void)?

  /// - Parameter isNext: The first unlogged set of its exercise. Its log control is filled rather
  ///   than outlined, so the eye lands on the one tap that matters between sets.
  /// - Parameter accentOverride: Whether this row's log control is drawn in plate blue, the screen's
  ///   one accent, when the set can be logged. `nil` leaves it to the row: the accent is on the next
  ///   row up. A host with several movements decides for them, because the accent belongs to the
  ///   workout's next loggable set wherever that row sits, and a warm-up with nothing in it is next
  ///   up without being loggable. It changes colour only: `isNext` still drives the spoken "next to
  ///   log", the bare Voice Control command and the −/+ steps.
  /// - Parameter allowsCorrection: Lets a saved row's figures open the keypad, so a wrong weight or
  ///   rep count is corrected where it is written. The host decides what a correction does and
  ///   whether it can; without it a saved figure is plain text, as it was.
  /// - Parameter isSeparated: Draws a hairline across the top of the row, inset from the leading
  ///   edge, because it meets another row there. The first row of a movement passes `false`, so a
  ///   hairline exists only where two rows meet.
  /// - Parameter showsInlineLabels: Draws "Last time" and the unit inside the row. A caller that
  ///   draws a column header above its rows passes `false`; accessibility sizes always show them,
  ///   because the stacked layout has no columns for a header to label.
  /// - Parameter comparison: How a logged set compares with the same set last time on this machine,
  ///   drawn as a small mark under the row: "+1 rep", "+2.5 kg · +1 rep", or "Matched". `nil` draws
  ///   nothing, which is the answer for a set that fell short, has no partner, or is a warm-up.
  /// - Parameter editingField: The field the keypad is on, drawn with a caret and an underline.
  ///   `nil` when the keypad is elsewhere or closed.
  /// - Parameter editingText: What has been typed into that field so far, exactly as typed, so
  ///   "100." reads "100." mid-entry rather than a reformatted number.
  /// - Parameter onBeginEditing: Asks the host to put its keypad on a field. `nil` leaves the
  ///   fields as read-only figures.
  /// - Parameter onUndo: Returns a logged set to unlogged, keeping its numbers. Offered from the
  ///   row's context menu and as a named VoiceOver action.
  /// - Parameter onEdit: Undoes a logged set and opens the keypad on it, so a wrong number is
  ///   corrected and logged again.
  /// - Parameter onRemove: Removes an unlogged row. A logged row is undone first; it is never
  ///   removed in one step.
  public init(
    draft: Binding<SetEntryDraft>,
    ordinal: Int,
    isWarmup: Bool = false,
    isLogged: Bool = false,
    isNext: Bool = false,
    accentOverride: Bool? = nil,
    allowsCorrection: Bool = false,
    isSeparated: Bool = false,
    showsInlineLabels: Bool = true,
    unit: WeightUnit,
    machineIncrementKg: Double? = nil,
    previous: PriorSetRecord? = nil,
    priorNote: String? = nil,
    comparison: SetComparison? = nil,
    editingField: SetRowField? = nil,
    editingText: String? = nil,
    onLog: @escaping () -> Void,
    onBeginEditing: ((SetRowField) -> Void)? = nil,
    onUndo: (() -> Void)? = nil,
    onEdit: (() -> Void)? = nil,
    onRemove: (() -> Void)? = nil
  ) {
    self._draft = draft
    self.ordinal = ordinal
    self.isWarmup = isWarmup
    self.isLogged = isLogged
    self.isNext = isNext
    self.accentOverride = accentOverride
    self.allowsCorrection = allowsCorrection
    self.isSeparated = isSeparated
    self.showsInlineLabels = showsInlineLabels
    self.unit = unit
    self.machineIncrementKg = machineIncrementKg
    self.previous = previous
    self.priorNote = priorNote
    self.comparison = comparison
    self.editingField = editingField
    self.editingText = editingText
    self.onLog = onLog
    self.onBeginEditing = onBeginEditing
    self.onUndo = onUndo
    self.onEdit = onEdit
    self.onRemove = onRemove
  }

  /// True at accessibility text sizes, where five columns cannot share one line legibly.
  private var isStacked: Bool { dynamicTypeSize.isAccessibilitySize }

  /// The role the weight and reps are drawn in. See the type's documentation for the compact case.
  private var figureRole: Tokens.Text.Role { showsInlineLabels ? .readout : .figureXL }

  /// The height of the row's tap regions: 64 pt for the 44 pt figures, 56 pt for the compact row.
  private var regionHeight: CGFloat {
    showsInlineLabels ? Tokens.loggerTapTarget : SetRowMetrics.rowHeight
  }

  /// Whether the figures take a tap. An unsaved row's always do, with a host to open the keypad; a
  /// saved row's do only where the host can write a correction.
  private var canEditFigures: Bool {
    onBeginEditing != nil && (!isLogged || allowsCorrection)
  }

  public var body: some View {
    Group {
      if isStacked {
        VStack(spacing: Tokens.Spacing.snug) {
          stackedLayout
          targetOrBeatMark
          inlineAdjusters
        }
      } else {
        VStack(spacing: Tokens.Spacing.snug) {
          rowLayout
          targetOrBeatMark
          inlineAdjusters
        }
      }
    }
    .padding(.vertical, Tokens.Spacing.tight)
    // No fill and no tint: a row is its figures. Logging used to wash the whole row green so a
    // glance down the card showed what was done; now the saved figures go to full chalk and the
    // check fills, which says the same thing without turning the list into a spreadsheet with
    // conditional formatting. Only the hairline above a row, where it meets the row before, draws.
    .overlay(alignment: .top) {
      if isSeparated {
        Rectangle()
          .fill(Tokens.Color.hairline)
          .frame(height: Tokens.Stroke.hairline)
          .padding(.leading, SetRowMetrics.ordinalWidth + Tokens.Spacing.snug)
          .accessibilityHidden(true)
      }
    }
    // With nothing painted behind it the row would be hit-testable only where it draws, so a long
    // press in a gap between columns would find no menu. The whole row is the interaction shape.
    .contentShape(.interaction, Rectangle())
    // Corrections live behind a long press, the iOS convention for acting on one item in place:
    // deliberate enough that a hurried tap on the check can never undo or remove a set.
    // The preview shape is iOS-only; the macOS host build (tests only) uses the default.
    #if os(iOS)
      .contentShape(.contextMenuPreview, Tokens.Shape.control)
    #endif
    .contextMenu { corrections }
    .sensoryFeedback(Tokens.Haptic.selection, trigger: adjustmentFeedback)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(spokenLabel)
    .accessibilityHint(accessibilityHint)
    // Voice Control speaks what it can name. The row's check has no words on it, so "Tap Log set"
    // found nothing; these names reach the row's default action, which logs a complete set.
    .accessibilityInputLabels(voiceControlNames)
    // The default activation does what the hint says. Combining the row's buttons left
    // double-tap to whichever child VoiceOver chose -- in practice the weight field.
    .accessibilityAction {
      guard !isLogged else { return }
      if draft.isLoggable {
        onLog()
      } else {
        onBeginEditing?(.weight)
      }
    }
    .accessibilityActions {
      if isLogged {
        if let onEdit { Button("Edit set", action: onEdit) }
        if canEditFigures, let onBeginEditing {
          Button("Edit weight") { onBeginEditing(.weight) }
          Button("Edit reps") { onBeginEditing(.reps) }
        }
        if let onUndo { Button("Undo log", action: onUndo) }
      } else {
        Button("Log set") { if draft.isLoggable { onLog() } }
        if let onBeginEditing {
          Button("Edit weight") { onBeginEditing(.weight) }
          Button("Edit reps") { onBeginEditing(.reps) }
        }
        if let step = machineIncrementKg, step.isFinite, step > 0 {
          Button("Increase load by one machine step") { adjustLoad(by: step) }
          Button("Decrease load by one machine step") { adjustLoad(by: -step) }
        }
        if let onRemove { Button("Remove set", action: onRemove) }
      }
    }
  }

  /// What a long press offers. A logged set can be undone, or undone and opened for editing; an
  /// unlogged row can be removed. Nothing here deletes a saved set in one step.
  @ViewBuilder private var corrections: some View {
    if isLogged {
      if let onEdit {
        Button(action: onEdit) {
          Label("Edit set", systemImage: "pencil")
        }
      }
      if let onUndo {
        Button(action: onUndo) {
          Label("Undo log", systemImage: "arrow.uturn.backward")
        }
      }
    } else if let onRemove {
      Button(role: .destructive, action: onRemove) {
        Label("Remove set", systemImage: "trash")
      }
    }
  }

  private var accessibilityHint: String {
    if isLogged {
      return onUndo == nil ? "This set is saved." : "This set is saved. Actions can undo or edit it."
    }
    if draft.isLoggable { return "Double tap to log this set." }
    return onBeginEditing == nil ? "Enter a weight and reps to log." : "Double tap to enter a weight."
  }

  // MARK: - Layouts

  /// Ordinary sizes: ordinal, last time, weight and reps, log, on one line aligned to the column
  /// header `ExerciseSectionView` draws above.
  ///
  /// The figures are the content. Weight ends at the multiply sign and reps begin after it, so the
  /// sign is one vertical axis down the list and the figures read as a pair. The ordinal and last
  /// time are small and dim in fixed columns; tapping them opens the weight, so no part of the row
  /// between its two edges is dead.
  private var rowLayout: some View {
    HStack(spacing: Tokens.Spacing.snug) {
      leadingColumns

      HStack(alignment: .firstTextBaseline, spacing: 0) {
        valueField(.weight, suffix: showsInlineLabels ? unit.abbreviation : nil, alignment: .trailing)
        multiplySign
        // Reps sit in a fixed column and the weight takes the rest. Weight is the wider figure,
        // "227.5" against "12", and an equal split gave it less room than it needed at 44 pt. The
        // multiply sign is still one axis down the list because the column is the same width in
        // every row, and the column header draws the same one.
        valueField(.reps, suffix: showsInlineLabels ? "reps" : nil, alignment: .leading)
          .frame(width: showsInlineLabels ? nil : SetRowMetrics.repsWidth)
      }

      logButton
    }
  }

  /// The ordinal and last time. A button into the weight whenever the weight can be edited, so the
  /// 56 pt row answers a tap anywhere left of the check; plain text otherwise, for a saved row.
  @ViewBuilder private var leadingColumns: some View {
    let columns = HStack(spacing: Tokens.Spacing.snug) {
      ordinalLabel
        .frame(width: SetRowMetrics.ordinalWidth, alignment: .leading)
      previousColumn
        .frame(width: SetRowMetrics.previousWidth, alignment: .leading)
    }
    .frame(minHeight: regionHeight)
    .contentShape(Rectangle())
    if !canEditFigures {
      columns
    } else {
      Button {
        onBeginEditing?(.weight)
      } label: {
        columns
      }
      .buttonStyle(HardsetPressStyle())
    }
  }

  /// The multiply sign between weight and reps: quieter than the figures it joins, in size and in
  /// weight, but still `chalkDim`, which clears 7:1. Decoration, so VoiceOver does not read it.
  private var multiplySign: some View {
    Text("×")
      .hardsetText(.provenance)
      .foregroundStyle(Tokens.Color.chalkDim)
      .frame(width: SetRowMetrics.multiplyWidth)
      .accessibilityHidden(true)
  }

  /// Accessibility sizes: a header line with the ordinal and last time, then the two values at
  /// full width with their units, then the log control at full width.
  private var stackedLayout: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.regular) {
        ordinalLabel
        previousColumn
      }
      valueField(.weight, suffix: unit.abbreviation, alignment: .leading)
      valueField(.reps, suffix: "reps", alignment: .leading)
      logButton
    }
    .padding(.vertical, Tokens.Spacing.tight)
  }

  /// Where the line under the columns starts: under the last-time column at ordinary sizes, since
  /// both speak about last time, and at the edge when the layout is stacked.
  private var markInset: CGFloat {
    isStacked ? 0 : SetRowMetrics.ordinalWidth + Tokens.Spacing.snug
  }

  /// Under the columns, one of two lines and never both. An unlogged row prefilled from a rep range
  /// says where its numbers came from, in the words of the rule, so a target is never read as
  /// history. A logged row says how it compares with last time, if it does.
  @ViewBuilder private var targetOrBeatMark: some View {
    if !isLogged, let target = draft.target {
      Text("Target · \(target.explanation)")
        .hardsetText(.provenance)
        .foregroundStyle(Tokens.Color.chalkDim)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, markInset)
    } else if isLogged, let comparison {
      beatMark(comparison)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, markInset)
    }
  }

  /// A short mark, not a control and not a badge: a symbol and the figures of the set, in type, on
  /// nothing. It names what grew, "+1 rep", "+2.5 kg · +1 rep", or says "Matched". A win is `chalk`
  /// with an up arrow and a match is `chalkDim` with an equals sign: the arrow and the words carry
  /// the difference, and no hue does, because green on the screen means a set is saved. It arrives
  /// with the standard reveal, so the row's height changes at once and nothing animates layout.
  private func beatMark(_ comparison: SetComparison) -> some View {
    let isMatch = comparison == .matched
    return HStack(spacing: Tokens.Spacing.tight) {
      Image(systemName: isMatch ? "equal" : "arrow.up")
        .accessibilityHidden(true)
      Text(comparison.label(in: unit))
    }
    .hardsetText(.caption, weight: .semibold)
    .monospacedDigit()
    .foregroundStyle(isMatch ? Tokens.Color.chalkDim : Tokens.Color.chalk)
    .hardsetArrival()
  }

  /// The −/+ machine-step pair, on the next set up and on a row being edited only.
  ///
  /// Drawn under every unlogged row, the pair nearly doubled a card's height and put a
  /// neighbouring row's adjuster under the thumb. Every row keeps the same steps as named
  /// VoiceOver actions.
  @ViewBuilder private var inlineAdjusters: some View {
    if !isLogged, isNext || editingField != nil,
      let step = machineIncrementKg, step.isFinite, step > 0
    {
      ViewThatFits(in: .horizontal) {
        HStack(spacing: Tokens.Spacing.snug) {
          loadAdjustment(-step)
          loadAdjustment(step)
        }
        VStack(spacing: Tokens.Spacing.snug) {
          loadAdjustment(-step)
          loadAdjustment(step)
        }
      }
    }
  }

  /// Labelled with the same figure the machine chip shows, so one machine step reads as one
  /// number on the card.
  private func loadAdjustment(_ delta: Double) -> some View {
    let step = LoadFigure.text(unit.fromKilograms(abs(delta)))
    let label = "\(delta < 0 ? "−" : "+")\(step) \(unit.abbreviation)"
    return Button {
      adjustLoad(by: delta)
    } label: {
      Text(label)
        .font(Tokens.Text.figure)
        .foregroundStyle(Tokens.Color.chalk)
    }
    // A step is a line of type in a 56 pt region, like every other logger action with no face of
    // its own; it dims when there is no load to step from.
    .buttonStyle(
      InlineControlStyle(
        minHeight: Tokens.loggerTapTarget, alignment: .center, fullWidth: true,
        dimsWhenDisabled: true)
    )
    .disabled(draft.weightKg == nil || (delta < 0 && draft.weightKg == 0))
    .accessibilityLabel("\(delta < 0 ? "Decrease" : "Increase") load by \(step) \(unit.abbreviation)")
  }

  /// Writes canonical kilograms to the draft. A keypad open on this row is reseeded by its host
  /// when the draft changes underneath it.
  private func adjustLoad(by delta: Double) {
    guard !isLogged, let current = draft.weightKg else { return }
    let updated = max(0, current + delta)
    guard updated.isFinite, updated != current else { return }
    adjustmentFeedback += 1
    draft.weightKg = updated
  }

  // MARK: - Pieces

  /// Working sets are numbered; a warm-up reads "W". Small and dim, a label for the row and not a
  /// figure in it, with no tile behind it: the letter alone says a warm-up is not counted. At
  /// accessibility sizes it is spelled out, "Set 2", which is also what Voice Control is told.
  private var ordinalLabel: some View {
    let word = isWarmup ? "W" : String(ordinal + 1)
    return Text(isStacked ? (isWarmup ? "Warm-up" : "Set \(ordinal + 1)") : word)
      .hardsetText(.caption, weight: .medium)
      .monospacedDigit()
      .foregroundStyle(Tokens.Color.chalkDim)
  }

  /// Last time's set as a logbook would write it: the load, and the reps beneath it. Two short
  /// lines rather than one long one, so the column stays narrow enough for both entry fields to
  /// keep their size on a 375 pt phone.
  private var previousColumn: some View {
    VStack(alignment: .leading, spacing: 0) {
      if showsInlineLabels || isStacked {
        Text("Last time")
          .hardsetText(.caption)
          .foregroundStyle(Tokens.Color.chalkDim)
          .padding(.bottom, Tokens.Spacing.hairline)
      }
      if let previous {
        Text(LoadFigure.text(unit.fromKilograms(previous.weightKg)))
          .font(Tokens.Text.unit)
          .monospacedDigit()
          .foregroundStyle(Tokens.Color.chalkDim)
          .lineLimit(1)
          // The one value allowed to give a little: it is a hint, read second, and a long pound
          // figure must not push the fields the lifter types into off the row.
          .minimumScaleFactor(0.8)
        Text("× \(previous.reps)")
          .hardsetText(.caption)
          .monospacedDigit()
          .foregroundStyle(Tokens.Color.chalkDim)
          .lineLimit(1)
      } else {
        Text("—")
          .font(Tokens.Text.unit)
          .foregroundStyle(Tokens.Color.chalkDim)
      }
      if let priorNote {
        // An assumption the user should be able to see, not a number presented as fact.
        Text(priorNote)
          .font(Tokens.Text.provenance)
          .foregroundStyle(Tokens.Color.certainty(.low))
      }
    }
  }

  /// The figure a field shows: what is being typed while the keypad is on it, otherwise the
  /// draft, in the display unit, written the way the keypad writes it. `nil` means empty.
  private func displayText(_ field: SetRowField) -> String? {
    if editingField == field, let editingText {
      return editingText.isEmpty ? nil : LoadFigure.typed(editingText)
    }
    switch field {
    case .weight: return draft.weightKg.map { LoadFigure.text(unit.fromKilograms($0)) }
    case .reps: return draft.reps.map { String($0) }
    }
  }

  /// A value is plain text, with no box around it: dimmed until the set is logged, full chalk once
  /// it is saved, and carrying a caret and an underline while the keypad is typing into it. The
  /// whole field stays a 56 pt target, so removing the box removed nothing to tap.
  private func valueField(
    _ field: SetRowField, suffix: String?, alignment: Alignment = .center
  ) -> some View {
    let isEditing = editingField == field
    let isReadOnly = !canEditFigures
    let shown: SetRowFieldState = isEditing ? .editing : (isReadOnly ? .readOnly : .rest)
    return Button {
      onBeginEditing?(field)
    } label: {
      SetRowFieldValue(
        text: displayText(field), suffix: suffix, state: shown, isLogged: isLogged,
        alignment: alignment, role: figureRole, minHeight: regionHeight)
    }
    // Presses dim and sink through the field's own style: with no face to darken, the figure
    // itself takes the press, as every control that draws no fill of its own does.
    .buttonStyle(SetFieldStyle(isEditing: isEditing, isReadOnly: isReadOnly))
    .disabled(isReadOnly)
  }

  /// The one tap the whole logger is built around.
  ///
  /// Four states, each drawn differently so none is mistaken for another: incomplete (an empty
  /// square, and disabled), ready (a checked square), next up (a square filled with plate blue), and
  /// logged (the plate-green seal). The stamp is the app's one spring; with Reduce Motion it simply
  /// appears.
  ///
  /// Logged and next up differ in shape, not only in hue. Both used to be a filled square with the
  /// same check, about 1.1:1 apart in luminance, so in glare or with a colour-vision deficiency a
  /// set waiting to be logged looked saved. A square means "tap to log"; a logged set is a round
  /// seal, which nothing tappable in the logger uses. At accessibility sizes the control also says
  /// which it is in words.
  ///
  /// `SetLogControlFace` draws the whole control, so the live button and the catalogue's forced
  /// states cannot drift. The button's own label is never drawn.
  private var logButton: some View {
    Button(action: onLog) {
      EmptyView()
    }
    .buttonStyle(
      SetReadoutStyle(state: logState, regionHeight: isStacked ? Tokens.loggerTapTarget : regionHeight))
    // The same predicate the store enforces. There is no second definition of "complete".
    .disabled(!draft.isLoggable || isLogged)
    .accessibilityLabel(isLogged ? "Logged" : "Log set")
    // Haptics confirm the tap landed without the user looking at the phone.
    .sensoryFeedback(Tokens.Haptic.success, trigger: isLogged) { !$0 && $1 }
    // The weight of the plate going down, as the set is saved: the clank under the success. Only on
    // the saved transition, so a failed write, which never marks the row logged, stays silent.
    .onChange(of: isLogged) { old, new in
      if !old && new { ClankPlayer.shared.play() }
    }
    // The tour points at the check of the first set still to log.
    .tourTarget(.logCheck, isActive: isNext && !isLogged)
  }

  private var logState: SetLogState {
    if isLogged { return .logged }
    if draft.isLoggable { return accentOverride ?? isNext ? .nextUp : .ready }
    return .incomplete
  }

  private var spokenLabel: String {
    var parts: [String] = [isWarmup ? "Warm-up set" : "Set \(ordinal + 1)"]
    // Each half is spoken on its own. A row with a weight and no reps used to be read as "no
    // values entered" while its field visibly showed the weight.
    let weight = draft.weightKg.map { "\(LoadFigure.text(unit.fromKilograms($0))) \(unit.abbreviation)" }
    let reps = draft.reps.map { $0 == 1 ? "1 rep" : "\($0) reps" }
    switch (weight, reps) {
    case let (weight?, reps?): parts.append("\(weight), \(reps)")
    case let (weight?, nil): parts.append("\(weight), reps not entered")
    case let (nil, reps?): parts.append("weight not entered, \(reps)")
    case (nil, nil): parts.append("no values entered")
    }
    if let previous {
      parts.append(
        "last time \(LoadFigure.text(unit.fromKilograms(previous.weightKg))) \(unit.abbreviation) for \(previous.reps)"
      )
    }
    if let priorNote { parts.append(priorNote) }
    // What the numbers came from, or how they went, said once and in the same words as the mark.
    if !isLogged, let target = draft.target { parts.append(target.spokenLabel(in: unit)) }
    if isLogged, let comparison { parts.append(comparison.spokenLabel(in: unit)) }
    if isLogged {
      parts.append("logged")
    } else if isNext {
      // The filled check says this to the eye; VoiceOver says it too.
      parts.append("next to log")
    }
    return parts.joined(separator: ", ")
  }

  /// What Voice Control can call the row. The first is the name "Show names" displays.
  private var voiceControlNames: [String] {
    let name = isWarmup ? "Warm-up set" : "Set \(ordinal + 1)"
    var names = [name]
    if !isLogged {
      names.append(isWarmup ? "Log warm-up set" : "Log set \(ordinal + 1)")
      // The one row the filled check marks also answers to the bare command.
      if isNext { names += ["Log set", "Log"] }
    }
    return names
  }
}

/// `sheet(item:)` needs an `Identifiable`; `SetRowField` is a value with no natural id.
extension SetRowField: Identifiable {
  public var id: Self { self }
}

#if DEBUG
  #Preview("Set rows") {
    struct Harness: View {
      @State private var suggested = SetEntryDraft(
        suggestion: PriorSetRecord(weightKg: 100, reps: 8, completedAt: .distantPast)
      )
      @State private var next = SetEntryDraft(
        suggestion: PriorSetRecord(weightKg: 105, reps: 6, completedAt: .distantPast)
      )
      @State private var blank = SetEntryDraft(suggestion: nil)

      var body: some View {
        VStack(spacing: Tokens.Spacing.snug) {
          // Logged: the plate-green seal, and the row takes the logged tint.
          SetRowView(
            draft: $suggested,
            ordinal: 0,
            isLogged: true,
            unit: .kilograms,
            previous: PriorSetRecord(weightKg: 100, reps: 8, completedAt: .distantPast),
            onLog: {},
            onUndo: {},
            onEdit: {}
          )
          // Prefilled from history and next up: loggable immediately, one tap, filled control.
          SetRowView(
            draft: $next,
            ordinal: 1,
            isNext: true,
            unit: .kilograms,
            previous: PriorSetRecord(weightKg: 105, reps: 6, completedAt: .distantPast),
            editingField: .weight,
            editingText: "10",
            onLog: {},
            onBeginEditing: { _ in },
            onRemove: {}
          )
          // No history: genuinely empty, and the log control is disabled rather than
          // silently writing zero.
          SetRowView(draft: $blank, ordinal: 2, unit: .kilograms, onLog: {}, onBeginEditing: { _ in })
        }
        .padding()
        .background(Tokens.Color.canvas)
      }
    }
    return Harness()
  }
#endif


// MARK: - Value fields

/// What a value field is showing: at rest, pressed, under the keypad, or inert. A `ButtonStyle`
/// cannot be forced pressed in a render, so the catalogue passes this to `SetRowFieldFace`
/// directly, and the live style derives it from the row.
enum SetRowFieldState: Sendable {
  case rest
  case pressed
  case editing
  case readOnly
}

/// A value field's content: the figure, or an em dash when empty, and its unit beside it. The live
/// field and the catalogue draw the same view, so a sample cannot drift from the row.
///
/// There is no box. A figure that has not been logged is dimmed to `chalkDim`, which still clears
/// 7:1 on every surface it sits on; a saved figure is full `chalk`. While the keypad types into the
/// field the figure is `chalk`, a caret follows it and a 2 pt rule sits beneath it, and nothing
/// else changes: the keypad is the input surface, so the row never becomes a form. The caret is
/// drawn still. It does not blink, so the field adds no motion.
struct SetRowFieldValue: View {
  let text: String?
  let suffix: String?
  let state: SetRowFieldState
  /// A logged set is saved, so its figures read in full chalk; before that they are only
  /// proposed, and read dimmed.
  let isLogged: Bool
  /// Where the figure sits in its column. A row sets weight against the multiply sign from the
  /// left and reps from the right, so the sign is one axis down the card; the catalogue centres.
  var alignment: Alignment = .center
  /// The figure's role: `figureXL` for a measurement in a full row, `readout` for the compact row.
  var role: Tokens.Text.Role = .figureXL
  /// The field's tap region: 64 pt for the 44 pt figures, 56 pt for the compact row.
  var minHeight: CGFloat = SetRowMetrics.rowHeight

  private var isEditing: Bool { state == .editing }

  /// An empty field shows an em dash, never "0": a zero on screen reads as a value. While typing,
  /// an empty field shows only its caret, so the first digit is plainly the first character.
  private var shown: String {
    if isEditing { return text ?? "" }
    return text ?? "—"
  }

  private var figureColor: Color {
    guard text != nil else { return Tokens.Color.chalkDim }
    return isEditing || isLogged ? Tokens.Color.chalk : Tokens.Color.chalkDim
  }

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.tight) {
      HStack(alignment: .firstTextBaseline, spacing: 0) {
        // The largest thing on the card: the figure role, set tight and tabular, so a column of
        // weights lines up digit under digit.
        Text(shown)
          .hardsetText(role)
          .foregroundStyle(figureColor)
          // Condensed tabular figures at 44 pt fit "227.5" in the weight column of a 402 pt phone,
          // and "132.28" with the floor below. The floor exists only so a long value shrinks a
          // little rather than truncating, as it does on a 375 pt phone: a number cut to "132.…"
          // is worse than one drawn slightly smaller. The compact size keeps its shallower floor.
          .lineLimit(1)
          .minimumScaleFactor(role == .readout ? 0.85 : 0.7)
        if isEditing {
          // The caret is the vertical bar glyph at the figure's own size, so it is as tall as the
          // digits at every Dynamic Type size without a measured frame.
          Text("|")
            .hardsetText(role, weight: .light)
            .foregroundStyle(Tokens.Color.chalk)
            .accessibilityHidden(true)
        }
      }
      .frame(minWidth: isEditing ? Self.minimumRuleWidth : nil)
      .overlay(alignment: .bottom) {
        if isEditing {
          Rectangle()
            .fill(Tokens.Color.chalk)
            .frame(height: Tokens.Stroke.selected)
            .offset(y: Tokens.Spacing.tight)
            .accessibilityHidden(true)
        }
      }
      if let suffix {
        Text(suffix)
          .hardsetText(.unit)
          .foregroundStyle(Tokens.Color.chalkDim)
      }
    }
    .frame(maxWidth: .infinity, minHeight: minHeight, alignment: alignment)
  }

  /// A rule under an empty field would be as wide as its caret; this keeps it a visible line.
  private static let minimumRuleWidth: CGFloat = 32
}

/// A value field's chrome in a given state, which is almost none.
///
/// At rest and read-only the field is its figure and nothing else. Pressed, the figure sinks to
/// 0.97 and dims to 80%, as every control with no fill of its own does, and Reduce Motion drops the
/// scale. Where the lifter has asked for boundaries, through Increase Contrast or Button Shapes, an
/// editable field wears the 3:1 `controlEdge` outline again, so the box comes back exactly where it
/// was requested and nowhere else. A read-only field is never outlined: it is a saved fact, not a
/// control. The hit region is the whole field, a rectangle, because there is no face to define it.
struct SetRowFieldFace<Label: View>: View {
  private let state: SetRowFieldState
  private let reduceMotion: Bool
  private let label: Label

  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.accessibilityShowButtonShapes) private var showsButtonShapes

  init(state: SetRowFieldState, reduceMotion: Bool, @ViewBuilder label: () -> Label) {
    self.state = state
    self.reduceMotion = reduceMotion
    self.label = label()
  }

  var body: some View {
    let request = ControlEdgeRequest(contrast: contrast, showsButtonShapes: showsButtonShapes)
    let isEditable = state != .readOnly
    label
      .overlay {
        if request.isRequested && isEditable {
          Tokens.Shape.control
            .strokeBorder(Tokens.Color.controlEdge, lineWidth: Tokens.Stroke.hairline)
        }
      }
      .contentShape(Rectangle())
      .scaleEffect(state == .pressed && !reduceMotion ? 0.97 : 1)
      .opacity(state == .pressed ? 0.8 : 1)
  }
}

/// The button style of a set-row value field. It feeds the row's editing and read-only flags and
/// `configuration.isPressed` into `SetRowFieldFace` and animates the press through `Motion.press`,
/// which Reduce Motion replaces with an instant swap.
private struct SetFieldStyle: ButtonStyle {
  let isEditing: Bool
  let isReadOnly: Bool

  func makeBody(configuration: ButtonStyleConfiguration) -> some View {
    SetFieldBody(configuration: configuration, isEditing: isEditing, isReadOnly: isReadOnly)
  }
}

private struct SetFieldBody: View {
  let configuration: ButtonStyleConfiguration
  let isEditing: Bool
  let isReadOnly: Bool

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var state: SetRowFieldState {
    if isEditing { return .editing }
    if isReadOnly { return .readOnly }
    return configuration.isPressed ? .pressed : .rest
  }

  var body: some View {
    SetRowFieldFace(state: state, reduceMotion: reduceMotion) {
      configuration.label
    }
    .animation(
      Tokens.Motion.adaptive(Tokens.Motion.press, reduceMotion: reduceMotion),
      value: configuration.isPressed
    )
  }
}

// MARK: - Log control

/// The four states of the set log control. The row derives it from the draft, the logged flag and
/// the next-up flag; the catalogue passes it directly.
enum SetLogState: Sendable {
  case incomplete
  case ready
  case nextUp
  case logged
}

/// The set log control in a given state, drawn whole: one SF Symbol, and at accessibility sizes the
/// words "Log set" or "Logged" beside it. The live button and the catalogue both draw this view, so
/// a forced state cannot drift from what a press shows.
///
/// Four glyphs of one weight and one size, drawn by the system and not by hand. Incomplete is an
/// empty square in `controlEdge`, faint but above the 3:1 floor for a graphic; ready is the same
/// square with its check in `chalkDim`; next up is that square filled with plate blue, the one
/// saturated colour on the screen; logged is a round `plateGreen` seal. A square is a control that
/// logs a set and a circle is a set that is logged, so logged and next up differ in shape and not
/// only in hue: in glare or with a colour-vision deficiency a set waiting to be logged still never
/// looks saved. The glyph is about 30 pt, inside the logger's whole 56 pt region.
///
/// Ready and next up take the opacity press through `HardsetPressFace`; incomplete and logged are
/// disabled, so they ignore `isPressed` and show no press. The stamp is the app's one spring, on
/// the seal and nothing else: it scales in from 0.6 as the unlogged glyph fades out, and with
/// Reduce Motion it simply appears. The glyph's text size stops growing at xxxLarge so it stays
/// inside the region; past that the words beside it carry the state.
struct SetLogControlFace: View {
  private let state: SetLogState
  private let isPressed: Bool
  private let regionHeight: CGFloat

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// - Parameter regionHeight: The control's tap region. It matches the row it sits in, 64 pt for
  ///   the 44 pt figures; the glyph inside stays one size.
  init(state: SetLogState, isPressed: Bool, regionHeight: CGFloat = Tokens.loggerTapTarget) {
    self.state = state
    self.isPressed = isPressed
    self.regionHeight = regionHeight
  }

  private var isStacked: Bool { dynamicTypeSize.isAccessibilitySize }
  private var isLogged: Bool { state == .logged }

  private var isPressable: Bool {
    switch state {
    case .ready, .nextUp: true
    case .incomplete, .logged: false
    }
  }

  /// One weight and one size for every state, so the glyphs differ by shape and fill alone.
  private static let glyphFont = Tokens.Text.readout.weight(.regular)

  var body: some View {
    HardsetPressFace(isPressed: isPressed && isPressable, reduceMotion: reduceMotion) {
      HStack(spacing: Tokens.Spacing.snug) {
        ZStack {
          unloggedGlyph
            .opacity(isLogged ? 0 : 1)
          seal
        }
        // Only the glyphs spring, so nothing is laid out twice and the stamp stays the one moving
        // thing.
        .animation(
          Tokens.Motion.adaptive(Tokens.Motion.stamp, reduceMotion: reduceMotion),
          value: isLogged
        )
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        if isStacked {
          Text(isLogged ? "Logged" : "Log set")
            .font(Tokens.Text.headline)
            .foregroundStyle(isLogged ? Tokens.Color.chalk : labelColor)
        }
      }
      .frame(
        maxWidth: isStacked ? .infinity : Tokens.loggerTapTarget,
        minHeight: regionHeight,
        alignment: isStacked ? .leading : .center
      )
      .frame(width: isStacked ? nil : Tokens.loggerTapTarget)
      .contentShape(Rectangle())
    }
  }

  /// The glyph of a set that is not logged yet: an empty square, a checked square, or a filled
  /// one. All three are the same size, so the control never moves between them.
  private var unloggedGlyph: some View {
    Image(systemName: unloggedSymbol)
      .font(Self.glyphFont)
      .foregroundStyle(unloggedColor)
  }

  private var unloggedSymbol: String {
    switch state {
    case .incomplete: "square"
    case .ready: "checkmark.square"
    case .nextUp, .logged: "checkmark.square.fill"
    }
  }

  private var unloggedColor: Color {
    switch state {
    case .incomplete: Tokens.Color.controlEdge
    case .ready: Tokens.Color.chalkDim
    case .nextUp, .logged: Tokens.Color.plateBlueFill
    }
  }

  /// The logged seal: a round filled check in `plateGreen`. It is always laid out at the control's
  /// square, so the control does not shift when a set is logged, and fades in as one layer.
  private var seal: some View {
    Image(systemName: "checkmark.circle.fill")
      .font(Self.glyphFont)
      .foregroundStyle(Tokens.Color.plateGreen)
      .scaleEffect(isLogged || reduceMotion ? 1 : 0.6)
      .opacity(isLogged ? 1 : 0)
  }

  /// The words beside the glyph at accessibility sizes, in chalk: the colour belongs to the glyph.
  private var labelColor: Color {
    switch state {
    case .incomplete: Tokens.Color.chalkDim
    case .ready, .nextUp, .logged: Tokens.Color.chalk
    }
  }
}

/// The log control's button style. Saved rows retain measured contrast; only actions are
/// disabled, and the incomplete control is drawn faint by its own colour in `SetLogControlFace`.
///
/// Pressed, the check sinks to 0.97 and dims to 80%, as every control that draws its own fill and
/// shape does: the most frequent tap in the app gave no touch-down feedback at all. The press is
/// carried by opacity rather than a second fill. A disabled button never reports a press, so saved
/// rows keep their full contrast. The face draws the whole control and adds no scale or opacity of
/// its own here; this style only animates the press.
private struct SetReadoutStyle: ButtonStyle {
  let state: SetLogState
  let regionHeight: CGFloat

  func makeBody(configuration: ButtonStyleConfiguration) -> some View {
    SetReadoutBody(configuration: configuration, state: state, regionHeight: regionHeight)
  }
}

private struct SetReadoutBody: View {
  let configuration: ButtonStyleConfiguration
  let state: SetLogState
  let regionHeight: CGFloat

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    SetLogControlFace(state: state, isPressed: configuration.isPressed, regionHeight: regionHeight)
      .animation(
        Tokens.Motion.adaptive(Tokens.Motion.press, reduceMotion: reduceMotion),
        value: configuration.isPressed
      )
  }
}
