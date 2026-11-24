import Foundation
import Testing

@testable import HardsetCore

@Suite("Muscle history is the paid surface's time, not a repeat of the week")
struct MuscleHistoryTests {
  private let now = Date(timeIntervalSince1970: 1_793_527_200)
  private let bench = ExerciseID()
  private let row = ExerciseID()
  private let mystery = ExerciseID()
  private let format = WorkedFromFormat(
    unit: .kilograms, locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "UTC")!)

  private func contribution(_ muscle: Muscle, _ role: MuscleRole) -> MuscleContribution {
    MuscleContribution(muscle, role: role, certainty: .moderate, source: .anatomy)
  }

  private var attribution: AttributionIndex {
    AttributionIndex([
      bench: [
        contribution(.chest, .direct), contribution(.frontDelts, .indirect),
        contribution(.triceps, .indirect),
      ],
      row: [contribution(.lats, .direct), contribution(.biceps, .indirect)],
    ])
  }

  private func report(
    _ chest: Double = 0, _ triceps: Double = 0, hard: Int = 0
  ) -> MuscleVolumeReport {
    var fractional: [MuscleKey: Double] = [:]
    if chest > 0 { fractional[MuscleKey(.chest)] = chest }
    if triceps > 0 { fractional[MuscleKey(.triceps)] = triceps }
    return MuscleVolumeReport(
      fractionalSets: fractional, hardSets: hard, unattributedHardSets: 0, setsTouchingGroup: [:])
  }

  /// One window, without needing the Store's calendar: only the order and containment matter here.
  private func week(
    _ weeksBack: Int, _ report: MuscleVolumeReport, sets: [CountableSet] = []
  ) -> MuscleHistoryWeek {
    let end = now.addingTimeInterval(-Double(weeksBack) * 7 * 86_400)
    return MuscleHistoryWeek(
      start: end.addingTimeInterval(-7 * 86_400), end: end,
      lastDay: end.addingTimeInterval(-60), report: report, sets: sets)
  }

  private func emptyWeeks() -> [MuscleHistoryWeek] {
    (0..<12).map { week($0, report()) }
  }

  private func history(
    counts: [MuscleHistoryCount], weeks: [MuscleHistoryWeek]? = nil,
    imported: Set<ExerciseID> = []
  ) -> MuscleHistory {
    MuscleHistoryAnalyzer.history(
      counts: counts, weeks: weeks ?? emptyWeeks(), attribution: attribution,
      imported: imported, names: [bench: "Barbell Bench Press", row: "Cable Row"])
  }

  // MARK: - One window trained, the other not

  @Test("A muscle trained in the last week and not five weeks ago shows both counts and the fall")
  func currentOnly() {
    var weeks = emptyWeeks()
    weeks[0] = week(0, report(2, 1, hard: 2))
    weeks[4] = week(4, report(6, 3, hard: 6))
    let counts = [
      MuscleHistoryCount(
        exerciseID: bench, setCount: 8, lastAt: now.addingTimeInterval(-2 * 86_400),
        firstAt: now.addingTimeInterval(-30 * 86_400))
    ]
    let history = history(counts: counts, weeks: weeks)

    #expect(history.currentSets(for: .chest) == 2)
    #expect(history.previousSets(for: .chest) == 6)
    #expect(history.difference(for: .chest) == -4)
    #expect(history.lifetimeSets(for: .chest) == 8)
    let last = history.lastTrained[MuscleKey(.chest)]
    #expect(last?.movementName == "Barbell Bench Press")
    #expect(last?.date == now.addingTimeInterval(-2 * 86_400))
    // Five points: the four empty weeks between the two trained ones are real zeros, not gaps to
    // interpolate across.
    #expect(history.shape(for: .chest) == [6, 0, 0, 0, 2])
  }

  @Test("A muscle trained only in the earlier window reports absence now, not a zero percentage")
  func previousOnly() {
    var weeks = emptyWeeks()
    weeks[4] = week(4, report(6, 3, hard: 6))
    let counts = [
      MuscleHistoryCount(
        exerciseID: bench, setCount: 6, lastAt: now.addingTimeInterval(-30 * 86_400),
        firstAt: now.addingTimeInterval(-30 * 86_400))
    ]
    let history = history(counts: counts, weeks: weeks)

    // Absent, not present-at-zero: the same rule the report keeps for a muscle with no credit.
    #expect(history.current.fractionalSets[MuscleKey(.chest)] == nil)
    #expect(history.currentSets(for: .chest) == 0)
    #expect(history.previousSets(for: .chest) == 6)
    #expect(history.difference(for: .chest) == -6)
    #expect(history.lastTrained[MuscleKey(.chest)]?.date == now.addingTimeInterval(-30 * 86_400))
    let words = MuscleHistoryCopy.comparison(
      current: 0, previous: 6, format: format)
    #expect(words.contains("down from 6"))
    #expect(!words.contains("%"))
  }

  // MARK: - The empty and the not-yet-attributed

  @Test("Nothing at all: absent from every collection, no shape, and the plain absence state")
  func empty() {
    let history = history(counts: [])

    #expect(history.isEmpty)
    #expect(history.lifetime.hardSets == 0)
    #expect(history.lifetime.fractionalSets.isEmpty)
    #expect(history.lastTrained.isEmpty)
    #expect(history.weeks.isEmpty)
    #expect(history.firstSetAt == nil)
    #expect(history.emptyState(for: .chest) == .noneCredited)
    #expect(MuscleHistoryCopy.noCreditedSets == "No credited sets")
  }

  @Test("A muscle with no credit in a history of unattributed sets is a floor, not a fact")
  func unattributedFloor() {
    let counts = [
      MuscleHistoryCount(exerciseID: mystery, setCount: 4, lastAt: now, firstAt: now),
      MuscleHistoryCount(exerciseID: bench, setCount: 2, lastAt: now, firstAt: now),
    ]
    let history = history(counts: counts)
    #expect(history.lifetime.unattributedHardSets == 4)
    #expect(history.isLowerBound)
    #expect(history.emptyState(for: .lats) == .floor(unattributed: 4))
    #expect(history.isTrained(.chest))
    #expect(MuscleHistoryCopy.noCreditedSetsFloor(4).contains("4 working sets have no body part"))
  }

  @Test("Content debt is the catalogue's, never the lifter's")
  func contentDebt() {
    let history = history(counts: [
      MuscleHistoryCount(exerciseID: bench, setCount: 2, lastAt: now, firstAt: now)
    ])
    #expect(history.emptyState(for: .neck) == .contentDebt)
    #expect(MuscleHistoryCopy.noCreditedSetsFloor(2).contains("2 working sets have"))
  }

  // MARK: - Imports

  @Test("An imported movement's sets produce the same figures and its account says it was imported")
  func importsCount() {
    let sets = [CountableSet(exerciseID: bench, isWarmup: false)]
    var weeks = emptyWeeks()
    weeks[0] = week(0, report(1, 0.5, hard: 1), sets: sets)
    let counts = [
      MuscleHistoryCount(exerciseID: bench, setCount: 1, lastAt: now, firstAt: now)
    ]
    let history = history(counts: counts, weeks: weeks, imported: [bench])

    #expect(history.currentSets(for: .chest) == 1)
    #expect(history.lifetimeSets(for: .chest) == 1)
    #expect(history.includesImportedHistory)
    #expect(history.current.fractionalSets[MuscleKey(.chest)] == 1)

    let account = history.account(
      muscle: .chest, figure: .lifetime, muscleName: "Chest", attribution: attribution,
      imported: [bench], name: { $0 == self.bench ? "Bench press (imported)" : "Unknown" },
      format: format)
    let line = account.sections
      .first { $0.id == "credited" }?.lines.first
    #expect(line?.context?.contains("imported movement") == true)
    #expect(account.figure == "1 sets")
  }

  // MARK: - The shape

  @Test("A zero week between two trained weeks keeps its place, so the shape dips")
  func gapInTheMiddle() {
    var weeks = emptyWeeks()
    weeks[0] = week(0, report(3, 1, hard: 3))
    weeks[6] = week(6, report(5, 2, hard: 5))
    let counts = [
      MuscleHistoryCount(
        exerciseID: bench, setCount: 8, lastAt: now, firstAt: now.addingTimeInterval(-45 * 86_400))
    ]
    let history = history(counts: counts, weeks: weeks)
    // Oldest first: week 6 is the first point, then five zero weeks, then the current week.
    #expect(history.shape(for: .chest) == [5, 0, 0, 0, 0, 0, 3])
  }

  @Test("History shorter than twelve weeks draws only the weeks that exist, and says how many")
  func shortHistory() {
    var weeks = emptyWeeks()
    weeks[0] = week(0, report(2, 1, hard: 2))
    weeks[1] = week(1, report(3, 1, hard: 3))
    let first = now.addingTimeInterval(-12 * 86_400)
    let counts = [
      MuscleHistoryCount(exerciseID: bench, setCount: 5, lastAt: now, firstAt: first)
    ]
    let history = history(counts: counts, weeks: weeks)

    #expect(history.weeks.count == 2)
    #expect(history.shape(for: .chest) == [3, 2])
    let label = MuscleHistoryCopy.shapeSpan(
      weeks: history.weeks.count,
      first: history.weeks.first!.start,
      last: history.weeks.last!.lastDay, format: format)
    #expect(label.hasPrefix("2 weeks"))
  }

  @Test("Lifetime is the twelve weeks plus whatever precedes them, and the four-week total agrees")
  func spanningProperty() {
    // Sixteen weeks at three chest sets a week: twelve are drawn, four are older than the shape.
    let setsPerWeek = 3.0
    let weeks = (0..<12).map { week($0, report(setsPerWeek, 0, hard: 3)) }
    let counts = [
      MuscleHistoryCount(
        exerciseID: bench, setCount: 48, lastAt: now,
        firstAt: now.addingTimeInterval(-112 * 86_400))
    ]
    let history = history(counts: counts, weeks: weeks)

    let withinShape = history.weeks.reduce(0) { $0 + $1.report.sets(for: .chest) }
    let older = 4 * setsPerWeek
    #expect(history.lifetimeSets(for: .chest) == withinShape + older)
    #expect(history.lifetimeSets(for: .chest) == 48)
    // The last four windows are the current four-week figure, by construction and by merge.
    let lastFour = weeks.prefix(4).map(\.report)
    #expect(history.currentSets(for: .chest) == MuscleVolumeReport.merge(Array(lastFour)).sets(for: .chest))
    #expect(history.currentSets(for: .chest) == 12)
  }

  // MARK: - D31: the future

  @Test("A future-dated set is in lifetime and in no timing figure")
  func futureDated() {
    var weeks = emptyWeeks()
    weeks[0] = week(0, report(6, 3, hard: 6))
    let counts = [
      MuscleHistoryCount(
        exerciseID: bench, setCount: 8, pastSetCount: 6,
        lastAt: now.addingTimeInterval(-2 * 86_400),
        firstAt: now.addingTimeInterval(-40 * 86_400)),
      MuscleHistoryCount(
        exerciseID: row, setCount: 2, pastSetCount: 0, lastAt: nil, firstAt: nil),
    ]
    let history = history(counts: counts, weeks: weeks)

    // Two future sets on the bench and two on the row.
    #expect(history.futureDatedSets == 4)
    // The future sets are in the lifetime total...
    #expect(history.lifetimeSets(for: .chest) == 8)
    #expect(history.lifetimeSets(for: .lats) == 2)
    // ...and in neither last trained nor the shape.
    #expect(history.lastTrained[MuscleKey(.lats)] == nil)
    #expect(history.shape(for: .lats) == [0, 0, 0, 0, 0, 0])
    #expect(history.lastTrained[MuscleKey(.chest)]?.date == now.addingTimeInterval(-2 * 86_400))
    #expect(history.firstSetAt == now.addingTimeInterval(-40 * 86_400))
    // One plain sentence, and no negative interval anywhere.
    #expect(MuscleHistoryCopy.futureDated(2).contains("dated in the future"))
    #expect(MuscleHistoryCopy.futureDated(2).contains("lifetime totals"))
    #expect(history.lastTrained[MuscleKey(.chest)]!.date <= now)
  }

  @Test("A movement with only future sets has a lifetime figure and no last trained date")
  func futureOnlyMovement() {
    let counts = [
      MuscleHistoryCount(
        exerciseID: bench, setCount: 3, pastSetCount: 0, lastAt: nil, firstAt: nil)
    ]
    let history = history(counts: counts)
    #expect(history.isTrained(.chest))
    #expect(history.lastTrained.isEmpty)
    #expect(history.weeks.isEmpty)
    #expect(history.futureDatedSets == 3)
    #expect(history.emptyState(for: .lats) == .noneCredited)
  }

  // MARK: - Inspection

  @Test("The four-week working accounts for both windows and states the difference, without a weekly badge")
  func fourWeekWorking() {
    var weeks = emptyWeeks()
    weeks[0] = week(0, report(2, 1, hard: 2), sets: [
      CountableSet(exerciseID: bench, isWarmup: false),
      CountableSet(exerciseID: bench, isWarmup: false),
    ])
    weeks[4] = week(4, report(6, 3, hard: 6), sets: (0..<6).map { _ in
      CountableSet(exerciseID: bench, isWarmup: false)
    })
    let counts = [
      MuscleHistoryCount(
        exerciseID: bench, setCount: 8, lastAt: now, firstAt: now.addingTimeInterval(-30 * 86_400))
    ]
    let history = history(counts: counts, weeks: weeks)
    let account = history.account(
      muscle: .chest, figure: .fourWeeks, muscleName: "Chest", attribution: attribution,
      name: { _ in "Bench press" }, format: format)

    #expect(account.figure == "2 sets")
    #expect(account.sections.contains { $0.id == "current-credited" })
    #expect(account.sections.contains { $0.id == "previous-credited" })
    #expect(!account.figureCaption.lowercased().contains("confidence"))
    #expect(!account.rule.lowercased().contains("confidence"))
    #expect(account.spoken.contains("Down 4"))
  }

  @Test("The lifetime working materialises the grouped counts and says warm-ups were excluded")
  func lifetimeWorking() {
    let counts = [
      MuscleHistoryCount(exerciseID: bench, setCount: 4, lastAt: now, firstAt: now),
      MuscleHistoryCount(exerciseID: mystery, setCount: 2, lastAt: now, firstAt: now),
    ]
    let history = history(counts: counts)
    let account = history.account(
      muscle: .chest, figure: .lifetime, muscleName: "Chest", attribution: attribution,
      name: { $0 == self.bench ? "Bench press" : "Mystery lift" }, format: format)

    // 4 chest + 2 unattributed: the materialised sets add up to the figure, and the floor is stated.
    #expect(account.figure == "≥ 4 sets")
    let left = account.sections.first { $0.id == "left" }
    #expect(left?.lines.contains { $0.id == "warmups-aggregate" } == true)
    #expect(left?.lines.contains { $0.id == "unattributed-\(mystery)" } == true)
    #expect(!account.figureCaption.lowercased().contains("confidence"))
  }
}
