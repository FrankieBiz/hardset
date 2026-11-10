import Foundation
import Observation
import StoreKit

/// StoreKit is the authority for the optional non-consumable. Core logging, history,
/// CSV migration and all export formats never consult this entitlement.
///
/// The exception is a development build: the simulator, or any install that carries an embedded
/// provisioning profile, which App Store and TestFlight installs never do. A personal team cannot
/// sell an In-App Purchase, so on such a build the product can never load and the deep muscle map
/// would be locked away from the person who built it. There the map is included, StoreKit is not
/// asked, and `developmentNote` is shown beside it so the build never implies a purchase was made.
/// App Store and TestFlight builds keep the paid gate unchanged.
@MainActor
@Observable
final class LifetimeAccess {
  /// The one instance the app uses, so a purchase or restore made in Settings is the same state the
  /// Volume tab's map reads, and an owner never sees the offer while a second instance loads.
  static let shared = LifetimeAccess()

  /// Shown wherever a development build presents the map as included.
  static let developmentNote =
    "Development build: the deep muscle map is included. Nothing was purchased."

  private(set) var product: Product?
  private(set) var isUnlocked: Bool
  /// Included because of how this build was signed, not because anything was bought.
  let isDevelopmentBuild: Bool
  private(set) var isWorking = false
  /// The first entitlement check has finished, so `isUnlocked == false` is an answer rather than
  /// "not known yet". A screen gating on the entitlement waits for this instead of flashing the
  /// offer at an owner. Always true for a development build, which never asks StoreKit.
  private(set) var hasLoaded: Bool
  /// The last attempt to load the product failed, as opposed to succeeding with no product.
  private(set) var loadFailed = false
  private(set) var message: String?
  let productID = "com.hardset.app.lifetime"
  @ObservationIgnored private var updates: Task<Void, Never>?

  init(isDevelopmentBuild: Bool = LifetimeAccess.detectDevelopmentBuild()) {
    self.isDevelopmentBuild = isDevelopmentBuild
    self.isUnlocked = isDevelopmentBuild
    self.hasLoaded = isDevelopmentBuild
  }

  /// The simulator, or an install with `embedded.mobileprovision`: development, ad hoc and
  /// personal-team builds carry one; App Store and TestFlight installs do not.
  static func detectDevelopmentBuild() -> Bool {
    #if targetEnvironment(simulator)
      return true
    #else
      return Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") != nil
    #endif
  }

  func load() async {
    guard !isDevelopmentBuild else { return }
    guard !isWorking else { return }
    observeTransactions()
    isWorking = true
    defer { isWorking = false }
    await refreshEntitlements()
    hasLoaded = true
    do {
      product = try await Product.products(for: [productID]).first { $0.type == .nonConsumable }
      loadFailed = false
      // The build or the App Store account may simply not offer it; which, StoreKit does not say,
      // so neither does this line.
      message = product == nil && !isUnlocked
        ? "The lifetime purchase isn't available right now. Logging, history and exports stay free."
        : nil
    } catch {
      loadFailed = true
      message = "Could not load the lifetime purchase. Check your connection and try again."
    }
  }

  /// Kept for callers that observed from a view's task. The listener now lives as long as this
  /// instance, so it is started once and this returns at once.
  func observe() async {
    observeTransactions()
  }

  /// Starts the one listener for transactions that arrive outside a purchase call: an approved
  /// Ask to Buy, a purchase on another device, a refund. Idempotent.
  func observeTransactions() {
    guard !isDevelopmentBuild, updates == nil else { return }
    let productID = productID
    updates = Task { [weak self] in
      for await result in Transaction.updates {
        guard !Task.isCancelled else { return }
        guard case .verified(let transaction) = result, transaction.productID == productID else { continue }
        await self?.refreshEntitlements()
        await transaction.finish()
      }
    }
  }

  func purchase() async {
    guard !isDevelopmentBuild, !isWorking, let product else { return }
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
    guard !isDevelopmentBuild, !isWorking else { return }
    isWorking = true
    defer { isWorking = false }
    do {
      try await AppStore.sync()
      await refreshEntitlements()
      message = isUnlocked ? "Lifetime access restored." : "No lifetime purchase was found for this Apple Account."
    } catch StoreKitError.userCancelled {
      // Dismissing the Apple Account prompt is a choice, not a failure.
      message = nil
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
