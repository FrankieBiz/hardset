#if canImport(UIKit)
  import Foundation
  import HardsetCore
  import HardsetUI
  import SwiftUI
  import Testing
  import UIKit

  /// Renders the "Worked from" sheet as the root view for each surface that opens it, so the
  /// working can be reviewed from images.
  ///
  /// The accounts are derived by Core from sets, not typed in here, so what is captured is the words
  /// a lifter would read. Like the other render suites it is inert unless `HARDSET_SNAPSHOT_DIR` is
  /// set, and it asserts nothing about pixels.
  @MainActor
  @Suite("Worked from sheet renders for review", .serialized)
  struct WorkedFromSheetSnapshotTests {
    private static let tall = CGSize(width: 402, height: 1400)
    private static let accessibility = CGSize(width: 402, height: 5200)

    private static let format = WorkedFromFormat(
      unit: .kilograms, locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "UTC")!)

    /// A session on one machine with a set that is the figure, one below it, a set too long to
    /// estimate, a warm-up, and a set from the same session on other equipment.
    static func estimateAccount() -> WorkedFromAccount {
      let exercise = ExerciseID()
      let hammer = MachineID()
      let cybex = MachineID()
      let session = SessionID()
      let start = Date(timeIntervalSince1970: 1_700_000_000)
      func set(_ kg: Double, _ reps: Int, _ minute: Int, _ machine: MachineID) -> ProgressionSample {
        ProgressionSample(
          sessionID: session, machineID: machine, weightKg: kg, reps: reps,
          completedAt: start.addingTimeInterval(Double(minute) * 60))
      }
      let key = ProgressionKey(exerciseID: exercise, machineID: hammer)
      let working = EstimateWorking.derive(
        key: key, sessionID: session,
        samples: [
          set(100, 5, 5, hammer), set(100, 8, 10, hammer), set(60, 15, 15, hammer),
          set(140, 3, 25, cybex),
        ],
        warmups: [set(60, 10, 0, hammer)],
        estimatesOneRepMax: true,
        label: { $0.machineID == hammer ? "Hammer Strength" : "Cybex" })
      return working!.account(format: format)
    }

    private static func sheet(_ account: WorkedFromAccount) -> some View {
      WorkedFromSheet(account: account)
        .tint(Tokens.Color.plateBlue)
    }

    @Test func estimate() async throws {
      try await Snapshot.capture("kit-worked-from-estimate-dark", size: Self.tall) {
        Self.sheet(Self.estimateAccount())
      }
      try await Snapshot.capture("kit-worked-from-estimate-light", size: Self.tall, style: .light) {
        Self.sheet(Self.estimateAccount())
      }
      try await Snapshot.capture(
        "kit-worked-from-estimate-dark-contrast", size: Self.tall, contrast: .high
      ) {
        Self.sheet(Self.estimateAccount())
      }
    }

    @Test func accessibilitySizes() async throws {
      try await Snapshot.capture(
        "kit-worked-from-estimate-dark-ax3", size: Self.accessibility, typeSize: .accessibility3
      ) {
        Self.sheet(Self.estimateAccount())
      }
    }
  }
#endif
