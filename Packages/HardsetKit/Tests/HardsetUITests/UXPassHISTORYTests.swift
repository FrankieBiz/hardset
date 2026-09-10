import HardsetCore
import Testing

@testable import HardsetUI

/// The two look-back sentences that count something.
///
/// Both pluralise by hand, because they are joined into a `String` and reach `Text(String)`, where
/// `^[...](inflect:)` renders verbatim -- so nothing but a test catches a missing "s". The suite
/// pinned `VolumeReportView`'s copy and not this line, which is how "3 warm-up" shipped.
@Suite("The history and summary lines say what they counted")
struct UXPassHISTORYTests {
  private func volume(warmups: Int = 0, drops: Int = 0) -> SessionVolume {
    SessionVolume(workingSets: 12, warmupSets: warmups, volumeKg: 9_400, reps: 96, dropSets: drops)
  }

  @Test("Warm-ups are pluralised like every other count on the row")
  func warmupPlural() {
    #expect(
      HistoryView.volumeText(volume(warmups: 1), unit: .kilograms).hasSuffix("1 warm-up")
    )
    #expect(
      HistoryView.volumeText(volume(warmups: 3), unit: .kilograms).hasSuffix("3 warm-ups")
    )
  }

  /// Drops were the one figure the row omitted while including their reps and tonnage in the two
  /// figures beside it, so the line read as more reps per set than were performed.
  @Test("Drops are named, and pluralised")
  func dropsAreNamed() {
    #expect(
      HistoryView.volumeText(volume(drops: 1), unit: .kilograms).hasSuffix("1 drop")
    )
    #expect(
      HistoryView.volumeText(volume(drops: 2), unit: .kilograms).hasSuffix("2 drops")
    )
  }

  /// A drop adds no set (HANDOFF invariant 11): naming it must not change the set count printed
  /// beside it.
  @Test("Naming a drop does not turn it into a set")
  func dropAddsNoSet() {
    #expect(HistoryView.volumeText(volume(drops: 2), unit: .kilograms).hasPrefix("12 sets"))
  }

  @Test("A session with neither is unchanged")
  func neitherPart() {
    let text = HistoryView.volumeText(volume(), unit: .kilograms)
    #expect(!text.contains("warm-up"))
    #expect(!text.contains("drop"))
  }

  /// A warm-up-only workout used to summarise as a row of zeroes, which reads as a measurement.
  /// The empty branch now has to say what actually happened instead of denying it.
  @Test("The summary's empty state names warm-ups when there were some")
  func emptyStateNamesWarmups() {
    #expect(
      SessionSummaryView.emptyStateText(warmupSets: 0)
        == "No sets were logged, so there is nothing to summarise."
    )
    #expect(
      SessionSummaryView.emptyStateText(warmupSets: 1)
        == "No working sets were logged. 1 warm-up set was."
    )
    #expect(
      SessionSummaryView.emptyStateText(warmupSets: 3)
        == "No working sets were logged. 3 warm-up sets were."
    )
  }
}
