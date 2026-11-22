import HardsetCore
import SwiftUI

/// What a screen holds while a "Worked from" sheet is up. Identified by itself, so asking for the
/// working of a different figure presents the new one rather than re-showing the last.
///
/// `nonisolated` for the same reason as the sheet enums on the screens: its `id` is stored and
/// must satisfy `Identifiable` without isolated-conformance inference.
public nonisolated struct WorkedFromPresentation: Identifiable, Sendable {
  public let id = UUID()
  public let account: WorkedFromAccount

  public init(_ account: WorkedFromAccount) {
    self.account = account
  }
}

/// The visible control that opens the working behind a number: a words-and-glyph label, so it is
/// found without a gesture and can be said aloud by what it shows. A screen that has dropped its
/// containers asks for `.inline`; every other screen keeps the quiet button.
public struct WorkedFromButton: View {
  /// How the control is drawn; the words, the glyph and the sheet it opens are the same.
  public enum Style: Sendable, Hashable {
    /// Accent text with no fill, inset like a quiet button.
    case quiet
    /// `chalk` words and the glyph with no face, for a screen that has dropped its containers.
    case inline
  }

  private let title: String
  private let style: Style
  private let action: () -> Void

  public init(
    _ title: String = "Worked from", style: Style = .quiet, action: @escaping () -> Void
  ) {
    self.title = title
    self.style = style
    self.action = action
  }

  public var body: some View {
    switch style {
    case .quiet:
      Button(action: action) {
        Label(title, systemImage: WorkedFromSheet.glyph)
      }
      .buttonStyle(HardsetButtonStyle(.quiet, fullWidth: false))
      // The quiet style insets its label; pulling it back aligns the words with the content edge
      // while the full 44 pt region stays tappable.
      .padding(.leading, -Tokens.Spacing.snug)
    case .inline:
      Button(action: action) {
        Label(title, systemImage: WorkedFromSheet.glyph)
          .font(Tokens.Text.headline)
          .foregroundStyle(Tokens.Color.chalk)
      }
      .buttonStyle(InlineControlStyle(alignment: .leading))
    }
  }
}

/// The working behind a number, as a document: the figure and how far to trust it, the rule that
/// produced it, the sets that fed it, and the sets that were left out and why.
///
/// One presentation for every surface that explains itself. It renders a `WorkedFromAccount` and
/// does no arithmetic of its own: the account is derived in Core, from the same inputs and through
/// the same functions the figure came from, so the sheet cannot say something the figure did not do.
///
/// Standing is carried by a word and a symbol, never by colour. The whole account is one sentence
/// for VoiceOver on the header, and each line is one sentence, so nothing is read as a table.
public struct WorkedFromSheet: View {
  /// The glyph every entry point to this sheet wears, so the control is the same everywhere.
  static let glyph = "list.bullet.rectangle"

  private let account: WorkedFromAccount
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  public init(account: WorkedFromAccount) {
    self.account = account
  }

