import HardsetStore
import SwiftUI

extension EnvironmentValues {
  /// Where this launch's history lives, for the screens that should say so where a lifter meets it
  /// rather than only in Settings. Set once by the launch view from the environment the app opened
  /// with; `nil` where it is not known (a preview, a staged screen), and then a screen says nothing
  /// about it.
  @Entry var syncStatus: SyncStatus? = nil
}
