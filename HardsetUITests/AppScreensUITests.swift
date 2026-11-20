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
///
/// Every journey launches the app with an empty store (`HARDSET_STORE=reset`) and checks that it
/// got one, so none depends on what another left behind and they pass in any order. A journey that
/// needs data makes it through the real screens first.
final class AppScreensUITests: XCTestCase {
  private var auditReport: [String] = []

  /// The start screen, Settings and the two other tabs, in dark mode.
  @MainActor
  func testStartAndTabsDark() throws {
    continueAfterFailure = true
    let app = XCUIApplication()
    launch(app)

    guard waitForStartScreen(app) else { return }
    capture(app, "01-start")
    audit(app, screen: "start")

    // Settings, over the start screen: the sheet's toolbar is system glass.
    app.buttons["Settings"].tap()
    XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
    capture(app, "02-settings")
    audit(app, screen: "settings")
    // A build signed without iCloud opens local-only and says so here, rather than stranding the
    // lifter on the startup failure screen. CI's build carries no iCloud container, as a
    // personal-team device build does not, so reaching this line is that regression check.
    let syncStatus = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label CONTAINS 'Saved on this iPhone only'")).firstMatch
    XCTAssertTrue(syncStatus.waitForExistence(timeout: 5))
    app.swipeUp()
    capture(app, "02b-settings-data")
    app.buttons["Done"].tap()

    openTab(app, "Volume")
    capture(app, "03-volume")
    audit(app, screen: "volume")
    openTab(app, "History")
    capture(app, "04-history")
    audit(app, screen: "history")

    writeAuditReport(named: "accessibility-audit-start-and-tabs")
  }

