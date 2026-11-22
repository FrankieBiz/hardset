#if canImport(UIKit)
  import Foundation
  import HardsetUI
  import SwiftUI
  import Testing
  import UIKit

  /// Renders the ledger the way the Train tab's last-workout card and the live session's totals
  /// draw it, for review from images. The real root view cannot stand in: this renderer cannot draw
  /// the tab bar's glass and veils the whole screen, so the card's ledger is drawn through the same
  /// `StatLedger`, inside the same card, instead.
  ///
  /// It exists to look at the three layouts a ledger can take that the screens' own captures do not
  /// reach: a measured monument over its columns at five-digit volume, an estimate offered as a
  /// monument and drawn at the readout size instead, and a four-figure ledger too wide for one line
  /// wrapping rather than clipping. Like the other render suites it is inert unless
  /// `HARDSET_SNAPSHOT_DIR` is set and it asserts nothing about pixels.
  @MainActor
  @Suite("Ledger renders for review", .serialized)
  struct LedgerSnapshotTests {
    private static let tall = CGSize(width: 402, height: 1300)
    private static let narrow = CGSize(width: 375, height: 1300)

    /// The Train card's ledger: volume leads at 88 pt, sets and reps under it at 44 pt.
    private static var trainCard: StatLedger {
      StatLedger(
        [
          StatLedger.Item(label: "Working sets", value: "14"),
          StatLedger.Item(label: "Reps", value: "112"),
        ],
        monument: StatLedger.Item(label: "Volume", value: "12,800", unit: "lb"))
    }

    /// An estimate handed to the ledger as its monument. It must come out at the readout size.
    private static var estimateAsMonument: StatLedger {
      StatLedger(
        [StatLedger.Item(label: "Sets behind it", value: "6")],
        monument: StatLedger.Item(
          label: "Estimated max", value: "112", unit: "kg", isEstimate: true))
    }

    /// The live session's totals late in a long workout: four figures and a five-digit volume,
    /// which are wider than a 375 pt line at 44 pt and have to wrap.
    private static var sessionTotals: StatLedger {
      StatLedger([
        StatLedger.Item(label: "Working sets", value: "18"),
        StatLedger.Item(label: "Reps", value: "144"),
        StatLedger.Item(label: "Volume", value: "25,600", unit: "lb"),
        StatLedger.Item(label: "Warm-ups", value: "4"),
      ])
    }

    private static func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
      content()
        .padding(Tokens.Spacing.loose)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hardsetCard()
    }

    private static var samples: some View {
      VStack(alignment: .leading, spacing: Tokens.Spacing.section) {
        card { trainCard }
        card { estimateAsMonument }
        sessionTotals
      }
      .padding(Tokens.Spacing.loose)
      .frame(maxHeight: .infinity, alignment: .top)
      .background(Tokens.Color.canvas)
    }

    @Test func ledgerLayouts() async throws {
      try await Snapshot.capture("kit-ledger-dark", size: Self.tall) { Self.samples }
      try await Snapshot.capture("kit-ledger-light", size: Self.tall, style: .light) { Self.samples }
      try await Snapshot.capture("kit-ledger-dark-375", size: Self.narrow) { Self.samples }
    }

    @Test func ledgerAtAccessibilitySize() async throws {
      try await Snapshot.capture(
        "kit-ledger-dark-ax3", size: CGSize(width: 402, height: 3400), typeSize: .accessibility3
      ) { Self.samples }
    }
  }
#endif
