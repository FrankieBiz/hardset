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
  /// What a coverage journey could not drive and why, written beside the screenshots so a state that
  /// is missing from the captures is explained there and not by its absence.
  private var coverageNotes: [String] = []

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
    // The single-thumb pad traversal: weight and reps are typed on the logger's own keypad, so the
    // system keyboard never comes up, with the weight open, after Next, or on the reps.
    XCTAssertFalse(
      app.keyboards.firstMatch.exists, "The weight keypad is the logger's own; no system keyboard.")
    for key in ["1", "0", "0"] { app.buttons[key].tap() }
    capture(app, "13-keypad-weight")
    audit(app, screen: "keypad")
    // One press moves from weight to reps: no cursor to place, no second tap on the reps field.
    app.buttons["Next field"].tap()
    // The same keypad, retargeted: its display now names reps.
    let repsDisplay = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label BEGINSWITH 'Reps'")).firstMatch
    XCTAssertTrue(repsDisplay.waitForExistence(timeout: 3))
    XCTAssertFalse(
      app.keyboards.firstMatch.exists, "Next retargets the pad in place; no system keyboard.")
    app.buttons["8"].tap()
    XCTAssertFalse(
      app.keyboards.firstMatch.exists, "The reps keypad is the logger's own; no system keyboard.")
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

    // A saved figure is corrected where it is: the weight opens the keypad on the saved set, the
    // first digit replaces it, and the correction is written when the keypad moves on. The set
    // stays logged throughout, with the same reps.
    row.coordinate(withNormalizedOffset: CGVector(dx: 0.44, dy: 0.5)).tap()
    XCTAssertTrue(
      app.buttons["Next field"].waitForExistence(timeout: 5),
      "A saved weight must open the keypad so it can be corrected.")
    for key in ["7", "0"] { app.buttons[key].tap() }
    capture(app, "40a-correcting-saved-weight")
    app.buttons["Next field"].tap()
    app.buttons["Done"].tap()
    let corrected = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label BEGINSWITH 'Set 1,' AND label CONTAINS ', logged'"))
      .firstMatch
    XCTAssertTrue(corrected.waitForExistence(timeout: 5), "A corrected set must stay logged.")
    XCTAssertTrue(corrected.label.contains("70 "), "The correction must be what is shown.")
    XCTAssertTrue(corrected.label.contains(", 5 reps"), "Correcting the weight must keep the reps.")
    capture(app, "40b-correction-saved")

    // Undo it from the row's long-press menu. The menu intermittently does not open on the first
    // press under automation, so this one press is retried once; see `longPressForMenu`.
    let undo = app.buttons["Undo log"]
    longPressForMenu(row, items: [undo])
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

    // The movement picker, then a *machine* movement with a gym set, so its card offers a
    // machine. A barbell movement has no machine, and since A9 its card offers no chip at all.
    addMovement.tap()
    let press = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Chest Press'"))
      .firstMatch
    XCTAssertTrue(press.waitForExistence(timeout: 5))
    press.tap()

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
      NSPredicate(format: "label BEGINSWITH 'Chest Press. Show load history'")
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
  /// three pitches, Setup and into the app, saving a screenshot of each page.
  ///
  /// It pins what the model tests cannot: that a swipe on the bar loads a plate instead of turning
  /// the page, that the last pitch leads straight to Setup with no tour, and that every page can
  /// be reached and completed.
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
    assertPitchProgress(app, page: 1)
    audit(app, screen: "onboarding pitch 1")
    app.buttons["Log set"].firstMatch.tap()
    XCTAssertTrue(app.buttons["Logged"].waitForExistence(timeout: 5), "the pitch row logs")
    capture(app, "43-onboarding-pitch-1-logged")
    app.buttons["Next"].tap()

    // Pitch 2: honest numbers.
    XCTAssertTrue(app.staticTexts["Honest numbers."].waitForExistence(timeout: 5))
    capture(app, "44-onboarding-pitch-2")
    assertPitchProgress(app, page: 2)
    let fifteen = app.buttons["15 reps"].firstMatch
    XCTAssertTrue(fifteen.waitForExistence(timeout: 5))
    fifteen.tap()
    capture(app, "45-onboarding-pitch-2-unevaluated")
    app.buttons["Next"].tap()

    // Pitch 3: rest that keeps time.
    XCTAssertTrue(app.staticTexts["Rest that keeps time."].waitForExistence(timeout: 5))
    capture(app, "46-onboarding-pitch-3")
    assertPitchProgress(app, page: 3)
    app.buttons["Next"].tap()
    // The last pitch leads straight to Setup: there is no tour page after it.
    XCTAssertTrue(
      app.staticTexts["Before your first set."].waitForExistence(timeout: 10),
      "the third pitch's Next lands on Setup")
    capture(app, "46b-onboarding-after-pitch-3-next")

    // Setup, then the app.
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

  // MARK: - Coverage wave 1

  /// The screens a lifter meets first that no journey had driven, only seen as component renders:
  /// Progress, Muscle history, Library, the live rest bar and its issue details, and a finished
  /// workout's receipt in correcting and removing mode. History's month jump and Settings' data
  /// transfer are added where they cost one tap.
  ///
  /// History is made through the real screens, as the other journeys make theirs: Bench Press four
  /// times (the first by hand, the next three by "Repeat last workout", so the movement has the four
  /// sessions a "No record in 3 sessions" row needs), then a workout with a Back Squat at 100 for 8 and
  /// a Deadlift at 140 for 1, so the board holds an estimated row and a measured one. Every set is
  /// logged today, so no row has a six-week change; what that leaves undriven is written to the
  /// coverage notes beside the screenshots.
  ///
  /// Each state is its own segment. A segment that cannot reach its screen fails with what it was
  /// looking for and goes back to the start screen, so one missing control does not hide every
  /// capture after it.
  @MainActor
  func testCoverageWaveOneScreensDark() throws {
    continueAfterFailure = true
    let app = XCUIApplication()
    launch(app)

    guard waitForStartScreen(app) else { return }
    guard seedCoverageHistory(app) else {
      writeCoverageNotes(named: "coverage-wave1-notes")
      return
    }

    driveProgress(app)
    driveMuscleHistory(app)
    driveLibrary(app)
    driveHistoryAndReceipt(app)
    driveSettingsData(app)
    driveLiveRest(app)

    writeAuditReport(named: "accessibility-audit-coverage-wave1")
    writeCoverageNotes(named: "coverage-wave1-notes")
  }

  /// Five finished workouts: Bench Press 100 for 8 four times, then Back Squat 100 for 8 and
  /// Conventional Deadlift 140 for 1 in one. Returns false when a step could not be taken, with the
  /// failure recorded, because every segment after it reads this history.
  @MainActor
  private func seedCoverageHistory(_ app: XCUIApplication) -> Bool {
    finishOneWorkout(app)
    guard app.buttons["Start workout"].exists else {
      XCTFail("The first seeded workout did not return to the start screen")
      return false
    }
    // Three more of the same, started from "Repeat last workout". Each is typed out again, not
    // relied on to be prefilled, so the four sessions hold the same set whatever the prefill does.
    for index in 2...4 {
      let again = app.buttons["Repeat last workout"]
      guard again.waitForExistence(timeout: 10) else {
        XCTFail("Seeded workout \(index): 'Repeat last workout' was not offered")
        return false
      }
      again.tap()
      guard typeAndLogPendingSet(app, weight: ["1", "0", "0"], reps: ["8"], loggedCount: 1),
        finishWorkout(app)
      else { return false }
    }

    let start = app.buttons["Start workout"]
    guard start.waitForExistence(timeout: 10) else {
      XCTFail("Seeded workout 5: the start screen did not offer 'Start workout'")
      return false
    }
    start.tap()
    guard addMovement(app, named: "Barbell Back Squat"),
      typeAndLogPendingSet(app, weight: ["1", "0", "0"], reps: ["8"], loggedCount: 1),
      addMovement(app, named: "Conventional Deadlift"),
      typeAndLogPendingSet(app, weight: ["1", "4", "0"], reps: ["1"], loggedCount: 2),
      finishWorkout(app)
    else { return false }
    return true
  }

  // MARK: Progress

  /// The board with a measured row, an estimated row and a "No record in 3 sessions" row, then the
  /// movement's chart and the working behind its estimated max.
  @MainActor
  private func driveProgress(_ app: XCUIApplication) {
    dismissSheets(app)
    openTab(app, "Progress")
    let rows = app.descendants(matching: .any)
    let stalled = rows.matching(
      NSPredicate(
        format: "label BEGINSWITH 'Barbell Bench Press' AND label CONTAINS 'No record in 3 sessions'")
    ).firstMatch
    let estimated = rows.matching(
      NSPredicate(
        format: "label BEGINSWITH 'Barbell Back Squat' AND label CONTAINS 'Estimated max'")
    ).firstMatch
    let measured = rows.matching(
      NSPredicate(
        format:
          "label BEGINSWITH 'Conventional Deadlift' AND label CONTAINS 'Max \u{00B7} no 6-week comparison' AND NOT (label CONTAINS 'Estimated max')"
      )
    ).firstMatch
    guard stalled.waitForExistence(timeout: 20) else {
      capture(app, "50-progress-board")
      XCTFail("Progress did not draw a Bench Press row that says 'No record in 3 sessions'")
      return
    }
    XCTAssertTrue(estimated.exists, "Progress did not draw an estimated row for the Back Squat")
    XCTAssertTrue(
      measured.exists, "Progress did not draw a measured row ('Max', not 'Estimated max') for the Deadlift")
    capture(app, "50-progress-board")
    audit(app, screen: "progress board")

    // "Worked from" on a row needs a six-week change, which needs a session 5 to 7 weeks before the
    // latest. Every set here is logged today, so none can have one.
    let rowWorking = rows.matching(
      NSPredicate(format: "label BEGINSWITH 'Worked from,' AND label CONTAINS ' change'"))
    if rowWorking.count == 0 {
      note(
        "Progress row 'Worked from': not drawn. A row offers it only with a six-week change, which needs a "
          + "session 5 to 7 weeks before the latest; the app cannot log a set into the past, so a UI test "
          + "cannot make one. The movement chart's own 'Worked from' (the estimated max) is captured instead "
          + "as 52-progress-worked-from.")
    }

    stalled.tap()
    let legend = rows.matching(NSPredicate(format: "label CONTAINS 'latest estimate on'")).firstMatch
    guard legend.waitForExistence(timeout: 15) else {
      capture(app, "51-progress-chart")
      XCTFail("The movement's chart did not draw its estimated-max figure")
      dismissSheets(app)
      return
    }
    capture(app, "51-progress-chart")
    audit(app, screen: "progress chart")
    if !legend.isHittable { _ = scrollUntilHittable(legend, in: app, maxSwipes: 4) }
    legend.tap()
    guard app.navigationBars["Worked from"].waitForExistence(timeout: 10) else {
      XCTFail("The estimated max's 'Worked from' did not open")
      dismissSheets(app)
      return
    }
    capture(app, "52-progress-worked-from")
    audit(app, screen: "progress worked from")
    tapDone(app, in: "Worked from")
    dismissSheets(app)
  }

  // MARK: Muscle history

  /// The paid sheet, unlocked because the simulator is a development build, then one account.
  @MainActor
  private func driveMuscleHistory(_ app: XCUIApplication) {
    dismissSheets(app)
    openTab(app, "Volume")
    let open = app.buttons["Muscle history"]
    guard open.waitForExistence(timeout: 20) else {
      capture(app, "53-muscle-history")
      XCTFail("Volume did not offer 'Muscle history' with a week of logged sets behind it")
      return
    }
    open.tap()
    let working = app.descendants(matching: .any).matching(
      NSPredicate(format: "label BEGINSWITH 'Worked from,' AND label ENDSWITH 'last four weeks'")
    ).firstMatch
    guard working.waitForExistence(timeout: 20) else {
      capture(app, "53-muscle-history")
      XCTFail("Muscle history did not draw a four-week 'Worked from' beside any muscle")
      dismissSheets(app)
      return
    }
    capture(app, "53-muscle-history")
    audit(app, screen: "muscle history")
    if !working.isHittable { _ = scrollUntilHittable(working, in: app, maxSwipes: 6) }
    working.tap()
    guard app.navigationBars["Worked from"].waitForExistence(timeout: 10) else {
      XCTFail("Muscle history's 'Worked from' did not open")
      dismissSheets(app)
      return
    }
    capture(app, "54-muscle-history-worked-from")
    audit(app, screen: "muscle history worked from")
    tapDone(app, in: "Worked from")
    tapDone(app, in: "Muscle history")
    XCTAssertTrue(
      waitUntilGone(app.navigationBars["Muscle history"]), "Done closes Muscle history")
  }

  // MARK: Library

  /// The Library from Train: the grouped list, and the editor its plus opens.
  @MainActor
  private func driveLibrary(_ app: XCUIApplication) {
    dismissSheets(app)
    openTab(app, "Train")
    let library = app.buttons["Library"]
    guard library.waitForExistence(timeout: 10) else {
      XCTFail("Train did not offer 'Library'")
      return
    }
    library.tap()
    let newMovement = app.buttons["New movement"]
    guard newMovement.waitForExistence(timeout: 15) else {
      capture(app, "55-library")
      XCTFail("The Library did not open with its 'New movement' control")
      return
    }
    capture(app, "55-library")
    audit(app, screen: "library")
    newMovement.tap()
    let cancel = app.buttons["Cancel"]
    guard cancel.waitForExistence(timeout: 10) else {
      capture(app, "56-library-movement-editor")
      XCTFail("'New movement' did not open the movement editor")
      return
    }
    capture(app, "56-library-movement-editor")
    audit(app, screen: "movement editor")
    cancel.tap()
    XCTAssertTrue(waitUntilGone(cancel), "Cancel closes the movement editor")
    // The Library is pushed onto Train, so its bar's first button is the way back.
    let back = app.navigationBars["Library"].buttons.element(boundBy: 0)
    if back.exists { back.tap() }
    XCTAssertTrue(
      app.buttons["Start workout"].waitForExistence(timeout: 10), "Back returns to the start screen")
  }

  // MARK: History month jump and the receipt

  /// History's month jump, then the newest workout's receipt: correcting mode, one set corrected
  /// through the keypad, and the remove-a-set confirmation, which is cancelled so nothing is lost.
  @MainActor
  private func driveHistoryAndReceipt(_ app: XCUIApplication) {
    dismissSheets(app)
    openTab(app, "History")

    let jump = app.buttons["Jump to a month"]
    if jump.waitForExistence(timeout: 15) {
      jump.tap()
      if app.navigationBars["Jump to a month"].waitForExistence(timeout: 10) {
        capture(app, "76-history-month-jump")
        audit(app, screen: "history month jump")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(
          waitUntilGone(app.navigationBars["Jump to a month"]), "Cancel closes the month jump")
      } else {
        XCTFail("The calendar button did not open the month jump")
        dismissSheets(app)
      }
    } else {
      XCTFail("History did not offer 'Jump to a month'")
    }

    let row = app.buttons.matching(NSPredicate(format: "label CONTAINS ' volume'")).firstMatch
    guard row.waitForExistence(timeout: 15) else {
      XCTFail("History did not list the seeded workouts")
      return
    }
    row.tap()
    let corrections = app.buttons["Correct"]
    guard corrections.waitForExistence(timeout: 15) else {
      XCTFail("The receipt did not open with its 'Correct' menu")
      dismissSheets(app)
      return
    }
    corrections.tap()
    let correctASet = app.buttons["Correct a set"]
    guard correctASet.waitForExistence(timeout: 5) else {
      XCTFail("The 'Correct' menu did not offer 'Correct a set'")
      dismissSheets(app)
      return
    }
    correctASet.tap()
    let pencil = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Correct set,'")).firstMatch
    guard pencil.waitForExistence(timeout: 10) else {
      XCTFail("Correcting mode did not put a pencil beside any set")
      dismissSheets(app)
      return
    }
    capture(app, "57-receipt-correcting")
    audit(app, screen: "receipt correcting")

    pencil.tap()
    let next = app.buttons["Next"]
    guard next.waitForExistence(timeout: 10) else {
      XCTFail("The pencil did not open the set correction sheet")
      dismissSheets(app)
      return
    }
    XCTAssertFalse(
      app.keyboards.firstMatch.exists, "The correction sheet's keypad is the logger's own; no system keyboard.")
    for key in ["1", "0", "5"] { app.buttons[key].tap() }
    capture(app, "58-receipt-correction-keypad")
    audit(app, screen: "receipt correction keypad")
    next.tap()
    let save = app.buttons["Save correction"]
    guard save.waitForExistence(timeout: 5) else {
      XCTFail("'Next' did not move the correction keypad to the reps with 'Save correction'")
      dismissSheets(app)
      return
    }
    save.tap()
    XCTAssertTrue(waitUntilGone(save, timeout: 10), "Saving the correction closes the sheet")
    let corrected = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH 'Correct set,' AND label CONTAINS '105'")
    ).firstMatch
    XCTAssertTrue(
      corrected.waitForExistence(timeout: 10), "The receipt must show the corrected weight, 105")
    capture(app, "59-receipt-corrected")

    // Removing is the other mode; the menu switches to it, and the confirmation is read, not taken.
    app.buttons["Correct"].tap()
    let removeASet = app.buttons["Remove a set"]
    guard removeASet.waitForExistence(timeout: 5) else {
      XCTFail("The 'Correct' menu did not offer 'Remove a set'")
      dismissSheets(app)
      return
    }
    removeASet.tap()
    let minus = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Delete set,'")).firstMatch
    guard minus.waitForExistence(timeout: 10) else {
      XCTFail("Removing mode did not put a minus beside any set")
      dismissSheets(app)
      return
    }
    minus.tap()
    let confirmDelete = app.buttons["Delete set"]
    guard confirmDelete.waitForExistence(timeout: 5) else {
      XCTFail("The minus did not ask 'Delete this set?'")
      dismissSheets(app)
      return
    }
    capture(app, "59b-receipt-remove-confirm")
    app.buttons["Cancel"].tap()
    XCTAssertTrue(waitUntilGone(confirmDelete), "Cancel closes the confirmation")
    XCTAssertTrue(
      app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Delete set,'")).firstMatch.exists,
      "Cancelling must leave the set where it was")

    // The first Done ends the mode; the second closes the receipt.
    tapDone(app, in: "Workout receipt")
    tapDone(app, in: "Workout receipt")
    XCTAssertTrue(
      waitUntilGone(app.navigationBars["Workout receipt"]), "Done closes the receipt")
  }

  // MARK: Settings, data transfer

  /// The export options, one export made, and the import section. The import preview needs a file
  /// chosen in the system's Files picker; see the notes written below for why that is not driven.
  @MainActor
  private func driveSettingsData(_ app: XCUIApplication) {
    dismissSheets(app)
    openTab(app, "Train")
    let settings = app.buttons["Settings"]
    guard settings.waitForExistence(timeout: 10) else {
      XCTFail("Train did not offer Settings")
      return
    }
    settings.tap()
    guard app.buttons["Done"].waitForExistence(timeout: 10) else {
      XCTFail("Settings did not open")
      return
    }
    let exportCSV = app.buttons["Export CSV"]
    guard scrollUntilHittable(exportCSV, in: app, maxSwipes: 10) else {
      capture(app, "77-settings-data-export")
      XCTFail("Settings' data transfer section did not offer 'Export CSV'")
      dismissSheets(app)
      return
    }
    capture(app, "77-settings-data-export")
    audit(app, screen: "settings data export")
    exportCSV.tap()
    let shareLink = app.descendants(matching: .any).matching(
      NSPredicate(format: "label BEGINSWITH 'Save or share'")
    ).firstMatch
    if shareLink.waitForExistence(timeout: 20) {
      if !shareLink.isHittable { _ = scrollUntilHittable(shareLink, in: app, maxSwipes: 3) }
      capture(app, "78-settings-data-export-ready")
    } else {
      capture(app, "78-settings-data-export-ready")
      XCTFail("'Export CSV' did not produce a file to save or share")
    }

    let choose = app.buttons["Choose workout file"]
    guard scrollUntilHittable(choose, in: app, maxSwipes: 8) else {
      XCTFail("Settings did not offer 'Choose workout file'")
      dismissSheets(app)
      return
    }
    capture(app, "79-settings-data-import")
    audit(app, screen: "settings data import")
    // Opening the picker is as far as a test can go: it is the system's, out of process, and the
    // simulator's Files holds no workout CSV that a test could put there.
    choose.tap()
    let pickerCancel = app.buttons["Cancel"]
    if pickerCancel.waitForExistence(timeout: 8) {
      capture(app, "79b-settings-file-picker")
      pickerCancel.tap()
      _ = waitUntilGone(pickerCancel)
      note(
        "Data transfer import preview: not driven. 'Choose workout file' opens the system's Files picker "
          + "(captured as 79b-settings-file-picker), and the simulator's Files holds no workout CSV; a UI "
          + "test cannot create a file there, and the picker is out of process, so no fixture could be "
          + "selected and the preview, its duplicate state, the commit and the undo stay undriven.")
    } else {
      note(
        "Data transfer import preview: not driven. 'Choose workout file' did not put a picker with a "
          + "Cancel control in front of the test within 8 seconds, so no fixture could be selected.")
    }
    dismissSheets(app)
  }

  // MARK: Live rest

  /// A rest started from the card, the running bar, the next-rest chooser, pause and resume, and,
  /// where the simulator denies alarms, the issue banner and its details sheet at an accessibility
  /// size, where the banner becomes one control that opens them.
  @MainActor
  private func driveLiveRest(_ app: XCUIApplication) {
    dismissSheets(app)
    openTab(app, "Train")
    let start = app.buttons["Start workout"]
    guard start.waitForExistence(timeout: 10) else {
      XCTFail("Rest: the start screen did not offer 'Start workout'")
      return
    }
    start.tap()
    guard addMovement(app, named: "Barbell Bench Press") else { return }

    // No rest has been chosen for this movement, so the card offers a menu of lengths, not a
    // one-tap rest. Three minutes, so the rest is still running after the relaunch below.
    let startRest = app.buttons["Start rest"]
    guard startRest.waitForExistence(timeout: 10) else {
      XCTFail("Rest: the card did not offer 'Start rest'")
      return
    }
    startRest.tap()
    let threeMinutes = app.buttons["3 minutes"]
    guard threeMinutes.waitForExistence(timeout: 5) else {
      XCTFail("Rest: the 'Start rest' menu did not offer 3 minutes")
      return
    }
    threeMinutes.tap()
    answerAlarmPermission(app)

    let resting = app.descendants(matching: .any).matching(
      NSPredicate(format: "label BEGINSWITH 'Resting,'")
    ).firstMatch
    guard resting.waitForExistence(timeout: 10) else {
      capture(app, "70-rest-running")
      XCTFail("Rest: choosing 3 minutes did not start the rest bar")
      return
    }
    capture(app, "70-rest-running")
    audit(app, screen: "rest running")

    let nextRest = app.buttons["Next rest, 3 minutes"]
    if nextRest.waitForExistence(timeout: 5) {
      nextRest.tap()
      let twoMinutes = app.buttons["2 minutes"]
      if twoMinutes.waitForExistence(timeout: 5) {
        capture(app, "71-rest-chooser")
        twoMinutes.tap()
        XCTAssertTrue(
          app.buttons["Next rest, 2 minutes"].waitForExistence(timeout: 5),
          "Choosing 2 minutes must become the next rest")
      } else {
        XCTFail("Rest: the next-rest row did not open the lengths")
      }
    } else {
      XCTFail("Rest: the bar did not offer 'Next rest, 3 minutes'")
    }

    let pause = app.buttons["Pause rest"]
    if pause.waitForExistence(timeout: 5) {
      pause.tap()
      let resume = app.buttons["Resume rest"]
      if resume.waitForExistence(timeout: 5) {
        capture(app, "72-rest-paused")
        resume.tap()
        XCTAssertTrue(
          app.buttons["Pause rest"].waitForExistence(timeout: 5), "Resume must run the rest again")
      } else {
        XCTFail("Rest: Pause did not become Resume")
      }
    } else {
      XCTFail("Rest: the bar did not offer 'Pause rest'")
    }

    let issueText = app.descendants(matching: .any).matching(
      NSPredicate(format: "label CONTAINS 'Rest alerts are off'")
    ).firstMatch
    guard issueText.waitForExistence(timeout: 5) else {
      note(
        "Rest issue banner and details sheet: not forced. The simulator answered the rest start without "
          + "denying alarms (no permission prompt was denied and no 'Rest alerts are off' banner drew), so "
          + "there was no issue to open. The details sheet is only reachable at an accessibility size, where "
          + "the banner becomes one control, and that needs the issue first.")
      return
    }
    capture(app, "73-rest-issue-banner")

    // At an accessibility size the banner is one control that opens the same words in a sheet. The
    // rest is stored as an absolute deadline, so it is still running after the relaunch.
    app.terminate()
    launch(app, keepsStore: true, contentSize: "UICTContentSizeCategoryAccessibilityXL")
    let compact = app.buttons.matching(
      NSPredicate(format: "label CONTAINS 'Rest alerts are off'")
    ).firstMatch
    guard compact.waitForExistence(timeout: 30) else {
      capture(app, "74-rest-issue-compact-ax")
      XCTFail("Rest: at an accessibility size the issue did not draw as one control after a relaunch")
      return
    }
    capture(app, "74-rest-issue-compact-ax")
    compact.tap()
    guard app.navigationBars["Rest timer"].waitForExistence(timeout: 10) else {
      XCTFail("Rest: the compact issue control did not open the 'Rest timer' details sheet")
      return
    }
    capture(app, "75-rest-issue-details")
    audit(app, screen: "rest issue details (accessibility size)")
    tapDone(app, in: "Rest timer")
    XCTAssertTrue(waitUntilGone(app.navigationBars["Rest timer"]), "Done closes the rest details")
  }

  // MARK: Coverage helpers

  /// Opens the picker from the live session's "Add movement" and chooses `name`, typing it into the
  /// search field when the row is not already on screen. The catalogue is long, and a row below the
  /// fold is not in the accessibility tree.
  @MainActor
  private func addMovement(_ app: XCUIApplication, named name: String) -> Bool {
    let add = app.buttons["Add movement"]
    guard add.waitForExistence(timeout: 10) else {
      XCTFail("'Add movement' was not offered before choosing \(name)")
      return false
    }
    add.tap()
    let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
    if !row.waitForExistence(timeout: 4) {
      let search = app.textFields.firstMatch
      if search.waitForExistence(timeout: 3) {
        search.tap()
        search.typeText(name)
      }
    }
    guard row.waitForExistence(timeout: 8) else {
      XCTFail("The movement picker did not list \(name)")
      return false
    }
    row.tap()
    return true
  }

  /// Types a weight and reps into the first set row that is not yet logged, through the logger's own
  /// keypad as the other journeys do, logs it, and waits until `loggedCount` rows are logged.
  @MainActor
  private func typeAndLogPendingSet(
    _ app: XCUIApplication, weight: [String], reps: [String], loggedCount: Int
  ) -> Bool {
    let pending = app.descendants(matching: .any).matching(
      NSPredicate(format: "label BEGINSWITH 'Set 1' AND NOT (label CONTAINS ', logged')")
    ).firstMatch
    guard pending.waitForExistence(timeout: 10) else {
      XCTFail("No set row was waiting to be logged")
      return false
    }
    pending.coordinate(withNormalizedOffset: CGVector(dx: 0.44, dy: 0.5)).tap()
    guard app.buttons["Next field"].waitForExistence(timeout: 5) else {
      XCTFail("The weight did not open the keypad")
      return false
    }
    for key in weight { app.buttons[key].tap() }
    app.buttons["Next field"].tap()
    for key in reps { app.buttons[key].tap() }
    app.buttons["Done"].tap()
    pending.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
    let logged = app.descendants(matching: .any).matching(
      NSPredicate(format: "label BEGINSWITH 'Set 1,' AND label CONTAINS ', logged'"))
    let deadline = Date().addingTimeInterval(10)
    while logged.count < loggedCount && Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
    guard logged.count >= loggedCount else {
      XCTFail("The typed set was not saved: \(logged.count) logged rows, expected \(loggedCount)")
      return false
    }
    return true
  }

  /// Finishes the live workout and closes its receipt, ending on the start screen.
  @MainActor
  private func finishWorkout(_ app: XCUIApplication) -> Bool {
    let finish = app.buttons["Finish workout"]
    var swipes = 0
    while !finish.exists && swipes < 3 {
      app.swipeUp()
      swipes += 1
    }
    guard finish.waitForExistence(timeout: 5) else {
      XCTFail("The live workout did not offer 'Finish workout'")
      return false
    }
    finish.tap()
    guard app.buttons["Finish"].waitForExistence(timeout: 5) else {
      XCTFail("'Finish workout' did not ask for confirmation")
      return false
    }
    app.buttons["Finish"].tap()
    let receiptDone = app.buttons["Done"]
    guard receiptDone.waitForExistence(timeout: 10) else {
      XCTFail("Finishing a workout did not open its receipt")
      return false
    }
    receiptDone.tap()
    guard waitUntilGone(receiptDone), app.buttons["Start workout"].waitForExistence(timeout: 5) else {
      XCTFail("Done did not close the receipt back to the start screen")
      return false
    }
    return true
  }

  /// Answers the system's alarm permission prompt, if the simulator raises one, by denying it: a
  /// denied alarm is the issue the rest banner exists to state. Returns whether a prompt appeared.
  @discardableResult
  @MainActor
  private func answerAlarmPermission(_ app: XCUIApplication) -> Bool {
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let alert = springboard.alerts.firstMatch
    guard alert.waitForExistence(timeout: 6) else {
      note("Alarm permission: no system prompt appeared when the first rest started.")
      return false
    }
    capture(app, "73a-rest-alarm-permission")
    let deny = alert.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Don'")).firstMatch
    (deny.exists ? deny : alert.buttons.element(boundBy: 0)).tap()
    return true
  }

  /// Taps the Done in the navigation bar titled `title`, which is the top sheet's when sheets are
  /// stacked and each has its own Done.
  @MainActor
  private func tapDone(_ app: XCUIApplication, in title: String) {
    let scoped = app.navigationBars[title].buttons["Done"]
    if scoped.waitForExistence(timeout: 3) {
      scoped.tap()
    } else {
      app.buttons["Done"].firstMatch.tap()
    }
  }

  /// Closes whatever sheets a segment left open, so the next one starts at a tab bar.
  @MainActor
  private func dismissSheets(_ app: XCUIApplication) {
    for _ in 0..<4 {
      let done = app.buttons["Done"]
      let cancel = app.buttons["Cancel"]
      if done.exists, done.isHittable {
        done.firstMatch.tap()
      } else if cancel.exists, cancel.isHittable {
        cancel.firstMatch.tap()
      } else {
        return
      }
      Thread.sleep(forTimeInterval: 0.6)
    }
  }

  /// Swipes up until the element can be tapped, for a control below the fold of a scroll view or a
  /// sheet. Returns whether it got there.
  @MainActor
  private func scrollUntilHittable(
    _ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int
  ) -> Bool {
    var swipes = 0
    while !(element.exists && element.isHittable) && swipes < maxSwipes {
      app.swipeUp()
      swipes += 1
    }
    return element.exists && element.isHittable
  }

  /// Records what a coverage journey could not drive, and why.
  @MainActor
  private func note(_ text: String) {
    coverageNotes.append(text)
  }

  @MainActor
  private func writeCoverageNotes(named name: String) {
    let text =
      coverageNotes.isEmpty
      ? "Every state this journey set out to drive was reached.\n"
      : coverageNotes.joined(separator: "\n\n") + "\n"
    let attachment = XCTAttachment(string: text)
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
    if let directory = Self.outputDirectory {
      try? text.write(
        to: directory.appendingPathComponent("\(name).txt"), atomically: true, encoding: .utf8)
    }
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

  /// Long-presses a set row to open its context menu, pressing once more if nothing opened.
  ///
  /// The menu intermittently fails to open under automation: this press failed on bases `31f7c45`
  /// and `e34e295` and passed on `1c935d5` and `09cb15e`, on the same app code. So a first press
  /// that produces nothing says nothing about the app, and it is retried once -- the same shape as
  /// the retry #22 added for a "Busy / installing" launch refusal. The caller's own assertion still
  /// fails if the second press produces nothing either; nothing else in this suite is retried, and
  /// no wait here is longer than the ones around it.
  ///
  /// - Parameter items: what the menu puts on screen. The press is retried only while none of them
  ///   exists, so a menu that opened but has not settled is never pressed a second time.
  @MainActor
  private func longPressForMenu(_ row: XCUIElement, items: [XCUIElement], dx: CGFloat = 0.08) {
    let point = row.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: 0.5))
    point.press(forDuration: 1.2)
    if items.contains(where: { $0.waitForExistence(timeout: 3) }) { return }
    // A swallowed press leaves no menu behind, so the second one starts from the same row.
    point.press(forDuration: 1.2)
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

  /// The pitch pages' progress row is a gauge: a progress indicator named "Introduction" whose
  /// value is the page. Fails if it goes back to a bare labelled node, which the audit read as a
  /// 4 pt target (the audit's hit-area line on the gauge is a known false positive; see the
  /// first-launch pager in `DESIGN.md`), or if its label or value drifts.
  @MainActor
  private func assertPitchProgress(
    _ app: XCUIApplication, page: Int, file: StaticString = #filePath, line: UInt = #line
  ) {
    let gauge = app.descendants(matching: .any)["pitch-progress"]
    XCTAssertTrue(gauge.waitForExistence(timeout: 5), "the pitch progress is offered", file: file, line: line)
    XCTAssertEqual(gauge.elementType, .progressIndicator, "the pitch progress is a gauge", file: file, line: line)
    XCTAssertEqual(gauge.label, "Introduction", file: file, line: line)
    XCTAssertEqual(gauge.value as? String, "Page \(page) of 3", file: file, line: line)
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
