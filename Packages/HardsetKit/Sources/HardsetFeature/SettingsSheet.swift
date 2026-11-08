import HardsetCore
import HardsetUI
import SwiftUI

/// The app's settings, currently one decision that genuinely cannot be inferred reliably.
///
/// Kept deliberately small. Anything the app can work out from behaviour — which gym, which
/// machine, how many sets a movement usually gets — is learned rather than asked, so it does not
/// belong here. The unit is different: it is a display preference with no behavioural signal, and
/// getting it wrong makes every number on screen wrong.
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
  private let onDone: () -> Void

  public init(useImperial: Binding<Bool>, onDone: @escaping () -> Void) {
    self._useImperial = useImperial
    self.onDone = onDone
  }

  public var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: Tokens.Spacing.block) {
          unitsSection
          methodologySection
        }
        .padding(.horizontal, Tokens.Spacing.loose)
        .padding(.top, Tokens.Spacing.loose)
        .padding(.bottom, Tokens.Spacing.block)
      }
      .scrollBounceBehavior(.basedOnSize)
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
