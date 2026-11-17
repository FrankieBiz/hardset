import HardsetCore
import SwiftUI

/// The first screen's bar: an Olympic bar seen side-on that the lifter loads with plates.
///
/// Tap a plate in the tray, or throw it up, and it rises to the sleeve and lands with a `clank`.
/// Plates stack outward in the order chosen, on both sleeves, and the bar bends a few degrees in
/// proportion to the load and settles on `Motion.state`. Tapping a loaded plate returns it to the
/// tray. The running total is in `hero` beside the bar, in the lifter's unit.
///
/// If the lifter does nothing for four seconds the bar loads one 20 kg plate per side on its own,
/// with the same clank, so the screen demonstrates itself; any touch hands control back. With
/// Reduce Motion the bar is drawn already loaded with 20s, tapping a plate swaps the stack instantly
/// and the `clank` still plays. The bar owns horizontal drags inside its region, so a swipe there
/// does not turn the page; a swipe anywhere else does.
public struct WelcomeBarView: View {
  private let unit: WeightUnit
  private let isAutoDemoEnabled: Bool
  private let onLifterLoaded: () -> Void

  @State private var perSide: [Plate]
  @State private var lifterTouched = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private static let maxPerSide = 5
  private static let barKg = 20.0

  /// - Parameters:
  ///   - initialPlates: The plates already on each sleeve, for a still capture or a preview.
  ///   - isAutoDemoEnabled: Whether the bar loads itself after four idle seconds. Off in captures.
  ///   - onLifterLoaded: Called when the lifter, not the demo, loads a plate.
  public init(
    unit: WeightUnit, initialPlates: [Plate] = [], isAutoDemoEnabled: Bool = true,
    onLifterLoaded: @escaping () -> Void = {}
  ) {
    self.unit = unit
    self.isAutoDemoEnabled = isAutoDemoEnabled
    self.onLifterLoaded = onLifterLoaded
    _perSide = State(initialValue: initialPlates)
  }

  public var body: some View {
    VStack(spacing: Tokens.Spacing.section) {
      bar
      total
      PlateTray { plate in load(plate, byLifter: true) }
    }
    .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in touch() })
    .task(id: lifterTouched) { await demonstrate() }
    .onAppear {
      // Reduce Motion draws the bar already loaded, so there is nothing to wait for or animate.
      if reduceMotion && isAutoDemoEnabled && perSide.isEmpty { perSide = [.twenty] }
    }
  }

  // MARK: - Bar

  private var tilt: Double {
    let loaded = perSide.reduce(0) { $0 + $1.massKg }
    return min(1.6, loaded / 125 * 1.6)
  }

  private var bar: some View {
    HStack(spacing: 0) {
      BarHalf(plates: perSide, isLeading: true, onRemove: remove)
        .rotationEffect(.degrees(-tilt), anchor: .trailing)
      BarHalf(plates: perSide, isLeading: false, onRemove: remove)
        .rotationEffect(.degrees(tilt), anchor: .leading)
    }
    .frame(height: 132)
    .animation(Tokens.Motion.adaptive(Tokens.Motion.state, reduceMotion: reduceMotion), value: perSide)
    .contentShape(Rectangle())
    // The bar owns horizontal drags here, so loading and unloading never turn the page. High
    // priority, because the pager's own pan would otherwise win the drag.
    .highPriorityGesture(DragGesture(minimumDistance: 8).onChanged { _ in touch() })
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Barbell, \(totalText) \(unit.abbreviation) loaded")
    .accessibilityHint("Tap a plate below to load it")
    .accessibilityAction(named: "Remove the outer plate") { if !perSide.isEmpty { remove(perSide.count - 1) } }
  }

  private var totalKg: Double {
    Self.barKg + 2 * perSide.reduce(0) { $0 + $1.massKg }
  }

  private var totalText: String {
    unit.fromKilograms(totalKg).formatted(.number.precision(.fractionLength(0...1)))
  }

  private var total: some View {
    HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.tight) {
      Text(totalText)
        .hardsetText(.hero)
        .foregroundStyle(Tokens.Color.chalk)
        .contentTransition(.numericText())
      Text(unit.abbreviation)
        .hardsetText(.unit)
        .foregroundStyle(Tokens.Color.chalkDim)
    }
    .accessibilityHidden(true)
  }

  // MARK: - Loading

  private func touch() {
    if !lifterTouched { lifterTouched = true }
  }

  private func load(_ plate: Plate, byLifter: Bool) {
    if byLifter {
      touch()
      onLifterLoaded()
    }
    withAnimation(Tokens.Motion.adaptive(Tokens.Motion.fling(initialVelocity: 0), reduceMotion: reduceMotion)) {
      if reduceMotion {
        perSide = [plate]
      } else if perSide.count < Self.maxPerSide {
        perSide.append(plate)
      }
    }
    ClankPlayer.shared.play()
  }

  private func remove(_ index: Int) {
    touch()
    guard perSide.indices.contains(index) else { return }
    withAnimation(Tokens.Motion.adaptive(Tokens.Motion.state, reduceMotion: reduceMotion)) {
      _ = perSide.remove(at: index)
    }
  }

  /// After four idle seconds, loads one 20 kg plate per side. Runs again, and does nothing, once
  /// the lifter has touched anything.
  private func demonstrate() async {
    guard isAutoDemoEnabled, !lifterTouched, perSide.isEmpty, !reduceMotion else { return }
    try? await Task.sleep(for: .seconds(4))
    guard !Task.isCancelled, !lifterTouched, perSide.isEmpty else { return }
    load(.twenty, byLifter: false)
  }
}

