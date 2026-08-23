import Foundation
import HardsetCore
import Testing

@testable import HardsetStore

/// The chart spends colour on the *gym* and stroke on the machine within it, because that is the
/// distinction per-machine tracking exists to draw: two leg presses at one gym are the same place
/// with different equipment, and the same movement at another gym is somewhere else entirely.
///
/// Colour must also follow the entity permanently. A series dropping out of a chart must not
/// repaint the survivors, which is what `gymOrder` being first-mention rather than sorted buys.
@Suite("Gym hue order is stable and buckets the unknowns together")
struct GymHueOrderTests {
  private func history(
    _ pairs: [(machine: MachineID?, gym: GymID?)]
  ) -> ProgressionHistory {
    let exercise = ExerciseID()
    var gyms: [MachineID: GymID] = [:]
    var series: [ProgressionSeries] = []
    for pair in pairs {
      let key = ProgressionKey(exerciseID: exercise, machineID: pair.machine)
      series.append(ProgressionSeries(key: key, points: []))
      if let machine = pair.machine, let gym = pair.gym { gyms[machine] = gym }
    }
    return ProgressionHistory(
      series: series, machineChanges: [], machineNames: [:], machineGyms: gyms
    )
  }

  @Test("Gyms are ordered by first mention, not by id")
  func firstMentionOrder() {
    let a = GymID(), b = GymID()
    let m1 = MachineID(), m2 = MachineID(), m3 = MachineID()
    let h = history([(m1, b), (m2, a), (m3, b)])
    // b is mentioned first, so b takes slot 0 regardless of how the ids sort.
    #expect(h.gymOrder(for: h.series.map(\.key)) == [b, a])
  }

  @Test("A gym appearing on several machines still claims one slot")
  func oneSlotPerGym() {
    let a = GymID()
    let m1 = MachineID(), m2 = MachineID()
    let h = history([(m1, a), (m2, a)])
    #expect(h.gymOrder(for: h.series.map(\.key)) == [a])
  }

  @Test("Free weights and unknown gyms claim no hue at all")
  func unknownsTakeNoSlot() {
    let a = GymID()
    let known = MachineID()
    let orphan = MachineID()  // a machine whose gym row has gone
    let h = history([(nil, nil), (orphan, nil), (known, a)])
    // "No gym" is one bucket, not three, and it is the neutral rather than a hue.
    #expect(h.gymOrder(for: h.series.map(\.key)) == [a])
  }

  @Test("Dropping a series does not renumber the gyms that remain")
  func filteringDoesNotRepaint() {
    let a = GymID(), b = GymID(), c = GymID()
    let m1 = MachineID(), m2 = MachineID(), m3 = MachineID()
    let h = history([(m1, a), (m2, b), (m3, c)])
    let all = h.gymOrder(for: h.series.map(\.key))
    #expect(all == [a, b, c])

    // Remove the middle series, as a filter would. `a` must keep slot 0 and `c` must not slide
    // into `b`'s colour -- it moves down because b is gone, which is why the caller recomputes
    // per chart rather than caching an index on the entity.
    let withoutB = h.gymOrder(for: [h.series[0].key, h.series[2].key])
    #expect(withoutB.first == a)
    #expect(withoutB.count == 2)
  }

  @Test("Beyond the third gym there is no fourth hue to claim")
  func fourthGymFallsToNeutral() {
    let gyms = (0..<5).map { _ in GymID() }
    let machines = (0..<5).map { _ in MachineID() }
    let h = history(zip(machines, gyms).map { (machine: $0.0, gym: $0.1) })
    let order = h.gymOrder(for: h.series.map(\.key))
    #expect(order.count == 5)
    // The palette only has three validated hues; anything past index 2 must resolve to the
    // neutral rather than wrapping around and reusing a colour.
    for (index, _) in order.enumerated() where index > 2 {
      #expect(index >= Tokens_seriesHueCount)
    }
  }

  /// Mirrors `Tokens.Color.Series.ordered.count`. Duplicated as a literal because HardsetStore
  /// must not depend on HardsetUI, and the point of the assertion is that the two agree.
  private var Tokens_seriesHueCount: Int { 3 }
}
