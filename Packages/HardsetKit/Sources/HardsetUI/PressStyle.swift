import SwiftUI

// MARK: - Press style

/// Press feedback for a control that draws its own shape and fill and has no flat face: a
/// segment, the dashed "Add movement" slot, the exercise-name link, the dismiss glyph, an unset
/// machine chip, the "Clear search" glyph and the certainty badge capsule. The ready and next-up
/// set log control takes the same press without this style: the set row's private
/// `SetReadoutStyle` draws `SetLogControlFace`, which wraps `HardsetPressFace`, the face this
/// style is built on.
///
/// The same 0.97 sink on `Motion.press` as `HardsetButtonStyle`, with opacity standing in for a
/// pressed fill because each of these controls owns its fill. With Reduce Motion the scale is
/// dropped and only the opacity changes. It never dims a disabled control, so an inert title keeps
/// its measured contrast.
///
/// Flat faces do not use it. Chips, header circles, `AssumptionChip`, a set machine chip and the
/// set-row value fields are raised fills that sink to `steelPressed`, through `ControlPressStyle`
/// or a style of their own, so a press never dims a boundary that is drawn.
public struct HardsetPressStyle: ButtonStyle {
  public init() {}

  public func makeBody(configuration: Configuration) -> some View {
    HardsetPressBody(configuration: configuration)
  }
}

private struct HardsetPressBody: View {
  let configuration: ButtonStyleConfiguration

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    HardsetPressFace(isPressed: configuration.isPressed, reduceMotion: reduceMotion) {
      configuration.label
    }
    .animation(
      Tokens.Motion.adaptive(Tokens.Motion.press, reduceMotion: reduceMotion),
      value: configuration.isPressed
    )
  }
}

/// The opacity press in a given state: the label at 0.97 scale and 80% opacity while pressed, the
/// scale dropped under Reduce Motion. `HardsetPressStyle` draws its live controls with it, and the
/// surfaces catalogue draws its pressed samples with it, because a `ButtonStyle` cannot be forced
/// pressed in a render. Sharing the face keeps the catalogue honest: a sample cannot drift from
/// what a press actually shows. The animation stays in the style, since it is motion rather than a
/// face.
struct HardsetPressFace<Label: View>: View {
  private let isPressed: Bool
  private let reduceMotion: Bool
  private let label: Label

  init(isPressed: Bool, reduceMotion: Bool, @ViewBuilder label: () -> Label) {
    self.isPressed = isPressed
    self.reduceMotion = reduceMotion
    self.label = label()
  }

  var body: some View {
    label
      .scaleEffect(isPressed && !reduceMotion ? 0.97 : 1)
      .opacity(isPressed ? 0.8 : 1)
  }
}

/// The flat press in a given state: the label on a raised fill that sinks to `steelPressed`,
/// scaled to 0.97 unless Reduce Motion is on. Nothing dims, so a boundary drawn by `outline` never
/// fades under a finger.
///
/// The face owns its control's hit region. After the flat face it applies the 44 pt minimum frame
/// and a rectangular content shape, because a frame applied outside a `Button` reserves space
/// without reliably extending what can be tapped. A compact capsule therefore sits inside a region
/// of at least 44 by 44 pt, and a header circle, which starts at 44 pt, keeps its size. The surface
/// is one modifier whose pressed state only changes its arguments, so the label keeps its identity
/// across a press.
///
/// The fill follows the surface the control sits on (see `ControlSurface`), and `outline` says
/// whether it is drawn by default (`.always`, an input) or only when the lifter has asked for
/// boundaries (`.onRequest`).
struct ControlPressFace<Label: View, S: InsettableShape>: View {
  private let shape: S
  private let outline: ControlOutline
  private let isPressed: Bool
  private let reduceMotion: Bool
  private let label: Label

  init(
    shape: S,
    outline: ControlOutline,
    isPressed: Bool,
    reduceMotion: Bool,
    @ViewBuilder label: () -> Label
  ) {
    self.shape = shape
    self.outline = outline
    self.isPressed = isPressed
    self.reduceMotion = reduceMotion
    self.label = label()
  }

  var body: some View {
    label
      .modifier(ControlFaceModifier(shape: shape, isPressed: isPressed, outline: outline))
      .frame(minWidth: Tokens.minimumTapTarget, minHeight: Tokens.minimumTapTarget)
      .contentShape(Rectangle())
      .scaleEffect(isPressed && !reduceMotion ? 0.97 : 1)
  }
}

/// The button style for a control with a flat raised face: header circles, `AssumptionChip` and a
/// set machine chip. It feeds `configuration.isPressed` into `ControlPressFace` and animates the
/// press through `Motion.press`, which Reduce Motion replaces with an instant swap. It never reads
/// `isEnabled`, so a disabled control is not dimmed.
struct ControlPressStyle<S: InsettableShape>: ButtonStyle {
  private let shape: S
  private let outline: ControlOutline

