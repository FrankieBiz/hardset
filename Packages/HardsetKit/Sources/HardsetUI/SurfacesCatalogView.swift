import SwiftUI

/// The shared surfaces and press faces of the component kit, for review from images: the opacity
/// press and the flat press shown apart, the cards, and the weighted type comparison.
///
/// Static: no state, no I/O. A `ButtonStyle` cannot be forced pressed in a render, so each pressed
/// sample is the style's own face, `HardsetPressFace` or `ControlPressFace`, drawn with
/// `isPressed: true`.
public struct SurfacesCatalogView: View {
  public enum Section: String, CaseIterable, Sendable {
    case press, cards, typeWeight
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
    case .press: PressStates()
    case .cards: CardStates()
    case .typeWeight: TypeWeightStates()
    }
  }
}

// MARK: - Press

private struct PressStates: View {
  var body: some View {
    CatalogSection("Press feedback") {
      VStack(alignment: .leading, spacing: Tokens.Spacing.loose) {
        opacityPress
        flatPress
        disabledSamples
      }
    }
  }

  /// A segment-like label and the dashed slot, rest then pressed. Only the dim shows: neither has a
  /// steel face to sink.
  private var opacityPress: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      note("Opacity press: rest, then pressed. Dims to 80%, no steel face")
      HStack(spacing: Tokens.Spacing.regular) {
        HardsetPressFace(isPressed: false, reduceMotion: false) { segmentLabel("Rest") }
        HardsetPressFace(isPressed: true, reduceMotion: false) { segmentLabel("Pressed") }
      }
      HardsetPressFace(isPressed: false, reduceMotion: false) { dashedSlot("Add movement") }
      HardsetPressFace(isPressed: true, reduceMotion: false) { dashedSlot("Add movement, pressed") }
    }
  }

  /// A circle and a capsule, rest then pressed. Only the sink shows: the face goes to
  /// `steelPressed`, and the label stays at full strength. Under Increase Contrast or Button Shapes
  /// the control edge is drawn in both states and stays at full strength too.
  private var flatPress: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      note("Flat press: rest, then pressed. Sinks to steelPressed, never dims")
      HStack(spacing: Tokens.Spacing.regular) {
        ControlPressFace(
          shape: Circle(), outline: .onRequest, isPressed: false, reduceMotion: false
        ) {
          circleGlyph
        }
        ControlPressFace(
          shape: Circle(), outline: .onRequest, isPressed: true, reduceMotion: false
        ) {
          circleGlyph
        }
        ControlPressFace(
          shape: Capsule(), outline: .onRequest, isPressed: false, reduceMotion: false
        ) {
          capsuleLabel("Rest")
        }
        ControlPressFace(
          shape: Capsule(), outline: .onRequest, isPressed: true, reduceMotion: false
        ) {
          capsuleLabel("Pressed")
        }
      }
    }
  }

  /// The live styles on disabled buttons. Neither reads `isEnabled`, so neither is dimmed and the
  /// label keeps its full contrast.
  private var disabledSamples: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      note("Disabled: not dimmed by either press")
      HStack(spacing: Tokens.Spacing.regular) {
        Button {
        } label: {
          segmentLabel("Opacity")
        }
        .buttonStyle(HardsetPressStyle())
        .disabled(true)
        Button {
        } label: {
          capsuleLabel("Flat")
        }
        .buttonStyle(ControlPressStyle(shape: Capsule(), outline: .onRequest))
        .disabled(true)
      }
    }
  }

  private func note(_ text: String) -> some View {
    Text(text)
      .hardsetText(.caption)
      .foregroundStyle(Tokens.Color.chalkDim)
      .fixedSize(horizontal: false, vertical: true)
  }

  private func segmentLabel(_ title: String) -> some View {
    Text(title)
      .font(Tokens.Text.headline)
      .foregroundStyle(Tokens.Color.chalk)
      .padding(.horizontal, Tokens.Spacing.loose)
      .frame(minHeight: Tokens.minimumTapTarget)
      .background(
        Tokens.Color.plateBlueSurface, in: RoundedRectangle(cornerRadius: Tokens.Radius.control))
  }

  private func dashedSlot(_ title: String) -> some View {
    let shape = RoundedRectangle(cornerRadius: Tokens.Radius.card)
    return Label(title, systemImage: "plus")
      .font(Tokens.Text.headline)
      .foregroundStyle(Tokens.Color.plateBlue)
      .frame(maxWidth: .infinity, minHeight: Tokens.loggerTapTarget)
      .overlay(
        shape.strokeBorder(
          Tokens.Color.controlEdge,
          style: StrokeStyle(lineWidth: Tokens.Stroke.hairline, dash: [5, 4])
        )
      )
  }

  private var circleGlyph: some View {
    Image(systemName: "ellipsis")
      .font(Tokens.Text.headline)
      .foregroundStyle(Tokens.Color.chalk)
      .frame(width: Tokens.minimumTapTarget, height: Tokens.minimumTapTarget)
  }

  private func capsuleLabel(_ title: String) -> some View {
    Text(title)
      .font(Tokens.Text.headline)
      .foregroundStyle(Tokens.Color.chalk)
      .padding(.horizontal, Tokens.Spacing.regular)
      .padding(.vertical, Tokens.Spacing.snug)
  }
}

// MARK: - Cards

private struct CardStates: View {
  var body: some View {
    CatalogSection("Cards") {
      VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
        card("Unselected", note: "steel fill, no border; a hairline under Increase Contrast", selected: false)
        card("Selected", note: "plateBlueSurface fill, 2 pt plateBlue ring", selected: true)
        card(
          "Control radius", note: "the same card at the control radius", selected: false,
          cornerRadius: Tokens.Radius.control)
      }
    }
  }

  private func card(
    _ title: String, note: String, selected: Bool,
    cornerRadius: CGFloat = Tokens.Radius.card
  ) -> some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
      Text(title)
        .font(Tokens.Text.headline)
        .foregroundStyle(Tokens.Color.chalk)
      Text(note)
        .hardsetText(.caption)
        .foregroundStyle(Tokens.Color.chalkDim)
    }
    .padding(Tokens.Spacing.loose)
    .frame(maxWidth: .infinity, alignment: .leading)
    .hardsetCard(selected: selected, cornerRadius: cornerRadius)
    .accessibilityElement(children: .combine)
  }
}

// MARK: - Type weight

/// The same sentence as a plain tracked role and as its weighted variant. The weighted line must
/// read visibly heavier while keeping the role's tracking, which is what the overload exists for.
private struct TypeWeightStates: View {
  private let sentence = "Set 3 of 4 logged at 82.5 kg"

  var body: some View {
    CatalogSection("Type weight") {
      VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
        sample("hardsetText(.caption)") {
          Text(sentence).hardsetText(.caption)
        }
        sample("hardsetText(.caption, weight: .semibold)") {
          Text(sentence).hardsetText(.caption, weight: .semibold)
        }
      }
    }
  }

  private func sample<Content: View>(
    _ label: String, @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
      Text(label)
        .font(Tokens.Text.provenance)
        .foregroundStyle(Tokens.Color.chalkDim)
        .fixedSize(horizontal: false, vertical: true)
      content()
        .foregroundStyle(Tokens.Color.chalk)
        .fixedSize(horizontal: false, vertical: true)
    }
    .accessibilityElement(children: .combine)
  }
}

#if DEBUG
  #Preview("Surfaces, all states") {
    SurfacesCatalogView()
  }
#endif
