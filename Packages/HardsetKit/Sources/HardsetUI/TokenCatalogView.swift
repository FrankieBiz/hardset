import SwiftUI

/// Every token and primitive of the design system on one scrolling page: the palette, machined
/// surfaces, type roles, buttons and keys in their live and pressed states, certainty badges, and
/// the motion and haptic vocabularies.
///
/// It exists so the design can be reviewed from images. The development machine cannot compile
/// SwiftUI, so a macOS CI lane renders this view to PNG in each appearance (dark, light, Increase
/// Contrast, an accessibility text size, Reduce Motion) and the images are what get looked at.
/// It is static on purpose: no state, no database, no network, so a render is the same every
/// time. Nothing in the app presents it.
public struct TokenCatalogView: View {
  /// The six catalogue sections, in page order. The snapshot suite renders them one at a time so
  /// that each image is as tall as its own section and nothing is cropped.
  public enum Section: String, CaseIterable, Sendable {
    case palette, machined, type, buttons, certainty, motion
  }

  private let section: Section?

  /// Pass `nil` for the whole page, which is what previews want; pass a section to render only
  /// that section under its label.
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
    case .palette: PaletteSection()
    case .machined: MachinedSection()
    case .type: TypeSection()
    case .buttons: ButtonSection()
    case .certainty: CertaintySection()
    case .motion: MotionAndHapticSection()
    }
  }
}

// MARK: - Section chrome

/// A catalogue section: the shared section label over its content, so every section reads the
/// same way and none draws its own heading.
private struct CatalogSection<Content: View>: View {
  private let title: String
  private let content: Content

  init(_ title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
      SectionLabel(title)
      content
    }
  }
}

// MARK: - Palette

/// One colour role: its name, its colour, and whether it is a text colour. Text roles are shown
/// as a sample on each of the three surfaces they must be legible on; every other role is a
/// swatch alone. Names and colours are listed together by hand rather than reflected from the
/// enum, so a role added to `Tokens.Color` shows up here only when someone chooses where.
private struct PaletteEntry: Identifiable {
  let name: String
  let color: Color
  let isText: Bool
  var id: String { name }
}

private enum PaletteCatalog {
  /// Ordered as the design document is: surfaces, edges, text, then the plate hues in family
  /// order, the warning hue, and the chart series.
  static let entries: [PaletteEntry] = [
    PaletteEntry(name: "canvas", color: Tokens.Color.canvas, isText: false),
    PaletteEntry(name: "steel", color: Tokens.Color.steel, isText: false),
    PaletteEntry(name: "steelRaised", color: Tokens.Color.steelRaised, isText: false),
    PaletteEntry(name: "steelPressed", color: Tokens.Color.steelPressed, isText: false),
    PaletteEntry(name: "edgeLight", color: Tokens.Color.edgeLight, isText: false),
    PaletteEntry(name: "edgeShadow", color: Tokens.Color.edgeShadow, isText: false),
    PaletteEntry(name: "hairline", color: Tokens.Color.hairline, isText: false),
    PaletteEntry(name: "controlEdge", color: Tokens.Color.controlEdge, isText: false),
    PaletteEntry(name: "chalk", color: Tokens.Color.chalk, isText: true),
    PaletteEntry(name: "chalkDim", color: Tokens.Color.chalkDim, isText: true),
    PaletteEntry(name: "plateBlue", color: Tokens.Color.plateBlue, isText: true),
    PaletteEntry(name: "plateBlueFill", color: Tokens.Color.plateBlueFill, isText: false),
    PaletteEntry(
      name: "plateBlueFillPressed", color: Tokens.Color.plateBlueFillPressed, isText: false),
    PaletteEntry(name: "onPlateBlue", color: Tokens.Color.onPlateBlue, isText: false),
    PaletteEntry(name: "plateBlueSurface", color: Tokens.Color.plateBlueSurface, isText: false),
    PaletteEntry(name: "plateGreen", color: Tokens.Color.plateGreen, isText: true),
    PaletteEntry(name: "plateGreenSurface", color: Tokens.Color.plateGreenSurface, isText: false),
    PaletteEntry(name: "plateYellow", color: Tokens.Color.plateYellow, isText: true),
    PaletteEntry(
      name: "plateYellowSurface", color: Tokens.Color.plateYellowSurface, isText: false),
    PaletteEntry(name: "plateRed", color: Tokens.Color.plateRed, isText: true),
    PaletteEntry(name: "plateRedSurface", color: Tokens.Color.plateRedSurface, isText: false),
    PaletteEntry(name: "warning", color: Tokens.Color.warning, isText: true),
    PaletteEntry(name: "warningSurface", color: Tokens.Color.warningSurface, isText: false),
  ] + series

