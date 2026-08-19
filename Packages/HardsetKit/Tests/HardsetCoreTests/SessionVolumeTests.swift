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
