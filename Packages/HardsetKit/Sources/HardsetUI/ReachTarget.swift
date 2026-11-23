import Observation
import SwiftUI

/// A pinned region whose position the single-thumb reach check measures.
///
/// The check hosts the real logger and asks where these regions actually are, rather than inferring
/// their place from the layout code. Each case is tagged with `reachTarget(_:)` on the view that
/// draws it, so the measurement cannot drift from the control it names.
public enum ReachTarget: Hashable, Sendable {
  /// The keypad.
  case keypad
  /// The rest bar.
  case restBar
  /// The record notice above the rest bar, whichever form it is in. Tagged so the pinned stack's
  /// height can be measured and not assumed (`SingleThumbReachTests`).
  case recordNotice
  /// The check on the set that is next to log.
  case logCheck
}

/// Where the tagged regions are, in window coordinates, for the reach check.
///
/// Tagged views report here rather than through a preference, because the navigation stacks the
/// logger lives in can host their content across a UIKit boundary, which a preference does not
/// cross and the window's coordinate space does.
@MainActor
@Observable
public final class ReachTargets {
  private var reports: [ReachTarget: [UUID: CGRect]] = [:]

  /// Asks the logger to open the keypad on its first set still to log, so the check can measure
  /// where the pad sits. Off everywhere but that measurement.
  public var opensKeypad: Bool

  public init(opensKeypad: Bool = false) {
    self.opensKeypad = opensKeypad
  }

  /// The target's rectangle in window coordinates. When several views carry the same tag, the
  /// topmost wins, so a target repeated down a list is the first one. `nil` when none is on screen.
  public func rect(for target: ReachTarget) -> CGRect? {
    reports[target]?.values.min { ($0.minY, $0.minX) < ($1.minY, $1.minX) }
  }

  func report(_ target: ReachTarget, from source: UUID, rect: CGRect?) {
    var forTarget = reports[target] ?? [:]
    guard forTarget[source] != rect else { return }
    forTarget[source] = rect
    reports[target] = forTarget
  }

  func forget(_ target: ReachTarget, from source: UUID) {
    guard var forTarget = reports[target], forTarget.removeValue(forKey: source) != nil else {
      return
    }
    reports[target] = forTarget
  }
}

extension EnvironmentValues {
  /// Where tagged regions report. `nil` outside the reach check, and then tagging does nothing.
  @Entry public var reachTargets: ReachTargets?
}

extension View {
  /// Marks this view as a region the reach check measures. Costs nothing outside the check: with no
  /// registry in the environment nothing is measured, and the view is otherwise unchanged.
  ///
  /// - Parameter isActive: Tags only while `true`, for a view that is the target on one row of
  ///   several, such as the check on the set that is next.
  public func reachTarget(_ target: ReachTarget, isActive: Bool = true) -> some View {
    modifier(ReachTargetModifier(target: target, isActive: isActive))
  }
}

private struct ReachTargetModifier: ViewModifier {
  let target: ReachTarget
  let isActive: Bool

  @Environment(\.reachTargets) private var registry
  @State private var source = UUID()

  @ViewBuilder func body(content: Content) -> some View {
    if registry != nil {
      content
        // Measured in a background reader rather than with `onGeometryChange`, because the
        // reader's `onChange(initial: true)` reports the first frame as well as every later one. A
        // control that is laid out once and never moves, such as the check, must still be
        // reported. Only inside the check: outside it the view is returned as it is, so the daily
        // app's set rows do not follow their own position while a list scrolls.
        .background {
          GeometryReader { proxy in
            let frame = proxy.frame(in: .global)
            Color.clear
              .onChange(of: frame, initial: true) { _, new in publish(new) }
              .onChange(of: isActive) { publish(frame) }
          }
        }
        .onDisappear { registry?.forget(target, from: source) }
    } else {
      content
    }
  }

  private func publish(_ frame: CGRect) {
    guard let registry else { return }
    registry.report(target, from: source, rect: isActive ? frame : nil)
  }
}
