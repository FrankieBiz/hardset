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
      // Trailing ".0" is noise on a set row: 60, not 60.0.
      seed = value == value.rounded() ? String(Int(value)) : String(value)
    case .some(let value):
      seed = String(Int(value.rounded()))
    }
    self.init(
      text: seed,
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
    guard !text.isEmpty, text != "." else { return nil }
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