  public var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: Tokens.Spacing.section) {
          header
          ruleBlock
          ForEach(account.sections) { section in
            sectionBlock(section)
          }
        }
        .padding(.horizontal, Tokens.Spacing.loose)
        .padding(.top, Tokens.Spacing.loose)
        .padding(.bottom, Tokens.Spacing.block)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .background(Tokens.Color.canvas)
      .hardsetNavigationTitle("Worked from")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
  }

  // MARK: - Header

  /// What is being explained, the figure in the largest type on the sheet, and what qualifies it.
  /// Spoken as one sentence that carries the whole account in brief.
  private var header: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      Text(account.title)
        .font(Tokens.Text.headline)
        .foregroundStyle(Tokens.Color.chalk)
        .fixedSize(horizontal: false, vertical: true)
      Text(account.figure)
        .font(Tokens.Text.readout)
        .foregroundStyle(Tokens.Color.chalk)
        .fixedSize(horizontal: false, vertical: true)
      Text(account.figureCaption)
        .font(Tokens.Text.provenance)
        .foregroundStyle(Tokens.Color.chalkDim)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(account.spoken)
    .accessibilityAddTraits(.isHeader)
  }

  // MARK: - Rule

  private var ruleBlock: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      Text(account.ruleHeading)
        .font(Tokens.Text.sectionHeader)
        .foregroundStyle(Tokens.Color.chalk)
        .accessibilityAddTraits(.isHeader)
      Text(account.rule)
        .font(Tokens.Text.label)
        .foregroundStyle(Tokens.Color.chalk)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  // MARK: - Sections

  private func sectionBlock(_ section: WorkedFromAccount.Section) -> some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
      VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
        SectionLabel(section.heading, count: section.lines.isEmpty ? nil : section.lines.count)
        if let note = section.note {
          Text(note)
            .font(Tokens.Text.caption)
            .foregroundStyle(Tokens.Color.chalkDim)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      VStack(alignment: .leading, spacing: 0) {
        ForEach(section.lines) { line in
          row(line)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// One set, movement or muscle: its figures, where it stands, where and when, and the arithmetic
  /// or the reason in a sentence. A left-out line is dimmed and says "Left out" in words, so no
  /// line is carried by tone alone.
  private func row(_ line: WorkedFromAccount.Line) -> some View {
    let isLeftOut = line.standing == .excluded
    let layout =
      dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tokens.Spacing.tight))
      : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Tokens.Spacing.snug))
    return VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
      layout {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.snug) {
          Image(systemName: Self.symbol(for: line.standing))
            .font(Tokens.Text.caption)
            .foregroundStyle(Tokens.Color.chalkDim)
            .accessibilityHidden(true)
          Text(line.headline)
            .font(Tokens.Text.figure)
            .foregroundStyle(isLeftOut ? Tokens.Color.chalkDim : Tokens.Color.chalk)
            .fixedSize(horizontal: false, vertical: true)
        }
        if !dynamicTypeSize.isAccessibilitySize {
          Spacer(minLength: Tokens.Spacing.regular)
        }
        Text(line.standingWord ?? Self.word(for: line.standing))
          .font(Tokens.Text.provenance)
          .foregroundStyle(Tokens.Color.chalkDim)
      }
      if let context = line.context {
        Text(context)
          .font(Tokens.Text.provenance)
          .foregroundStyle(Tokens.Color.chalkDim)
          .fixedSize(horizontal: false, vertical: true)
      }
      Text(line.detail)
        .font(Tokens.Text.provenance)
        .foregroundStyle(isLeftOut ? Tokens.Color.chalkDim : Tokens.Color.chalk)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, Tokens.Spacing.snug)
    .overlay(alignment: .top) {
      Rectangle().fill(Tokens.Color.hairline).frame(height: Tokens.Stroke.hairline)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(line.spoken)
  }

  /// Three shapes, so the standing is never hue alone: a tick for what produced the figure, a ring
  /// for what took part, a minus for what was left out.
  static func symbol(for standing: WorkedFromAccount.Standing) -> String {
    switch standing {
    case .produced: "checkmark"
    case .counted: "circle"
    case .excluded: "minus.circle"
    }
  }

  static func word(for standing: WorkedFromAccount.Standing) -> String {
    switch standing {
    case .produced: "Produced the figure"
    case .counted: "Counted"
    case .excluded: "Left out"
    }
  }
}

#if DEBUG
  #Preview("Estimated one-rep max") {
    WorkedFromSheet(
      account: WorkedFromAccount(
        title: "Estimated one-rep max", figure: "126.5 kg",
        figureCaption: "Moderate confidence · Hammer Strength · Nov 14, 2023",
        ruleHeading: "Formula",
        rule: "Each set is converted with the Epley formula: weight × (1 + reps ÷ 30). One rep at a load "
          + "is its own one-rep max, so a single is taken as measured. Sets above 12 reps are not "
          + "estimated. The session's figure is the highest estimate among its sets, shown to the "
          + "nearest 0.5 kg.",
        sections: [
          WorkedFromAccount.Section(
            id: "fed", heading: "Sets that fed this figure",
            note: "The set with the highest estimate is the figure.",
            lines: [
              WorkedFromAccount.Line(
                id: "a", standing: .counted, headline: "100 kg × 5",
                context: "Nov 14, 2023 · Hammer Strength",
                detail: "100 × (1 + 5 ÷ 30) → 116.5 kg. Below the figure.", spoken: "A set."),
              WorkedFromAccount.Line(
                id: "b", standing: .produced, headline: "100 kg × 8",
                context: "Nov 14, 2023 · Hammer Strength",
                detail: "100 × (1 + 8 ÷ 30) → 126.5 kg. This set is the figure.", spoken: "A set."),
            ]),
          WorkedFromAccount.Section(
            id: "left", heading: "Left out",
            note: "Warm-ups, other machines and imported history are never mixed into this line.",
            lines: [
              WorkedFromAccount.Line(
                id: "c", standing: .excluded, headline: "60 kg × 15",
                context: "Nov 14, 2023 · Hammer Strength",
                detail: "Left out: 15 reps is above 12, where no one-rep max is estimated.",
                spoken: "A set.")
            ]),
        ],
        spoken: "Estimated one-rep max, 126.5 kilograms."))
  }
#endif
