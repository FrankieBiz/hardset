import SwiftUI

/// Shows how much the app trusts the number next to it, and where that number came from.
///
/// App Review guideline 1.4.1 requires disclosing the data and methodology behind
/// health-related accuracy claims. Making the disclosure a property of the badge -- rather
/// than a paragraph in a settings screen -- means it cannot drift away from the value it
/// describes, because the same view renders both.
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
      HStack(spacing: Tokens.Spacing.tight) {
        Image(systemName: level.symbolName)
        // Colour is never the only carrier of meaning.
        Text(level.label)
      }
      .font(Tokens.Text.caption)
      .foregroundStyle(Tokens.Color.certainty(level))
      // A caption-height row of text is roughly 16 pt tall. The badge is the only way to reach the
      // methodology behind a number, so it gets a real target rather than the size of its glyphs.
      .frame(minHeight: Tokens.minimumTapTarget)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(level.label). How this was calculated.")
    .popover(isPresented: $isShowingDetail) {
      VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
        Text("How this is calculated")
          .font(Tokens.Text.title)
        Text(methodology)
          .font(Tokens.Text.label)
        if let citation {
          Text(citation)
            .font(Tokens.Text.caption)
            .foregroundStyle(Tokens.Color.textSecondary)
        }
      }
      .padding(Tokens.Spacing.loose)
      .frame(maxWidth: 320)
      .presentationCompactAdaptation(.popover)
    }
  }
}

/// The one-tap correction for a value the app inferred rather than knew.
///
/// Required wherever an inferred experience level moved a number the user sees: the guess is
/// stated, and correcting it is a single tap away.
/// An inferred input, paired with the affordance to correct it.
///
/// **Unused in v1, deliberately, and not a wiring bug.** It exists for the locked decision that
/// experience level is inferred rather than asked, with every volume band it moves carrying an
/// "assumes intermediate" chip. There are no volume bands: `VolumeAnalyzer.weeklyTarget` returns
/// `.unevaluated` for every muscle because no per-muscle weekly target is established. So there is
/// currently nothing for this to qualify, and no experience-level concept in the code at all.
///
/// Kept rather than deleted because the requirement is a real one and this is what satisfies it the
/// day a band exists. If bands are still absent when v1 ships, delete both this and `Assumption`
/// rather than shipping a component with no host.
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
