import Testing

@testable import HardsetUI

@Suite("Volume copy names the period it actually reports")
struct VolumeCopyTests {
  @Test("Working-set copy remains grammatical for the current and browsed windows")
  func workingSetCopy() {
    #expect(VolumeReportView.workingSetText(1, periodDescription: "this week") == "1 working set this week")
    #expect(
      VolumeReportView.workingSetText(4, periodDescription: "in this seven-day window")
        == "4 working sets in this seven-day window"
    )
  }

  @Test("Set copy does not carry an incorrect plural into a historic window")
  func setCopy() {
    #expect(VolumeReportView.setCountText(1) == "1 set")
    #expect(VolumeReportView.setCountText(2) == "2 sets")
  }

  /// The fractional counterpart, which VoiceOver alone reads: the visible row prints the bare
  /// number, so nothing on screen ever showed the noun and "1 sets" survived untested.
  ///
  /// The whole-number cases are pinned exactly; the fractional one asserts only the noun, because
  /// the number is now formatted through the reader's locale and its separator is not the subject
  /// of this test.
  @Test("A single credited set is spoken in the singular")
  func spokenSetCopy() {
    #expect(VolumeReportView.spokenSetCount(1) == "1 set")
    #expect(VolumeReportView.spokenSetCount(2) == "2 sets")
    #expect(VolumeReportView.spokenSetCount(6.5).hasSuffix(" sets"))
    #expect(VolumeReportView.spokenSetCount(0) == "0 sets")
  }
}
