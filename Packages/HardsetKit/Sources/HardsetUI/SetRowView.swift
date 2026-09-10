import HardsetCore
import SwiftUI

/// Which value a row is editing. `nil` means the row is idle.
public enum SetRowField: Hashable, Sendable {
  case weight
  case reps
  /// Effort, 1-10. Optional everywhere: a set with no RPE is a complete set.
  case rpe
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
  @State private var rpeBuffer: NumericEntryBuffer
  @State private var editing: SetRowField?
  /// The last draft this row itself wrote. Anything else arriving through the binding came from
  /// outside — a machine change, an undo — and means the display buffers are stale.
  @State private var lastPushed: SetEntryDraft?

  /// Chosen layout depends on this. At accessibility sizes the horizontal row cannot hold its
  /// five columns: "Last time" broke to one character per line ("Las / t / tim / e") and the unit
  /// suffixes split mid-word ("—k / g"), which made the most-used screen in the app unreadable for
  /// exactly the people who need the larger text.
  @Environment(\.dynamicTypeSize) private var typeSize
  /// The commit animation is the app's signature moment, which is exactly why it has to be
  /// switchable off. The row moves on one curve; under Reduce Motion it changes state without one.
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// One keypad row's height, scaled with the glyphs that sit in it.
  ///
  /// `@ScaledMetric` relative to `.title` because that is the font the keys use. The pad was
  /// presented in a hard 360 pt sheet while its content floors at 56 pt a row -- six rows plus
  /// spacing and padding is 400 pt at *default* text size, and the keys grow from there. So the
  /// Done key was already being clipped before anyone touched an accessibility setting, on the one
  /// control every weight and every rep in the app is typed on.
  @ScaledMetric(relativeTo: .title) private var padRowHeight: CGFloat = Tokens.loggerTapTarget

  /// The ordinal's gutter, scaled. It was a hard 28 pt, which is narrower than a single AX5 digit.
  @ScaledMetric(relativeTo: .subheadline) private var ordinalWidth: CGFloat = 28

  /// The "Last time" column's floor, scaled with the caption it holds. It was a raw 78, in a file
  /// that uses `@ScaledMetric` for exactly this two lines above -- so the column stayed at 78 pt
  /// while the text inside it grew, and "100 kg × 8" wrapped.
  @ScaledMetric(relativeTo: .caption) private var previousWidth: CGFloat = 78

