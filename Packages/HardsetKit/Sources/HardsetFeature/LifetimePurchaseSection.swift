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
      if access.isUnlocked {
        Label("Lifetime access active", systemImage: "checkmark.seal")
          .font(Tokens.Text.headline).foregroundStyle(Tokens.Color.success)
      } else if let product = access.product {
        Button("Unlock Lifetime · \(product.displayPrice)") { Task { await access.purchase() } }
          .buttonStyle(HardsetButtonStyle()).disabled(access.isWorking)
        Text("One purchase. No subscription.").font(Tokens.Text.caption).foregroundStyle(Tokens.Color.textSecondary)
      }
      if access.isWorking { ProgressView() }
      if let message = access.message {
        Text(message).font(Tokens.Text.provenance).foregroundStyle(Tokens.Color.textSecondary)
      }
      Button("Restore purchases") { Task { await access.restore() } }
        .buttonStyle(HardsetButtonStyle(.secondary)).disabled(access.isWorking)
      Button("Refresh availability") { Task { await access.load() } }
        .buttonStyle(HardsetButtonStyle(.quiet)).disabled(access.isWorking)
    }
    .task { await access.load() }
    .task { await access.observe() }
  }
}
