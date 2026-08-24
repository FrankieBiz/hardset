import Foundation
import Testing

@testable import HardsetCore

@Suite("Volume counts fractionally and admits what it could not attribute")
struct MuscleVolumeTests {
  private func index(_ pairs: [(ExerciseID, [MuscleContribution])]) -> AttributionIndex {
    AttributionIndex(Dictionary(uniqueKeysWithValues: pairs))
  }

  private func contribution(
    _ muscle: Muscle, _ role: MuscleRole
  ) -> MuscleContribution {
    MuscleContribution(muscle, role: role, certainty: .moderate, source: .anatomy)
  }

  private func sets(_ exercise: ExerciseID, _ count: Int, warmup: Bool = false) -> [CountableSet] {
    (0..<count).map { _ in CountableSet(exerciseID: exercise, isWarmup: warmup) }
  }

  // MARK: - The arithmetic

  @Test("A direct set credits one, an indirect set credits a half")
  func fractionalCredit() {
    let bench = ExerciseID()
    let attribution = index([
      (bench, [
        contribution(.chest, .direct),
        contribution(.frontDelts, .indirect),
        contribution(.triceps, .indirect),
      ])
    ])
    let report = VolumeAnalyzer.report(sets: sets(bench, 4), attribution: attribution)

    #expect(report.hardSets == 4)
    #expect(report.sets(for: .chest) == 4.0)
    #expect(report.sets(for: .frontDelts) == 2.0)
    #expect(report.sets(for: .triceps) == 2.0)
    #expect(report.coverage == 1.0)
    #expect(!report.isLowerBound)
  }

  /// The defect the role split exists to prevent: grip and bracing must add nothing.
  @Test("A stabiliser credits nothing and does not appear at all")
  func stabiliserCreditsNothing() {
    let pullUp = ExerciseID()
    let attribution = index([
      (pullUp, [
        contribution(.lats, .direct),
        contribution(.biceps, .indirect),
        contribution(.forearms, .stabilizer),
      ])
    ])
    let report = VolumeAnalyzer.report(sets: sets(pullUp, 10), attribution: attribution)

    #expect(report.sets(for: .lats) == 10.0)
    #expect(report.sets(for: .biceps) == 5.0)
    #expect(report.sets(for: .forearms) == 0)
    // Absent, not present-at-zero: a zero entry would render as a trained muscle with no volume.
    #expect(report.fractionalSets[MuscleKey(.forearms)] == nil)
  }

  @Test("Warm-ups count nowhere, not even in hard sets")
  func warmupsAreExcluded() {
    let press = ExerciseID()
    let attribution = index([(press, [contribution(.chest, .direct)])])
    let all = sets(press, 3) + sets(press, 2, warmup: true)
    let report = VolumeAnalyzer.report(sets: all, attribution: attribution)

    #expect(report.hardSets == 3)
    #expect(report.sets(for: .chest) == 3.0)
  }

  @Test("An empty week reports zero and full coverage rather than dividing by zero")
  func emptyWeek() {
    let report = VolumeAnalyzer.report(sets: [], attribution: index([]))
    #expect(report.hardSets == 0)
    #expect(report.coverage == 1.0)
    #expect(!report.isLowerBound)
    #expect(report.fractionalSets.isEmpty)
  }

  // MARK: - Coverage, which is the honesty requirement

  /// The ancestor turned "I do not recognise this" into a confident score. Here it becomes a
  /// stated lower bound.
  @Test("An unattributed exercise makes every figure a lower bound")
  func unattributedMakesLowerBound() {
    let known = ExerciseID()
    let mystery = ExerciseID()
    let attribution = index([(known, [contribution(.chest, .direct)])])
    let report = VolumeAnalyzer.report(
      sets: sets(known, 6) + sets(mystery, 2), attribution: attribution
    )

    #expect(report.hardSets == 8)
    #expect(report.unattributedHardSets == 2)
    #expect(report.isLowerBound)
    #expect(abs(report.coverage - 0.75) < 1e-9)
    // The known work still counts; it is the total that is uncertain, not the chest figure.
    #expect(report.sets(for: .chest) == 6.0)
  }

  /// An exercise attributed to nothing is different from an exercise nobody attributed.
  @Test("A movement with an empty attribution is not the same as an unknown movement")
  func emptyAttributionIsNotUnknown() {
    let deliberatelyEmpty = ExerciseID()
    let attribution = index([(deliberatelyEmpty, [])])
    let report = VolumeAnalyzer.report(sets: sets(deliberatelyEmpty, 3), attribution: attribution)

    #expect(report.hardSets == 3)
    // Attribution exists and credits nothing, so nothing is unaccounted for.
    #expect(report.unattributedHardSets == 0)
    #expect(!report.isLowerBound)
  }

  @Test("A fully unattributed week reports zero coverage, not a plausible-looking total")
  func fullyUnattributed() {
    let mystery = ExerciseID()
    let report = VolumeAnalyzer.report(sets: sets(mystery, 12), attribution: index([]))
    #expect(report.hardSets == 12)
    #expect(report.unattributedHardSets == 12)
    #expect(report.coverage == 0)
    #expect(report.fractionalSets.isEmpty)
  }

