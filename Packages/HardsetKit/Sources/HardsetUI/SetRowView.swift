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
/// at ordinary sizes, and a stacked card at accessibility sizes, where the values take the full
/// width and carry their own labels.
public struct SetRowView: View {
  @Binding private var draft: SetEntryDraft
  @State private var adjustmentFeedback = 0

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private let ordinal: Int
  private let isWarmup: Bool
  private let isLogged: Bool
  private let isNext: Bool
  private let showsInlineLabels: Bool
  private let unit: WeightUnit
  private let machineIncrementKg: Double?
  private let previous: PriorSetRecord?
  private let priorNote: String?
  private let editingField: SetRowField?
  private let editingText: String?
  private let onLog: () -> Void
  private let onBeginEditing: ((SetRowField) -> Void)?
  private let onUndo: (() -> Void)?
  private let onEdit: (() -> Void)?
  private let onRemove: (() -> Void)?

  /// - Parameter isNext: The first unlogged set of its exercise. Its log control is filled rather
  ///   than outlined, so the eye lands on the one tap that matters between sets.
  /// - Parameter showsInlineLabels: Draws "Last time" and the unit inside the row. A caller that
  ///   draws a column header above its rows passes `false`; accessibility sizes always show them,
  ///   because the stacked layout has no columns for a header to label.
  /// - Parameter editingField: The field the keypad is on, drawn with the focus ring. `nil` when
  ///   the keypad is elsewhere or closed.
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
    showsInlineLabels: Bool = true,
    unit: WeightUnit,
    machineIncrementKg: Double? = nil,
    previous: PriorSetRecord? = nil,
    priorNote: String? = nil,
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
    self.showsInlineLabels = showsInlineLabels
    self.unit = unit
    self.machineIncrementKg = machineIncrementKg
    self.previous = previous
    self.priorNote = priorNote
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

