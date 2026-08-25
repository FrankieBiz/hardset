import Foundation
import Testing

/// Every extension of a `nonisolated` store type declares its isolation.
///
/// # The failure this prevents
///
/// `HardsetStore` is built with `.defaultIsolation(MainActor.self)`, which is why every store type
/// in it spells out `public nonisolated struct`. An **extension** that forgets the same word is
/// silently `@MainActor`, and the compiler says nothing: the type's API is then split across two
/// isolation domains, most of it callable from anywhere and part of it main-actor-only.
///
/// It does not fail at build time. It fails as **SIGTRAP with no message**, apparently *on entry*
/// to the function — so nothing logged inside it ever prints and the crash reads as though the call
/// site were at fault. The triggers are closures handed to the standard library (`filter`,
/// `sorted`); `map(\.someKeyPath)` and plain `for` loops do not trip it, because a key path carries
/// no isolation and a loop body is not a closure. That combination makes it look like a codegen bug
/// and sends you rewriting correct code, which is exactly what happened when `MachineLibrary.swift`
/// was written — hours of bisecting, and every "fix" only moved the symptom.
///
/// A one-word omission with no diagnostic and a misleading symptom is precisely what a sweep is
/// for.
@Suite("Store extensions never drift into MainActor by omission")
struct IsolationContractTests {
  static let storeSources = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // HardsetStoreTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // HardsetKit
    .appending(path: "Sources/HardsetStore")

  private static func sources() throws -> [(name: String, lines: [String])] {
    let names = try FileManager.default.contentsOfDirectory(atPath: storeSources.path)
    var found: [(String, [String])] = []
    for name in names.sorted() where name.hasSuffix(".swift") {
      let text = try String(contentsOf: storeSources.appending(path: name), encoding: .utf8)
      found.append((name, text.components(separatedBy: .newlines)))
    }
    return found
  }

  /// Types declared `nonisolated` in this module. Read from disk rather than listed, so a new
  /// store is covered the day it is written.
  static func nonisolatedTypes() throws -> Set<String> {
    var names: Set<String> = []
    for source in try sources() {
      for line in source.lines where line.hasPrefix("public nonisolated ") || line.hasPrefix("nonisolated ") {
        for keyword in ["struct ", "enum ", "final class ", "class "] {
          guard let range = line.range(of: keyword) else { continue }
          let name = line[range.upperBound...]
            .components(separatedBy: CharacterSet(charactersIn: " :{<"))
            .first ?? ""
          if !name.isEmpty { names.insert(name) }
          break
        }
      }
    }
    return names
  }

  @Test("The sweep finds the stores, so it cannot pass by finding nothing")
  func sweepFindsTypes() throws {
    let types = try Self.nonisolatedTypes()
    #expect(types.contains("GymStore"))
    #expect(types.contains("LoggerStore"))
    #expect(types.count >= 10)
  }

  /// Either the extension itself is `nonisolated`, or every member it declares is. Both spellings
  /// exist in this module and both are deliberate; what is forbidden is neither.
  @Test("Every extension of a nonisolated store type states its isolation")
  func extensionsStateTheirIsolation() throws {
    let types = try Self.nonisolatedTypes()

    for source in try Self.sources() {
      var index = 0
      while index < source.lines.count {
        let line = source.lines[index]
        defer { index += 1 }
        guard line.hasPrefix("extension ") else { continue }
        let extended = line.dropFirst("extension ".count)
          .components(separatedBy: CharacterSet(charactersIn: " :{<"))
          .first ?? ""
        guard types.contains(extended) else { continue }

        // The extension is unmarked (a `nonisolated extension` would not have matched the prefix),
        // so every member it declares must carry the word itself.
        var members: [String] = []
        var cursor = index + 1
        while cursor < source.lines.count, !source.lines[cursor].hasPrefix("}") {
          let member = source.lines[cursor].trimmingCharacters(in: .whitespaces)
          for keyword in ["func ", "var ", "init(", "subscript("] where member.contains(keyword) {
            // Only declarations at member indentation, not calls inside a body.
            if source.lines[cursor].hasPrefix("  ") && !source.lines[cursor].hasPrefix("   ") {
              members.append(member)
            }
            break
          }
          cursor += 1
        }

        let unmarked = members.filter { !$0.contains("nonisolated") }
        #expect(
          unmarked.isEmpty,
          """
          \(source.name): `extension \(extended)` is not `nonisolated`, and declares members that \
          are not either: \(unmarked.joined(separator: " | ")). \(extended) is a nonisolated type, \
          so this extension is silently @MainActor and will SIGTRAP with no message when one of \
          its closures runs off the main actor. Mark the extension `nonisolated extension \
          \(extended)`.
          """
        )
      }
    }
  }
}
