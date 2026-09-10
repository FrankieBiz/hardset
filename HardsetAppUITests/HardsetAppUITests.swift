import XCTest

/// User-visible coverage for the path that has to work with one hand in a gym.
///
/// The package suite proves the calculations and persistence rules. These tests prove the app a
/// lifter actually taps still exposes those paths after SwiftUI composition, navigation, and
/// accessibility have had their say.
final class HardsetAppUITests: XCTestCase {
  @MainActor
  private func makeApp() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments.append("--hardset-ui-testing")
    return app
  }

  @MainActor
  func testFirstLaunchMakesEveryPrimaryRouteObvious() {
    continueAfterFailure = false
    let app = makeApp()
    app.launch()

    XCTAssertTrue(app.staticTexts["No workout in progress"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["Start workout"].isHittable)
    XCTAssertTrue(app.buttons["Add a gym to track machines"].isHittable)
    XCTAssertTrue(app.buttons["Settings"].isHittable)

    for tab in ["Train", "Plan", "Volume", "History"] {
      XCTAssertTrue(app.buttons[tab].isHittable, "Missing primary tab: \(tab)")
    }
  }

  @MainActor
  func testEveryEmptyPrimaryScreenExplainsWhatComesNext() {
    continueAfterFailure = false
    let app = makeApp()
    app.launch()

    app.buttons["Plan"].tap()
    XCTAssertTrue(app.navigationBars["Plan"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.staticTexts["No plans yet"].exists)
    XCTAssertTrue(app.buttons["New plan"].isHittable)

    app.buttons["Volume"].tap()
    XCTAssertTrue(app.navigationBars["Volume"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.staticTexts["Nothing logged this week"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["How sets are counted"].isHittable)

    app.buttons["History"].tap()
    XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.staticTexts["No workouts yet"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["Browse progress"].isHittable)
  }

  @MainActor
  func testGymCanBeNamedAndSelectedBeforeTraining() {
    continueAfterFailure = false
    let app = makeApp()
    app.launch()

    let location = app.buttons["Add a gym to track machines"]
    XCTAssertTrue(location.waitForExistence(timeout: 5))
    location.tap()
    XCTAssertTrue(app.navigationBars["Where are you training?"].waitForExistence(timeout: 3))
    app.buttons["Add a gym"].tap()

    XCTAssertTrue(app.navigationBars["Add a gym"].waitForExistence(timeout: 3))
    let name = app.textFields["Name"]
    XCTAssertTrue(name.waitForExistence(timeout: 2))
    name.typeText("Iron Works")
    app.buttons["Add"].tap()

    XCTAssertTrue(app.buttons["Iron Works"].waitForExistence(timeout: 3))
    XCTAssertFalse(app.buttons["Add a gym to track machines"].exists)
  }

  @MainActor
  func testPlanCanBecomeTodaysWorkout() {
    continueAfterFailure = false
    let app = makeApp()
    app.launch()

    app.buttons["Plan"].tap()
    let newPlan = app.buttons["New plan"]
    XCTAssertTrue(newPlan.waitForExistence(timeout: 3))
    newPlan.tap()

    XCTAssertTrue(app.navigationBars["New plan"].waitForExistence(timeout: 3))
    let name = app.textFields["Plan name"]
    XCTAssertTrue(name.waitForExistence(timeout: 2))
    name.typeText("My week")
    app.buttons["Create"].tap()

    XCTAssertTrue(
      app.staticTexts["A plan is a reusable weekly structure for exercises you already train."]
        .waitForExistence(timeout: 3))
    let buildItMyself = app.buttons["Build it myself"]
    XCTAssertTrue(buildItMyself.waitForExistence(timeout: 2))
    buildItMyself.tap()

    let addMovement = app.buttons["Add movement"]
    XCTAssertTrue(addMovement.waitForExistence(timeout: 3))
    addMovement.tap()
    selectMovement(named: "Barbell Bench Press", in: app)

    let startDay = app.buttons["Start this day"]
    XCTAssertTrue(startDay.waitForExistence(timeout: 3))
    startDay.tap()
    let noTimer = app.buttons["No timer"]
    XCTAssertTrue(noTimer.waitForExistence(timeout: 3))
    noTimer.tap()

    XCTAssertTrue(app.navigationBars["Workout"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["Barbell Bench Press. Show load history."].exists)
    XCTAssertTrue(setRow(ordinal: 1, in: app).exists)
  }

  @MainActor
  func testSettingsAndBodyweightEntryWorkWithoutSetup() {
    continueAfterFailure = false
    let app = makeApp()
    app.launch()

    let settings = app.buttons["Settings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 5))
    settings.tap()
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.staticTexts["Units"].exists)
    XCTAssertTrue(app.staticTexts["Rest timer"].exists)
    XCTAssertTrue(app.switches["Record RPE"].exists)

    let bodyweight = app.buttons["Bodyweight"]
    XCTAssertTrue(bodyweight.exists)
    bodyweight.tap()
    XCTAssertTrue(app.navigationBars["Bodyweight"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.staticTexts["No readings yet"].waitForExistence(timeout: 3))
    app.buttons["Add a reading"].tap()

    XCTAssertTrue(app.navigationBars["Add a reading"].waitForExistence(timeout: 3))
    let weight = app.textFields.firstMatch
    XCTAssertTrue(weight.waitForExistence(timeout: 2))
    weight.typeText("185")
    app.buttons["Save"].tap()

    XCTAssertTrue(app.staticTexts["185"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.staticTexts["lb"].exists)
  }

  @MainActor
  func testPrimaryScreensPassTheSystemAccessibilityAudit() throws {
    continueAfterFailure = false
    let app = makeApp()
    app.launch()
    XCTAssertTrue(app.buttons["Start workout"].waitForExistence(timeout: 5))
    try auditCurrentScreen(in: app)

    app.buttons["Plan"].tap()
    XCTAssertTrue(app.staticTexts["No plans yet"].waitForExistence(timeout: 3))
    try auditCurrentScreen(in: app)

    app.buttons["Volume"].tap()
    XCTAssertTrue(app.staticTexts["Nothing logged this week"].waitForExistence(timeout: 3))
    try auditCurrentScreen(in: app)

    app.buttons["History"].tap()
    XCTAssertTrue(app.staticTexts["No workouts yet"].waitForExistence(timeout: 3))
    try auditCurrentScreen(in: app)

    app.buttons["Train"].tap()
    app.buttons["Settings"].tap()
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
    try auditCurrentScreen(in: app)
  }

  @MainActor
  private func auditCurrentScreen(in app: XCUIApplication) throws {
    try app.performAccessibilityAudit { issue in
      // Xcode 26.4 misclassifies this deliberately inverted button: its own failure attachment
      // shows #080A0E text on #F5F5F7 (18.1:1), while reporting "Contrast failed" for the node.
      // Keep the exception at the exact audit type and exact element; every other contrast,
      // clipping, hit-area, label, trait, and Dynamic Type finding still fails this test.
      if issue.auditType == .contrast, let element = issue.element,
        element.label == "Start workout"
      {
        let attachment = XCTAttachment(screenshot: element.screenshot())
        attachment.name = "Verified 18.1-to-1 inverted Start workout button"
        attachment.lifetime = .keepAlways
        self.add(attachment)
        return true
      }

      // Xcode 26.4 also reports system-owned navigation chrome as fixed-size. Giving either label
      // an explicit semantic font produces the same report because UINavigationBar and Form own
      // their rendering. Keep the native controls and scope the exceptions to their exact types,
      // labels, and audit category.
      if issue.auditType == .dynamicType
        && issue.element?.elementType == .button
        && issue.element?.label == "Done"
      {
        return true
      }
      if issue.auditType == .dynamicType
        && issue.element?.elementType == .staticText
        && issue.element?.label == "Bodyweight"
      {
        return true
      }
      return false
    }
  }

  @MainActor
  func testEmptyWorkoutCanBeStartedAndFinishedWithoutGuesswork() {
    continueAfterFailure = false
    let app = makeApp()
    app.launch()

    let start = app.buttons["Start workout"]
    XCTAssertTrue(start.waitForExistence(timeout: 5))
    start.tap()

    let noTimer = app.buttons["No timer"]
    XCTAssertTrue(noTimer.waitForExistence(timeout: 3))
    noTimer.tap()

    XCTAssertTrue(app.staticTexts["Nothing added yet"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["Add movement"].isHittable)
    XCTAssertTrue(app.buttons["Finish workout"].isHittable)

    finishWorkout(in: app)
    XCTAssertTrue(app.navigationBars["Summary"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["Done"].isHittable)
    app.buttons["Done"].tap()
    XCTAssertTrue(app.staticTexts["No workout in progress"].waitForExistence(timeout: 3))
  }

  @MainActor
  func testMovementCanBeFoundAndAddedDuringAWorkout() {
    continueAfterFailure = false
    let app = makeApp()
    app.launch()
    startEmptyWorkout(in: app)
    addMovement(named: "Barbell Bench Press", in: app)

    XCTAssertTrue(
      app.buttons["Barbell Bench Press. Show load history."].waitForExistence(timeout: 3))
    let firstSet = app.descendants(matching: .any).matching(
      NSPredicate(format: "label BEGINSWITH %@", "Set 1")
    ).firstMatch
    XCTAssertTrue(firstSet.exists)

    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "Workout after adding a movement"
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  @MainActor
  func testASetCanBeLoggedAndReadBackWithoutLeavingTheCriticalPath() {
    continueAfterFailure = false
    let app = makeApp()
    app.launch()
    startEmptyWorkout(in: app)
    addMovement(named: "Barbell Bench Press", in: app)

    var firstSet = setRow(ordinal: 1, in: app)
    XCTAssertTrue(firstSet.waitForExistence(timeout: 3))

    // The row is intentionally one accessibility element with field actions. Normal touch users
    // still hit the large visible fields, so exercise them by position within the row rather than
    // reaching through SwiftUI's private view hierarchy.
    firstSet.coordinate(withNormalizedOffset: CGVector(dx: 0.48, dy: 0.5)).tap()
    XCTAssertTrue(app.buttons["1"].waitForExistence(timeout: 2))
    app.buttons["1"].tap()
    app.buttons["0"].tap()
    app.buttons["0"].tap()
    app.buttons["Done"].tap()

    firstSet = setRow(ordinal: 1, in: app)
    firstSet.coordinate(withNormalizedOffset: CGVector(dx: 0.70, dy: 0.5)).tap()
    XCTAssertTrue(app.buttons["8"].waitForExistence(timeout: 2))
    app.buttons["8"].tap()
    app.buttons["Done"].tap()

    firstSet = setRow(ordinal: 1, in: app)
    XCTAssertTrue(firstSet.label.contains("100 lb"))
    XCTAssertTrue(firstSet.label.contains("8 reps"))
    firstSet.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
    XCTAssertTrue(app.staticTexts["1 of 1 logged"].waitForExistence(timeout: 3))

    finishWorkout(in: app)
    XCTAssertTrue(app.staticTexts["Workout complete"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.staticTexts["1"].exists)
    XCTAssertTrue(app.staticTexts["working set"].exists)
    app.buttons["Done"].tap()

    app.buttons["History"].tap()
    let savedWorkout = app.buttons.matching(
      NSPredicate(format: "label CONTAINS %@", "Barbell Bench Press")
    ).firstMatch
    XCTAssertTrue(savedWorkout.waitForExistence(timeout: 3))
    XCTAssertTrue(savedWorkout.label.contains("1 set"))
    XCTAssertTrue(savedWorkout.label.contains("8 reps"))

    savedWorkout.tap()
    let repeatWorkout = app.buttons["Do it again"]
    XCTAssertTrue(repeatWorkout.waitForExistence(timeout: 3))
    repeatWorkout.tap()
    XCTAssertTrue(app.navigationBars["Workout"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["Barbell Bench Press. Show load history."].exists)
    XCTAssertTrue(setRow(ordinal: 1, in: app).exists)
  }

  @MainActor
  func testColdLaunchBecomesInteractiveQuickly() {
    continueAfterFailure = false
    let app = makeApp()
    measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)]) {
      app.launch()
      XCTAssertTrue(app.buttons["Start workout"].waitForExistence(timeout: 5))
      app.terminate()
    }
  }

  @MainActor
  private func startEmptyWorkout(in app: XCUIApplication) {
    let start = app.buttons["Start workout"]
    XCTAssertTrue(start.waitForExistence(timeout: 5))
    start.tap()

    let noTimer = app.buttons["No timer"]
    XCTAssertTrue(noTimer.waitForExistence(timeout: 3))
    noTimer.tap()
    XCTAssertTrue(app.staticTexts["Nothing added yet"].waitForExistence(timeout: 3))
  }

  @MainActor
  private func addMovement(named name: String, in app: XCUIApplication) {
    app.buttons["Add movement"].tap()
    selectMovement(named: name, in: app)
    XCTAssertTrue(app.buttons["\(name). Show load history."].waitForExistence(timeout: 3))
  }

  @MainActor
  private func finishWorkout(in app: XCUIApplication) {
    app.buttons["Finish workout"].tap()

    let confirm = app.sheets.buttons["Finish workout"]
    XCTAssertTrue(confirm.waitForExistence(timeout: 3))
    XCTAssertTrue(confirm.isHittable)
    confirm.tap()
  }

  @MainActor
  private func selectMovement(named name: String, in app: XCUIApplication) {
    XCTAssertTrue(app.navigationBars["Add movement"].waitForExistence(timeout: 3))

    let search = app.searchFields.firstMatch
    XCTAssertTrue(search.waitForExistence(timeout: 3))
    search.tap()
    search.typeText(name)

    let result = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH %@", name)
    ).firstMatch
    XCTAssertTrue(result.waitForExistence(timeout: 3))
    result.tap()
  }

  @MainActor
  private func setRow(ordinal: Int, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(
      NSPredicate(format: "label BEGINSWITH %@", "Set \(ordinal)")
    ).firstMatch
  }
}
