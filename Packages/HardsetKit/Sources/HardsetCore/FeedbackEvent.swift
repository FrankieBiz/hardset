import Foundation

/// The things worth a haptic, named here so the UI only maps them and decides nothing.
///
/// Four, on purpose. The HIG asks for restraint on frequent actions, and the spec gives the app
/// exactly one celebratory moment: a record (spec §3, items 4, 5 and 7).
public enum FeedbackEvent: Hashable, Sendable {
  case log
  case record
  case error
  case restAdjust

  /// The single event a successful log produces. A record set plays only the record haptic, so
  /// the moment is distinct rather than a log haptic with something added.
  public static func afterLogging(records: [PersonalRecord]) -> FeedbackEvent {
    records.isEmpty ? .log : .record
  }
}

/// One occurrence of an event.
///
/// The sequence number makes two identical events in a row two different values, which is what
/// a `sensoryFeedback(trigger:)` needs to fire twice. `slotID` names the row it is about, so the
/// screen can bounce that row's trophy and find what to announce.
public struct FeedbackPulse: Hashable, Sendable {
  public let event: FeedbackEvent
  public let sequence: Int
  public let slotID: UUID?

  public init(event: FeedbackEvent, sequence: Int, slotID: UUID? = nil) {
    self.event = event
    self.sequence = sequence
    self.slotID = slotID
  }

  public static func following(
    _ previous: FeedbackPulse?, event: FeedbackEvent, slotID: UUID? = nil
  ) -> FeedbackPulse {
    FeedbackPulse(event: event, sequence: (previous?.sequence ?? 0) + 1, slotID: slotID)
  }
}
