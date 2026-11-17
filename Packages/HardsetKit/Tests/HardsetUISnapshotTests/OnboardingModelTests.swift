import Foundation
import GRDB
import HardsetCore
import HardsetFeature
import HardsetStore
import Testing

/// The first-launch sequence as state: where "Next" and "Skip" lead, what the tour's interactive
/// step holds back, and what Setup offers and saves for a fresh install and for one that already
/// has gyms. No pager and no view is involved, which is the point of keeping this a model.
@MainActor
@Suite("Onboarding model")
struct OnboardingModelTests {
  /// A migrated in-memory database with nothing in it: a fresh install's store.
  private static func freshGyms() throws -> GymStore {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return GymStore(database: queue)
  }

  // MARK: - Pages

  @Test func nextWalksWelcomeThroughThePitchesToTheTour() throws {
    let model = OnboardingModel(gyms: try Self.freshGyms())
    #expect(model.page == .welcome)

    model.next()
    #expect(model.page == .pitchSetRow)
    model.next()
    #expect(model.page == .pitchEstimate)
    model.next()
    #expect(model.page == .pitchRest)
    model.next()
    #expect(model.page == .tour)
  }

  @Test func welcomeHasNoSkipAndTheRestDo() throws {
    let model = OnboardingModel(gyms: try Self.freshGyms())
    #expect(!model.canSkip)
    model.skip()
    #expect(model.page == .welcome, "skip does nothing on the welcome page")

    for page in [OnboardingModel.Page.pitchSetRow, .pitchEstimate, .pitchRest, .tour] {
      model.page = page
      #expect(model.canSkip, "\(page)")
    }
    model.page = .setup
    #expect(!model.canSkip, "Setup is where skip leads, so it has none")
  }

  @Test func skipLandsOnSetupFromEveryPageButWelcome() throws {
    for page in [OnboardingModel.Page.pitchSetRow, .pitchEstimate, .pitchRest, .tour] {
      let model = OnboardingModel(gyms: try Self.freshGyms(), startingPage: page)
      model.skip()
      #expect(model.page == .setup, "\(page)")
    }
  }

  @Test func aFirstLaunchHoldsEveryPageAndAReplayDropsSetup() throws {
    let first = OnboardingModel(gyms: try Self.freshGyms())
    #expect(first.pages == OnboardingModel.Page.allCases)

    let replay = OnboardingModel(gyms: try Self.freshGyms(), mode: .replay)
    #expect(!replay.pages.contains(.setup))
    #expect(replay.pages.count == OnboardingModel.Page.allCases.count - 1)
  }

  // MARK: - Tour

  @Test func theTourHasEightSteps() {
    #expect(OnboardingModel.tourStepCount == 8)
    #expect(OnboardingModel.TourStep.allCases.map(\.number) == Array(1...8))
  }

  @Test func theSetStepHoldsNextBackUntilTheCheckIsTapped() throws {
    let model = OnboardingModel(gyms: try Self.freshGyms(), startingPage: .tour)
    #expect(model.tourStep == .train)
    #expect(model.canAdvanceTour)

    model.next()
    #expect(model.tourStep == .logSet)
    #expect(!model.canAdvanceTour, "Next stays hidden until the lifter taps the check")
    model.next()
    #expect(model.tourStep == .logSet, "and a stray Next does nothing")

    model.didLogTourSet()
    #expect(model.canAdvanceTour)
    model.next()
    #expect(model.tourStep == .keypad)
  }

  @Test func everyOtherStepMayBeLeftAtOnce() throws {
    let model = OnboardingModel(gyms: try Self.freshGyms(), startingPage: .tour)
    model.didLogTourSet()
    var seen: [OnboardingModel.TourStep] = [model.tourStep]
    while model.page == .tour {
      model.next()
      if model.page == .tour { seen.append(model.tourStep) }
    }
    #expect(seen == OnboardingModel.TourStep.allCases)
  }

