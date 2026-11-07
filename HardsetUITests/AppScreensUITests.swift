import XCTest

/// Drives the real app on the simulator, screen by screen.
///
/// The package's snapshot suite renders views without an app host, so it cannot draw what the
/// system composites: Liquid Glass in the tab bar and the workout accessory, sheet toolbars, the
/// keyboard. This suite launches the actual app and walks the journey a lifter takes -- add a gym,
/// start a workout, add a movement, type a set on the keypad, log it, finish -- saving a screenshot
/// of each screen and running Apple's accessibility audit on it.
///
/// Audit issues are recorded rather than failing the run, so one finding cannot hide the screens
/// after it; the report is written next to the screenshots. With `HARDSET_UI_SHOT_DIR` set (CI
/// passes it through `TEST_RUNNER_`), screenshots and the report land in that directory.
final class AppScreensUITests: XCTestCase {
  private var auditReport: [String] = []

  /// The whole journey, in dark mode, starting from a fresh install.
  func testJourneyInDarkMode() throws {
    // Set here rather than in an overridden setUp, whose isolation would have to match XCTest's.
    continueAfterFailure = true
    XCUIDevice.shared.appearance = .dark
    let app = XCUIApplication()
    app.launch()

    guard waitForStartScreen(app) else { return }
    capture(app, "01-start-empty")
    audit(app, screen: "start")

    // Settings, over the start screen: the sheet's toolbar is system glass.
    app.buttons["Settings"].tap()
    XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
    capture(app, "02-settings")
    audit(app, screen: "settings")
    app.buttons["Done"].tap()

    // The other two tabs, empty.
    openTab(app, "Volume")
    capture(app, "03-volume-empty")
    audit(app, screen: "volume")
    openTab(app, "History")
    capture(app, "04-history-empty")
    audit(app, screen: "history")
    openTab(app, "Train")

    // A gym, added from the start screen's card.
    app.buttons["Add a gym to track machines"].tap()
    XCTAssertTrue(app.buttons["Add a gym"].waitForExistence(timeout: 5))
    capture(app, "05-gym-picker")
    audit(app, screen: "gym picker")
    app.buttons["Add a gym"].tap()
    let name = app.textFields.firstMatch
    XCTAssertTrue(name.waitForExistence(timeout: 5))
    capture(app, "06-name-entry")
    name.typeText("Metroflex Gym")
    app.buttons["Add"].tap()
    XCTAssertTrue(app.buttons["Start workout"].waitForExistence(timeout: 5))
    capture(app, "07-start-with-gym")

    // A workout: empty, then with a movement.
    app.buttons["Start workout"].tap()
    let addMovement = app.buttons["Add movement"]
    XCTAssertTrue(addMovement.waitForExistence(timeout: 5))
    capture(app, "08-session-empty")
    audit(app, screen: "empty session")
    addMovement.tap()
    let bench = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Barbell Bench Press'"))
      .firstMatch
    XCTAssertTrue(bench.waitForExistence(timeout: 5))
    capture(app, "09-movement-picker")
    audit(app, screen: "movement picker")
    bench.tap()

    // A set, typed on the keypad. The row is one accessibility element, so its fields are reached
    // by position: weight sits at about 44% of the row's width, the log control at the end.
    let row = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label BEGINSWITH 'Set 1'")).firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 5))
    capture(app, "10-session-movement")
    audit(app, screen: "session with a movement")
    row.coordinate(withNormalizedOffset: CGVector(dx: 0.44, dy: 0.5)).tap()
    XCTAssertTrue(app.buttons["Next field"].waitForExistence(timeout: 5))
    for key in ["1", "0", "0"] { app.buttons[key].tap() }
    capture(app, "11-keypad-weight")
    audit(app, screen: "keypad")
    app.buttons["Next field"].tap()
    app.buttons["8"].tap()
    app.buttons["Done"].tap()
    row.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
    capture(app, "12-session-logged")

    // Finish, which asks once, then the start screen and history with the workout in them.
    let finish = app.buttons["Finish workout"]
    if finish.waitForExistence(timeout: 5) {
      finish.tap()
      capture(app, "13-finish-confirm")
      app.buttons["Finish"].tap()
    }
    XCTAssertTrue(app.buttons["Start workout"].waitForExistence(timeout: 5))
    capture(app, "14-start-last-workout")
    openTab(app, "History")
    capture(app, "15-history")
    audit(app, screen: "history with a workout")
    openTab(app, "Volume")
    capture(app, "16-volume")
    audit(app, screen: "volume with a workout")

    writeAuditReport(named: "accessibility-audit-dark")
  }

