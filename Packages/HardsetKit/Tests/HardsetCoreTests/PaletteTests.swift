import Foundation
import Testing

@testable import HardsetCore

@Suite("Every colour that carries text is readable, and Increase Contrast reads better")
struct PaletteTests {
  @Test("WCAG contrast: black on white is 21:1, a colour on itself is 1:1")
  func formula() {
    let black = PaletteColor(hex: 0x000000)
    let white = PaletteColor(hex: 0xFFFFFF)
    #expect(abs(black.contrast(with: white) - 21) < 1e-9)
    #expect(abs(white.contrast(with: black) - 21) < 1e-9)
    let grey = PaletteColor(hex: 0x777777)
    #expect(abs(grey.contrast(with: grey) - 1) < 1e-9)
  }

  @Test("Hex decodes in RGB order")
  func hex() {
    let colour = PaletteColor(hex: 0xFF8000)
    #expect(colour.red == 1)
    #expect(abs(colour.green - 128.0 / 255) < 1e-12)
    #expect(colour.blue == 0)
  }

  @Test("Text colours meet 4.5:1 on cards and backgrounds, light and dark", arguments: Palette.Role.allCases)
  func standardContrast(role: Palette.Role) {
    let swatch = Palette.swatch(role)
    for ground in [Palette.surfaceLight, Palette.backgroundLight] {
      #expect(swatch.light.contrast(with: ground) >= Palette.minimumTextContrast)
    }
    for ground in [Palette.surfaceDark, Palette.backgroundDark] {
      #expect(swatch.dark.contrast(with: ground) >= Palette.minimumTextContrast)
    }
  }

  @Test("Increase Contrast variants meet 7:1", arguments: Palette.Role.allCases)
  func increasedContrast(role: Palette.Role) {
    let swatch = Palette.swatch(role)
    for ground in [Palette.surfaceLight, Palette.backgroundLight] {
      #expect(swatch.lightIncreasedContrast.contrast(with: ground) >= Palette.increasedTextContrast)
    }
    for ground in [Palette.surfaceDark, Palette.backgroundDark] {
      #expect(swatch.darkIncreasedContrast.contrast(with: ground) >= Palette.increasedTextContrast)
    }
  }

  @Test("Increase Contrast never reads worse than standard", arguments: Palette.Role.allCases)
  func increasedIsStronger(role: Palette.Role) {
    let swatch = Palette.swatch(role)
    #expect(
      swatch.lightIncreasedContrast.contrast(with: Palette.surfaceLight)
        > swatch.light.contrast(with: Palette.surfaceLight))
    #expect(
      swatch.darkIncreasedContrast.contrast(with: Palette.surfaceDark)
        > swatch.dark.contrast(with: Palette.surfaceDark))
  }

  @Test("Cards stand apart from the background in both modes")
  func cardSeparation() {
    #expect(Palette.surfaceLight.contrast(with: Palette.backgroundLight) >= 1.1)
    #expect(Palette.surfaceDark.contrast(with: Palette.backgroundDark) >= 1.1)
  }

  @Test("Semantic colours are their own tokens, not certainty under another name")
  func semanticsSeparate() {
    #expect(Palette.swatch(.success) != Palette.swatch(.certaintyHigh))
    #expect(Palette.swatch(.record) != Palette.swatch(.certaintyModerate))
    #expect(Palette.swatch(.caution) != Palette.swatch(.certaintyLow))
    #expect(Palette.swatch(.critical) != Palette.swatch(.certaintyLow))
  }
}
