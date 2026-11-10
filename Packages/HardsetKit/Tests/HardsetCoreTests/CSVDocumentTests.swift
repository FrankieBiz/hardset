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

  /// A semicolon file comes from a comma-decimal locale, so callers need the same separator the
  /// decoder chose to know whether "82,5" can be a number.
  @Test("The separator the decoder uses is the one reported")
  func separator() {
    #expect(CSVDocument.separator(of: "a;b\n82,5;2\n") == ";")
    #expect(CSVDocument.separator(of: "a,b\n1;2,3\n") == ",")
    #expect(CSVDocument.separator(of: "\u{FEFF}a;b\n1;2\n") == ";")
    #expect(CSVDocument.separator(of: "\"a;b\",c\n1,2\n") == ",")
    #expect(CSVDocument.separator(of: "single\n1\n") == ",")
  }
}
