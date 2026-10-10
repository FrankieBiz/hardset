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
    /// Nil for a rest the app adopted from AlarmKit after a relaunch: the metadata lived only in
    /// memory, and a replacement alarm (after +15 s or a resume) must still be scheduled.
    public let metadata: RestMetadata?
    public let alertTitle: String
    public let tint: Color

    public init(
      id: UUID,
      duration: Duration,
      metadata: RestMetadata?,
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
    // The 26.1 initialiser, `init(title:secondaryButton:secondaryButtonBehavior:)`, with both
    // secondary parameters left at their documented `nil` defaults: the system supplies the stop
    // control, and "the secondary button is optional, you can choose to exclude it". The old
    // "Skip" button was `.custom` with no intent behind it, so it did nothing; a real one needs
    // an App Intent (Phase 4). The `stopButton:` overload is deprecated as of 26.1, which is why
    // the deployment target is 26.1 rather than 26.0.
    let alert = AlarmPresentation.Alert(
      title: LocalizedStringResource(stringLiteral: request.alertTitle)
    )

    let countdown = AlarmPresentation.Countdown(
      // "Rest" matches the widget's own fallback when the attributes carry no metadata.
      title: LocalizedStringResource(stringLiteral: request.metadata?.setLabel ?? "Rest"),
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
  ///
  /// Prompts only if the lifter has never been asked; otherwise it returns the stored answer.
  public nonisolated static func requestAuthorization() async throws
    -> RestTimerController.Authorization
  {
    let state = try await AlarmManager.shared.requestAuthorization()
    return mapped(state)
  }

  /// Synchronous, and safe to call straight from main-actor code.
  ///
  /// Note there is no `await`: `authorizationState` is a plain property, and awaiting it
  /// produces a "no 'async' operations occur within 'await' expression" warning.
  public nonisolated static var authorization: RestTimerController.Authorization {
    mapped(AlarmManager.shared.authorizationState)
  }

  private nonisolated static func mapped(
    _ state: AlarmManager.AuthorizationState
  ) -> RestTimerController.Authorization {
    switch state {
    case .authorized: .authorized
    case .denied: .denied
    case .notDetermined: .unknown
    // Required: the enum is resilient, so omitting this is a compile error. A state this build
    // does not know is treated as unasked, and asking again never prompts twice.
    @unknown default: .unknown
    }
  }

  /// Every alarm of this app's that the system still holds. A fired alarm leaves the list once
  /// it has been stopped.
  public nonisolated static func currentAlarms() throws -> [Alarm] {
    try AlarmManager.shared.alarms
  }

  /// Emits this app's full set of alarms whenever it changes. Documented to fire when an alarm
  /// alerts, snoozes or is dismissed; whether a pause or resume also emits is a Mac check.
  public nonisolated static func alarmUpdates() -> some AsyncSequence<[Alarm], Never> {
    AlarmManager.shared.alarmUpdates
  }

  /// What reconciliation needs from an alarm, and nothing it would have to guess.
  ///
  /// `Alarm` exposes only `id`, `state`, `countdownDuration` and `schedule`. None of them is a
  /// running timer's fire date or a paused timer's remainder: `countdownDuration` is the length
  /// the alarm was configured with, not what is left, and a timer has no `schedule` because it
  /// starts counting at once. So countdowns and pauses carry `nil`, and `RestReconciler`
  /// takes those from what the app wrote down, or ends the rest when nothing was written.
  public nonisolated static func snapshot(of alarm: Alarm) -> AlarmSnapshot {
    let mode: AlarmSnapshot.Mode
    switch alarm.state {
    case .countdown:
      mode = .countdown(fireDate: nil)
    case .paused:
      mode = .paused(remaining: nil)
    case .alerting:
      mode = .alerting
    case .scheduled:
      // Not counting yet. Only a one-shot `.fixed` schedule names its alert time outright; a
      // relative schedule would need its next occurrence computed, and that is a guess.
      if case .fixed(let fireDate)? = alarm.schedule {
        mode = .countdown(fireDate: fireDate)
      } else {
        mode = .countdown(fireDate: nil)
      }
    // Required: the enum is resilient. An unknown state is treated as an alarm that will still
    // ring, with nothing about it read.
    @unknown default:
      mode = .countdown(fireDate: nil)
    }
    return AlarmSnapshot(id: alarm.id, mode: mode)
  }

  /// Cancels an alarm, unless the system is presenting its alert.
  ///
  /// The one alarm Hardset must never silence is the one telling the lifter the rest is over,
  /// and `cancel(id:)` would do exactly that. Every cancel the controller makes for its own
  /// reasons comes through here; the system removes an alerting alarm once it is dismissed. An
  /// alarm that no longer exists needs no cancelling.
  public static func cancelUnlessAlerting(id: UUID) throws {
    guard let alarm = try AlarmManager.shared.alarms.first(where: { $0.id == id }),
      alarm.state != .alerting
    else { return }
    try AlarmManager.shared.cancel(id: id)
  }

  public static func cancel(id: UUID) throws { try AlarmManager.shared.cancel(id: id) }
  public static func stop(id: UUID) throws { try AlarmManager.shared.stop(id: id) }
  public static func pause(id: UUID) throws { try AlarmManager.shared.pause(id: id) }
  public static func resume(id: UUID) throws { try AlarmManager.shared.resume(id: id) }
}

#endif  // canImport(AlarmKit)
