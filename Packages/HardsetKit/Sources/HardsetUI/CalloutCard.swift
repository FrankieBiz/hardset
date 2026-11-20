import SwiftUI

/// The tour's floating explanation: one line about the highlighted control, the step counter, and
/// the two ways forward.
///
/// It floats over the staged phone on system glass, as the spec allows for the tour's callout and
/// the toolbars and nothing else: content never sits on glass. Where glass is not available it is a
/// `steel` card with the lit edge. "Next" is a primary button and is absent while the step waits
/// on the lifter; "Skip tour" is a quiet link under it that is always there.
public struct CalloutCard: View {
  private let step: Int
  private let count: Int
  private let message: String
  private let nextTitle: String?
  private let onNext: () -> Void
  private let onSkip: () -> Void

  /// - Parameters:
  ///   - step: One-based, as the lifter counts.
  ///   - nextTitle: The primary button's title, or `nil` to hide it while the step waits on the lifter.
  public init(
    step: Int, of count: Int, message: String, nextTitle: String?, onNext: @escaping () -> Void,
    onSkip: @escaping () -> Void
  ) {
    self.step = step
    self.count = count
    self.message = message
    self.nextTitle = nextTitle
    self.onNext = onNext
    self.onSkip = onSkip
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      Text("\(step) of \(count)")
        .hardsetText(.caption)
        .foregroundStyle(Tokens.Color.chalkDim)
        .accessibilityLabel("Step \(step) of \(count)")
      Text(message)
        .hardsetText(.label)
        .foregroundStyle(Tokens.Color.chalk)
        .fixedSize(horizontal: false, vertical: true)
      VStack(spacing: Tokens.Spacing.tight) {
        if let nextTitle {
          Button(nextTitle, action: onNext)
            .buttonStyle(HardsetButtonStyle(.primary))
            // Named for the UI tests: the staged keypad has a "Next" of its own.
            .accessibilityIdentifier("tour-next")
        }
        Button("Skip tour", action: onSkip)
          .buttonStyle(HardsetButtonStyle(.quiet))
          .accessibilityIdentifier("tour-skip")
      }
      .padding(.top, Tokens.Spacing.tight)
    }
    .padding(Tokens.Spacing.loose)
    .frame(maxWidth: .infinity, alignment: .leading)
    .calloutSurface()
    .accessibilityElement(children: .contain)
  }
}

extension View {
  /// Glass on iOS, where the tour's callout is allowed it; a steel card elsewhere, so the host
  /// build, which only compiles the package, has the same shape.
  fileprivate func calloutSurface() -> some View {
    #if os(iOS)
      glassEffect(.regular, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
    #else
      background(Tokens.Color.steel, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
        .overlay {
          RoundedRectangle(cornerRadius: Tokens.Radius.card)
            .strokeBorder(Tokens.Color.hairline, lineWidth: Tokens.Stroke.hairline)
        }
    #endif
  }
}
