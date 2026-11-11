import HardsetCore
import SwiftUI

/// The logger's only text input.
///
/// There is no `TextField` anywhere in the logging path, so there is no system keyboard: it
/// covers half a small screen, it needs a dismiss gesture the user's other hand is not free to
/// make, and it puts the digits in a different place depending on hardware. One pad, always in
/// the same place, with 56 pt keys.
///
/// It edits a `NumericEntryBuffer` rather than a `Double`, which is what keeps "nothing typed"
/// distinct from "zero" all the way to the database.
///
/// The pad shows the value it is editing in its own display, at the largest figure size in the
/// app. The set row is still visible behind it, but a lifter typing between sets should not have
/// to look past the keys to check what they typed.
public struct NumericPad: View {
  @Binding private var buffer: NumericEntryBuffer
  private let title: String?
  private let context: String?
  private let unit: String?
  private let restEndsAt: Date?
  private let doneTitle: String
  private let isDoneEnabled: Bool
  private let onDone: (() -> Void)?
  private let onNext: (() -> Void)?
  private let onLog: (() -> Void)?
  private let canLog: Bool

  @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  /// Moved to the display when the pad changes field, so a VoiceOver user who pressed Next hears
  /// which value they are now entering instead of losing their place when Next is replaced.
  @AccessibilityFocusState private var isDisplayFocused: Bool

  /// - Parameter title: What is being edited, such as "Weight". `nil` hides the display.
  /// - Parameter context: Which set the value belongs to, such as "Leg Press · Set 2". The pad
  ///   covers the lower half of the screen, so the row it edits may be out of sight; this line is
  ///   how the lifter knows the digits are going where they mean them to.
  /// - Parameter unit: Drawn beside the value in the display, such as "kg" or "reps".
  /// - Parameter restEndsAt: A running rest's deadline. The rest bar sits under the pad while it
  ///   is up, so the countdown is repeated in the display rather than hidden for the whole entry.
  /// - Parameter doneTitle: The single footer action's title, for a pad whose Done commits, such
  ///   as the load-step editor's "Save load step".
  /// - Parameter isDoneEnabled: Disables that action while the value cannot be committed, so a
  ///   tap that would do nothing looks like it does nothing.
  /// - Parameter onLog: Puts "Log set" beside Done on the last field of a set, so a changed set
  ///   is entered and logged without a separate trip back to the row's check.
  /// - Parameter canLog: Whether the set is complete. The same `SetEntryDraft.isLoggable` the
  ///   row's check uses; the pad never decides that on its own.
  public init(
    buffer: Binding<NumericEntryBuffer>,
    title: String? = nil,
    context: String? = nil,
    unit: String? = nil,
    restEndsAt: Date? = nil,
    doneTitle: String = "Done",
    isDoneEnabled: Bool = true,
    onDone: (() -> Void)? = nil,
    onNext: (() -> Void)? = nil,
    onLog: (() -> Void)? = nil,
    canLog: Bool = false
  ) {
    self._buffer = buffer
    self.title = title
    self.context = context
    self.unit = unit
    self.restEndsAt = restEndsAt
    self.doneTitle = doneTitle
    self.isDoneEnabled = isDoneEnabled
    self.onDone = onDone
    self.onNext = onNext
    self.onLog = onLog
    self.canLog = canLog
  }

  private var quickAdjusters: [Double] {
    buffer.allowsDecimal ? [-5.0, -2.5, 2.5, 5.0] : [-1.0, 1.0, 2.0]
  }

  /// A step that would invent a value or overflow the field is disabled rather than applied.
  ///
  /// Subtracting from an empty field used to write "0", which reads as a value and made the row
  /// loggable at a load nobody typed. Adding past the field's digit limit produced a number the
  /// keys themselves could never enter.
  private func isAdjusterEnabled(_ delta: Double) -> Bool {
    if delta < 0 { return buffer.value != nil }
    let limit = (0..<buffer.maximumIntegerDigits).reduce(1.0) { power, _ in power * 10 }
    return (buffer.value ?? 0) + delta < limit
  }

