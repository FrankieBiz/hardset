import Foundation
import Testing

@testable import HardsetCore

@Suite("The chart says what changed on one machine, and VoiceOver hears the same chart")
struct ProgressionChartModelTests {
  private let day = Date(timeIntervalSince1970: 40_000_000)
  private let kilograms = WeightFormatter(unit: .kilograms, locale: Locale(identifier: "en_US_POSIX"))
  private let pounds = WeightFormatter(unit: .pounds, locale: Locale(identifier: "en_US_POSIX"))

  private func point(
    _ week: Int, _ load: Double, estimate: Double? = nil, certainty: Certainty? = nil
  ) -> ProgressionPoint {
    ProgressionPoint(
      sessionID: SessionID(), machineID: nil, date: day.addingTimeInterval(Double(week) * 604_800),
      heaviestLoadKg: load, bestEstimatedOneRepMaxKg: estimate, workingSets: 3,
      bestEstimateCertainty: certainty)
  }

  private func series(_ label: String, _ points: [ProgressionPoint]) -> ProgressionChartSeries {
    ProgressionChartSeries(label: label, points: points)
  }

  @Test("A rise in load reads as the spec's example")
  func rise() throws {
    let hammer = series("Hammer leg press", [point(0, 100), point(1, 102.5), point(2, 105)])
    let headline = try #require(ProgressionHeadline.make(for: hammer, metric: .heaviestLoad, formatter: kilograms))
    #expect(headline.text == "Hammer leg press: +5 kg over 3 sessions")
    #expect(headline.spoken == "Hammer leg press: up 5 kilograms over 3 sessions")
    // A load is measured, so it carries no certainty badge.
    #expect(headline.certainty == nil)
  }

  @Test("A fall is stated with a minus sign and spoken as down")
  func fall() throws {
    let hammer = series("Hammer leg press", [point(0, 105), point(1, 102.5)])
    let headline = try #require(ProgressionHeadline.make(for: hammer, metric: .heaviestLoad, formatter: kilograms))
    #expect(headline.text == "Hammer leg press: \u{2212}2.5 kg over 2 sessions")
    #expect(headline.spoken == "Hammer leg press: down 2.5 kilograms over 2 sessions")
  }