  /// A workout from start to finish, without choosing a gym first: start, add a movement, type a
  /// set on the keypad, log it, finish, and see it on the start screen and in history.
  @MainActor
  func testWorkoutJourneyDark() throws {
    continueAfterFailure = true
    let app = XCUIApplication()
    launch(app)

    guard waitForStartScreen(app) else { return }
    app.buttons["Start workout"].tap()
    let addMovement = app.buttons["Add movement"]
    XCTAssertTrue(addMovement.waitForExistence(timeout: 5))
    capture(app, "10-session-empty")
    audit(app, screen: "empty session")
    addMovement.tap()
    let bench = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Barbell Bench Press'"))
      .firstMatch
    XCTAssertTrue(bench.waitForExistence(timeout: 5))
    capture(app, "11-movement-picker")
    // The first audit is of the picker as the lifter meets it, keyboard up. Rows behind the keyboard
    // were reported for contrast measured on the keyboard's pixels, not their own, so the audit that
    // judges the picker is the second, with the keyboard down and every row in view.
    audit(app, screen: "movement picker (keyboard up)")
    dismissKeyboard(app)
    capture(app, "11b-movement-picker-keyboard-down")
    audit(app, screen: "movement picker")
    bench.tap()

    // A set, typed on the keypad. The row is one accessibility element, so its fields are reached
    // by position: weight sits at about 44% of the row's width, the log control at the end.
    let row = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label BEGINSWITH 'Set 1'")).firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 5))
    capture(app, "12-session-movement")
    audit(app, screen: "session with a movement")
    row.coordinate(withNormalizedOffset: CGVector(dx: 0.44, dy: 0.5)).tap()
    XCTAssertTrue(app.buttons["Next field"].waitForExistence(timeout: 5))
    for key in ["1", "0", "0"] { app.buttons[key].tap() }
    capture(app, "13-keypad-weight")
    audit(app, screen: "keypad")
    app.buttons["Next field"].tap()
    // The same keypad, retargeted: its display now names reps.
    let repsDisplay = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label BEGINSWITH 'Reps'")).firstMatch
    XCTAssertTrue(repsDisplay.waitForExistence(timeout: 3))
    app.buttons["8"].tap()
    capture(app, "13b-keypad-reps")
    app.buttons["Done"].tap()
    row.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
    let loggedRow = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label BEGINSWITH 'Set 1,' AND label CONTAINS ', logged'"))
      .firstMatch
    XCTAssertTrue(loggedRow.waitForExistence(timeout: 5), "The entered set must actually be saved.")
    let savedLabel = loggedRow.label
    XCTAssertTrue(savedLabel.contains("100 "), "The saved load must match the keypad entry.")
    XCTAssertTrue(savedLabel.contains(", 8 reps"), "The saved reps must match the keypad entry.")
    capture(app, "14-session-logged")

    // Recovery must read the committed set from disk, with its values and logged state intact.
    // Relaunching a real app exercises the startup and view wiring that Store tests cannot.
    app.terminate()
    launch(app, keepsStore: true)
    let recoveredRows = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label == %@", savedLabel))
    XCTAssertTrue(recoveredRows.firstMatch.waitForExistence(timeout: 30))
    XCTAssertEqual(recoveredRows.count, 1, "Relaunch must recover exactly one copy of the saved set.")
    XCTAssertFalse(app.buttons["Start workout"].exists, "A live workout must resume before offering a new one.")
    capture(app, "14b-session-resumed")

    // Finish asks once, then the workout is on the start screen and in history.
    let finish = app.buttons["Finish workout"]
    if finish.waitForExistence(timeout: 5) {
      finish.tap()
      // No manual scroll: the expanded confirmation brings itself into view above the tab bar.
      // An earlier build needed a swipe here, which hid that its buttons opened off screen.
      XCTAssertTrue(app.buttons["Finish"].waitForExistence(timeout: 5))
      capture(app, "15-finish-confirm")
      app.buttons["Finish"].tap()
    }
    XCTAssertTrue(app.buttons["Start workout"].waitForExistence(timeout: 5))
    // Finishing opens the workout's receipt over the start screen, by design, and it stays up until
    // it is closed. This journey never closed it, so the pictures and audits below that are named for
    // the start screen, History and Volume were all of the receipt (main's own 17-history-with-workout
    // and 18-volume-with-workout show it). It is audited here for what it is, then closed, so that
    // what follows is those screens.
    let receiptDone = app.buttons["Done"]
    XCTAssertTrue(receiptDone.waitForExistence(timeout: 10), "Finishing a workout opens its receipt")
    capture(app, "15b-workout-receipt")
    audit(app, screen: "workout receipt")
    receiptDone.tap()
    XCTAssertTrue(waitUntilGone(receiptDone), "Done closes the receipt")
    capture(app, "16-start-last-workout")
    openTab(app, "History")
    capture(app, "17-history-with-workout")
    audit(app, screen: "history with a workout")
    openTab(app, "Volume")
    capture(app, "18-volume-with-workout")
    audit(app, screen: "volume with a workout")
    // The first audit saw the top of the list. The muscle rows below it were reported as sitting
    // behind the map button and the tab bar, so the list is audited again scrolled to them.
    app.swipeUp()
    capture(app, "18b-volume-with-workout-scrolled")
    audit(app, screen: "volume with a workout, scrolled")

    writeAuditReport(named: "accessibility-audit-workout")
  }

  /// Mistakes are reversible: a logged set is undone from its long-press menu, a movement is
  /// removed from its card menu, and an accidental workout is discarded from the header menu,
  /// leaving nothing in History.
  @MainActor
  func testCorrectionsAndDiscardDark() throws {
    continueAfterFailure = true
    let app = XCUIApplication()
    launch(app)

    guard waitForStartScreen(app) else { return }
    app.buttons["Start workout"].tap()
    let addMovement = app.buttons["Add movement"]
    XCTAssertTrue(addMovement.waitForExistence(timeout: 5))
    addMovement.tap()
    let bench = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Barbell Bench Press'"))
      .firstMatch
    XCTAssertTrue(bench.waitForExistence(timeout: 5))
    bench.tap()

    // Log one set, as the journey does.
    let row = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label BEGINSWITH 'Set 1'")).firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 5))
    row.coordinate(withNormalizedOffset: CGVector(dx: 0.44, dy: 0.5)).tap()
    XCTAssertTrue(app.buttons["Next field"].waitForExistence(timeout: 5))
    for key in ["6", "0"] { app.buttons[key].tap() }
    app.buttons["Next field"].tap()
    app.buttons["5"].tap()
    app.buttons["Done"].tap()
    row.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
    capture(app, "40-correction-logged")

    // Undo it from the row's long-press menu.
    row.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).press(forDuration: 1.2)
    let undo = app.buttons["Undo log"]
    XCTAssertTrue(undo.waitForExistence(timeout: 5))
    capture(app, "41-set-corrections-menu")
    audit(app, screen: "set corrections menu")
    undo.tap()
    capture(app, "42-set-undone")

