import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

/// What the app says each export is for is a claim, so it is checked against what the importer
/// does with the file. A format may say it restores only if its own export restores.
@Suite("Each export says what it is for, and the claim is true")
struct ExportFormatPurposeTests {
  private let strong = "Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,RPE,Notes\n2026-11-01 10:00:00,Push,1h 2m,Press,1,100,8,8,Keep this\n2026-11-01 10:00:00,Push,1h 2m,Press,2,100,7,,\n"

  private func populatedDatabase() async throws -> DatabaseQueue {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let db = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(db)
    _ = try await DataTransferStore(database: db).importWorkouts(
      WorkoutCSVImport.preview(strong, strongUnit: .kilograms, timeZone: TimeZone(secondsFromGMT: 0)!))
    return db
  }

  @Test("A format claims to restore exactly when the importer can read its own export")
  func claimMatchesTheImporter() async throws {
    let db = try await populatedDatabase()
    let store = DataTransferStore(database: db)
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    for format in DataTransferStore.Format.allCases {
      let url = try await store.export(format, directory: folder)
      let restores: Bool
      if let text = try? String(contentsOf: url, encoding: .utf8) {
        restores = (try? WorkoutCSVImport.preview(text, strongUnit: .kilograms))?.restore != nil
      } else {
        restores = false  // not text: the file picker and the importer only read text
      }
      #expect(restores == format.restoresIntoHardset, "\(format.displayName)")
    }
  }

  @Test("Copy never offers a restore from a format that has none")
  func copyDoesNotOverpromise() {
    for format in DataTransferStore.Format.allCases {
      let purpose = format.purpose.lowercased()
      let ready = format.readyMessage(fileName: "Hardset-2026-11-21.\(format.rawValue)").lowercased()
      if format.restoresIntoHardset {
        #expect(purpose.contains("read this file back in"), "\(format)")
        #expect(ready.contains("to restore"), "\(format)")
        #expect(!purpose.contains("can't"), "\(format)")
      } else {
        #expect(purpose.contains("can't read it back in"), "\(format)")
        #expect(ready.contains("can't restore"), "\(format)")
        #expect(!ready.contains("to restore, choose"), "\(format)")
      }
    }
  }

  @Test("The CSV's own copy says what it leaves out")
  func csvCopySaysWhatItLeavesOut() {
    let purpose = DataTransferStore.Format.csv.purpose
    #expect(purpose.contains("saved workouts"))
    #expect(purpose.contains("body mass"))
    #expect(purpose.contains("still open"))
  }
}
