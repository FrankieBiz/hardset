import Foundation
import Testing

/// Contracts the rest of the suite structurally cannot reach.
///
/// Every test here reads the repository from disk rather than exercising a type, because each one
/// guards something no runtime assertion in this package can touch: a plist key the host suite never
/// loads, iOS-only source that `canImport(AlarmKit)` compiles away on macOS entirely, and a colour
/// or hit-target decision that only exists once SwiftUI has laid a view out on a device.
///
/// HANDOFF section 7 is blunt that "the package tests pass" says nothing about any of those. This
/// file does not change that. It is the narrower claim that the *authored source* still says what a
/// past defect proved it has to say, checked the only way it can be from here -- as text. A green
/// run here is not a substitute for `DEVICE-CHECKLIST.md`; it only stops a fix from being quietly
/// undone between now and the device.
@Suite("The submission candidate keeps the contracts a green suite cannot see")
struct SubmissionContractTests {
  static let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // HardsetUITests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // HardsetKit
    .deletingLastPathComponent()  // Packages
    .deletingLastPathComponent()  // repository root

  static func read(_ relative: String) throws -> String {
    try String(contentsOf: repositoryRoot.appending(path: relative), encoding: .utf8)
  }

  /// The file with whole-line comments removed.
  ///
  /// Every fix below is documented in a comment that names the construct it removed, so a naive
  /// scan finds the ban in the sentence explaining the ban. That is the trap recorded in HANDOFF
  /// section 9, and its remedy is the same one recorded there: strip first, then assert the scan is
  /// still looking at something, so stripping cannot become a way to pass by deleting the subject.
  static func code(_ relative: String) throws -> String {
    let lines = try read(relative).split(separator: "\n", omittingEmptySubsequences: false)
    let kept = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    return kept.joined(separator: "\n")
  }

  // MARK: - Orientation

  /// The numeric pad is a sheet sized to its own content: seven rows floored at `loggerTapTarget`
  /// plus spacing and padding, so 464 pt, with no `ScrollView` to compress into and no
  /// `verticalSizeClass` reader anywhere in HardsetKit. Landscape on every supported iPhone is
  /// 375-440 pt tall, so allowing it clipped the bottom key row and Done off the screen -- the pad
  /// opened on the one control every weight and every rep is typed on, and could not be dismissed
  /// or completed. `GENERATE_INFOPLIST_FILE` is NO for this target, so nothing supplies this key
  /// except this file, and its absence is not neutral: it means portrait plus both landscapes.
  @Test("The app declares portrait only, so the keypad cannot be clipped off a landscape screen")
  func portraitOnly() throws {
    let plist = try Self.read("Hardset/Info.plist")

    let declaresOrientations = plist.contains("<key>UISupportedInterfaceOrientations</key>")
    #expect(
      declaresOrientations,
      "Info.plist must pin the orientation set. Absent, the app ships portrait and both landscapes."
    )

    let offersPortrait = plist.contains("UIInterfaceOrientationPortrait")
    #expect(offersPortrait, "The scan is vacuous if the array names no orientation at all.")

