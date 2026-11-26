import Foundation
import Testing

@testable import HardsetCore

@Suite("Your heaviest at each rep count")
struct RepLadderTests {
  let epoch = Date(timeIntervalSince1970: 1_700_000_000)
  let exercise = ExerciseID()
  let machine = MachineID()

  private func day(_ n: Int) -> Date { epoch.addingTimeInterval(Double(n) * 86_400) }

  private func sample(
    _ kg: Double, _ reps: Int, day dayNumber: Int, on machineID: MachineID?,
    isImported: Bool = false
  ) -> ProgressionSample {
    ProgressionSample(
      sessionID: SessionID(), machineID: machineID, weightKg: kg, reps: reps,
      completedAt: day(dayNumber), isImported: isImported)
  }

  private func key(_ machineID: MachineID? = nil, imported: Bool = false) -> ProgressionKey {
    ProgressionKey(exerciseID: exercise, machineID: machineID, isImported: imported)
  }

  private var format: WorkedFromFormat {
    WorkedFromFormat(
      unit: .kilograms, locale: Locale(identifier: "en_US_POSIX"),
      timeZone: TimeZone(secondsFromGMT: 0)!)
  }

  @Test("Each rung is the heaviest set with exactly that many reps")
  func rungIsTheHeaviestAtItsExactReps() {
    let samples = [
      sample(40, 1, day: 0, on: machine),
      sample(60, 8, day: 1, on: machine),
      sample(80, 8, day: 2, on: machine),
      sample(70, 8, day: 3, on: machine),
      sample(90, 10, day: 4, on: machine),
      sample(90, 12, day: 5, on: machine),
      sample(100, 20, day: 6, on: machine),
    ]

    let ladder = RepLadder.ladder(for: key(machine), from: samples)

    #expect(ladder.rungs.map(\.reps) == [1, 8, 10, 12])
    #expect(ladder.rung(reps: 8)?.weightKg == 80)
    #expect(ladder.rung(reps: 8)?.completedAt == day(2))
    #expect(ladder.rung(reps: 10)?.weightKg == 90)
    #expect(ladder.rung(reps: 12)?.weightKg == 90)
    // Twenty reps is outside the twelve the ladder covers, and was not invented as a cell.
    #expect(ladder.rung(reps: 20) == nil)
  }

