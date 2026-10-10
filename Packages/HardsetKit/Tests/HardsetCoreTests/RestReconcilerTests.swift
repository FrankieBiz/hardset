import Foundation
import Testing

@testable import HardsetCore

@Suite("The rest timer reconciles with the alarms that actually exist")
struct RestReconcilerTests {
  let now = Date(timeIntervalSince1970: 1_000_000)
  let ours = UUID()
  let other = UUID()

  private func persisted(_ state: RestTimerState, alarm: UUID?) -> PersistedRest {
    PersistedRest(state: state, alarmID: alarm)
  }

  @Test("R1: nothing persisted and no alarms is idle")
  func nothingIsIdle() {
    let result = RestReconciler.reconcile(persisted: nil, alarms: [], now: now)
    #expect(result == RestReconciliation(state: .idle, alarmID: nil, staleAlarmIDs: []))
  }

  @Test("R2: a counting-down alarm's fire date wins over the persisted deadline")
  func alarmDeadlineWins() {
    let fire = now.addingTimeInterval(75)
    let result = RestReconciler.reconcile(
      persisted: persisted(.running(endsAt: now.addingTimeInterval(30)), alarm: ours),
      alarms: [AlarmSnapshot(id: ours, mode: .countdown(fireDate: fire))],
      now: now
    )
    #expect(result.state == .running(endsAt: fire))
    #expect(result.alarmID == ours)
    #expect(result.staleAlarmIDs.isEmpty)
  }

  @Test("R3: a countdown with no readable fire date keeps the persisted deadline")
  func unknownFireDateKeepsPersisted() {
    let endsAt = now.addingTimeInterval(40)
    let result = RestReconciler.reconcile(
      persisted: persisted(.running(endsAt: endsAt), alarm: ours),
      alarms: [AlarmSnapshot(id: ours, mode: .countdown(fireDate: nil))],
      now: now
    )
    #expect(result.state == .running(endsAt: endsAt))
    #expect(result.alarmID == ours)
  }

  @Test("R4: an alarm paused from the Lock Screen is shown paused")
  func pausedElsewhere() {
    let result = RestReconciler.reconcile(
      persisted: persisted(.running(endsAt: now.addingTimeInterval(40)), alarm: ours),
      alarms: [AlarmSnapshot(id: ours, mode: .paused(remaining: .seconds(25)))],
      now: now
    )
    #expect(result.state == .paused(remaining: .seconds(25)))
    #expect(result.alarmID == ours)
  }

  @Test("R5: an unreadable pause keeps a persisted pause")
  func unreadablePauseKeepsPersistedPause() {
    let result = RestReconciler.reconcile(
      persisted: persisted(.paused(remaining: .seconds(50)), alarm: ours),
      alarms: [AlarmSnapshot(id: ours, mode: .paused(remaining: nil))],
      now: now
    )
    #expect(result.state == .paused(remaining: .seconds(50)))
    #expect(result.alarmID == ours)
  }

  @Test("R5: an unreadable pause over a running record is cancelled, never guessed")
  func unreadablePauseIsNotGuessed() {
    let result = RestReconciler.reconcile(
      persisted: persisted(.running(endsAt: now.addingTimeInterval(40)), alarm: ours),
      alarms: [AlarmSnapshot(id: ours, mode: .paused(remaining: nil))],
      now: now
    )
    #expect(result.state == .idle)
    #expect(result.alarmID == nil)
    #expect(result.staleAlarmIDs == [ours])
  }

  @Test("R6: an alerting alarm ends the rest but is left for the system to show")
  func alertingIsIdleNotStale() {
    let result = RestReconciler.reconcile(
      persisted: persisted(.running(endsAt: now.addingTimeInterval(-1)), alarm: ours),
      alarms: [AlarmSnapshot(id: ours, mode: .alerting)],
      now: now
    )
    #expect(result.state == .idle)
    #expect(result.alarmID == nil)
    #expect(result.staleAlarmIDs.isEmpty)
  }

  @Test("R7: a persisted countdown with no alarm behind it is idle")
  func missingAlarmIsIdle() {
    let result = RestReconciler.reconcile(
      persisted: persisted(.running(endsAt: now.addingTimeInterval(60)), alarm: ours),
      alarms: [],
      now: now
    )
    #expect(result == RestReconciliation(state: .idle, alarmID: nil, staleAlarmIDs: []))
  }

  @Test("R8: a lone countdown alarm is adopted when nothing was persisted")
  func loneAlarmAdopted() {
    let fire = now.addingTimeInterval(90)
    let result = RestReconciler.reconcile(
      persisted: nil,
      alarms: [AlarmSnapshot(id: other, mode: .countdown(fireDate: fire))],
      now: now
    )
    #expect(result.state == .running(endsAt: fire))
    #expect(result.alarmID == other)
    #expect(result.staleAlarmIDs.isEmpty)
  }

  @Test("R8: two unexplained alarms are both stale, not adopted")
  func twoUnexplainedAreStale() {
    let result = RestReconciler.reconcile(
      persisted: nil,
      alarms: [
        AlarmSnapshot(id: ours, mode: .countdown(fireDate: now.addingTimeInterval(10))),
        AlarmSnapshot(id: other, mode: .countdown(fireDate: now.addingTimeInterval(20))),
      ],
      now: now
    )
    #expect(result.state == .idle)
    #expect(Set(result.staleAlarmIDs) == [ours, other])
  }

  @Test("R9: alarms other than ours are stale")
  func othersAreStale() {
    let fire = now.addingTimeInterval(30)
    let result = RestReconciler.reconcile(
      persisted: persisted(.running(endsAt: fire), alarm: ours),
      alarms: [
        AlarmSnapshot(id: ours, mode: .countdown(fireDate: fire)),
        AlarmSnapshot(id: other, mode: .countdown(fireDate: now.addingTimeInterval(500))),
      ],
      now: now
    )
    #expect(result.state == .running(endsAt: fire))
    #expect(result.staleAlarmIDs == [other])
  }
}
