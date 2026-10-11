#if canImport(AlarmKit)

import Foundation
import UserNotifications

/// Presents the rest notification while Hardset is in front.
///
/// The fallback notification stands in for the alarm when alarms are off, and the lifter it
/// serves is often still looking at the app when the rest ends. Without a delegate saying how
/// to present a notification that arrives in the foreground, it may not show or sound at all.
///
/// The app must keep one alive and assign it to `UNUserNotificationCenter.current().delegate`
/// before it finishes launching. The property is `weak`, and Apple asks for it to be set by
/// then.
///
/// `nonisolated` and `Sendable` because the center calls its delegate from its own queue. It
/// holds no state, so that is safe.
public nonisolated final class RestNotificationPresenter:
  NSObject, UNUserNotificationCenterDelegate, Sendable
{
  public override init() { super.init() }

  /// The rest notification shows as a banner with its sound. Anything else gets the behaviour
  /// of a delegate that does not implement this method: not presented in the foreground.
  ///
  /// The completion-handler form, with the documented `@escaping @Sendable` handler. This is an
  /// optional requirement, so a signature that only nearly matched would compile and then never
  /// be called.
  public func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler:
      @escaping @Sendable (UNNotificationPresentationOptions) -> Void
  ) {
    let isRest = notification.request.identifier == RestNotificationFallback.identifier
    completionHandler(isRest ? [.banner, .sound] : [])
  }
}

#endif  // canImport(AlarmKit)
