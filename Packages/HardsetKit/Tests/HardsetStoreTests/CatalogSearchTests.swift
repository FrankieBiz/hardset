import Foundation
import GRDB
import HardsetCore
import Testing

@testable import HardsetStore

/// Search matched movement names only, on a list that is *grouped* by muscle and labelled with
/// equipment -- so the words a lifter can actually see were the words that found nothing.
@Suite("Movements are found by name, muscle or equipment")
struct CatalogSearchTests {
  let now = Date(timeIntervalSince1970: 12_000_000)

  private func seeded() throws -> CatalogSeeder {
    let queue = try DatabaseQueue()
    try HardsetMigrations.migrator().migrate(queue)
    let seeder = CatalogSeeder(database: queue)
    try seeder.seed(now: now)
    return seeder
  }

  @Test("A name still matches")
  func nameMatches() throws {
    let results = try seeded().search("bench")
    #expect(!results.isEmpty)
    #expect(results.allSatisfy { CatalogSeeder.matches($0, query: "bench") })
    #expect(results.contains { $0.name == "Barbell Bench Press" })
  }

  /// The headline case: the enum case is `quadriceps`, the word on screen is "Quads", and typing the
  /// word found nothing.
  @Test("A muscle name finds the movements that train it")
  func muscleMatches() throws {
    let results = try seeded().search("quads")
    #expect(!results.isEmpty, "searching a muscle found nothing")
    #expect(results.contains { $0.name == "Barbell Back Squat" })
  }

  /// Secondaries count, because the row already prints them under the name.
  @Test("An indirectly trained muscle finds the movement too")
  func indirectMuscleMatches() throws {
    let results = try seeded().search("triceps")
    // The bench press credits triceps indirectly and does not have the word in its name.
    #expect(results.contains { $0.name == "Barbell Bench Press" })
  }

  @Test("Equipment finds every movement loaded that way")
  func equipmentMatches() throws {
    let results = try seeded().search("bodyweight")
    #expect(!results.isEmpty, "searching equipment found nothing")
    #expect(results.allSatisfy { $0.modality == .bodyweight })
  }

  @Test("Matching is case- and diacritic-insensitive")
  func matchingIsInsensitive() throws {
    let seeder = try seeded()
    #expect(try !seeder.search("QUADS").isEmpty)
    #expect(try !seeder.search("Bódyweight").isEmpty)
  }

  /// Clearing the box restores the list rather than emptying it.
  @Test("An empty query returns everything")
  func emptyQueryReturnsAll() throws {
    let seeder = try seeded()
    let all = try seeder.search("")
    #expect(all.count > 50)
    #expect(try seeder.search("   ").count == all.count)
  }

  @Test("A query that matches nothing returns nothing rather than everything")
  func noMatchReturnsNothing() throws {
    #expect(try seeded().search("zzzzz").isEmpty)
  }
}
