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
public struct NumericPad: View {
  @Binding private var buffer: NumericEntryBuffer
  /// How much one press of minus or plus moves the value, in the unit on screen. `nil` hides the
  /// row -- there is no sensible step for every field, and an inert control is worse than none.
  private let step: Double?
  private let onDone: (() -> Void)?

  public init(
    buffer: Binding<NumericEntryBuffer>,
    step: Double? = nil,
    onDone: (() -> Void)? = nil
  ) {
    self._buffer = buffer
    self.step = step
    self.onDone = onDone
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
      readout
      if let step { stepRow(step) }
      ForEach(Array(keys.enumerated()), id: \.offset) { _, row in
        HStack(spacing: Tokens.Spacing.snug) {
          ForEach(row) { key in
            keyButton(key)
          }
        }
      }
      if let onDone {
        Button(action: onDone) {
          Text("Done")
            .font(Tokens.Text.label.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: Tokens.loggerTapTarget)
        }
        .buttonStyle(KeyButtonStyle(fill: Tokens.Color.accent.opacity(0.15)))
      }
    }
    .padding(Tokens.Spacing.regular)
    // Opaque, not glass. Glass cannot sample glass, and a translucent keypad over a dense set
    // grid is unreadable in a bright gym besides.
    .background(Tokens.Color.surface)
  }

  /// What has been typed so far, on the pad itself.
  ///
  /// The pad is a sheet sized to its own content, and at accessibility text sizes that content is
  /// taller than the screen -- the detent clamps, the sheet covers the row it is editing, and the
  /// value being entered was then visible nowhere at all. Stating it here makes the pad
  /// self-describing whether or not the row behind it survives.
  ///
  /// Locale separator, same as the key: the buffer stores a period the way the store keeps
  /// kilograms, converted at the presentation edge.
  private var readout: some View {
    let typed = buffer.displayText.replacingOccurrences(of: ".", with: decimalSeparator)
    return Text(buffer.isEmpty ? "\u{2014}" : typed)
      .font(Tokens.Text.readout)
      .monospacedDigit()
      .lineLimit(1)
      .minimumScaleFactor(0.6)
      .frame(maxWidth: .infinity, minHeight: Tokens.loggerTapTarget, alignment: .trailing)
      // An em dash on its own is announced as "dash", which is not what it means here.
      .accessibilityLabel(buffer.isEmpty ? "Nothing entered" : typed)
  }

  /// Minus and plus, with the step stated between them.
  ///
  /// Above the digits rather than inside the set row: the row is the densest thing in the app and
  /// already has to restack at accessibility sizes, and this is where the thumb already is while
  /// editing. Almost every load a lifter enters is the last one plus or minus one step, so this is
  /// the difference between one press and three digits, twenty-odd times a session.
  ///
  /// The step is printed, not implied. A lifter on a machine that moves in 11 lb jumps should be
  /// told that is what the button does rather than discovering it.
  @ViewBuilder private func stepRow(_ step: Double) -> some View {
    HStack(spacing: Tokens.Spacing.snug) {
      stepButton(step, presses: -1, symbol: "minus")
      Text(Self.format(step))
        .font(Tokens.Text.caption)
        .monospacedDigit()
        .foregroundStyle(Tokens.Color.textSecondary)
        .frame(minWidth: 44)
        // Spoken as part of each button instead, so it is not read as a stray number between them.
        .accessibilityHidden(true)
      stepButton(step, presses: 1, symbol: "plus")
    }
  }

  private func stepButton(_ step: Double, presses: Int, symbol: String) -> some View {
    // Nothing typed means nothing to step from. Starting a bench press at 2.5 kg because the lifter
    // pressed plus would be an invention, so the control waits rather than inventing a basis.
    let stepped = PlateMath.stepped(buffer.value, by: presses, step: step)
    return Button {
      if let stepped { buffer = buffer.replacingValue(stepped) }
    } label: {
      Image(systemName: symbol)
        .font(Tokens.Text.label.weight(.semibold))
        .frame(maxWidth: .infinity, minHeight: Tokens.loggerTapTarget)
        .contentShape(Rectangle())
    }
    .buttonStyle(KeyButtonStyle(fill: Tokens.Color.raised))
    .disabled(stepped == nil)
    .foregroundStyle(stepped == nil ? Tokens.Color.textTertiary : Tokens.Color.accent)
    .accessibilityLabel(
      presses < 0 ? "Down \(Self.format(step))" : "Up \(Self.format(step))"
    )
  }

  /// Trailing zeros trimmed: a 2.5 step reads "2.5" and a 5 step reads "5", not "5.0".
  static func format(_ value: Double) -> String {
    var text = String(format: "%.2f", value)
    while text.hasSuffix("0") { text.removeLast() }
    if text.hasSuffix(".") { text.removeLast() }
    return text
  }

  /// What VoiceOver says for a key. Digits and the separator read as themselves; the icon does not.
  private static func spokenLabel(for key: Key, decimalSeparator: String) -> String {
    switch key {
    case .digit(let value): String(value)
    case .decimal, .disabledDecimal: "Decimal point"
    case .delete: "Delete"
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
      // The glyph is hidden, not the whole key: the fill now lives inside the button style, and
      // hiding that too would leave a gap in the grid instead of the empty well the placeholder is.
      .opacity(key == .disabledDecimal ? 0 : 1)
      .frame(maxWidth: .infinity, minHeight: Tokens.loggerTapTarget)
      .contentShape(Rectangle())
    }
    .buttonStyle(KeyButtonStyle(fill: Tokens.Color.ground))
    // Delete on an empty buffer routes to a `guard !text.isEmpty else { return }` -- lit, tappable
    // and inert. Disabled and dimmed like the step keys beside it, for the same reason they are:
    // an inert control is worse than none.
    .disabled(key == .disabledDecimal || (key == .delete && buffer.isEmpty))
    .foregroundStyle(
      key == .delete && buffer.isEmpty ? Tokens.Color.textTertiary : Tokens.Color.textPrimary
    )
    // The delete key is an icon with no text, so without this VoiceOver announces the SF Symbol
    // name or nothing at all -- on the keypad used to enter every weight and every rep in the app.
    .accessibilityLabel(Self.spokenLabel(for: key, decimalSeparator: decimalSeparator))
    // Invisible *and* unreachable. The placeholder exists so the grid does not change shape between
    // an integer field and a decimal one -- which would move the other keys under the user's thumb
    // -- but at zero opacity it stayed focusable, so VoiceOver on a reps field announced a
    // "Decimal point" button that does nothing and cannot be seen.
    .accessibilityHidden(key == .disabledDecimal)
  }

  /// The user's locale decides how a decimal point looks, even though the stored buffer is
  /// always a period.
  private var decimalSeparator: String {
    Locale.current.decimalSeparator ?? "."
  }

  private func apply(_ key: Key) {
    switch key {
    case .digit(let value): buffer.append(digit: value)
    case .decimal: buffer.appendDecimalSeparator()
    case .disabledDecimal: break
    case .delete: buffer.deleteBackward()
    }
  }

  /// A pad key that answers the finger landing.
  ///
  /// `.plain` applies no pressed appearance on iOS, and the fill used to sit *outside*
  /// `configuration.label`, so no style could have animated it either -- every weight and every rep
  /// in the app was typed with nothing happening until release, against guideline M3. The fill is
  /// drawn in here so the dim covers the key rather than only the digit on top of it.
  ///
  /// No haptic: §5.8 reserves those for a committed state change, and typing a digit commits
  /// nothing.
  private struct KeyButtonStyle: ButtonStyle {
    let fill: SwiftUI.Color

    func makeBody(configuration: Configuration) -> some View {
      configuration.label
        .background(fill, in: RoundedRectangle(cornerRadius: Tokens.Radius.control))
        // The same press dim the log control uses. No scale: a 56 pt key shrinking under a thumb
        // that covers it is movement nobody sees, and Reduce Motion then has nothing to strip.
        .opacity(configuration.isPressed ? 0.82 : 1)
        .animation(Tokens.Motion.tap, value: configuration.isPressed)
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
