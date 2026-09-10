#if canImport(AlarmKit)

import ActivityKit
import AlarmKit
import Foundation
import HardsetCore
import SwiftUI

/// The AlarmKit seam.
///
/// ## The one concurrency rule that matters here
///
/// `AlarmManager.AlarmConfiguration` is the single type in AlarmKit's public surface that is
/// **not** `Sendable`, and `schedule(id:configuration:)` is a nonisolated `async` method.
/// Building the configuration on the main actor and then awaiting `schedule` sends a
/// main-actor-isolated non-Sendable value into a nonisolated context, which is a hard error in
/// Swift 6 language mode.
///
/// So the configuration is built and consumed inside the same `nonisolated` function and never
/// crosses an isolation boundary. `Task.detached` does not fix this -- it is what fails, since a
/// detached body cannot call a main-actor-isolated builder.
///
/// Verified by compiling (`swiftc -c`, not `-typecheck`) with `-swift-version 6
/// -default-isolation MainActor -warnings-as-errors`. Region-based isolation is enforced in
/// SIL, so `-typecheck` gives a false all-clear on exactly these errors.
public enum RestAlarmService {
  /// Everything AlarmKit needs that is safely `Sendable`.
  public struct Request: Sendable {
    public let id: UUID
    public let duration: Duration
    public let metadata: RestMetadata
    public let alertTitle: String
    public let tint: Color

    public init(
      id: UUID,
      duration: Duration,
      metadata: RestMetadata,
      alertTitle: String = "Rest complete",
      tint: Color = .accentColor
    ) {
      self.id = id
      self.duration = duration
      self.metadata = metadata
      self.alertTitle = alertTitle
      self.tint = tint
    }
  }

  /// Schedules a rest countdown.
  ///
  /// `nonisolated` is load-bearing, not decoration: it is what keeps the non-Sendable
  /// configuration inside one isolation domain.
  @discardableResult
  public nonisolated static func schedule(_ request: Request) async throws -> Alarm {
    // The 26.1 initialiser. The `stopButton:` overload is deprecated as of 26.1, which is
    // why the deployment target is 26.1 rather than 26.0.
    //
    // No secondary button, deliberately.
    //
    // This carried one reading "Skip" with `secondaryButtonBehavior: .custom`. `.custom` is the
    // case that dispatches to the configuration's `secondaryIntent`, and the SDK's
    // `timer(duration:attributes:stopIntent:secondaryIntent:sound:)` defaults that to nil -- which
    // is what it was, because this app declares no AppIntents type at all: `LiveActivityIntent`
    // appears nowhere in the repository. So the only interactive control on the app's flagship
    // alert had nothing behind it, and this codebase already states the rule for that -- "an inert
    // control is worse than none" (NumericPad.swift:169).
    //
    // `.countdown` is the only other case and it restarts the countdown, which is not what a button
    // labelled Skip means on an alert that fires *because* rest is already over. Restoring a real
    // secondary action means declaring a `LiveActivityIntent` in the app target and passing it as
    // `secondaryIntent:` here; until that exists the honest alert is its title plus the system's own
    // stop affordance. Nothing here is provable off-device -- see DEVICE-CHECKLIST.md section B.
    let alert = AlarmPresentation.Alert(
      title: LocalizedStringResource(stringLiteral: request.alertTitle)
    )

    let countdown = AlarmPresentation.Countdown(
      title: LocalizedStringResource(stringLiteral: request.metadata.setLabel),
      pauseButton: AlarmButton(text: "Pause", textColor: .white, systemImageName: "pause.fill")
    )

    let paused = AlarmPresentation.Paused(
      title: "Paused",
      resumeButton: AlarmButton(text: "Resume", textColor: .white, systemImageName: "play.fill")
    )

    let attributes = AlarmAttributes<RestMetadata>(
      presentation: AlarmPresentation(alert: alert, countdown: countdown, paused: paused),
      metadata: request.metadata,
      tintColor: request.tint
    )

    let configuration = AlarmManager.AlarmConfiguration.timer(
      duration: request.duration.seconds,
      attributes: attributes
    )

    return try await AlarmManager.shared.schedule(id: request.id, configuration: configuration)
  }

  /// AlarmKit needs no entitlement, but it does need `NSAlarmKitUsageDescription` in
  /// Info.plist -- without it scheduling fails at runtime.
  public nonisolated static func requestAuthorization() async throws -> Bool {
    try await AlarmManager.shared.requestAuthorization() == .authorized
  }

  /// Synchronous, and safe to call straight from main-actor code.
  ///
  /// Note there is no `await`: `authorizationState` is a plain property, and awaiting it
  /// produces a "no 'async' operations occur within 'await' expression" warning.
  public static var isAuthorized: Bool {
    switch AlarmManager.shared.authorizationState {
    case .authorized: true
    case .denied, .notDetermined: false
    // Required: the enum is resilient, so omitting this is a compile error.
    @unknown default: false
    }
  }

  public static func cancel(id: UUID) throws { try AlarmManager.shared.cancel(id: id) }
  public static func stop(id: UUID) throws { try AlarmManager.shared.stop(id: id) }
  public static func pause(id: UUID) throws { try AlarmManager.shared.pause(id: id) }
  public static func resume(id: UUID) throws { try AlarmManager.shared.resume(id: id) }
}

#endif  // canImport(AlarmKit)