  /// The chart series, one entry per colour in legend order.
  static let series: [PaletteEntry] = Tokens.Color.series.enumerated().map { index, color in
    PaletteEntry(name: "series[\(index)]", color: color, isText: false)
  }
}

private struct PaletteSection: View {
  var body: some View {
    CatalogSection("Palette") {
      VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
        ForEach(PaletteCatalog.entries) { entry in
          PaletteRow(entry: entry)
        }
      }
    }
  }
}

private struct PaletteRow: View {
  let entry: PaletteEntry
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    if dynamicTypeSize.isAccessibilitySize {
      VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
        name
        HStack(spacing: Tokens.Spacing.snug) { swatchAndSamples }
      }
    } else {
      HStack(spacing: Tokens.Spacing.snug) {
        name.frame(width: 128, alignment: .leading)
        swatchAndSamples
      }
    }
  }

  private var name: some View {
    Text(entry.name)
      .font(Tokens.Text.caption)
      .foregroundStyle(Tokens.Color.chalkDim)
  }

  /// A 44 pt swatch of the colour on a `steel` tile, so surface and edge roles are judged against
  /// steel rather than the page, then, for text roles, the colour as text on each surface.
  @ViewBuilder
  private var swatchAndSamples: some View {
    RoundedRectangle(cornerRadius: Tokens.Radius.control)
      .fill(entry.color)
      .frame(width: Tokens.minimumTapTarget, height: Tokens.minimumTapTarget)
      .padding(Tokens.Spacing.tight)
      .background(Tokens.Color.steel, in: RoundedRectangle(cornerRadius: Tokens.Radius.control))
      .overlay(
        RoundedRectangle(cornerRadius: Tokens.Radius.control)
          .strokeBorder(Tokens.Color.hairline, lineWidth: Tokens.Stroke.hairline)
      )
    if entry.isText {
      PaletteSample(color: entry.color, surface: Tokens.Color.canvas)
      PaletteSample(color: entry.color, surface: Tokens.Color.steel)
      PaletteSample(color: entry.color, surface: Tokens.Color.steelRaised)
    }
  }
}

/// A text colour drawn on one of the surfaces it has to be legible on. The surface gets its own
/// hairline so `canvas` and `steel` stay distinguishable from the page behind them.
private struct PaletteSample: View {
  let color: Color
  let surface: Color

  var body: some View {
    Text("Aa 1.5")
      .font(Tokens.Text.figure)
      .foregroundStyle(color)
      .lineLimit(1)
      .frame(maxWidth: .infinity, minHeight: Tokens.minimumTapTarget)
      .background(surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.control))
      .overlay(
        RoundedRectangle(cornerRadius: Tokens.Radius.control)
          .strokeBorder(Tokens.Color.hairline, lineWidth: Tokens.Stroke.hairline)
      )
  }
}

// MARK: - Machined

private struct MachinedSection: View {
  var body: some View {
    CatalogSection("Machined") {
      VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
        HStack(spacing: Tokens.Spacing.regular) {
          MachinedSample(title: "Raised", style: .raised)
          MachinedSample(title: "Outlined", style: .outlined)
          MachinedSample(title: "Pressed", style: .pressed)
        }
        HStack(spacing: Tokens.Spacing.regular) {
          MachinedSample(title: "", style: .knurled)
            .frame(width: 120, height: Tokens.loggerTapTarget)
          Text("Knurl: texture for a control's face, never behind text")
            .font(Tokens.Text.caption)
            .foregroundStyle(Tokens.Color.chalkDim)
        }
      }
    }
  }
}

private struct MachinedSample: View {
  enum Style { case raised, outlined, pressed, knurled }