  public var body: some View {
    let shape = RoundedRectangle(cornerRadius: Tokens.Radius.control)
    Group {
      if isStacked {
        VStack(spacing: Tokens.Spacing.snug) {
          stackedLayout
          inlineAdjusters
        }
      } else {
        VStack(spacing: Tokens.Spacing.snug) {
          rowLayout
          inlineAdjusters
        }
      }
    }
    .padding(.horizontal, Tokens.Spacing.tight)
    .padding(.vertical, Tokens.Spacing.tight)
    // Opaque. Dense numeric rows are the one surface glass is actively wrong for. A logged row
    // takes the success tint, so a glance down the card shows what is done without reading.
    //
    // The tint is a layer that fades in place; only its opacity is animated. An animation on the
    // whole row also animated its height when the step buttons left it, so the shrinking tint
    // and the fading buttons were drawn over the next row, which had already moved up.
    .background {
      ZStack {
        shape.fill(Tokens.Color.surface)
        shape.fill(Tokens.Color.successSurface)
          .opacity(isLogged ? 1 : 0)
      }
      .animation(
        Tokens.Motion.adaptive(Tokens.Motion.state, reduceMotion: reduceMotion), value: isLogged
      )
    }
    // Corrections live behind a long press, the iOS convention for acting on one item in place:
    // deliberate enough that a hurried tap on the check can never undo or remove a set.
    // The preview shape is iOS-only; the macOS host build (tests only) uses the default.
    #if os(iOS)
      .contentShape(.contextMenuPreview, shape)
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

  /// Ordinary sizes: ordinal, last time, weight, reps, log — one line, aligned to the column
  /// header `ExerciseSectionView` draws above.
  private var rowLayout: some View {
    HStack(spacing: Tokens.Spacing.snug) {
      ordinalBadge
        .frame(width: SetRowMetrics.ordinalWidth)

      previousColumn
        .frame(width: SetRowMetrics.previousWidth, alignment: .leading)

      valueField(.weight, suffix: showsInlineLabels ? unit.abbreviation : nil)
        .frame(minWidth: SetRowMetrics.weightMinWidth)
      valueField(.reps, suffix: showsInlineLabels ? "reps" : nil)
        .frame(minWidth: SetRowMetrics.repsMinWidth)

      logButton
    }
  }

  /// Accessibility sizes: a header line with the ordinal and last time, then the two values at
  /// full width with their units, then the log control at full width.
  private var stackedLayout: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.regular) {
        ordinalBadge
        previousColumn
      }
      valueField(.weight, suffix: unit.abbreviation)
      valueField(.reps, suffix: "reps")
      logButton
    }
    .padding(.vertical, Tokens.Spacing.tight)
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
    return Button(label) { adjustLoad(by: delta) }
    .buttonStyle(HardsetButtonStyle(.secondary, size: .logger, fullWidth: true))
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

  /// Working sets are numbered; a warm-up reads "W" inside a dashed outline, the app's mark for
  /// something that is present but not counted.
  private var ordinalBadge: some View {
    let shape = RoundedRectangle(cornerRadius: Tokens.Radius.control - Tokens.Spacing.tight)
    return Text(isWarmup ? "W" : String(ordinal + 1))
      .font(Tokens.Text.figure)
      .foregroundStyle(isWarmup ? Tokens.Color.textSecondary : Tokens.Color.textPrimary)
      .frame(minWidth: SetRowMetrics.ordinalWidth, minHeight: SetRowMetrics.ordinalWidth)
      .background(isWarmup ? Color.clear : Tokens.Color.surfaceRaised, in: shape)
      .overlay {
        if isWarmup {
          shape.strokeBorder(
            Tokens.Color.controlBorder,
            style: StrokeStyle(lineWidth: Tokens.Stroke.hairline, dash: [3, 2])
          )
        }
      }
  }

  /// Last time's set as a logbook would write it: the load, and the reps beneath it. Two short
  /// lines rather than one long one, so the column stays narrow enough for both entry fields to
  /// keep their size on a 375 pt phone.
  private var previousColumn: some View {
    VStack(alignment: .leading, spacing: 0) {
      if showsInlineLabels || isStacked {
        Text("Last time")
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.textSecondary)
          .padding(.bottom, Tokens.Spacing.hairline)
      }
      if let previous {
        Text(LoadFigure.text(unit.fromKilograms(previous.weightKg)))
          .font(Tokens.Text.figure)
          .foregroundStyle(Tokens.Color.textSecondary)
          .lineLimit(1)
          // The one value allowed to give a little: it is a hint, read second, and a long pound
          // figure must not push the fields the lifter types into off the row.
          .minimumScaleFactor(0.8)
        Text("× \(previous.reps)")
          .font(Tokens.Text.caption.monospacedDigit())
          .foregroundStyle(Tokens.Color.textSecondary)
          .lineLimit(1)
      } else {
        Text("—")
          .font(Tokens.Text.figure)
          .foregroundStyle(Tokens.Color.textSecondary)
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

  private func valueField(_ field: SetRowField, suffix: String?) -> some View {
    let isEditing = editingField == field
    let text = displayText(field)
    let shape = RoundedRectangle(cornerRadius: Tokens.Radius.control)
    return Button {
      onBeginEditing?(field)
    } label: {
      HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.tight) {
        // An empty field shows an em dash, never "0" — a zero on screen reads as a value.
        Text(text ?? "—")
          .font(Tokens.Text.setEntry)
          .foregroundStyle(text == nil ? Tokens.Color.textSecondary : Tokens.Color.textPrimary)
          // Condensed tabular figures fit a pound value such as "132.28" at full size on a 375 pt
          // phone. The mild floor below exists only so an extreme value shrinks a little rather
          // than truncating: a number cut to "132.…" is worse than one drawn slightly smaller.
          .lineLimit(1)
          .minimumScaleFactor(0.85)
        if let suffix {
          Text(suffix)
            .font(Tokens.Text.unit)
            .foregroundStyle(Tokens.Color.textSecondary)
        }
      }
      .padding(.horizontal, Tokens.Spacing.tight)
      .frame(maxWidth: .infinity, minHeight: Tokens.loggerTapTarget)
      .background(isEditing ? Tokens.Color.accentSurface : Tokens.Color.surfaceRaised, in: shape)
      .overlay(
        shape.strokeBorder(
          isEditing ? Tokens.Color.accent : Tokens.Color.controlBorder,
          lineWidth: isEditing ? Tokens.Stroke.selected : Tokens.Stroke.hairline
        )
      )
      .contentShape(shape)
    }
    .buttonStyle(SetReadoutStyle())
    .disabled(isLogged || onBeginEditing == nil)
  }

  /// The one tap the whole logger is built around.
  ///
  /// Four states, each drawn differently so none is mistaken for another: incomplete (dashed, and
  /// disabled), ready (outlined), next up (filled with the accent), and logged (the success
  /// stamp). The stamp is the app's one spring; with Reduce Motion it simply appears.
  ///
  /// Logged and next up differ in shape, not only in hue. Both used to be a filled square with the
  /// same check, about 1.1:1 apart in luminance, so in glare or with a colour-vision deficiency a
  /// set waiting to be logged looked saved. A key face (square, check) means "tap to log"; a
  /// logged set loses its key face and wears a round seal, which nothing tappable in the logger
  /// uses. At accessibility sizes the control also says which it is in words.
  private var logButton: some View {
    let shape = RoundedRectangle(cornerRadius: Tokens.Radius.control)
    let isReady = draft.isLoggable
    return Button(action: onLog) {
      HStack(spacing: Tokens.Spacing.snug) {
        ZStack {
          Image(systemName: "checkmark")
            .font(Tokens.Text.headline.weight(.bold))
            .foregroundStyle(logSymbolColor(isReady: isReady))
            .opacity(isLogged ? 0 : 1)
          Image(systemName: "checkmark.circle.fill")
            .font(Tokens.Text.readout)
            .foregroundStyle(Tokens.Color.success)
            .opacity(isLogged ? 1 : 0)
            .scaleEffect(isLogged || reduceMotion ? 1 : 0.6)
        }
        // Only the glyphs spring. The key face below changes at once, so nothing is laid out
        // twice and the stamp stays the one moving thing.
        .animation(
          Tokens.Motion.adaptive(Tokens.Motion.stamp, reduceMotion: reduceMotion),
          value: isLogged
        )
        if isStacked {
          Text(isLogged ? "Logged" : "Log set")
            .font(Tokens.Text.headline)
            .foregroundStyle(isLogged ? Tokens.Color.success : logSymbolColor(isReady: isReady))
        }
      }
      .frame(
        maxWidth: isStacked ? .infinity : Tokens.loggerTapTarget,
        minHeight: Tokens.loggerTapTarget
      )
      .frame(width: isStacked ? nil : Tokens.loggerTapTarget)
      .background(logFill(isReady: isReady), in: shape)
      .overlay {
        if !isLogged && !(isReady && isNext) {
          shape.strokeBorder(
            isReady ? Tokens.Color.accent : Tokens.Color.controlBorder,
            style: StrokeStyle(
              lineWidth: isReady ? Tokens.Stroke.selected : Tokens.Stroke.hairline,
              dash: isReady ? [] : [4, 3]
            )
          )
        }
      }
      .contentShape(shape)
    }
    .buttonStyle(SetReadoutStyle())
    // The same predicate the store enforces. There is no second definition of "complete".
    .disabled(!isReady || isLogged)
    .opacity(isReady || isLogged ? 1 : 0.6)
    .accessibilityLabel(isLogged ? "Logged" : "Log set")
    // Haptics confirm the tap landed without the user looking at the phone.
    .sensoryFeedback(Tokens.Haptic.success, trigger: isLogged) { !$0 && $1 }
  }

  /// A logged set has no key face: its seal sits straight on the row's success tint.
  private func logFill(isReady: Bool) -> Color {
    if isLogged { return .clear }
    if isReady && isNext { return Tokens.Color.accentFill }
    return Tokens.Color.surfaceRaised
  }

  private func logSymbolColor(isReady: Bool) -> Color {
    // `onAccent` is dark on the dark-mode accent fill and white on the light-mode one, which is
    // the pairing that clears 7:1 on it.
    if isReady && isNext { return Tokens.Color.onAccent }
    return isReady ? Tokens.Color.accent : Tokens.Color.textSecondary
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

/// One way of writing a load, everywhere the logger shows one.
///
/// Up to two decimals with trailing zeros trimmed: the precision the keypad accepts and seeds,
/// so a kilogram load shown in pounds reads "220.46" in the field, under "Last time", on the
/// machine chip and on the step buttons alike. Three roundings on one card made one load look like
/// two different numbers. Display only; the draft stays canonical kilograms.
///
/// Written with the locale's decimal separator, as the keypad's separator key is labelled, and
/// without grouping, as the keypad types it: "82,5" on a comma-locale phone, and "1002.5" rather
/// than "1,002.5" for a load typed as 1002.5.
enum LoadFigure {
  static func text(_ value: Double, locale: Locale = .current) -> String {
    guard value.isFinite else { return "—" }
    return value.formatted(
      .number.precision(.fractionLength(0...2)).grouping(.never).locale(locale)
    )
  }

  /// Keypad text, which is always stored with ".", written with the locale's separator.
  static func typed(_ text: String, locale: Locale = .current) -> String {
    let separator = locale.decimalSeparator ?? "."
    return separator == "." ? text : text.replacingOccurrences(of: ".", with: separator)
  }
}

/// Column widths shared by `SetRowView` and the column header `ExerciseSectionView` draws above
/// the rows, so the header's labels sit exactly over the values they name.
///
/// Sized for the narrowest supported phone. With the 56 pt log control and four 8 pt gaps the row
/// needs 292 pt; a 375 pt screen leaves it 319 pt inside the session's margins, the card's padding
/// and the row's inset, and the slack goes to the two entry fields.
enum SetRowMetrics {
  static let ordinalWidth: CGFloat = 28
  static let previousWidth: CGFloat = 60
  static let weightMinWidth: CGFloat = 64
  static let repsMinWidth: CGFloat = 52
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
          // Logged: the success stamp, and the row takes the success tint.
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
        .background(Tokens.Color.background)
      }
    }
    return Harness()
  }
#endif

/// Disabled saved rows retain measured text contrast; only actions are disabled.
/// Incomplete log controls still apply their explicit disabled opacity above.
///
/// Pressed, a field or the check sinks to 0.97 and dims slightly, as every other control does: the
/// most frequent tap in the app gave no touch-down feedback at all. Each control draws its own
/// fill and shape, so the press is carried by opacity rather than a second fill. A disabled
/// button never reports a press, so saved rows keep their full contrast.
private struct SetReadoutStyle: ButtonStyle {
  func makeBody(configuration: ButtonStyleConfiguration) -> some View {
    SetReadoutBody(configuration: configuration)
  }
}

private struct SetReadoutBody: View {
  let configuration: ButtonStyleConfiguration

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    configuration.label
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
      .opacity(configuration.isPressed ? 0.85 : 1)
      .animation(
        Tokens.Motion.adaptive(Tokens.Motion.press, reduceMotion: reduceMotion),
        value: configuration.isPressed
      )
  }
}
