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
public struct SetRowView: View {
  @Binding private var draft: SetEntryDraft
  @State private var weightBuffer: NumericEntryBuffer
  @State private var repsBuffer: NumericEntryBuffer
  @State private var editing: SetRowField?

  private let ordinal: Int
  private let isWarmup: Bool
  private let isLogged: Bool
  private let unit: WeightUnit
  private let previous: PriorSetRecord?
  private let priorNote: String?
  private let onLog: () -> Void

  public init(
    draft: Binding<SetEntryDraft>,
    ordinal: Int,
    isWarmup: Bool = false,
    isLogged: Bool = false,
    unit: WeightUnit,
    previous: PriorSetRecord? = nil,
    priorNote: String? = nil,
    onLog: @escaping () -> Void
  ) {
    self._draft = draft
    self.ordinal = ordinal
    self.isWarmup = isWarmup
    self.isLogged = isLogged
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
            .foregroundStyle(Tokens.Color.certainty(.low))
        }
      }
      .frame(minWidth: 78, alignment: .leading)

      valueField(.weight, buffer: weightBuffer, suffix: unit.abbreviation)
      valueField(.reps, buffer: repsBuffer, suffix: "reps")

      logButton
    }
    .padding(.horizontal, Tokens.Spacing.regular)
    .padding(.vertical, Tokens.Spacing.snug)
    // Opaque. Dense numeric rows are the one surface glass is actively wrong for.
    .background(Tokens.Color.surface)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(spokenLabel)
    .accessibilityHint(draft.isLoggable ? "Double tap to log this set." : "Enter a weight and reps to log.")
    .accessibilityAction(named: Text("Log set")) {
      if draft.isLoggable { onLog() }
    }
    .accessibilityAction(named: Text("Edit weight")) { editing = .weight }
    .accessibilityAction(named: Text("Edit reps")) { editing = .reps }
    .sheet(item: $editing) { field in
      padSheet(for: field)
    }
    // Reseeded when the unit changes, because `@State` is initialised once per view identity: the
    // suffix switched to "kg" while the number stayed in pounds, so a 60 kg set read "132.28 kg".
    // Editing that row would then have written 132.28 kg to storage — a wrong number the user
    // never typed. The draft is canonical kilograms, so reseeding from it is always correct.
    .onChange(of: unit) { reseedBuffers() }
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

  private var ordinalBadge: some View {
    Text(isWarmup ? "W" : String(ordinal + 1))
      .font(Tokens.Text.label.weight(.semibold))
      .monospacedDigit()
      .foregroundStyle(isWarmup ? Tokens.Color.textSecondary : Tokens.Color.textPrimary)
      .frame(width: 28)
  }

  private func valueField(
    _ field: SetRowField,
    buffer: NumericEntryBuffer,
    suffix: String
  ) -> some View {
    Button {
      editing = field
    } label: {
      HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.tight) {
        // An empty field shows an em dash, never "0" — a zero on screen reads as a value.
        Text(buffer.isEmpty ? "—" : buffer.displayText)
          .font(Tokens.Text.setEntry)
          .foregroundStyle(buffer.isEmpty ? Tokens.Color.textSecondary : Tokens.Color.textPrimary)
          // Kilograms fit in four characters; pounds need six ("132.28"), and the field wrapped
          // mid-number onto a second line. Shrinking beats wrapping for a value read at a glance
          // between sets.
          .lineLimit(1)
          .minimumScaleFactor(0.6)
        Text(suffix)
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.textSecondary)
      }
      .frame(maxWidth: .infinity, minHeight: Tokens.loggerTapTarget)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background(
      Tokens.Color.background,
      in: RoundedRectangle(cornerRadius: Tokens.Radius.control)
    )
    .overlay {
      if editing == field {
        RoundedRectangle(cornerRadius: Tokens.Radius.control)
          .strokeBorder(Tokens.Color.accent, lineWidth: 2)
      }
    }
  }

  private var logButton: some View {
    Button(action: onLog) {
      Image(systemName: isLogged ? "checkmark.circle.fill" : "circle")
        .font(.title2)
        .frame(width: Tokens.loggerTapTarget, height: Tokens.loggerTapTarget)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(isLogged ? Tokens.Color.certainty(.high) : Tokens.Color.accent)
    // The same predicate the store enforces. There is no second definition of "complete".
    .disabled(!draft.isLoggable)
    .opacity(draft.isLoggable || isLogged ? 1 : 0.35)
    // Haptics confirm the tap landed without the user looking at the phone.
    .sensoryFeedback(.success, trigger: isLogged) { !$0 && $1 }
  }

  private func padSheet(for field: SetRowField) -> some View {
    let binding: Binding<NumericEntryBuffer> =
      field == .weight
      ? Binding(get: { weightBuffer }, set: { weightBuffer = $0; pushToDraft() })
      : Binding(get: { repsBuffer }, set: { repsBuffer = $0; pushToDraft() })

    return NumericPad(buffer: binding) { editing = nil }
      .presentationDetents([.height(360)])
      // The row stays visible and tappable behind the pad, so this reads as a keyboard
      // replacement rather than a modal that interrupts the set.
      #if os(iOS)
        .presentationBackgroundInteraction(.enabled(upThrough: .height(360)))
      #endif
  }

  // MARK: - Wiring

  /// Writes both buffers into the draft, converting display units back to canonical
  /// kilograms. There is no `?? 0` here and there must never be one: an empty buffer's value
  /// is `nil`, which makes the row not loggable, which is the correct outcome.
  private func pushToDraft() {
    draft.weightKg = weightBuffer.value.map(unit.toKilograms)
    draft.reps = repsBuffer.value.map { Int($0) }
  }

  private var previousDescription: String {
    guard let previous else { return "—" }
    let weight = unit.fromKilograms(previous.weightKg)
    return "\(Self.format(weight)) \(unit.abbreviation) × \(previous.reps)"
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
      @State private var blank = SetEntryDraft(suggestion: nil)

      var body: some View {
        VStack(spacing: Tokens.Spacing.snug) {
          // Prefilled from history: loggable immediately, one tap.
          SetRowView(
            draft: $suggested,
            ordinal: 0,
            unit: .kilograms,
            previous: PriorSetRecord(weightKg: 100, reps: 8, completedAt: .distantPast),
            onLog: {}
          )
          // No history: genuinely empty, and the log control is disabled rather than
          // silently writing zero.
          SetRowView(draft: $blank, ordinal: 1, unit: .kilograms, onLog: {})
        }
        .padding()
        .background(Tokens.Color.background)
      }
    }
    return Harness()
  }
#endif
