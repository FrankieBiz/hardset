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
      Text(buffer.isEmpty ? "—" : buffer.displayText)
        .font(Tokens.Text.hero)
        .foregroundStyle(buffer.isEmpty ? Tokens.Color.textSecondary : Tokens.Color.textPrimary)
        .lineLimit(1)
        // A readout must show the whole number: at the largest text sizes it scales down rather
        // than clip "1002.5" to "100…". The row's own field keeps the full-size figure.
        .minimumScaleFactor(0.5)
      if let unit {
        Text(unit)
          .font(Tokens.Text.unit)
          .foregroundStyle(Tokens.Color.textSecondary)
      }
    }
    .padding(.horizontal, Tokens.Spacing.tight)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      "\(title), \(buffer.isEmpty ? "empty" : buffer.displayText)\(unit.map { " \($0)" } ?? "")"
    )
  }

  private var adjustersRow: some View {
    HStack(spacing: Tokens.Spacing.snug) {
      ForEach(quickAdjusters, id: \.self) { delta in
        Button {
          buffer.adjust(by: delta)
        } label: {
          // A real minus sign, not a hyphen: at this size the difference is visible, and a
          // hyphen next to a plus reads as a dash.
          Text(delta > 0 ? "+\(formatDelta(delta))" : "−\(formatDelta(-delta))")
            .font(Tokens.Text.setEntry)
            .foregroundStyle(Tokens.Color.accent)
        }
        .buttonStyle(HardsetKeyStyle())
        .disabled(!isAdjusterEnabled(delta))
        .accessibilityLabel(
          delta > 0 ? "Add \(formatDelta(delta))" : "Subtract \(formatDelta(-delta))"
        )
      }
    }
  }

  private func formatDelta(_ delta: Double) -> String {
    delta == delta.rounded() ? String(Int(delta)) : String(format: "%.1f", delta)
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
    case .digit(let value): buffer.append(digit: value)
    case .decimal: buffer.appendDecimalSeparator()
    case .disabledDecimal: break
    case .delete: buffer.deleteBackward()
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