  private var keys: [[Key]] {
    [
      [.digit(1), .digit(2), .digit(3)],
      [.digit(4), .digit(5), .digit(6)],
      [.digit(7), .digit(8), .digit(9)],
      // The decimal key is rendered but inert for integer fields (reps), rather than absent:
      // a grid that changes shape between fields moves the other keys under the user's thumb.
      [buffer.allowsDecimal ? .decimal : .disabledDecimal, .digit(0), .delete],
    ]
  }

  public var body: some View {
    VStack(spacing: Tokens.Spacing.snug) {
      if context != nil || restEndsAt != nil {
        contextLine
      }
      if let title {
        display(title: title)
      }

      adjustersRow

      ForEach(keys, id: \.self) { row in
        HStack(spacing: Tokens.Spacing.snug) {
          ForEach(row) { key in
            keyButton(key)
          }
        }
      }
      footerActions
    }
    .padding(.horizontal, Tokens.Spacing.regular)
    .padding(.top, Tokens.Spacing.loose)
    .padding(.bottom, Tokens.Spacing.regular)
    // Opaque, not glass. Glass cannot sample glass, and a translucent keypad over a dense set
    // grid is unreadable in a bright gym besides.
    .background(Tokens.Color.surface)
    .onChange(of: title) {
      if voiceOverEnabled { isDisplayFocused = true }
    }
  }

  /// A prefilled value the next digit or separator will replace, as selected text would be.
  private var replacesPrefill: Bool {
    buffer.replaceOnFirstEntry && !buffer.isEmpty
  }

  /// The value as VoiceOver should say it: no dangling separator, and the unit.
  private func spokenValue(_ buffer: NumericEntryBuffer) -> String {
    guard !buffer.isEmpty else { return "empty" }
    var text = buffer.displayText
    if text.hasSuffix(".") { text.removeLast() }
    return LoadFigure.typed(text) + (unit.map { " \($0)" } ?? "")
  }

  /// Says what a key did. The keys are labelled "1" or "Delete", and the value lives in the
  /// display, so without this a VoiceOver user had to swipe back to the display after every key
  /// to learn what had been entered, or that the first digit had replaced the prefill.
  private func announceChange(from before: NumericEntryBuffer, to after: NumericEntryBuffer) {
    guard voiceOverEnabled, before.text != after.text else { return }
    let now = spokenValue(after)
    let replaced = before.replaceOnFirstEntry && !before.isEmpty && !after.replaceOnFirstEntry
    AccessibilityNotification.Announcement(
      replaced ? "Replaced \(spokenValue(before)). \(now)" : now
    ).post()
  }

  /// Applies an edit through the binding and announces its result.
  private func edit(_ change: (inout NumericEntryBuffer) -> Void) {
    let before = buffer
    var after = buffer
    change(&after)
    buffer = after
    announceChange(from: before, to: after)
  }

