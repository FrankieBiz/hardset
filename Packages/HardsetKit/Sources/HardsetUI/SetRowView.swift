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
///    empty field and logged 0 kg. Here the suggestion is written into the buffer, and the
///    "Last time" column is rendered *outside* the fields — so what looks filled is filled, and
///    what is only a hint cannot be mistaken for one.
/// 2. **The log control cannot fire on an incomplete row.** It is bound to
///    `SetEntryDraft.isLoggable`, which is the same predicate `LoggerStore.logSet` enforces. A
///    disagreement between them is impossible because there is only one predicate.
/// 3. **The row is one accessibility element.** A 40-set session with five separately focusable
///    controls per row costs roughly 280 VoiceOver swipes to review. The row reads as a
///    sentence and exposes its actions as named custom actions instead.
///
/// Two layouts, chosen from Dynamic Type rather than by shrinking text: a single line of columns
/// at ordinary sizes, and a stacked card at accessibility sizes, where the values take the full
/// width and carry their own labels.
public struct SetRowView: View {
  @Binding private var draft: SetEntryDraft
  @State private var weightBuffer: NumericEntryBuffer
  @State private var repsBuffer: NumericEntryBuffer
  @State private var editing: SetRowField?
  /// The keypad's measured height, so the sheet is exactly as tall as its keys. Seeded with a
  /// close estimate so the first presentation does not visibly resize.
  @State private var padHeight: CGFloat = 470

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private let ordinal: Int
  private let isWarmup: Bool
  private let isLogged: Bool
  private let isNext: Bool
  private let showsInlineLabels: Bool
  private let unit: WeightUnit
  private let previous: PriorSetRecord?
  private let priorNote: String?
  private let onLog: () -> Void

  /// - Parameter isNext: The first unlogged set of its exercise. Its log control is filled rather
  ///   than outlined, so the eye lands on the one tap that matters between sets.
  /// - Parameter showsInlineLabels: Draws "Last time" and the unit inside the row. A caller that
  ///   draws a column header above its rows passes `false`; accessibility sizes always show them,
  ///   because the stacked layout has no columns for a header to label.
  public init(
    draft: Binding<SetEntryDraft>,
    ordinal: Int,
    isWarmup: Bool = false,
    isLogged: Bool = false,
    isNext: Bool = false,
    showsInlineLabels: Bool = true,
    unit: WeightUnit,
    previous: PriorSetRecord? = nil,
    priorNote: String? = nil,
    onLog: @escaping () -> Void
  ) {
    self._draft = draft
    self.ordinal = ordinal
    self.isWarmup = isWarmup
    self.isLogged = isLogged
    self.isNext = isNext
    self.showsInlineLabels = showsInlineLabels
    self.unit = unit
    self.previous = previous
    self.priorNote = priorNote
    self.onLog = onLog

    // Seeded once, from whatever the caller already resolved as the suggestion. Note the
    // conversion: the draft is canonical kilograms, the buffer is what the user reads.
    self._weightBuffer = State(
      initialValue: NumericEntryBuffer(
        value: draft.wrappedValue.weightKg.map(unit.fromKilograms),
        maximumIntegerDigits: 4,
        maximumFractionDigits: 2
      )
    )
    self._repsBuffer = State(
      initialValue: NumericEntryBuffer(
        value: draft.wrappedValue.reps.map(Double.init),
        allowsDecimal: false,
        maximumIntegerDigits: 3,
        maximumFractionDigits: 0
      )
    )
  }

  /// True at accessibility text sizes, where five columns cannot share one line legibly.
  private var isStacked: Bool { dynamicTypeSize.isAccessibilitySize }

