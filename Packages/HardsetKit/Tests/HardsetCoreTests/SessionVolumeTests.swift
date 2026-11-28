import Foundation
import Testing

@testable import HardsetCore

@Suite("Session volume counts only what was written")
struct SessionVolumeTests {
  private func state(
    slots: [(weight: Double?, reps: Int?, warmup: Bool, logged: Bool)]
  ) -> ExerciseLogState {
    ExerciseLogState(
      exerciseID: ExerciseID(),
      exerciseName: "Leg Press",
      prior: nil,
      slots: slots.map {
        SetSlot(
          draft: SetEntryDraft(weightKg: $0.weight, reps: $0.reps),
          isWarmup: $0.warmup,
          loggedSetID: $0.logged ? SetID() : nil
        )
      }
    )
  }

  @Test("Logged working sets are summed")
  func sumsLoggedSets() {
    let volume = SessionVolume(exercises: [
      state(slots: [
        (100, 10, false, true),
        (100, 8, false, true),
      ])
    ])
    #expect(volume.workingSets == 2)
    #expect(volume.volumeKg == 1800)
    #expect(volume.reps == 18)
    #expect(volume.warmupSets == 0)
  }

  /// A row the user typed into but never logged is not training, and must not inflate the
  /// number the product is judged on.
  @Test("A typed but unlogged row contributes nothing")
  func unloggedIsExcluded() {
    let volume = SessionVolume(exercises: [
      state(slots: [
        (100, 10, false, true),
        (200, 10, false, false),
      ])
    ])
    #expect(volume.workingSets == 1)
    #expect(volume.volumeKg == 1000)
  }

  @Test("Warm-ups are counted separately, not folded into volume")
  func warmupsAreSeparate() {
    let volume = SessionVolume(exercises: [
      state(slots: [
        (40, 15, true, true),
        (100, 8, false, true),
      ])
    ])
    #expect(volume.warmupSets == 1)
    #expect(volume.workingSets == 1)
    #expect(volume.volumeKg == 800)
    #expect(volume.reps == 8)
  }

  /// Belt and braces: a row cannot be logged without a resolvable draft, but if some future
  /// path bypasses the store, the total must not silently absorb a zero.
  @Test("An unresolvable draft is skipped rather than counted as zero")
  func unresolvableIsSkipped() {
    let volume = SessionVolume(exercises: [
      state(slots: [
        (nil, 10, false, true),
        (100, nil, false, true),
        (100, 8, false, true),
      ])
    ])
    #expect(volume.workingSets == 1)
    #expect(volume.volumeKg == 800)
  }

  /// Bodyweight work is real, contributes reps, and contributes no tonnage.
  @Test("Zero added load adds reps but no volume")
  func bodyweightAddsReps() {
    let volume = SessionVolume(exercises: [state(slots: [(0, 12, false, true)])])
    #expect(volume.workingSets == 1)
    #expect(volume.volumeKg == 0)
    #expect(volume.reps == 12)
  }

  @Test("An empty session reports empty")
  func empty() {
    #expect(SessionVolume(exercises: []).isEmpty)
    #expect(SessionVolume(exercises: [state(slots: [(100, 10, false, false)])]).isEmpty)
  }

  @Test("Volume sums across exercises")
  func acrossExercises() {
    let volume = SessionVolume(exercises: [
      state(slots: [(100, 10, false, true)]),
      state(slots: [(50, 10, false, true)]),
    ])
    #expect(volume.workingSets == 2)
    #expect(volume.volumeKg == 1500)
  }
}

@Suite("Durations render as clock time")
struct DurationClockStringTests {
  @Test(
    "Seconds format as m:ss",
    arguments: [
      (0.0, "0:00"), (5.0, "0:05"), (59.0, "0:59"), (60.0, "1:00"), (96.0, "1:36"),
      (599.0, "9:59"),
    ]
  )
  func minutesAndSeconds(seconds: Double, expected: String) {
    #expect(Duration.seconds(seconds).clockString == expected)
  }

  @Test("Past an hour, hours appear")
  func hours() {
    #expect(Duration.seconds(3600).clockString == "1:00:00")
    #expect(Duration.seconds(3661).clockString == "1:01:01")
  }

  /// An elapsed rest timer is finished, not owed.
  @Test("A negative duration reads as zero, not as a minus sign")
  func negativeIsZero() {
    #expect(Duration.seconds(-30).clockString == "0:00")
  }
}

/// "1:44" beside a clock glyph reads as an hour and forty-four minutes when it is a minute and
/// forty-four seconds, so a workout's length is said in words and never as a clock face.
@Suite("A workout's length is said as a length, never as a clock face")
struct WorkoutLengthTextTests {
  @Test("Under a minute there is nothing to draw")
  func underAMinute() {
    #expect(Duration.seconds(0).workoutLengthText == nil)
    #expect(Duration.seconds(44).workoutLengthText == nil)
    #expect(Duration.seconds(59.4).workoutLengthText == nil)
    #expect(Duration.seconds(-30).workoutLengthText == nil)
    #expect(Duration.seconds(44).workoutLengthSpoken == nil)
  }

  @Test("Under an hour it is whole minutes, to the nearest")
  func minutes() {
    #expect(Duration.seconds(60).workoutLengthText == "1 min")
    #expect(Duration.seconds(104).workoutLengthText == "2 min")  // 1:44
    #expect(Duration.seconds(89).workoutLengthText == "1 min")
    #expect(Duration.seconds(90).workoutLengthText == "2 min")
    #expect(Duration.seconds(45 * 60).workoutLengthText == "45 min")
    #expect(Duration.seconds(59 * 60 + 29).workoutLengthText == "59 min")
  }

  @Test("From an hour up it is hours and minutes")
  func hours() {
    #expect(Duration.seconds(1 * 3600 + 44 * 60).workoutLengthText == "1 h 44 min")  // 1:44:00
    #expect(Duration.seconds(3600 + 5 * 60).workoutLengthText == "1 h 5 min")
    #expect(Duration.seconds(3600).workoutLengthText == "1 h")
    // Rounding to the minute carries into the hour rather than reading "59 min" or "60 min".
    #expect(Duration.seconds(59 * 60 + 30).workoutLengthText == "1 h")
    #expect(Duration.seconds(2 * 3600 + 59 * 60 + 45).workoutLengthText == "3 h")
  }

  @Test("It is spelled out for VoiceOver")
  func spoken() {
    #expect(Duration.seconds(104).workoutLengthSpoken == "2 minutes")
    #expect(Duration.seconds(60).workoutLengthSpoken == "1 minute")
    #expect(Duration.seconds(3600 + 44 * 60).workoutLengthSpoken == "1 hour 44 minutes")
    #expect(Duration.seconds(3600).workoutLengthSpoken == "1 hour")
    #expect(Duration.seconds(2 * 3600 + 60).workoutLengthSpoken == "2 hours 1 minute")
  }

  /// Rest countdowns are clock faces and keep `clockString`.
  @Test("A countdown is still a clock face")
  func countdownUnchanged() {
    #expect(Duration.seconds(104).clockString == "1:44")
  }
}
