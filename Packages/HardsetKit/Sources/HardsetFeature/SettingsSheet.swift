import HardsetCore
import HardsetUI
import HardsetStore
import SwiftUI

/// The app's settings, currently one decision that genuinely cannot be inferred reliably.
///
/// Kept deliberately small. Anything the app can work out from behaviour — which gym, which
/// machine, how many sets a movement usually gets — is learned rather than asked, so it does not
/// belong here. The unit is different: it is a display preference with no behavioural signal, and
/// getting it wrong makes every number on screen wrong.
///
/// Gyms and machines appear only to be corrected: the pickers learn them as they are added, but a
/// typo'd name or a gym the lifter has left would otherwise stay at the top of those lists forever.
///
/// Order follows what the lifter owns first: the unit every number is read in, where the workouts
/// live and how to take a copy, then the equipment they added, the methods, and last the optional
/// purchase.
///
/// The methodology disclosures sit here too, one tap away from anywhere in the app. They are not
/// settings, but this is the screen a lifter opens when they want to know how the app works, and
/// an app that claims calibrated honesty should not make its own limits hard to find.
@MainActor
public struct SettingsSheet: View {
  @Binding private var useImperial: Bool
  /// Which disclosure is open. One optional rather than a flag per row, so two can never be asked
  /// to present at once.
  @State private var disclosure: Disclosure?
  private let lifetime = LifetimeAccess.shared
  private let transfer: DataTransferStore?
  private let sync: SyncStatus?
  private let gyms: GymStore?
  private let onDataChanged: (() -> Void)?
  private let onDone: () -> Void

  /// - Parameters:
  ///   - gyms: When given, Settings offers renaming and removing gyms and machines.
  ///   - onDataChanged: Called after Settings changes saved data: an import that wrote workouts, or
  ///     a gym or machine renamed or removed. Screens showing that data re-read it.
  public init(
    useImperial: Binding<Bool>, transfer: DataTransferStore? = nil,
    sync: SyncStatus? = nil, gyms: GymStore? = nil,
    onDataChanged: (() -> Void)? = nil,
    onDone: @escaping () -> Void
  ) {
    self._useImperial = useImperial
    self.transfer = transfer
    self.sync = sync
    self.gyms = gyms
    self.onDataChanged = onDataChanged
    self.onDone = onDone
  }

  private var unit: WeightUnit { useImperial ? .pounds : .kilograms }

