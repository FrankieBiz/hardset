import Foundation
import Testing

@testable import HardsetCore

@Suite("Worked from: a muscle's weekly count")
struct MuscleCountWorkingTests {
  let bench = ExerciseID()
  let incline = ExerciseID()
  let pullUp = ExerciseID()
  let squat = ExerciseID()
  let mystery = ExerciseID()
  let format = WorkedFromFormat(
    unit: .kilograms, locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "UTC")!)

  private func contribution(_ muscle: Muscle, _ role: MuscleRole) -> MuscleContribution {
    MuscleContribution(muscle, role: role, certainty: .moderate, source: .anatomy)
  }

  private var attribution: AttributionIndex {
    AttributionIndex([
      bench: [
        contribution(.chest, .direct), contribution(.frontDelts, .indirect),
        contribution(.triceps, .indirect),
      ],
      incline: [contribution(.chest, .direct), contribution(.frontDelts, .indirect)],
      pullUp: [contribution(.lats, .direct), contribution(.biceps, .indirect), contribution(.forearms, .stabilizer)],
      squat: [contribution(.quadriceps, .direct), contribution(.glutes, .indirect)],
    ])
  }

  private func sets(_ exercise: ExerciseID, _ count: Int, warmup: Bool = false) -> [CountableSet] {
    (0..<count).map { _ in CountableSet(exerciseID: exercise, isWarmup: warmup) }
  }

  private func name(_ id: ExerciseID) -> String {
    switch id {
    case bench: "Bench press"
    case incline: "Incline press"
    case pullUp: "Pull-up"
    case squat: "Squat"
    case mystery: "Mystery lift"
    default: "Unknown movement"
    }
  }

  /// The window the tests share: a count of every kind of set the account has to place.
  private var window: [CountableSet] {
    sets(bench, 6) + sets(bench, 2, warmup: true) + sets(incline, 4) + sets(pullUp, 3)
      + sets(squat, 5) + sets(mystery, 2)
  }

  private func derive(_ muscle: Muscle, in window: [CountableSet]? = nil) -> MuscleCountWorking {
    MuscleCountWorking.derive(
      muscle: muscle, sets: window ?? self.window, attribution: attribution, name: name)
  }

  // MARK: - Which sets, what credit, what was left out

  @Test("A known window credits each movement what its role gives and says what it left out")
  func knownWindow() throws {
    let chest = derive(.chest)

    #expect(chest.total == 10)
    #expect(chest.credited.map(\.name) == ["Bench press", "Incline press"])
    #expect(chest.credited.map(\.setCount) == [6, 4])
    #expect(chest.credited.map(\.credit) == [6, 4])
    #expect(chest.credited.map(\.role) == [.direct, .direct])
    #expect(chest.stabilizing.isEmpty)
    #expect(chest.unattributed.map(\.name) == ["Mystery lift"])
    #expect(chest.unattributed.map(\.setCount) == [2])
    #expect(chest.warmupSets == 2)
    // The pull-ups and squats train other muscles: counted, as a number, not listed by movement.
    #expect(chest.unrelatedSets == 8)
    #expect(chest.isLowerBound)
    #expect(chest.hardSets == 20)

    let account = chest.account(muscleName: "Chest", windowLabel: "Last 7 days, 14 Nov to now", format: format)
    #expect(account.title == "Chest, fractional sets")
    #expect(account.figure == "≥ 10 sets")
    #expect(account.figureCaption == "Last 7 days, 14 Nov to now · Moderate confidence")
    #expect(account.ruleHeading == "How sets are counted")
    #expect(account.rule.hasPrefix(
      "A completed working set credits 1.0 set to each muscle the movement trains directly, "
        + "0.5 to each it trains indirectly, and 0 to each it only stabilises. Warm-ups never count."))

    let credited = try #require(account.sections.first { $0.id == "credited" })
    #expect(credited.note == "The credits below add up to 10.")
    #expect(credited.lines.map(\.headline) == ["Bench press", "Incline press"])
    #expect(credited.lines.allSatisfy { $0.standing == .counted })
    #expect(credited.lines[0].context == "6 sets · direct")
    #expect(credited.lines[0].detail == "6 sets at 1.0 each: 6 sets credited to chest.")

    let left = try #require(account.sections.first { $0.id == "left" })
    #expect(left.lines.map(\.headline) == ["Mystery lift", "2 warm-up sets", "8 sets on other movements"])
    #expect(left.lines.allSatisfy { $0.standing == .excluded })
    #expect(
      left.lines[0].detail
        == "Left out: no muscles are recorded for this movement, so its sets credit no muscle. "
        + "It may have trained chest, so the count is at least what is shown. "
        + "Set its body part in Library, on the Train tab, to count it.")
    #expect(left.lines[1].detail == "Left out: warm-ups count toward no muscle.")
  }

  @Test("An indirect set credits a half, and the line says so")
  func indirectCredit() throws {
    let delts = derive(.frontDelts)
    #expect(delts.total == 5)  // 6 bench sets and 4 incline sets, half a set each
    #expect(delts.credited.map(\.name) == ["Bench press", "Incline press"])
    #expect(delts.credited.map(\.creditPerSet) == [0.5, 0.5])
    #expect(delts.credited.map(\.credit) == [3, 2])
    let line = try #require(
      delts.account(muscleName: "Front delts", windowLabel: "Last 7 days", format: format)
        .sections.first { $0.id == "credited" }?.lines.first)
    #expect(line.context == "6 sets · indirect")
    #expect(line.detail == "6 sets at 0.5 each: 3 sets credited to front delts.")
  }

  @Test("A movement that only stabilises a muscle is listed as left out, with its sets")
  func stabilisersAreListed() throws {
    let forearms = derive(.forearms)
    #expect(forearms.total == 0)
    #expect(forearms.credited.isEmpty)
    #expect(forearms.stabilizing.map(\.name) == ["Pull-up"])
    #expect(forearms.stabilizing.map(\.setCount) == [3])
    #expect(forearms.stabilizing.map(\.creditPerSet) == [0])

    let account = forearms.account(muscleName: "Forearms", windowLabel: "Last 7 days", format: format)
    #expect(account.figure == "≥ 0 sets")
    let credited = try #require(account.sections.first { $0.id == "credited" })
    #expect(credited.lines.isEmpty)
    #expect(credited.note == "No set in this window credited forearms.")
    let left = try #require(account.sections.first { $0.id == "left" })
    #expect(left.lines.first?.headline == "Pull-up")
    #expect(left.lines.first?.context == "3 sets · stabilizing")
    #expect(
      left.lines.first?.detail
        == "Left out: this movement only stabilises forearms, which credits 0, so these sets add nothing to it.")
  }

  @Test("With every movement attributed the count is exact, and a window with nothing left out says so")
  func exactAndNothingLeftOut() throws {
    let working = derive(.chest, in: sets(bench, 3))
    #expect(!working.isLowerBound)
    let account = working.account(muscleName: "Chest", windowLabel: "Last 7 days", format: format)
    #expect(account.figure == "3 sets")
    let left = try #require(account.sections.first { $0.id == "left" })
    #expect(left.lines.isEmpty)
    #expect(left.note == "Nothing in this window was left out.")
  }

  @Test("A single set is a set, not sets")
  func singular() throws {
    let account = derive(.chest, in: sets(bench, 1))
      .account(muscleName: "Chest", windowLabel: "Last 7 days", format: format)
    let line = try #require(account.sections.first { $0.id == "credited" }?.lines.first)
    #expect(line.context == "1 set · direct")
    #expect(line.detail == "1 set at 1.0 each: 1 set credited to chest.")
  }

  @Test("A movement a workout import created is counted by the same rule and says it was imported")
  func importedMovementsAreLabelled() throws {
    let imported = ExerciseID()
    let index = AttributionIndex([
      bench: [contribution(.chest, .direct)], imported: [contribution(.chest, .direct), contribution(.triceps, .indirect)],
    ])
    let data = sets(bench, 3) + sets(imported, 2) + sets(mystery, 1)
    let working = MuscleCountWorking.derive(
      muscle: .chest, sets: data, attribution: index, imported: [imported, mystery],
      name: { $0 == imported ? "Bench Press (Imported)" : $0 == mystery ? "Cable Fly (Imported)" : self.name($0) })

    // Counted exactly as a logged movement's sets are: the report knows nothing of imports.
    #expect(working.total == VolumeAnalyzer.report(sets: data, attribution: index).sets(for: .chest))
    #expect(working.total == 5)
    #expect(working.credited.map(\.isImported) == [false, true])
    #expect(working.unattributed.map(\.isImported) == [true])

    let account = working.account(muscleName: "Chest", windowLabel: "Last 7 days", format: format)
    let credited = try #require(account.sections.first { $0.id == "credited" })
    #expect(credited.lines.map(\.context) == ["3 sets · direct", "2 sets · direct · imported movement"])
    #expect(credited.lines[1].spoken.contains("direct, imported movement, 1.0 each"))
    let left = try #require(account.sections.first { $0.id == "left" })
    #expect(left.lines[0].context == "1 set · no muscles recorded · imported movement")
    // The way out is the one the banner gives, for a movement the lifter made and an imported one.
    #expect(left.lines[0].detail.hasSuffix("Set its body part in Library, on the Train tab, to count it."))
  }

  // MARK: - The same arithmetic as the report

  /// The point of the design: the total in the account is the count on the row, for every muscle,
  /// and the sets in it reconcile with the report's own.
  @Test("For every muscle the account's total and floor are the report's, and its sets add up")
  func agreesWithTheReport() {
    var generator = SplitMix(seed: 11)
    let exercises = [bench, incline, pullUp, squat, mystery]
    var mixed: [CountableSet] = []
    for _ in 0..<120 {
      mixed.append(
        CountableSet(
          exerciseID: exercises[Int.random(in: 0..<exercises.count, using: &generator)],
          isWarmup: Int.random(in: 0..<5, using: &generator) == 0))
    }
    let report = VolumeAnalyzer.report(sets: mixed, attribution: attribution)

    for muscle in Muscle.allCases {
      let working = derive(muscle, in: mixed)
      #expect(working.total == report.sets(for: muscle), "\(muscle)")
      #expect(working.hardSets == report.hardSets)
      #expect(working.isLowerBound == report.isLowerBound)
      let accounted =
        working.credited.reduce(0) { $0 + $1.setCount } + working.stabilizing.reduce(0) { $0 + $1.setCount }
        + working.unattributed.reduce(0) { $0 + $1.setCount } + working.unrelatedSets
      #expect(accounted == report.hardSets, "\(muscle)")
      #expect(working.warmupSets == mixed.filter(\.isWarmup).count)
      #expect(working.credited.reduce(0) { $0 + $1.credit } == working.total)
    }
  }

  @Test("Two attributions of one muscle in one movement add, as the report adds them")
  func duplicatesAddLikeTheReport() {
    let odd = ExerciseID()
    let index = AttributionIndex([odd: [contribution(.chest, .direct), contribution(.chest, .indirect)]])
    let data = sets(odd, 2)
    let working = MuscleCountWorking.derive(muscle: .chest, sets: data, attribution: index, name: { _ in "Odd" })
    #expect(working.total == VolumeAnalyzer.report(sets: data, attribution: index).sets(for: .chest))
    #expect(working.total == 3)
  }

  // MARK: - Words

  @Test("What is read aloud is sentences: the credit, the floor and what was left out")
  func spokenIsProse() throws {
    let account = derive(.chest)
      .account(muscleName: "Chest", windowLabel: "Last 7 days, 14 Nov to now", format: format)
    #expect(
      account.spoken
        == "Chest, at least 10 fractional sets, Last 7 days, 14 Nov to now, Moderate confidence. "
        + "Credited by Bench press 6, Incline press 4. "
        + "Left out: 2 warm-up sets, 2 sets on movements with no muscles recorded, 8 sets on other muscles' movements.")
    let credited = try #require(account.sections.first { $0.id == "credited" })
    #expect(
      credited.lines[0].spoken
        == "Bench press, 6 sets, direct, 1.0 each, 6 sets credited to chest.")
    for text in account.sections.flatMap(\.lines).map(\.spoken) + [account.spoken] {
      #expect(!text.contains("×") && !text.contains("→") && !text.contains("≥"))
    }
  }

  @Test("A muscle outside the studied research is not evaluated, and its caption says so")
  func notEvaluated() {
    // Forearms are counted, not modelled: the count is shown and the research does not reach it.
    let caption = derive(.forearms)
      .account(muscleName: "Forearms", windowLabel: "Last 7 days", format: format).figureCaption
    #expect(caption == "Last 7 days · Not evaluated")
  }
}
