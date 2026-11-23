import Foundation

/// The log tap as one event, written down as data so it can be tested and cannot drift.
///
/// Logging a set used to be three things that happened near each other: a spring on the seal, two
/// haptics at once, and a rest bar that cut in at full strength while a record card faded in on a
/// different clock. This names the one moment they are parts of, in two beats.
///
/// **Contact** is the instant the write has succeeded and the row is marked logged. The clank, the
/// seal's stamp, the figures going to full chalk and the screen's one accent moving on all begin in
/// that same frame. Nothing before it: the row is only marked logged after the store has written the
/// set (`SessionCoordinator.logSet`), so a failed write has no contact and no haptic.
///
/// **Follow** is what the log means, arriving a moment after the stamp has landed: the "+1 rep" mark,
/// the rest bar and the record notice fade in together, on one delay. They are information about the
/// set rather than the set being stamped, so they wait for the stamp instead of competing with it,
/// and the whole moment reads as one gesture, contact then consequence, about 0.4 s end to end.
///
/// With Reduce Motion there is one beat and nothing travels: the seal, the mark, the rest bar and the
/// notice appear instantly and together, and the haptic is unchanged, because it carries the meaning
/// that the motion no longer does. `plan(reduceMotion:)` is the whole contract; the interface reads
/// its delays and durations from here, so a number changed in one place is changed in both.
///
/// Nothing else in the app may be this theatrical. That is what makes the moment a signature, and
/// `DESIGN.md` says so beside the motion tokens.
public enum LogMoment {
  /// The two beats of the moment, in order.
  public enum Beat: Int, Sendable, Comparable, CaseIterable {
    case contact
    case follow

    public static func < (lhs: Beat, rhs: Beat) -> Bool { lhs.rawValue < rhs.rawValue }
  }

  /// Everything that takes part. A part not listed here is not part of the moment, and a part is
  /// listed once.
  public enum Part: String, Sendable, CaseIterable {
    /// The clank: the one haptic of a saved set.
    case haptic
    /// The log control's seal, stamping in.
    case seal
    /// The row's figures going from dimmed to full chalk.
    case figures
    /// The screen's one accent, handed to the next set that can be logged.
    case accent
    /// "+1 rep", "Matched": how the set compares with last time on this machine.
    case beatMark
    /// The rest countdown and its controls.
    case restBar
    /// The record notice, when the set earned one.
    case records
    /// The one-time line saying a saved figure can be tapped to correct it.
    case correctionHint
  }

  /// How a part arrives.
  public enum Style: Sendable, Equatable {
    /// Felt, not seen.
    case played
    /// A cut: the state changes in the frame and nothing travels.
    case instant
    /// The stamp's spring, on the seal and nowhere else.
    case spring
    /// An insertion-only opacity reveal. Layout never animates.
    case fade
  }

  /// One part, when it starts and how it arrives.
  public struct Step: Sendable, Equatable {
    public let part: Part
    public let beat: Beat
    public let style: Style
    /// Seconds after contact that the part starts.
    public let delay: TimeInterval
    /// Seconds the part takes, zero for a cut or a haptic.
    public let duration: TimeInterval

    /// When the part has finished, measured from contact.
    public var end: TimeInterval { delay + duration }
  }

  /// The stamp's spring, in seconds. `Tokens.Motion.stamp` is built from this.
  public static let sealDuration: TimeInterval = 0.3

  /// The reveal's ease-out, in seconds. `Tokens.Motion.reveal` is built from this.
  public static let revealDuration: TimeInterval = 0.28

  /// How long the follow beat waits after contact. Long enough that the seal has nearly reached its
  /// full size when the consequence begins to fade in, so the eye lands on the stamp first, and short
  /// enough that the two overlap and read as one event rather than a stamp and then a separate
  /// message. `Tokens.Motion.follow` is built from this.
  public static let followDelay: TimeInterval = 0.12

  /// No part of the moment may take longer than this from contact, with motion. The stamp and the
  /// follow beat overlap inside it.
  public static let settleCeiling: TimeInterval = 0.45

  /// Whether a row's logged flag changing is the contact: false to true, which only happens after
  /// the write succeeded. True to false is an undo and has no moment, and a row that appears already
  /// logged, such as a recovered workout, never changes at all and so plays nothing.
  public static func isContact(from wasLogged: Bool, to isLogged: Bool) -> Bool {
    !wasLogged && isLogged
  }

  /// The moment, part by part.
  ///
  /// - Parameter reduceMotion: The lifter's Reduce Motion setting. Everything that moved becomes an
  ///   instant change at contact; the haptic is the same.
  public static func plan(reduceMotion: Bool) -> [Step] {
    if reduceMotion {
      return Part.allCases.map { part in
        Step(
          part: part, beat: .contact, style: part == .haptic ? .played : .instant, delay: 0,
          duration: 0)
      }
    }
    return [
      Step(part: .haptic, beat: .contact, style: .played, delay: 0, duration: 0),
      Step(part: .seal, beat: .contact, style: .spring, delay: 0, duration: sealDuration),
      Step(part: .figures, beat: .contact, style: .instant, delay: 0, duration: 0),
      Step(part: .accent, beat: .contact, style: .instant, delay: 0, duration: 0),
      Step(part: .beatMark, beat: .follow, style: .fade, delay: followDelay, duration: revealDuration),
      Step(part: .restBar, beat: .follow, style: .fade, delay: followDelay, duration: revealDuration),
      Step(part: .records, beat: .follow, style: .fade, delay: followDelay, duration: revealDuration),
      Step(
        part: .correctionHint, beat: .follow, style: .fade, delay: followDelay,
        duration: revealDuration),
    ]
  }
}
