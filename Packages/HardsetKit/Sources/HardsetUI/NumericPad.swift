import Accessibility
import HardsetCore
import SwiftUI

/// The logger's only text input, docked at the bottom of the session screen.
///
/// There is no `TextField` anywhere in the logging path, so there is no system keyboard: it
/// covers half a small screen, it needs a dismiss gesture the user's other hand is not free to
/// make, and it puts the digits in a different place depending on hardware. One pad, always in
/// the same place, with 56 pt keys.
///
/// It used to be a 360 pt sheet over the row it edited. It is now the screen's bottom inset, so
/// the row stays in view above it while the lifter types.
///
/// It edits a `SetEntryKeypad`, whose fields are `NumericEntryBuffer`s rather than `Double`s:
/// that is what keeps "nothing typed" distinct from "zero" all the way to the database. Every rule
/// about what a key does lives there and is tested in Core; this view only lays the keys out.
public struct NumericPad: View {
  /// What the bottom-right key says. The caller decides what pressing it does.
  public enum Commit: Hashable, Sendable {
    /// Weight → reps.
    case next
    /// Close the pad. The row keeps what was typed.
    case done
    /// Write a correction to a logged set.
    case save
  }

  @Binding private var keypad: SetEntryKeypad
  private let commit: Commit
  private let onCommit: () -> Void
  private let onDismiss: () -> Void

  // Key height and the close target scale with the type, capped so the four rows of keys never
  // cover the row being edited at the largest sizes. Both stay at or above 44 pt.
  @ScaledMetric(relativeTo: .title3) private var scaledKeyHeight: CGFloat = Tokens.loggerTapTarget
  @ScaledMetric(relativeTo: .body) private var closeTarget: CGFloat = Tokens.minimumTapTarget

  private var keyHeight: CGFloat { min(scaledKeyHeight, 88) }

  public init(
    keypad: Binding<SetEntryKeypad>,
    commit: Commit,
    onCommit: @escaping () -> Void,
    onDismiss: @escaping () -> Void
  ) {
    self._keypad = keypad
    self.commit = commit
    self.onCommit = onCommit
    self.onDismiss = onDismiss
  }

  /// Four by four, in a fixed order. Keys change what they say between fields, never where they
  /// are, so nothing moves under the lifter's thumb.
  private var keys: [[Key]] {
    [
      [.digit(1), .digit(2), .digit(3), .stepDown],
      [.digit(4), .digit(5), .digit(6), .stepUp],
      [.digit(7), .digit(8), .digit(9), .clear],
      // The decimal key is rendered but inert for integer fields (reps), rather than absent:
      // a grid that changes shape between fields moves the other keys under the user's thumb.
      [keypad.focused.allowsDecimal ? .decimal : .disabledDecimal, .digit(0), .delete, .commit],
    ]
  }

  public var body: some View {
    VStack(spacing: Tokens.Spacing.snug) {
      header
      ForEach(Array(keys.enumerated()), id: \.offset) { _, row in
        HStack(spacing: Tokens.Spacing.snug) {
          ForEach(row) { key in
            keyButton(key)
          }
        }
      }
    }
    .padding(Tokens.Spacing.regular)
    // Opaque, not glass. Glass cannot sample glass, and a translucent keypad over a dense set
    // grid is unreadable in a bright gym besides.
    .background(Tokens.Color.surface)
  }

  // MARK: - Header

  /// Names the field being typed into and shows the whole set as it will be saved, so the lifter
  /// can check the number without looking up at the row.
  private var header: some View {
    HStack(spacing: Tokens.Spacing.snug) {
      VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
        Text(fieldName)
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.textSecondary)
        Text(keypad.composedText())
          .font(Tokens.Text.readout)
          .foregroundStyle(Tokens.Color.textPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.6)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .combine)
      // "kg" and "×" read badly aloud; the spoken form names the unit and the reps.
      .accessibilityLabel(keypad.spokenValue())
      // Typing is silent otherwise: VoiceOver says the value as it is composed. The pad's
      // `focused.text` changes on every key and on the step keys, never on a no-op.
      .onChange(of: keypad.focused.text) {
        AccessibilityNotification.Announcement(keypad.spokenValue()).post()
      }

