import HardsetUI
import StoreKit
import SwiftUI

struct LifetimePurchaseSection: View {
  let access: LifetimeAccess
  var body: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
      SectionLabel("Hardset Lifetime")
      Text("An optional one-time purchase for the deep muscle map. Your workouts, personal history, CSV import, and CSV, JSON and SQLite exports stay free. Existing gym and machine logging stays available.")
        .font(Tokens.Text.provenance).foregroundStyle(Tokens.Color.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
      if access.isDevelopmentBuild {
        LifetimeDevelopmentNote(access: access)
      } else if access.isUnlocked {
        Label("Lifetime access active", systemImage: "checkmark.seal")
          .font(Tokens.Text.headline).foregroundStyle(Tokens.Color.success)
      } else if let product = access.product {
        Button("Unlock Lifetime · \(product.displayPrice)") { Task { await access.purchase() } }
          .buttonStyle(HardsetButtonStyle()).disabled(access.isWorking)
        Text("One purchase. No subscription.").font(Tokens.Text.caption).foregroundStyle(Tokens.Color.textSecondary)
      }
      if access.isWorking { ProgressView().accessibilityLabel("Checking the lifetime purchase") }
      if let message = access.message {
        Text(message).font(Tokens.Text.provenance).foregroundStyle(Tokens.Color.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      if !access.isDevelopmentBuild && !access.isUnlocked {
        // Restoring an existing entitlement does not need the storefront product to load.
        // Keep this user-initiated action available during a product outage or delisting.
        Button("Restore purchases") { Task { await access.restore() } }
          .buttonStyle(HardsetButtonStyle(.secondary)).disabled(access.isWorking)
        if access.product == nil && access.hasLoaded && !access.isWorking {
          Button("Try again") { Task { await access.load() } }
            .buttonStyle(HardsetButtonStyle(.quiet))
        }
      }
    }
    .task { await access.load() }
  }
}

/// The line a development build shows beside the deep muscle map and in Settings, so the map
/// being open is never mistaken for a purchase. Draws nothing in App Store and TestFlight builds.
struct LifetimeDevelopmentNote: View {
  let access: LifetimeAccess

  var body: some View {
    if access.isDevelopmentBuild {
      Label {
        Text(LifetimeAccess.developmentNote)
          .fixedSize(horizontal: false, vertical: true)
      } icon: {
        Image(systemName: "hammer")
      }
      .font(Tokens.Text.caption)
      .foregroundStyle(Tokens.Color.textSecondary)
      .accessibilityElement(children: .combine)
    }
  }
}
