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
  private let onFocus: (SetRowField) -> Void
  private let onLog: () -> Void

  /// - Parameter keypad: The pad editing this row, or `nil` when the row is not focused. While it
  ///   is set the row shows what is being typed, which `SessionView` also writes into the draft.
  /// - Parameter onFocus: A field was tapped. The caller opens the pad on it.
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
    onFocus: @escaping (SetRowField) -> Void,
    onLog: @escaping () -> Void
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
    self.onFocus = onFocus
    self.onLog = onLog
  }

  public var body: some View {
    HStack(spacing: Tokens.Spacing.regular) {
      ordinalBadge

      VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
        Text("Last time")
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.textSecondary)
        Text(previousDescription)
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.textSecondary)
          .monospacedDigit()
        if let priorNote {
          // An assumption the user should be able to see, not a number presented as fact.
          Text(priorNote)
            .font(Tokens.Text.caption)
            .foregroundStyle(Tokens.Color.caveat)
        }
      }
      .frame(minWidth: 78, alignment: .leading)

      valueField(.weight, suffix: unit.abbreviation)
      valueField(.reps, suffix: "reps")

      logButton
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
    .accessibilityElement(children: .combine)
    .accessibilityLabel(spokenLabel)
    // A logged row is read-only (see `valueField`), so it has no hint to give.
    .accessibilityHint(
      isLogged
        ? ""
        : (draft.isLoggable ? "Double tap to log this set." : "Enter a weight and reps to log.")
    )
    .accessibilityAction(named: Text("Log set")) {
      if draft.isLoggable { onLog() }
    }
    // The row is one combined element, so `.disabled` on the field buttons does not reach these.
    // Left in place on a logged row they would still open the pad and edit an unsaved draft.
    .accessibilityActions {
      if !isLogged {
        Button("Edit weight") { onFocus(.weight) }
        Button("Edit reps") { onFocus(.reps) }
      }
    }
  }

  // MARK: - Pieces

  private var ordinalBadge: some View {
    Text(isWarmup ? "W" : String(ordinal + 1))
      .font(Tokens.Text.label.weight(.semibold))
      .monospacedDigit()
      .foregroundStyle(isWarmup ? Tokens.Color.textSecondary : Tokens.Color.textPrimary)
      .frame(width: 28)
  }

  private func valueField(_ field: SetRowField, suffix: String) -> some View {
    let shown = value(field)
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
      .frame(maxWidth: .infinity, minHeight: controlHeight)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    // Editing a logged set changed only the in-memory draft, never the database, so the row showed
    // a check mark beside an unsaved value. Logged rows are read-only until editing returns
    // properly in Phase 2 (2.3).
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
      Image(systemName: isLogged ? "checkmark.circle.fill" : "circle")
        .font(.title2)
        // The width stays fixed so the value columns line up between compact and full rows.
        .frame(width: Tokens.loggerTapTarget, height: controlHeight)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(isLogged ? Tokens.Color.success : Tokens.Color.accent)
    // The same predicate the store enforces. There is no second definition of "complete".
    .disabled(!draft.isLoggable)
    .opacity(draft.isLoggable || isLogged ? 1 : 0.35)
    // Haptics confirm the tap landed without the user looking at the phone.
    .sensoryFeedback(.success, trigger: isLogged) { !$0 && $1 }
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
      return buffer.displayText.replacingOccurrences(of: ".", with: decimalSeparator)
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
    emphasis == .logged ? Tokens.minimumTapTarget : Tokens.loggerTapTarget
  }

  /// The user's locale decides how a decimal point looks; the keypad's text always uses a period.
  private var decimalSeparator: String {
    Locale.current.decimalSeparator ?? "."
  }

  private var formatter: WeightFormatter { WeightFormatter(unit: unit) }

  private var previousDescription: String {
    guard let previous else { return "—" }
    return "\(formatter.load(kilograms: previous.weightKg)) × \(previous.reps)"
  }

  private var spokenLabel: String {
    var parts: [String] = [isWarmup ? "Warm-up set" : "Set \(ordinal + 1)"]
    // The draft is canonical kilograms, and while the pad is open it holds each keystroke.
    if let weight = draft.weightKg, let reps = draft.reps {
      parts.append("\(formatter.spoken(kilograms: weight)), \(reps) reps")
    } else {
      parts.append("no values entered")
    }
    if let previous {
      let lastLoad = formatter.spoken(kilograms: previous.weightKg)
      parts.append("last time \(lastLoad) for \(previous.reps)")
    }
    if let priorNote { parts.append(priorNote) }
    if isLogged { parts.append("logged") }
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
