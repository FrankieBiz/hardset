#if canImport(UIKit)
  import Foundation
  import HardsetCore
  import SwiftUI
  import Testing
  import UIKit

  @testable import HardsetUI

  /// The accessibility and layout findings of the 1.0 UI review, pinned where they can be: the
  /// arithmetic and the decisions as plain values, and the one hit region that was measured too
  /// small, hosted and measured again. What a screen looks like is in the renders, not here.
  @MainActor
  @Suite("The deferred accessibility findings stay fixed")
  struct AccessibilityBatchTests {
    // MARK: - B1: the movement chart's date axis

    /// The caption role is Footnote, whose point size at each Dynamic Type size is Apple's table.
    private static let footnoteSizes: [(name: String, points: CGFloat)] = [
      ("large", 13), ("xxxLarge", 16), ("accessibility1", 17), ("accessibility2", 19),
      ("accessibility3", 21), ("accessibility4", 23), ("accessibility5", 25),
    ]
    private static let widths: [CGFloat] = [343, 370, 408]

    @Test("The default size keeps its four automatic labels")
    func defaultSizeKeepsFour() {
      let axis = DateAxisLayout(chartWidth: 370, labelPointSize: 13)
      #expect(axis.tickCount == 4)
      #expect(axis.ticks(from: Date(timeIntervalSince1970: 0), to: Date(timeIntervalSince1970: 86_400 * 60)) == nil)
    }

    @Test("An unmeasured chart is laid out as a phone-width one")
    func unmeasuredWidth() {
      #expect(
        DateAxisLayout(chartWidth: 0, labelPointSize: 21)
          == DateAxisLayout(chartWidth: DateAxisLayout.assumedWidth, labelPointSize: 21))
    }

    @Test("At accessibility sizes fewer labels are asked for, never more than at the default")
    func fewerLabelsAsTextGrows() {
      for width in Self.widths {
        var previous = Int.max
        for (_, points) in Self.footnoteSizes {
          let count = DateAxisLayout(chartWidth: width, labelPointSize: points).tickCount
          #expect(count <= previous)
          #expect(count >= DateAxisLayout.minimumTicks && count <= DateAxisLayout.maximumTicks)
          previous = count
        }
      }
      #expect(DateAxisLayout(chartWidth: 370, labelPointSize: 21).tickCount < 4)
    }

    /// The review's failure: at AX3 the labels overprint. Whatever count is chosen, the gap between
    /// neighbouring ticks holds a label and its margin, and an end label has half its width clear.
    @Test("Neighbouring labels have room, and the end labels are whole")
    func labelsHaveRoom() {
      for width in Self.widths {
        for (name, points) in Self.footnoteSizes {
          let axis = DateAxisLayout(chartWidth: width, labelPointSize: points)
          let label = points * DateAxisLayout.labelEms
          let usable = width - points * DateAxisLayout.yAxisEms - 2 * axis.edgeInset
          if axis.tickCount > DateAxisLayout.minimumTicks {
            let spacing = usable / CGFloat(axis.tickCount - 1)
            #expect(
              spacing >= label + DateAxisLayout.gap - 0.001,
              "\(name) at \(width): ticks \(spacing) apart for a \(label) label")
          }
          #expect(axis.edgeInset >= label / 2, "\(name) at \(width): the end label is clipped")
        }
      }
    }

    @Test("Fewer than four labels are placed evenly from the first date to the last")
    func evenTicks() throws {
      let axis = DateAxisLayout(chartWidth: 370, labelPointSize: 21)
      let first = Date(timeIntervalSince1970: 1_000_000)
      let last = first.addingTimeInterval(86_400 * 40)
      let ticks = try #require(axis.ticks(from: first, to: last))
      #expect(ticks.count == axis.tickCount)
      #expect(ticks.first == first)
      #expect(abs(ticks.last!.timeIntervalSince(last)) < 0.001)
      let steps = zip(ticks, ticks.dropFirst()).map { $1.timeIntervalSince($0) }
      #expect(steps.allSatisfy { abs($0 - steps[0]) < 0.001 })
    }

    @Test("A chart with one date has no span to divide, so the automatic ticks stay")
    func noSpan() {
      let day = Date(timeIntervalSince1970: 1_000_000)
      let axis = DateAxisLayout(chartWidth: 370, labelPointSize: 21)
      #expect(axis.ticks(from: day, to: day) == nil)
      #expect(axis.ticks(from: nil, to: nil) == nil)
    }

    // MARK: - B3, B4: a control narrower than a fingertip

    /// Volume's per-muscle count and the Welcome bar's unload control share this style. A single
    /// digit and a glyph measured 37.33 pt wide before the floor.
    @Test("An inline control with a width floor is at least 44 by 44 pt around a single digit")
    func inlineControlFloor() {
      let control = Button {
      } label: {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.snug) {
          Text("5").font(Tokens.Text.setEntry)
          Image(systemName: "info.circle").font(Tokens.Text.caption)
        }
      }
      .buttonStyle(
        InlineControlStyle(minWidth: Tokens.minimumTapTarget, alignment: .trailing))
      let size = UIHostingController(rootView: control).sizeThatFits(
        in: CGSize(width: 402, height: 400))
      #expect(size.width >= Tokens.minimumTapTarget)
      #expect(size.height >= Tokens.minimumTapTarget)
    }

    @Test("Without a floor the same control is narrower than a fingertip")
    func inlineControlWithoutFloor() {
      let control = Button {
      } label: {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.snug) {
          Text("5").font(Tokens.Text.setEntry)
          Image(systemName: "info.circle").font(Tokens.Text.caption)
        }
      }
      .buttonStyle(InlineControlStyle(alignment: .trailing))
      let size = UIHostingController(rootView: control).sizeThatFits(
        in: CGSize(width: 402, height: 400))
      #expect(size.width < Tokens.minimumTapTarget)
    }

    // MARK: - B5: the next set after a log

    @Test("A log at an accessibility size scrolls to the next set")
    func logScrollsAtAccessibilitySize() {
      let next = UUID()
      #expect(
        SessionView.nextUpScrollTarget(
          loggedBefore: 1, loggedAfter: 2, isAccessibilitySize: true, nextUp: next) == next)
    }

    @Test("Nothing scrolls at ordinary sizes, on an undo or a correction, or with no next set")
    func otherwiseNothingScrolls() {
      let next = UUID()
      #expect(
        SessionView.nextUpScrollTarget(
          loggedBefore: 1, loggedAfter: 2, isAccessibilitySize: false, nextUp: next) == nil)
      #expect(
        SessionView.nextUpScrollTarget(
          loggedBefore: 2, loggedAfter: 1, isAccessibilitySize: true, nextUp: next) == nil)
      #expect(
        SessionView.nextUpScrollTarget(
          loggedBefore: 2, loggedAfter: 2, isAccessibilitySize: true, nextUp: next) == nil)
      #expect(
        SessionView.nextUpScrollTarget(
          loggedBefore: 1, loggedAfter: 2, isAccessibilitySize: true, nextUp: nil) == nil)
    }

    // MARK: - B6: the pitch's rep segments

    private static let reps = [1, 3, 12, 15].map { HardsetSegment("\($0) reps", value: $0) }

    @Test("Two columns split four segments into two rows of two, in order")
    func twoColumns() {
      let rows = HardsetSegmentedControl<Int>.rows(Self.reps, columns: 2)
      #expect(rows.map { $0.map(\.value) } == [[1, 3], [12, 15]])
    }

    @Test("No column count, or one the segments already fit, is a single row")
    func singleRow() {
      #expect(HardsetSegmentedControl<Int>.rows(Self.reps, columns: nil).count == 1)
      #expect(HardsetSegmentedControl<Int>.rows(Self.reps, columns: 4).count == 1)
      #expect(HardsetSegmentedControl<Int>.rows(Self.reps, columns: 0).count == 1)
    }

    @Test("An odd count leaves a short last row")
    func shortLastRow() {
      let rows = HardsetSegmentedControl<Int>.rows(Array(Self.reps.prefix(3)), columns: 2)
      #expect(rows.map(\.count) == [2, 1])
    }
  }
#endif
