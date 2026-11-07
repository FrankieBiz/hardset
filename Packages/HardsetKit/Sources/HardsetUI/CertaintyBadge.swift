import SwiftUI

/// Shows how much the app trusts the number next to it, and where that number came from.
///
/// App Review guideline 1.4.1 requires disclosing the data and methodology behind
/// health-related accuracy claims. Making the disclosure a property of the badge -- rather
/// than a paragraph in a settings screen -- means it cannot drift away from the value it
/// describes, because the same view renders both.
///
/// Drawn as a compact capsule on the level's own tint, outlined in the level's hue so it reads as
/// something that can be opened. The capsule stays small enough to sit beside a figure, but the
/// tappable region is the full 44 pt floor, laid out inside the button's label: a frame applied
/// outside a plain button reserves space without reliably extending what can be tapped.
public struct CertaintyBadge: View {
  private let level: CertaintyLevel
  private let methodology: String
  private let citation: String?
  @State private var isShowingDetail = false

  public init(level: CertaintyLevel, methodology: String, citation: String? = nil) {
    self.level = level
    self.methodology = methodology
    self.citation = citation
  }

  public var body: some View {
    Button {
      isShowingDetail = true
    } label: {
      CertaintyCapsule(level: level, isInteractive: true)
        .frame(
          minWidth: Tokens.minimumTapTarget,
          minHeight: Tokens.minimumTapTarget,
          alignment: .leading
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(CertaintyPressStyle())
    .accessibilityLabel("\(level.label). How this was calculated.")
    .popover(isPresented: $isShowingDetail) {
      CertaintyDetail(level: level, methodology: methodology, citation: citation)
    }
  }
}

/// The popover behind a badge: the level restated, then the method, then where it comes from.
///
/// Drawn on `surface` rather than the system's translucent popover material, so every text role in
/// it stays on a background whose contrast has been measured.
private struct CertaintyDetail: View {
  let level: CertaintyLevel
  let methodology: String
  let citation: String?

  /// Wide enough for a methodology paragraph to read as prose, narrow enough that the popover
  /// stays anchored to its badge rather than becoming a sheet.
  private static let readingWidth: CGFloat = 320

  var body: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
      CertaintyCapsule(level: level, isInteractive: false)
      Text("How this is calculated")
        .font(Tokens.Text.headline)
        .foregroundStyle(Tokens.Color.textPrimary)
        .accessibilityAddTraits(.isHeader)
      Text(methodology)
        .font(Tokens.Text.label)
        .foregroundStyle(Tokens.Color.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
      if let citation {
        Rectangle()
          .fill(Tokens.Color.border)
          .frame(height: Tokens.Stroke.hairline)
          .accessibilityHidden(true)
        Text(citation)
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(Tokens.Spacing.loose)
    .frame(maxWidth: Self.readingWidth, alignment: .leading)
    .presentationCompactAdaptation(.popover)
    .presentationBackground(Tokens.Color.surface)
  }
}

/// The capsule itself: symbol, word and hue together, on the level's tint.
///
/// Shared with `MethodologySheet`, which states the same level at the top of its disclosure. Only
/// the interactive version carries a full-strength outline, because an outline at 3:1 is what tells
/// the lifter something is tappable, and a static chip must not imitate a control.
struct CertaintyCapsule: View {
  let level: CertaintyLevel
  let isInteractive: Bool

  var body: some View {
    HStack(spacing: Tokens.Spacing.tight) {
      Image(systemName: level.symbolName)
        .accessibilityHidden(true)
      // Colour is never the only carrier of meaning.
      Text(level.label)
        .lineLimit(1)
    }
    .font(Tokens.Text.caption.weight(.semibold))
    .foregroundStyle(Tokens.Color.certainty(level))
    .padding(.horizontal, Tokens.Spacing.snug)
    .padding(.vertical, Tokens.Spacing.tight)
    .background(Tokens.Color.certaintySurface(level), in: Capsule())
    .overlay(
      Capsule().strokeBorder(
        Tokens.Color.certainty(level).opacity(isInteractive ? 1 : 0.35),
        lineWidth: Tokens.Stroke.hairline
      )
    )
  }
}

/// The one-tap correction for a value the app inferred rather than knew.
///
/// Required wherever an inferred experience level moved a number the user sees: the guess is
/// stated, and correcting it is a single tap away.
///
/// Outlined as a control, with the pencil in readout cyan because it is the part that acts. The
/// 44 pt region sits inside the label for the same reason as `CertaintyBadge`'s.
public struct AssumptionChip: View {
  private let label: String
  private let correctionPrompt: String
  private let onCorrect: () -> Void

  public init(label: String, correctionPrompt: String, onCorrect: @escaping () -> Void) {
    self.label = label
    self.correctionPrompt = correctionPrompt
    self.onCorrect = onCorrect
  }

  public var body: some View {
    Button(action: onCorrect) {
      HStack(spacing: Tokens.Spacing.tight) {
        Text(label)
          .foregroundStyle(Tokens.Color.textPrimary)
        Image(systemName: "pencil")
          .foregroundStyle(Tokens.Color.accent)
          .accessibilityHidden(true)
      }
      .font(Tokens.Text.caption.weight(.semibold))
      .padding(.horizontal, Tokens.Spacing.regular)
      .padding(.vertical, Tokens.Spacing.snug)
      .background(Tokens.Color.surfaceRaised, in: Capsule())
      .overlay(
        Capsule().strokeBorder(Tokens.Color.controlBorder, lineWidth: Tokens.Stroke.hairline)
      )
      .frame(minHeight: Tokens.minimumTapTarget)
      .contentShape(Rectangle())
    }
    .buttonStyle(CertaintyPressStyle())
    .accessibilityLabel("\(label). \(correctionPrompt).")
  }
}

/// Renders the absence of a value without pretending one exists.
///
/// This is what the app shows instead of a neutral fallback score. The ancestor app's scorers
/// returned 70 when they recognised nothing, so three unknown lifts read as "78/100 -- Dialed
/// in"; there is deliberately no way to render that here.
///
/// Styled as an instrument reading whose slot is drawn but left empty: the words sit in readout
/// type over a dashed rule, the app's one mark for "nothing here", and never in a figure's place.
public struct UnevaluatedReadout: View {
  private let explanation: String

  public init(explanation: String) {
    self.explanation = explanation
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.snug) {
        Image(systemName: CertaintyLevel.unevaluated.symbolName)
          .font(Tokens.Text.headline)
          .accessibilityHidden(true)
        Text("Not evaluated")
          .font(Tokens.Text.readout)
      }
      .foregroundStyle(Tokens.Color.textSecondary)
      .padding(.bottom, Tokens.Spacing.tight)
      .overlay(alignment: .bottom) {
        GeometryReader { proxy in
          // Inset by half the stroke so the whole rule lands inside the readout's own bounds.
          let y = proxy.size.height - Tokens.Stroke.hairline / 2
          Path { path in
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: proxy.size.width, y: y))
          }
          .stroke(
            Tokens.Color.controlBorder,
            style: StrokeStyle(lineWidth: Tokens.Stroke.hairline, dash: [4, 3])
          )
        }
        .accessibilityHidden(true)
      }

      Text(explanation)
        .font(Tokens.Text.provenance)
        .foregroundStyle(Tokens.Color.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }
}

/// Press feedback for the badge and the chip: a slight dip in opacity and scale while the finger
/// is down, on `Motion.press`, and opacity alone with Reduce Motion on.
private struct CertaintyPressStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    CertaintyPressBody(configuration: configuration)
  }
}

private struct CertaintyPressBody: View {
  let configuration: ButtonStyleConfiguration
  @Environment(\.accessibilityReduceMotion) var reduceMotion

  var body: some View {
    configuration.label
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
      .opacity(configuration.isPressed ? 0.7 : 1)
      .animation(
        Tokens.Motion.adaptive(Tokens.Motion.press, reduceMotion: reduceMotion),
        value: configuration.isPressed
      )
  }
}

#if DEBUG
  #Preview("Certainty") {
    VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
      ForEach(CertaintyLevel.allCases, id: \.self) { level in
        CertaintyBadge(
          level: level,
          methodology: "Verified empirical load logged in active sessions on this specific machine.",
          citation: "Exact weight recorded by user"
        )
      }
      AssumptionChip(
        label: "Assumes intermediate",
        correctionPrompt: "Set your training experience",
        onCorrect: {}
      )
      UnevaluatedReadout(
        explanation: "No weekly set target is established for any muscle, so none is shown."
      )
    }
    .padding(Tokens.Spacing.loose)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Tokens.Color.background)
  }
#endif
