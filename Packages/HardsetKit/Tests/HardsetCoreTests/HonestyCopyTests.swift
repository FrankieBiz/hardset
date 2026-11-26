import Foundation
import Testing

@testable import HardsetCore

/// The four claims the refusal sheet makes on the app's behalf, held to the engine that enforces
/// them.
///
/// The sheet is worth nothing if it restates a rule differently from the code: a headline that types
/// "12" survives the day the ceiling moves, and a claim that no target exists survives the day one
/// is published. These tests read every number and every name through the constant or the source the
/// engine uses, and fail when the prose drifts.
@Suite("What Hardset won't say")
struct HonestyCopyTests {
  /// The count the live row is built from, computed here from the engine rather than read from the
  /// copy, so the test's number and the app's number are arrived at independently.
  private var evaluatedTargets: Int {
    Muscle.allCases.filter { VolumeAnalyzer.weeklyTarget(for: $0).value != nil }.count
  }

  private func refusal(at index: Int) throws -> Refusal {
    let rows = HonestyCopy.refusals
    return try #require(rows.indices.contains(index) ? rows[index] : nil)
  }

  @Test("The rep ceiling is read from the engine, not typed into the copy")
  func repsCeilingReadsTheConstant() throws {
    let line = HonestyCopy.repsCeilingLine(limit: 10)
    #expect(line.contains("10"))
    #expect(!line.contains("12"))

    let row = try refusal(at: 0)
    #expect(row.headline == HonestyCopy.repsCeilingLine())
    #expect(row.body == HonestyCopy.repsCeilingBody())
  }

  @Test("The weekly target claim follows the engine's evaluated targets")
  func weeklyTargetFollowsTheEngine() throws {
    #expect(
      HonestyCopy.weeklyTargetLine(evaluatedTargets: 0, of: Muscle.allCases.count)
        == "No weekly set target for any muscle.")
    let partial = HonestyCopy.weeklyTargetLine(evaluatedTargets: 3, of: Muscle.allCases.count)
    #expect(partial.contains("3 of \(Muscle.allCases.count)"))

    let row = try refusal(at: 1)
    #expect(row.headline == HonestyCopy.weeklyTargetLine(evaluatedTargets: evaluatedTargets))
  }

  @Test("No muscle has an evaluated weekly target today")
  func noEvaluatedTargetsToday() {
    // Asserted against the whole vocabulary, not a sample: "for any muscle" is a universal claim,
    // and the engine is the thing that has to keep it true.
    #expect(Muscle.allCases.count > 0)
    #expect(evaluatedTargets == 0)
  }

  @Test("Four refusals, each with a unique id and a stated source")
  func rowsAreComplete() {
    let rows = HonestyCopy.refusals
    #expect(rows.count == 4)
    #expect(Set(rows.map(\.id)).count == rows.count)
    for row in rows {
      #expect(!row.sourceTitle.isEmpty)
      #expect(!row.sourceLimit.isEmpty)
    }
  }

  @Test("Each row names the source it cites, in that source's own words")
  func rowsNameTheirSources() throws {
    #expect(try refusal(at: 0).id == StrengthMath.epleySource.id)
    #expect(try refusal(at: 1).id == VolumeAnalyzer.targetSource.id)
    #expect(try refusal(at: 2).id == ProgressionAnalyzer.source.id)

    #expect(try refusal(at: 0).sourceTitle == StrengthMath.epleySource.title)
    #expect(try refusal(at: 1).sourceTitle == VolumeAnalyzer.targetSource.title)
    #expect(try refusal(at: 2).sourceTitle == ProgressionAnalyzer.source.title)
  }

  @Test("The progression rule still describes the machine change it refuses to measure")
  func progressionSourceStillNamesTheMachine() {
    // The drift guard, not a copy test: if the engine's own limit text stops saying "machine", the
    // sheet's third row is describing a rule that no longer reads that way and must be revisited.
    let range = ProgressionAnalyzer.source.validRange ?? ""
    #expect(range.contains("machine"))
  }

  @Test("The future-dated row carries the singular sentence the screen shows")
  func futureDatedRowUsesTheScreenCopy() throws {
    let row = try refusal(at: 3)
    #expect(row.sourceLimit == MuscleHistoryCopy.futureDated(1))
    #expect(MuscleHistoryCopy.futureDated(1) != MuscleHistoryCopy.futureDated(3))
    #expect(MuscleHistoryCopy.futureDated(3).contains("are dated"))
  }

  @Test("No refusal tells the lifter what they should do")
  func copyCarriesNoPrescription() {
    // The engine's own methodology prose legitimately recommends; this is the sheet's copy only.
    let banned = ["should", "recommend", "aim for", "ideal", "goal", "must"]
    let lines = HonestyCopy.refusals.flatMap { [$0.headline, $0.body] } + [HonestyCopy.introduction]
    for line in lines {
      for word in banned {
        #expect(!line.lowercased().contains(word), "\(word) appears in: \(line)")
      }
    }
  }
}
