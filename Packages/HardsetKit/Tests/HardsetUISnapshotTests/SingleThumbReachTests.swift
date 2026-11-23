#if canImport(UIKit)
  import Foundation
  import HardsetCore
  import HardsetUI
  import SwiftUI
  import Testing
  import UIKit

  /// The single-thumb pad traversal's reach claim, measured and not assumed.
  ///
  /// DESIGN.md says everything the logger pins is in the lower part of the screen, and that nothing a
  /// lifter needs between sets is out of reach of the thumb that holds the phone. This hosts the live
  /// session at 402 by 874 points, the size of the phones it is built for, asks the reach registry
  /// where the keypad, the rest bar and the next set's check actually are, and asserts the two things
  /// that are pinned. It writes every number it measured to `thumb-reach.txt` beside the
  /// renders, so a reviewer reads the figures and not only the verdict.
  ///
  /// What it does not and cannot say: where a row is in the scrolling list, because that is wherever
  /// the lifter scrolled it, and whether a given hand can reach a given point, which is a device check.
  /// The rows live in the scrolling content on purpose; the header scrolls away with them.
  @MainActor
  @Suite("Single-thumb reach on a 402 by 874 phone", .serialized)
  struct SingleThumbReachTests {
    /// Nothing the logger pins may start above this fraction of the screen's height: the keypad's top
    /// edge is its display, and every key sits below it.
    static let keypadFloor: CGFloat = 0.40
    /// The rest bar and its four 56 pt controls are the bottom of the screen.
    static let restBarFloor: CGFloat = 0.60
    /// At an accessibility size the record notice and the rest bar together may cover at most this
    /// fraction of the screen. Before they were capped they covered about eighty percent at
    /// accessibility3 and left a sliver of the list to log in; the upper half is the list's.
    static let pinnedStackCeiling: CGFloat = 0.50

    /// Hosts `content` in a window of `size`, lets it settle, and returns where the reach targets
    /// are in window coordinates. Read before the window goes away, because a view that disappears
    /// forgets what it reported.
    private static func measure<Content: View>(
      size: CGSize = Snapshot.phone,
      typeSize: DynamicTypeSize = .large,
      opensKeypad: Bool = false,
      @ViewBuilder _ content: () -> Content
    ) async throws -> [ReachTarget: CGRect] {
      let registry = ReachTargets(opensKeypad: opensKeypad)
      let host = UIHostingController(
        rootView: content()
          .environment(\.reachTargets, registry)
          .environment(\.colorScheme, .dark)
          .environment(\.dynamicTypeSize, typeSize)
      )
      host.overrideUserInterfaceStyle = .dark
      // The same plain 402 by 874 window the old tour-tagged measurement used. The pad is drawn
      // inline for this check, so no scene is needed and the safe-area reading matches that harness.
      let window = UIWindow(frame: CGRect(origin: .zero, size: size))
      window.overrideUserInterfaceStyle = .dark
      window.rootViewController = host
      window.makeKeyAndVisible()
      host.view.frame = window.bounds
      host.view.layoutIfNeeded()
      try await Task.sleep(for: .milliseconds(800))
      host.view.layoutIfNeeded()

      var rects: [ReachTarget: CGRect] = [:]
      for target in [ReachTarget.keypad, .restBar, .logCheck, .recordNotice] {
        if let rect = registry.rect(for: target) { rects[target] = rect }
      }
      window.isHidden = true
      window.rootViewController = nil
      return rects
    }

    private static func line(_ name: String, _ rect: CGRect?, height: CGFloat) -> String {
      guard let rect else { return "\(name): not on screen" }
      let top = Int((rect.minY / height * 100).rounded())
      return "\(name): x \(Int(rect.minX))–\(Int(rect.maxX)), y \(Int(rect.minY))–\(Int(rect.maxY)) "
        + "of \(Int(height)) (top edge at \(top)%)"
    }

    @Test func theKeypadIsBelowTheReachFloorAndTheRestBarIsAtTheBottom() async throws {
      let height = Snapshot.phone.height

      let withKeypad = try await Self.measure(opensKeypad: true) {
        Fixtures.session(pinned: false)
      }
      let keypad = try #require(withKeypad[.keypad], "The staged keypad reported no frame.")
      #expect(
        keypad.minY >= height * Self.keypadFloor,
        "The keypad starts at y \(keypad.minY), above \(Self.keypadFloor * 100)% of \(height).")

      let resting = try await Self.measure { Fixtures.session(pinned: true) }
      let restBar = try #require(resting[.restBar], "The rest bar reported no frame.")
      #expect(
        restBar.minY >= height * Self.restBarFloor,
        "The rest bar starts at y \(restBar.minY), above \(Self.restBarFloor * 100)% of \(height).")

      if let directory = Snapshot.directory {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let report = [
          "Single-thumb reach, measured on a \(Int(Snapshot.phone.width)) by \(Int(height)) window.",
          "Pinned, asserted: the keypad starts at or below \(Int(Self.keypadFloor * 100))% and the "
            + "rest bar at or below \(Int(Self.restBarFloor * 100))%.",
          Self.line("keypad (display, steps, keys, Next / Log set)", keypad, height: height),
          Self.line("rest bar (countdown, -15, +15, pause, skip)", restBar, height: height),
          Self.line(
            "next set's log check, at the list's opening scroll position, not asserted",
            resting[.logCheck] ?? withKeypad[.logCheck], height: height),
          "Rows scroll; the header scrolls with them and nothing is pinned to the top.",
        ].joined(separator: "\n")
        try report.write(
          to: directory.appendingPathComponent("thumb-reach.txt"), atomically: true, encoding: .utf8)
      }
    }

    /// A lifter at the largest text sizes must always be able to see and reach the set they are
    /// logging. The record notice and the rest bar are pinned over the list, so what they cover is what
    /// the list loses: this hosts the session with a notice and a running rest at accessibility3 and
    /// accessibility5 and asserts the stack takes no more than half the screen, writing every number
    /// to `pinned-stack.txt`. It cannot say that a given row is on screen, which is wherever the lifter
    /// scrolled it, but it does say how much window the list keeps.
    @Test(arguments: [DynamicTypeSize.accessibility3, DynamicTypeSize.accessibility5])
    func thePinnedStackLeavesRoomToLogAtAccessibilitySizes(typeSize: DynamicTypeSize) async throws {
      let height = Snapshot.phone.height
      let rects = try await Self.measure(typeSize: typeSize) { Fixtures.session(pinned: true) }
      let restBar = try #require(rects[.restBar], "The rest bar reported no frame.")
      let notice = try #require(rects[.recordNotice], "The record notice reported no frame.")

      let top = min(notice.minY, restBar.minY)
      let covered = (height - top) / height
      #expect(
        covered <= Self.pinnedStackCeiling,
        "The notice and the rest bar cover \(Int((covered * 100).rounded()))% of the screen at \(typeSize), above \(Int(Self.pinnedStackCeiling * 100))%."
      )
      // One line for the notice: a count and a close mark, never a sentence per record.
      #expect(
        notice.height <= height * 0.15,
        "The record notice is \(Int(notice.height)) pt tall at \(typeSize); it should be one line.")

      if let directory = Snapshot.directory {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let report = [
          "Pinned stack at \(typeSize), measured on a \(Int(Snapshot.phone.width)) by \(Int(height)) window.",
          "Asserted: the record notice and the rest bar cover at most \(Int(Self.pinnedStackCeiling * 100))% of the screen.",
          "covered: \(Int((covered * 100).rounded()))% (top edge of the stack at y \(Int(top)))",
          Self.line("record notice (collapsed: a count and a close mark)", notice, height: height),
          Self.line("rest bar (countdown and the four controls)", restBar, height: height),
          Self.line("next set's log check, at the list's opening scroll position, not asserted", rects[.logCheck], height: height),
        ].joined(separator: "\n")
        try report.write(
          to: directory.appendingPathComponent("pinned-stack-\(String(describing: typeSize)).txt"),
          atomically: true, encoding: .utf8)
      }
    }

    /// The pad with a machine's own steps, for review: a 4.5 kg pin stack in kilograms, the same
    /// stack in pounds, and the fallback when no increment is recorded. The widest step, "−19.84", is
    /// the one that has to fit its key at the largest ordinary size and at accessibility sizes.
    @Test func rendersTheMachineSteps() async throws {
      func pad(_ unit: WeightUnit, _ incrementKg: Double?) -> some View {
        NumericPad(
          buffer: .constant(
            NumericEntryBuffer(value: 102.5, maximumIntegerDigits: 4, maximumFractionDigits: 2)),
          title: "Weight", context: "Leg Press · Set 2", unit: unit.abbreviation,
          onDone: {}, onNext: {},
          weightSteps: QuickSteps.weight(machineIncrementKg: incrementKg, unit: unit))
      }
      let size = CGSize(width: 402, height: 520)
      try await Snapshot.capture("keypad-machine-step-kg-dark", size: size) { pad(.kilograms, 4.5) }
      try await Snapshot.capture("keypad-machine-step-lb-dark", size: size) { pad(.pounds, 4.5) }
      try await Snapshot.capture("keypad-machine-step-lb-light", size: size, style: .light) {
        pad(.pounds, 4.5)
      }
      try await Snapshot.capture("keypad-fallback-steps-dark", size: size) { pad(.kilograms, nil) }
      try await Snapshot.capture(
        "keypad-machine-step-lb-dark-xxxl", size: CGSize(width: 402, height: 560),
        typeSize: .xxxLarge
      ) { pad(.pounds, 4.5) }
      try await Snapshot.capture(
        "keypad-machine-step-lb-dark-ax3", size: CGSize(width: 402, height: 900),
        typeSize: .accessibility3
      ) { pad(.pounds, 4.5) }
    }

    /// The targets a chalky thumb has to hit: every key and quick step is a logger-height cell, and
    /// the row's machine steps use the same floor. Pinned as numbers so a change to a cell's height
    /// is a change to this test first.
    @Test func theLoggerTargetFloorIsFiftySixPoints() {
      #expect(Tokens.loggerTapTarget == 56)
      #expect(Tokens.minimumTapTarget == 44)
      #expect(Tokens.loggerTapTarget > Tokens.minimumTapTarget)
    }
  }
#endif
