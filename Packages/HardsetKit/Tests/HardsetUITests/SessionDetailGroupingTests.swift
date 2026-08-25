import Foundation
import HardsetCore
import Testing

@testable import HardsetUI

/// The rule the session-detail screen groups by, tested with more than one movement.
///
/// Both defects this suite pins shipped together and were only visible on a real workout: three
/// movements of three sets rendered as nine headings, the same three names repeating down the page,
/// with most sets missing. One movement of three sets -- the only case previously covered -- looks
/// correct under both the broken and the fixed rule, which is why nothing caught it.
@Suite("A workout groups into one block per movement run")
struct SessionDetailGroupingTests {
  private func set(
    _ name: String, _ kg: Double, _ reps: Int, machine: String? = nil, warmup: Bool = false
  ) -> LoggedSetRow {
    LoggedSetRow(
      id: UUID(), exerciseName: name, machineName: machine,
      weightKg: kg, reps: reps, kind: warmup ? .warmup : .working
    )
  }

  @Test("Three movements of three sets make three groups, not nine")
  func threeMovementsMakeThreeGroups() {
    let sets = [
      set("Bench Press", 40, 12, warmup: true),
      set("Bench Press", 84, 8), set("Bench Press", 84, 8), set("Bench Press", 86.5, 6),
      set("Incline Press", 30, 10), set("Incline Press", 30, 10), set("Incline Press", 30, 9),
      set("Pushdown", 25, 15), set("Pushdown", 25, 14), set("Pushdown", 25, 12),
    ]

    let groups = SessionDetailView.groups(from: sets)

    #expect(groups.map(\.exerciseName) == ["Bench Press", "Incline Press", "Pushdown"])
    // Every set lands in exactly one group, and none is dropped.
    #expect(groups.map(\.sets.count) == [4, 3, 3])
    #expect(groups.flatMap(\.sets).count == sets.count)
  }

  /// The `ForEach` identity bug. A name-based id is duplicated when a movement is returned to, and
  /// SwiftUI renders the first group again for each duplicate rather than merging them.
  @Test("A movement performed in two separate runs gets two distinct group ids")
  func returningToAMovementKeepsDistinctIdentity() {
    let sets = [
      set("Bench Press", 84, 8),
      set("Pushdown", 25, 15),
      set("Bench Press", 84, 6),
    ]

    let groups = SessionDetailView.groups(from: sets)

    #expect(groups.map(\.exerciseName) == ["Bench Press", "Pushdown", "Bench Press"])
    #expect(Set(groups.map(\.id)).count == groups.count)
  }

  /// Same movement, different equipment: two blocks, because 80 kg on one machine is not 80 kg on
  /// another and merging them is what this app refuses to do everywhere else.
  @Test("Changing machine mid-movement starts a new group")
  func machineChangeSplitsTheGroup() {
    let sets = [
      set("Leg Press", 100, 10, machine: "Hammer Strength"),
      set("Leg Press", 100, 10, machine: "Hammer Strength"),
      set("Leg Press", 80, 10, machine: "Cybex"),
    ]

    let groups = SessionDetailView.groups(from: sets)

    #expect(groups.count == 2)
    #expect(groups.map(\.machineName) == ["Hammer Strength", "Cybex"])
    #expect(groups.map(\.sets.count) == [2, 1])
    #expect(Set(groups.map(\.id)).count == 2)
  }

  /// Group identity must not shift as the group grows, or SwiftUI treats a group gaining a set as a
  /// different group and discards its state.
  @Test("A group keeps its identity as sets are appended to it")
  func identityIsStableAsGroupsGrow() {
    let first = set("Row", 60, 10)
    let onlyFirst = SessionDetailView.groups(from: [first])
    let withMore = SessionDetailView.groups(from: [first, set("Row", 60, 10)])

    #expect(onlyFirst[0].id == withMore[0].id)
  }
}

/// A past workout's headline must agree with the week that contains it. Counting every
/// non-warm-up row reported a drop chain as three sets where the volume report said one.
@Suite("A past workout's set count follows the same convention as the week")
struct SessionDetailDropCountTests {
  @Test("A drop chain reads as one working set, not three")
  func dropsAreNotCountedAsWorkingSets() {
    let rows = [
      LoggedSetRow(
        id: UUID(), exerciseName: "Leg Press", machineName: nil,
        weightKg: 200, reps: 10, kind: .working
      ),
      LoggedSetRow(
        id: UUID(), exerciseName: "Leg Press", machineName: nil,
        weightKg: 160, reps: 8, kind: .drop
      ),
      LoggedSetRow(
        id: UUID(), exerciseName: "Leg Press", machineName: nil,
        weightKg: 120, reps: 6, kind: .drop
      ),
    ]
    let working = rows.count { $0.kind.countsAsWorkingSet }
    #expect(working == 1)
    // Each drop still knows what it is, so history can label it rather than hiding it.
    #expect(rows.count { $0.kind == .drop } == 2)
    #expect(rows.allSatisfy { !$0.isWarmup })
  }
}
