#if canImport(AlarmKit)
import Foundation
import HardsetAlarm
import HardsetCore
import Testing

@Suite("Durable AlarmKit reconciliation")
@MainActor
struct RestControllerTests {
  private let metadata = RestMetadata(exerciseName: "Press", setOrdinal: 2, machineName: "Cybex")

  @Test("A failed journal write changes neither UI nor the OS")
  func persistBeforeClaim() async {
    let spy = AlarmSpy()
    let controller = RestTimerController(operations: spy.operations)
    controller.configure(checkpoint: .init(), save: { _ in throw ProbeError.diskFull })
    await controller.waitForReconciliation()
    controller.start(duration: .seconds(120), metadata: metadata)
    await controller.waitForReconciliation()
    #expect(controller.state == .idle)
    #expect(controller.lastError != nil)
    #expect(spy.scheduled.isEmpty)
  }

  @Test("A failed mutation can retry its intended state")
  func retryFailedWrite() async {
    let spy = AlarmSpy()
    let controller = RestTimerController(operations: spy.operations)
    var fail = false
    var saved: RestCheckpoint?
    controller.configure(checkpoint: .init(), save: { value in
      if fail { throw ProbeError.diskFull }
      saved = value
    })
    await controller.waitForReconciliation()
    fail = true
    controller.start(duration: .seconds(120), metadata: metadata)
    #expect(controller.state == .idle)
    fail = false
    controller.retry()
    await controller.waitForReconciliation()
    #expect(controller.state.isRunning)
    #expect(saved?.state == controller.state)
    #expect(spy.scheduled.count == 1)
  }

  @Test("Failed recovery blocks timer commands and later restores the saved state")
  func retryRecovery() async {
    let spy = AlarmSpy()
    let controller = RestTimerController(operations: spy.operations)
    let recovered = RestCheckpoint(state: .paused(remaining: .seconds(45)), metadata: metadata)
    controller.configureRecoveryFailure(ProbeError.diskFull, restore: { recovered }, save: { _ in })
    controller.start(duration: .seconds(120), metadata: metadata)
    #expect(controller.lastError != nil)
    #expect(controller.state == .idle)
    #expect(spy.scheduled.isEmpty)
    controller.retry()
    await controller.waitForReconciliation()
    #expect(controller.state == recovered.state)
    #expect(controller.lastError == nil)
  }

  @Test("A late schedule is canceled before the newest deadline is scheduled")
  func lateSchedule() async throws {
    let spy = AlarmSpy()
    spy.holdNextSchedule = true
    let controller = RestTimerController(operations: spy.operations)
    var journal: [RestCheckpoint] = []
    controller.configure(checkpoint: .init(), save: { journal.append($0) })
    await controller.waitForReconciliation()
    let events = spy.events.makeAsyncIterator()
    var iterator = events
    controller.start(duration: .seconds(120), metadata: metadata)
    _ = await iterator.next()
    let oldID = try #require(spy.scheduled.first)
    controller.adjust(by: .seconds(15))
    #expect(journal.last?.retiredAlarmIDs.contains(oldID) == true)
    spy.completeSchedule()
    await controller.waitForReconciliation()
    #expect(spy.cancelled.contains(oldID))
    #expect(spy.active.count == 1)
    #expect(spy.scheduled.count == 2)
    #expect(journal.last?.retiredAlarmIDs.isEmpty == true)
    #expect(journal.last?.state == controller.state)
  }

  @Test("Relaunch retains a scheduled alarm and retries pending cancellations")
  func relaunch() async {
    let spy = AlarmSpy()
    let old = UUID(), current = UUID()
    spy.active = [old, current]
    let checkpoint = RestCheckpoint(state: .running(endsAt: Date().addingTimeInterval(120)), metadata: metadata,
      alarmID: current, retiredAlarmIDs: [old])
    let controller = RestTimerController(operations: spy.operations)
    var saved: RestCheckpoint?
    controller.configure(checkpoint: checkpoint, save: { saved = $0 })
    await controller.waitForReconciliation()
    #expect(controller.metadata == metadata)
    #expect(controller.state == checkpoint.state)
    #expect(spy.active == [current])
    #expect(spy.scheduled.isEmpty)
    #expect(saved?.retiredAlarmIDs.isEmpty == true)
  }