  private let ordinal: Int
  /// Working, warm-up, or a drop continuing the row above. Drives the badge, the ink and the
  /// spoken label; the row is otherwise identical, because logging a drop is logging a set.
  private let kind: SetKind
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
  /// Whether to offer the effort field at all. Off unless the lifter asked for it.
  private let tracksRPE: Bool
  /// How much one press of the keypad's minus or plus moves the load, in the unit on screen.
  /// Resolved by the caller through `PlateMath`, which is the layer that knows the movement's
  /// modality and the machine's real step. `nil` hides the control.
  private let loadStep: Double?
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
    kind: SetKind = .working,
    isLogged: Bool = false,
    unit: WeightUnit,
    previous: PriorSetRecord? = nil,
    priorNote: String? = nil,
    loadFraction: Double? = nil,
    isBodyweight: Bool = false,
    tracksRPE: Bool = false,
    loadStep: Double? = nil,
    onLog: @escaping () -> Void,
    onUnlog: (() -> Void)? = nil,
    onRemove: (() -> Void)? = nil
  ) {
    self._draft = draft
    self.ordinal = ordinal
    self.kind = kind
    self.isLogged = isLogged
    self.unit = unit
    self.previous = previous
    self.priorNote = priorNote
    self.loadFraction = loadFraction
    self.isBodyweight = isBodyweight
    self.tracksRPE = tracksRPE
    self.loadStep = loadStep
    self.onLog = onLog
    self.onUnlog = onUnlog
    self.onRemove = onRemove

    // Seeded once, from whatever the caller already resolved as the suggestion. Note the
    // conversion: the draft is canonical kilograms, the buffer is what the user reads.
    self._weightBuffer = State(
      initialValue: NumericEntryBuffer(
        // `displayValue(fromKilograms:)`, not `fromKilograms`: the conversion has to be rounded to
        // what the app displays before it becomes a prefill, or 84 kg seeds "185.19 lb". The field
        // still holds two decimals so a lifter with micro-plates can type 62.75 -- what the app
        // *produces* and what it *accepts* are different questions, and conflating them is what put
        // an unloadable number in the field.
        value: draft.wrappedValue.weightKg.map(unit.displayValue(fromKilograms:)),
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
    // Two digits and one decimal place: the scale runs to 10 and moves in halves.
    self._rpeBuffer = State(
      initialValue: NumericEntryBuffer(
        value: draft.wrappedValue.rpe,
        maximumIntegerDigits: 2,
        maximumFractionDigits: 1
      )
    )
  }

  public var body: some View {
    // One set of shared behaviour, two geometries. Everything below the layout choice -- the
    // commit animation, the accessibility element, the actions, the pad, the unit reseed -- is
    // identical, so the two paths cannot drift in behaviour, only in arrangement.
    Group {
      // The restack is not only for accessibility sizes. With effort tracking on there are six
      // columns, and at XXL/XXXL -- ordinary Dynamic Type, not an accessibility setting -- the
      // three value fields have no width floor and squeeze until the numbers scale down to 60%.
      // Restacking earlier when the sixth column is present is cheaper than the alternative: width
      // minimums on every column add up to roughly 370 pt on a 375 pt screen, which trades the
      // squeeze for a clipped row.
      if typeSize.isAccessibilitySize || (tracksRPE && typeSize >= .xxLarge) {
        stackedRow
      } else {
        compactRow
      }
    }
    .padding(.horizontal, Tokens.Spacing.regular)
    .padding(.vertical, Tokens.Spacing.snug)
    // Opaque. Dense numeric rows are the one surface glass is actively wrong for.
    .background(Tokens.Color.surface)
    // One animation for the whole commit, weighted by the load. Driven off `isLogged` so the
    // recede, the symbol swap and the tick all move on a single curve rather than three that
    // drift apart.
    .animation(reduceMotion ? nil : Tokens.Motion.commit(intensity: loadFraction), value: isLogged)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(spokenLabel)
    .accessibilityHint(
      isLogged
        ? "Double tap to take this set back."
        : draft.isLoggable ? "Double tap to log this set." : "Enter a weight and reps to log."
    )
    .accessibilityAction(named: Text(isLogged ? "Take this set back" : "Log set")) {
      toggleLoggedState()
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
    // One block rather than a mix of `.accessibilityAction(named:)` modifiers, because this is the
    // only form in which an action can be *conditional*. Registered unconditionally, the three
    // "Edit …" actions offered a rotor entry that does nothing on a logged row (the fields are
    // disabled) and an "Edit effort" on a movement that does not track effort -- a named action
    // that no-ops is the same defect the pad's placeholder decimal key was fixed for.
    //
    // Un-logging is deliberately absent here: the row's primary action at the top of this chain is
    // already named "Take this set back" when logged, and registering it twice put two identically
    // named entries in the rotor for the one action that undoes a written record.
    .accessibilityActions {
      if !isLogged {
        Button("Edit weight") { editing = .weight }
        Button("Edit reps") { editing = .reps }
        if tracksRPE {
          Button("Edit effort") { editing = .rpe }
        }
      }
      // VoiceOver cannot long-press, so the context menu's removal is named here. Without this the
      // row would be unremovable for anyone using it.
      if !isLogged, let onRemove {
        Button("Remove this row", action: onRemove)
      }
    }
    // `sheet(isPresented:)`, not `sheet(item:)`, and the difference is a bug the lifter meets on
    // their second tap. The pad deliberately leaves the row behind it live, so moving from weight
    // to reps by tapping the reps field is the expected gesture -- but that changes the item's
    // identity while a sheet is up, which SwiftUI serves by tearing the old sheet down and putting
    // a new one in its place. The teardown left the pad floating over an empty sheet with the whole
    // workout gone, so the second number was typed blind. Bound to "is a field being edited", the
    // same sheet stays up and only its contents change.
    // `onDismiss:` and not only the Done closure: a swipe down never runs Done, and the effort
    // scale is snapped there. Typing 8.3 and flicking the pad away left the row reading 8.3 while
    // the record holds 8.5. `snapRPEToScale` only touches the effort side and is idempotent, so
    // running it after any field's dismissal is correct rather than merely harmless.
    .sheet(isPresented: isEditingField, onDismiss: { snapRPEToScale() }) {
      if let editing { padSheet(for: editing) }
    }
    // Reseeded when the unit changes, because `@State` is initialised once per view identity: the
    // suffix switched to "kg" while the number stayed in pounds, so a 60 kg set read "132.28 kg".
    // Editing that row would then have written 132.28 kg to storage — a wrong number the user
    // never typed. The draft is canonical kilograms, so reseeding from it is always correct.
    .onChange(of: unit) { reseedBuffers() }
    // And reseeded when the draft is replaced from *outside* the row. Changing the machine
    // re-prefills every unlogged row's draft (`ExerciseLogState.changeMachine`), but view identity
    // is keyed on the slot id, so `@State` survived it: the row went on displaying the old
    // machine's load while the commit wrote the new machine's — the display-versus-record
    // divergence this whole file exists to prevent.
    //
    // The `lastPushed` guard is load-bearing, not defensive. The row's own keystrokes come back
    // through this same binding, and an unguarded reseed would rebuild the buffer on every digit,
    // destroying an in-progress "62." the moment it was typed.
    .onChange(of: draft) { _, new in
      if new != lastPushed { reseedBuffers() }
    }
  }

  /// Whether any field is being edited, as something the sheet can be dismissed through.
  ///
  /// Only the false direction is written: the sheet never turns itself on, and a swipe-down sets
  /// this to false, which is exactly "stop editing".
  private var isEditingField: Binding<Bool> {
    Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })
  }

  /// Rebuilds both display buffers from the draft, in the current unit.
  private func reseedBuffers() {
    weightBuffer = NumericEntryBuffer(
      value: draft.weightKg.map(unit.displayValue(fromKilograms:)),
      maximumIntegerDigits: 4,
      maximumFractionDigits: 2
    )
    repsBuffer = NumericEntryBuffer(
      value: draft.reps.map(Double.init),
      allowsDecimal: false,
      maximumIntegerDigits: 3,
      maximumFractionDigits: 0
    )
    rpeBuffer = NumericEntryBuffer(
      value: draft.rpe,
      maximumIntegerDigits: 2,
      maximumFractionDigits: 1
    )
  }

  // MARK: - Layouts

  /// The dense row: five columns, which is right at normal text sizes and is what the logger is
  /// designed around.
  private var compactRow: some View {
    HStack(spacing: Tokens.Spacing.regular) {
      ordinalBadge
      previousBlock
        .frame(minWidth: previousWidth, alignment: .leading)
      valueField(.weight, buffer: weightBuffer, suffix: weightSuffix)
      valueField(.reps, buffer: repsBuffer, suffix: "reps")
      if tracksRPE { valueField(.rpe, buffer: rpeBuffer, suffix: "RPE") }
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
      if tracksRPE { valueField(.rpe, buffer: rpeBuffer, suffix: "RPE") }
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
    Text(badgeText)
      .font(Tokens.Text.label.weight(.semibold))
      .monospacedDigit()
      .foregroundStyle(ordinalInk)
      .frame(minWidth: ordinalWidth, alignment: .leading)
  }

  /// A drop shows an arrow rather than a number, because it does not have one — it belongs to the
  /// set above it. Numbering it would make a set dropped twice read as sets 3, 4 and 5, which is
  /// the same inflation the counting convention exists to avoid, printed on the row.
  private var badgeText: String {
    switch kind {
    case .warmup: "W"
    case .working: String(ordinal + 1)
    case .drop: "↓"
    }
  }

  private var isWarmup: Bool { kind == .warmup }

  /// A logged row recedes, and the next row is left as the brightest thing on screen.
  ///
  /// Most loggers do the opposite -- they light up what is finished -- and the result is a screen
  /// that gets louder as the session fills. Attention belongs on the set being worked on.
  private var ordinalInk: SwiftUI.Color {
    if isLogged { return Tokens.Color.textSecondary }
    // A drop is dimmed like a warm-up rather than lit like a working set: both are rows the
    // set count does not include, and the badge is the one place that can say so at a glance.
    return kind.countsAsWorkingSet ? Tokens.Color.textPrimary : Tokens.Color.textSecondary
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

  /// A zero on a bodyweight movement is a real value, so it renders as "Body" rather than "0".
  ///
  /// An *empty* field is an em dash even on a bodyweight movement, and the distinction matters: a
  /// cleared weight field used to read "Body" too, which is pixel-identical to a valid zero — so
  /// the row said "complete bodyweight set" while `weightKg` was nil, `isLoggable` was false and
  /// the commit control sat dimmed with no visible cause.
  ///
  /// Locale conversion happens here rather than in the buffer. The buffer stores a period the way
  /// the store keeps kilograms: one canonical form, converted at the presentation edge.
  private func displayText(for field: SetRowField, buffer: NumericEntryBuffer) -> String {
    if buffer.isEmpty { return "\u{2014}" }
    if field == .weight, isBodyweight, buffer.value == 0 { return "Body" }
    return buffer.displayText.replacingOccurrences(
      of: ".",
      with: Locale.current.decimalSeparator ?? "."
    )
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
        // Suppressed while the field reads "Body": "Body + kg" is not a thing. An *emptied*
        // bodyweight field keeps its suffix, so it reads "— + kg" like every other empty field
        // rather than a bare dash with no unit and no visible reason the commit control is dimmed.
        if !(field == .weight && isBodyweight && !buffer.isEmpty && buffer.value == 0) {
          Text(suffix)
            .font(Tokens.Text.caption)
            .foregroundStyle(Tokens.Color.textSecondary)
        }
      }
      .frame(maxWidth: .infinity, minHeight: Tokens.loggerTapTarget)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    // A logged row's fields do not open the pad. The pad writes straight into the draft, and
    // `SessionCoordinator.logSet` refuses a second write to an already-logged slot -- so a tap here
    // left the row displaying a number the database does not hold, beside a check mark. Editing a
    // written set goes through "Take this set back" and a fresh log, which is the only route that
    // actually reaches storage.
    .disabled(isLogged)
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
    Button(action: toggleLoggedState) {
      Image(systemName: isLogged ? "checkmark.circle.fill" : "circle")
        .font(Tokens.Text.glyph)
        // The check replaces the circle rather than cross-fading into it. `.offUp` reads as the
        // set being put away, which is what just happened. Under Reduce Motion the glyph simply
        // changes -- `.identity`, not a shorter travel, because the travel is the thing being asked
        // about.
        .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace.offUp))
        .frame(width: Tokens.loggerTapTarget, height: Tokens.loggerTapTarget)
        .contentShape(Rectangle())
    }
    // Not `.plain`: this is the app's signature interaction and it has to respond to the finger
    // landing, not to the finger leaving. See `CommitButtonStyle`.
    .buttonStyle(CommitButtonStyle(intensity: loadFraction))
    .foregroundStyle(isLogged ? Tokens.Color.certainty(.high) : Tokens.Color.accent)
    // A checked circle is a toggle in every other iOS list. Tapping it again now takes the set
    // back instead of trying the already-completed log write a second time and appearing dead.
    // An unavailable undo is disabled; an unlogged row uses the same predicate the store enforces.
    .disabled(isLogged ? onUnlog == nil : !draft.isLoggable)
    .opacity(draft.isLoggable || isLogged ? 1 : 0.35)
    // Haptics confirm the tap landed without the user looking at the phone.
    .sensoryFeedback(.success, trigger: isLogged) { !$0 && $1 }
    // The un-log direction, which the haptics table had listed as having no host.
    .sensoryFeedback(.impact(weight: .light), trigger: isLogged) { $0 && !$1 }
  }

  private func toggleLoggedState() {
    if isLogged {
      onUnlog?()
    } else if draft.isLoggable {
      onLog()
    }
  }

  private func padSheet(for field: SetRowField) -> some View {
    let binding: Binding<NumericEntryBuffer>
    switch field {
    case .weight:
      binding = Binding(get: { weightBuffer }, set: { weightBuffer = $0; pushToDraft() })
    case .reps:
      binding = Binding(get: { repsBuffer }, set: { repsBuffer = $0; pushToDraft() })
    case .rpe:
      binding = Binding(get: { rpeBuffer }, set: { rpeBuffer = $0; pushToDraft() })
    }

    return NumericPad(buffer: binding, step: step(for: field)) {
      editing = nil
      // Snapped on dismissal, not while typing: the effort scale runs in half points, so
      // `validatedRPE` rounds 8.3 to 8.5 -- and the row went on showing 8.3, a number the database
      // does not hold. Snapping mid-keystroke would fight a lifter part-way through "8.5".
      if field == .rpe { snapRPEToScale() }
    }
      .presentationDetents([.height(padHeight)])
      // The row stays visible and tappable behind the pad, so this reads as a keyboard
      // replacement rather than a modal that interrupts the set.
      #if os(iOS)
        .presentationBackgroundInteraction(.enabled(upThrough: .height(padHeight)))
      #endif
  }

  /// How tall the pad sheet has to be: the readout, the step row, four key rows, and Done.
  ///
  /// Derived rather than guessed, so the sheet tracks the text size instead of clipping at it.
  private var padHeight: CGFloat {
    let rows: CGFloat = 7
    return rows * padRowHeight
      + (rows - 1) * Tokens.Spacing.snug
      + 2 * Tokens.Spacing.regular
  }

  /// The step for each field. Reps move by one and effort by half a point, which are the only
  /// increments those scales have; a load's step depends on the equipment and comes from the caller.
  private func step(for field: SetRowField) -> Double? {
    switch field {
    case .weight: loadStep
    case .reps: 1
    case .rpe: 0.5
    }
  }

  /// Rewrites the effort field as the value that will actually be stored.
  ///
  /// The alternative is a row that disagrees with its own record, which is the same class of defect
  /// as a prefill no gym can load.
  private func snapRPEToScale() {
    // An effort outside 1...10 -- 95, or 0 -- is what `validatedRPE` returns nil for, and nil is
    // exactly what the write then persists. Clearing both sides together makes the row read "—",
    // which is the record. Clamping 95 to 10 would be the other thing: a number nobody typed.
    // Through `pushToDraft` rather than assigning `draft.rpe` directly, so `lastPushed` keeps up:
    // an unrecorded write comes back through the binding as an outside change and reseeds every
    // buffer, which would take an in-progress "62." in the weight field down with it.
    guard let snapped = draft.validatedRPE else {
      rpeBuffer.clear()
      pushToDraft()
      return
    }
    rpeBuffer = rpeBuffer.replacingValue(snapped)
  }

  // MARK: - Wiring

  /// Writes both buffers into the draft, converting display units back to canonical
  /// kilograms. There is no `?? 0` here and there must never be one: an empty buffer's value
  /// is `nil`, which makes the row not loggable, which is the correct outcome.
  private func pushToDraft() {
    draft.weightKg = weightBuffer.value.map(unit.toKilograms)
    draft.reps = repsBuffer.value.map { Int($0) }
    // No `?? 0` here either: an untouched effort field means no RPE, not an RPE of zero.
    draft.rpe = rpeBuffer.value
    // Recorded so the reseed above can tell the row's own writes from someone else's. Without
    // this every keystroke would look like an outside change and rebuild the buffer under the
    // typing finger.
    lastPushed = draft
  }

  private var previousDescription: String {
    guard let previous else { return "—" }
    let weight = unit.fromKilograms(previous.weightKg)
    return "\(Self.format(weight)) \(unit.abbreviation) × \(previous.reps)"
  }

  /// How the row opens when read aloud.
  ///
  /// A drop names what it continues. Without that a chain reads as three sets at falling loads
  /// with no explanation, which is exactly the reading the badge exists to prevent for sighted
  /// users.
  private var spokenKind: String {
    switch kind {
    case .warmup: "Warm-up set"
    case .working: "Set \(ordinal + 1)"
    case .drop: "Drop set, continuing set \(ordinal + 1)"
    }
  }

  /// Each field speaks for itself.
  ///
  /// This was all-or-nothing: a row with a weight and no reps read "no values entered" while the
  /// weight sat on screen next to it, and the effort column was never spoken at all -- the row is
  /// one combined element, so if the label omits a value nothing else says it.
  private var spokenLabel: String {
    var parts: [String] = [spokenKind]
    if let weight = weightBuffer.value {
      // "Body" matches what the row shows; "0 kg" on a pull-up is a different claim.
      parts.append(
        isBodyweight && weight == 0
          ? "Body"
          : "\(Self.format(weight)) \(unit.abbreviation)"
      )
    } else {
      parts.append("no weight entered")
    }
    if let reps = repsBuffer.value {
      // Inflected here and not in the column suffix beside the field, which is a fixed label
      // rather than a sentence.
      parts.append("\(Int(reps)) \(Int(reps) == 1 ? "rep" : "reps")")
    } else {
      parts.append("no reps entered")
    }
    if tracksRPE, let rpe = rpeBuffer.value {
      parts.append("effort \(Self.format(rpe))")
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

  /// At most one fraction digit, in the reader's locale.
  ///
  /// `String(format: "%.1f")` is POSIX-locale, so on a comma locale the "Last time" line printed
  /// "62.5" directly beside the "62,5" the lifter had just typed on the pad. The precision spec
  /// drops a zero fraction on its own, so the integer case needs no branch.
  private static func format(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...1)))
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