  let title: String
  let style: Style

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: Tokens.Radius.control)
    let label = Text(title)
      .font(Tokens.Text.caption)
      .foregroundStyle(Tokens.Color.chalk)
      .frame(maxWidth: .infinity, minHeight: Tokens.loggerTapTarget)
    switch style {
    case .raised:
      label.machinedRaised(shape)
    case .outlined:
      label.machinedRaised(shape, outlined: true)
    case .pressed:
      label.machinedPressed(shape)
    case .knurled:
      // The knurl is clipped to rectangular bounds, so the rounded face clips it back to its
      // corners. Its title is empty: the knurl must never sit behind text, so it is labelled
      // beside the sample instead.
      label.machinedRaised(shape).knurl().clipShape(shape)
    }
  }
}

// MARK: - Type

private struct TypeSection: View {
  var body: some View {
    CatalogSection("Type") {
      VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
        ForEach(Tokens.Text.Role.allCases, id: \.self) { role in
          TypeRow(role: role)
        }
      }
    }
  }
}

private struct TypeRow: View {
  let role: Tokens.Text.Role

  /// Figure roles are shown with a weight, since they exist for numbers; the rest with a name.
  private var sample: String {
    switch role {
    case .hero, .readout, .setEntry, .figure: "132.3 kg"
    default: "Chest press"
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
      Text(String(describing: role))
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.chalkDim)
      Text(sample)
        .hardsetText(role)
        .foregroundStyle(Tokens.Color.chalk)
        .fixedSize(horizontal: false, vertical: true)
    }
    .accessibilityElement(children: .combine)
  }
}

// MARK: - Buttons

/// A button role with the label the catalogue shows for it.
private struct ButtonVariant: Identifiable {
  let title: String
  let role: HardsetButtonStyle.Role
  var id: String { title }
}

private enum ButtonCatalog {
  static let variants: [ButtonVariant] = [
    ButtonVariant(title: "Primary", role: .primary),
    ButtonVariant(title: "Secondary", role: .secondary),
    ButtonVariant(title: "Quiet", role: .quiet),
    ButtonVariant(title: "Destructive", role: .destructive),
  ]
}

private struct ButtonSection: View {
  var body: some View {
    CatalogSection("Buttons") {
      VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
        ForEach(ButtonCatalog.variants) { variant in
          ButtonVariantRows(variant: variant)
        }
        Button("Primary disabled") {}
          .buttonStyle(HardsetButtonStyle(.primary))
          .disabled(true)
        KeyRows()
      }
    }
  }
}

/// One role in both sizes, each beside its pressed state. A `ButtonStyle` cannot be forced
/// pressed in a render, so the pressed instance is drawn directly with the same face.
private struct ButtonVariantRows: View {
  let variant: ButtonVariant

  var body: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      Text("\(variant.title.lowercased()): live, then pressed")
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.chalkDim)
      pair(size: .logger)
      pair(size: .regular)
    }
  }

  private func pair(size: HardsetButtonStyle.Size) -> some View {
    let name = size == .logger ? "\(variant.title) 56" : "\(variant.title) 44"
    return ViewThatFits(in: .horizontal) {
      HStack(spacing: Tokens.Spacing.snug) {
        Button(name) {}.buttonStyle(HardsetButtonStyle(variant.role, size: size))
        PressedButtonSample(title: name, role: variant.role, size: size)
      }
      VStack(spacing: Tokens.Spacing.snug) {
        Button(name) {}.buttonStyle(HardsetButtonStyle(variant.role, size: size))
        PressedButtonSample(title: name, role: variant.role, size: size)
      }
    }
  }
}

/// A button's pressed face, drawn directly. Secondary goes through `MachinedModifier` with
/// `isPressed: true`, which is what the live style does; primary shows its pressed fill, quiet
/// its dimmed label, and destructive its unchanged face, because those are what the live styles
/// do on press.
private struct PressedButtonSample: View {
  let title: String
  let role: HardsetButtonStyle.Role
  let size: HardsetButtonStyle.Size

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: Tokens.Radius.control)
    face(label, shape: shape)
  }

  private var label: some View {
    Text(title)
      .font(size == .logger ? Tokens.Text.headline : Tokens.Text.labelEmphasis)
      .foregroundStyle(foreground)
      .multilineTextAlignment(.center)
      .padding(.horizontal, role == .quiet ? Tokens.Spacing.snug : Tokens.Spacing.loose)
      .padding(.vertical, Tokens.Spacing.snug)
      .frame(
        maxWidth: .infinity,
        minHeight: size == .logger ? Tokens.loggerTapTarget : Tokens.minimumTapTarget
      )
  }

  @ViewBuilder
  private func face<Content: View>(_ content: Content, shape: RoundedRectangle) -> some View {
    switch role {
    case .primary:
      content.background(Tokens.Color.plateBlueFillPressed, in: shape)
    case .secondary:
      content.modifier(MachinedModifier(shape: shape, isPressed: true, outlined: false))
    case .quiet:
      content.opacity(0.6)
    case .destructive:
      content.background(Tokens.Color.plateRedSurface, in: shape)
    }
  }

  private var foreground: Color {
    switch role {
    case .primary: Tokens.Color.onPlateBlue
    case .secondary: Tokens.Color.chalk
    case .quiet: Tokens.Color.plateBlue
    case .destructive: Tokens.Color.plateRed
    }
  }
}