  @Test("A previously acknowledged alarm stopped by the OS is not resurrected")
  func stoppedBySystem() async {
    let spy = AlarmSpy()
    let id = UUID()
    let controller = RestTimerController(operations: spy.operations)
    var saved: RestCheckpoint?
    controller.configure(checkpoint: .init(state: .running(endsAt: Date().addingTimeInterval(120)),
      metadata: metadata, alarmID: id, scheduledAlarmID: id), save: { saved = $0 })
    await controller.waitForReconciliation()
    #expect(controller.state == .idle)
    #expect(saved?.state == .idle)
    #expect(spy.scheduled.isEmpty)
  }

  @Test("Pause survives relaunch without scheduling an OS countdown")
  func paused() async {
    let spy = AlarmSpy()
    let controller = RestTimerController(operations: spy.operations)
    controller.configure(checkpoint: .init(state: .paused(remaining: .seconds(45)), metadata: metadata), save: { _ in })
    await controller.waitForReconciliation()
    #expect(controller.state == .paused(remaining: .seconds(45)))
    #expect(spy.scheduled.isEmpty)
  }

  @Test("Denied authorization is visible and does not remove the durable deadline")
  func denied() async {
    let spy = AlarmSpy()
    spy.authorized = false
    let controller = RestTimerController(operations: spy.operations)
    var saved: RestCheckpoint?
    controller.configure(checkpoint: .init(), save: { saved = $0 })
    await controller.waitForReconciliation()
    controller.start(duration: .seconds(120), metadata: metadata)
    await controller.waitForReconciliation()
    #expect(controller.state.isRunning)
    #expect(saved?.state == controller.state)
    #expect(controller.lastError != nil)
    #expect(controller.issue == .alarmsDenied)
    #expect(spy.scheduled.isEmpty)
  }

  @Test("Permission is asked before any alarm is queried")
  func permissionFirst() async {
    let spy = AlarmSpy()
    spy.authorized = false
    spy.grantOnRequest = true
    spy.queriesNeedPermission = true
    let controller = RestTimerController(operations: spy.operations)
    controller.configure(checkpoint: .init(), save: { _ in })
    await controller.waitForReconciliation()
    #expect(spy.requests == 0)
    controller.start(duration: .seconds(120), metadata: metadata)
    await controller.waitForReconciliation()
    #expect(spy.requests == 1)
    #expect(spy.scheduled.count == 1)
    #expect(controller.issue == nil)
  }

  @Test("A rest with alarms off ends at its deadline instead of reading 0:00")
  func deniedRestEnds() async throws {
    let spy = AlarmSpy()
    spy.authorized = false
    let controller = RestTimerController(operations: spy.operations)
    var saved: RestCheckpoint?
    controller.configure(checkpoint: .init(), save: { saved = $0 })
    await controller.waitForReconciliation()
    // Half a second left: long enough to see the denial, short enough to wait for the deadline.
    controller.start(duration: .seconds(120), metadata: metadata, now: Date().addingTimeInterval(-119.5))
    await controller.waitForReconciliation()
    #expect(controller.state.isRunning)
    #expect(controller.issue == .alarmsDenied)
    for _ in 0..<500 where controller.state != .idle { try await Task.sleep(for: .milliseconds(10)) }
    await controller.waitForReconciliation()
    #expect(controller.state == .idle)
    #expect(saved?.state == .idle)
    #expect(controller.issue == nil)
  }

