import Foundation
import Testing
@testable import HardsetCore

@Suite("Lossless CSV fields")
struct CSVDocumentTests {
  @Test("Quoted commas, quotes, multiline fields, BOM and empty columns")
  func roundTrip() throws {
    let rows = [["Name", "Notes", "Empty"], ["Press, seated", "Say \"go\"\nNext line", ""]]
    #expect(try CSVDocument.decode("\u{FEFF}" + CSVDocument.encode(rows)) == rows)
    #expect(try CSVDocument.decode("a;b;c\r\n1;2;\r\n") == [["a", "b", "c"], ["1", "2", ""]])
  }
  @Test("Malformed quotes never silently alter cells", arguments: ["a\n\"unfinished", "a\nvalue\"", "a\n\"closed\"x"])
  func malformed(_ text: String) {
    #expect(throws: CSVError.self) { try CSVDocument.decode(text) }
  }
}