  /// The main screens again in light mode, over whatever the dark journey left behind.
  func testScreensInLightMode() throws {
    continueAfterFailure = true
    XCUIDevice.shared.appearance = .light
    let app = XCUIApplication()
    app.launch()

    guard waitForStartScreen(app) else { return }
    capture(app, "21-light-start")
    audit(app, screen: "light start")
    openTab(app, "Volume")
    capture(app, "22-light-volume")
    openTab(app, "History")
    capture(app, "23-light-history")
    openTab(app, "Train")
    app.buttons["Settings"].tap()
    if app.buttons["Done"].waitForExistence(timeout: 5) {
      capture(app, "24-light-settings")
      app.buttons["Done"].tap()
    }

    writeAuditReport(named: "accessibility-audit-light")
  }

  // MARK: - Helpers

  /// Waits for the start screen, and when it does not come, says what is showing instead.
  private func waitForStartScreen(_ app: XCUIApplication) -> Bool {
    if app.buttons["Start workout"].waitForExistence(timeout: 30) { return true }
    capture(app, "00-launch-did-not-reach-start")
    XCTFail(
      "The start screen did not appear within 30 seconds. If the startup failure screen is "
        + "showing, the simulator build could not create the database or the sync engine."
    )
    return false
  }

  private func openTab(_ app: XCUIApplication, _ title: String) {
    let tab = app.tabBars.buttons[title].firstMatch
    if tab.waitForExistence(timeout: 5) {
      tab.tap()
    } else {
      app.buttons[title].firstMatch.tap()
    }
  }

  private func capture(_ app: XCUIApplication, _ name: String) {
    // Let presentation and scroll-edge transitions settle before the frame is taken.
    Thread.sleep(forTimeInterval: 0.8)
    let screenshot = XCUIScreen.main.screenshot()
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
    if let directory = Self.outputDirectory {
      try? screenshot.pngRepresentation.write(to: directory.appendingPathComponent("\(name).png"))
    }
  }

  /// Apple's accessibility audit on whatever is on screen: hit regions, contrast, clipped text,
  /// Dynamic Type, element descriptions and traits. Every issue is recorded and the run goes on.
  private func audit(_ app: XCUIApplication, screen: String) {
    do {
      try app.performAccessibilityAudit { [weak self] issue in
        let element = issue.element
        let label = element?.label ?? "no element"
        let frame = element.map { "\($0.frame)" } ?? "no frame"
        self?.auditReport.append(
          "[\(screen)] \(issue.compactDescription) | \(label) | \(frame) | \(issue.detailedDescription)"
        )
        return true
      }
    } catch {
      auditReport.append("[\(screen)] audit could not run: \(error)")
    }
  }

  private func writeAuditReport(named name: String) {
    let text =
      auditReport.isEmpty
      ? "No accessibility audit issues.\n" : auditReport.joined(separator: "\n") + "\n"
    let attachment = XCTAttachment(string: text)
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
    if let directory = Self.outputDirectory {
      try? text.write(
        to: directory.appendingPathComponent("\(name).txt"), atomically: true, encoding: .utf8)
    }
  }

  private static var outputDirectory: URL? {
    guard let path = ProcessInfo.processInfo.environment["HARDSET_UI_SHOT_DIR"], !path.isEmpty
    else { return nil }
    let url = URL(fileURLWithPath: path, isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}
