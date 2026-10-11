import HardsetCore
import SwiftUI

/// Shows how much the app trusts the number next to it, and where that number came from.
///
/// A glyph and a word, never colour alone (spec 3.1). Both come from `CertaintyMark` in Core,
/// where they are tested. Tapping opens the source, which is what App Review guideline 1.4.1 asks
/// for, attached to the number rather than buried in settings.
public struct CertaintyBadge: View {
  /// `.full` shows the whole word ("Moderate confidence"); `.compact` the short one ("Moderate"),
  /// for dense rows where the full word would repeat down a list. VoiceOver hears the whole word
  /// either way.
  public enum Style: Sendable { case full, compact }

  private let mark: CertaintyMark
  private let source: EvidenceSource
  private let style: Style
  @State private var isShowingSource = false

  public init(_ certainty: Certainty, source: EvidenceSource, style: Style = .full) {
    self.mark = certainty.mark
    self.source = source
    self.style = style
  }

  public var body: some View {
    Button {
      isShowingSource = true
    } label: {
      HStack(spacing: Tokens.Spacing.tight) {
        Image(systemName: mark.symbolName)
        Text(style == .full ? mark.word : mark.shortWord)
      }
      .font(Tokens.Text.caption)
      .foregroundStyle(Tokens.Color.certainty(mark.certainty))
      .frame(minHeight: Tokens.minimumTapTarget)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(mark.word)
    .accessibilityHint("Shows how this was calculated")
    .sheet(isPresented: $isShowingSource) {
      MethodologySheet(source: source, certainty: mark.certainty)
    }
  }
}

/// The one-tap correction for a value the app inferred rather than knew.
///
/// Required wherever an inferred experience level moved a number the user sees: the guess is
/// stated, and correcting it is a single tap away.
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
        Image(systemName: "pencil.circle")
      }
      .font(Tokens.Text.caption)
      .padding(.horizontal, Tokens.Spacing.snug)
      .padding(.vertical, Tokens.Spacing.tight)
      .background(Tokens.Color.surface, in: Capsule())
      .foregroundStyle(Tokens.Color.textSecondary)
    }
    .buttonStyle(.plain)
    .frame(minHeight: Tokens.minimumTapTarget)
    .accessibilityLabel("\(label). \(correctionPrompt).")
  }
}

/// Renders the absence of a value without pretending one exists.
///
/// This is what the app shows instead of a neutral fallback score. The ancestor app's scorers
/// returned 70 when they recognised nothing, so three unknown lifts read as "78/100 -- Dialed
/// in"; there is deliberately no way to render that here.
public struct UnevaluatedReadout: View {
  private let explanation: String

  public init(explanation: String) {
    self.explanation = explanation
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
      Text("Not evaluated")
        .font(Tokens.Text.readout)
        .foregroundStyle(Tokens.Color.textSecondary)
      Text(explanation)
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.textSecondary)
    }
  }
}
