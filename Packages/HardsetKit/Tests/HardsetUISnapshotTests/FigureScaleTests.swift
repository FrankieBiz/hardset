import HardsetUI
import SwiftUI
import Testing

/// The figure scale, pinned as executable checks. Its argument is that size is earned by being a
/// measurement: a number the lifter typed or the app counted may be a monument, and an estimate,
/// whatever formula produced it, is never drawn larger than `readout`. The first four tests hold
/// that rule in the tokens and the ledger without rendering; the last holds the Dynamic Type cap by
/// rendering, because a cap that is not applied would look exactly like one that is until the
/// largest setting.
@MainActor
@Suite("The figure scale")
struct FigureScaleTests {
  typealias Role = Tokens.Text.Role

  @Test func theCeilingForAnEstimateIsTwentyEightPoints() {
    #expect(Tokens.Text.estimateCeiling == 28)
    #expect(Role.readout.baseSize == Tokens.Text.estimateCeiling)
    #expect(Role.readout.mayCarryEstimate)
  }

  /// A new role larger than 28 pt has to be added to this list on purpose, and that is the point of
  /// listing it: the roles that cannot carry an estimate are exactly the measured ones and `hero`,
  /// which draws the keypad's display and the welcome bar's total and never an estimate.
  @Test func onlyMeasuredRolesAreTooLargeToCarryAnEstimate() {
    let tooLarge = Set(Role.allCases.filter { !$0.mayCarryEstimate })
    #expect(tooLarge == [.hero, .figureXL, .countdown, .monument, .monumentAside])
  }

  @Test func theScaleRolesHaveTheirSizes() {
    #expect(Role.figureXL.baseSize == 44)
    #expect(Role.countdown.baseSize == 64)
    #expect(Role.monument.baseSize == 88)
    #expect(Role.monumentAside.baseSize == 72)
    // Titles step down below the figures they sit over.
    #expect(Role.display.baseSize == 28)
    #expect(Role.display.baseSize < Role.figureXL.baseSize)
  }

  @Test func theLedgerNeverDrawsAnEstimateAboveTheCeiling() {
    let estimate = StatLedger.Item(
      label: "Estimated max", value: "112", unit: "kg", isEstimate: true)
    let measured = StatLedger.Item(label: "Volume", value: "800", unit: "lb")
    for kind: StatLedger.MonumentKind? in [.subject, .aside, nil] {
      let role = StatLedger.figureRole(for: estimate, monument: kind)
      #expect(role == .readout)
      #expect(role.mayCarryEstimate)
    }
    #expect(StatLedger.figureRole(for: measured, monument: .subject) == .monument)
    #expect(StatLedger.figureRole(for: measured, monument: .aside) == .monumentAside)
    #expect(StatLedger.figureRole(for: measured, monument: nil) == .figureXL)
  }

  /// The monument is 88 where the screen's subject is the number and 72 where it is an action, so
  /// a number never outranks the action on the screen that exists to take it. Pinned so the aside
  /// cannot drift back up to the subject's size, and so the tiers stay distinct from the
  /// countdown's 64 pt and the row figure's 44.
  @Test func anAsideMonumentIsSmallerThanASubjectMonument() {
    #expect(Role.monumentAside.baseSize < Role.monument.baseSize)
    #expect(Role.monumentAside.baseSize > Role.countdown.baseSize)
    #expect(Role.countdown.baseSize > Role.figureXL.baseSize)
  }

  /// The three scale roles stop at accessibility1 and every other role keeps growing, measured by
  /// rendering one figure at three settings and comparing widths.
  @Test func theScaleRolesStopGrowingAtAccessibility1() throws {
    func width(_ role: Role, _ size: DynamicTypeSize) throws -> Int {
      let renderer = ImageRenderer(
        content: Text("188").hardsetText(role).environment(\.dynamicTypeSize, size).fixedSize()
      )
      renderer.scale = 1
      return try #require(renderer.cgImage).width
    }
    for role in [Role.figureXL, .countdown, .monument, .monumentAside] {
      #expect(role.maximumDynamicTypeSize == .accessibility1)
      #expect(try width(role, .accessibility3) == width(role, .accessibility1), "\(role)")
      #expect(try width(role, .accessibility1) > width(role, .large), "\(role)")
    }
    #expect(Role.readout.maximumDynamicTypeSize == nil)
    #expect(try width(.readout, .accessibility3) > width(.readout, .accessibility1))
  }
}
