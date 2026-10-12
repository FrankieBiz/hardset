import Foundation
import Testing

@testable import HardsetCore

@Suite("Every source says it in short, links its DOI, and keeps its methodology word for word")
struct EvidenceSummaryTests {
  @Test("Every shipped source has a one-sentence summary", arguments: EvidenceSource.shipped)
  func summaryIsOneSentence(source: EvidenceSource) throws {
    let summary = try #require(source.summary)
    #expect(!summary.isEmpty)
    #expect(summary.count <= 200)
    #expect(summary.hasSuffix("."))
    // One sentence: no full stop followed by a space anywhere before the end.
    #expect(!summary.dropLast().contains(". "))
  }

  @Test("No summary claims the weights were fitted or that the app is entitled to them")
  func summariesDoNotOverclaim() {
    for source in EvidenceSource.shipped {
      let summary = (source.summary ?? "").lowercased()
      #expect(!summary.contains("fitted"))
      #expect(!summary.contains("entitled"))
      #expect(!summary.contains("proven"))
    }
    let counting = SetCounting.source.summary ?? ""
    #expect(counting.contains("convention"))
    #expect(!counting.lowercased().contains("finding"))
  }

  @Test("Shipped sources have distinct ids")
  func distinctIDs() {
    #expect(Set(EvidenceSource.shipped.map(\.id)).count == EvidenceSource.shipped.count)
  }

