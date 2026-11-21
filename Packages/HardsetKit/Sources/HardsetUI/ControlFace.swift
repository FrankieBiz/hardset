import SwiftUI

// MARK: - Where a control sits

/// Where a control sits, which decides the fill that separates it from what is behind it.
///
/// A control straight on `canvas` takes `controlFillOnCanvas`; one on a card or on the keypad's
/// panel takes `steelRaised`. In dark the two are the same colour. In light `steelRaised` on
/// `canvas` is only 1.04:1, so a control sitting on the canvas is white instead, as Apple draws it.
///
/// `hardsetCard()` sets `.steel` for everything inside it, so a button or chip in a card takes no
/// argument. Outside a card the default is `.canvas`; a steel panel that is not a card says so with
/// `hardsetControlSurface(_:)`.
public enum ControlSurface: Sendable, Hashable {
  case canvas
  case steel
}

extension EnvironmentValues {
  /// The surface the controls below are drawn on. See `ControlSurface`.
  @Entry public var hardsetControlSurface: ControlSurface = .canvas
}

public extension View {
  /// Says which surface the controls inside are drawn on, so each takes the fill that separates it
  /// from that surface. Cards do this themselves.
  func hardsetControlSurface(_ surface: ControlSurface) -> some View {
    environment(\.hardsetControlSurface, surface)
  }
}

// MARK: - Outline policy

/// When a control draws its `controlEdge` outline.
///
/// Structure comes from fill, so a labelled control is not outlined by default. The outline stays
/// where nothing else can carry it, and comes back wherever the lifter asked for boundaries.
public enum ControlOutline: Sendable, Hashable {
  /// Only under Increase Contrast or Button Shapes, where every control wears its edge.
  case onRequest
  /// Always: an input that is empty or being typed into, identified by its box.
  case always
}

/// Whether the lifter has asked, through a system setting, for every control to show its edge.
///
/// Increase Contrast collapses `canvas`, `steel` and `steelRaised` to one colour, so the fill step
/// that separates a control is gone and the outline is all that is left. Button Shapes asks for
/// the same thing in words. Both come back as `true` here so no component reads the settings
/// itself and the rule changes in one place.
struct ControlEdgeRequest {
  let contrast: ColorSchemeContrast
  let showsButtonShapes: Bool

  var isRequested: Bool { contrast == .increased || showsButtonShapes }

  func draws(_ outline: ControlOutline) -> Bool {
    outline == .always || isRequested
  }
}

// MARK: - The flat face

/// A control's flat face: a fill that steps off the surface behind it, sinking to `steelPressed`
/// while pressed, with the 3:1 `controlEdge` outline drawn only as `ControlOutline` allows.
///
/// There is no lit edge and no shaded edge: the fill step does the separating. A pressed face keeps
/// any outline it had, so a boundary that is drawn never disappears under a finger, and it never
/// dims. The surface is chosen by `hardsetControlSurface` and the outline by `outline`; the shape
/// is the caller's, so a chip, a key and a header circle share one face.
public struct ControlFaceModifier<S: InsettableShape>: ViewModifier {
  public let shape: S
  public let isPressed: Bool
  public let outline: ControlOutline

  @Environment(\.hardsetControlSurface) private var surface
  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.accessibilityShowButtonShapes) private var showsButtonShapes

  public init(shape: S, isPressed: Bool, outline: ControlOutline) {
    self.shape = shape
    self.isPressed = isPressed
    self.outline = outline
  }

  public func body(content: Content) -> some View {
    let request = ControlEdgeRequest(contrast: contrast, showsButtonShapes: showsButtonShapes)
    content
      .background(shape.fill(fill))
      .overlay {
        if request.draws(outline) {
          shape.strokeBorder(Tokens.Color.controlEdge, lineWidth: Tokens.Stroke.hairline)
        }
      }
      .contentShape(shape)
  }

  private var fill: Color {
    if isPressed { return Tokens.Color.steelPressed }
    switch surface {
    case .canvas: return Tokens.Color.controlFillOnCanvas
    case .steel: return Tokens.Color.steelRaised
    }
  }
}

public extension View {
  /// Gives the view a flat control face. Pass `.always` for an input, which keeps its outline.
  func controlFace<S: InsettableShape>(
    _ shape: S, outline: ControlOutline = .onRequest
  ) -> some View {
    modifier(ControlFaceModifier(shape: shape, isPressed: false, outline: outline))
  }

  /// Gives the view the pressed face: the pressed fill, with any outline the face has kept.
  func controlFacePressed<S: InsettableShape>(
    _ shape: S, outline: ControlOutline = .onRequest
  ) -> some View {
    modifier(ControlFaceModifier(shape: shape, isPressed: true, outline: outline))
  }
}
