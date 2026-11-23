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
  /// session at 402 by 874 points, the size of the phones it is built for, asks the tour's target
  /// registry where the keypad, the rest bar and the next set's check actually are, and asserts the
  /// two things that are pinned. It writes every number it measured to `thumb-reach.txt` beside the
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

    /// Hosts `content` in a window of `size`, lets it settle, and returns where the tour's targets
    /// are in window coordinates. Read before the window goes away, because a view that disappears
    /// forgets what it reported.
    private static func measure<Content: View>(
      size: CGSize = Snapshot.phone,
      @ViewBuilder _ content: () -> Content
    ) async throws -> [TourTarget: CGRect] {
      let registry = TourTargets()
      let host = UIHostingController(
        rootView: content()
          .environment(\.tourTargets, registry)
          .environment(\.colorScheme, .dark)
      )
      host.overrideUserInterfaceStyle = .dark
      let window = UIWindow(frame: CGRect(origin: .zero, size: size))
      window.overrideUserInterfaceStyle = .dark
      window.rootViewController = host
      window.makeKeyAndVisible()
      host.view.frame = window.bounds
      host.view.layoutIfNeeded()
      try await Task.sleep(for: .milliseconds(800))
      host.view.layoutIfNeeded()

      var rects: [TourTarget: CGRect] = [:]
      for target in [TourTarget.keypad, .restBar, .logCheck] {
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

      let withKeypad = try await Self.measure {
        Fixtures.session(pinned: false)
          .environment(\.tourStaging, TourStaging(opensKeypad: true, presentsSheetsInline: true))
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
