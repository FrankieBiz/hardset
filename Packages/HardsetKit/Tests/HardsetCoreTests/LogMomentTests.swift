import Foundation
import Testing

@testable import HardsetCore

/// The log tap as one event. These pin the sequencing and the Reduce Motion variant as data: which
/// part starts when, that there is one haptic and it is at contact, and that nothing travels when the
/// lifter asked for less motion. They do not, and cannot, say how the moment feels; that is a device
/// check, recorded in `docs/OWNER-DEVICE-CHECKLIST.md`.
///
/// "Never before the save" is held where the write happens: `SessionCoordinatorTests` has "A refused
/// write leaves the row unlogged and starts no rest", and the row only draws contact when its logged
/// flag turns true, which is after that write. `isContact` below holds the other half, that only
/// that change is a contact.
@Suite("The log moment")
struct LogMomentTests {
  private func step(_ part: LogMoment.Part, reduceMotion: Bool = false) throws -> LogMoment.Step {
    try #require(LogMoment.plan(reduceMotion: reduceMotion).first { $0.part == part })
  }

  @Test("Every part of the moment is planned exactly once, with or without motion")
  func everyPartOnce() {
    for reduceMotion in [false, true] {
      let parts = LogMoment.plan(reduceMotion: reduceMotion).map(\.part)
      #expect(Set(parts) == Set(LogMoment.Part.allCases), "reduceMotion \(reduceMotion)")
      #expect(parts.count == LogMoment.Part.allCases.count, "reduceMotion \(reduceMotion)")
    }
  }

  @Test("There is one haptic, it is the clank at contact, and Reduce Motion does not remove it")
  func oneHapticAtContact() throws {
    for reduceMotion in [false, true] {
      let plan = LogMoment.plan(reduceMotion: reduceMotion)
      let played = plan.filter { $0.style == .played }
      #expect(played.count == 1, "reduceMotion \(reduceMotion)")
      let haptic = try step(.haptic, reduceMotion: reduceMotion)
      #expect(haptic.style == .played)
      #expect(haptic.beat == .contact)
      #expect(haptic.delay == 0)
    }
  }

  @Test("The stamp and the figures land at contact; the consequence follows it")
  func contactThenFollow() throws {
    for part in [LogMoment.Part.haptic, .seal, .figures, .accent] {
      let planned = try step(part)
      #expect(planned.beat == .contact, "\(part)")
      #expect(planned.delay == 0, "\(part)")
    }
    for part in [LogMoment.Part.beatMark, .restBar, .records, .correctionHint] {
      let planned = try step(part)
      #expect(planned.beat == .follow, "\(part)")
      #expect(planned.style == .fade, "\(part)")
      #expect(planned.delay == LogMoment.followDelay, "\(part)")
    }
  }

  @Test("The follow beat arrives together: one delay for everything that explains the set")
  func followArrivesTogether() {
    let delays = Set(
      LogMoment.plan(reduceMotion: false).filter { $0.beat == .follow }.map(\.delay))
    #expect(delays == [LogMoment.followDelay])
  }

  /// A stamp and a message that start more than a few tenths of a second apart are two events. The
  /// follow beat starts inside the stamp's own duration, so the two overlap, and the whole moment is
  /// over inside the ceiling.
  @Test("The beats overlap and the moment settles inside its ceiling")
  func readsAsOneEvent() throws {
    let seal = try step(.seal)
    #expect(LogMoment.followDelay > 0)
    #expect(LogMoment.followDelay < seal.end, "the consequence begins before the stamp has settled")
    let plan = LogMoment.plan(reduceMotion: false)
    #expect(plan.map(\.end).max()! <= LogMoment.settleCeiling)
    #expect(plan.map(\.end).max()! > 0)
  }

  @Test("Reduce Motion: no spring, no fade, nothing delayed; everything but the haptic is instant")
  func reducedMotionVariant() {
    let plan = LogMoment.plan(reduceMotion: true)
    #expect(!plan.contains { $0.style == .spring })
    #expect(!plan.contains { $0.style == .fade })
    #expect(plan.allSatisfy { $0.beat == .contact })
    #expect(plan.allSatisfy { $0.delay == 0 && $0.duration == 0 })
    for planned in plan where planned.part != .haptic {
      #expect(planned.style == .instant, "\(planned.part)")
    }
  }

  @Test("Reduce Motion keeps every part: the meaning stays, only the travel goes")
  func reducedMotionKeepsTheMeaning() {
    let full = Set(LogMoment.plan(reduceMotion: false).map(\.part))
    let reduced = Set(LogMoment.plan(reduceMotion: true).map(\.part))
    #expect(full == reduced)
  }

  @Test("Only the seal springs, and only the follow beat fades")
  func theSpringIsTheOneFlourish() {
    let plan = LogMoment.plan(reduceMotion: false)
    #expect(plan.filter { $0.style == .spring }.map(\.part) == [.seal])
    #expect(plan.filter { $0.style == .fade }.allSatisfy { $0.beat == .follow })
  }

  @Test("Only a row turning logged is a contact")
  func contactIsLoggedTurningTrue() {
    #expect(LogMoment.isContact(from: false, to: true))
    // An undo is the opposite change and has no moment.
    #expect(!LogMoment.isContact(from: true, to: false))
    // A row that was already logged, or never was, did not change.
    #expect(!LogMoment.isContact(from: true, to: true))
    #expect(!LogMoment.isContact(from: false, to: false))
  }
}
