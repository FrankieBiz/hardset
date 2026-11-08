import Foundation
import Observation
import StoreKit

/// StoreKit is the authority for the optional non-consumable. Core logging, history,
/// CSV migration and all export formats never consult this entitlement.
@MainActor
@Observable
final class LifetimeAccess {
  private(set) var product: Product?
  private(set) var isUnlocked = false
  private(set) var isWorking = false
  private(set) var message: String?
  let productID = "com.hardset.app.lifetime"

  func load() async {
    guard !isWorking else { return }
    isWorking = true
    defer { isWorking = false }
    await refreshEntitlements()
    do {
      product = try await Product.products(for: [productID]).first { $0.type == .nonConsumable }
      message = product == nil ? "Lifetime purchase is not available in this storefront. Logging, history and exports remain free." : nil
    } catch { message = "Could not load the lifetime purchase. Try again." }
  }

  func observe() async {
    for await result in Transaction.updates {
      guard !Task.isCancelled else { return }
      guard case .verified(let transaction) = result, transaction.productID == productID else { continue }
      await refreshEntitlements()
      await transaction.finish()
    }
  }

  func purchase() async {
    guard !isWorking, let product else { return }
    isWorking = true
    defer { isWorking = false }
    do {
      switch try await product.purchase() {
      case .success(.verified(let transaction)):
        await refreshEntitlements()
        await transaction.finish()
        message = isUnlocked ? "Lifetime access is active." : "The purchase could not be verified as an active entitlement."
      case .success(.unverified): message = "The purchase could not be verified. Restore purchases or try again."
      case .pending: message = "Purchase is pending approval."
      case .userCancelled: message = nil
      @unknown default: message = "Purchase status is unavailable. Restore purchases to check again."
      }
    } catch { message = "The purchase did not complete. Try again or restore purchases." }
  }

  func restore() async {
    guard !isWorking else { return }
    isWorking = true
    defer { isWorking = false }
    do {
      try await AppStore.sync()
      await refreshEntitlements()
      message = isUnlocked ? "Lifetime access restored." : "No active lifetime purchase was found."
    } catch { message = "Could not restore purchases. Try again." }
  }

  private func refreshEntitlements() async {
    var unlocked = false
    for await result in Transaction.currentEntitlements {
      if case .verified(let transaction) = result,
        transaction.productID == productID, transaction.revocationDate == nil,
        transaction.expirationDate == nil { unlocked = true }
    }
    isUnlocked = unlocked
  }
}
