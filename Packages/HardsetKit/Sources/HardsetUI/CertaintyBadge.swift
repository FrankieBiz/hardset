import HardsetCore
import SwiftUI

/// Shows how much the app trusts the number next to it, and where that number came from.
///
/// App Review guideline 1.4.1 requires disclosing the data and methodology behind
/// health-related accuracy claims. Making the disclosure a property of the badge -- rather
/// than a paragraph in a settings screen -- means it cannot drift away from the value it
/// describes, because the same view renders both.
///
/// Two styles, one control. `.capsule` is a compact capsule on the level's own tint: the symbol, the
/// word and the hue identify it, and it wears no outline by default; under Increase Contrast or
/// Button Shapes it is outlined in the level's hue, so it still reads as something that can be
/// opened. At accessibility sizes, where the word can wrap, the capsule takes the control radius
/// (see `CertaintyCapsule`). `.language` is the same claim as a phrase in the quiet label style, in
/// `chalkDim`, with a small info glyph that says it opens: no tint, no hue, no capsule. The words
/// carry the level, which is better for the product's claim than a badge, because the app is
/// saying what it knows in a sentence. Both open the same disclosure.
///
/// Either way the visible part stays small enough to sit beside a figure, but the tappable region is
/// the full 44 pt floor, laid out inside the button's label: a frame applied outside a plain button
/// reserves space without reliably extending what can be tapped.
public struct CertaintyBadge: View {
  /// How the badge is drawn. The disclosure it opens is the same in both.
  public enum Style: Sendable, Hashable {
    /// A tinted capsule with the level's symbol and word.
    case capsule
    /// A quiet phrase, "Moderate confidence", with an info glyph, and no tint or hue.
    case language
  }

  private let level: CertaintyLevel
  private let methodology: String
  private let citation: String?
  private let context: String?
  private let style: Style
  @State private var isShowingDetail = false
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  /// - Parameter context: What the level is about, said before it in a `.language` badge:
  ///   "From another machine · Low confidence". Ignored by `.capsule`.
  public init(
    level: CertaintyLevel, methodology: String, citation: String? = nil, context: String? = nil,
    style: Style = .capsule
  ) {
    self.level = level
    self.methodology = methodology
    self.citation = citation
    self.context = context
    self.style = style
  }

  public var body: some View {
    trigger
      .accessibilityLabel(accessibilityName)
      .popover(isPresented: $isShowingDetail) {
        CertaintyDetail(
          level: level, methodology: methodology, citation: citation,
          isLargeText: Self.needsSheet(dynamicTypeSize), style: style
        )
      }
  }

  @ViewBuilder private var trigger: some View {
    switch style {
    case .capsule:
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
      .buttonStyle(HardsetPressStyle())
    case .language:
      Button {
        isShowingDetail = true
      } label: {
        CertaintyPhrase(level: level, context: context)
      }
      .buttonStyle(InlineControlStyle(minHeight: Tokens.minimumTapTarget, alignment: .leading))
    }
  }

  /// Begins with the words the badge shows, so Voice Control can say what it sees; a `.language`
  /// badge says its context first, as it does on screen.
  private var accessibilityName: String {
    guard style == .language, let context else { return "\(level.label). How this was calculated." }
    return "\(context). \(level.label). How this was calculated."
  }

  /// From Extra Extra Extra Large up, the longest methodologies run taller than an iPhone screen
  /// in the popover's reading column, so the disclosure opens as a scrolling sheet instead.
  static func needsSheet(_ size: DynamicTypeSize) -> Bool {
    size >= .xxxLarge
  }
}

/// A certainty level as a phrase: the level's word, with what it is about before it, in the quiet
/// label style and `chalkDim`, and a small info glyph after it. There is no fill, no hue and no
/// outline; the words say the level, and the glyph says that it opens. The phrase wraps rather than
/// truncating, so the word that qualifies a claim is never cut.
struct CertaintyPhrase: View {
  let level: CertaintyLevel
  let context: String?

  private var phrase: String {
    [context, level.label].compactMap { $0 }.joined(separator: " · ")
  }

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.tight) {
      Text(phrase)
        .hardsetText(.provenance)
        .foregroundStyle(Tokens.Color.chalkDim)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
      Image(systemName: "info.circle")
        .hardsetText(.caption)
        .foregroundStyle(Tokens.Color.chalkDim)
        .accessibilityHidden(true)
    }
  }
}

extension CertaintyLevel {
  /// The UI level for an engine certainty, mapped by name. The switch names every case and takes
  /// no `default`, so a case added to either enum fails to compile here instead of rendering as
  /// the wrong word.
  public init(_ certainty: Certainty) {
    switch certainty {
    case .high: self = .high
    case .moderate: self = .moderate
    case .low: self = .low
    case .unevaluated: self = .unevaluated
    }
  }
}