    // Remove the movement from its card menu. With nothing logged it goes without a question.
    let movementMenu = app.buttons["Barbell Bench Press options"]
    XCTAssertTrue(movementMenu.waitForExistence(timeout: 5))
    movementMenu.tap()
    let remove = app.buttons["Remove movement"]
    XCTAssertTrue(remove.waitForExistence(timeout: 5))
    capture(app, "43-movement-menu")
    remove.tap()
    XCTAssertTrue(addMovement.waitForExistence(timeout: 5))
    XCTAssertFalse(row.waitForExistence(timeout: 2))
    capture(app, "44-movement-removed")

    // Discard the workout from the header menu, confirmed.
    let workoutMenu = app.buttons["Workout options"]
    XCTAssertTrue(workoutMenu.waitForExistence(timeout: 5))
    workoutMenu.tap()
    capture(app, "45-workout-menu")
    app.buttons["Discard workout"].firstMatch.tap()
    let confirm = app.buttons.matching(NSPredicate(format: "label == 'Discard workout'")).firstMatch
    XCTAssertTrue(confirm.waitForExistence(timeout: 5))
    capture(app, "46-discard-confirm")
    confirm.tap()
    XCTAssertTrue(app.buttons["Start workout"].waitForExistence(timeout: 5))
    capture(app, "47-start-after-discard")
    openTab(app, "History")
    capture(app, "48-history-after-discard")

