import Foundation
import Testing

@testable import HardsetCore

/// What a run of scale readings is allowed to claim.
@Suite("Bodyweight reports a trend, not the newest number")
struct BodyweightTrendTests {
  let now = Date(timeIntervalSince1970: 1_700_000_000)

  private func reading(_ kg: Double, daysAgo: Double) -> BodyweightReading {
    BodyweightReading(weightKg: kg, measuredAt: now.addingTimeInterval(-daysAgo * 86_400))
  }

  @Test("The readout is a trailing average, so one heavy morning does not move it far")
  func smoothedAveragesTheWindow() {
    let steady = (0..<7).map { reading(80, daysAgo: Double($0)) }
    #expect(BodyweightTrend.smoothed(steady, endingAt: now) == 80)

    // One reading 3.5 kg high moves a seven-day average by half a kilogram, not by 3.5.
    var withSpike = steady
    withSpike[0] = reading(83.5, daysAgo: 0)
    let average = try! #require(BodyweightTrend.smoothed(withSpike, endingAt: now))
    #expect(abs(average - 80.5) < 1e-9)
  }

  @Test("An empty window reads as unknown rather than as a stale number")
  func staleReadingsAreNotCurrent() {
    let old = [reading(80, daysAgo: 30), reading(81, daysAgo: 25)]
    #expect(BodyweightTrend.smoothed(old, endingAt: now) == nil)
  }

  /// The defect this whole type exists to prevent.
  @Test("Two readings a day apart produce no rate at all")
  func twoAdjacentReadingsClaimNothing() {
    let overnight = [reading(80, daysAgo: 1), reading(80.8, daysAgo: 0)]
    let rate = BodyweightTrend.weeklyRate(overnight, asOf: now)

    // Last-minus-first over one day would have called this 5.6 kg a week.
    #expect(rate.certainty == .unevaluated)
    #expect(rate.value == nil)
  }

  @Test("A single reading claims nothing")
  func oneReadingClaimsNothing() {
    #expect(BodyweightTrend.weeklyRate([reading(80, daysAgo: 0)], asOf: now).value == nil)
    #expect(BodyweightTrend.weeklyRate([], asOf: now).value == nil)
  }

  @Test("A month of daily readings recovers the real rate at high certainty")
  func monthOfDailyReadingsIsHighCertainty() {
    // Losing exactly 0.5 kg a week from 85.
    let daily = (0..<28).map { day in
      reading(85 - 0.5 * (Double(27 - day) / 7), daysAgo: Double(day))
    }
    let rate = BodyweightTrend.weeklyRate(daily, asOf: now)

    #expect(rate.certainty == .high)
    let perWeek = try! #require(rate.value)
    #expect(abs(perWeek - -0.5) < 0.01)
  }

  /// Noise must not flip the sign of a real trend, which is the point of fitting rather than
  /// differencing.
  @Test("Daily noise does not reverse a real gain")
  func noiseDoesNotReverseTheTrend() {
    let wobble: [Double] = [0.9, -0.7, 0.4, -1.1, 0.8, -0.5, 0.2, 1.0, -0.9, 0.3, -0.4, 0.6,
                            -0.8, 0.5, 0.1, -0.6, 0.7, -0.3, 0.9, -1.0, 0.2, 0.4, -0.5, 0.8,
                            -0.2, 0.6, -0.7, 0.3]
    let gaining = (0..<28).map { day in
      reading(80 + 0.25 * (Double(27 - day) / 7) + wobble[day], daysAgo: Double(day))
    }
    let perWeek = try! #require(BodyweightTrend.weeklyRate(gaining, asOf: now).value)
    #expect(perWeek > 0)
  }

  @Test("A fortnight is hedged, and a sparse month is hedged harder")
  func certaintyTracksSpanAndDensity() {
    let fortnight = (0..<8).map { day in reading(80, daysAgo: Double(day) * 2) }
    #expect(BodyweightTrend.weeklyRate(fortnight, asOf: now).certainty == .moderate)

    // Nine days apart, three readings: spans enough to exist, far too sparse to state plainly.
    let sparse = [reading(80, daysAgo: 18), reading(80, daysAgo: 9), reading(80, daysAgo: 0)]
    #expect(BodyweightTrend.weeklyRate(sparse, asOf: now).certainty == .low)
  }

