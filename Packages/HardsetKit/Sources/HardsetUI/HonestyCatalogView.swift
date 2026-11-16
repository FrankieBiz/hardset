import HardsetCore
import SwiftUI

/// Every state of the honesty components, for review from images: the certainty badge at each
/// level, pressed, static and interactive; the open detail in its popover and large-text forms; the
/// assumption chip at rest, pressed and long; and the unevaluated readout.
///
/// Static: no state, no I/O. The badges are fed by the engine's own claims, so each level shown is
/// one the engine can produce. A `ButtonStyle` cannot be forced pressed in a render, so each
/// pressed sample is the style's own face drawn with `isPressed: true`.
public struct HonestyCatalogView: View {
  public enum Section: String, CaseIterable, Sendable {
    case badges, detail, chips, readouts
  }

  private let section: Section?

  public init(section: Section? = nil) {
    self.section = section
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Tokens.Spacing.section) {
        if let section {
          sectionView(section)
        } else {
          ForEach(Section.allCases, id: \.self) { sectionView($0) }
        }
      }
      .padding(.horizontal, Tokens.Spacing.loose)
      .padding(.vertical, Tokens.Spacing.loose)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(Tokens.Color.canvas.ignoresSafeArea())
  }

  @ViewBuilder
  private func sectionView(_ section: Section) -> some View {
    switch section {
    case .badges: HonestyBadgeStates()
    case .detail: HonestyDetailStates()
    case .chips: HonestyChipStates()
    case .readouts: HonestyReadoutStates()
    }
  }
}

// MARK: - Samples

/// What a badge says for one rep count, taken from the engine so the catalogue cannot show a level
/// the engine would not produce. The reps walk 3, 8, 12 and 15 because the engine gives high,
/// moderate, low and unevaluated there.
private struct HonestySample {
  let reps: Int
  let level: CertaintyLevel
  let methodology: String
  let citation: String?

  init(reps: Int) {
    let claim = StrengthMath.estimatedOneRepMax(weightKg: 60, reps: reps)
    self.reps = reps
    self.level = CertaintyLevel(claim.certainty)
    self.methodology = claim.source.methodology
    self.citation = claim.source.citation
  }

  static let walk: [HonestySample] = [3, 8, 12, 15].map { HonestySample(reps: $0) }
}

private func honestyNote(_ text: String) -> some View {
  Text(text)
    .hardsetText(.caption)
    .foregroundStyle(Tokens.Color.chalkDim)
    .fixedSize(horizontal: false, vertical: true)
}

/// A message too long for one line, to show the label wrapping instead of truncating.
private let honestyLongMethodology =
  "This estimate applies the Epley equation to the heaviest set logged on this machine in the last "
  + "twelve weeks. It was fitted on sets of two to twelve repetitions, so the further a set sits "
  + "from that range the wider the error, and the app lowers its stated confidence accordingly "
  + "instead of rounding a guess into a figure. Loads logged on a different machine are never "
  + "merged into this number."

// MARK: - Badges

private struct HonestyBadgeStates: View {
  var body: some View {
    CatalogSection("Certainty badges") {
      VStack(alignment: .leading, spacing: Tokens.Spacing.loose) {
        live
        statics
        pressed
      }
    }
  }

  /// The four levels as live badges: the interactive capsule inside its 44 pt hit region.
  private var live: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      honestyNote(
        "Interactive badge at each level the engine can produce. The outline is full strength")
      ForEach(HonestySample.walk, id: \.reps) { sample in
        CertaintyBadge(
          level: sample.level, methodology: sample.methodology, citation: sample.citation)
      }
    }
  }

  /// The static capsule, which states a level without offering to open anything: a faint outline,
  /// so it never imitates a control.
  private var statics: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      honestyNote("Static capsule: the same word and symbol, a faint outline")
      ForEach(HonestySample.walk, id: \.reps) { sample in
        CertaintyCapsule(level: sample.level, isInteractive: false)
      }
    }
  }

  /// The badge pressed: the opacity press, with the capsule's outline and word at the same colour.
  private var pressed: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      honestyNote("Pressed: dims to 80%, no steel face to sink")
      HardsetPressFace(isPressed: true, reduceMotion: false) {
        CertaintyCapsule(level: .high, isInteractive: true)
          .frame(
            minWidth: Tokens.minimumTapTarget,
            minHeight: Tokens.minimumTapTarget,
            alignment: .leading
          )
      }
    }
  }
}

// MARK: - Detail

