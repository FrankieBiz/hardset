import HardsetCore
import HardsetUI
import SwiftUI

/// The policy that ships inside the binary, so Settings never hides a required legal surface just
/// because the public App Store URL has not been configured yet.
///
/// The public URL is still required in App Store Connect. When supplied through `LegalLinks.live`,
/// it appears at the bottom as the canonical web copy without replacing this offline-readable one.
@MainActor
public struct PrivacyPolicyScreen: View {
  private let onlineURL: URL?

  public init(onlineURL: URL? = nil) {
    self.onlineURL = onlineURL
  }

  public var body: some View {
    List {
      Section("Summary") {
        Text(
          "Hardset has no advertising, analytics, tracking, or developer-operated user account. "
            + "The developer does not sell your data or receive your training history on a "
            + "developer-controlled server."
        )
      }

      Section("Data Hardset handles") {
        policyRow(
          title: "Training data",
          text: "Workouts, sets, exercise notes, plans, gyms, and machines are stored on this "
            + "device. When iCloud is available, they sync between your devices through your "
            + "private iCloud database using Apple CloudKit."
        )
        policyRow(
          title: "Bodyweight",
          text: "Bodyweight readings stay on this device and are excluded from Hardset's "
            + "CloudKit synchronization."
        )
        policyRow(
          title: "Preferences and exports",
          text: "Unit, timer, and effort-field choices stay on this device. A CSV export leaves "
            + "Hardset only when you choose a destination in the system share sheet."
        )
      }

      Section("Use and sharing") {
        Text(
          "Hardset uses the information you enter only to provide the logger, history, planning, "
            + "progression, and volume features on your devices. It is not used for advertising, "
            + "marketing, profiling, or data mining, and it is not shared with data brokers."
        )
        Link("Apple privacy policy", destination: URL(string: "https://www.apple.com/legal/privacy/")!)
      }

      Section("Retention and deletion") {
        Text(
          "Your records remain until you delete them. Settings offers a permanent Delete All "
            + "Hardset Data action. It removes device-only data immediately and queues deletion "
            + "of synchronized records from your private iCloud database. If the device is "
            + "offline or signed out of iCloud, that iCloud deletion completes when sync becomes "
            + "available again. Uninstalling the app by itself may not remove its iCloud copy."
        )
        Text(
          "Files you deliberately copied with the share sheet are controlled by the destination "
            + "you selected and cannot be deleted by Hardset."
        )
      }

      Section("Contact") {
        Text(
          "For privacy questions, use the support contact on Hardset's App Store product page. "
            + "The developer cannot inspect or delete records inside your private iCloud "
            + "database on your behalf; use the in-app deletion control instead."
        )
        if let onlineURL {
          Link("View the policy online", destination: onlineURL)
        }
      }

      Section {
        LabeledContent("Effective", value: "August 26, 2026")
          .foregroundStyle(Tokens.Color.textSecondary)
      }
    }
    .navigationTitle("Privacy policy")
  }

  private func policyRow(title: String, text: String) -> some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
      Text(title).font(Tokens.Text.label)
      Text(text)
        .font(Tokens.Text.label)
        .foregroundStyle(Tokens.Color.textSecondary)
    }
    .accessibilityElement(children: .combine)
  }
}

#if DEBUG
  #Preview { NavigationStack { PrivacyPolicyScreen() } }
#endif
