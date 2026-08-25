import Foundation
import Testing

/// Every place the movement picker appears offers the same way out of an empty result.
///
/// This exists because of the exact defect it now forbids. `ExercisePickerView` carries both create
/// affordances — a `+` toolbar item and an "Add it yourself" button on the empty state — and **both
/// are gated on `onCreate`**. The live session passed it. The planner passed nothing. So building a
/// plan and searching for a movement the catalogue lacks ended at "Nothing in the catalogue matches"
/// with no way forward, on a catalogue that is knowingly a third of its intended size.
///
/// That is this codebase's dominant defect shape, not a one-off: capability built in full, and one
/// call site forgetting the last hop. An optional closure is the worst-behaved version of it,
/// because the affordance looks present in the view's source while being invisible to the user, and
/// nothing in the type system objects.
///
/// Swept from disk rather than asserted against a count, so a *new* call site that forgets is
/// caught too — a count would pass the moment someone updated the number.
@Suite("Every movement picker offers a way out of an empty result")
struct AffordanceWiringTests {
  static let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // HardsetUITests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // HardsetKit
    .deletingLastPathComponent()  // Packages
    .deletingLastPathComponent()  // repository root

  /// The arguments of every `ExercisePickerView(...)` call in the wiring module, one string each.
  ///
  /// Balanced-paren scan rather than a regex: the argument list spans lines and contains nested
  /// calls and closures, and a non-greedy regex stops at the first `)` — which here is inside
  /// `MuscleKey(option)`, not at the end of the call.
  static func pickerCallSites() throws -> [(file: String, arguments: String)] {
    let directory = repositoryRoot.appending(path: "Packages/HardsetKit/Sources/HardsetFeature")
    let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    var found: [(String, String)] = []

    for name in names.sorted() where name.hasSuffix(".swift") {
      let text = try String(contentsOf: directory.appending(path: name), encoding: .utf8)
      var search = text.startIndex
      while let start = text.range(of: "ExercisePickerView(", range: search..<text.endIndex) {
        var depth = 0
        var index = text.index(before: start.upperBound)  // the opening paren
        var end = text.endIndex
        while index < text.endIndex {
          if text[index] == "(" { depth += 1 }
          if text[index] == ")" {
            depth -= 1
            if depth == 0 {
              end = index
              break
            }
          }
          index = text.index(after: index)
        }
        found.append((name, String(text[start.upperBound..<end])))
        search = end
      }
    }
    return found
  }

  @Test("The picker is wired somewhere, so an empty sweep cannot pass by finding nothing")
  func sweepFindsCallSites() throws {
    let sites = try Self.pickerCallSites()
    #expect(sites.count >= 2, "Expected the logger and the planner to both present the picker.")
  }

  /// The dead end itself. Without `onCreate` there is no `+` and no "Add it yourself", and a lifter
  /// whose gym has a machine the catalogue never heard of simply cannot proceed.
  @Test("Every call site passes onCreate, so 'nothing matches' is never the end")
  func everyCallSiteOffersCreation() throws {
    for site in try Self.pickerCallSites() {
      #expect(
        site.arguments.contains("onCreate:"),
        """
        \(site.file) presents ExercisePickerView without `onCreate`, so both create affordances \
        are hidden and a search that matches nothing is a dead end. Pass it.
        """
      )
    }
  }

  /// The same call site also omitted these, which is why the planner never showed the "At *your
  /// gym*" section the logger does. Both are facts — the lifter's own history and the building's
  /// inventory — so passing them is not the app recommending anything.
  @Test("Every call site passes the relevance the picker is built to show")
  func everyCallSitePassesRelevance() throws {
    for site in try Self.pickerCallSites() {
      for argument in ["recent:", "availableHere:", "gymName:"] {
        #expect(
          site.arguments.contains(argument),
          """
          \(site.file) presents ExercisePickerView without `\(argument)`, so that relevance \
          section silently never renders there.
          """
        )
      }
    }
  }
}