  init(shape: S, outline: ControlOutline) {
    self.shape = shape
    self.outline = outline
  }

  func makeBody(configuration: Configuration) -> some View {
    ControlPressBody(configuration: configuration, shape: shape, outline: outline)
  }
}

private struct ControlPressBody<S: InsettableShape>: View {
  let configuration: ButtonStyleConfiguration
  let shape: S
  let outline: ControlOutline

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ControlPressFace(
      shape: shape,
      outline: outline,
      isPressed: configuration.isPressed,
      reduceMotion: reduceMotion
    ) {
      configuration.label
    }
    .animation(
      Tokens.Motion.adaptive(Tokens.Motion.press, reduceMotion: reduceMotion),
      value: configuration.isPressed
    )
  }
}

// MARK: - Inline control

/// The style of a control that is only its label: words, a symbol or both, with no fill, no
/// outline and no shape of its own.
///
/// This is how a control looks when type carries the screen. The caller sets the label's font and
/// colour; the style supplies the hit region and the press. The region is `minHeight` tall, 44 pt
/// in general and the logger's 56 pt where a missed tap costs a set, and rectangular, because
/// there is no face to define it. Pressed, the label sinks to 0.97 and dims to 80% on
/// `Motion.press`, as every control that draws no fill of its own does, and Reduce Motion drops
/// the scale.
///
/// Where the lifter has asked for boundaries, through Increase Contrast or Button Shapes, the
/// label gets the 3:1 `controlEdge` outline and a little padding to sit inside it, so a control
/// that looks like plain text still looks like a control to anyone who asked it to. A disabled
/// control is dimmed to 40% only when `dimsWhenDisabled` says so: an inert title keeps its
/// contrast, an action that cannot be used does not.
public struct InlineControlStyle: ButtonStyle {
  let minWidth: CGFloat?
  let minHeight: CGFloat
  let alignment: Alignment
  let fullWidth: Bool
  let dimsWhenDisabled: Bool
  let outlinesRegion: Bool

  /// - Parameter minWidth: A floor on the hit region's width, for a control whose label can be
  ///   narrower than a fingertip, such as a single digit and a glyph. The label keeps its
  ///   `alignment` inside the region, so a trailing figure stays on its column's edge. `nil`, the
  ///   default, leaves the width to the label.
  public init(
    minWidth: CGFloat? = nil,
    minHeight: CGFloat = Tokens.minimumTapTarget,
    alignment: Alignment = .leading,
    fullWidth: Bool = false,
    dimsWhenDisabled: Bool = false,
    outlinesRegion: Bool = false
  ) {
    self.minWidth = minWidth
    self.minHeight = minHeight
    self.alignment = alignment
    self.fullWidth = fullWidth
    self.dimsWhenDisabled = dimsWhenDisabled
    self.outlinesRegion = outlinesRegion
  }

  public func makeBody(configuration: Configuration) -> some View {
    InlineControlBody(
      configuration: configuration, minWidth: minWidth, minHeight: minHeight, alignment: alignment,
      fullWidth: fullWidth, dimsWhenDisabled: dimsWhenDisabled, outlinesRegion: outlinesRegion)
  }
}

private struct InlineControlBody: View {
  let configuration: ButtonStyleConfiguration
  let minWidth: CGFloat?
  let minHeight: CGFloat
  let alignment: Alignment
  let fullWidth: Bool
  let dimsWhenDisabled: Bool
  let outlinesRegion: Bool

  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.accessibilityShowButtonShapes) private var showsButtonShapes

  var body: some View {
    let request = ControlEdgeRequest(contrast: contrast, showsButtonShapes: showsButtonShapes)
    HardsetPressFace(isPressed: configuration.isPressed, reduceMotion: reduceMotion) {
      configuration.label
        .padding(.horizontal, request.isRequested && !outlinesRegion ? Tokens.Spacing.regular : 0)
        .padding(.vertical, request.isRequested && !outlinesRegion ? Tokens.Spacing.snug : 0)
        .overlay {
          if request.isRequested && !outlinesRegion {
            Tokens.Shape.control
              .strokeBorder(Tokens.Color.controlEdge, lineWidth: Tokens.Stroke.hairline)
          }
        }
        .frame(
          minWidth: minWidth, maxWidth: fullWidth ? .infinity : nil, minHeight: minHeight,
          alignment: alignment)
        // A control whose region is its outline, such as a footer action, is outlined around the
        // whole region and not around its label.
        .overlay {
          if request.isRequested && outlinesRegion {
            Tokens.Shape.control
              .strokeBorder(Tokens.Color.controlEdge, lineWidth: Tokens.Stroke.hairline)
          }
        }
        .contentShape(Rectangle())
    }
    .opacity(dimsWhenDisabled && !isEnabled ? 0.4 : 1)
    .animation(
      Tokens.Motion.adaptive(Tokens.Motion.press, reduceMotion: reduceMotion),
      value: configuration.isPressed
    )
  }
}
