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
    #expect(spy.scheduled.isEmpty)
  }
}

@MainActor
private final class AlarmSpy {
  var active: Set<UUID> = []
  var scheduled: [UUID] = []
  var cancelled: [UUID] = []
  var authorized = true
  var holdNextSchedule = false
  let events: AsyncStream<Void>
  private let continuation: AsyncStream<Void>.Continuation
  private var pending: CheckedContinuation<Void, Never>?
  init() { (events, continuation) = AsyncStream.makeStream() }
  var operations: RestAlarmOperations {
    RestAlarmOperations(contains: { self.active.contains($0) }, cancel: {
      self.cancelled.append($0); self.active.remove($0)
    }, isAuthorized: { self.authorized }, requestAuthorization: { self.authorized }, schedule: { id, _, _ in
      self.scheduled.append(id)
      if self.holdNextSchedule {
        self.holdNextSchedule = false
        await withCheckedContinuation { self.pending = $0; self.continuation.yield(()) }
      }
      self.active.insert(id)
    })
  }
  func completeSchedule() { pending?.resume(); pending = nil }
}
private enum ProbeError: Error { case diskFull }
#endif
