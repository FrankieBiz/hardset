import HardsetCore
import HardsetStore
import HardsetUI
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct WorkoutReceiptScreen: View {
  let sessionID: SessionID
  let store: ReceiptStore
  let unit: WeightUnit
  @State private var snapshot = SnapshotLoader<WorkoutReceipt>()
  @State private var image: Image?
  @Environment(\.displayScale) private var displayScale
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Group {
        if let receipt = snapshot.value {
          ScrollView {
            WorkoutReceiptView(receipt: receipt, unit: unit)
            VStack(spacing: Tokens.Spacing.regular) {
              CertaintyBadge(level: receipt.lines.isEmpty || receipt.lines.contains { $0.machineName == nil || $0.isImported } ? .unevaluated : .high,
                methodology: "A receipt of saved user-entered sets. Unknown equipment is unevaluated. No independent load measurement or technique verification is claimed.")
              ShareLink(item: receipt.text(unit: unit)) { Label("Share text receipt", systemImage: "square.and.arrow.up") }
                .buttonStyle(HardsetButtonStyle(.secondary))
              if let image {
                ShareLink(item: image, preview: SharePreview("Hardset workout receipt", image: image)) {
                  Label("Share receipt image", systemImage: "photo")
                }.buttonStyle(HardsetButtonStyle())
              }
            }
            .padding(Tokens.Spacing.loose)
          }
        } else if snapshot.loadFailed {
          HardsetEmptyState(title: "Could not read this workout", detail: "Your saved sets are unchanged. Try again.",
            systemImage: "exclamationmark.triangle", actionTitle: "Try again", actionSystemImage: "arrow.clockwise", action: { Task { await load() } })
        } else { HardsetLoadingState("Reading your workout…") }
      }
      .background(Tokens.Color.background)
      .hardsetNavigationTitle("Workout receipt")
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
      .task { await load() }
    }
  }

  private func load() async {
    await snapshot.load { try await store.load(sessionID) }
    #if canImport(UIKit)
      guard let receipt = snapshot.value else { return }
      // Keep very long sessions as text rather than allocate an unbounded bitmap.
      guard receipt.lines.count <= 30 else { return }
      let renderer = ImageRenderer(content: WorkoutReceiptView(receipt: receipt, unit: unit)
        .frame(width: 540).environment(\.colorScheme, .dark).environment(\.dynamicTypeSize, .large))
      renderer.scale = min(displayScale, 2)
      if let rendered = renderer.uiImage { image = Image(uiImage: rendered) }
    #endif
  }
}
