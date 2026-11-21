import Foundation
import SQLiteData

extension Session.TableColumns {
  /// Whether a session counts as a workout the lifter did: it has ended, and it holds at least one
  /// working set.
  ///
  /// One rule, used wherever a finished session stands for "done": the saved-workout rotation and
  /// its last-done day, the "last time" a saved workout compares against, "Repeat last workout",
  /// and the workouts written to Apple Health. They had disagreed: Health required a working set,
  /// and the others counted any finished session. An accidental Start finished with nothing logged
  /// then moved the rotation on, took the place of the workout actually trained as the one to
  /// repeat, and was left out of Health, so the app said two things about one session.
  ///
  /// A workout of warm-ups only is not one either: warm-ups are not training volume, and starting
  /// on a saved workout and leaving after the bar has been warmed is not having done it.
  ///
  /// Nothing is deleted or hidden. The session stays in history with its sets; it is only not
  /// counted as a day the workout was done.
  nonisolated var isCounted: some QueryExpression<Bool> {
    finishedAt.isNot(nil) && LoggedSet.where { $0.sessionID.eq(id) && !$0.isWarmup }.exists()
  }
}
