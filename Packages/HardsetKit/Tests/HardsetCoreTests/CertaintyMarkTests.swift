import Foundation
import Testing

@testable import HardsetCore

@Suite("Certainty reads as a glyph and a word, and a caveat never looks like an error")
struct CertaintyMarkTests {
  @Test("Each level has its own glyph and its own word, so colour is never the only signal")
  func distinct() {
    let marks = Certainty.allCases.map(\.mark)
    #expect(Set(marks.map(\.symbolName)).count == Certainty.allCases.count)
    #expect(Set(marks.map(\.word)).count == Certainty.allCases.count)
    #expect(Set(marks.map(\.shortWord)).count == Certainty.allCases.count)
    for mark in marks {
      #expect(!mark.symbolName.isEmpty)
      #expect(!mark.word.isEmpty)
    }
  }

  @Test("The words are the ones the badge has always shown")
  func words() {
    #expect(Certainty.high.mark.word == "High confidence")
    #expect(Certainty.moderate.mark.word == "Moderate confidence")
    #expect(Certainty.low.mark.word == "Low confidence")
    #expect(Certainty.unevaluated.mark.word == "Not evaluated")
    #expect(Certainty.moderate.mark.shortWord == "Moderate")
  }

  @Test("Each level takes its own certainty colour, never a semantic one")
  func roles() {
    #expect(Certainty.high.mark.role == .certaintyHigh)
    #expect(Certainty.moderate.mark.role == .certaintyModerate)
    #expect(Certainty.low.mark.role == .certaintyLow)
    #expect(Certainty.unevaluated.mark.role == .certaintyUnevaluated)
    for certainty in Certainty.allCases {
      #expect(![.success, .record, .caution, .critical].contains(certainty.mark.role))
      #expect(certainty.mark.certainty == certainty)
    }
  }

  @Test("No certainty or caveat borrows an error's glyph")
  func noErrorGlyphs() {
    let glyphs = Certainty.allCases.map(\.mark.symbolName) + CaveatMark.all.map(\.symbolName)
    for glyph in glyphs {
      #expect(!glyph.hasPrefix("exclamationmark"))
      #expect(!glyph.hasPrefix("xmark"))
    }
  }

  @Test("Caveats are the tested grey, never orange")
  func caveatsAreGrey() {
    for caveat in CaveatMark.all {
      #expect(caveat.role == .certaintyUnevaluated)
      #expect(!caveat.word.isEmpty)
    }
    #expect(Set(CaveatMark.all.map(\.symbolName)).count == CaveatMark.all.count)
  }

  @Test("An inferred unit is stated in words, with its correction")
  func unitAssumption() {
    let pounds = Assumption.unitFromRegion(.pounds)
    #expect(pounds.label == "Weights in pounds, from your region")
    #expect(pounds.correctionPrompt == "Change the unit")
    #expect(Assumption.unitFromRegion(.kilograms).label == "Weights in kilograms, from your region")
    #expect(Assumption.borrowedFromOtherMachine.correctionPrompt == "Choose the machine you're on")
  }
}