/// The popover behind a badge: the level restated, then the method, then where it comes from.
///
/// Drawn on `steel` rather than the system's translucent popover material, so every text role in
/// it stays on a background whose contrast has been measured.
///
/// At large text sizes the same content is presented as a sheet that scrolls, with a Done button,
/// because a popover cannot scroll and the disclosure would be cut off for exactly the lifters who
/// enlarge text. At ordinary sizes it stays the anchored popover.
struct CertaintyDetail: View {
  let level: CertaintyLevel
  let methodology: String
  let citation: String?
  let isLargeText: Bool
  let style: CertaintyBadge.Style

  @Environment(\.dismiss) private var dismiss

  /// Wide enough for a methodology paragraph to read as prose, narrow enough that the popover
  /// stays anchored to its badge rather than becoming a sheet.
  private static let readingWidth: CGFloat = 320

  /// Explicit, because the private environment property above would otherwise make the memberwise
  /// initialiser private, and the honesty catalogue draws the detail from another file.
  init(
    level: CertaintyLevel, methodology: String, citation: String?, isLargeText: Bool,
    style: CertaintyBadge.Style = .capsule
  ) {
    self.level = level
    self.methodology = methodology
    self.citation = citation
    self.isLargeText = isLargeText
    self.style = style
  }

  var body: some View {
    if isLargeText {
      ScrollView {
        content
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .scrollBounceBehavior(.basedOnSize)
      // Only consulted where a regular-width popover asks for the content's own size; a sheet
      // proposes its full size and ignores these.
      .frame(idealWidth: Self.readingWidth * 1.5, idealHeight: Self.readingWidth * 2)
      .background(Tokens.Color.steel)
      .safeAreaInset(edge: .top, spacing: 0) {
        HStack {
          Spacer(minLength: 0)
          Button("Done") { dismiss() }
            .buttonStyle(HardsetButtonStyle(.quiet, fullWidth: false))
        }
        .padding(.horizontal, Tokens.Spacing.snug)
        .padding(.top, Tokens.Spacing.snug)
        .background(Tokens.Color.steel)
      }
      .presentationCompactAdaptation(.sheet)
      .presentationDetents([.medium, .large])
      .presentationDragIndicator(.visible)
      .presentationBackground(Tokens.Color.steel)
    } else {
      content
        .frame(maxWidth: Self.readingWidth, alignment: .leading)
        .presentationCompactAdaptation(.popover)
        .presentationBackground(Tokens.Color.steel)
    }
  }

  private var content: some View {
    CertaintyDetailContent(
      level: level, methodology: methodology, citation: citation, style: style)
  }
}

/// What the detail says, without its popover or sheet chrome: the level restated, the heading, the
/// method and, when there is one, a hairline and the citation. `CertaintyDetail` presents it, and
/// the honesty catalogue draws it directly, so the open detail can be rendered and reviewed
/// without opening a popover.
struct CertaintyDetailContent: View {
  let level: CertaintyLevel
  let methodology: String
  let citation: String?
  /// `.language` restates the level as a heading in chalk, so a disclosure opened from a phrase
  /// does not bring the tinted capsule back.
  var style: CertaintyBadge.Style = .capsule

  var body: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
      switch style {
      case .capsule:
        CertaintyCapsule(level: level, isInteractive: false)
      case .language:
        Text(level.label)
          .font(Tokens.Text.title)
          .foregroundStyle(Tokens.Color.chalk)
          .fixedSize(horizontal: false, vertical: true)
      }
      Text("How this is calculated")
        .font(Tokens.Text.headline)
        .foregroundStyle(Tokens.Color.chalk)
        .accessibilityAddTraits(.isHeader)
      Text(methodology)
        .font(Tokens.Text.label)
        .foregroundStyle(Tokens.Color.chalk)
        .fixedSize(horizontal: false, vertical: true)
      if let citation {
        Rectangle()
          .fill(Tokens.Color.hairline)
          .frame(height: Tokens.Stroke.hairline)
          .accessibilityHidden(true)
        Text(citation)
          .hardsetText(.caption)
          .foregroundStyle(Tokens.Color.chalkDim)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(Tokens.Spacing.loose)
  }
}

/// The capsule itself: symbol, word and hue together, on the level's tint.
///
/// Shared with `MethodologySheet`, which states the same level at the top of its disclosure. The
/// fill, symbol and word are the whole of it: no capsule draws a decorative outline. Only the
/// interactive version has one to give, a full-strength outline in the level's hue that appears
/// under Increase Contrast or Button Shapes, because those settings ask every control to show its
/// edge, and a static chip must never imitate a control.
///
/// A capsule at ordinary sizes. At accessibility sizes the word can wrap to a second line, and a
/// capsule's corner radius, half its height, then pushes the wrapped text across the outline, so
/// there the fill and outline take the control radius instead. Only the shape changes: the tint,
/// the outline strength and the padding are the same at every size.
struct CertaintyCapsule: View {
  let level: CertaintyLevel
  let isInteractive: Bool

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.accessibilityShowButtonShapes) private var showsButtonShapes

