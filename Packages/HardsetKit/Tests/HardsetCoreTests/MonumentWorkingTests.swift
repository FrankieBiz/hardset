import Foundation
import Testing

@testable import HardsetCore

/// Worked from, for the two figures the app draws as monuments: the Volume screen's weekly count of
/// working sets (88 pt) and the Train screen's last-workout volume (72 pt). A large number the lifter
/// cannot inspect is what the product refuses, so each of them has an account derived from the same
/// inputs and by the same classification as the figure it explains, and these hold the two equal.
@Suite("Worked from: the monuments")
struct MonumentWorkingTests {
  let bench = ExerciseID()
  let squat = ExerciseID()
  let mystery = ExerciseID()
  let format = WorkedFromFormat(
    unit: .kilograms, locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "UTC")!)

  private func contribution(_ muscle: Muscle, _ role: MuscleRole) -> MuscleContribution {
    MuscleContribution(muscle, role: role, certainty: .moderate, source: .anatomy)
  }

  private var attribution: AttributionIndex {
    AttributionIndex([
      bench: [contribution(.chest, .direct), contribution(.triceps, .indirect)],
      squat: [contribution(.quadriceps, .direct), contribution(.glutes, .indirect)],
    ])
  }

  private func sets(_ exercise: ExerciseID, _ count: Int, warmup: Bool = false) -> [CountableSet] {
    (0..<count).map { _ in CountableSet(exerciseID: exercise, isWarmup: warmup) }
  }

  private func name(_ id: ExerciseID) -> String {
    switch id {
    case bench: "Bench press"
    case squat: "Squat"
    case mystery: "Mystery lift"
    default: "Unknown movement"
    }
  }

  private var window: [CountableSet] {
    sets(bench, 6) + sets(bench, 2, warmup: true) + sets(squat, 5) + sets(mystery, 2)
  }

  // MARK: - The weekly working-set count

  @Test("The count is exactly the report's own count, by the same classification")
  func totalIsTheReportsCount() {
    let report = VolumeAnalyzer.report(sets: window, attribution: attribution)
    let working = WorkingSetCountWorking.derive(
      sets: window, attribution: attribution, name: name)
    #expect(working.total == report.hardSets)
    #expect(working.total == 13)
    #expect(working.warmupSets == 2)
    #expect(working.unattributedSets == report.unattributedHardSets)
  }

  @Test("Every movement is a line, the most sets first, and a movement with no muscles says so")
  func linesAreTheMovements() {
    let account = WorkingSetCountWorking.derive(sets: window, attribution: attribution, name: name)
      .account(windowLabel: "Last 7 days", format: format)
    #expect(account.figure == "13 working sets")
    let counted = account.sections[0].lines
    #expect(counted.map(\.headline) == ["Bench press", "Squat", "Mystery lift"])
    #expect(counted.map(\.context) == [
      "6 sets", "5 sets", "2 sets · no muscles recorded",
    ])
    #expect(counted.allSatisfy { $0.standing == .counted })
    // The lines add up to the figure on screen.
    #expect(account.sections[0].note == "The sets below add up to 13.")
  }

  @Test("Warm-ups are a line under Left out, and nothing is silently missing")
  func warmupsAreLeftOut() {
    let account = WorkingSetCountWorking.derive(sets: window, attribution: attribution, name: name)
      .account(windowLabel: "Last 7 days", format: format)
    let left = account.sections[1].lines
    #expect(left.count == 1)
    #expect(left[0].headline == "2 warm-up sets")
    #expect(left[0].standing == .excluded)
    #expect(account.spoken.contains("Left out: 2 warm-up sets."))
  }

  @Test("It states that the figure is counted and not estimated, with no confidence rating")
  func isACountNotAnEstimate() {
    let account = WorkingSetCountWorking.derive(sets: window, attribution: attribution, name: name)
      .account(windowLabel: "Last 7 days", format: format)
    #expect(account.figureCaption.contains("not estimated"))
    #expect(account.rule.contains("no confidence rating"))
  }

  @Test("An empty window says so instead of drawing an empty explanation")
  func emptyWindow() {
    let account = WorkingSetCountWorking.derive(sets: [], attribution: attribution, name: name)
      .account(windowLabel: "Last 7 days", format: format)
    #expect(account.figure == "0 working sets")
    #expect(account.sections[0].note == "No working set was logged in this window.")
    #expect(account.sections[0].lines.isEmpty)
  }

  @Test("One working set is singular")
  func singular() {
    let account = WorkingSetCountWorking.derive(
      sets: sets(bench, 1), attribution: attribution, name: name
    ).account(windowLabel: "Last 7 days", format: format)
    #expect(account.figure == "1 working set")
  }

  @Test("A movement a workout import created is marked as one")
  func importedIsMarked() {
    let account = WorkingSetCountWorking.derive(
      sets: sets(mystery, 3), attribution: attribution, imported: [mystery], name: name
    ).account(windowLabel: "Last 7 days", format: format)
    #expect(account.sections[0].lines[0].context == "3 sets · no muscles recorded · imported movement")
  }

  // MARK: - A workout's volume

  private func line(
    _ name: String, _ kg: Double, _ reps: Int, warmup: Bool = false, machine: String? = "Hammer Strength"
  ) -> WorkoutReceipt.Line {
    WorkoutReceipt.Line(
      id: SetID(), exerciseName: name, machineName: machine, weightKg: kg, reps: reps,
      isWarmup: warmup)
  }

  private var lines: [WorkoutReceipt.Line] {
    [
      line("Leg press", 60, 12, warmup: true),
      line("Leg press", 100, 10),
      line("Leg press", 100, 8),
      line("Pull-up", 0, 10, machine: nil),
    ]
  }

  @Test("The volume is SessionVolume's own, by its three rules")
  func volumeIsTheSummarys() {
    let working = SessionVolumeWorking.derive(lines: lines)
    let volume = working.volume
    #expect(volume.workingSets == 3)
    #expect(volume.warmupSets == 1)
    #expect(volume.volumeKg == 1800)
    #expect(volume.reps == 28)
  }

  @Test("Each working set is a line of weight × reps and what it adds; the figure is their sum")
  func eachSetIsALine() {
    let account = SessionVolumeWorking.derive(lines: lines)
      .account(title: "Pull day", format: format)
    #expect(account.figure == "1,800 kg")
    let fed = account.sections[0].lines
    #expect(fed.map(\.headline) == ["100 kg × 10", "100 kg × 8", "0 kg × 10"])
    #expect(fed[0].detail == "= 1000 kg")
    #expect(fed[1].detail == "= 800 kg")
    #expect(fed.allSatisfy { $0.standing == .counted })
    #expect(account.sections[0].note == "3 working sets · 28 reps, in the order you did them.")
  }

  @Test("A warm-up is a line under Left out, and a set with no load says it adds nothing")
  func warmupsAndNoLoad() {
    let account = SessionVolumeWorking.derive(lines: lines)
      .account(title: "Pull day", format: format)
    let left = account.sections[1].lines
    #expect(left.count == 1)
    #expect(left[0].headline == "60 kg × 12")
    #expect(left[0].standing == .excluded)
    #expect(left[0].context == "Leg press · Hammer Strength · warm-up")
    let noLoad = account.sections[0].lines[2]
    #expect(noLoad.detail.contains("adds nothing to volume"))
    #expect(noLoad.detail.contains("still counts as a working set"))
  }

  @Test("In pounds the figure is the screen's: whole pounds, the same rounding")
  func inPounds() {
    let pounds = WorkedFromFormat(
      unit: .pounds, locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "UTC")!)
    let account = SessionVolumeWorking.derive(lines: lines).account(title: "Pull day", format: pounds)
    // 1800 kg is 3968.3 lb, shown to the nearest pound as the Train screen does.
    #expect(account.figure == "3,968 lb")
  }

  @Test("A workout with only warm-ups has no volume and nothing to inflate it")
  func onlyWarmups() {
    let account = SessionVolumeWorking.derive(lines: [line("Leg press", 60, 12, warmup: true)])
      .account(title: "Pull day", format: format)
    #expect(account.figure == "0 kg")
    #expect(account.sections[0].lines.isEmpty)
    #expect(account.sections[0].note == "No working set was logged.")
    #expect(account.sections[1].lines.count == 1)
  }

  @Test("It states that the figure is a sum of what was logged, with no confidence rating")
  func isASumNotAnEstimate() {
    let account = SessionVolumeWorking.derive(lines: lines)
      .account(title: "Pull day", format: format)
    #expect(account.figureCaption.contains("not estimated"))
    #expect(account.rule.contains("no confidence rating"))
    #expect(account.spoken.hasPrefix("Volume, 1,800 kg"))
  }
}