  @Test("A rep count with no set has no cell")
  func absentCountsStayAbsent() {
    let samples = [
      sample(40, 5, day: 0, on: machine),
      sample(50, 9, day: 1, on: machine),
    ]
    let ladder = RepLadder.ladder(for: key(machine), from: samples)
    let produced = Set(samples.map(\.reps))

    for reps in RepLadder.repCounts {
      #expect(
        (ladder.rung(reps: reps) != nil) == produced.contains(reps),
        "\(reps) reps should exist only when a set produced it")
    }
    #expect(ladder.rungs.count == produced.count)
  }

  @Test("Loads within the record tolerance are one load")
  func toleranceKeepsOneRung() {
    let samples = [
      sample(40, 8, day: 0, on: machine),
      sample(40.004, 8, day: 1, on: machine),
    ]
    let ladder = RepLadder.ladder(for: key(machine), from: samples)

    #expect(ladder.rungs.count == 1)
    #expect(ladder.rung(reps: 8)?.weightKg == 40)
    #expect(ladder.rung(reps: 8)?.completedAt == day(0))

    // A load beyond the tolerance is a genuinely heavier set and replaces the rung.
    let heavier = RepLadder.ladder(
      for: key(machine), from: samples + [sample(40.02, 8, day: 2, on: machine)])
    #expect(heavier.rung(reps: 8)?.weightKg == 40.02)
    #expect(heavier.rung(reps: 8)?.completedAt == day(2))
  }

  @Test("Two machines are two ladders, never one line")
  func twoMachinesStayApart() {
    let other = MachineID()
    let samples = [
      sample(80, 8, day: 0, on: machine),
      sample(120, 8, day: 1, on: other),
      sample(85, 10, day: 2, on: machine),
    ]

    let ladders = RepLadder.ladders(for: exercise, from: samples)

    #expect(ladders.count == 2)
    #expect(ladders[key(machine)]?.rung(reps: 8)?.weightKg == 80)
    #expect(ladders[key(machine)]?.rung(reps: 10)?.weightKg == 85)
    #expect(ladders[key(other)]?.rung(reps: 8)?.weightKg == 120)
    #expect(ladders[key(other)]?.rung(reps: 10) == nil)

    // One key's ladder reads only its own sets even when built from both machines' history.
    let one = RepLadder.ladder(for: key(machine), from: samples)
    #expect(one.rungs.map(\.weightKg) == [80, 85])
  }

  @Test("Imported sets stay on the imported key")
  func importedSetsStayImported() {
    let samples = [
      sample(100, 8, day: 0, on: machine),
      sample(140, 8, day: 1, on: nil, isImported: true),
    ]

    let ladders = RepLadder.ladders(for: exercise, from: samples)

    #expect(ladders.count == 2)
    #expect(ladders[key(machine)]?.rung(reps: 8)?.weightKg == 100)
    #expect(ladders[key(nil, imported: true)]?.rung(reps: 8)?.weightKg == 140)
  }

  @Test("A rung opens the set it came from")
  func rungOpensItsSet() throws {
    let samples = [
      sample(40, 8, day: 0, on: machine),
      sample(30, 8, day: 1, on: machine),
    ]
    let ladder = RepLadder.ladder(for: key(machine), from: samples)
    let account = try #require(
      ladder.working(reps: 8, from: samples, label: "Leg press", format: format))

    #expect(account.title == "Your heaviest 8")
    #expect(account.figure == "40 kg")
    #expect(account.figureCaption == "\(format.day(day(0))) · Leg press")
    #expect(account.sections.count == 2)

    let produced = try #require(account.sections.first?.lines.first)
    #expect(produced.standing == .produced)
    #expect(produced.headline == "40 kg × 8")
    #expect(produced.context == "\(format.day(day(0))) · Leg press")
    #expect(produced.detail == "The heaviest set at 8 reps.")

    let other = try #require(
      account.sections.last?.lines.first { $0.headline == "30 kg × 8" })
    #expect(other.standing == .counted)
    #expect(other.detail == "Lighter than your heaviest 8.")

    // A count with no set has nothing to open.
    #expect(ladder.working(reps: 5, from: samples, label: "Leg press", format: format) == nil)
  }

  @Test("The ladder's words never give a recommendation")
  func copyCarriesNoRecommendation() {
    let banned = [
      "try", "aim", "should", "must", "recommend", "target", "increase", "decrease",
      "add", "push", "beat", "could", "can", "will", "go for", "next time",
    ]
    let allSamples = (1...12).map { reps in
      sample(Double(20 + reps * 5), reps, day: reps, on: machine)
    }
    let ladder = RepLadder.ladder(for: key(machine), from: allSamples)

    var strings = [
      RepLadderCopy.sectionTitle, RepLadderCopy.sectionDetail, RepLadderCopy.openHint,
      RepLadderCopy.ruleHeading, RepLadderCopy.producedHeading,
      RepLadderCopy.producedStandingWord, RepLadderCopy.otherSetsNote,
      RepLadderCopy.sameLoadDetail,
    ]
    for reps in RepLadder.repCounts {
      strings.append(contentsOf: [
        RepLadderCopy.repsText(reps), RepLadderCopy.rungName(reps: reps),
        RepLadderCopy.producedDetail(reps: reps), RepLadderCopy.lighterDetail(reps: reps),
        RepLadderCopy.otherSetsHeading(reps: reps), RepLadderCopy.rule(reps: reps),
        RepLadderCopy.rowLabel(
          reps: reps, weightKg: 40, date: day(0), machine: "Leg press", format: format),
      ])
      guard
        let account = ladder.working(
          reps: reps, from: allSamples, label: "Leg press", format: format)
      else {
        Issue.record("\(reps) reps should have an account")
        continue
      }
      strings.append(contentsOf: [
        account.title, account.figure, account.figureCaption, account.ruleHeading, account.rule,
        account.spoken,
      ])
      for section in account.sections {
        strings.append(section.heading)
        if let note = section.note { strings.append(note) }
        for line in section.lines {
          strings.append(line.headline)
          strings.append(line.detail)
          strings.append(line.spoken)
          if let context = line.context { strings.append(context) }
          if let word = line.standingWord { strings.append(word) }
        }
      }
    }

    for text in strings {
      for word in banned {
        #expect(
          text.range(of: "\\b\(word)\\b", options: [.regularExpression, .caseInsensitive]) == nil,
          "\"\(word)\" in \"\(text)\"")
      }
      #expect(!text.contains("%"), "a percentage in \"\(text)\"")
    }
  }
}