  public var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: Tokens.Spacing.block) {
          unitsSection
          // Where the workouts live, then how to take a copy: on a local-only build the export is
          // the only copy off this phone, so it sits near the top, above anything optional.
          if let sync { syncSection(sync) }
          if let transfer {
            DataPortabilitySection(
              store: transfer, unit: unit, isLocalOnly: sync == .localOnly,
              isDevelopmentBuild: lifetime.isDevelopmentBuild,
              onDataChanged: { onDataChanged?() })
          }
          if let gyms { gymsSection(gyms) }
          methodologySection
          // The optional purchase comes after everything the lifter already owns.
          LifetimePurchaseSection(access: lifetime)
        }
        .padding(.horizontal, Tokens.Spacing.loose)
        .padding(.top, Tokens.Spacing.loose)
        .padding(.bottom, Tokens.Spacing.block)
      }
      .scrollBounceBehavior(.basedOnSize)
      // The body-mass field's decimal pad has no return key; dragging the list puts it away.
      .scrollDismissesKeyboard(.interactively)
      .background(Tokens.Color.canvas)
      .hardsetNavigationTitle("Settings")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done", action: onDone)
        }
      }
      // Attached inside this sheet's own stack, so the disclosure presents over Settings rather
      // than competing with it for the presenting view.
      .sheet(item: $disclosure) { item in
        disclosureSheet(for: item)
          .hardsetSheet()
      }
    }
  }

  /// The set-counting disclosure is the one the Volume screen opens, built in one place, so what
  /// Settings says a certainty is about cannot differ from what the screen that shows it says.
  @ViewBuilder private func disclosureSheet(for item: Disclosure) -> some View {
    switch item {
    case .setCounting: MethodologySheet.setCounting()
    case .progression:
      if let source = item.source {
        MethodologySheet(source: source, certainty: item.certainty)
      }
    case .whatItWontSay: RefusalsSheet()
    }
  }

  // MARK: - Units

  private var unitsSection: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      SectionLabel("Units")

      VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
        VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
          Text("Weight")
            .font(Tokens.Text.headline)
            .foregroundStyle(Tokens.Color.chalk)
          Text("How loads are shown, and what typed numbers are read as.")
            .font(Tokens.Text.caption)
            .foregroundStyle(Tokens.Color.chalkDim)
            .fixedSize(horizontal: false, vertical: true)
        }

        HardsetSegmentedControl(
          selection: $useImperial,
          segments: [
            HardsetSegment(WeightUnit.kilograms.abbreviation, value: false),
            HardsetSegment(WeightUnit.pounds.abbreviation, value: true),
          ]
        )
        // Spoken as words, not "kg" and "lb": abbreviations are not reliably expanded, and the
        // "Weight" heading above is a separate element VoiceOver may not have just read.
        .accessibilityRepresentation {
          Picker("Weight unit", selection: $useImperial) {
            Text("Kilograms").tag(false)
            Text("Pounds").tag(true)
          }
          .pickerStyle(.segmented)
        }
      }
      .padding(Tokens.Spacing.loose)
      .frame(maxWidth: .infinity, alignment: .leading)
      .hardsetCard()

      // Stated because it is the reason switching never corrupts anything, and because a
      // lifter who has logged in one unit deserves to know the other view is a conversion,
      // not a re-entry.
      Text(
        "Every set is stored in kilograms, whichever you pick. Switching converts what you "
          + "see and changes nothing that was recorded."
      )
      .font(Tokens.Text.provenance)
      .foregroundStyle(Tokens.Color.chalkDim)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, Tokens.Spacing.tight)
    }
  }

  // MARK: - Sync

  /// Where the lifter's workouts live, stated rather than implied.
  ///
  /// A build signed without iCloud opens local-only, and nothing else on screen would tell the
  /// lifter that their history has no copy off this phone. "Set up" is as far as the enabled
  /// state claims: the engine exists, but whether an account is signed in and records have
  /// uploaded is CloudKit's to know, and the app does not guess.
  private func syncSection(_ sync: SyncStatus) -> some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      SectionLabel("iCloud")

      HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.regular) {
        Image(systemName: sync.isSyncing ? "icloud" : "iphone")
          .font(Tokens.Text.headline)
          .foregroundStyle(Tokens.Color.chalkDim)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
          Text(sync.isSyncing ? "iCloud sync is set up" : "Saved on this iPhone only")
            .font(Tokens.Text.headline)
            .foregroundStyle(Tokens.Color.chalk)
          // Sync, not backup, is what this build lacks; whether a device backup includes the
          // database is iOS's to say. A local-only build says plainly that its history is on this
          // phone, that an export is how to keep it, and that updating keeps it. Only a
          // development install adds that an update goes over the old app, because a free profile
          // expires and deleting the app is the natural reaction; an App Store or TestFlight
          // install has no such profile, so it is never told about one.
          VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
            ForEach(
              sync.isSyncing
                ? ["Workouts replicate to your private iCloud database while you are signed in to iCloud."]
                : DataSafetyCopy.localOnly(developmentBuild: lifetime.isDevelopmentBuild),
              id: \.self
            ) { paragraph in
              Text(paragraph)
                .font(Tokens.Text.caption)
                .foregroundStyle(Tokens.Color.chalkDim)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(Tokens.Spacing.loose)
      .frame(maxWidth: .infinity, alignment: .leading)
      .hardsetCard()
      .accessibilityElement(children: .combine)
    }
  }

  // MARK: - Gyms and machines

  private func gymsSection(_ gyms: GymStore) -> some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      SectionLabel("Gyms and machines")
      NavigationLink {
        GymManagementScreen(store: gyms, onChanged: { onDataChanged?() })
      } label: {
        HStack(spacing: Tokens.Spacing.regular) {
          VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
            Text("Rename or remove")
              .font(Tokens.Text.headline)
              .foregroundStyle(Tokens.Color.chalk)
            Text("Fix a misspelt name, or take a gym or machine out of the pickers for good. Logged sets stay in your history.")
              .font(Tokens.Text.caption)
              .foregroundStyle(Tokens.Color.chalkDim)
          }
          .multilineTextAlignment(.leading)
          .frame(maxWidth: .infinity, alignment: .leading)

          Image(systemName: "chevron.right")
            .font(Tokens.Text.caption.weight(.semibold))
            .foregroundStyle(Tokens.Color.chalkDim)
            .accessibilityHidden(true)
        }
      }
      .buttonStyle(DisclosureRowButtonStyle())
      .accessibilityHint("Opens your gyms and their machines")
    }
  }

  // MARK: - Methodology

  private var methodologySection: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      SectionLabel("How the numbers work")

      Text("The method behind each figure the app shows, and where it stops applying.")
        .font(Tokens.Text.provenance)
        .foregroundStyle(Tokens.Color.chalkDim)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Tokens.Spacing.tight)
        .padding(.bottom, Tokens.Spacing.tight)

      VStack(spacing: Tokens.Spacing.snug) {
        disclosureRow(.setCounting)
        disclosureRow(.progression)
        disclosureRow(.whatItWontSay)
      }

      // The Progress board's two marks, stated here as well as above its rows, because Settings is
      // where a lifter looks for how a figure is worked out.
      Text(ProgressCopy.comparisonAndRecordKey)
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.chalkDim)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Tokens.Spacing.tight)
        .padding(.top, Tokens.Spacing.tight)
    }
  }

  private func disclosureRow(_ item: Disclosure) -> some View {
    Button {
      disclosure = item
    } label: {
      HStack(spacing: Tokens.Spacing.regular) {
        VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
          // The row title: the source's own title where a source exists, so the row and the sheet
          // it opens cannot name it differently.
          Text(item.rowTitle)
            .font(Tokens.Text.headline)
            .foregroundStyle(Tokens.Color.chalk)
          Text(item.detail)
            .font(Tokens.Text.caption)
            .foregroundStyle(Tokens.Color.chalkDim)
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)

        Image(systemName: "chevron.right")
          .font(Tokens.Text.caption.weight(.semibold))
          .foregroundStyle(Tokens.Color.chalkDim)
          .accessibilityHidden(true)
      }
    }
    .buttonStyle(DisclosureRowButtonStyle())
    .accessibilityHint("Opens the method and its limits")
  }
}