  /// The methodology is what App Review reads, and spec §4 forbids editing it. A summary is a new
  /// field; this holds the old text to the character.
  @Test("The fractional-counting disclosure is unchanged, character for character")
  func countingTextUnchanged() {
    #expect(
      SetCounting.source.methodology == """
        A completed working set credits 1.0 set to each muscle labelled direct on the movement, \
        0.5 to each labelled indirect, and 0 to each labelled stabilising. The 1.0/0.5 split \
        follows the fractional scheme that best fitted 67 training studies in Pelland et al. \
        (2025). Those authors fixed the 0.5 weight in advance rather than estimating it from the \
        data, and describe it as an assumption and a heuristic; Hardset adopts it as a stated \
        convention. The 0 weight for stabilising and gripping muscles is Hardset's own convention \
        and is not part of the scheme that was tested.
        """)
    #expect(
      SetCounting.source.citation == """
        Pelland JC, Remmert JF, Robinson ZP, Hinson SR, Zourdos MC. Sports Med 2025. \
        DOI 10.1007/s40279-025-02344-w, PMID 41343037.
        """)
    #expect(
      SetCounting.source.validRange == """
        The scheme was compared against studies measuring eight sites: quadriceps and knee \
        extensors, rectus femoris, hamstrings and posterior thigh, pectoralis major, anterior \
        deltoid, trapezius, triceps brachii and elbow extensors, biceps brachii and elbow flexors. \
        Applying it to any other muscle is an extrapolation. Few studies examined more than about \
        25 fractional weekly sets, so counts above that fall outside the fitted range. No isometric \
        or stabilising contribution appears anywhere in the classification.
        """)
  }

  @Test("The other methodologies are unchanged, character for character")
  func otherTextsUnchanged() {
    #expect(
      VolumeAnalyzer.doseResponseSource.methodology == """
        Weekly fractional sets per muscle are placed against the dose-response relationship fitted \
        across 67 training studies. The best-fit form showed diminishing returns rather than an \
        inverted-U, but the credible intervals widen with volume and few studies examined more than \
        about 25 fractional weekly sets, so above that the app reports the count and declines to \
        say what an additional set buys.
        """)
    #expect(
      VolumeAnalyzer.targetSource.methodology == """
        Hardset does not publish a weekly set target for any muscle, because no such target is \
        established. What the literature supports is a dose-response relationship for eight \
        measured sites and a general finding that higher volumes tended to produce more growth. \
        The app therefore shows what you did and where it is empty, and does not tell you what \
        number you should have hit.
        """)
    #expect(
      StrengthMath.measuredSource.methodology
        == "A completed single at this load is reported directly. No estimation is involved.")
    #expect(
      StrengthMath.epleySource.methodology
        == "Estimated from a completed set as weight x (1 + reps / 30). This is a plan-structure "
        + "heuristic for comparing loads over time, not a measurement of maximal strength. "
        + "Accuracy falls as repetitions rise, so certainty is reduced above 6 repetitions "
        + "and no estimate is produced above 12.")
    #expect(
      ProgressionAnalyzer.source.methodology == """
        Each point is your best work in one session on one specific machine: the heaviest load you \
        moved, and where the rep counts allow it, the best estimated one-rep max. Sessions on \
        different machines are drawn as separate lines and never merged, because the same number on \
        different equipment is not the same effort.
        """)
  }

  @Test("The DOI links to doi.org, without the comma that follows it")
  func doiStopsAtPunctuation() {
    #expect(
      SetCounting.source.doiURL?.absoluteString == "https://doi.org/10.1007/s40279-025-02344-w")
    // Here the DOI ends the sentence, so it is followed by a full stop.
    #expect(
      VolumeAnalyzer.targetSource.doiURL?.absoluteString
        == "https://doi.org/10.1007/s40279-025-02344-w")
    let wrapped = EvidenceSource(
      id: "t", title: "t", methodology: "t", citation: "Someone (doi:10.1234/ab.cd)."
    )
    #expect(wrapped.doiURL?.absoluteString == "https://doi.org/10.1234/ab.cd")
  }

  @Test("A citation without a DOI gets no link")
  func noDOINoLink() {
    #expect(StrengthMath.epleySource.doiURL == nil)
    #expect(ProgressionAnalyzer.source.doiURL == nil)
    let version = EvidenceSource(
      id: "t", title: "t", methodology: "t", citation: "Version 10.2 of the manual, p. 3/4.")
    #expect(version.doiURL == nil)
  }

  @Test("Only a DOI makes a link: not a number that merely contains 10.")
  func doiNeedsTheDOIShape() {
    func url(_ citation: String) -> String? {
      EvidenceSource(id: "t", title: "t", methodology: "t", citation: citation).doiURL?.absoluteString
    }
    #expect(url("Smith 2025, DOI 10.1007/s40279-025-02344-w") == "https://doi.org/10.1007/s40279-025-02344-w")
    #expect(url("https://doi.org/10.1234/ab.cd") == "https://doi.org/10.1234/ab.cd")
    #expect(url("Smith 2010.5/6") == nil)
    #expect(url("see pp. 10.5/7") == nil)
    #expect(url("Registrant too short 10.123/abc") == nil)
  }

  @Test("The credit picture reads its numbers from the counting itself")
  func creditScheme() {
    let posix = Locale(identifier: "en_US_POSIX")
    let tiers = SetCounting.creditScheme(locale: posix)
    #expect(tiers.map(\.role) == [.direct, .indirect, .stabilizer])
    #expect(tiers.map(\.credit) == MuscleRole.allCases.map(SetCounting.weight))
    #expect(tiers.map(\.creditText) == ["1", "0.5", "0"])
    #expect(SetCounting.creditScheme(locale: Locale(identifier: "de_DE"))[1].creditText == "0,5")
  }

  /// `DECISIONS.md` §17: the 0.5 is an adopted convention, not an inherited finding.
  @Test("The half credit is called a convention, and the zero is Hardset's own")
  func creditBasisIsHonest() {
    let tiers = SetCounting.creditScheme(locale: Locale(identifier: "en_US_POSIX"))
    #expect(tiers[1].basis.contains("convention"))
    #expect(tiers[1].basis.contains("in advance"))
    #expect(!tiers[1].basis.lowercased().contains("fitted"))
    #expect(tiers[2].basis.contains("Hardset's own convention"))
    for tier in tiers {
      #expect(!tier.meaning.isEmpty)
    }
  }
}
