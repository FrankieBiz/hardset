import HardsetCore
import SwiftUI

/// The claims Hardset refuses to make, each beside the rule that stops it.
///
/// A settings screen usually lists what the app does. This one lists what it will not do, because
/// the product's claim is calibrated honesty and a claim like that is only checkable against its
/// fences: no estimate past a dozen reps, no weekly set target for any muscle, no progress across a
/// machine switch, no timing verdict on a future-dated session. Every sentence and every source name
/// comes from `HonestyCopy`, which reads them from the engine, so this view carries no copy of its
/// own and cannot drift from the rule it is describing.
///
/// Laid out as a document: an introduction, then one block per refusal with its statement, what the
/// app does instead, and the source's own title and stated limit. Four rows of prose, no controls.
public struct RefusalsSheet: View {
  /// Settings applies `.hardsetSheet()` to whatever it presents, but the sheet also carries its own
  /// way out rather than relying on a drag a lifter may not know about.
  @Environment(\.dismiss) private var dismiss

  public init() {}

  public var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: Tokens.Spacing.block) {
          Text(HonestyCopy.introduction)
            .font(Tokens.Text.provenance)
            .foregroundStyle(Tokens.Color.chalkDim)
            .fixedSize(horizontal: false, vertical: true)

          ForEach(HonestyCopy.refusals) { refusal in
            row(refusal)
          }
        }
        .padding(.horizontal, Tokens.Spacing.loose)
        .padding(.top, Tokens.Spacing.loose)
        .padding(.bottom, Tokens.Spacing.block)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .background(Tokens.Color.canvas)
      .hardsetNavigationTitle(HonestyCopy.title)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
  }

  /// One refusal. Combined into a single accessibility element so VoiceOver reads the statement,
  /// then what the app does instead, then the rule, without stopping on a heading that leads
  /// nowhere.
  private func row(_ refusal: Refusal) -> some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      Text(refusal.headline)
        .font(Tokens.Text.headline)
        .foregroundStyle(Tokens.Color.chalk)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)
      Text(refusal.body)
        .font(Tokens.Text.label)
        .foregroundStyle(Tokens.Color.chalk)
        .fixedSize(horizontal: false, vertical: true)
      VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
        Text(refusal.sourceTitle)
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.chalkDim)
          .fixedSize(horizontal: false, vertical: true)
        Text(refusal.sourceLimit)
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.chalkDim)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }
}

#if DEBUG
  #Preview("What Hardset won't say") {
    RefusalsSheet()
  }

  #Preview("Large text") {
    RefusalsSheet()
      .dynamicTypeSize(.accessibility3)
  }
#endif