/// A row of three keypad keys, then the same three drawn pressed.
private struct KeyRows: View {
  private static let digits = ["7", "8", "9"]

  var body: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      Text("keys: live, then pressed")
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.chalkDim)
      HStack(spacing: Tokens.Spacing.snug) {
        ForEach(Self.digits, id: \.self) { digit in
          Button {
          } label: {
            Text(digit).font(Tokens.Text.setEntry)
          }
          .buttonStyle(HardsetKeyStyle())
        }
      }
      HStack(spacing: Tokens.Spacing.snug) {
        ForEach(Self.digits, id: \.self) { digit in
          Text(digit)
            .font(Tokens.Text.setEntry)
            .foregroundStyle(Tokens.Color.chalk)
            .frame(maxWidth: .infinity, minHeight: Tokens.loggerTapTarget)
            .modifier(
              MachinedModifier(
                shape: RoundedRectangle(cornerRadius: Tokens.Radius.control),
                isPressed: true,
                outlined: false
              )
            )
        }
      }
    }
  }
}

// MARK: - Certainty

private struct CertaintySection: View {
  var body: some View {
    CatalogSection("Certainty") {
      VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
        ForEach(CertaintyLevel.allCases, id: \.self) { level in
          CertaintyBadge(level: level, methodology: "Catalogue sample")
        }
      }
    }
  }
}

// MARK: - Motion and haptics

/// A named token and its value, as text. The motion and haptic tokens are not visible things, so
/// the page documents them in words. The values here mirror `Tokens.Motion` and `Tokens.Haptic`
/// and must be updated with them.
private struct TokenFact: Identifiable {
  let name: String
  let value: String
  var id: String { name }
}

private enum MotionCatalog {
  static let motion: [TokenFact] = [
    TokenFact(name: "Motion.press", value: "easeOut, 0.12 s"),
    TokenFact(name: "Motion.state", value: "spring, response 0.30, damping 1.0"),
    TokenFact(name: "Motion.reveal", value: "easeOut, 0.28 s"),
    TokenFact(name: "Motion.stamp", value: "spring, duration 0.3, bounce 0.3"),
    TokenFact(
      name: "Motion.fling",
      value: "interpolating spring, response 0.35, damping ratio 0.80, initialVelocity 0"),
  ]

  static let haptics: [TokenFact] = [
    TokenFact(name: "Haptic.clank", value: "impact, heavy, intensity 1.0"),
    TokenFact(name: "Haptic.success", value: "success"),
    TokenFact(name: "Haptic.error", value: "error"),
    TokenFact(name: "Haptic.selection", value: "selection"),
    TokenFact(name: "Haptic.warning", value: "warning"),
  ]
}

private struct MotionAndHapticSection: View {
  var body: some View {
    CatalogSection("Motion and haptics") {
      VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
        ForEach(MotionCatalog.motion) { fact in
          TokenFactRow(fact: fact)
        }
        ForEach(MotionCatalog.haptics) { fact in
          TokenFactRow(fact: fact)
        }
      }
    }
  }
}

private struct TokenFactRow: View {
  let fact: TokenFact
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) { texts }
      } else {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.snug) { texts }
      }
    }
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder
  private var texts: some View {
    Text(fact.name)
      .font(Tokens.Text.caption)
      .foregroundStyle(Tokens.Color.chalkDim)
      .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : 112, alignment: .leading)
    Text(fact.value)
      .font(Tokens.Text.provenance)
      .foregroundStyle(Tokens.Color.chalk)
      .fixedSize(horizontal: false, vertical: true)
  }
}