  /// Explicit, because the private environment properties above would otherwise make the
  /// memberwise initialiser private, and `MethodologySheet` and the honesty catalogue draw the
  /// capsule from other files.
  init(level: CertaintyLevel, isInteractive: Bool) {
    self.level = level
    self.isInteractive = isInteractive
  }

  var body: some View {
    let isLarge = dynamicTypeSize.isAccessibilitySize
    let request = ControlEdgeRequest(contrast: contrast, showsButtonShapes: showsButtonShapes)
    let outline = Tokens.Color.certainty(level)
    HStack(spacing: Tokens.Spacing.tight) {
      Image(systemName: level.symbolName)
        .accessibilityHidden(true)
      // Colour is never the only carrier of meaning.
      Text(level.label)
        .fixedSize(horizontal: false, vertical: true)
    }
    .hardsetText(.caption, weight: .semibold)
    .foregroundStyle(Tokens.Color.certainty(level))
    .padding(.horizontal, Tokens.Spacing.snug)
    .padding(.vertical, Tokens.Spacing.tight)
    .background {
      if isLarge {
        Tokens.Shape.control.fill(Tokens.Color.certaintySurface(level))
      } else {
        Capsule().fill(Tokens.Color.certaintySurface(level))
      }
    }
    .overlay {
      if isInteractive && request.isRequested {
        if isLarge {
          Tokens.Shape.control.strokeBorder(outline, lineWidth: Tokens.Stroke.hairline)
        } else {
          Capsule().strokeBorder(outline, lineWidth: Tokens.Stroke.hairline)
        }
      }
    }
  }
}

/// The one-tap correction for a value the app inferred rather than knew.
///
/// Required wherever an inferred experience level moved a number the user sees: the guess is
/// stated, and correcting it is a single tap away.
///
/// A flat raised fill, with the pencil in plate blue because it is the part that acts; it is
/// outlined when Increase Contrast or Button Shapes asks every control to be. Its 44 pt hit region
/// is applied by `ControlPressFace` after the capsule (R40).
///
/// A capsule at ordinary sizes. At accessibility sizes a long label wraps to several lines, and a
/// capsule's corner radius, half its height, then pushes the wrapped text across the outline, so
/// there the face takes the control radius instead. Only the shape changes: the press, the
/// outline, the hit region and the spoken label are the same at every size.
public struct AssumptionChip: View {
  private let label: String
  private let correctionPrompt: String
  private let onCorrect: () -> Void

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  public init(label: String, correctionPrompt: String, onCorrect: @escaping () -> Void) {
    self.label = label
    self.correctionPrompt = correctionPrompt
    self.onCorrect = onCorrect
  }

  public var body: some View {
    styledChip
      .accessibilityLabel("\(label). \(correctionPrompt).")
  }

  /// The chip in its flat press style, on the capsule or, at accessibility sizes, on the control
  /// radius.
  @ViewBuilder
  private var styledChip: some View {
    if dynamicTypeSize.isAccessibilitySize {
      chip.buttonStyle(ControlPressStyle(shape: Tokens.Shape.control, outline: .onRequest))
    } else {
      chip.buttonStyle(ControlPressStyle(shape: Capsule(), outline: .onRequest))
    }
  }

  private var chip: some View {
    Button(action: onCorrect) {
      HStack(spacing: Tokens.Spacing.tight) {
        Text(label)
          .foregroundStyle(Tokens.Color.chalk)
          .fixedSize(horizontal: false, vertical: true)
        Image(systemName: "pencil")
          .foregroundStyle(Tokens.Color.plateBlue)
          .accessibilityHidden(true)
      }
      .hardsetText(.caption, weight: .semibold)
      .padding(.horizontal, Tokens.Spacing.regular)
      .padding(.vertical, Tokens.Spacing.snug)
    }
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
        Text(CertaintyLevel.unevaluated.label)
          .hardsetText(.readout)
      }
      .foregroundStyle(Tokens.Color.chalkDim)
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
            Tokens.Color.controlEdge,
            style: StrokeStyle(lineWidth: Tokens.Stroke.hairline, dash: [4, 3])
          )
        }
        .accessibilityHidden(true)
      }

      Text(explanation)
        .font(Tokens.Text.provenance)
        .foregroundStyle(Tokens.Color.chalkDim)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
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
    .background(Tokens.Color.canvas)
  }
#endif