  @Test("Readings older than the window are excluded from the rate")
  func windowExcludesOldReadings() {
    // A steep climb two months ago, flat since. The rate must describe now, not then.
    let old = (0..<10).map { day in reading(70 + Double(day), daysAgo: 60 - Double(day)) }
    let recent = (0..<20).map { day in reading(80, daysAgo: Double(day)) }
    let perWeek = try! #require(BodyweightTrend.weeklyRate(old + recent, asOf: now).value)
    #expect(abs(perWeek) < 0.01)
  }

  /// Many readings sharing one timestamp span zero days, which the span check alone cannot catch.
  @Test("Readings that all share a timestamp produce no rate")
  func simultaneousReadingsClaimNothing() {
    let piled = (0..<10).map { _ in reading(80, daysAgo: 0) }
    #expect(BodyweightTrend.weeklyRate(piled, asOf: now).value == nil)
  }

  @Test("Future readings are not counted")
  func futureReadingsExcluded() {
    let mixed = [reading(80, daysAgo: 10), reading(80, daysAgo: 0), reading(95, daysAgo: -5)]
    let average = try! #require(BodyweightTrend.smoothed(mixed, endingAt: now))
    #expect(average == 80)
  }

  /// Guideline 1.4.1 asks for the methodology in plain language wherever a number is derived.
  @Test("The trend carries its methodology, in no particular unit")
  func sourceIsStated() {
    #expect(!BodyweightTrend.source.methodology.isEmpty)
    #expect(BodyweightTrend.source.validRange?.isEmpty == false)
    // The disclosure sits directly under a figure rendered in the user's chosen unit. Naming
    // kilograms there contradicted the "0.9 lb a week" printed an inch above it.
    #expect(!BodyweightTrend.source.methodology.lowercased().contains("kilogram"))
    #expect(BodyweightTrend.source.validRange?.lowercased().contains("kilogram") == false)
  }

  /// A fit is essentially never exactly zero, so without a threshold the app would report a body
  /// that has not moved in a month as gaining 0.02 kg a week.
  @Test("A negligible slope reads as steady, not as a direction")
  func negligibleSlopeIsSteady() {
    #expect(BodyweightTrend.direction(perWeek: 0.02) == .steady)
    #expect(BodyweightTrend.direction(perWeek: -0.09) == .steady)
    #expect(BodyweightTrend.direction(perWeek: 0.4) == .gaining)
    #expect(BodyweightTrend.direction(perWeek: -0.4) == .losing)
  }

  @Test("A flat month is reported as steady end to end")
  func flatMonthIsSteady() {
    let flat = (0..<28).map { day in reading(80, daysAgo: Double(day)) }
    let perWeek = try! #require(BodyweightTrend.weeklyRate(flat, asOf: now).value)
    #expect(BodyweightTrend.direction(perWeek: perWeek) == .steady)
  }

  @Test("The plotted line is the trailing average, oldest first")
  func smoothedSeriesIsOrderedAndAveraged() {
    let readings = (0..<10).map { day in reading(80, daysAgo: Double(day)) }
    let series = BodyweightTrend.smoothedSeries(readings)

    #expect(series.count == readings.count)
    #expect(series == series.sorted { $0.measuredAt < $1.measuredAt })
    #expect(series.allSatisfy { $0.weightKg == 80 })
  }

  /// The point of plotting the average: a sawtooth in the raw readings must not appear in the line.
  @Test("A sawtooth in the readings is flattened in the plotted line")
  func smoothedSeriesFlattensSawtooth() {
    let sawtooth = (0..<14).map { day in
      reading(day.isMultiple(of: 2) ? 81 : 79, daysAgo: Double(13 - day))
    }
    let series = BodyweightTrend.smoothedSeries(sawtooth)

    // Raw swing is 2 kg between adjacent points; the averaged line must be far tighter once the
    // window has filled.
    let settled = series.dropFirst(BodyweightTrend.smoothingDays).map(\.weightKg)
    let swing = (settled.max() ?? 0) - (settled.min() ?? 0)
    #expect(swing < 0.5)
  }
}
