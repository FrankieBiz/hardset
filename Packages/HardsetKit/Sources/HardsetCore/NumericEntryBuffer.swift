import Foundation

/// The edit state behind the logger's keypad.
///
/// This exists as a pure value type, outside any view, for one reason: it is exactly where the
/// missing-versus-zero bug comes back. A `TextField` bound to a `Double` needs a
/// `Double(text) ?? 0` somewhere, and that `?? 0` is the reference app's defect — a row the
/// user never touched persisting as 0 kg. Here an empty buffer's `value` is `nil`, there is no
/// coercion anywhere, and the rule is unit-tested rather than trusted to a view.
///
/// It also removes the system keyboard from the logger entirely. Sweaty hands at arm's length
/// from a rack do not want a keyboard that covers half the screen and needs a Done button.
public struct NumericEntryBuffer: Hashable, Sendable {
  /// The literal characters typed so far. Never normalised behind the user's back — what they
  /// see is what is here.
  public private(set) var text: String
  public let allowsDecimal: Bool
  public let maximumIntegerDigits: Int
  public let maximumFractionDigits: Int

  public init(
    text: String = "",
    allowsDecimal: Bool = true,
    maximumIntegerDigits: Int = 4,
    maximumFractionDigits: Int = 2
  ) {
    self.text = text
    self.allowsDecimal = allowsDecimal
    self.maximumIntegerDigits = maximumIntegerDigits
    self.maximumFractionDigits = maximumFractionDigits
  }

  /// Seeds the buffer from a prefill value.
  ///
  /// A `nil` value yields an empty buffer — which is not loggable — rather than "0". This is
  /// the prefill contract: either a real suggested value is committed here, or the row is
  /// genuinely blank and the log control stays disabled.
  public init(
    value: Double?,
    allowsDecimal: Bool = true,
    maximumIntegerDigits: Int = 4,
    maximumFractionDigits: Int = 2
  ) {
    let seed: String
    switch value {
    case .none:
      seed = ""
    case .some(let value) where allowsDecimal:
      // Rounded to what this buffer can actually hold. Seeding `String(value)` printed the raw
      // double, so a 60 kg set displayed in pounds read as "132.277357310926 53" and wrapped
      // across four lines of the row — the conversion is exact, the *display* was not truncated.
      seed = Self.seedText(value, fractionDigits: maximumFractionDigits)
    case .some(let value):
      seed = Self.seedText(value, fractionDigits: 0)
    }
    self.init(
      text: seed,
      allowsDecimal: allowsDecimal,
      maximumIntegerDigits: maximumIntegerDigits,
      maximumFractionDigits: maximumFractionDigits
    )
  }

  /// Formats a prefill to at most `fractionDigits`, with no trailing zeros.
  ///
  /// Uses `String(format:)` rather than an `Int` conversion so a large value cannot trap, and
  /// trims so trailing ".0" never appears on a set row: 60, not 60.0.
  private static func seedText(_ value: Double, fractionDigits: Int) -> String {
    var text = String(format: "%.\(max(0, fractionDigits))f", value)
    guard text.contains(".") else { return text }
    while text.hasSuffix("0") { text.removeLast() }
    if text.hasSuffix(".") { text.removeLast() }
    return text
  }

  /// The same field, holding a different number.
  ///
  /// Exists so a stepper can move the value without knowing how the field was configured. Rebuilding
  /// the buffer by hand at the call site is how `allowsDecimal` gets dropped and a reps field starts
  /// accepting a decimal point.
  public func replacingValue(_ value: Double?) -> NumericEntryBuffer {
    NumericEntryBuffer(
      value: value,
      allowsDecimal: allowsDecimal,
      maximumIntegerDigits: maximumIntegerDigits,
      maximumFractionDigits: maximumFractionDigits
    )
  }

  /// The number entered, or `nil` when nothing usable has been typed.
  ///
  /// Deliberately not `Double`. There is no zero default, because "no weight entered" and
  /// "zero added load" are different facts and must not share a representation.
  public var value: Double? {
    // "0." is an incomplete entry, not zero.
    //
    // The old guard tested for a bare ".", which `appendDecimalSeparator` never produces -- it
    // writes "0." so a leading separator is readable on a dense row. So the guard was dead and the
    // hole it existed to close was open: one tap of the separator on an empty weight field made the
    // field worth 0.0, and because reps are prefilled from history, that single tap was enough to
    // make the row loggable. A barbell bench press could be written at 0 kg by one stray tap --
    // exactly the missing-versus-zero defect this whole type exists to prevent.
    //
    // Nothing is lost by refusing it. A lifter who means zero types "0" and stops, which still
    // reads as zero; a lifter part-way through "0.5" has not finished entering anything yet.
    guard !text.isEmpty, text != ".", text != "0." else { return nil }
    return Double(text)
  }

  public var isEmpty: Bool { text.isEmpty }

  /// What to show when nothing has been typed. Empty, not "0" — a zero on screen invites the
  /// user to believe a value is present.
  public var displayText: String { text }

  public mutating func append(digit: Int) {
    guard (0...9).contains(digit) else { return }
    // A single leading zero is meaningful ("0.5"); a second one is not.
    if text == "0" { text = String(digit); return }

    if let separatorIndex = text.firstIndex(of: ".") {
      let fraction = text.distance(from: text.index(after: separatorIndex), to: text.endIndex)
      guard fraction < maximumFractionDigits else { return }
    } else {
      guard text.count < maximumIntegerDigits else { return }
    }
    text.append(String(digit))
  }

  public mutating func appendDecimalSeparator() {
    guard allowsDecimal, !text.contains(".") else { return }
    // Leading "." is ambiguous to read on a dense row; make it explicit.
    text = text.isEmpty ? "0." : text + "."
  }

  public mutating func deleteBackward() {
    guard !text.isEmpty else { return }
    text.removeLast()
  }

  public mutating func clear() { text = "" }
}
