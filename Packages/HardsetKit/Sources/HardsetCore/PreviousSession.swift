import Foundation

/// The earlier session used by both the live row and the receipt: the one with the most recent
/// completed working set on the same movement/equipment. A session's first set can precede work
/// in another session, so its start is not the rule. Equal timestamps choose the greater session
/// UUID, never a set UUID or dictionary iteration order. Callers exclude the current session,
/// warm-ups, imported equipment and other machines before selecting.
public enum PreviousSession {
  public static func latest(
    in workingSets: [(sessionID: SessionID, completedAt: Date)]
  ) -> SessionID? {
    workingSets.max {
      if $0.completedAt != $1.completedAt { return $0.completedAt < $1.completedAt }
      return $0.sessionID.rawValue.uuidString < $1.sessionID.rawValue.uuidString
    }?.sessionID
  }
}
