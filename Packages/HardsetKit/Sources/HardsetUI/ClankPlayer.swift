import SwiftUI

#if canImport(CoreHaptics)
  import CoreHaptics
#endif
#if canImport(UIKit)
  import UIKit
#endif

/// Plays `clank`: the weighty tap of a plate meeting a bar.
///
/// A sharp transient at full intensity and a sharpness of 0.6, then a 40 ms low rumble, so it
/// feels like iron landing rather than the generic system tick. The system's `SensoryFeedback`
/// vocabulary cannot be played on demand outside a view's trigger, which is why the welcome bar and
/// the pitch demo play this directly. Where CoreHaptics is unavailable, such as the Simulator and
/// devices without a haptic engine, it falls back to the heavy system impact, which is also what
/// `Tokens.Haptic.clank` names for a view that plays it through `.sensoryFeedback`.
///
/// Failure is silent on purpose: a haptic is a flourish, and a lifter must never see an error, or
/// lose a tap, because the engine could not start. A failed engine is dropped so the next play
/// builds a fresh one.
@MainActor
public final class ClankPlayer {
  public static let shared = ClankPlayer()

  #if canImport(CoreHaptics)
    private var engine: CHHapticEngine?
  #endif

  public init() {}

  /// Plays the pattern, or the fallback impact when the pattern cannot play.
  public func play() {
    #if canImport(CoreHaptics)
      if playPattern() { return }
    #endif
    playFallback()
  }

  #if canImport(CoreHaptics)
    private func playPattern() -> Bool {
      guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return false }
      do {
        let engine = try self.engine ?? CHHapticEngine()
        self.engine = engine
        try engine.start()
        let transient = CHHapticEvent(
          eventType: .hapticTransient,
          parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6),
          ],
          relativeTime: 0)
        let rumble = CHHapticEvent(
          eventType: .hapticContinuous,
          parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.35),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.1),
          ],
          relativeTime: 0.01, duration: 0.04)
        let pattern = try CHHapticPattern(events: [transient, rumble], parameters: [])
        let player = try engine.makePlayer(with: pattern)
        try player.start(atTime: CHHapticTimeImmediate)
        return true
      } catch {
        engine = nil
        return false
      }
    }
  #endif

  private func playFallback() {
    #if canImport(UIKit) && !os(watchOS)
      UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 1.0)
    #endif
  }
}
