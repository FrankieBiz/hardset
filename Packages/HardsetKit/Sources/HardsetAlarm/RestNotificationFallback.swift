#if canImport(AlarmKit)

import Foundation
import HardsetCore
import UserNotifications

/// The end of a rest, announced by a plain local notification when alarms are off.
///
/// Weaker than an alarm, and not by choice: a notification does not break through Focus or the
/// silent switch. The time-sensitive level would help, but it needs an entitlement and is
/// deferred. It still beats a rest that ends in silence.
///
/// One fixed identifier, so there is never more than one: a request whose identifier matches a
/// pending one replaces it (`UNNotificationRequest.init(identifier:content:trigger:)`).
///
/// ## Concurrency
///
/// None of `UNUserNotificationCenter`, `UNNotificationRequest` or `UNMutableNotificationContent`
/// is documented as `Sendable`. So, as with `AlarmManager.AlarmConfiguration` in
/// `RestAlarmService`, each one is created and consumed inside a single `nonisolated` function,
/// and none is stored or used again after an `await`. `current()` is called afresh for each
/// request for the same reason.
nonisolated enum RestNotificationFallback {
  static let identifier = "hardset.rest"

  /// Asks for permission to show an alert and play a sound.
  ///
  /// Calling this on every rest still prompts only once: the system stores the first answer, and
  /// "subsequent calls to this method don't prompt the person again". It also picks up a change
  /// the lifter made in Settings since.
  ///
  /// - Returns: whether notifications are allowed.
  static func requestAuthorization() async throws -> Bool {
    try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
  }

  /// Schedules the notification `remaining` from now, replacing any pending one.
  static func schedule(after remaining: Duration, title: String, body: String) async throws {
    // The trigger's interval "must be greater than zero". A rest already over needs no alert.
    guard remaining.seconds > 0 else { return }
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = UNNotificationSound.default
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: remaining.seconds, repeats: false)
    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    try await UNUserNotificationCenter.current().add(request)
  }

  /// Removes the pending notification, if there is one. The center "processes requests serially
  /// in the order that the system initiates them", so a removal made after an `add` removes
  /// what that `add` scheduled, even if it has not finished.
  static func cancel() {
    UNUserNotificationCenter.current().removePendingNotificationRequests(
      withIdentifiers: [identifier])
  }
}

#endif  // canImport(AlarmKit)
