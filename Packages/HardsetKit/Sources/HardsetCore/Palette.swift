import Foundation

/// An sRGB colour as three 0...1 components.
///
/// The palette's numbers live in Core, not in `Tokens`, so the claim that text meets 4.5:1 is
/// tested on every run instead of eyeballed. `HardsetUI` turns these into SwiftUI colours and
/// adds nothing.
public struct PaletteColor: Hashable, Sendable {
  public let red: Double
  public let green: Double
  public let blue: Double

  public init(red: Double, green: Double, blue: Double) {
    self.red = red
    self.green = green
    self.blue = blue
  }

  public init(hex: UInt32) {
    self.init(
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255
    )
  }

  /// WCAG 2 relative luminance.
  public var relativeLuminance: Double {
    func linear(_ channel: Double) -> Double {
      channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
  }

  /// WCAG 2 contrast ratio, from 1 to 21.
  public func contrast(with other: PaletteColor) -> Double {
    let a = relativeLuminance
    let b = other.relativeLuminance
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)
  }
}

/// One role's colour in light and dark appearance, each with an Increase Contrast variant.
public struct PaletteSwatch: Hashable, Sendable {
  public let light: PaletteColor
  public let lightIncreasedContrast: PaletteColor
  public let dark: PaletteColor
  public let darkIncreasedContrast: PaletteColor

  public init(light: UInt32, lightIncreasedContrast: UInt32, dark: UInt32, darkIncreasedContrast: UInt32) {
    self.light = PaletteColor(hex: light)
    self.lightIncreasedContrast = PaletteColor(hex: lightIncreasedContrast)
    self.dark = PaletteColor(hex: dark)
    self.darkIncreasedContrast = PaletteColor(hex: darkIncreasedContrast)
  }
}

/// The app's colours that carry meaning.
///
/// Certainty colours and semantic colours are separate roles (spec 2.8). A record is not "high
/// confidence", and an error is not "low confidence". Using one for the other made a lower bound
/// look like a failure. Every role is legible as text on cards and on the background.
public enum Palette {
  public enum Role: String, CaseIterable, Sendable {
    case certaintyHigh, certaintyModerate, certaintyLow, certaintyUnevaluated
    case success, record, caution, critical
    /// Captions, labels and prior-performance notes: quieter than primary text, still 4.5:1.
    case secondaryText
  }

  /// WCAG 1.4.3 (AA) for body text.
  public static let minimumTextContrast = 4.5
  /// WCAG 1.4.6 (AAA), what Increase Contrast should reach.
  public static let increasedTextContrast = 7.0

  /// `#F2F2F7`, darker than before so a white card is visible on it in light mode.
  public static let backgroundLight = PaletteColor(hex: 0xF2F2F7)
  public static let backgroundDark = PaletteColor(red: 0.055, green: 0.055, blue: 0.063)
  public static let surfaceLight = PaletteColor(hex: 0xFFFFFF)
  public static let surfaceDark = PaletteColor(red: 0.110, green: 0.110, blue: 0.122)

  public static func swatch(_ role: Role) -> PaletteSwatch {
    switch role {
    case .certaintyHigh:
      PaletteSwatch(light: 0x1F7A3A, lightIncreasedContrast: 0x14592A, dark: 0x4FD17A, darkIncreasedContrast: 0x8BE8A8)
    case .certaintyModerate:
      PaletteSwatch(light: 0x7A5C00, lightIncreasedContrast: 0x5C4500, dark: 0xE6C229, darkIncreasedContrast: 0xF5DC6E)
    case .certaintyLow:
      PaletteSwatch(light: 0xA84300, lightIncreasedContrast: 0x7D3200, dark: 0xFF9F45, darkIncreasedContrast: 0xFFC48A)
    case .certaintyUnevaluated:
      PaletteSwatch(light: 0x5E5E66, lightIncreasedContrast: 0x46464D, dark: 0xA3A3AB, darkIncreasedContrast: 0xC8C8CF)
    case .success:
      PaletteSwatch(light: 0x1E7D46, lightIncreasedContrast: 0x155A32, dark: 0x5BD68E, darkIncreasedContrast: 0x98EBBB)
    case .record:
      PaletteSwatch(light: 0x4B3FD1, lightIncreasedContrast: 0x3A2FA8, dark: 0xA39BFF, darkIncreasedContrast: 0xC4BEFF)
    case .caution:
      PaletteSwatch(light: 0x8A4B00, lightIncreasedContrast: 0x683800, dark: 0xFFB357, darkIncreasedContrast: 0xFFD199)
    case .critical:
      PaletteSwatch(light: 0xC0262D, lightIncreasedContrast: 0x931C22, dark: 0xFF6B6B, darkIncreasedContrast: 0xFF9C9C)
    case .secondaryText:
      PaletteSwatch(light: 0x66666E, lightIncreasedContrast: 0x48484F, dark: 0x9E9EA6, darkIncreasedContrast: 0xC4C4CB)
    }
  }
}
