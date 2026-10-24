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
  private let onDone: (() -> Void)?
  private let onNext: (() -> Void)?

  public init(
    buffer: Binding<NumericEntryBuffer>,
    onDone: (() -> Void)? = nil,
    onNext: (() -> Void)? = nil
  ) {
    self._buffer = buffer
    self.onDone = onDone
    self.onNext = onNext
  }

  private var quickAdjusters: [Double] {
    buffer.allowsDecimal ? [-5.0, -2.5, 2.5, 5.0] : [-1.0, 1.0, 2.0]
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
      adjustersRow

      ForEach(Array(keys.enumerated()), id: \.offset) { _, row in
        HStack(spacing: Tokens.Spacing.snug) {
          ForEach(row) { key in
            keyButton(key)
          }
        }
      }
      footerActions
    }
    .padding(Tokens.Spacing.regular)
    // Opaque, not glass. Glass cannot sample glass, and a translucent keypad over a dense set
    // grid is unreadable in a bright gym besides.
    .background(Tokens.Color.surface)
  }

  private var adjustersRow: some View {
    HStack(spacing: Tokens.Spacing.snug) {
      ForEach(quickAdjusters, id: \.self) { delta in
        Button {
          buffer.adjust(by: delta)
        } label: {
          Text(delta > 0 ? "+\(formatDelta(delta))" : formatDelta(delta))
            .font(Tokens.Text.caption.weight(.medium))
            .foregroundStyle(Tokens.Color.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
          Tokens.Color.background,
          in: RoundedRectangle(cornerRadius: Tokens.Radius.control)
        )
      }
    }
  }

  private func formatDelta(_ delta: Double) -> String {
    delta == delta.rounded() ? String(Int(delta)) : String(format: "%.1f", delta)
  }

  @ViewBuilder
  private var footerActions: some View {
    if onNext != nil && onDone != nil {
      HStack(spacing: Tokens.Spacing.snug) {
        if let onDone {
          Button(action: onDone) {
            Text("Done")
              .font(Tokens.Text.label.weight(.semibold))
              .frame(maxWidth: .infinity, minHeight: Tokens.loggerTapTarget)
          }
          .buttonStyle(.plain)
          .background(
            Tokens.Color.background,
            in: RoundedRectangle(cornerRadius: Tokens.Radius.control)
          )
        }
        if let onNext {
          Button(action: onNext) {
            HStack(spacing: Tokens.Spacing.tight) {
              Text("Next")
              Image(systemName: "chevron.right")
            }
            .font(Tokens.Text.label.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: Tokens.loggerTapTarget)
          }
          .buttonStyle(.plain)
          .background(
            Tokens.Color.accent.opacity(0.15),
            in: RoundedRectangle(cornerRadius: Tokens.Radius.control)
          )
        }
      }
    } else if let onDone {
      Button(action: onDone) {
        Text("Done")
          .font(Tokens.Text.label.weight(.semibold))
          .frame(maxWidth: .infinity, minHeight: Tokens.loggerTapTarget)
      }
      .buttonStyle(.plain)
      .background(
        Tokens.Color.accent.opacity(0.15),
        in: RoundedRectangle(cornerRadius: Tokens.Radius.control)
      )
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
      .frame(maxWidth: .infinity, minHeight: Tokens.loggerTapTarget)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(key == .disabledDecimal)
    .opacity(key == .disabledDecimal ? 0 : 1)
    .background(
      Tokens.Color.background,
      in: RoundedRectangle(cornerRadius: Tokens.Radius.control)
    )
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
