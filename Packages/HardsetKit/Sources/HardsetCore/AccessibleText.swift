import Foundation

/// What VoiceOver says about a set row, and after a log (spec 3.4).
///
/// Written here, not in `SetRowView`, so every sentence is tested. Units are always in full:
/// VoiceOver reads "kg" as "k g", and "lb" as "l b".
public enum SetRowSpeech {
  /// The row's label: "Set 2", or "Warm-up set". `number` is the working-set number the row shows.
  public static func label(number: Int, isWarmup: Bool) -> String {
    isWarmup ? "Warm-up set" : "Set \(number)"
  }

  /// The row's value: "100 kilograms, 8 reps", with ", logged" once it is saved. A half-entered
  /// row says which half is missing.
  public static func value(
    weightKg: Double?, reps: Int?, isLogged: Bool, formatter: WeightFormatter
  ) -> String {
    let weight = weightKg.map { formatter.spoken(kilograms: $0) }
    let count = reps.map(CountText.reps)
    let entry: String =
      switch (weight, count) {
      case let (weight?, count?): "\(weight), \(count)"
      case let (weight?, nil): "\(weight), reps not entered"
      case let (nil, count?): "weight not entered, \(count)"
      case (nil, nil): "no values entered"
      }
    return isLogged ? "\(entry), logged" : entry
  }

  /// "Last time 100 kilograms for 8 reps", or nil with no history.
  public static func previous(_ record: PriorSetRecord?, formatter: WeightFormatter) -> String? {
    record.map { "Last time \(formatter.spoken(kilograms: $0.weightKg)) for \(CountText.reps($0.reps))" }
  }

  /// What a double tap does. Nil on a logged row, which has nothing left to do.
  public static func hint(isLoggable: Bool, isLogged: Bool) -> String? {
    guard !isLogged else { return nil }
    return isLoggable ? "Double tap to log this set." : "Enter a weight and reps to log."
  }

  /// Said once, after the write succeeds: "Set 2 logged, 100 kilograms, 8 reps." A record follows
  /// in the same announcement, so VoiceOver does not read two at once and drop one.
  public static func logAnnouncement(
    number: Int, isWarmup: Bool, weightKg: Double, reps: Int, exerciseName: String,
    records: [PersonalRecord], formatter: WeightFormatter
  ) -> String {
    let logged =
      "\(label(number: number, isWarmup: isWarmup)) logged, "
      + "\(formatter.spoken(kilograms: weightKg)), \(CountText.reps(reps))."
    guard
      let record = RecordCopy.announcement(
        for: records, exerciseName: exerciseName, formatter: formatter)
    else { return logged }
    return "\(logged) \(record)"
  }
}

/// A session's totals as one line, written and spoken. The history row and the session detail
/// both use it, so they cannot disagree.
public enum SessionVolumeText {
  /// "12 sets · 96 reps · 9400 kg · 2 warm-up", or "No sets".
  public static func written(_ volume: SessionVolume, formatter: WeightFormatter) -> String {
    guard !volume.isEmpty else { return "No sets" }
    var parts = [CountText.sets(volume.workingSets), CountText.reps(volume.reps)]
    if volume.volumeKg > 0 { parts.append(formatter.total(kilograms: volume.volumeKg)) }
    if volume.warmupSets > 0 { parts.append("\(volume.warmupSets) warm-up") }
    return parts.joined(separator: " · ")
  }

  /// "12 sets, 96 reps, 9400 kilograms, 2 warm-up sets", or "No sets".
  public static func spoken(_ volume: SessionVolume, formatter: WeightFormatter) -> String {
    guard !volume.isEmpty else { return "No sets" }
    var parts = [CountText.sets(volume.workingSets), CountText.reps(volume.reps)]
    if volume.volumeKg > 0 { parts.append(formatter.spokenTotal(kilograms: volume.volumeKg)) }
    if volume.warmupSets > 0 {
      parts.append(volume.warmupSets == 1 ? "1 warm-up set" : "\(volume.warmupSets) warm-up sets")
    }
    return parts.joined(separator: ", ")
  }
}

extension NumericEntryBuffer {
  /// The typed text with the locale's decimal separator: "62,5" in German. The buffer always
  /// stores ".", so the row and the pad header must both substitute, and both call this.
  public func displayText(locale: Locale) -> String {
    text.replacingOccurrences(of: ".", with: locale.decimalSeparator ?? ".")
  }
}

extension SetEntryKeypad {
  /// What the pad's header says to VoiceOver as the value changes: "Weight, 62.5 kilograms",
  /// "Reps, 8", or "Weight, empty". Spoken in full, never "kg".
  public func spokenValue(locale: Locale = .current) -> String {
    switch field {
    case .weight:
      guard let value = weight.value else { return "Weight, empty" }
      let formatter = WeightFormatter(unit: unit, locale: locale)
      return "Weight, \(formatter.spoken(kilograms: unit.toKilograms(value)))"
    case .reps:
      guard let value = reps.value else { return "Reps, empty" }
      return "Reps, \(Int(value))"
    }
  }

  /// The ± keys' spoken labels: "Add 2.5 kilograms", "One fewer rep".
  public func spokenStep(_ direction: Direction, locale: Locale = .current) -> String {
    switch field {
    case .weight:
      let amount = WeightFormatter(unit: unit, locale: locale)
        .spoken(kilograms: unit.toKilograms(loadStep.amount))
      return direction == .up ? "Add \(amount)" : "Subtract \(amount)"
    case .reps:
      return direction == .up ? "One more rep" : "One fewer rep"
    }
  }
}
