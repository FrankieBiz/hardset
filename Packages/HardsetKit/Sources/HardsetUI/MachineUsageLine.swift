import Foundation
import HardsetCore
import SwiftUI

/// One machine's logged history in the words the gym list uses.
///
/// Kept as its own view rather than composed inside `GymManagementScreen` so the exact shipped
/// string can be rendered for review at the size and colours it ships in. A nil usage means the
/// machine has no working sets at all, which reads as `MachineUsageCopy.neverUsed`; no date, count
/// or load is invented for it.
public struct MachineUsageLine: View {
  private let usage: MachineUsage?
  private let unit: WeightUnit

  public init(usage: MachineUsage?, unit: WeightUnit) {
    self.usage = usage
    self.unit = unit
  }

  public var body: some View {
    Text(Self.text(usage: usage, unit: unit))
      .font(Tokens.Text.caption)
      .foregroundStyle(Tokens.Color.chalkDim)
      .fixedSize(horizontal: false, vertical: true)
  }

  /// The same line as a string, for a row that already draws its own caption.
  ///
  /// The gym list hands this to `ManagedRow`, whose detail line is the same caption style, so the
  /// words and the formatting live here once and are never re-typed by a screen.
  public static func text(usage: MachineUsage?, unit: WeightUnit) -> String {
    guard let usage, !usage.isNeverUsed else { return MachineUsageCopy.neverUsed }
    return MachineUsageCopy.summary(
      lastUsed: usage.lastUsedAt?.formatted(.dateTime.day().month(.abbreviated)),
      sessions: usage.sessionCount,
      workingSets: usage.workingSetCount,
      heaviest: usage.heaviestLoadKg.map { load($0, in: unit) }
    )
  }

  /// An integer load reads without a decimal point; a half reads as `.5`. The value is the
  /// log's own load rounded the way every displayed estimate is, then written in the chosen unit.
  private static func load(_ kilograms: Double, in unit: WeightUnit) -> String {
    let display = StrengthMath.displayRounded(kilograms, in: unit)
    let number = display.formatted(.number.precision(.fractionLength(0...1)).grouping(.never))
    return "\(number) \(unit.abbreviation)"
  }
}
