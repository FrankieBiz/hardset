import Foundation
import Testing

@testable import HardsetCore

/// The live record notice states what a record beat and, for an estimated max, a figure that is
/// itself an estimate. The account behind it explains exactly the records on screen, names the
/// formula, and lists what the comparison was never made against.
@Suite("Worked from: the live record notice")
struct LiveRecordWorkingTests {
  let epoch = Date(timeIntervalSince1970: 1_700_000_000)  // 14 Nov 2023, 22:13:20 UTC
  let exercise = ExerciseID()
  let hammer = MachineID()
  let cybex = MachineID()
  let format = WorkedFromFormat(
    unit: .kilograms, locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "UTC")!)

  private func at(_ minutes: Int, day: Int) -> Date {
    epoch.addingTimeInterval(Double(day) * 86_400 + Double(minutes) * 60)
  }

  private func sample(
    _ session: SessionID, _ kg: Double, _ reps: Int, day: Int, minute: Int = 0,
    machine: MachineID? = nil, imported: Bool = false
  ) -> ProgressionSample {
    ProgressionSample(
      sessionID: session, machineID: machine, weightKg: kg, reps: reps,
      completedAt: at(minute, day: day), isImported: imported)
  }

  private func label(_ key: ProgressionKey) -> String {
    if key.isImported { return "Imported · machine not recorded" }
    return key.machineID == hammer ? "Hammer Strength" : key.machineID == cybex ? "Cybex" : "Free weight"
  }

  /// A history, a set just logged that beat it, and the records the logger's own detector claims for
  /// that set: what the notice draws.
  private func scene() -> (
    records: [PersonalRecord], today: SessionID, samples: [ProgressionSample],
    warmups: [ProgressionSample]
  ) {
    let earlier = SessionID()
    let today = SessionID()
    let imported = SessionID()
    let samples = [
      sample(earlier, 100, 5, day: 0, machine: hammer),
      sample(earlier, 90, 8, day: 0, minute: 5, machine: cybex),
      sample(imported, 80, 10, day: -30, imported: true),
      sample(today, 100, 8, day: 14, machine: hammer),
    ]
    let warmups = [
      sample(earlier, 40, 10, day: 0, minute: -5, machine: hammer),
      sample(today, 50, 5, day: 14, minute: -5, machine: hammer),
    ]
    let records = PersonalRecordDetector.records(
      for: .init(weightKg: 100, reps: 8),
      history: [PriorSetRecord(weightKg: 100, reps: 5, completedAt: at(0, day: 0))],
      increment: nil, estimatesOneRepMax: true)
    return (records, today, samples, warmups)
  }

  private func liveAccount(
    _ scene: (records: [PersonalRecord], today: SessionID, samples: [ProgressionSample], warmups: [ProgressionSample]),
    records: [PersonalRecord]? = nil, estimates: Bool = true
  ) -> WorkedFromAccount? {
    RecordWorking.liveAccount(
      records: records ?? scene.records, exerciseName: "Chest press", sessionID: scene.today,
      key: ProgressionKey(exerciseID: exercise, machineID: hammer), samples: scene.samples,
      warmups: scene.warmups, estimatesOneRepMax: estimates, incrementKg: nil, label: label,
      format: format)
  }

  @Test("The account explains the records on screen, names the formula, and lists what was left out")
  func explainsTheNotice() throws {
    let scene = scene()
    // The notice's records: more reps at the weight, and a better estimate.
    #expect(Set(scene.records.map(\.kind)) == [.repsAtLoad, .estimatedOneRepMax])

    let account = try #require(liveAccount(scene))
    #expect(account.title == "New records")
    #expect(account.figure == "2 records")
    #expect(
      account.figureCaption == "Moderate confidence · Chest press · Hammer Strength · Nov 28, 2023")
    #expect(account.ruleHeading == "What counts as a record")
    #expect(account.rule.contains("A record is a working set that beats everything logged before it"))
    // The estimate's formula and its cap, from the estimator's own constants.
    #expect(account.rule.contains("weight × (1 + reps ÷ 30)"))
    #expect(account.rule.contains("Sets above 12 reps are not estimated."))

    #expect(
      account.sections.map(\.id) == ["group-live", "estimate-fed", "estimate-left", "comparison-left"])

    // One line for each record on screen, in the order the notice shows them, each naming the set it beat.
    let records = account.sections[0]
    #expect(records.note == "Compared with every earlier working set on this machine.")
    #expect(records.lines.count == scene.records.count)
    #expect(records.lines.map(\.headline) == scene.records.map(\.qualifiedLabel))
    #expect(records.lines.allSatisfy { $0.standing == .produced && $0.standingWord == "Set the record" })
    let reps = try #require(records.lines.first { $0.headline == PersonalRecordKind.repsAtLoad.label })
    #expect(reps.detail.contains("Beat 100 kg × 5 on Nov 14, 2023 by 3 reps."))
    let estimate = try #require(records.lines.first { $0.headline.hasPrefix(PersonalRecordKind.estimatedOneRepMax.label) })
    #expect(estimate.detail.contains("from 100 kg × 5 on Nov 14, 2023"))
    #expect(estimate.detail.contains("with an estimate on both sides"))

    // The estimate's own working: the set that is the figure.
    let fed = account.sections[1]
    #expect(fed.heading.hasPrefix("This session's estimate · "))
    #expect(fed.lines.map(\.headline) == ["100 kg × 8"])
    #expect(fed.lines[0].standing == .produced)
    #expect(fed.lines[0].detail == "100 × (1 + 8 ÷ 30) → 126.5 kg. This set is the figure.")

    // Left out of the estimate: this session's own warm-up, and the sets on other equipment and imported.
    let estimateLeft = account.sections[2]
    #expect(estimateLeft.heading == "Left out of this estimate")
    #expect(estimateLeft.lines.allSatisfy { $0.standing == .excluded })
    #expect(estimateLeft.lines.map(\.headline).contains("50 kg × 5"))

    // And what the comparison was never made against, counted.
    let left = account.sections[3]
    #expect(left.heading == "Left out of the comparison")
    #expect(left.lines.map(\.id) == ["comparison-warmups", "comparison-elsewhere", "comparison-imported"])
    #expect(left.lines.map(\.headline) == ["2 warm-up sets", "1 set on other equipment", "1 imported set"])
    #expect(left.lines.allSatisfy { $0.standing == .excluded && $0.detail.hasPrefix("Left out:") })
    #expect(account.spoken.contains("Left out of the comparison: 2 warm-up sets"))
  }

  @Test("A record that is not an estimate carries no estimate working and no confidence rating")
  func measuredRecordOnly() throws {
    let scene = scene()
    let reps = scene.records.filter { $0.kind == .repsAtLoad }
    #expect(reps.count == 1)
    let account = try #require(liveAccount(scene, records: reps))
    #expect(account.title == "New record")
    #expect(account.figure == "1 record")
    #expect(account.figureCaption == "Chest press · Hammer Strength · Nov 28, 2023")
    #expect(account.sections.map(\.id) == ["group-live", "comparison-left"])
    #expect(!account.rule.contains("Epley"))
  }

  @Test("Nothing is left out of the comparison when there was nothing to leave out")
  func nothingLeftOut() throws {
    let earlier = SessionID()
    let today = SessionID()
    let samples = [
      sample(earlier, 100, 5, day: 0, machine: hammer), sample(today, 100, 8, day: 14, machine: hammer),
    ]
    let records = PersonalRecordDetector.records(
      for: .init(weightKg: 100, reps: 8),
      history: [PriorSetRecord(weightKg: 100, reps: 5, completedAt: at(0, day: 0))],
      increment: nil, estimatesOneRepMax: true)
    let account = try #require(
      RecordWorking.liveAccount(
        records: records, exerciseName: "Chest press", sessionID: today,
        key: ProgressionKey(exerciseID: exercise, machineID: hammer), samples: samples, warmups: [],
        estimatesOneRepMax: true, incrementKg: nil, label: label, format: format))
    let left = try #require(account.sections.last)
    #expect(left.id == "comparison-left")
    #expect(left.lines.isEmpty)
    #expect(left.note?.hasPrefix("Nothing was left out.") == true)
    #expect(account.spoken.hasSuffix("Nothing was left out of the comparison."))
  }

  @Test("No records, nothing to explain")
  func noRecords() {
    #expect(liveAccount(scene(), records: []) == nil)
  }

  @Test("A record the replay does not find is still explained from the record itself")
  func recordWithoutAReplayMatch() throws {
    let scene = scene()
    // A record the notice drew that the saved history does not reproduce, such as a machine step that
    // was edited mid-session. It is explained from its own figures, not dropped and not invented.
    let odd = PersonalRecord(
      kind: .heaviestLoad, weightKg: 105, reps: 3, previousWeightKg: 100)
    let account = try #require(liveAccount(scene, records: [odd]))
    let line = try #require(account.sections.first?.lines.first)
    #expect(line.headline == "Heaviest weight")
    #expect(line.detail.hasPrefix("Beat your previous heaviest weight, 100 kg, by 5 kg"))
  }
}
