import SwiftUI

/// What the first-launch tour asks of the real screens it shows.
///
/// The tour stages the real root view inside a scaled phone, so a step cannot reach a state by being
/// tapped through: the keypad, the machine picker and Settings are all things a lifter opens, and
/// the tour opens them by writing this value into the environment, which the screens read. A step
/// never shows a picture or a lookalike of a screen; it asks the real one to be in a state.
///
/// Outside the tour the value is `TourStaging()`, which asks for nothing, so no screen behaves
/// differently in the daily app.
public struct TourStaging: Equatable, Sendable {
  /// The root's tabs, named without the root's own type, which lives in the feature layer.
  public enum Tab: Sendable {
    case train
    case volume
    case history
  }

  /// The tab the root shows.
  public var tab: Tab = .train
  /// Opens the keypad on the first set still to log.
  public var opensKeypad = false
  /// Opens the machine picker for the first movement.
  public var opensMachinePicker = false
  /// Opens Settings.
  public var showsSettings = false
  /// Draws sheets inside the screen that presents them, instead of over the whole window. A system
  /// sheet always presents over the window, so inside a scaled phone it would appear at full size
  /// on top of everything. The sheet's content is the real content; only the surface it sits on is
  /// the tour's.
  public var presentsSheetsInline = false

  public init(
    tab: Tab = .train, opensKeypad: Bool = false, opensMachinePicker: Bool = false,
    showsSettings: Bool = false, presentsSheetsInline: Bool = false
  ) {
    self.tab = tab
    self.opensKeypad = opensKeypad
    self.opensMachinePicker = opensMachinePicker
    self.showsSettings = showsSettings
    self.presentsSheetsInline = presentsSheetsInline
  }
}

extension EnvironmentValues {
  /// What the tour asks of the screens below. Absent outside the tour.
  @Entry public var tourStaging = TourStaging()
}

// MARK: - Sheets that can draw inline

extension View {
  /// `sheet(isPresented:)`, except that inside the staged tour phone the sheet is drawn over the
  /// bottom of this view, so it stays inside the phone.
  ///
  /// - Parameter inlineHeight: How tall the inline surface is. `nil` fills the view below a small
  ///   margin, as a tall sheet does.
  public func stagedSheet<Sheet: View>(
    isPresented: Binding<Bool>, inlineHeight: CGFloat? = nil, onDismiss: (() -> Void)? = nil,
    @ViewBuilder content: @escaping () -> Sheet
  ) -> some View {
    modifier(
      StagedSheetModifier(
        isPresented: isPresented, inlineHeight: inlineHeight, onDismiss: onDismiss, sheet: content))
  }

  /// `sheet(item:)` with the same inline behaviour.
  public func stagedSheet<Item: Identifiable & Hashable, Sheet: View>(
    item: Binding<Item?>, inlineHeight: CGFloat? = nil, onDismiss: (() -> Void)? = nil,
    @ViewBuilder content: @escaping (Item) -> Sheet
  ) -> some View {
    modifier(
      StagedItemSheetModifier(
        item: item, inlineHeight: inlineHeight, onDismiss: onDismiss, sheet: content))
  }
}

private struct StagedSheetModifier<Sheet: View>: ViewModifier {
  @Binding var isPresented: Bool
  let inlineHeight: CGFloat?
  let onDismiss: (() -> Void)?
  @ViewBuilder let sheet: () -> Sheet

  @Environment(\.tourStaging) private var staging
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    if staging.presentsSheetsInline {
      content
        .overlay(alignment: .bottom) {
          if isPresented {
            InlineSheetSurface(height: inlineHeight, content: sheet)
              .transition(.move(edge: .bottom).combined(with: .opacity))
          }
        }
        .animation(
          Tokens.Motion.adaptive(Tokens.Motion.state, reduceMotion: reduceMotion), value: isPresented
        )
        .onChange(of: isPresented) { old, new in
          if old && !new { onDismiss?() }
        }
    } else {
      content.sheet(isPresented: $isPresented, onDismiss: onDismiss, content: sheet)
    }
  }
}

private struct StagedItemSheetModifier<Item: Identifiable & Hashable, Sheet: View>: ViewModifier {
  @Binding var item: Item?
  let inlineHeight: CGFloat?
  let onDismiss: (() -> Void)?
  @ViewBuilder let sheet: (Item) -> Sheet

  @Environment(\.tourStaging) private var staging
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    if staging.presentsSheetsInline {
      content
        .overlay(alignment: .bottom) {
          if let item {
            InlineSheetSurface(height: inlineHeight) { sheet(item) }
              .id(item)
              .transition(.move(edge: .bottom).combined(with: .opacity))
          }
        }
        .animation(
          Tokens.Motion.adaptive(Tokens.Motion.state, reduceMotion: reduceMotion),
          value: item?.id.hashValue
        )
        .onChange(of: item == nil) { old, new in
          if !old && new { onDismiss?() }
        }
    } else {
      content.sheet(item: $item, onDismiss: onDismiss, content: sheet)
    }
  }
}

/// The surface an inline sheet sits on: steel, with the card radius on its top corners and the lit
/// top edge of a raised face, over whatever the screen shows behind it.
private struct InlineSheetSurface<Content: View>: View {
  let height: CGFloat?
  @ViewBuilder let content: () -> Content

  var body: some View {
    let shape = UnevenRoundedRectangle(
      topLeadingRadius: Tokens.Radius.card, bottomLeadingRadius: 0, bottomTrailingRadius: 0,
      topTrailingRadius: Tokens.Radius.card)
    content()
      .frame(maxWidth: .infinity, maxHeight: height == nil ? .infinity : height)
      .background(Tokens.Color.steel, in: shape)
      .overlay { shape.strokeBorder(Tokens.Color.edgeLight, lineWidth: Tokens.Stroke.hairline) }
      .clipShape(shape)
      .padding(.top, height == nil ? Tokens.Spacing.block * 2 : 0)
  }
}
