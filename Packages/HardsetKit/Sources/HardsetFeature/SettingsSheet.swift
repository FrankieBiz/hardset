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
/// live and how to take a copy, then the equipment they added, the optional Health link, the
/// methods, and last the optional purchase.
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
  private let health: DeviceHealthStore?
  private let transfer: DataTransferStore?
  private let sync: SyncStatus?
  private let gyms: GymStore?
  private let onDataChanged: (() -> Void)?
  private let onDone: () -> Void

  /// - Parameters:
  ///   - gyms: When given, Settings offers renaming and archiving gyms and machines.
  ///   - onDataChanged: Called after Settings changes saved data: an import that wrote workouts, or
  ///     a gym or machine renamed or archived. Screens showing that data re-read it.
  public init(
    useImperial: Binding<Bool>, transfer: DataTransferStore? = nil,
    health: DeviceHealthStore? = nil, sync: SyncStatus? = nil, gyms: GymStore? = nil,
    onDataChanged: (() -> Void)? = nil, onDone: @escaping () -> Void
  ) {
    self._useImperial = useImperial
    self.health = health
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
            DataPortabilitySection(store: transfer, unit: unit, onDataChanged: { onDataChanged?() })
          }
          if let gyms { gymsSection(gyms) }
          #if os(iOS)
          if let health { HealthSettingsSection(store: health, unit: unit) }
          #endif
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
      .background(Tokens.Color.background)
      .hardsetNavigationTitle("Settings")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done", action: onDone)
        }
      }
      // Attached inside this sheet's own stack, so the disclosure presents over Settings rather
      // than competing with it for the presenting view.
      .sheet(item: $disclosure) { item in
        MethodologySheet(source: item.source, certainty: item.certainty)
          .hardsetSheet()
      }
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
            .foregroundStyle(Tokens.Color.textPrimary)
          Text("How loads are shown, and what typed numbers are read as.")
            .font(Tokens.Text.caption)
            .foregroundStyle(Tokens.Color.textSecondary)
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
      .foregroundStyle(Tokens.Color.textSecondary)
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
          .foregroundStyle(Tokens.Color.textSecondary)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
          Text(sync.isSyncing ? "iCloud sync is set up" : "Saved on this iPhone only")
            .font(Tokens.Text.headline)
            .foregroundStyle(Tokens.Color.textPrimary)
          Text(
            sync.isSyncing
              ? "Workouts replicate to your private iCloud database while you are signed in "
                + "to iCloud."
              // Sync, not backup, is what this build lacks; whether a device backup includes the
              // database is iOS's to say. An export is a readable copy, not a restore point.
              : "This build can't use iCloud sync, so workouts stay on this iPhone and don't reach "
                + "your other devices. Deleting Hardset deletes them. An export below is a readable "
                + "copy to keep elsewhere; Hardset can't restore from it."
          )
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
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
            Text("Rename or archive")
              .font(Tokens.Text.headline)
              .foregroundStyle(Tokens.Color.textPrimary)
            Text("Fix a misspelt name, or retire a gym or machine. Logged sets stay in your history.")
              .font(Tokens.Text.caption)
              .foregroundStyle(Tokens.Color.textSecondary)
          }
          .multilineTextAlignment(.leading)
          .frame(maxWidth: .infinity, alignment: .leading)

          Image(systemName: "chevron.right")
            .font(Tokens.Text.caption.weight(.semibold))
            .foregroundStyle(Tokens.Color.textSecondary)
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
        .foregroundStyle(Tokens.Color.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Tokens.Spacing.tight)
        .padding(.bottom, Tokens.Spacing.tight)

      VStack(spacing: Tokens.Spacing.snug) {
        disclosureRow(.setCounting)
        disclosureRow(.progression)
      }
    }
  }

  private func disclosureRow(_ item: Disclosure) -> some View {
    Button {
      disclosure = item
    } label: {
      HStack(spacing: Tokens.Spacing.regular) {
        VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
          // The source's own title, so the row and the sheet it opens cannot name it differently.
          Text(item.source.title)
            .font(Tokens.Text.headline)
            .foregroundStyle(Tokens.Color.textPrimary)
          Text(item.detail)
            .font(Tokens.Text.caption)
            .foregroundStyle(Tokens.Color.textSecondary)
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)

        Image(systemName: "chevron.right")
          .font(Tokens.Text.caption.weight(.semibold))
          .foregroundStyle(Tokens.Color.textSecondary)
          .accessibilityHidden(true)
      }
    }
    .buttonStyle(DisclosureRowButtonStyle())
    .accessibilityHint("Opens the method and its limits")
  }
}

/// The disclosures reachable from Settings.
///
/// Each renders an `EvidenceSource` that the arithmetic itself uses, so what is read here cannot
/// drift from what the app computes.
///
/// `nonisolated` so its `Identifiable` conformance is an ordinary one: this target defaults to
/// `MainActor`, and a main-actor `id` cannot satisfy a nonisolated requirement.
private nonisolated enum Disclosure: Identifiable {
  case setCounting
  case progression

  var id: Disclosure { self }

  var source: EvidenceSource {
    switch self {
    case .setCounting: return SetCounting.source
    case .progression: return ProgressionAnalyzer.source
    }
  }

  /// The same certainty the weekly volume screen states beside its own disclosure. Load history
  /// states none there, so none is invented here.
  var certainty: Certainty? {
    switch self {
    case .setCounting: return .moderate
    case .progression: return nil
    }
  }

  /// Where the method is used, so the row says why it matters before it is opened.
  var detail: String {
    switch self {
    case .setCounting: return "How weekly volume credits each muscle"
    case .progression: return "How each machine's load chart is drawn"
    }
  }
}

/// A full-width, outlined row that opens something.
///
/// Outlined with the measured control border rather than the decorative hairline, because the
/// boundary is what tells the lifter the row can be tapped. Pressed, it sinks to the pressed fill;
/// with Reduce Motion on, the scale is dropped and only the fill changes.
private struct DisclosureRowButtonStyle: ButtonStyle {
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
        configuration.isPressed ? Tokens.Color.surfacePressed : Tokens.Color.surface,
        in: shape
      )
      .overlay {
        shape.strokeBorder(Tokens.Color.controlBorder, lineWidth: Tokens.Stroke.hairline)
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
