import HardsetCore
import HardsetStore
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
  @Binding private var restSeconds: Int
  @Binding private var tracksRPE: Bool
  /// `nil` hides the bodyweight row entirely, the same rule the rest of the app follows: an
  /// affordance that opens a screen with no store behind it is worse than no affordance.
  private let bodyweight: BodyweightStore?
  private let unit: WeightUnit
  private let onDone: () -> Void

  /// Rest options the user can pick from. **Off is first and is the default**, because the app has
  /// no basis for prescribing a rest length: the literature does not give one, and inventing 90
  /// seconds would be exactly the kind of unearned prescription this app refuses elsewhere. What it
  /// can do is honour a choice the lifter makes, which is a different thing from making it for them.
  static let restOptions: [Int] = [0, 60, 90, 120, 180, 240]

  public init(
    useImperial: Binding<Bool>,
    restSeconds: Binding<Int>,
    tracksRPE: Binding<Bool>,
    bodyweight: BodyweightStore? = nil,
    unit: WeightUnit = .kilograms,
    onDone: @escaping () -> Void
  ) {
    self._useImperial = useImperial
    self._restSeconds = restSeconds
    self._tracksRPE = tracksRPE
    self.bodyweight = bodyweight
    self.unit = unit
    self.onDone = onDone
  }

  static func restLabel(_ seconds: Int) -> String {
    switch seconds {
    case 0: "Off"
    case ..<60: "\(seconds)s"
    default:
      seconds % 60 == 0
        ? "\(seconds / 60) min"
        : "\(seconds / 60) min \(seconds % 60)s"
    }
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


        Section {
          Picker("After a working set", selection: $restSeconds) {
            ForEach(Self.restOptions, id: \.self) { seconds in
              Text(Self.restLabel(seconds)).tag(seconds)
            }
          }
        } header: {
          Text("Rest timer")
        } footer: {
          // Says what it does and, more importantly, what it does not decide.
          Text(
            restSeconds == 0
              ? "No timer starts when you log a set. The app does not prescribe a rest length \u{2014} "
                + "pick one and it will hold you to it."
              : "A timer starts when you log a working set, never after a warm-up. It keeps "
                + "running if you leave the app or force-quit it."
          )
        }

        Section {
          Toggle("Record RPE", isOn: $tracksRPE)
        } header: {
          Text("Effort")
        } footer: {
          // Says what it does and, as everywhere else, what it refuses to do.
          Text(
            "Adds an optional effort field to every set, on the 1\u{2013}10 scale. Off by default, "
              + "because a field nobody fills is clutter in the one place this app cannot afford "
              + "it. The app records what you enter and nothing more \u{2014} there is no target "
              + "RPE and no warning for being far from failure, because neither is established."
          )
        }
        if let bodyweight {
          Section {
            NavigationLink {
              BodyweightScreen(store: bodyweight, unit: unit)
                .navigationTitle("Bodyweight")
            } label: {
              Label("Bodyweight", systemImage: "scalemass")
            }
          } header: {
            Text("You")
          } footer: {
            // The two things a lifter needs before typing a weight in: what it is used for, and
            // where it goes.
            Text(
              "Kept on this device and never uploaded. Shown as a "
                + "\(BodyweightTrend.smoothingDays)-day average, because a single morning is "
                + "mostly food and water."
            )
          }
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
    @State private var restSeconds = 90
    @State private var tracksRPE = true
    var body: some View {
      SettingsSheet(
        useImperial: $useImperial, restSeconds: $restSeconds, tracksRPE: $tracksRPE
      ) {}
    }
  }

  #Preview("Settings") { SettingsHarness() }
#endif
