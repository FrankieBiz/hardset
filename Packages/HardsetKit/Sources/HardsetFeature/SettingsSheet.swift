import HardsetCore
import HardsetUI
import SwiftUI

/// The app's settings, currently one decision that genuinely cannot be inferred reliably.
///
/// Kept deliberately small. Anything the app can work out from behaviour — which gym, which
/// machine, how many sets a movement usually gets — is learned rather than asked, so it does not
/// belong here. The unit is different: it is a display preference with no behavioural signal, and
/// getting it wrong makes every number on screen wrong.
@MainActor
public struct SettingsSheet: View {
  @Binding private var useImperial: Bool
  private let onDone: () -> Void

  public init(useImperial: Binding<Bool>, onDone: @escaping () -> Void) {
    self._useImperial = useImperial
    self.onDone = onDone
  }

  public var body: some View {
    NavigationStack {
      Form {
        Section {
          Picker("Weight", selection: $useImperial) {
            Text(WeightUnit.kilograms.abbreviation).tag(false)
            Text(WeightUnit.pounds.abbreviation).tag(true)
          }
          .pickerStyle(.segmented)
        } header: {
          Text("Units")
        } footer: {
          // Stated because it is the reason switching never corrupts anything, and because a
          // lifter who has logged in one unit deserves to know the other view is a conversion,
          // not a re-entry.
          Text(
            "Every set is stored in kilograms, whichever you pick. Switching converts what you "
              + "see and changes nothing that was recorded."
          )
        }
      }
      .navigationTitle("Settings")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done", action: onDone)
        }
      }
    }
  }
}

#if DEBUG
  private struct SettingsHarness: View {
    @State private var useImperial = true
    var body: some View { SettingsSheet(useImperial: $useImperial) {} }
  }

  #Preview("Settings") { SettingsHarness() }
#endif