    writeAuditReport(named: "accessibility-audit-corrections")
  }

  /// The gym picker and adding a gym, on their own: the first runs saw the app exit as this sheet
  /// presented, and a separate test keeps that from hiding every screen after it.
  @MainActor
  func testGymPickerDark() throws {
    continueAfterFailure = true
    let app = XCUIApplication()
    launch(app)

    guard waitForStartScreen(app) else { return }
    let card = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'gym'")).firstMatch
    XCTAssertTrue(card.waitForExistence(timeout: 5))
    card.tap()
    let addGym = app.buttons["Add a gym"]
    XCTAssertTrue(addGym.waitForExistence(timeout: 10))
    capture(app, "20-gym-picker")
    audit(app, screen: "gym picker")
    addGym.tap()
    let name = app.textFields.firstMatch
    XCTAssertTrue(name.waitForExistence(timeout: 5))
    capture(app, "21-name-entry")
    name.typeText("Metroflex Gym")
    app.buttons["Add"].tap()
    XCTAssertTrue(app.buttons["Start workout"].waitForExistence(timeout: 5))
    capture(app, "22-start-with-gym")

    writeAuditReport(named: "accessibility-audit-gym")
  }

  /// Every sheet the live workout opens, one after another from the same screen: the gym picker
  /// (with the gym added from inside it), the machine picker (with a machine added from inside it,
  /// then its load step) and a movement's load history. They share one presentation, so each must
  /// open, show its own content and close back to the workout, with the one before it gone.
  @MainActor
  func testSessionSheetsDark() throws {
    continueAfterFailure = true
    let app = XCUIApplication()
    launch(app)

    guard waitForStartScreen(app) else { return }
    app.buttons["Start workout"].tap()
    let addMovement = app.buttons["Add movement"]
    XCTAssertTrue(addMovement.waitForExistence(timeout: 5))

    // The workout's gym, from the header chip, with the add-gym sheet nested inside the picker.
    let setGym = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Set gym'")).firstMatch
    XCTAssertTrue(setGym.waitForExistence(timeout: 5), "A workout with no gym offers to set one")
    setGym.tap()
    let addGym = app.buttons["Add a gym"]
    XCTAssertTrue(addGym.waitForExistence(timeout: 10), "The workout's gym picker opens")
    capture(app, "80-session-gym-picker")
    addGym.tap()
    let gymName = app.textFields.firstMatch
    XCTAssertTrue(gymName.waitForExistence(timeout: 5), "Add a gym opens its name sheet over the picker")
    gymName.typeText("Journey Gym")
    app.buttons["Add"].tap()
    let gymChip = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Journey Gym'")).firstMatch
    XCTAssertTrue(gymChip.waitForExistence(timeout: 10), "The new gym is set and both sheets close")
    XCTAssertTrue(waitUntilGone(addGym), "The gym picker closed with the name sheet")

    // The movement picker, then a movement with a gym set, so its card offers a machine.
    addMovement.tap()
    let bench = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Barbell Bench Press'"))
      .firstMatch
    XCTAssertTrue(bench.waitForExistence(timeout: 5))
    bench.tap()

    // The machine picker, with a machine named from inside it and chosen at once.
    let chooseMachine = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Choose machine'"))
      .firstMatch
    XCTAssertTrue(chooseMachine.waitForExistence(timeout: 10), "With a gym set, the card offers a machine")
    chooseMachine.tap()
    let addMachine = app.buttons["Add a machine"]
    XCTAssertTrue(addMachine.waitForExistence(timeout: 10), "The machine picker opens")
    capture(app, "81-session-machine-picker")
    addMachine.tap()
    let machineName = app.textFields.firstMatch
    XCTAssertTrue(machineName.waitForExistence(timeout: 5), "Add a machine opens its name sheet over the picker")
    machineName.typeText("Hammer Strength")
    app.buttons["Add"].tap()
    // The card's chip, not a row of the picker still closing: only the chip says "Change machine".
    let machineChip = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH 'Hammer Strength' AND label ENDSWITH 'Change machine.'")
    ).firstMatch
    XCTAssertTrue(machineChip.waitForExistence(timeout: 10), "The new machine is chosen and the picker closes")
    XCTAssertTrue(waitUntilGone(addMachine), "The machine picker closed with the name sheet")

    // Its load step, from the picker's second nested sheet.
    machineChip.tap()
    let loadStep = app.buttons["Set this machine\u{2019}s load step"]
    XCTAssertTrue(loadStep.waitForExistence(timeout: 10), "The chosen machine offers its load step")
    loadStep.tap()
    let saveStep = app.buttons["Save load step"]
    XCTAssertTrue(saveStep.waitForExistence(timeout: 5), "The load-step editor opens over the machine picker")
    capture(app, "82-session-load-step")
    for key in ["1", "0"] { app.buttons[key].tap() }
    saveStep.tap()
    XCTAssertTrue(waitUntilGone(saveStep), "Saving the step closes the editor")
    XCTAssertTrue(loadStep.waitForExistence(timeout: 5), "and returns to the machine picker")
    app.buttons["Cancel"].tap()
    let steppedChip = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH 'Hammer Strength,' AND label CONTAINS 'steps'")
    ).firstMatch
    XCTAssertTrue(steppedChip.waitForExistence(timeout: 10), "The saved step shows on the card's machine chip")

    // The movement's load history, from its name.
    let history = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH 'Barbell Bench Press. Show load history'")
    ).firstMatch
    XCTAssertTrue(history.waitForExistence(timeout: 5))
    history.tap()
    let done = app.buttons["Done"]
    XCTAssertTrue(done.waitForExistence(timeout: 10), "The load history opens")
    capture(app, "83-session-history")
    done.tap()
    XCTAssertTrue(waitUntilGone(done), "Done closes the load history")
    XCTAssertTrue(addMovement.waitForExistence(timeout: 5), "and the workout is where it was left")
  }

  /// The main screens again in light mode, over a finished workout it makes for itself, so the
  /// start screen's last workout, History and Volume are drawn with data rather than empty.
  @MainActor
  func testScreensInLightMode() throws {
    continueAfterFailure = true
    let app = XCUIApplication()
    launch(app)

    guard waitForStartScreen(app) else { return }
    finishOneWorkout(app)
    XCTAssertTrue(app.buttons["Start workout"].exists, "The start screen lost its start action")
    capture(app, "30-light-start")
    audit(app, screen: "light start")
    openTab(app, "Volume")
    XCTAssertTrue(
      app.staticTexts["Volume"].firstMatch.waitForExistence(timeout: 5),
      "The Volume screen did not draw its header")
    capture(app, "31-light-volume")
    openTab(app, "History")
    XCTAssertTrue(
      app.staticTexts["History"].firstMatch.waitForExistence(timeout: 5),
      "The History screen did not draw its header")
    capture(app, "32-light-history")
    openTab(app, "Train")
    app.buttons["Settings"].tap()
    XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5), "Settings did not open")
    capture(app, "33-light-settings")
    app.buttons["Done"].tap()

    writeAuditReport(named: "accessibility-audit-light")
  }

  /// The first launch as a fresh install sees it: load a plate on the Welcome bar, through the
  /// three pitches, the guided tour, Setup and into the app, saving a screenshot of each page.
  ///
  /// It pins what the model tests cannot: that a swipe on the bar loads a plate instead of turning
  /// the page, that the tour's second step waits for the lifter's own tap on the staged set's check
  /// before "Next" appears, and that every page can be reached and completed.
  @MainActor
  func testOnboardingJourneyDark() throws {
    continueAfterFailure = true
    let app = XCUIApplication()
    launch(app, showsOnboarding: true)

    // Welcome.
    XCTAssertTrue(app.staticTexts["Hardset"].waitForExistence(timeout: 30))
    XCTAssertFalse(app.buttons["Skip"].exists, "the welcome page has no skip")
    capture(app, "40-onboarding-welcome")
    audit(app, screen: "onboarding welcome")

    let bar = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label BEGINSWITH 'Barbell'")).firstMatch
    XCTAssertTrue(bar.waitForExistence(timeout: 5))
    let unloaded = bar.label
    app.buttons["20 kilogram plate"].tap()
    XCTAssertNotEqual(bar.label, unloaded, "tapping a plate loads it")
    XCTAssertTrue(app.staticTexts["That\u{2019}s a set logged in one tap."].waitForExistence(timeout: 5))
    capture(app, "41-onboarding-welcome-loaded")

    // A swipe across the bar belongs to the bar: the page does not turn.
    bar.swipeLeft()
    XCTAssertTrue(app.staticTexts["Hardset"].exists, "swiping the bar must not turn the page")
    XCTAssertFalse(app.buttons["Skip"].exists)

    app.buttons["Start"].tap()

    // Pitch 1: one tap per set.
    XCTAssertTrue(app.staticTexts["One tap per set."].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["Skip"].exists, "skip is offered from the second page on")
    capture(app, "42-onboarding-pitch-1")
    audit(app, screen: "onboarding pitch 1")
    app.buttons["Log set"].firstMatch.tap()
    XCTAssertTrue(app.buttons["Logged"].waitForExistence(timeout: 5), "the pitch row logs")
    capture(app, "43-onboarding-pitch-1-logged")
    app.buttons["Next"].tap()

    // Pitch 2: honest numbers.
    XCTAssertTrue(app.staticTexts["Honest numbers."].waitForExistence(timeout: 5))
    capture(app, "44-onboarding-pitch-2")
    let fifteen = app.buttons["15 reps"].firstMatch
    XCTAssertTrue(fifteen.waitForExistence(timeout: 5))
    fifteen.tap()
    capture(app, "45-onboarding-pitch-2-unevaluated")
    app.buttons["Next"].tap()

    // Pitch 3: rest that keeps time.
    XCTAssertTrue(app.staticTexts["Rest that keeps time."].waitForExistence(timeout: 5))
    capture(app, "46-onboarding-pitch-3")
    app.buttons["Next"].tap()
    // What is on screen two seconds after the tap, kept in the log so a page that lands somewhere
    // else is visible in the run rather than inferred.
    Thread.sleep(forTimeInterval: 2)
    print("ONBOARDING-TRACE after the third pitch's Next:", app.staticTexts.allElementsBoundByIndex.map(\.label))
    capture(app, "46b-onboarding-after-pitch-3-next")

    // The tour. Its first step waits while two staged apps are built.
    XCTAssertTrue(app.staticTexts["Step 1 of 8"].waitForExistence(timeout: 90))
    capture(app, "47-onboarding-tour-1")
    assertStagedPhoneIsHidden(app, at: "tour step 1")
    app.buttons["tour-next"].tap()

    // Step 2 is the interactive one: no "Next" until the staged check is tapped.
    XCTAssertTrue(app.staticTexts["Step 2 of 8"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["tour-next"].exists, "Next waits for the check to be tapped")
    capture(app, "48-onboarding-tour-2")
    audit(app, screen: "onboarding tour 2")
    // The control for the hidden checks around it: while the staged phone is the thing to tap it is
    // reachable, so a count of zero elsewhere is the phone being hidden and not the query finding
    // nothing. Recorded rather than asserted, since it describes the interactive step.
    auditReport.append(
      "[onboarding tour 2] control: \(app.tabBars.count) tab bar(s) reachable while the staged phone is interactive"
    )
    // Tapped where the spotlight is. The staged row is one accessibility element with named actions,
    // so there is no separate "Log set" button to query; a touch at the check's place is also the
    // honest test that the hole lets a touch through while the scrim stops every other one. The
    // check sits at the right of the third Leg Press row, about 61% of the way down the screen: the
    // two logged rows above it each carry a "Matched" beat mark, which sits it lower than it was.
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.767, dy: 0.609)).tap()
    XCTAssertTrue(app.buttons["tour-next"].waitForExistence(timeout: 10), "logging the staged set unlocks Next")
    capture(app, "49-onboarding-tour-2-logged")
    assertStagedPhoneIsHidden(app, at: "tour step 2 after the check")

    for step in 3...8 {
      app.buttons["tour-next"].tap()
      XCTAssertTrue(app.staticTexts["Step \(step) of 8"].waitForExistence(timeout: 10))
      capture(app, "5\(step - 3)-onboarding-tour-\(step)")
      assertStagedPhoneIsHidden(app, at: "tour step \(step)")
    }
    app.buttons["tour-next"].tap()

    // Setup, then the app.
    XCTAssertTrue(app.staticTexts["Before your first set."].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["Kilograms"].exists)
    XCTAssertTrue(app.buttons["Pounds"].exists)
    XCTAssertFalse(app.buttons["Skip"].exists, "Setup is where skip leads")
    capture(app, "60-onboarding-setup")
    audit(app, screen: "onboarding setup")
    app.buttons["Start logging"].tap()
    guard waitForStartScreen(app) else { return }
    capture(app, "61-onboarding-done")

    writeAuditReport(named: "accessibility-audit-onboarding")
  }

  /// The first-launch pages at an accessibility text size. The audit's "text may be clipped at larger
  /// sizes" reports are a prediction; this draws the pages at one of those sizes, keeps the pictures
  /// to look at, and checks that the welcome line, the report's first example, is wholly on screen.
  @MainActor
  func testOnboardingAccessibilitySizeDark() throws {
    continueAfterFailure = true
    let app = XCUIApplication()
    launch(app, showsOnboarding: true, contentSize: "UICTContentSizeCategoryAccessibilityXL")

    let tagline = app.staticTexts["A calibrated log for the lifts you actually do."]
    XCTAssertTrue(tagline.waitForExistence(timeout: 30))
    capture(app, "90-onboarding-ax-welcome")
    let window = app.windows.firstMatch.frame
    XCTAssertTrue(
      window.contains(tagline.frame),
      "The welcome line runs off the screen at an accessibility size: \(tagline.frame) in \(window)")
    audit(app, screen: "onboarding welcome (accessibility size)")
    app.buttons["Start"].tap()

    XCTAssertTrue(app.staticTexts["One tap per set."].waitForExistence(timeout: 5))
    capture(app, "91-onboarding-ax-pitch-1")
    audit(app, screen: "onboarding pitch 1 (accessibility size)")
    app.buttons["Next"].tap()

    XCTAssertTrue(app.staticTexts["Honest numbers."].waitForExistence(timeout: 5))
    capture(app, "92-onboarding-ax-pitch-2")
    audit(app, screen: "onboarding pitch 2 (accessibility size)")
    app.buttons["Next"].tap()

    XCTAssertTrue(app.staticTexts["Rest that keeps time."].waitForExistence(timeout: 5))
    capture(app, "93-onboarding-ax-pitch-3")
    audit(app, screen: "onboarding pitch 3 (accessibility size)")

    writeAuditReport(named: "accessibility-audit-onboarding-ax")
  }

  /// The tour again, from Settings: the sheet closes, the same sequence plays in a full-screen cover
  /// without Setup, and skipping it returns to the app. Run past onboarding, as the daily app is.
  @MainActor
  func testTourReplayDark() throws {
    continueAfterFailure = true
    let app = XCUIApplication()
    launch(app)

    guard waitForStartScreen(app) else { return }
    app.buttons["Settings"].tap()
    XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
    let replay = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Show the tour again'"))
      .firstMatch
    var swipes = 0
    while !replay.exists && swipes < 6 {
      app.swipeUp()
      swipes += 1
    }
    XCTAssertTrue(replay.exists, "Settings offers the tour again")
    capture(app, "70-replay-settings-row")
    replay.tap()

    // The welcome page, then a skip from the second page ends the replay with no Setup page.
    XCTAssertTrue(app.staticTexts["Hardset"].waitForExistence(timeout: 10))
    capture(app, "71-replay-welcome")
    app.buttons["Start"].tap()
    XCTAssertTrue(app.staticTexts["One tap per set."].waitForExistence(timeout: 5))
    app.buttons["Skip"].tap()
    XCTAssertFalse(app.staticTexts["Before your first set."].exists, "a replay has no Setup")
    guard waitForStartScreen(app) else { return }
    capture(app, "72-replay-done")
  }

  // MARK: - Helpers

  /// Launches the app. Appearance is set by CI with `simctl ui` around separate passes, because
  /// `XCUIDevice.appearance` did not reach the system on the runner; the pass is chosen by the
  /// test method CI selects, not by this helper.
  ///
  /// - Parameter keepsStore: Leaves the database as the last launch left it. Only a journey that
  ///   relaunches to prove recovery passes it; every first launch starts from an empty store.
  /// - Parameter contentSize: A `UICTContentSizeCategory` name to launch at, for the journeys that
  ///   look at an accessibility text size. `nil` leaves the device's size alone.
  @MainActor
  private func launch(
    _ app: XCUIApplication, showsOnboarding: Bool = false, keepsStore: Bool = false,
    contentSize: String? = nil
  ) {
    // Keeps the app's stderr, so a runtime trap's message survives for CI to collect.
    app.launchEnvironment["HARDSET_CAPTURE_STDERR"] = "1"
    // Every journey but the onboarding one starts past the first-launch sequence; that one starts
    // as a fresh install would.
    app.launchEnvironment["HARDSET_ONBOARDING"] = showsOnboarding ? "reset" : "skip"
    // The store, and the preferences beside it, are emptied before the app opens them unless the
    // journey is picking up after a relaunch of its own.
    app.launchEnvironment["HARDSET_STORE"] = keepsStore ? "keep" : "reset"
    if let contentSize {
      app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
    }
    app.launch()
  }

  /// Waits for the start screen, and when it does not come, says what is showing instead. The
  /// first launch of every journey is on an empty store, so it also waits for the start screen's own
  /// statement that there are no sessions: a store that was not reset would show a last workout or
  /// resume one, and the journeys that follow would be testing another journey's leftovers.
  @MainActor
  private func waitForStartScreen(_ app: XCUIApplication) -> Bool {
    if app.buttons["Start workout"].waitForExistence(timeout: 30) {
      let noSessions = app.descendants(matching: .any)
        .matching(NSPredicate(format: "label == 'No sessions yet'")).firstMatch
      XCTAssertTrue(
        noSessions.waitForExistence(timeout: 10),
        "The journey did not start from an empty store: the start screen shows a session.")
      return true
    }
    capture(app, "00-launch-did-not-reach-start")
    XCTFail(
      "The start screen did not appear within 30 seconds. If the startup failure screen is "
        + "showing, the simulator build could not create the database or the sync engine."
    )
    return false
  }

  /// A finished one-set workout, made through the real screens: Bench Press, 100 for 8, logged and
  /// finished. The fixture for a journey that needs History and Volume to hold something.
  @MainActor
  private func finishOneWorkout(_ app: XCUIApplication) {
    app.buttons["Start workout"].tap()
    let addMovement = app.buttons["Add movement"]
    XCTAssertTrue(addMovement.waitForExistence(timeout: 5))
    addMovement.tap()
    let bench = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Barbell Bench Press'"))
      .firstMatch
    XCTAssertTrue(bench.waitForExistence(timeout: 5))
    bench.tap()
    let row = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label BEGINSWITH 'Set 1'")).firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 5))
    row.coordinate(withNormalizedOffset: CGVector(dx: 0.44, dy: 0.5)).tap()
    XCTAssertTrue(app.buttons["Next field"].waitForExistence(timeout: 5))
    for key in ["1", "0", "0"] { app.buttons[key].tap() }
    app.buttons["Next field"].tap()
    app.buttons["8"].tap()
    app.buttons["Done"].tap()
    row.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
    let loggedRow = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label BEGINSWITH 'Set 1,' AND label CONTAINS ', logged'"))
      .firstMatch
    XCTAssertTrue(loggedRow.waitForExistence(timeout: 5), "The fixture set must actually be saved.")
    let finish = app.buttons["Finish workout"]
    XCTAssertTrue(finish.waitForExistence(timeout: 5))
    finish.tap()
    XCTAssertTrue(app.buttons["Finish"].waitForExistence(timeout: 5))
    app.buttons["Finish"].tap()
    // Finishing opens the receipt over the start screen. Left open it covers every screen the
    // journey goes on to, so it is closed before the fixture is handed back.
    let receiptDone = app.buttons["Done"]
    XCTAssertTrue(receiptDone.waitForExistence(timeout: 10), "Finishing a workout opens its receipt")
    receiptDone.tap()
    XCTAssertTrue(waitUntilGone(receiptDone), "Done closes the receipt")
    XCTAssertTrue(app.buttons["Start workout"].waitForExistence(timeout: 5))
  }

  /// The staged phone is a picture of the app, so while it is not what the lifter is asked to tap,
  /// none of it may be reachable by an assistive technology: not its buttons, and not the tab bar of
  /// the root view inside it, which is UIKit-hosted and was still listed when the phone was only
  /// hidden with `accessibilityHidden`. This is what an assistive technology is offered, as XCUITest
  /// sees it; how VoiceOver reads the tour is for a device.
  @MainActor
  private func assertStagedPhoneIsHidden(_ app: XCUIApplication, at step: String) {
    XCTAssertEqual(
      app.tabBars.count, 0, "\(step): the staged phone's tab bar is reachable by accessibility")
    XCTAssertFalse(
      app.buttons["Start workout"].exists,
      "\(step): the staged start screen's button is reachable by accessibility")
  }

  /// Puts the keyboard down, so that what is audited is the screen and not the keyboard over it. The
  /// return key is the search key in the picker; failing that, the list dismisses the keyboard as it
  /// scrolls. If the keyboard is still up afterwards the audit would be of its pixels, so that fails.
  @MainActor
  private func dismissKeyboard(_ app: XCUIApplication) {
    guard app.keyboards.count > 0 else { return }
    let search = app.keyboards.buttons.matching(NSPredicate(format: "label ==[c] 'search'")).firstMatch
    if search.exists {
      search.tap()
    } else {
      app.swipeUp()
    }
    let deadline = Date().addingTimeInterval(5)
    while app.keyboards.count > 0 && Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
    XCTAssertEqual(app.keyboards.count, 0, "The keyboard is still up, so the audit would be of it")
  }

  /// True once the element is no longer on screen: a sheet that has finished closing, rather than one
  /// still sliding away, whose controls a query would otherwise find beside the next sheet's.
  @MainActor
  private func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
    let gone = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == false"), object: element)
    return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
  }

  @MainActor
  private func openTab(_ app: XCUIApplication, _ title: String) {
    let tab = app.tabBars.buttons[title].firstMatch
    if tab.waitForExistence(timeout: 5) {
      tab.tap()
    } else {
      app.buttons[title].firstMatch.tap()
    }
  }

  @MainActor
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
  @MainActor
  private func audit(_ app: XCUIApplication, screen: String) {
    do {
      try app.performAccessibilityAudit { [weak self] issue in
        let element = issue.element
        let label = element?.label ?? "no element"
        let frame = element.map { "\($0.frame)" } ?? "no frame"
        // The element's type and identifier, which a report line with no label could not otherwise be
        // traced from. `nil` element: the audit named nothing it could be pointed at.
        let kind = element.map { "type \($0.elementType.rawValue) id '\($0.identifier)'" } ?? "no type"
        self?.auditReport.append(
          "[\(screen)] \(issue.compactDescription) | \(label) | \(frame) | \(kind) | \(issue.detailedDescription)"
        )
        return true
      }
    } catch {
      auditReport.append("[\(screen)] audit could not run: \(error)")
    }
  }

  @MainActor
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