  @Test("No change, and a single session, say so plainly")
  func flatAndSingle() throws {
    let flat = series("Cybex", [point(0, 80), point(1, 80)])
    #expect(ProgressionHeadline.make(for: flat, metric: .heaviestLoad, formatter: kilograms)?.text
      == "Cybex: no change over 2 sessions")
    let single = series("Cybex", [point(0, 80)])
    let headline = try #require(ProgressionHeadline.make(for: single, metric: .heaviestLoad, formatter: kilograms))
    #expect(headline.text == "Cybex: 80 kg, 1 session")
    #expect(headline.spoken == "Cybex: 80 kilograms, 1 session")
  }

  @Test("An estimate is said with about, and carries its weaker end's certainty")
  func estimate() throws {
    let hammer = series(
      "Hammer leg press",
      [
        point(0, 100, estimate: 120, certainty: .high),
        point(1, 100, estimate: nil),
        point(2, 105, estimate: 126, certainty: .moderate),
      ])
    let headline = try #require(
      ProgressionHeadline.make(for: hammer, metric: .estimatedOneRepMax, formatter: kilograms))
    // The session with no estimate is not plotted, so it is not counted.
    #expect(headline.text == "Hammer leg press: about +6 kg over 2 sessions")
    #expect(headline.spoken == "Hammer leg press: up about 6 kilograms over 2 sessions")
    #expect(headline.certainty == .moderate)
  }

  /// Review Focus: the delta must be the difference of the numbers on screen, in the lifter's unit.
  @Test("In pounds the change is the difference of the two displayed loads")
  func deltaMatchesDisplayedNumbers() throws {
    let hammer = series("Hammer leg press", [point(0, 100), point(1, 102.5)])
    // 100 kg reads 220.46 lb and 102.5 kg reads 225.97 lb.
    #expect(pounds.number(kilograms: 100) == "220.46")
    #expect(pounds.number(kilograms: 102.5) == "225.97")
    let headline = try #require(ProgressionHeadline.make(for: hammer, metric: .heaviestLoad, formatter: pounds))
    #expect(headline.text == "Hammer leg press: +5.51 lb over 2 sessions")
  }

  @Test("A comma-decimal locale gets a comma")
  func germanDecimal() throws {
    let german = WeightFormatter(unit: .kilograms, locale: Locale(identifier: "de_DE"))
    let hammer = series("Hammer", [point(0, 100), point(1, 102.5)])
    #expect(ProgressionHeadline.make(for: hammer, metric: .heaviestLoad, formatter: german)?.text
      == "Hammer: +2,5 kg over 2 sessions")
  }

  /// Review Focus: a machine switch is not progress. 110 kg on the Hammer, then 90 kg on the Cybex,
  /// is not "−20 kg".
  @Test("The headline describes the machine used last and never spans two machines")
  func headlineNeverSpansMachines() throws {
    let hammer = series("Hammer", [point(0, 100), point(1, 110)])
    let cybex = series("Cybex", [point(2, 85), point(3, 90)])
    let headline = try #require(
      ProgressionHeadline.current(in: [hammer, cybex], metric: .heaviestLoad, formatter: kilograms))
    #expect(headline.text == "Cybex: +5 kg over 2 sessions")
    // Order of the input does not matter; recency does.
    #expect(
      ProgressionHeadline.current(in: [cybex, hammer], metric: .heaviestLoad, formatter: kilograms)
        == headline)
  }

  @Test("For estimates, the latest machine that has any estimate speaks")
  func estimateHeadlineSkipsUnestimableSeries() throws {
    let hammer = series("Hammer", [point(0, 100, estimate: 120, certainty: .high), point(1, 100, estimate: 123, certainty: .high)])
    let highReps = series("Cybex", [point(2, 60), point(3, 60)])
    let headline = try #require(
      ProgressionHeadline.current(in: [hammer, highReps], metric: .estimatedOneRepMax, formatter: kilograms))
    #expect(headline.text == "Hammer: about +3 kg over 2 sessions")
    #expect(ProgressionHeadline.current(in: [highReps], metric: .estimatedOneRepMax, formatter: kilograms) == nil)
  }

  @Test("Scrubbing picks the nearest logged session and names its own machine")
  func scrub() throws {
    let hammer = series("Hammer", [point(0, 100), point(1, 110)])
    let cybex = series("Cybex", [point(3, 90)])
    // Two and a half weeks in: nearer the Cybex session (week 3) than the Hammer one (week 1).
    let selection = try #require(
      ProgressionSelection.nearest(
        to: day.addingTimeInterval(2.6 * 604_800), in: [hammer, cybex], metric: .heaviestLoad,
        formatter: kilograms))
    #expect(selection.seriesLabel == "Cybex")
    #expect(selection.text == "Cybex: 90 kg")
    #expect(selection.spoken == "Cybex: 90 kilograms")
    #expect(ProgressionSelection.nearest(to: day, in: [], metric: .heaviestLoad, formatter: kilograms) == nil)
  }

  @Test("VoiceOver's description keeps one series per machine, as drawn")
  func descriptionKeepsSeriesApart() throws {
    let hammer = series("Hammer", [point(0, 100), point(1, 110)])
    let cybex = series("Cybex", [point(2, 85), point(3, 90)])
    let description = try #require(
      ProgressionChartDescription.make(
        exerciseName: "Leg Press", series: [cybex, hammer], metric: .heaviestLoad,
        formatter: kilograms))
    #expect(description.series.map(\.name) == ["Cybex", "Hammer"])
    #expect(description.series.map(\.points.count) == [2, 2])
    #expect(description.series[1].points.map(\.value) == [100, 110])
    #expect(description.series[1].points[0].spokenValue == "100 kilograms")
    #expect(description.valueRange == 85...110)
    #expect(description.dateRange.lowerBound == day)
    #expect(description.title == "Leg Press, heaviest load")
    #expect(description.valueAxisTitle == "Heaviest load in kilograms")
    #expect(description.summary == "Cybex: up 5 kilograms over 2 sessions")
  }

  @Test("A series with nothing to plot is left out, and one value still gives the axis a width")
  func descriptionEdges() throws {
    let estimated = series("Hammer", [point(0, 100, estimate: 116, certainty: .high)])
    let highReps = series("Cybex", [point(1, 60)])
    let description = try #require(
      ProgressionChartDescription.make(
        exerciseName: "Leg Press", series: [estimated, highReps], metric: .estimatedOneRepMax,
        formatter: kilograms))
    #expect(description.series.map(\.name) == ["Hammer"])
    #expect(description.valueRange == 115...117)
    #expect(description.spokenValue(116) == "about 116 kilograms")
    #expect(description.valueAxisTitle == "Estimated one-rep max in kilograms")
    #expect(
      ProgressionChartDescription.make(
        exerciseName: "Leg Press", series: [highReps], metric: .estimatedOneRepMax,
        formatter: kilograms) == nil)
  }

  @Test("Loads draw solid and estimates dashed")
  func estimateIsMarked() {
    #expect(!ProgressionMetric.heaviestLoad.isEstimate)
    #expect(ProgressionMetric.estimatedOneRepMax.isEstimate)
    #expect(ProgressionMetric.estimatedOneRepMax.label == "Est. 1RM")
  }
}
