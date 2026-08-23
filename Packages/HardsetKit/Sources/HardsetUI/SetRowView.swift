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

  /// Chosen layout depends on this. At accessibility sizes the horizontal row cannot hold its
  /// five columns: "Last time" broke to one character per line ("Las / t / tim / e") and the unit
  /// suffixes split mid-word ("—k / g"), which made the most-used screen in the app unreadable for
  /// exactly the people who need the larger text.
  @Environment(\.dynamicTypeSize) private var typeSize

  /// The ordinal's gutter, scaled. It was a hard 28 pt, which is narrower than a single AX5 digit.
  @ScaledMetric(relativeTo: .subheadline) private var ordinalWidth: CGFloat = 28

  private let ordinal: Int
  private let isWarmup: Bool
  private let isLogged: Bool
  private let unit: WeightUnit
  private let previous: PriorSetRecord?
  private let priorNote: String?
  /// How heavy this set is relative to the lifter's own best on this movement, or `nil` when
  /// there is no history to measure against. Drives the weight of the commit animation only --
  /// it is never displayed, and `nil` deliberately produces no effect rather than a middle.
  private let loadFraction: Double?
  /// True when the movement is loaded by the lifter's own body, so an empty or zero weight field
  /// means "bodyweight only" and not "no load".
  private let isBodyweight: Bool
  private let onLog: () -> Void
  /// Takes a logged set back. `nil` hides the affordance, which is correct wherever un-logging is
  /// not supported.
  private let onUnlog: (() -> Void)?
  /// Removes an empty row. `nil` hides it. Never offered on a logged set -- taking a set back is a
  /// different action with a different meaning.
  private let onRemove: (() -> Void)?

  public init(
    draft: Binding<SetEntryDraft>,
    ordinal: Int,
    isWarmup: Bool = false,
    isLogged: Bool = false,
    unit: WeightUnit,
    previous: PriorSetRecord? = nil,
    priorNote: String? = nil,
    loadFraction: Double? = nil,
    isBodyweight: Bool = false,
    onLog: @escaping () -> Void,
    onUnlog: (() -> Void)? = nil,
    onRemove: (() -> Void)? = nil
  ) {
    self._draft = draft
    self.ordinal = ordinal
    self.isWarmup = isWarmup
    self.isLogged = isLogged
    self.unit = unit
    self.previous = previous
    self.priorNote = priorNote
    self.loadFraction = loadFraction
    self.isBodyweight = isBodyweight
    self.onLog = onLog
    self.onUnlog = onUnlog
    self.onRemove = onRemove

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
    // One set of shared behaviour, two geometries. Everything below the layout choice -- the
    // commit animation, the accessibility element, the actions, the pad, the unit reseed -- is
    // identical, so the two paths cannot drift in behaviour, only in arrangement.
    Group {
      if typeSize.isAccessibilitySize { stackedRow } else { compactRow }
    }
    .padding(.horizontal, Tokens.Spacing.regular)
    .padding(.vertical, Tokens.Spacing.snug)
    // Opaque. Dense numeric rows are the one surface glass is actively wrong for.
    .background(Tokens.Color.surface)
    // One animation for the whole commit, weighted by the load. Driven off `isLogged` so the
    // recede, the symbol swap and the tick all move on a single curve rather than three that
    // drift apart.
    .animation(Tokens.Motion.commit(intensity: loadFraction), value: isLogged)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(spokenLabel)
    .accessibilityHint(draft.isLoggable ? "Double tap to log this set." : "Enter a weight and reps to log.")
    .accessibilityAction(named: Text("Log set")) {
      if draft.isLoggable { onLog() }
    }
    // On a logged row, taking the set back is the action a lifter actually needs -- a mistyped
    // weight is otherwise permanent. Long press rather than a visible button: it is rare, and a
    // destructive control next to the log control on a row tapped forty times a session is a
    // mis-tap waiting to happen.
    .contextMenu {
      if isLogged, let onUnlog {
        Button(role: .destructive) {
          onUnlog()
        } label: {
          Label("Take this set back", systemImage: "arrow.uturn.backward")
        }
      } else if !isLogged, let onRemove {
        Button(role: .destructive) {
          onRemove()
        } label: {
          Label("Remove this row", systemImage: "minus.circle")
        }
      }
    }
    .accessibilityAction(named: Text("Edit weight")) { editing = .weight }
    .accessibilityAction(named: Text("Edit reps")) { editing = .reps }
    // VoiceOver cannot long-press, so the same action is named here. Without this the row would be
    // uncorrectable for anyone using it.
    .accessibilityActions {
      if isLogged, let onUnlog {
        Button("Take this set back", action: onUnlog)
      } else if !isLogged, let onRemove {
        Button("Remove this row", action: onRemove)
      }
    }
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

  // MARK: - Layouts

  /// The dense row: five columns, which is right at normal text sizes and is what the logger is
  /// designed around.
  private var compactRow: some View {
    HStack(spacing: Tokens.Spacing.regular) {
      ordinalBadge
      previousBlock
        .frame(minWidth: 78, alignment: .leading)
      valueField(.weight, buffer: weightBuffer, suffix: weightSuffix)
      valueField(.reps, buffer: repsBuffer, suffix: "reps")
      logButton
    }
  }

  /// The accessibility-size row. Each value gets the full width rather than a fifth of it, so
  /// nothing wraps mid-word, and the log control spans the row -- which also makes it a far easier
  /// target for someone who set the text larger for motor rather than visual reasons.
  private var stackedRow: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.regular) {
        ordinalBadge
        previousBlock
        Spacer(minLength: 0)
      }
      valueField(.weight, buffer: weightBuffer, suffix: weightSuffix)
      valueField(.reps, buffer: repsBuffer, suffix: "reps")
      logButton
        .frame(maxWidth: .infinity)
    }
  }

  /// Last session's numbers. Rendered outside the entry fields on purpose: a suggestion must never
  /// be mistakable for a filled value.
  private var previousBlock: some View {
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
  }

  // MARK: - Pieces

  private var ordinalBadge: some View {
    Text(isWarmup ? "W" : String(ordinal + 1))
      .font(Tokens.Text.label.weight(.semibold))
      .monospacedDigit()
      .foregroundStyle(ordinalInk)
      .frame(minWidth: ordinalWidth, alignment: .leading)
  }

  /// A logged row recedes, and the next row is left as the brightest thing on screen.
  ///
  /// Most loggers do the opposite -- they light up what is finished -- and the result is a screen
  /// that gets louder as the session fills. Attention belongs on the set being worked on.
  private var ordinalInk: SwiftUI.Color {
    if isLogged { return Tokens.Color.textSecondary }
    return isWarmup ? Tokens.Color.textSecondary : Tokens.Color.textPrimary
  }

  private func valueInk(isEmpty: Bool) -> SwiftUI.Color {
    if isEmpty { return Tokens.Color.textSecondary }
    return isLogged ? Tokens.Color.textSecondary : Tokens.Color.textPrimary
  }

  /// "+ kg" on a bodyweight movement, because whatever is typed there is *added* load. A pull-up
  /// logged with an empty field is not an unloaded set.
  private var weightSuffix: String {
    isBodyweight ? "+ \(unit.abbreviation)" : unit.abbreviation
  }

  /// What a weight field says when it holds nothing, or holds zero on a bodyweight movement.
  ///
  /// "Body" rather than "0" or an em dash: zero *added* load on a pull-up is the truth, and a bare
  /// "0" reads as no load at all. Reps keep the em dash, because a set with no reps is genuinely
  /// unrecorded.
  private func emptyText(for field: SetRowField) -> String {
    field == .weight && isBodyweight ? "Body" : "\u{2014}"
  }

  /// A zero on a bodyweight movement is a real value, so it renders as "Body" rather than "0".
  private func displayText(for field: SetRowField, buffer: NumericEntryBuffer) -> String {
    if buffer.isEmpty { return emptyText(for: field) }
    if field == .weight, isBodyweight, buffer.value == 0 { return "Body" }
    return buffer.displayText
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
        Text(displayText(for: field, buffer: buffer))
          .font(Tokens.Text.setEntry)
          .foregroundStyle(valueInk(isEmpty: buffer.isEmpty))
          // Kilograms fit in four characters; pounds need six ("132.28"), and the field wrapped
          // mid-number onto a second line. Shrinking beats wrapping for a value read at a glance
          // between sets.
          .lineLimit(1)
          .minimumScaleFactor(0.6)
        // Suppressed while the field reads "Body": "Body + kg" is not a thing.
        if !(field == .weight && isBodyweight && (buffer.isEmpty || buffer.value == 0)) {
          Text(suffix)
            .font(Tokens.Text.caption)
            .foregroundStyle(Tokens.Color.textSecondary)
        }
      }
      .frame(maxWidth: .infinity, minHeight: Tokens.loggerTapTarget)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background(
      Tokens.Color.ground,
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
        // The check replaces the circle rather than cross-fading into it. `.offUp` reads as the
        // set being put away, which is what just happened.
        .contentTransition(.symbolEffect(.replace.offUp))
        .frame(width: Tokens.loggerTapTarget, height: Tokens.loggerTapTarget)
        .contentShape(Rectangle())
    }
    // Not `.plain`: this is the app's signature interaction and it has to respond to the finger
    // landing, not to the finger leaving. See `CommitButtonStyle`.
    .buttonStyle(CommitButtonStyle(intensity: loadFraction))
    .foregroundStyle(isLogged ? Tokens.Color.certainty(.high) : Tokens.Color.accent)
    // The same predicate the store enforces. There is no second definition of "complete".
    .disabled(!draft.isLoggable)
    .opacity(draft.isLoggable || isLogged ? 1 : 0.35)
    // Haptics confirm the tap landed without the user looking at the phone.
    .sensoryFeedback(.success, trigger: isLogged) { !$0 && $1 }
    // The un-log direction, which the haptics table had listed as having no host.
    .sensoryFeedback(.impact(weight: .light), trigger: isLogged) { $0 && !$1 }
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
        .background(Tokens.Color.ground)
      }
    }
    return Harness()
  }
#endif
