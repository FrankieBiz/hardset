import Foundation
import Testing

@testable import HardsetCore

/// The rest payload is archived into the device journal and into the Live Activity, so a field
/// added later must not make an older saved rest unreadable.
@Suite("Rest metadata stays readable as it grows")
struct RestMetadataTests {
  @Test("A rest saved before its total was recorded still decodes")
  func decodesWithoutTotal() throws {
    let json = Data(#"{"exerciseName":"Press","setOrdinal":2,"machineName":"Cybex"}"#.utf8)
    let metadata = try JSONDecoder().decode(RestMetadata.self, from: json)
    #expect(metadata == RestMetadata(exerciseName: "Press", setOrdinal: 2, machineName: "Cybex"))
    #expect(metadata.totalRest == nil)
  }

  @Test("The total rest round trips with the rest of the payload")
  func roundTrip() throws {
    let metadata = RestMetadata(exerciseName: "Press", setOrdinal: 2, plannedSets: 4,
      machineName: "Cybex", totalRest: .seconds(105))
    let decoded = try JSONDecoder().decode(RestMetadata.self, from: JSONEncoder().encode(metadata))
    #expect(decoded == metadata)
    #expect(decoded.totalRest == .seconds(105))
  }

  @Test("Recording a total changes nothing else")
  func withTotalRest() {
    let metadata = RestMetadata(exerciseName: "Press", setOrdinal: 2, plannedSets: 4, machineName: "Cybex")
    let counted = metadata.withTotalRest(.seconds(90))
    #expect(counted.totalRest == .seconds(90))
    #expect(counted.withTotalRest(nil) == metadata)
    #expect(counted.setLabel == metadata.setLabel)
  }
}