    let offersLandscape = plist.contains("UIInterfaceOrientationLandscape")
    #expect(
      !offersLandscape,
      "NumericPad has to become scrollable before landscape is offered -- see SetRowView.padHeight."
    )
  }

  // MARK: - The flagship alert

  /// `AlarmPresentation.Alert.SecondaryButtonBehavior` has exactly two cases in the iOS 26.4 SDK:
  /// `.countdown`, which the system handles, and `.custom`, which dispatches to the configuration's
  /// `secondaryIntent`. `AlarmManager.AlarmConfiguration.timer(duration:attributes:stopIntent:
  /// secondaryIntent:sound:)` defaults that intent to nil.
  ///
  /// So the alert once offered a "Skip" button declared `.custom` with no intent behind it, in an
  /// app that declares no `AppIntents` type at all -- an inert control on the single alert the whole
  /// product claim rests on. This codebase already states the rule it broke: "an inert control is
  /// worse than none" (NumericPad.swift). Nothing here is provable off-device, which is exactly why
  /// it is pinned as text: the file compiles to nothing on macOS, so no other test in this package
  /// can observe it.
  @Test("No alarm button is offered that the app has no intent to answer it with")
  func noInertAlarmSecondaryButton() throws {
    let source = try Self.code("Packages/HardsetKit/Sources/HardsetAlarm/RestAlarmService.swift")

    let buildsAnAlert = source.contains("AlarmPresentation.Alert(")
    #expect(buildsAnAlert, "The scan is vacuous if the alert construction left this file.")

    let declaresCustom = source.contains("secondaryButtonBehavior: .custom")
    let suppliesIntent = source.contains("secondaryIntent:")
    #expect(
      !declaresCustom || suppliesIntent,
      """
      `.custom` dispatches the alert's secondary button to `secondaryIntent`, which the timer \
      configuration defaults to nil. One without the other is a button that cannot do anything.
      """
    )
  }

  /// `commit` replaces the alarm rather than updating it, because AlarmKit has no update. Its one
  /// suspension is `schedule`, and the main actor is free across it -- so a set logged in that
  /// window runs `start`, which cancels an id that does not exist yet and then overwrites it,
  /// leaving the in-flight `schedule` to create an alarm for a finished rest that nothing holds the
  /// id of. It then fires in the middle of the following set. `start`'s own comment describes that
  /// orphan being fixed from the other direction; this is the same defect reached through the await.
  @Test("A superseded alarm is not left scheduled after the await it was created in")
  func commitCancelsASupersededAlarm() throws {
    let source = try Self.code(
      "Packages/HardsetKit/Sources/HardsetAlarm/RestTimerController.swift")

    let schedules = source.contains("try await RestAlarmService.schedule(")
    #expect(schedules, "The scan is vacuous if `commit` no longer schedules through this seam.")

    let guardsSupersession = source.contains("guard alarmID == id else")
    #expect(
      guardsSupersession,
      """
      `commit` must re-check that the alarm it just created is still the current one, and cancel it \
      if a newer rest superseded it while `schedule` was suspended.
      """
    )
  }

  // MARK: - Ink

  /// The sentences the planner's honesty rests on, identified by their own copy.
  ///
  /// `SplitCopyTests` already pins what these say. This pins that they can be read: `textTertiary`
  /// measures 4.35:1 against `surface` -- under the 4.5:1 WCAG AA floor for normal text -- and its
  /// own token comment scopes it to "disabled controls, decorative separators" under the rule "if a
  /// sentence matters it is at least `textSecondary`". Every string below, plus one enabled button
  /// label, was rendered in it: the attribution line the file's own comment calls "the attribution
  /// the whole app is built on", the caveat whose comment insists it "has to be readable", and the
  /// refusal HANDOFF points App Review at.
  /// `nonisolated` because `@Test(arguments:)` reads it from outside the actor: this package sets
  /// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so an ordinary `static let` here is main-actor
  /// isolated and the macro expansion cannot see it. The same leak HANDOFF section 9 records.
  nonisolated static let loadBearingCopy = [
    "Not attributed",
    "Not at the gym you are training at next",
    "No gym chosen",
    "Add machine",
    "these are not ranked and none is better than another.",
    "so this is a floor, not a total.",
    "No plan is graded.",
  ]

  @Test(
    "No load-bearing disclosure is rendered in ink that fails AA for normal text",
    arguments: loadBearingCopy
  )
  func disclosuresAreLegible(_ needle: String) throws {
    let source = try Self.code("Packages/HardsetKit/Sources/HardsetUI/SplitPlannerView.swift")

    guard let hit = source.range(of: needle) else {
      Issue.record("\"\(needle)\" is no longer in SplitPlannerView. Update this contract's copy.")
      return
    }
    let marker = ".foregroundStyle(Tokens.Color."
    guard let styled = source.range(of: marker, range: hit.upperBound..<source.endIndex) else {
      Issue.record("No `foregroundStyle` follows \"\(needle)\", so its ink cannot be checked.")
      return
    }

    let token = source[styled.upperBound...].prefix { $0.isLetter }
    #expect(
      token != "textTertiary",
      """
      "\(needle)" is styled `textTertiary` (4.35:1 on surface, below the 4.5:1 AA floor). \
      A sentence that matters is at least `textSecondary` -- the token's own rule.
      """
    )
  }

  // MARK: - Hit targets

  /// The `label:` closure body of every `Menu` in the two view modules.
  ///
  /// Brace-matched rather than regex-matched, the same technique `AffordanceWiringTests` uses and
  /// for the same reason: the closure spans lines and contains nested closures, so a non-greedy
  /// pattern stops at the first `}` inside it rather than at its end.
  static func menuLabelBodies() throws -> [(file: String, body: String)] {
    var found: [(String, String)] = []
    for module in ["HardsetUI", "HardsetFeature"] {
      let directory = repositoryRoot.appending(path: "Packages/HardsetKit/Sources/\(module)")
      let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)

      for name in names.sorted() where name.hasSuffix(".swift") {
        let text = try String(contentsOf: directory.appending(path: name), encoding: .utf8)
        var search = text.startIndex

        while let menu = text.range(of: "Menu {", range: search..<text.endIndex) {
          search = menu.upperBound
          guard
            let label = text.range(of: "} label: {", range: menu.upperBound..<text.endIndex)
          else { continue }

          var depth = 1
          var index = label.upperBound
          var end: String.Index?
          while index < text.endIndex {
            if text[index] == "{" { depth += 1 }
            if text[index] == "}" {
              depth -= 1
              if depth == 0 {
                end = index
                break
              }
            }
            index = text.index(after: index)
          }
          guard let end else { continue }
          found.append((name, String(text[label.upperBound..<end])))
        }
      }
    }
    return found
  }

  /// A menu's hit region is its *label's* content shape. A tap-target frame hung on the `Menu`
  /// instead therefore grows the layout footprint and leaves every added point untappable, so the
  /// glyph stays around 20 pt while the source reads as though it were 44. Two menus had it in the
  /// wrong place -- the only route to renaming or deleting a plan day, and the only route to
  /// renaming a machine, setting its stack step, or putting it away.
  ///
  /// `contentShape` is required alongside the frame, not instead of it: without it only the drawn
  /// glyph hit-tests and the declared 44 pt is still not what the finger has to find. Toolbar items
  /// and menu rows are excluded by construction -- both are system-sized, and neither is icon-only
  /// in this codebase.
  @Test("Every icon-only menu shapes a real tap target inside its own label")
  func menuLabelsCarryTheirTapTarget() throws {
    let bodies = try Self.menuLabelBodies()
    let iconOnly = bodies.filter {
      $0.body.contains("Image(systemName:") || $0.body.contains("labelStyle(.iconOnly)")
    }
    #expect(!iconOnly.isEmpty, "The scan is vacuous if it found no icon-only menu label at all.")

    let offenders = iconOnly.filter {
      !($0.body.contains("TapTarget") && $0.body.contains("contentShape("))
    }
    let named = offenders.map(\.file).joined(separator: ", ")
    #expect(
      offenders.isEmpty,
      """
      Icon-only menu labels must carry both a tap-target frame and a `contentShape` inside the \
      label closure. Offending file(s): \(named)
      """
    )
  }
}
