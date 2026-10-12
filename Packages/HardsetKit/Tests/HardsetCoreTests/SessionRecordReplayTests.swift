import Foundation
import Testing

@testable import HardsetCore

@Suite("A session's records, replayed exactly as they were judged live")
struct SessionRecordReplayTests {
  let day = Date(timeIntervalSince1970: 1_000_000)
  let press = ProgressionKey(exerciseID: ExerciseID())

  private func entry(
    _ weight: Double, _ reps: Int, key: ProgressionKey? = nil, warmup: Bool = false
  ) -> SessionRecordReplay.Entry {
    SessionRecordReplay.Entry(
      setID: SetID(), key: key ?? press, weightKg: weight, reps: reps, isWarmup: warmup,
      completedAt: day)
  }
  private func history(_ sets: [(Double, Int)]) -> [PriorSetRecord] {
    sets.map { PriorSetRecord(weightKg: $0.0, reps: $0.1, completedAt: .distantPast) }
  }

  @Test("The first set ever on a lift is never a record")
  func firstEver() {
    let only = entry(100, 8)
    #expect(SessionRecordReplay.records(session: [only], priorHistory: [:], increments: [:]).isEmpty)
  }

  @Test("A later set is judged against this session's earlier sets too")
  func earlierSetsCount() {
    let first = entry(100, 8)
    let second = entry(105, 8)
    let result = SessionRecordReplay.records(
      session: [first, second], priorHistory: [:], increments: [:])
    #expect(result[first.setID] == nil)
    #expect(result[second.setID]?.contains { $0.kind == .heaviestLoad } == true)
  }

  @Test("Repeating the best is not a record")
  func repeatIsNot() {
    let same = entry(100, 8)
    let result = SessionRecordReplay.records(
      session: [same], priorHistory: [press: history([(100, 8)])], increments: [:])
    #expect(result.isEmpty)
  }

  @Test("A heavy warm-up is never a record and never raises the bar")
  func warmupsAreInvisible() {
    let warmup = entry(140, 3, warmup: true)
    let working = entry(110, 8)
    let result = SessionRecordReplay.records(
      session: [warmup, working], priorHistory: [press: history([(100, 8)])], increments: [:])
    #expect(result[warmup.setID] == nil)
    #expect(result[working.setID]?.contains { $0.kind == .heaviestLoad } == true)
  }

  @Test("A machine's increment sets the margin")
  func machineIncrementMargin() {
    let machine = MachineID()
    let stack = ProgressionKey(exerciseID: press.exerciseID, machineID: machine)
    let set = entry(104, 1, key: stack)
    let onStack = SessionRecordReplay.records(
      session: [set], priorHistory: [stack: history([(100, 1)])], increments: [machine: 5])
    #expect(onStack[set.setID]?.contains { $0.kind == .heaviestLoad } != true)
    let onPlates = SessionRecordReplay.records(
      session: [set], priorHistory: [stack: history([(100, 1)])], increments: [:])
    #expect(onPlates[set.setID]?.contains { $0.kind == .heaviestLoad } == true)
  }

  @Test("Another machine's history is not this machine's")
  func seriesNeverMerge() {
    let other = ProgressionKey(exerciseID: press.exerciseID, machineID: MachineID())
    let set = entry(100, 8)
    let result = SessionRecordReplay.records(
      session: [set], priorHistory: [other: history([(60, 8)])], increments: [:])
    #expect(result.isEmpty)
  }

  @Test("A window keeps the newest sets at each step, so an old best slides out")
  func windowSlides() {
    let old = PriorSetRecord(weightKg: 200, reps: 5, completedAt: Date(timeIntervalSince1970: 1))
    let recent = PriorSetRecord(weightKg: 100, reps: 8, completedAt: Date(timeIntervalSince1970: 2))
    let first = entry(120, 5)
    let second = entry(130, 5)
    let unbounded = SessionRecordReplay.records(
      session: [first, second], priorHistory: [press: [old, recent]], increments: [:])
    let windowed = SessionRecordReplay.records(
      session: [first, second], priorHistory: [press: [old, recent]], increments: [:], window: 2)
    #expect(unbounded.isEmpty)
    #expect(windowed[first.setID] == nil)
    #expect(windowed[second.setID]?.contains { $0.kind == .heaviestLoad } == true)
  }
}