  @Test("Allowing alarms later schedules the running rest")
  func allowedLater() async {
    let spy = AlarmSpy()
    spy.authorized = false
    let controller = RestTimerController(operations: spy.operations)
    controller.configure(checkpoint: .init(), save: { _ in })
    await controller.waitForReconciliation()
    controller.start(duration: .seconds(120), metadata: metadata)
    await controller.waitForReconciliation()
    #expect(controller.issue == .alarmsDenied)
    spy.authorized = true
    controller.refresh()
    await controller.waitForReconciliation()
    #expect(spy.scheduled.count == 1)
    #expect(controller.issue == nil)
    #expect(controller.state.isRunning)
  }

  @Test("Subtracting past the end of a rest ends it and cancels its alarm")
  func subtractToZero() async throws {
    let spy = AlarmSpy()
    let controller = RestTimerController(operations: spy.operations)
    var saved: RestCheckpoint?
    controller.configure(checkpoint: .init(), save: { saved = $0 })
    await controller.waitForReconciliation()
    controller.start(duration: .seconds(120), metadata: metadata, now: Date().addingTimeInterval(-110))
    await controller.waitForReconciliation()
    let id = try #require(spy.scheduled.first)
    controller.adjust(by: .seconds(-15))
    await controller.waitForReconciliation()
    #expect(controller.state == .idle)
    #expect(saved?.state == .idle)
    #expect(spy.cancelled == [id])
    #expect(spy.scheduled.count == 1)
  }

  @Test("A relaunched rest whose deadline passed with no alarm left is over")
  func expiredOnRelaunch() async {
    let spy = AlarmSpy()
    let controller = RestTimerController(operations: spy.operations)
    var saved: RestCheckpoint?
    controller.configure(checkpoint: .init(state: .running(endsAt: Date().addingTimeInterval(-30)),
      metadata: metadata, alarmID: UUID()), save: { saved = $0 })
    await controller.waitForReconciliation()
    #expect(controller.state == .idle)
    #expect(saved?.state == .idle)
    #expect(spy.scheduled.isEmpty)
  }

  @Test("A ringing alarm keeps its rest until it is stopped")
  func ringingAlarm() async {
    let spy = AlarmSpy()
    let id = UUID()
    spy.active = [id]
    let controller = RestTimerController(operations: spy.operations)
    controller.configure(checkpoint: .init(state: .running(endsAt: Date().addingTimeInterval(-5)),
      metadata: metadata, alarmID: id, scheduledAlarmID: id), save: { _ in })
    await controller.waitForReconciliation()
    #expect(controller.state.isRunning)
    spy.active = []
    controller.refresh()
    await controller.waitForReconciliation()
    #expect(controller.state == .idle)
  }

  @Test("Adding time to a finished rest gives fifteen more seconds")
  func extendFinished() async {
    let spy = AlarmSpy()
    let id = UUID()
    spy.active = [id]
    let controller = RestTimerController(operations: spy.operations)
    controller.configure(checkpoint: .init(state: .running(endsAt: Date().addingTimeInterval(-5)),
      metadata: metadata, alarmID: id, scheduledAlarmID: id), save: { _ in })
    await controller.waitForReconciliation()
    let now = Date()
    controller.adjust(by: .seconds(15), now: now)
    await controller.waitForReconciliation()
    #expect(controller.state == .running(endsAt: now.addingTimeInterval(15)))
    #expect(spy.cancelled == [id])
    #expect(spy.scheduled.count == 1)
  }

  @Test("Pausing a finished rest or resuming one paused at zero ends it")
  func zeroPauseAndResume() async {
    let spy = AlarmSpy()
    let controller = RestTimerController(operations: spy.operations)
    controller.configure(checkpoint: .init(state: .paused(remaining: .zero), metadata: metadata), save: { _ in })
    await controller.waitForReconciliation()
    controller.resume()
    await controller.waitForReconciliation()
    #expect(controller.state == .idle)
    controller.start(duration: .seconds(120), metadata: metadata, now: Date().addingTimeInterval(-120))
    controller.pause()
    await controller.waitForReconciliation()
    #expect(controller.state == .idle)
    #expect(spy.active.isEmpty)
  }

