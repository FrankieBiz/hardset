import Observation
import SwiftUI

/// A place on a real screen the tour can point at.
///
/// Each case is tagged on the real control or region with `tourTarget(_:)`, so the spotlight follows
/// the thing itself and cannot drift from it when the layout changes.
public enum TourTarget: Hashable, Sendable {
  /// The Train tab's start action.
  case startAction
  /// The check on the set that is next to log.
  case logCheck
  /// The keypad.
  case keypad
  /// The rest bar.
  case restBar
  /// The record notice above the rest bar, whichever form it is in. Tagged so the pinned stack's
  /// height can be measured and not assumed (`SingleThumbReachTests`); the tour points at nothing here.
  case recordNotice
  /// The machine picker's list.
  case machineList
  /// The Volume tab's figures.
  case volumeFigures
  /// The History tab's list of workouts.
  case historyList
  /// Settings' units.
  case settingsUnits
}

/// Where the tagged targets are, in window coordinates, for the tour to point at.
///
/// Tagged views report here rather than through a preference, because the tab view and navigation
/// stacks the tour shows can host their content across a UIKit boundary, which a preference does not
/// cross and the window's coordinate space does.
@MainActor
@Observable
public final class TourTargets {
  private var reports: [TourTarget: [UUID: CGRect]] = [:]

  public init() {}

  /// The target's rectangle in window coordinates. When several views carry the same tag, the
  /// topmost wins, so a target repeated down a list is the first one. `nil` when none is on screen.
  public func rect(for target: TourTarget) -> CGRect? {
    reports[target]?.values.min { ($0.minY, $0.minX) < ($1.minY, $1.minX) }
  }

  func report(_ target: TourTarget, from source: UUID, rect: CGRect?) {
    var forTarget = reports[target] ?? [:]
    guard forTarget[source] != rect else { return }
    forTarget[source] = rect
    reports[target] = forTarget
  }

  func forget(_ target: TourTarget, from source: UUID) {
    guard var forTarget = reports[target], forTarget.removeValue(forKey: source) != nil else {
      return
    }
    reports[target] = forTarget
  }
}

extension EnvironmentValues {
  /// Where tagged targets report. `nil` outside the tour, and then tagging does nothing.
  @Entry public var tourTargets: TourTargets?
}

extension View {
  /// Marks this view as something the tour can point at. Costs nothing outside the tour: with no
  /// registry in the environment nothing is measured, and the view is otherwise unchanged.
  ///
  /// - Parameter isActive: Tags only while `true`, for a view that is the target on one row of
  ///   several, such as the check on the set that is next.
  public func tourTarget(_ target: TourTarget, isActive: Bool = true) -> some View {
    modifier(TourTargetModifier(target: target, isActive: isActive))
  }
}

private struct TourTargetModifier: ViewModifier {
  let target: TourTarget
  let isActive: Bool

  @Environment(\.tourTargets) private var registry
  @State private var source = UUID()

  @ViewBuilder func body(content: Content) -> some View {
    if registry != nil {
      content
        // Measured in a background reader rather than with `onGeometryChange`, because the
        // reader's `onChange(initial: true)` reports the first frame as well as every later one. A
        // control that is laid out once and never moves, such as the start button, must still be
        // reported. Only inside the tour: outside it the view is returned as it is, so the daily
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