private struct HonestyDetailStates: View {
  var body: some View {
    CatalogSection("Open detail") {
      VStack(alignment: .leading, spacing: Tokens.Spacing.loose) {
        popover(
          "Popover form, with a citation",
          level: .high, methodology: HonestySample.walk[0].methodology,
          citation: HonestySample.walk[0].citation)
        popover(
          "Popover form, no citation",
          level: .moderate, methodology: HonestySample.walk[1].methodology, citation: nil)
        popover(
          "Popover form, long methodology",
          level: .low, methodology: honestyLongMethodology,
          citation: HonestySample.walk[2].citation)
        largeText
      }
    }
  }

  /// The detail as the anchored popover draws it: its content in the 320 pt reading column on
  /// steel.
  private func popover(
    _ title: String, level: CertaintyLevel, methodology: String, citation: String?
  ) -> some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      honestyNote(title)
      CertaintyDetailContent(level: level, methodology: methodology, citation: citation)
        .frame(maxWidth: 320, alignment: .leading)
        .hardsetCard(selected: false, cornerRadius: Tokens.Radius.card)
    }
  }

  /// The detail in its large-text form: the scrolling sheet layout with its Done button, which a
  /// badge presents from Extra Extra Extra Large up. The sheet's own detents and drag indicator
  /// belong to the system and are not drawn here.
  private var largeText: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      honestyNote("Large-text form: the sheet layout, scrolling, with Done")
      CertaintyDetail(
        level: .moderate, methodology: honestyLongMethodology,
        citation: HonestySample.walk[1].citation, isLargeText: true
      )
      .frame(height: 420)
      .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
    }
  }
}

// MARK: - Chips

private struct HonestyChipStates: View {
  private let assumption = Assumption(
    id: "experience", label: "Assumes intermediate",
    correctionPrompt: "Set your training experience")
  private let long = Assumption(
    id: "experience-long",
    label: "Assumes intermediate experience and a twelve week training age on every machine",
    correctionPrompt: "Set your training experience")

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    CatalogSection("Assumption chip") {
      VStack(alignment: .leading, spacing: Tokens.Spacing.loose) {
        sample("Rest") { live(assumption) }
        sample("Pressed: sinks to steelPressed, the edge and label stay full strength") {
          pressedFace(assumption)
        }
        sample("Long label: wraps, never truncates") { live(long) }
      }
    }
  }

  private func sample<Content: View>(
    _ title: String, @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      honestyNote(title)
      content()
    }
  }

  private func live(_ assumption: Assumption) -> some View {
    AssumptionChip(
      label: assumption.label, correctionPrompt: assumption.correctionPrompt, onCorrect: {})
  }

  /// The chip's own face drawn pressed, around the same label, pencil and padding the live chip
  /// draws, because a `ButtonStyle` cannot be forced pressed in a render. It takes the same shape
  /// the live chip does: a capsule, and at accessibility sizes the control radius, so wrapped text
  /// stays inside its outline.
  @ViewBuilder
  private func pressedFace(_ assumption: Assumption) -> some View {
    if dynamicTypeSize.isAccessibilitySize {
      pressedFace(assumption, in: RoundedRectangle(cornerRadius: Tokens.Radius.control))
    } else {
      pressedFace(assumption, in: Capsule())
    }
  }

  private func pressedFace<S: InsettableShape>(_ assumption: Assumption, in shape: S) -> some View {
    MachinedPressFace(shape: shape, outlined: true, isPressed: true, reduceMotion: false) {
      HStack(spacing: Tokens.Spacing.tight) {
        Text(assumption.label)
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

// MARK: - Readouts

private struct HonestyReadoutStates: View {
  var body: some View {
    CatalogSection("Unevaluated readout") {
      VStack(alignment: .leading, spacing: Tokens.Spacing.loose) {
        sample("Short") {
          UnevaluatedReadout(
            explanation: "No weekly set target is established for any muscle, so none is shown.")
        }
        sample("Long") {
          UnevaluatedReadout(
            explanation:
              "Sets of more than twelve repetitions fall outside the range the one-rep-max "
              + "equation was fitted on, so the app shows no estimate for this lift rather than "
              + "a figure it cannot justify. Log a heavier set of twelve or fewer repetitions on "
              + "this machine and an estimate appears with its own stated confidence.")
        }
      }
    }
  }

  private func sample<Content: View>(
    _ title: String, @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      honestyNote(title)
      content()
    }
  }
}

#if DEBUG
  #Preview("Honesty, all states") {
    HonestyCatalogView()
  }
#endif