  /// Which set is being edited, and the rest still running, on one line above the value.
  private var contextLine: some View {
    HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.snug) {
      if let context {
        Text(context)
          .font(Tokens.Text.sectionHeader)
          .foregroundStyle(Tokens.Color.textPrimary)
          .lineLimit(2)
          // Spoken as one phrase, movement first: "Leg Press, Set 2".
          .accessibilityLabel(context.replacingOccurrences(of: " · ", with: ", "))
      }
      Spacer(minLength: Tokens.Spacing.snug)
      if let restEndsAt {
        HStack(spacing: Tokens.Spacing.tight) {
          Image(systemName: "timer")
            .accessibilityHidden(true)
          // System-rendered from the deadline, like the rest bar it stands in for.
          Text(timerInterval: Date()...max(restEndsAt, Date()), countsDown: true)
            .lineLimit(1)
            .fixedSize()
        }
        .font(Tokens.Text.figure)
        .foregroundStyle(Tokens.Color.accent)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Resting")
      }
    }
    .padding(.horizontal, Tokens.Spacing.tight)
  }

  /// The value being typed, as large as anything in the app, with what it is and its unit.
  private func display(title: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.snug) {
      Text(title)
        .font(Tokens.Text.sectionHeader)
        .foregroundStyle(Tokens.Color.textSecondary)
      Spacer(minLength: Tokens.Spacing.snug)
      // An empty buffer shows an em dash, never "0": nothing typed is not a value.
      Text(buffer.isEmpty ? "—" : LoadFigure.typed(buffer.displayText))
        .font(Tokens.Text.hero)
        .foregroundStyle(buffer.isEmpty ? Tokens.Color.textSecondary : Tokens.Color.textPrimary)
        .lineLimit(1)
        // A readout must show the whole number: at the largest text sizes it scales down rather
        // than clip "1002.5" to "100…". The row's own field keeps the full-size figure.
        .minimumScaleFactor(0.5)
        // Padded whether or not it is highlighted, so the highlight never moves the figure.
        .padding(.horizontal, Tokens.Spacing.snug)
        .background {
          // A prefill the next key will replace is drawn as selected, the way iOS marks text
          // about to be typed over. Pressing "." on a highlighted "100" then reads as starting a
          // new number, not as a bug that turned 100 into "0.". Static: nothing animates.
          if replacesPrefill {
            let shape = RoundedRectangle(cornerRadius: Tokens.Radius.control - Tokens.Spacing.tight)
            shape
              .fill(Tokens.Color.accentSurface)
              .overlay(shape.strokeBorder(Tokens.Color.accent, lineWidth: Tokens.Stroke.hairline))
          }
        }
      if let unit {
        Text(unit)
          .font(Tokens.Text.unit)
          .foregroundStyle(Tokens.Color.textSecondary)
      }
    }
    .padding(.horizontal, Tokens.Spacing.tight)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(title), \(spokenValue(buffer))")
    .accessibilityHint(replacesPrefill ? "The next digit you type replaces this value." : "")
    .accessibilityFocused($isDisplayFocused)
  }

  /// One row of quick steps at ordinary sizes; two rows of two at accessibility sizes, where
  /// "−2.5" in four columns no longer fits its key and wrapped to "−2." over "5".
  @ViewBuilder private var adjustersRow: some View {
    if dynamicTypeSize.isAccessibilitySize {
      VStack(spacing: Tokens.Spacing.snug) {
        ForEach(Array(stride(from: 0, to: quickAdjusters.count, by: 2)), id: \.self) { start in
          HStack(spacing: Tokens.Spacing.snug) {
            ForEach(quickAdjusters[start..<min(start + 2, quickAdjusters.count)], id: \.self) {
              adjuster($0)
            }
          }
        }
      }
    } else {
      HStack(spacing: Tokens.Spacing.snug) {
        ForEach(quickAdjusters, id: \.self) { adjuster($0) }
      }
    }
  }

  private func adjuster(_ delta: Double) -> some View {
    let figure = formatDelta(abs(delta))
    return Button {
      edit { $0.adjust(by: delta) }
    } label: {
      // A real minus sign, not a hyphen: at this size the difference is visible, and a
      // hyphen next to a plus reads as a dash.
      Text(delta > 0 ? "+\(figure)" : "−\(figure)")
        .font(Tokens.Text.setEntry)
        .foregroundStyle(Tokens.Color.accent)
        .lineLimit(1)
    }
    .buttonStyle(HardsetKeyStyle())
    .disabled(!isAdjusterEnabled(delta))
    // Begins with what the key shows, "+2.5" read as "Plus 2.5", so a Voice Control user can say
    // what they see; the unit says what is being stepped.
    .accessibilityLabel("\(delta > 0 ? "Plus" : "Minus") \(figure)\(spokenUnit(for: delta))")
    .accessibilityInputLabels(
      delta > 0 ? ["Plus \(figure)", "Add \(figure)"] : ["Minus \(figure)", "Subtract \(figure)"]
    )
  }

  private func spokenUnit(for delta: Double) -> String {
    guard let unit else { return "" }
    if unit == "reps", abs(delta) == 1 { return " rep" }
    return " \(unit)"
  }

  private func formatDelta(_ delta: Double) -> String {
    LoadFigure.text(delta)
  }

  /// Two shapes on the logger, one elsewhere: weight offers Done and Next, the last field of a
  /// set offers Done and Log set, and a pad with only Done makes it the primary commit.
  ///
  /// Log set keeps its place whether or not the set is complete yet, and is disabled until it is,
  /// so the keys do not shift under the thumb at the moment the last digit makes it loggable.
  @ViewBuilder
  private var footerActions: some View {
    if let onDone, let onNext {
      HStack(spacing: Tokens.Spacing.snug) {
        Button(doneTitle, action: onDone)
          .buttonStyle(HardsetButtonStyle(.secondary, size: .logger))
        Button(action: onNext) {
          HStack(spacing: Tokens.Spacing.tight) {
            Text("Next")
              .lineLimit(1)
              .minimumScaleFactor(0.7)
            Image(systemName: "chevron.right")
          }
        }
        .buttonStyle(HardsetButtonStyle(.primary, size: .logger))
        .accessibilityLabel("Next field")
      }
    } else if let onDone, let onLog {
      HStack(spacing: Tokens.Spacing.snug) {
        Button(doneTitle, action: onDone)
          .buttonStyle(HardsetButtonStyle(.secondary, size: .logger))
        Button(action: onLog) {
          Label("Log set", systemImage: "checkmark")
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .buttonStyle(HardsetButtonStyle(.primary, size: .logger))
        .disabled(!canLog)
        .accessibilityLabel("Log set")
      }
    } else if let onDone {
      Button(doneTitle, action: onDone)
        .buttonStyle(HardsetButtonStyle(.primary, size: .logger))
        .disabled(!isDoneEnabled)
    }
  }

  private func keyButton(_ key: Key) -> some View {
    Button {
      apply(key)
    } label: {
      Group {
        switch key {
        case .digit(let value): Text(String(value))
        case .decimal, .disabledDecimal: Text(decimalSeparator)
        case .delete: Image(systemName: "delete.backward")
        }
      }
      .font(Tokens.Text.readout)
    }
    .buttonStyle(HardsetKeyStyle())
    .disabled(key == .disabledDecimal)
    .opacity(key == .disabledDecimal ? 0 : 1)
    .accessibilityHidden(key == .disabledDecimal)
    .accessibilityLabel(accessibilityLabel(for: key))
    .accessibilityHint(keyHint(for: key))
  }

  /// A digit or separator pressed on a highlighted prefill starts a new number; the hint says so
  /// before the key is pressed, as the highlight does.
  private func keyHint(for key: Key) -> String {
    switch key {
    case .digit, .decimal:
      replacesPrefill ? "Replaces \(spokenValue(buffer))" : ""
    case .disabledDecimal, .delete:
      ""
    }
  }

  /// The user's locale decides how a decimal point looks, even though the stored buffer is
  /// always a period.
  private var decimalSeparator: String {
    Locale.current.decimalSeparator ?? "."
  }

  private func accessibilityLabel(for key: Key) -> String {
    switch key {
    case .digit(let value): String(value)
    case .decimal, .disabledDecimal: "Decimal point"
    case .delete: "Delete"
    }
  }

  private func apply(_ key: Key) {
    switch key {
    case .digit(let value): edit { $0.append(digit: value) }
    case .decimal: edit { $0.appendDecimalSeparator() }
    case .disabledDecimal: break
    case .delete: edit { $0.deleteBackward() }
    }
  }

  private enum Key: Hashable, Identifiable {
    case digit(Int)
    case decimal
    /// Occupies the decimal key's slot without acting, so the grid never reflows.
    case disabledDecimal
    case delete

    var id: String {
      switch self {
      case .digit(let value): "d\(value)"
      case .decimal: "sep"
      case .disabledDecimal: "sep-off"
      case .delete: "del"
      }
    }
  }
}

#if DEBUG
  #Preview("Keypad, weight") {
    struct Harness: View {
      @State private var buffer = NumericEntryBuffer(
        value: 102.5, maximumIntegerDigits: 4, maximumFractionDigits: 2
      )

      var body: some View {
        NumericPad(
          buffer: $buffer, title: "Weight", context: "Leg Press · Set 2", unit: "kg",
          restEndsAt: Date().addingTimeInterval(84), onDone: {}, onNext: {}
        )
      }
    }
    return Harness()
  }

  #Preview("Keypad, reps") {
    struct Harness: View {
      @State private var buffer = NumericEntryBuffer(
        value: nil, allowsDecimal: false, maximumIntegerDigits: 3, maximumFractionDigits: 0
      )

      var body: some View {
        NumericPad(
          buffer: $buffer, title: "Reps", context: "Leg Press · Set 2", unit: "reps",
          onDone: {}, onLog: {}, canLog: false
        )
      }
    }
    return Harness()
  }
#endif
