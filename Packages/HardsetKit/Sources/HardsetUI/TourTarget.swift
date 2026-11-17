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
  @State private var lastFrame: CGRect?

  func body(content: Content) -> some View {
    content
      .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
        guard registry != nil else { return }
        lastFrame = frame
        publish()
      }
      .onChange(of: isActive) { publish() }
      .onDisappear { registry?.forget(target, from: source) }
  }

  private func publish() {
    guard let registry else { return }
    registry.report(target, from: source, rect: isActive ? lastFrame : nil)
  }
}