  // MARK: - The group rule

  /// Summing fractional sets across a group double-counts every compound. A bench press credits
  /// chest, front delts and triceps; counted as a sum it would appear three times.
  @Test("Group figures count sets once, never sum the members")
  func groupsCountSetsOnce() {
    let bench = ExerciseID()
    let attribution = index([
      (bench, [
        contribution(.chest, .direct),
        contribution(.frontDelts, .indirect),
        contribution(.triceps, .indirect),
      ])
    ])
    let report = VolumeAnalyzer.report(sets: sets(bench, 4), attribution: attribution)

    // Four sets touched chest, four touched shoulders, four touched arms — not twelve anywhere.
    #expect(report.setsTouchingGroup[.chest] == 4)
    #expect(report.setsTouchingGroup[.shoulders] == 4)
    #expect(report.setsTouchingGroup[.arms] == 4)
    // And the sum of the fractional credits is deliberately larger than the set count.
    let credited = report.fractionalSets.values.reduce(0, +)
    #expect(credited == 8.0)
    #expect(report.hardSets == 4)
  }

  @Test("A set crediting two muscles in one group counts once for that group")
  func twoMusclesOneGroup() {
    let row = ExerciseID()
    let attribution = index([
      (row, [contribution(.upperBack, .direct), contribution(.lats, .indirect)])
    ])
    let report = VolumeAnalyzer.report(sets: sets(row, 5), attribution: attribution)
    #expect(report.setsTouchingGroup[.back] == 5)
    #expect(report.sets(for: .upperBack) == 5.0)
    #expect(report.sets(for: .lats) == 2.5)
  }

  // MARK: - Coverage gaps

  @Test("Untrained muscles are reported, and the exclusion set is honoured")
  func untrainedMuscles() {
    let bench = ExerciseID()
    let attribution = index([(bench, [contribution(.chest, .direct)])])
    let report = VolumeAnalyzer.report(sets: sets(bench, 3), attribution: attribution)

    let gaps = report.untrainedMuscles(excluding: ExerciseCatalog.unauthoredDirectTokens)
    #expect(!gaps.contains(.chest))
    #expect(gaps.contains(.hamstrings))

    // Every token now has a movement that trains it, so there is no content debt left to
    // suppress -- and `neck` is therefore a genuine gap in this user's week rather than a hole in
    // the catalogue. This assertion used to read `!gaps.contains(.neck)` for the opposite reason.
    #expect(ExerciseCatalog.unauthoredDirectTokens.isEmpty)
    #expect(gaps.contains(.neck))

    // The suppression mechanism is pinned separately, on an explicit set rather than on whatever
    // the catalogue happens to be missing. That is the behaviour worth protecting: a muscle the
    // app cannot offer an exercise for must never be presented as the user's failing. Testing it
    // this way also means growing the catalogue cannot break this test again.
    let suppressed = report.untrainedMuscles(excluding: [.neck, .obliques])
    #expect(!suppressed.contains(.neck))
    #expect(!suppressed.contains(.obliques))
    #expect(suppressed.contains(.hamstrings))
  }
}

@Suite("The app declines to invent a target or extrapolate a curve")
struct DoseResponseTests {
  /// The honest v1 position, and a finding rather than a placeholder: no per-muscle weekly set
  /// target is established for any muscle.
  @Test("No muscle has a weekly target")
  func noTargets() {
    for muscle in Muscle.allCases {
      let target = VolumeAnalyzer.weeklyTarget(for: muscle)
      #expect(!target.isEvaluated, "\(muscle.rawValue) claims a target")
      #expect(target.certainty == .unevaluated)
    }
  }

  @Test("Only the six measured sites get a dose-response position")
  func onlyModelledMusclesArePlaced() {
    for muscle in Muscle.allCases {
      let position = VolumeAnalyzer.doseResponse(fractionalSets: 12, for: muscle)
      if muscle.tier == .modelled {
        #expect(position.isEvaluated, "\(muscle.rawValue) is modelled but unevaluated")
        #expect(position.certainty == .moderate)
      } else {
        #expect(!position.isEvaluated, "\(muscle.rawValue) is counted but got a curve position")
        #expect(position.certainty == .unevaluated)
      }
    }
  }

  /// Above roughly 25 fractional sets the intervals widen enough that no per-set return may be
  /// asserted. Certainty drops rather than the number being hidden.
  @Test("Beyond the studied range, certainty drops and it is flagged")
  func beyondStudiedRange() {
    let inside = VolumeAnalyzer.doseResponse(fractionalSets: 20, for: .quadriceps)
    #expect(inside.certainty == .moderate)
    #expect(inside.value?.isBeyondStudiedRange == false)

    let outside = VolumeAnalyzer.doseResponse(fractionalSets: 30, for: .quadriceps)
    #expect(outside.certainty == .low)
    #expect(outside.value?.isBeyondStudiedRange == true)
  }

