import Foundation
import Testing

@testable import HardsetCore

@Suite("The widget's file says what was done last, in the lifter's unit, and never counts days")
struct WidgetSnapshotTests {
  let t = Date(timeIntervalSince1970: 90_000_000)

  private func lastTime(sets: [(Double, Int)], machine: String? = "Hammer Strength Leg Press")
    -> WidgetSnapshot.LastTime
  {
    WidgetSnapshot.LastTime(
      exerciseID: ExerciseID(), machineID: machine == nil ? nil : MachineID(),
      exerciseName: "Leg Press", machineName: machine, performedAt: t,
      sets: sets.map { WidgetSnapshot.SetLine(weightKg: $0.0, reps: $0.1) })
  }

  private func snapshot(unit: WeightUnit = .kilograms) -> WidgetSnapshot {
    WidgetSnapshot(
      writtenAt: t, unit: unit,
      lastWorkout: .init(
        startedAt: t, finishedAt: t + 3_130, lengthSeconds: 3_130, workingSets: 18, volumeKg: 9_400,
        movementCount: 5),
      lastTimes: [lastTime(sets: [(100, 8), (100, 8), (95, 7)])])
  }

  private func temporaryFile() -> WidgetSnapshotFile {
    WidgetSnapshotFile(
      url: FileManager.default.temporaryDirectory
        .appendingPathComponent("hardset-widget-\(UUID().uuidString).json"))
  }

  @Test("Written and read back unchanged")
  func roundTrip() throws {
    let file = temporaryFile()
    let original = snapshot()
    try file.write(original)
    #expect(file.read() == .snapshot(original))
  }

  /// Review Focus: no file yet, a torn or corrupt file, a file from a newer build. Each is a calm
  /// state, never a crash and never someone else's numbers.
  @Test("No file is nothing yet; a corrupt or newer file is unreadable")
  func unreadableFileIsEmptyNotCrash() throws {
    #expect(temporaryFile().read() == .nothingYet)
    #expect(WidgetSnapshotFile.decode(Data("{\"version\":1,".utf8)) == .unreadable)
    #expect(WidgetSnapshotFile.decode(Data()) == .unreadable)
  }

  @Test("A file from a newer build is not half-understood")
  func newerVersionIsIgnored() throws {
    let newer = WidgetSnapshot(
      version: WidgetSnapshot.currentVersion + 1, writtenAt: t, unit: .kilograms, lastWorkout: nil,
      lastTimes: [])
    let data = try JSONEncoder().encode(newer)
    #expect(WidgetSnapshotFile.decode(data) == .unreadable)
  }

  @Test("No App Group container, no file")
  func noContainer() {
    #expect(WidgetSnapshotFile(containerURL: nil) == nil)
    let url = URL(fileURLWithPath: "/tmp/group")
    #expect(WidgetSnapshotFile(containerURL: url)?.url.lastPathComponent == "widget-snapshot.json")
  }

  @Test("Sets read in the lifter's unit, and a long list says how many more")
  func lines() {
    let five = lastTime(sets: [(100, 8), (100, 8), (95, 7), (95, 6), (90, 6)])
    let kg = WeightFormatter(unit: .kilograms, locale: Locale(identifier: "en_US_POSIX"))
    #expect(five.lines(formatter: kg, limit: 3) == ["100 kg × 8", "100 kg × 8", "95 kg × 7", "+2 more sets"])
    let lb = WeightFormatter(unit: .pounds, locale: Locale(identifier: "en_US_POSIX"))
    #expect(lastTime(sets: [(100, 8)]).lines(formatter: lb, limit: 3) == ["220.46 lb × 8"])
  }

  @Test("Free weight is named, and VoiceOver hears units in full")
  func spoken() {
    let free = lastTime(sets: [(60, 10)], machine: nil)
    #expect(free.equipmentText == "Free weight")
    let kg = WeightFormatter(unit: .kilograms, locale: Locale(identifier: "en_US_POSIX"))
    #expect(free.spokenSummary(formatter: kg) == "Leg Press on Free weight: 60 kilograms for 10 reps")
  }

  @Test("The last workout's totals and length")
  func lastWorkout() throws {
    let workout = try #require(snapshot().lastWorkout)
    let kg = WeightFormatter(unit: .kilograms, locale: Locale(identifier: "en_US_POSIX"))
    #expect(workout.totalsText(formatter: kg) == "18 sets · 9400 kg")
    #expect(workout.lengthText == "52:10")
    let unknown = WidgetSnapshot.LastWorkout(
      startedAt: t, finishedAt: t, lengthSeconds: nil, workingSets: 1, volumeKg: 100,
      movementCount: 1)
    #expect(unknown.lengthText == "Length unknown")
    #expect(unknown.totalsText(formatter: kg) == "1 set · 100 kg")
  }

  /// Spec 4.5: no "days since" counts. A relative date is one.
  @Test("Dates are dates, never days ago")
  func dayTextIsAbsolute() {
    let text = WidgetSnapshot.dayText(
      t, locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "UTC")!)
    // 90,000,000 s after 1970 is Tuesday 7 November 1972.
    #expect(text.contains("7"))
    #expect(text.contains("Nov"))
    #expect(text.contains("Tue"))
    for word in ["ago", "today", "yesterday", "days", "since"] {
      #expect(!text.lowercased().contains(word))
    }
  }

  @Test("The empty states are calm and count nothing")
  func copy() {
    for line in [WidgetCopy.nothingYet, WidgetCopy.unreadable] {
      for word in ["error", "failed", "streak", "days", "since"] {
        #expect(!line.lowercased().contains(word), "\(line)")
      }
    }
  }
}
