#if canImport(UIKit)
  import Foundation
  import HardsetCore
  import HardsetUI
  import SwiftUI
  import Testing
  import UIKit

  /// Renders the "Worked from" sheet as the root view for each surface that opens it, so the
  /// working can be reviewed from images.
  ///
  /// The accounts are derived by Core from sets, not typed in here, so what is captured is the words
  /// a lifter would read. Like the other render suites it is inert unless `HARDSET_SNAPSHOT_DIR` is
  /// set, and it asserts nothing about pixels.
  @MainActor
  @Suite("Worked from sheet renders for review", .serialized)
  struct WorkedFromSheetSnapshotTests {
    private static let tall = CGSize(width: 402, height: 1400)
    private static let accessibility = CGSize(width: 402, height: 5200)

    private static let format = WorkedFromFormat(
      unit: .kilograms, locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "UTC")!)

    /// A session on one machine with a set that is the figure, one below it, a set too long to
    /// estimate, a warm-up, and a set from the same session on other equipment.
    static func estimateAccount() -> WorkedFromAccount {
      let exercise = ExerciseID()
      let hammer = MachineID()
      let cybex = MachineID()
      let session = SessionID()
      let start = Date(timeIntervalSince1970: 1_700_000_000)
      func set(_ kg: Double, _ reps: Int, _ minute: Int, _ machine: MachineID) -> ProgressionSample {
        ProgressionSample(
          sessionID: session, machineID: machine, weightKg: kg, reps: reps,
          completedAt: start.addingTimeInterval(Double(minute) * 60))
      }
      let key = ProgressionKey(exerciseID: exercise, machineID: hammer)
      let working = EstimateWorking.derive(
        key: key, sessionID: session,
        samples: [
          set(100, 5, 5, hammer), set(100, 8, 10, hammer), set(60, 15, 15, hammer),
          set(140, 3, 25, cybex),
        ],
        warmups: [set(60, 10, 0, hammer)],
        estimatesOneRepMax: true,
        label: { $0.machineID == hammer ? "Hammer Strength" : "Cybex" })
      return working!.account(format: format)
    }

    /// A week with a muscle credited by two movements at two roles, a movement that only stabilises
    /// it, a movement nobody has attributed, and warm-ups: every line the account can hold.
    static func muscleAccount() -> WorkedFromAccount {
      let bench = ExerciseID()
      let fly = ExerciseID()
      let pullUp = ExerciseID()
      let mystery = ExerciseID()
      let squat = ExerciseID()
      func contribution(_ muscle: Muscle, _ role: MuscleRole) -> MuscleContribution {
        MuscleContribution(muscle, role: role, certainty: .moderate, source: .anatomy)
      }
      let attribution = AttributionIndex([
        bench: [contribution(.chest, .direct), contribution(.triceps, .indirect)],
        fly: [contribution(.chest, .indirect)],
        pullUp: [contribution(.lats, .direct), contribution(.chest, .stabilizer)],
        squat: [contribution(.quadriceps, .direct)],
      ])
      func sets(_ id: ExerciseID, _ count: Int, warmup: Bool = false) -> [CountableSet] {
        (0..<count).map { _ in CountableSet(exerciseID: id, isWarmup: warmup) }
      }
      let names = [bench: "Barbell bench press", fly: "Cable fly", pullUp: "Pull-up", mystery: "Cable crossover", squat: "Back squat"]
      return MuscleCountWorking.derive(
        muscle: .chest,
        sets: sets(bench, 8) + sets(bench, 2, warmup: true) + sets(fly, 5) + sets(pullUp, 6)
          + sets(mystery, 3) + sets(squat, 4),
        attribution: attribution, name: { names[$0] ?? "Unknown movement" }
      ).account(muscleName: "Chest", windowLabel: "Last 7 days, 14 Nov to now", format: format)
    }

    /// The Volume screen's monument: a week of working sets across movements, one with no muscles
    /// recorded, and warm-ups under Left out.
    static func workingSetCountAccount() -> WorkedFromAccount {
      let bench = ExerciseID()
      let squat = ExerciseID()
      let mystery = ExerciseID()
      func contribution(_ muscle: Muscle, _ role: MuscleRole) -> MuscleContribution {
        MuscleContribution(muscle, role: role, certainty: .moderate, source: .anatomy)
      }
      let attribution = AttributionIndex([
        bench: [contribution(.chest, .direct), contribution(.triceps, .indirect)],
        squat: [contribution(.quadriceps, .direct), contribution(.glutes, .indirect)],
      ])
      func sets(_ id: ExerciseID, _ count: Int, warmup: Bool = false) -> [CountableSet] {
        (0..<count).map { _ in CountableSet(exerciseID: id, isWarmup: warmup) }
      }
      let names = [bench: "Barbell bench press", squat: "Back squat", mystery: "Cable crossover"]
      return WorkingSetCountWorking.derive(
        sets: sets(bench, 12) + sets(bench, 3, warmup: true) + sets(squat, 14) + sets(squat, 2, warmup: true)
          + sets(mystery, 3),
        attribution: attribution, name: { names[$0] ?? "Unknown movement" }
      ).account(windowLabel: "Last 7 days, 14 Nov to now", format: format)
    }

    /// The Train screen's monument: a workout's sets as weight x reps, a warm-up under Left out and
    /// a set with no load.
    static func sessionVolumeAccount() -> WorkedFromAccount {
      func line(
        _ name: String, _ kg: Double, _ reps: Int, warmup: Bool = false, machine: String? = "Hammer Strength"
      ) -> WorkoutReceipt.Line {
        WorkoutReceipt.Line(
          id: SetID(), exerciseName: name, machineName: machine, weightKg: kg, reps: reps,
          isWarmup: warmup)
      }
      return SessionVolumeWorking.derive(lines: [
        line("Chest press", 60, 12, warmup: true),
        line("Chest press", 100, 10),
        line("Chest press", 100, 8),
        line("Chest press", 102.5, 6),
        line("Pull-up", 0, 10, machine: nil),
      ]).account(title: "Push day", format: format)
    }

    /// Two sessions that each set records on one machine, with the machine's own 5 kg step.
    static func chartRecordAccount() -> WorkedFromAccount {
      let exercise = ExerciseID()
      let hammer = MachineID()
      let key = ProgressionKey(exerciseID: exercise, machineID: hammer)
      let start = Date(timeIntervalSince1970: 1_700_000_000)
      func set(_ kg: Double, _ reps: Int, day: Int) -> ProgressionSample {
        ProgressionSample(
          sessionID: SessionID(), machineID: hammer, weightKg: kg, reps: reps,
          completedAt: start.addingTimeInterval(Double(day) * 86_400))
      }
      return RecordWorking.chartAccount(
        keys: [key], samples: [set(100, 5, day: 0), set(110, 5, day: 7), set(110, 8, day: 14)],
        estimatesOneRepMax: true, incrementKg: { _ in 5 }, label: { _ in "Hammer Strength" },
        format: format)!
    }

    /// A receipt with a record of each of the four kinds, so every sentence the account can say is
    /// captured once.
    static func receiptRecordAccount() -> WorkedFromAccount {
      func line(
        _ name: String, _ kg: Double, _ reps: Int, _ equipment: WorkoutReceipt.Equipment,
        _ records: [PersonalRecord]
      ) -> WorkoutReceipt.Line {
        WorkoutReceipt.Line(
          id: SetID(), exerciseID: nil, exerciseName: name, equipment: equipment, weightKg: kg,
          reps: reps, isWarmup: false, records: records, incrementKg: 5)
      }
      let receipt = WorkoutReceipt(
        id: SessionID(), title: "Push day", startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        finishedAt: Date(timeIntervalSince1970: 1_700_003_600),
        lines: [
          line(
            "Chest press", 105, 5, .machine("Hammer Strength"),
            [PersonalRecord(kind: .heaviestLoad, weightKg: 105, reps: 5, previousWeightKg: 100)]),
          line(
            "Chest press", 100, 9, .machine("Hammer Strength"),
            [PersonalRecord(kind: .repsAtLoad, weightKg: 100, reps: 9, previousWeightKg: 100, previousReps: 8)]),
          line(
            "Row", 105, 8, .unrecorded,
            [PersonalRecord(kind: .loadAtReps, weightKg: 105, reps: 8, previousWeightKg: 100, previousReps: 8)]),
          line(
            "Back squat", 100, 8, .freeWeight,
            [PersonalRecord(kind: .estimatedOneRepMax, weightKg: 100, reps: 8, previousWeightKg: 116.7)]),
        ])
      return RecordWorking.receiptAccount(receipt: receipt, format: format)!
    }

    /// A Progress row's six-week change: the latest session, the baseline five to seven weeks before
    /// it, another session in the band that lost, a set too long to estimate, a warm-up, a set on other
    /// equipment and sessions outside the band.
    static func sixWeekAccount() -> WorkedFromAccount {
      let exercise = ExerciseID()
      let hammer = MachineID()
      let cybex = MachineID()
      let key = ProgressionKey(exerciseID: exercise, machineID: hammer)
      let start = Date(timeIntervalSince1970: 1_700_000_000)
      func set(
        _ session: SessionID, _ kg: Double, _ reps: Int, day: Int, minute: Int = 0,
        machine: MachineID? = nil
      ) -> ProgressionSample {
        // Unless it says otherwise, a set is on the machine the row is for.
        ProgressionSample(
          sessionID: session, machineID: machine ?? hammer, weightKg: kg, reps: reps,
          completedAt: start.addingTimeInterval(Double(day) * 86_400 + Double(minute) * 60))
      }
      let baseline = SessionID()
      let below = SessionID()
      let recent = SessionID()
      let latest = SessionID()
      let working = ChangeWorking.sixWeek(
        key: key,
        samples: [
          set(baseline, 100, 5, day: 0), set(baseline, 100, 8, day: 0, minute: 5),
          set(baseline, 60, 15, day: 0, minute: 10), set(baseline, 90, 8, day: 0, minute: 15, machine: cybex),
          set(below, 90, 8, day: 3), set(recent, 95, 8, day: 14), set(latest, 120, 5, day: 42),
          set(latest, 120, 4, day: 42, minute: 5),
        ],
        warmups: [set(baseline, 40, 10, day: 0, minute: -5), set(latest, 60, 5, day: 42, minute: -5)],
        estimatesOneRepMax: true, label: { $0.machineID == hammer ? "Hammer Strength" : "Cybex" })
      return working!.account(format: format)
    }

    /// The scorecard's biggest gain: this workout against last time on the same machine, with
    /// warm-ups, a set on other equipment and an older session left out.
    static func gainAccount() -> WorkedFromAccount {
      let start = Date(timeIntervalSince1970: 1_700_000_000)
      func set(_ kg: Double, _ reps: Int, day: Int, minute: Int = 0) -> PriorSetRecord {
        PriorSetRecord(
          weightKg: kg, reps: reps,
          completedAt: start.addingTimeInterval(Double(day) * 86_400 + Double(minute) * 60))
      }
      let input = ScorecardInput(
        key: ProgressionKey(exerciseID: ExerciseID(), machineID: MachineID()), exerciseName: "Incline press",
        currentSets: [set(80, 9, day: 7), set(80, 8, day: 7, minute: 5), set(60, 15, day: 7, minute: 10)],
        previousSets: [set(80, 7, day: 0), set(80, 6, day: 0, minute: 5)],
        leftOut: ScorecardInput.LeftOut(
          currentWarmups: 2, currentOtherEquipment: 1, previousWarmups: 1, olderSessions: 4, olderSets: 14))
      let gain = WorkoutScorecard.make([input]).biggestGain!
      return ChangeWorking.lastTime(gain: gain)!.account(format: format)
    }

    /// The live record notice: two records on a set just logged, one an estimate, with the
    /// estimate's formula and what the comparison was never made against.
    static func liveRecordAccount() -> WorkedFromAccount {
      let exercise = ExerciseID()
      let hammer = MachineID()
      let cybex = MachineID()
      let key = ProgressionKey(exerciseID: exercise, machineID: hammer)
      let start = Date(timeIntervalSince1970: 1_700_000_000)
      func set(
        _ session: SessionID, _ kg: Double, _ reps: Int, day: Int, minute: Int = 0,
        machine: MachineID? = nil, imported: Bool = false
      ) -> ProgressionSample {
        // Unless it says otherwise, a set is on the machine the record was set on; an imported set
        // records no machine.
        ProgressionSample(
          sessionID: session, machineID: imported ? nil : (machine ?? hammer), weightKg: kg, reps: reps,
          completedAt: start.addingTimeInterval(Double(day) * 86_400 + Double(minute) * 60),
          isImported: imported)
      }
      let earlier = SessionID()
      let today = SessionID()
      let records = PersonalRecordDetector.records(
        for: .init(weightKg: 100, reps: 8),
        history: [PriorSetRecord(weightKg: 100, reps: 5, completedAt: start)], increment: nil,
        estimatesOneRepMax: true)
      return RecordWorking.liveAccount(
        records: records, exerciseName: "Chest press", sessionID: today, key: key,
        samples: [
          set(earlier, 100, 5, day: 0), set(earlier, 90, 8, day: 0, minute: 5, machine: cybex),
          set(SessionID(), 80, 10, day: -30, imported: true), set(today, 100, 8, day: 14),
        ],
        warmups: [set(earlier, 40, 10, day: 0, minute: -5), set(today, 50, 5, day: 14, minute: -5)],
        estimatesOneRepMax: true, incrementKg: nil,
        label: { $0.machineID == hammer ? "Hammer Strength" : "Cybex" }, format: format)!
    }

    private static func sheet(_ account: WorkedFromAccount) -> some View {
      WorkedFromSheet(account: account)
        .tint(Tokens.Color.plateBlue)
    }

    @Test func estimate() async throws {
      try await Snapshot.capture("kit-worked-from-estimate-dark", size: Self.tall) {
        Self.sheet(Self.estimateAccount())
      }
      try await Snapshot.capture("kit-worked-from-estimate-light", size: Self.tall, style: .light) {
        Self.sheet(Self.estimateAccount())
      }
      try await Snapshot.capture(
        "kit-worked-from-estimate-dark-contrast", size: Self.tall, contrast: .high
      ) {
        Self.sheet(Self.estimateAccount())
      }
    }

    @Test func muscleCount() async throws {
      try await Snapshot.capture("kit-worked-from-muscle-dark", size: Self.tall) {
        Self.sheet(Self.muscleAccount())
      }
      try await Snapshot.capture("kit-worked-from-muscle-light", size: Self.tall, style: .light) {
        Self.sheet(Self.muscleAccount())
      }
    }

    @Test func monuments() async throws {
      try await Snapshot.capture("kit-worked-from-working-sets-dark", size: Self.tall) {
        Self.sheet(Self.workingSetCountAccount())
      }
      try await Snapshot.capture("kit-worked-from-working-sets-light", size: Self.tall, style: .light) {
        Self.sheet(Self.workingSetCountAccount())
      }
      try await Snapshot.capture("kit-worked-from-volume-dark", size: Self.tall) {
        Self.sheet(Self.sessionVolumeAccount())
      }
      try await Snapshot.capture("kit-worked-from-volume-light", size: Self.tall, style: .light) {
        Self.sheet(Self.sessionVolumeAccount())
      }
      try await Snapshot.capture(
        "kit-worked-from-volume-dark-ax3", size: Self.accessibility, typeSize: .accessibility3
      ) {
        Self.sheet(Self.sessionVolumeAccount())
      }
    }

    @Test func cappedEstimates() async throws {
      try await Snapshot.capture("kit-worked-from-six-week-dark", size: Self.accessibility) {
        Self.sheet(Self.sixWeekAccount())
      }
      try await Snapshot.capture("kit-worked-from-six-week-light", size: Self.accessibility, style: .light) {
        Self.sheet(Self.sixWeekAccount())
      }
      try await Snapshot.capture("kit-worked-from-gain-dark", size: Self.accessibility) {
        Self.sheet(Self.gainAccount())
      }
      try await Snapshot.capture("kit-worked-from-record-notice-dark", size: Self.accessibility) {
        Self.sheet(Self.liveRecordAccount())
      }
      try await Snapshot.capture(
        "kit-worked-from-record-notice-dark-ax3", size: CGSize(width: 402, height: 9000),
        typeSize: .accessibility3
      ) {
        Self.sheet(Self.liveRecordAccount())
      }
    }

    @Test func records() async throws {
      try await Snapshot.capture("kit-worked-from-records-chart-dark", size: Self.tall) {
        Self.sheet(Self.chartRecordAccount())
      }
      try await Snapshot.capture("kit-worked-from-records-receipt-dark", size: Self.accessibility) {
        Self.sheet(Self.receiptRecordAccount())
      }
      try await Snapshot.capture(
        "kit-worked-from-records-receipt-light", size: Self.accessibility, style: .light
      ) {
        Self.sheet(Self.receiptRecordAccount())
      }
    }

    @Test func accessibilitySizes() async throws {
      try await Snapshot.capture(
        "kit-worked-from-estimate-dark-ax3", size: Self.accessibility, typeSize: .accessibility3
      ) {
        Self.sheet(Self.estimateAccount())
      }
      try await Snapshot.capture(
        "kit-worked-from-muscle-dark-ax3", size: Self.accessibility, typeSize: .accessibility3
      ) {
        Self.sheet(Self.muscleAccount())
      }
    }
  }
#endif