/// One half of the bar: its shaft toward the centre, its collar, and its plates stacked outward.
/// The two halves mirror each other, and each rotates about the centre so the bar droops under
/// load.
private struct BarHalf: View {
  let plates: [Plate]
  let isLeading: Bool
  let onRemove: (Int) -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    HStack(spacing: 2) {
      if isLeading {
        stack
        collar
        shaft
      } else {
        shaft
        collar
        stack
      }
    }
    .frame(maxWidth: .infinity, alignment: isLeading ? .trailing : .leading)
  }

  private var shaft: some View {
    let shape = RoundedRectangle(cornerRadius: 5)
    return ZStack {
      shape.fill(
        LinearGradient(
          colors: [Tokens.Color.edgeLight, Tokens.Color.controlEdge, Tokens.Color.edgeShadow],
          startPoint: .top, endPoint: .bottom))
      KnurlPattern(opacity: 0.08).clipShape(shape)
    }
    .frame(height: 10)
    .frame(maxWidth: .infinity)
  }

  private var collar: some View {
    RoundedRectangle(cornerRadius: 2)
      .fill(Tokens.Color.controlEdge)
      .frame(width: 8, height: 30)
  }

  private var stack: some View {
    // The innermost plate sits next to the collar, so the leading half lists them outermost first.
    let ordered = isLeading ? Array(plates.enumerated().reversed()) : Array(plates.enumerated())
    return HStack(spacing: 2) {
      ForEach(ordered, id: \.offset) { index, plate in
        RoundedRectangle(cornerRadius: 3)
          .fill(plate.fill)
          .frame(width: 14, height: plate.barHeight)
          .transition(
            reduceMotion
              ? .opacity : .offset(y: 150).combined(with: .opacity))
          .onTapGesture { onRemove(index) }
      }
    }
  }
}

#if DEBUG
  #Preview("Welcome bar, loaded") {
    WelcomeBarView(unit: .kilograms, initialPlates: [.twentyFive, .twenty, .ten], isAutoDemoEnabled: false)
      .padding(Tokens.Spacing.loose)
      .background(Tokens.Color.canvas)
  }
#endif