  @Test func theLastTourStepLeadsToSetupOnAFirstLaunchAndEndsAReplay() throws {
    let first = OnboardingModel(gyms: try Self.freshGyms(), startingPage: .tour)
    first.didLogTourSet()
    for _ in 0..<OnboardingModel.tourStepCount { first.next() }
    #expect(first.page == .setup)
    #expect(!first.isReplayFinished)

    let replay = OnboardingModel(gyms: try Self.freshGyms(), mode: .replay, startingPage: .tour)
    replay.didLogTourSet()
    for _ in 0..<OnboardingModel.tourStepCount { replay.next() }
    #expect(replay.isReplayFinished)
    #expect(replay.page == .tour, "a replay never reaches Setup")
  }

  @Test func skippingAReplayEndsItAndLeavesThePageAlone() throws {
    let replay = OnboardingModel(gyms: try Self.freshGyms(), mode: .replay, startingPage: .pitchEstimate)
    replay.skip()
    #expect(replay.isReplayFinished)
  }

  // MARK: - Setup on a fresh install

  @Test func aFreshInstallOffersNoGymsAndSavesATypedName() throws {
    let gyms = try Self.freshGyms()
    let model = OnboardingModel(gyms: gyms, startingPage: .setup)
    model.loadSetup()
    #expect(model.existingGyms.isEmpty)
    #expect(model.selectedGymID == nil)

    model.gymName = "  Downtown Barbell  "
    #expect(model.completeSetup())
    #expect(model.setupError == nil)

    let saved = try gyms.gyms()
    #expect(saved.map(\.name) == ["Downtown Barbell"])
    #expect(model.chosenGymID == saved.first?.id)
  }

  @Test func aBlankGymNameIsFineAndSavesNothing() throws {
    let gyms = try Self.freshGyms()
    let model = OnboardingModel(gyms: gyms, startingPage: .setup)
    model.loadSetup()

    model.gymName = "   "
    #expect(model.completeSetup())
    #expect(model.chosenGymID == nil)
    #expect(try gyms.gyms().isEmpty)
  }

  // MARK: - Setup on an existing install

  @Test func anExistingInstallListsItsGymsAndPreselectsOneAndCreatesNoDuplicate() throws {
    let staged = try TourFixtures.make(stage: .start, now: Date(timeIntervalSince1970: 1_793_000_000))
    let gyms = staged.environment.gyms
    let model = OnboardingModel(gyms: gyms, startingPage: .setup)
    model.loadSetup()

    #expect(model.existingGyms.map(\.name) == [TourFixtures.gymName])
    #expect(model.selectedGymID == staged.gymID, "the only gym is preselected")

    // A typed name is ignored when gyms exist: the lifter picks among them.
    model.gymName = "Another gym"
    #expect(model.completeSetup())
    #expect(model.chosenGymID == staged.gymID)
    #expect(try gyms.gyms().map(\.name) == [TourFixtures.gymName], "nothing was created")
  }

  @Test func aSavedChoiceThatIsNoLongerOfferedFallsBackToTheLastUsedGym() throws {
    let staged = try TourFixtures.make(stage: .start, now: Date(timeIntervalSince1970: 1_793_000_000))
    let model = OnboardingModel(gyms: staged.environment.gyms, startingPage: .setup)
    model.selectedGymID = GymID()
    model.loadSetup()
    #expect(model.selectedGymID == staged.gymID)
  }

  @Test func aGymThatCannotBeSavedKeepsSetupOpenWithTheNameKept() throws {
    // A store whose gym table is gone, so every read and write of a gym fails.
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    try queue.writeWithoutTransaction { db in
      try db.execute(sql: "PRAGMA foreign_keys = OFF")
      try db.execute(sql: "DROP TABLE gyms")
    }
    let model = OnboardingModel(gyms: GymStore(database: queue), startingPage: .setup)

    model.loadSetup()
    #expect(model.existingGyms.isEmpty)
    #expect(model.setupError == "Your gyms could not be read. You can add one later in Settings.")

    model.gymName = "Downtown"
    #expect(!model.completeSetup(), "Setup stays open")
    #expect(model.setupError == "“Downtown” could not be saved. Try again.")
    #expect(model.gymName == "Downtown", "the typed name is still there for another try")
    #expect(model.chosenGymID == nil)
  }
}