/// The disclosures reachable from Settings.
///
/// Each method row renders an `EvidenceSource` that the arithmetic itself uses, so what is read
/// here cannot drift from what the app computes. The refusal sheet does the same through
/// `HonestyCopy`: its four rows are built from the sources behind them, and it discloses no single
/// source of its own.
///
/// `nonisolated` so its `Identifiable` conformance is an ordinary one: this target defaults to
/// `MainActor`, and a main-actor `id` cannot satisfy a nonisolated requirement.
private nonisolated enum Disclosure: Identifiable {
  case setCounting
  case progression
  case whatItWontSay

  var id: Disclosure { self }

  /// What the row is called. The source's own title wherever there is one; the refusal sheet's own
  /// title where the row opens a set of rules rather than one method.
  var rowTitle: String {
    switch self {
    case .setCounting: return SetCounting.source.title
    case .progression: return ProgressionAnalyzer.source.title
    case .whatItWontSay: return HonestyCopy.title
    }
  }

  /// The one method a row discloses, where the row is a method. The refusal sheet cites four
  /// sources in its rows instead of disclosing one, so it has none.
  var source: EvidenceSource? {
    switch self {
    case .setCounting: return SetCounting.source
    case .progression: return ProgressionAnalyzer.source
    case .whatItWontSay: return nil
    }
  }

  /// The best certainty a weekly count can reach, from the engine's own rule rather than a value
  /// written here. Load history states none, so none is invented; the refusal sheet states none.
  var certainty: Certainty? {
    switch self {
    case .setCounting: return VolumeAnalyzer.bestCertainty
    case .progression: return nil
    case .whatItWontSay: return nil
    }
  }

  /// Where the method is used, so the row says why it matters before it is opened.
  var detail: String {
    switch self {
    case .setCounting: return "How weekly volume credits each muscle"
    case .progression: return "How each machine's load chart is drawn"
    case .whatItWontSay: return "The claims the app refuses to make, and the rule behind each"
    }
  }
}

/// A full-width, outlined row that opens something.
///
/// Outlined with the measured control border rather than the decorative hairline, because the
/// boundary is what tells the lifter the row can be tapped. Pressed, it sinks to the pressed fill;
/// with Reduce Motion on, the scale is dropped and only the fill changes.
///
/// Shared with the published-page rows in Settings' "Your data" area, which open in the browser
/// rather than in place, so a row that opens anything looks the same wherever it sits.
struct DisclosureRowButtonStyle: ButtonStyle {
  func makeBody(configuration: ButtonStyleConfiguration) -> some View {
    DisclosureRowButtonBody(configuration: configuration)
  }
}

private struct DisclosureRowButtonBody: View {
  let configuration: ButtonStyleConfiguration

  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: Tokens.Radius.control)
    configuration.label
      .padding(.horizontal, Tokens.Spacing.loose)
      .padding(.vertical, Tokens.Spacing.regular)
      .frame(maxWidth: .infinity, minHeight: Tokens.loggerTapTarget, alignment: .leading)
      .background(
        configuration.isPressed ? Tokens.Color.steelPressed : Tokens.Color.steel,
        in: shape
      )
      .overlay {
        shape.strokeBorder(Tokens.Color.controlEdge, lineWidth: Tokens.Stroke.hairline)
      }
      .contentShape(shape)
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
      .opacity(isEnabled ? 1 : 0.4)
      .animation(Tokens.Motion.press, value: configuration.isPressed)
  }
}

#if DEBUG
  private struct SettingsHarness: View {
    @State private var useImperial = true
    var body: some View { SettingsSheet(useImperial: $useImperial) {} }
  }

  #Preview("Settings") { SettingsHarness() }
#endif
