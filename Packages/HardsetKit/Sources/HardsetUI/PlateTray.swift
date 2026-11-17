import SwiftUI

/// One of the five competition plates, coloured by mass: the colours are a calibration standard
/// (red 25 kg, blue 20, yellow 15, green 10, white 5), and they are the same plate colours the rest
/// of the app uses to mean something.
public enum Plate: Int, CaseIterable, Sendable {
  case twentyFive = 25
  case twenty = 20
  case fifteen = 15
  case ten = 10
  case five = 5

  /// The plate's mass in kilograms. Plates are kilogram plates whatever unit the lifter reads.
  public var massKg: Double { Double(rawValue) }

  /// The plate colour. The 5 kg plate is "white", which here is chalk.
  var fill: Color {
    switch self {
    case .twentyFive: Tokens.Color.plateRed
    case .twenty: Tokens.Color.plateBlue
    case .fifteen: Tokens.Color.plateYellow
    case .ten: Tokens.Color.plateGreen
    case .five: Tokens.Color.chalk
    }
  }

  /// How tall the plate stands on the bar, in points, so a heavier plate reads larger.
  var barHeight: CGFloat {
    switch self {
    case .twentyFive: 118
    case .twenty: 106
    case .fifteen: 92
    case .ten: 76
    case .five: 60
    }
  }

  /// What VoiceOver calls it.
  var spokenName: String { "\(rawValue) kilogram plate" }
}

/// The five plates resting in their tray below the bar, each a 56 pt target.
///
/// Tapping a plate hands it to `onSelect`. The welcome bar also lifts a plate on an upward drag,
/// so a lifter can load it by throwing it up at the bar or by tapping it; either way the plate
/// goes to the bar.
public struct PlateTray: View {
  private let onSelect: (Plate) -> Void

  public init(onSelect: @escaping (Plate) -> Void) {
    self.onSelect = onSelect
  }

  public var body: some View {
    HStack(spacing: Tokens.Spacing.snug) {
      ForEach(Plate.allCases, id: \.rawValue) { plate in
        Button {
          onSelect(plate)
        } label: {
          PlateFace(plate: plate)
        }
        .buttonStyle(HardsetPressStyle())
        .simultaneousGesture(
          DragGesture(minimumDistance: 16).onEnded { value in
            if value.translation.height < -24 { onSelect(plate) }
          }
        )
        .accessibilityLabel(plate.spokenName)
        .accessibilityHint("Loads it on the bar")
      }
    }
    .frame(maxWidth: .infinity)
  }
}

/// A plate seen edge-on in the tray: its colour, with its mass stamped on it. The stamp is `canvas`
/// so it clears the plate fill in both appearances.
struct PlateFace: View {
  let plate: Plate

  var body: some View {
    RoundedRectangle(cornerRadius: Tokens.Radius.control)
      .fill(plate.fill)
      .frame(width: Tokens.loggerTapTarget, height: Tokens.loggerTapTarget)
      .overlay {
        Text("\(plate.rawValue)")
          .hardsetText(.figure)
          .foregroundStyle(Tokens.Color.canvas)
          .accessibilityHidden(true)
      }
      .contentShape(Rectangle())
  }
}

#if DEBUG
  #Preview("Plate tray") {
    PlateTray { _ in }
      .padding(Tokens.Spacing.loose)
      .background(Tokens.Color.canvas)
  }
#endif
