import Foundation
import Testing

@testable import HardsetCore

@Suite("A live card's Last time is dated from the sets it quotes")
struct LastTimeSourceTests {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }

  private let locale = Locale(identifier: "en_GB")
  private let usLocale = Locale(identifier: "en_US")
  /// 2026-11-14 12:00 UTC. Twenty days before is 2026-10-25, the date the copy tests name.
  private let now = Date(timeIntervalSince1970: 1_794_657_600)

  private func daysAgo(_ days: Int) -> Date {
    calendar.date(byAdding: .day, value: -days, to: now)!
  }

  private func prior(
    exerciseID: ExerciseID = ExerciseID(), machineID: MachineID? = nil,
    sets: [(Double, Int, Date)]
  ) -> PriorPerformance {
    PriorPerformance(
      key: ProgressionKey(exerciseID: exerciseID, machineID: machineID),
      lastSets: sets.map { PriorSetRecord(weightKg: $0.0, reps: $0.1, completedAt: $0.2) },
      heaviestSet: nil
    )
  }

  @Test("The date is the newest set in the quoted session, never the heaviest set")
  func newestQuotedSetWins() {
    let heaviestDate = daysAgo(700)
    let newestDate = daysAgo(2)
    let performance = PriorPerformance(
      key: ProgressionKey(exerciseID: ExerciseID()),
      lastSets: [
        PriorSetRecord(weightKg: 95, reps: 10, completedAt: daysAgo(3)),
        PriorSetRecord(weightKg: 100, reps: 8, completedAt: newestDate),
      ],
      heaviestSet: PriorSetRecord(weightKg: 140, reps: 3, completedAt: heaviestDate)
    )

    let source = LastTimeSource(prior: performance, borrowed: false)

    #expect(source?.lastDoneAt == newestDate)
    #expect(source?.lastDoneAt != heaviestDate)
  }

  @Test("Borrowed history is named as another machine, an exact prior as this one")
  func equipmentComesFromTheNote() {
    let performance = prior(sets: [(100, 8, daysAgo(4))])

    #expect(LastTimeSource(prior: performance, borrowed: true)?.equipment == .otherMachine)
    #expect(LastTimeSource(prior: performance, borrowed: false)?.equipment == .sameEquipment)
  }

  @Test("No prior, or a prior with no sets, has no date to state")
  func nothingToDate() {
    #expect(LastTimeSource(prior: nil, borrowed: false) == nil)
    #expect(LastTimeSource(prior: prior(sets: []), borrowed: false) == nil)
  }

  @Test("Days, weeks and months follow the app's wording, and a future date is today")
  func wordingBoundaries() {
    func line(_ days: Int) -> String {
      let source = LastTimeSource(prior: prior(sets: [(100, 8, daysAgo(days))]), borrowed: false)!
      return source.dateLine(now: now, calendar: calendar, locale: locale)
    }

    #expect(line(0) == "today")
    #expect(line(1) == "13 Nov · yesterday")
    #expect(line(2) == "12 Nov · 2 days ago")
    #expect(line(13) == "1 Nov · 13 days ago")
    #expect(line(14) == "31 Oct · 2 weeks ago")
    #expect(line(59) == "16 Sep · 8 weeks ago")
    #expect(line(60) == "15 Sep · 2 months ago")

    let future = LastTimeSource(
      prior: prior(sets: [(100, 8, now.addingTimeInterval(3 * 86_400))]), borrowed: false)!
    #expect(future.dateLine(now: now, calendar: calendar, locale: locale) == "today")

    let twentyDays = LastTimeSource(
      prior: prior(sets: [(100, 8, daysAgo(20))]), borrowed: false)!
    #expect(
      twentyDays.dateLine(now: now, calendar: calendar, locale: locale) == "25 Oct · 2 weeks ago")
    #expect(
      twentyDays.dateLine(now: now, calendar: calendar, locale: usLocale) == "Oct 25 · 2 weeks ago")
    #expect(
      twentyDays.spokenDateLine(now: now, calendar: calendar, locale: locale)
        == "25 October, 2 weeks ago")
    #expect(
      twentyDays.spokenDateLine(now: now, calendar: calendar, locale: usLocale)
        == "October 25, 2 weeks ago")
    #expect(
      LastTimeSource(prior: prior(sets: [(100, 8, now)]), borrowed: false)!
        .spokenDateLine(now: now, calendar: calendar, locale: locale) == "today")
  }

  @Test("The source follows the machine, and a machine's own set today drops the borrowed note")
  func sourceFollowsTheState() {
    let exercise = ExerciseID()
    let machineA = MachineID()
    let machineB = MachineID()
    let aDate = daysAgo(400)
    let bDate = daysAgo(3)
    let aPrior = prior(exerciseID: exercise, machineID: machineA, sets: [(95, 8, aDate)])
    let bPrior = prior(exerciseID: exercise, machineID: machineB, sets: [(60, 10, bDate)])

    var state = ExerciseLogState.build(
      exerciseID: exercise, machineID: machineA, exerciseName: "Press",
      snapshot: PriorPerformanceSnapshot(entries: [aPrior.key: aPrior], capturedAt: now)
    )
    #expect(state.lastTimeSource?.lastDoneAt == aDate)
    #expect(state.lastTimeSource?.equipment == .sameEquipment)

    state.changeMachine(to: machineB, machineName: "B", machineIncrementKg: nil, prior: bPrior)
    #expect(state.priorNote == nil)
    #expect(state.lastTimeSource?.lastDoneAt == bDate)
    #expect(state.lastTimeSource?.equipment == .sameEquipment)

    state.changeMachine(to: machineA, machineName: "A", machineIncrementKg: nil, prior: aPrior)
    #expect(state.lastTimeSource?.lastDoneAt == aDate)

    // Borrowed history is datable and named as borrowed...
    state.changeMachine(
      to: machineB, machineName: "B", machineIncrementKg: nil, prior: aPrior,
      priorNote: "From another machine")
    #expect(state.priorNote == "From another machine")
    #expect(state.lastTimeSource?.equipment == .otherMachine)

    // ...until a set saved today on B makes the fallback unnecessary. Then neither the note nor
    // a dated source survives, because there is no borrowed session left to describe.
    state.slots[0].draft = SetEntryDraft(weightKg: 60, reps: 8)
    state.markLogged(slotID: state.slots[0].id, setID: SetID(), completedAt: now)
    state.changeMachine(to: machineA, machineName: "A", machineIncrementKg: nil, prior: aPrior)
    state.changeMachine(
      to: machineB, machineName: "B", machineIncrementKg: nil, prior: aPrior,
      priorNote: "From another machine")
    #expect(state.priorNote == nil)
    #expect(state.lastTimeSource == nil)
  }

  @Test("The copy never advises, predicts or sets a goal")
  func noAdvice() {
    let forbidden = [
      "should", "deload", "lighter", "rusty", "detrain", "recommend", "aim for", "ideal", "goal",
    ]
    var strings = [LastTimeCopy.label]
    for days in [-1, 0, 1, 2, 13, 14, 59, 60, 400] {
      let source = LastTimeSource(
        prior: prior(sets: [(100, 8, daysAgo(days))]), borrowed: false)!
      let line = source.dateLine(now: now, calendar: calendar, locale: locale)
      let spoken = source.spokenDateLine(now: now, calendar: calendar, locale: locale)
      strings.append(LastTimeCopy.line(dateLine: line))
      strings.append(LastTimeCopy.borrowedContext(note: "From another machine", dateLine: line))
      strings.append(LastTimeCopy.spoken(dateSpoken: spoken))
    }
    for string in strings {
      for word in forbidden {
        #expect(!string.lowercased().contains(word), "\(string) contains \(word)")
      }
    }
  }
}
