#if canImport(UIKit)
  import Foundation
  import HardsetCore
  import HardsetUI
  import SwiftUI
  import Testing
  import UIKit

  /// Renders the machine usage line as it ships: the caption on the card the gym list draws it in.
  ///
  /// Like the other render suites it is inert unless `HARDSET_SNAPSHOT_DIR` is set, and it asserts
  /// nothing about pixels. Each state is one capture so the line can be read at its real size.
  @MainActor
  @Suite("Machine usage line renders for review", .serialized)
  struct MachineUsageSnapshotTests {
    private static let card = CGSize(width: 402, height: 180)
    private static let day = Date(timeIntervalSince1970: 1_793_000_000)

    /// A machine used across two weeks, with a heaviest working load of 80 kg.
    private static let used = MachineUsage(
      sessionCount: 14, workingSetCount: 312, heaviestLoadKg: 80, lastUsedAt: day)

    private static func line(_ usage: MachineUsage?, unit: WeightUnit = .kilograms) -> some View {
      VStack(alignment: .leading) {
        MachineUsageLine(usage: usage, unit: unit)
      }
      .padding(Tokens.Spacing.loose)
      .frame(maxWidth: .infinity, alignment: .leading)
      .hardsetCard()
      .padding(Tokens.Spacing.loose)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(Tokens.Color.canvas)
    }

    @Test func usedInEveryAppearance() async throws {
      try await Snapshot.capture("machine-usage-used-dark", size: Self.card) {
        Self.line(Self.used)
      }
      try await Snapshot.capture("machine-usage-used-light", size: Self.card, style: .light) {
        Self.line(Self.used)
      }
    }

    /// A machine with nothing logged: nil usage is the absent entry the inventory holds.
    @Test func neverUsed() async throws {
      try await Snapshot.capture("machine-usage-never-dark", size: Self.card) {
        Self.line(nil)
      }
    }

    /// The same 80 kg read in pounds: 176 lb.
    @Test func imperial() async throws {
      try await Snapshot.capture("machine-usage-imperial-dark", size: Self.card) {
        Self.line(Self.used, unit: .pounds)
      }
    }
  }
#endif