  public var body: some View {
    Group {
      if isStacked {
        stackedLayout
      } else {
        rowLayout
      }
    }
    .padding(.horizontal, Tokens.Spacing.tight)
    .padding(.vertical, Tokens.Spacing.tight)
    // Opaque. Dense numeric rows are the one surface glass is actively wrong for. A logged row
    // takes the success tint, so a glance down the card shows what is done without reading.
    .background(
      isLogged ? Tokens.Color.successSurface : Tokens.Color.surface,
      in: RoundedRectangle(cornerRadius: Tokens.Radius.control)
    )
    .animation(Tokens.Motion.adaptive(Tokens.Motion.state, reduceMotion: reduceMotion), value: isLogged)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(spokenLabel)
    .accessibilityHint(draft.isLoggable ? "Double tap to log this set." : "Enter a weight and reps to log.")
    .accessibilityAction(named: Text("Log set")) {
      if draft.isLoggable { onLog() }
    }
    .accessibilityAction(named: Text("Edit weight")) { beginEditing(.weight) }
    .accessibilityAction(named: Text("Edit reps")) { beginEditing(.reps) }
    .sheet(item: $editing) { field in
      padSheet(for: field)
    }
    // Reseeded when the unit changes, because `@State` is initialised once per view identity: the
    // suffix switched to "kg" while the number stayed in pounds, so a 60 kg set read "132.28 kg".
    // Editing that row would then have written 132.28 kg to storage — a wrong number the user
    // never typed. The draft is canonical kilograms, so reseeding from it is always correct.
    .onChange(of: unit) { reseedBuffers() }
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

      valueField(.weight, buffer: weightBuffer, suffix: showsInlineLabels ? unit.abbreviation : nil)
        .frame(minWidth: SetRowMetrics.weightMinWidth)
      valueField(.reps, buffer: repsBuffer, suffix: showsInlineLabels ? "reps" : nil)
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
      valueField(.weight, buffer: weightBuffer, suffix: unit.abbreviation)
      valueField(.reps, buffer: repsBuffer, suffix: "reps")
      logButton
    }
    .padding(.vertical, Tokens.Spacing.tight)
  }

  /// Rebuilds both display buffers from the draft, in the current unit.
  private func reseedBuffers() {
    weightBuffer = NumericEntryBuffer(
      value: draft.weightKg.map(unit.fromKilograms),
      maximumIntegerDigits: 4,
      maximumFractionDigits: 2
    )
    repsBuffer = NumericEntryBuffer(
      value: draft.reps.map(Double.init),
      allowsDecimal: false,
      maximumIntegerDigits: 3,
      maximumFractionDigits: 0
    )
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
        Text(Self.format(unit.fromKilograms(previous.weightKg)))
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

  private func valueField(
    _ field: SetRowField,
    buffer: NumericEntryBuffer,
    suffix: String?
  ) -> some View {
    let isEditing = editing == field
    let shape = RoundedRectangle(cornerRadius: Tokens.Radius.control)
    return Button {
      beginEditing(field)
    } label: {
      HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.tight) {
        // An empty field shows an em dash, never "0" — a zero on screen reads as a value.
        Text(buffer.isEmpty ? "—" : buffer.displayText)
          .font(Tokens.Text.setEntry)
          .foregroundStyle(buffer.isEmpty ? Tokens.Color.textSecondary : Tokens.Color.textPrimary)
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
    .buttonStyle(.plain)
  }

  /// The one tap the whole logger is built around.
  ///
  /// Four states, each drawn differently so none is mistaken for another: incomplete (dashed, and
  /// disabled), ready (outlined), next up (filled with the accent), and logged (the success
  /// stamp). The stamp is the app's one spring; with Reduce Motion it simply appears.
  private var logButton: some View {
    let shape = RoundedRectangle(cornerRadius: Tokens.Radius.control)
    let isReady = draft.isLoggable
    return Button(action: onLog) {
      Image(systemName: "checkmark")
        .font(Tokens.Text.headline.weight(.bold))
        .foregroundStyle(logSymbolColor(isReady: isReady))
        .scaleEffect(isLogged || reduceMotion ? 1 : 0.85)
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
        .animation(
          Tokens.Motion.adaptive(Tokens.Motion.stamp, reduceMotion: reduceMotion),
          value: isLogged
        )
    }
    .buttonStyle(.plain)
    // The same predicate the store enforces. There is no second definition of "complete".
    .disabled(!isReady)
    .opacity(isReady || isLogged ? 1 : 0.6)
    .accessibilityLabel(isLogged ? "Logged" : "Log set")
    // Haptics confirm the tap landed without the user looking at the phone.
    .sensoryFeedback(.success, trigger: isLogged) { !$0 && $1 }
  }

  private func logFill(isReady: Bool) -> Color {
    if isLogged { return Tokens.Color.success }
    if isReady && isNext { return Tokens.Color.accentFill }
    return Tokens.Color.surfaceRaised
  }

  private func logSymbolColor(isReady: Bool) -> Color {
    // `onAccent` is dark on the dark-mode fills and white on the light-mode ones, which is the
    // pairing that clears 7:1 on both the accent and the success fill.
    if isLogged || (isReady && isNext) { return Tokens.Color.onAccent }
    return isReady ? Tokens.Color.accent : Tokens.Color.textSecondary
  }

  private func padSheet(for field: SetRowField) -> some View {
    let binding: Binding<NumericEntryBuffer> =
      field == .weight
      ? Binding(get: { weightBuffer }, set: { weightBuffer = $0; pushToDraft() })
      : Binding(get: { repsBuffer }, set: { repsBuffer = $0; pushToDraft() })

    return ScrollView {
      NumericPad(
        buffer: binding,
        title: field == .weight ? "Weight" : "Reps",
        unit: field == .weight ? unit.abbreviation : "reps",
        onDone: { editing = nil },
        onNext: field == .weight ? {
          if !repsBuffer.isEmpty { repsBuffer.replaceOnFirstEntry = true }
          editing = .reps
        } : nil
      )
      // Measured rather than fixed. A hard-coded 370 pt detent was shorter than the pad's own
      // minimum (380 pt before any larger text), so the bottom row could clip; the scroll view
      // keeps every key reachable when the measured height exceeds what the screen offers.
      .onGeometryChange(for: CGFloat.self) { proxy in
        proxy.size.height
      } action: { height in
        padHeight = height
      }
    }
    .scrollBounceBehavior(.basedOnSize)
    .background(Tokens.Color.surface)
    .presentationDetents([.height(padHeight)])
    .presentationBackground(Tokens.Color.surface)
    .presentationDragIndicator(.hidden)
    // The row stays visible and tappable behind the pad, so this reads as a keyboard
    // replacement rather than a modal that interrupts the set.
    #if os(iOS)
      .presentationBackgroundInteraction(.enabled(upThrough: .height(padHeight)))
      .presentationCornerRadius(Tokens.Radius.card)
    #endif
  }

  // MARK: - Wiring

  /// Puts the keypad on a field. A field that already holds a value is armed to be replaced by
  /// the first digit typed, so retyping a prefilled weight does not mean deleting it first.
  private func beginEditing(_ field: SetRowField) {
    if field == .weight && !weightBuffer.isEmpty {
      weightBuffer.replaceOnFirstEntry = true
    } else if field == .reps && !repsBuffer.isEmpty {
      repsBuffer.replaceOnFirstEntry = true
    }
    editing = field
  }

  /// Writes both buffers into the draft, converting display units back to canonical
  /// kilograms. There is no `?? 0` here and there must never be one: an empty buffer's value
  /// is `nil`, which makes the row not loggable, which is the correct outcome.
  private func pushToDraft() {
    draft.weightKg = weightBuffer.value.map(unit.toKilograms)
    draft.reps = repsBuffer.value.map { Int($0) }
  }

  private var spokenLabel: String {
    var parts: [String] = [isWarmup ? "Warm-up set" : "Set \(ordinal + 1)"]
    if let weight = weightBuffer.value, let reps = repsBuffer.value {
      parts.append("\(Self.format(weight)) \(unit.abbreviation), \(Int(reps)) reps")
    } else {
      parts.append("no values entered")
    }
    if let previous {
      parts.append(
        "last time \(Self.format(unit.fromKilograms(previous.weightKg))) \(unit.abbreviation) for \(previous.reps)"
      )
    }
    if let priorNote { parts.append(priorNote) }
    if isLogged { parts.append("logged") }
    return parts.joined(separator: ", ")
  }

  private static func format(_ value: Double) -> String {
    value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
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
            onLog: {}
          )
          // Prefilled from history and next up: loggable immediately, one tap, filled control.
          SetRowView(
            draft: $next,
            ordinal: 1,
            isNext: true,
            unit: .kilograms,
            previous: PriorSetRecord(weightKg: 105, reps: 6, completedAt: .distantPast),
            onLog: {}
          )
          // No history: genuinely empty, and the log control is disabled rather than
          // silently writing zero.
          SetRowView(draft: $blank, ordinal: 2, unit: .kilograms, onLog: {})
        }
        .padding()
        .background(Tokens.Color.background)
      }
    }
    return Harness()
  }
#endif