  @Test("The disclosure says the ~25 boundary is ours and the range is limited")
  func disclosureIsHonest() {
    let range = VolumeAnalyzer.doseResponseSource.validRange ?? ""
    #expect(range.contains("unevaluated, not approximate"))
    #expect(range.contains("Hardset's chosen cut point"))
    #expect(VolumeAnalyzer.targetSource.methodology.contains("does not publish a weekly set target"))
  }
}

@Suite("The real catalogue produces sane volume")
struct CatalogVolumeTests {
  /// An end-to-end check against the shipped attribution rather than a fixture, so a bad edit to
  /// the catalogue shows up as absurd volume here.
  @Test("A push/pull/legs week credits every major muscle plausibly")
  func realisticWeek() throws {
    let entries = ExerciseCatalog.v1.compactMap(\.catalogEntry)
    let attribution = AttributionIndex(entries: entries)
    func id(_ slug: String) throws -> ExerciseID {
      try #require(entries.first { $0.slug == slug }?.id)
    }

    var week: [CountableSet] = []
    for slug in ["barbell-bench-press", "incline-dumbbell-press", "cable-triceps-pushdown"] {
      week += (0..<3).map { _ in CountableSet(exerciseID: try! id(slug), isWarmup: false) }
    }
    for slug in ["pull-up", "seated-cable-row", "barbell-curl"] {
      week += (0..<3).map { _ in CountableSet(exerciseID: try! id(slug), isWarmup: false) }
    }
    for slug in ["barbell-back-squat", "romanian-deadlift", "standing-calf-raise"] {
      week += (0..<3).map { _ in CountableSet(exerciseID: try! id(slug), isWarmup: false) }
    }

    let report = VolumeAnalyzer.report(sets: week, attribution: attribution)
    #expect(report.hardSets == 27)
    #expect(report.coverage == 1.0)

    // Chest: 3 direct + 3 direct = 6.
    #expect(report.sets(for: .chest) == 6.0)
    // Triceps: 3 direct pushdown + 1.5 + 1.5 indirect from the two presses = 6.
    #expect(report.sets(for: .triceps) == 6.0)
    // Quads: 3 direct from squats.
    #expect(report.sets(for: .quadriceps) == 3.0)
    // Grip is held on pull-ups and curls and credits nothing.
    #expect(report.sets(for: .forearms) == 0)
    // Bracing on squats credits nothing either.
    #expect(report.sets(for: .abs) == 0)

    // Nothing exceeds the number of sets performed for it — the sanity check that would catch a
    // duplicated contribution.
    for (key, credited) in report.fractionalSets {
      #expect(credited <= Double(report.hardSets), "\(key.storedValue) credited \(credited)")
    }
  }

  /// "Credited nothing" is not the same claim as "not trained".
  ///
  /// When nothing could be attributed, every muscle has zero credited sets -- so the gap list
  /// returned all of them, and the report read as "you trained nothing this week" when the truth was
  /// "the app could not tell what you trained". The engine still answers the question it was asked;
  /// what it must also expose is that the answer is unsafe to present as a gap.
  @Test("A week of unattributed work is a coverage failure, not an empty week")
  func unattributedWeekIsNotAnEmptyWeek() {
    let report = MuscleVolumeReport(
      fractionalSets: [:],
      hardSets: 12,
      unattributedHardSets: 12,
      setsTouchingGroup: [:]
    )

    // The gap list is technically correct and completely misleading on its own.
    #expect(report.untrainedMuscles(excluding: []).count == Muscle.allCases.count)
    // These are what a caller has to check before presenting it as a gap.
    #expect(report.coverage == 0)
    #expect(report.isLowerBound)
    #expect(report.unattributedHardSets == 12)
  }

  /// Partial attribution: the gaps are real but overstated, and the caller has to say so.
  @Test("Partly unattributed work makes the gap list a maximum")
  func partialAttributionMakesGapsAMaximum() {
    let report = MuscleVolumeReport(
      fractionalSets: [MuscleKey(.chest): 6],
      hardSets: 10,
      unattributedHardSets: 4,
      setsTouchingGroup: [:]
    )

    #expect(report.isLowerBound)
    #expect(abs(report.coverage - 0.6) < 1e-9)
    let gaps = report.untrainedMuscles(excluding: [])
    #expect(!gaps.contains(.chest))
    // Every other muscle is listed, though four sets of unknown work might have hit some of them.
    #expect(gaps.contains(.hamstrings))
  }

  /// The safe case, where a gap really is a gap.
  @Test("A fully attributed week states its gaps without qualification")
  func fullyAttributedWeekIsCertain() {
    let report = MuscleVolumeReport(
      fractionalSets: [MuscleKey(.chest): 6],
      hardSets: 6,
      unattributedHardSets: 0,
      setsTouchingGroup: [:]
    )
    #expect(!report.isLowerBound)
    #expect(report.coverage == 1)
    #expect(report.untrainedMuscles(excluding: []).contains(.hamstrings))
  }
}