      Button(action: onDismiss) {
        Image(systemName: "chevron.down")
          .font(Tokens.Text.label.weight(.semibold))
          .frame(width: max(keyHeight, Tokens.loggerTapTarget), height: closeTarget)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .foregroundStyle(Tokens.Color.accent)
      .accessibilityLabel("Close keypad")
    }
  }

  private var fieldName: String {
    keypad.field == .weight ? "Weight" : "Reps"
  }

  // MARK: - Keys

  private func keyButton(_ key: Key) -> some View {
    Button {
      apply(key)
    } label: {
      label(for: key)
        .font(keyFont(for: key))
        .lineLimit(1)
        // "−11.02" on a quarter-width key in pounds: shrink rather than wrap.
        .minimumScaleFactor(0.6)
        .frame(maxWidth: .infinity, minHeight: keyHeight)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    // Drawn as disabled explicitly; the plain style is not relied on to dim a disabled label.
    .foregroundStyle(isEnabled(key) ? Tokens.Color.textPrimary : Tokens.Color.textSecondary)
    .disabled(!isEnabled(key))
    .opacity(key == .disabledDecimal ? 0 : 1)
    // Invisible and inert, so VoiceOver must not land on a "Decimal point" that is not there.
    .accessibilityHidden(key == .disabledDecimal)
    .background(
      key == .commit ? Tokens.Color.accent.opacity(0.15) : Tokens.Color.background,
      in: RoundedRectangle(cornerRadius: Tokens.Radius.control)
    )
    .accessibilityLabel(accessibilityLabel(for: key))
    // No haptic on any key: a keypress is the most frequent action in the app, and it stays quiet.
  }

  @ViewBuilder private func label(for key: Key) -> some View {
    switch key {
    case .digit(let value): Text(String(value))
    case .decimal, .disabledDecimal: Text(decimalSeparator)
    case .delete: Image(systemName: "delete.backward")
    case .stepDown: Text(stepLabel(.down))
    case .stepUp: Text(stepLabel(.up))
    case .clear: Text("Clear")
    case .commit: Text(commitTitle)
    }
  }

  private func keyFont(for key: Key) -> Font {
    switch key {
    case .clear, .commit: Tokens.Text.label.weight(.semibold)
    default: Tokens.Text.readout
    }
  }

  /// ± only moves a value that exists. An empty field stays empty, so the step keys are off: a
  /// step that invented a load would be a `?? 0` with extra steps.
  private func isEnabled(_ key: Key) -> Bool {
    switch key {
    case .stepDown, .stepUp: keypad.focused.value != nil
    case .disabledDecimal: false
    default: true
    }
  }

  /// The machine's real increment on weight, in the unit the lifter reads ("+2.5", "+11.02");
  /// one rep on reps.
  private func stepLabel(_ direction: SetEntryKeypad.Direction) -> String {
    let sign = direction == .up ? "+" : "−"
    switch keypad.field {
    case .weight:
      return sign + keypad.loadStep.amount.formatted(.number.precision(.fractionLength(0...2)))
    case .reps:
      return sign + "1"
    }
  }

  private var commitTitle: String {
    switch commit {
    case .next: "Next"
    case .done: "Done"
    case .save: "Save"
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
    case .clear: "Clear"
    case .commit: commitTitle
    // "Add 2.5 kilograms", "One more rep": Core's sentences, units in full.
    case .stepDown: keypad.spokenStep(.down)
    case .stepUp: keypad.spokenStep(.up)
    }
  }

  private func apply(_ key: Key) {
    switch key {
    case .digit(let value): keypad.type(digit: value)
    case .decimal: keypad.typeDecimalSeparator()
    case .disabledDecimal: break
    case .delete: keypad.deleteBackward()
    case .clear: keypad.clear()
    case .stepDown: keypad.step(.down)
    case .stepUp: keypad.step(.up)
    case .commit: onCommit()
    }
  }

  private enum Key: Hashable, Identifiable {
    case digit(Int)
    case decimal
    /// Occupies the decimal key's slot without acting, so the grid never reflows.
    case disabledDecimal
    case delete
    case stepDown
    case stepUp
    case clear
    case commit

    var id: String {
      switch self {
      case .digit(let value): "d\(value)"
      case .decimal: "sep"
      case .disabledDecimal: "sep-off"
      case .delete: "del"
      case .stepDown: "step-down"
      case .stepUp: "step-up"
      case .clear: "clear"
      case .commit: "commit"
      }
    }
  }
}
