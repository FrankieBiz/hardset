import Foundation
import Testing

@testable import HardsetCore

@Suite("VoiceOver hears units in full, and numbers read in the lifter's locale")
struct AccessibleTextTests {
  private let posix = Locale(identifier: "en_US_POSIX")
  private var kilograms: WeightFormatter { WeightFormatter(unit: .kilograms, locale: posix) }
  private var pounds: WeightFormatter { WeightFormatter(unit: .pounds, locale: posix) }

  @Test("A row is labelled by its number and valued by what it holds")
  func rowSpeech() {
    #expect(SetRowSpeech.label(number: 2, isWarmup: false) == "Set 2")
    #expect(SetRowSpeech.label(number: 0, isWarmup: true) == "Warm-up set")
    #expect(
      SetRowSpeech.value(weightKg: 100, reps: 8, isLogged: false, formatter: kilograms)
        == "100 kilograms, 8 reps")
    #expect(
      SetRowSpeech.value(weightKg: 100, reps: 1, isLogged: true, formatter: kilograms)
        == "100 kilograms, 1 rep, logged")
    #expect(
      SetRowSpeech.value(weightKg: nil, reps: nil, isLogged: false, formatter: kilograms)
        == "no values entered")
  }

  @Test("A half-entered row says which half is missing")
  func halfEntered() {
    #expect(
      SetRowSpeech.value(weightKg: 60, reps: nil, isLogged: false, formatter: kilograms)
        == "60 kilograms, reps not entered")
    #expect(
      SetRowSpeech.value(weightKg: nil, reps: 8, isLogged: false, formatter: kilograms)
        == "weight not entered, 8 reps")
  }

  @Test("Pounds are spoken as pounds")
  func poundsInFull() {
    #expect(
      SetRowSpeech.value(weightKg: 60, reps: 8, isLogged: false, formatter: pounds)
        == "132.28 pounds, 8 reps")
    let last = PriorSetRecord(weightKg: 60, reps: 8, completedAt: .distantPast)
    #expect(SetRowSpeech.previous(last, formatter: pounds) == "Last time 132.28 pounds for 8 reps")
    #expect(SetRowSpeech.previous(nil, formatter: pounds) == nil)
  }

  @Test("The hint says what a double tap does, and a logged row has none")
  func hints() {
    #expect(SetRowSpeech.hint(isLoggable: true, isLogged: false) == "Double tap to log this set.")
    #expect(SetRowSpeech.hint(isLoggable: false, isLogged: false) == "Enter a weight and reps to log.")
    #expect(SetRowSpeech.hint(isLoggable: true, isLogged: true) == nil)
  }

  @Test("A log is announced once, with any record in the same breath")
  func logAnnouncement() {
    #expect(
      SetRowSpeech.logAnnouncement(
        number: 2, isWarmup: false, weightKg: 100, reps: 8, exerciseName: "Leg Press",
        records: [], formatter: kilograms) == "Set 2 logged, 100 kilograms, 8 reps.")
    let record = PersonalRecord(kind: .heaviestLoad, weightKg: 105, reps: 8, previousWeightKg: 100)
    #expect(
      SetRowSpeech.logAnnouncement(
        number: 3, isWarmup: false, weightKg: 105, reps: 8, exerciseName: "Leg Press",
        records: [record], formatter: kilograms)
        == "Set 3 logged, 105 kilograms, 8 reps. New record on Leg Press. "
        + "Heaviest weight: 105 kilograms, up from 100 kilograms.")
  }

  @Test("A session's totals read the same on every screen, written and spoken")
  func sessionVolume() {
    let volume = SessionVolume(workingSets: 12, warmupSets: 2, volumeKg: 9_400, reps: 96)
    #expect(SessionVolumeText.written(volume, formatter: kilograms) == "12 sets · 96 reps · 9400 kg · 2 warm-up")
    #expect(
      SessionVolumeText.spoken(volume, formatter: kilograms)
        == "12 sets, 96 reps, 9400 kilograms, 2 warm-up sets")
    let one = SessionVolume(workingSets: 1, warmupSets: 1, volumeKg: 0, reps: 1)
    #expect(SessionVolumeText.written(one, formatter: kilograms) == "1 set · 1 rep · 1 warm-up")
    #expect(SessionVolumeText.spoken(one, formatter: kilograms) == "1 set, 1 rep, 1 warm-up set")
    let empty = SessionVolume(workingSets: 0, warmupSets: 0, volumeKg: 0, reps: 0)
    #expect(SessionVolumeText.written(empty, formatter: kilograms) == "No sets")
  }

  @Test("A total is spoken whole, in the lifter's unit")
  func spokenTotal() {
    #expect(pounds.spokenTotal(kilograms: 9_400) == "20723 pounds")
    #expect(kilograms.spokenTotal(kilograms: 9_400.4) == "9400 kilograms")
  }

  /// Review Focus: in a comma-decimal locale the row and the pad header both show "62,5".
  @Test("The typed value shows the locale's separator")
  func keypadDisplayUsesLocaleSeparator() {
    let german = Locale(identifier: "de_DE")
    let buffer = NumericEntryBuffer(value: 62.5)
    #expect(buffer.displayText(locale: german) == "62,5")
    #expect(buffer.displayText(locale: posix) == "62.5")
    let keypad = SetEntryKeypad(
      draft: SetEntryDraft(weightKg: 62.5, reps: 8), unit: .kilograms, machineIncrementKg: nil)
    #expect(keypad.composedText(locale: german) == "62,5 kg × 8")
  }

  @Test("The pad speaks the value being composed, with its field")
  func padSpeaks() {
    var keypad = SetEntryKeypad(
      draft: SetEntryDraft(weightKg: 62.5, reps: 8), unit: .kilograms, machineIncrementKg: nil)
    #expect(keypad.spokenValue(locale: posix) == "Weight, 62.5 kilograms")
    keypad.clear()
    #expect(keypad.spokenValue(locale: posix) == "Weight, empty")
    keypad.focus(.reps)
    #expect(keypad.spokenValue(locale: posix) == "Reps, 8")
  }

  @Test("The step keys say how far they move, in full")
  func stepLabels() {
    var keypad = SetEntryKeypad(
      draft: SetEntryDraft(weightKg: 60, reps: 8), unit: .pounds, machineIncrementKg: nil)
    #expect(keypad.spokenStep(.up, locale: posix) == "Add 5 pounds")
    #expect(keypad.spokenStep(.down, locale: posix) == "Subtract 5 pounds")
    keypad.focus(.reps)
    #expect(keypad.spokenStep(.up, locale: posix) == "One more rep")
    let machine = SetEntryKeypad(
      draft: SetEntryDraft(weightKg: 60, reps: 8), unit: .kilograms, machineIncrementKg: 2.5)
    #expect(machine.spokenStep(.down, locale: posix) == "Subtract 2.5 kilograms")
  }
}
