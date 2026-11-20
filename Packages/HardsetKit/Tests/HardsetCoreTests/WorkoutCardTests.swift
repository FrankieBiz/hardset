import Foundation
import Testing

@testable import HardsetCore

@Suite("Saved workout cards read like a coach's note")
struct WorkoutCardTests {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }

  private let now = Date(timeIntervalSince1970: 1_700_000_000 + 12 * 3_600)

  private func ago(days: Double, hours: Double = 0) -> Date {
    now.addingTimeInterval(-(days * 86_400 + hours * 3_600))
  }

  private func template(
    _ name: String, position: Int, movements: Int = 3, lastDoneAt: Date? = nil
  ) -> WorkoutTemplate {
    WorkoutTemplate(
      name: name, position: position,
      exercises: (0..<movements).map { _ in
        TemplateExercise(exerciseID: ExerciseID(), exerciseName: "Movement", plannedSets: 3)
      },
      lastDoneAt: lastDoneAt)
  }

  @Test("Last done is said in calendar days, then weeks, then months, and never for a new plan")
  func lastDoneWording() {
    func text(_ date: Date?) -> String { LastDoneText.text(for: date, now: now, calendar: calendar) }

    #expect(text(nil) == "not done yet")
    #expect(text(ago(days: 0, hours: 5)) == "last done today")
    #expect(text(ago(days: 1)) == "last done yesterday")
    #expect(text(ago(days: 4)) == "last done 4 days ago")
    #expect(text(ago(days: 13)) == "last done 13 days ago")
    #expect(text(ago(days: 14)) == "last done 2 weeks ago")
    #expect(text(ago(days: 59)) == "last done 8 weeks ago")
    #expect(text(ago(days: 60)) == "last done 2 months ago")
    #expect(text(now.addingTimeInterval(3_600)) == "last done today")
  }

  @Test("A calendar day is a calendar day, whatever the hour either side")
  func lastDoneCountsMidnightsNotHours() {
    // 2023-11-15 00:00:00 UTC. 23:59 the evening before is a calendar day ago at 00:01, though two
    // minutes have passed.
    let midnight = Date(timeIntervalSince1970: 1_700_006_400)
    let justAfterMidnight = midnight.addingTimeInterval(60)
    let lateYesterday = midnight.addingTimeInterval(-60)

    #expect(LastDoneText.text(for: lateYesterday, now: justAfterMidnight, calendar: calendar)
      == "last done yesterday")
  }

  @Test("The workout done longest ago leads, and says it is up next with how the last one went")
  func upNextCardLeads() {
    let a = template("Upper A", position: 0, movements: 6, lastDoneAt: ago(days: 4))
    let b = template("Upper B", position: 1, lastDoneAt: ago(days: 11))

    let cards = WorkoutCard.cards(
      templates: [a, b], now: now, calendar: calendar,
      lastResult: .init(workout: b.id, beaten: 4, compared: 6))

    #expect(cards.map(\.name) == ["Upper B", "Upper A"])
    #expect(cards.map(\.isUpNext) == [true, false])
    #expect(cards[0].contextLine == "Up next · last done 11 days ago · beat 4 of 6 last time")
    #expect(cards[1].contextLine == "Last done 4 days ago")
    #expect(cards[0].movementsLine == "3 movements")
    #expect(cards[1].movementsLine == "6 movements")
  }

  @Test("The last result is only claimed when something was compared, and only for its own workout")
  func lastResultNeedsAComparison() {
    let a = template("Upper A", position: 0, lastDoneAt: ago(days: 4))
    let b = template("Upper B", position: 1, lastDoneAt: ago(days: 11))

    let none = WorkoutCard.cards(
      templates: [a, b], now: now, calendar: calendar,
      lastResult: .init(workout: b.id, beaten: 0, compared: 0))
    #expect(none[0].contextLine == "Up next · last done 11 days ago")

    let elsewhere = WorkoutCard.cards(
      templates: [a, b], now: now, calendar: calendar,
      lastResult: .init(workout: a.id, beaten: 2, compared: 3))
    #expect(elsewhere[0].contextLine == "Up next · last done 11 days ago")

    let zeroBeaten = WorkoutCard.cards(
      templates: [a, b], now: now, calendar: calendar,
      lastResult: .init(workout: b.id, beaten: 0, compared: 3))
    #expect(zeroBeaten[0].contextLine == "Up next · last done 11 days ago · beat 0 of 3 last time")
  }

  @Test("Workouts never done come first, and say so")
  func neverDoneComesFirst() {
    let done = template("Upper A", position: 0, lastDoneAt: ago(days: 2))
    let fresh = template("Lower", position: 1, movements: 1)

    let cards = WorkoutCard.cards(templates: [done, fresh], now: now, calendar: calendar)

    #expect(cards.map(\.name) == ["Lower", "Upper A"])
    #expect(cards[0].contextLine == "Up next · not done yet")
    #expect(cards[0].movementsLine == "1 movement")
  }

  @Test("With nothing saved there are no cards")
  func noTemplatesNoCards() {
    #expect(WorkoutCard.cards(templates: [], now: now, calendar: calendar).isEmpty)
  }
}