  @Test("The total rest follows adjustments and leaves out paused time")
  func totalRest() async {
    let spy = AlarmSpy()
    let controller = RestTimerController(operations: spy.operations)
    controller.configure(checkpoint: .init(), save: { _ in })
    await controller.waitForReconciliation()
    let now = Date()
    controller.start(duration: .seconds(90), metadata: metadata, now: now)
    #expect(controller.metadata?.totalRest == .seconds(90))
    #expect(controller.metadata?.exerciseName == metadata.exerciseName)
    controller.adjust(by: .seconds(15), now: now)
    #expect(controller.metadata?.totalRest == .seconds(105))
    controller.pause(now: now.addingTimeInterval(30))
    controller.adjust(by: .seconds(-15), now: now.addingTimeInterval(60))
    controller.resume(now: now.addingTimeInterval(90))
    #expect(controller.metadata?.totalRest == .seconds(90))
    #expect(controller.state == .running(endsAt: now.addingTimeInterval(150)))
    await controller.waitForReconciliation()
  }

  @Test("An unreadable saved rest can be reset, ending every alarm the app still holds")
  func resetUnreadable() async {
    let spy = AlarmSpy()
    let orphan = UUID()
    spy.active = [orphan]
    let controller = RestTimerController(operations: spy.operations)
    var saved: RestCheckpoint?
    controller.configureRecoveryFailure(ProbeError.diskFull, restore: { throw ProbeError.diskFull },
      save: { saved = $0 })
    #expect(controller.issue == .recoveryFailed)
    controller.retry()
    #expect(controller.issue == .recoveryFailed)
    controller.resetAfterRecoveryFailure()
    await controller.waitForReconciliation()
    #expect(controller.issue == nil)
    #expect(controller.state == .idle)
    #expect(spy.cancelled == [orphan])
    #expect(saved?.retiredAlarmIDs.isEmpty == true)
    controller.start(duration: .seconds(120), metadata: metadata)
    await controller.waitForReconciliation()
    #expect(spy.scheduled.count == 1)
  }

  @Test("A failed write is reported as a failure that a retry can fix")
  func failureIssue() async {
    let spy = AlarmSpy()
    let controller = RestTimerController(operations: spy.operations)
    controller.configure(checkpoint: .init(), save: { _ in throw ProbeError.diskFull })
    await controller.waitForReconciliation()
    #expect(controller.issue == .failed)
  }
}

@MainActor
private final class AlarmSpy {
  var active: Set<UUID> = []
  var scheduled: [UUID] = []
  var cancelled: [UUID] = []
  var authorized = true
  /// Models a first prompt: the request grants permission.
  var grantOnRequest = false
  /// Models AlarmKit refusing queries before permission is settled.
  var queriesNeedPermission = false
  var requests = 0
  var holdNextSchedule = false
  let events: AsyncStream<Void>
  private let continuation: AsyncStream<Void>.Continuation
  private var pending: CheckedContinuation<Void, Never>?
  init() { (events, continuation) = AsyncStream.makeStream() }
  var operations: RestAlarmOperations {
    RestAlarmOperations(contains: {
      if self.queriesNeedPermission, !self.authorized { throw ProbeError.notAuthorized }
      return self.active.contains($0)
    }, cancel: {
      self.cancelled.append($0); self.active.remove($0)
    }, isAuthorized: { self.authorized }, requestAuthorization: {
      self.requests += 1
      if self.grantOnRequest { self.authorized = true }
      return self.authorized
    }, schedule: { id, _, _ in
      self.scheduled.append(id)
      if self.holdNextSchedule {
        self.holdNextSchedule = false
        await withCheckedContinuation { self.pending = $0; self.continuation.yield(()) }
      }
      self.active.insert(id)
    }, alarmIDs: { Array(self.active) })
  }
  func completeSchedule() { pending?.resume(); pending = nil }
}
private enum ProbeError: Error { case diskFull, notAuthorized }
#endif
