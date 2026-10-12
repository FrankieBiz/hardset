import HardsetCore
import SwiftUI
import TipKit

// TipKit: `Tip` (iOS 17, macOS 14), `Tips.configure(_:)`,
// `Tips.ConfigurationOption.displayFrequency(_:)`, `View.popoverTip(_:arrowEdge:action:)`,
// `Tip.invalidate(reason:)` -- all the same availability, so no `#available` at this package's
// floors (iOS 26.1, macOS 15).
//
// `Tip` is `Sendable` and its requirements (`title`, `message`, `image`, `rules`) are not
// main-actor isolated, so these conformances are `nonisolated` against HardsetUI's MainActor
// default, as `ProgressionAudioGraph` is for its protocol. They hold no state of their own: the
// one input is a static `@Parameter`, which TipKit stores.

/// The machine chip: loads are kept per machine. Words from `FeatureTip`, tested in Core.
nonisolated struct MachineChipTip: Tip {
  /// Whether `FeatureTipPlan` allows this tip right now. TipKit re-evaluates the rule on change.
  @Parameter static var isEligible: Bool = false

  var title: Text { Text(FeatureTip.machineChip.title) }
  var message: Text? { Text(FeatureTip.machineChip.message) }
  var image: Image? { Image(systemName: FeatureTip.machineChip.symbolName) }
  var rules: [Rule] { [#Rule(Self.$isEligible) { $0 == true }] }
}

/// A movement's name opens its load history.
nonisolated struct MovementHistoryTip: Tip {
  @Parameter static var isEligible: Bool = false

  var title: Text { Text(FeatureTip.movementHistory.title) }
  var message: Text? { Text(FeatureTip.movementHistory.message) }
  var image: Image? { Image(systemName: FeatureTip.movementHistory.symbolName) }
  var rules: [Rule] { [#Rule(Self.$isEligible) { $0 == true }] }
}

/// The app's two tips (spec 4.7): when each may show is Core's (`FeatureTipPlan`); TipKit shows
/// each once, ends it when the feature is used, and shows at most one a day.
public enum HardsetTips {
  /// From `HardsetApp.init()`, once. `.displayFrequency(.daily)` is what holds the two tips to one
  /// a day: with it, no new tip is shown for at least 24 hours after one was. A store TipKit
  /// cannot open means no tips, which costs nothing.
  public static func configure() {
    do {
      try Tips.configure([.displayFrequency(.daily), .datastoreLocation(.applicationDefault)])
    } catch {
      assertionFailure("TipKit could not be configured: \(error)")
    }
  }

  static func update(_ facts: FeatureTipFacts) {
    MachineChipTip.isEligible = FeatureTipPlan.isEligible(.machineChip, facts: facts)
    MovementHistoryTip.isEligible = FeatureTipPlan.isEligible(.movementHistory, facts: facts)
  }
}
