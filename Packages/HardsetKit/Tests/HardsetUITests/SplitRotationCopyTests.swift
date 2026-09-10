import Foundation
import HardsetCore
import Testing

@testable import HardsetUI

@Suite("A plan day says where the lifter is without telling them what to do")
struct SplitRotationCopyTests {
  private let now = Date(timeIntervalSince1970: 1_700_000_000)

  private func day(lastTrained: Date?, isLongest: Bool = false) -> PlannedDay {
    PlannedDay(
      id: SplitDayID(rawValue: UUID()),
      name: "Push",
      subtitle: "Chest · Triceps",
      movements: [],
      lastTrained: lastTrained,
      isLongestSinceTrained: isLongest
    )
  }

  @Test("A trained day reports when, and a marked day says why it is marked")
  func trainedDayCopy() {
    let tenDaysAgo = now.addingTimeInterval(-10 * 86_400)
    #expect(day(lastTrained: tenDaysAgo).rotationText(asOf: now) == "Last trained 10 days ago")
    #expect(
      day(lastTrained: tenDaysAgo, isLongest: true).rotationText(asOf: now)
        == "Last trained 10 days ago · longest since trained"
    )
  }

  @Test("An untrained day says so rather than showing a date it does not have")
  func untrainedDayCopy() {
    #expect(day(lastTrained: nil).rotationText(asOf: now) == "Not trained yet")
    #expect(
      day(lastTrained: nil, isLongest: true).rotationText(asOf: now)
        == "Not trained yet · longest since trained"
    )
  }

  /// The defect this line was rewritten to fix: two days a lifter is choosing between must not read
  /// identically. The system's named relative format calls both of these "last week".
  @Test("Days seven and ten apart do not read the same")
  func distinguishesWithinTheSecondWeek() {
    let seven = day(lastTrained: now.addingTimeInterval(-7 * 86_400)).rotationText(asOf: now)
    let ten = day(lastTrained: now.addingTimeInterval(-10 * 86_400)).rotationText(asOf: now)

    #expect(seven != ten)
    #expect(seven == "Last trained 7 days ago")
  }

  /// Guideline 1.4.1 and the app's own refusal: a plan is never graded, and nothing here may read
  /// as an instruction. "Longest since trained" is a fact about the lifter's own history.
  @Test("The rotation line never prescribes or grades")
  func neverPrescribes() {
    let phrases = [
      day(lastTrained: now.addingTimeInterval(-9 * 86_400), isLongest: true).rotationText(asOf: now),
      day(lastTrained: nil, isLongest: true).rotationText(asOf: now),
      day(lastTrained: now, isLongest: false).rotationText(asOf: now),
    ]
      .compactMap { $0 }
      .map { $0.lowercased() }

    let banned = ["should", "recommend", "next up", "due", "today's workout", "score", "rating"]
    for phrase in phrases {
      for word in banned {
        let contains = phrase.contains(word)
        #expect(!contains, "\(phrase) contains prescriptive copy: \(word)")
      }
    }
  }
}
