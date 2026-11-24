import Foundation
import HardsetCore
import HardsetStore
import Observation

/// The first-launch sequence as plain state, so every rule can be tested without a pager.
///
/// Welcome, three pitch pages, then Setup. The model knows where the lifter is, what "Next" and
/// "Skip" do from there, and what Setup has to offer and save. It draws nothing and owns no unit:
/// the unit is the app's one stored preference, and Setup edits it where it lives.
@MainActor
@Observable
public final class OnboardingModel {
  /// A page of the pager, in order.
  public enum Page: Int, CaseIterable, Hashable, Sendable {
    case welcome
    case pitchSetRow
    case pitchEstimate
    case pitchRest
    case setup
  }

  /// The page on screen. Bound to the pager, so a swipe sets it directly.
  public var page: Page

  // MARK: - Setup

  /// The gyms the lifter already has, offered as choices so Setup never asks them to retype one.
  public private(set) var existingGyms: [GymRecord] = []

  /// The existing gym picked, when there are any.
  public var selectedGymID: GymID?

  /// The name typed for a first gym, used only when no gym exists yet. Blank is allowed.
  public var gymName = ""

  /// Why Setup could not read or save, in the lifter's words. Shown above "Start logging".
  public private(set) var setupError: String?

  /// The gym Setup settled on, once `completeSetup()` has succeeded. `nil` means none was named.
  public private(set) var chosenGymID: GymID?

  private let gyms: GymStore

  /// - Parameter startingPage: The page shown first. Only a capture or a test starts anywhere but
  ///   Welcome.
  public init(gyms: GymStore, startingPage: Page = .welcome) {
    self.gyms = gyms
    self.page = startingPage
  }

  // MARK: - Pages

  /// The pages the pager holds.
  public var pages: [Page] { Page.allCases }

  /// "Skip" is offered from the second page on, and not on Setup, which is where it leads.
  public var canSkip: Bool {
    page != .welcome && page != .setup
  }

  /// Leaves the pager's current page for the next one.
  public func next() {
    guard let following = Page(rawValue: page.rawValue + 1) else { return }
    page = following
  }

  /// Jumps to where the sequence ends: Setup. Never from the welcome page, which has no skip.
  public func skip() {
    guard canSkip else { return }
    page = .setup
  }

  // MARK: - Setup

  /// Reads the gyms Setup offers, and preselects the last one the lifter trained at, or the only
  /// one there is. A failed read leaves Setup usable with no choices, and says so.
  public func loadSetup() {
    do {
      let selection = try gyms.selection()
      existingGyms = selection.options
      if selectedGymID == nil || !selection.options.contains(where: { $0.id == selectedGymID }) {
        selectedGymID = selection.lastUsed ?? (selection.options.count == 1 ? selection.options.first?.id : nil)
      }
      setupError = nil
    } catch {
      existingGyms = []
      setupError = "Your gyms could not be read. You can add one later in Settings."
    }
  }

  /// Saves Setup's gym choice. A lifter who already has gyms picks among them and nothing is
  /// written; otherwise a typed name becomes their first gym, and a blank one is fine.
  ///
  /// - Returns: Whether Setup may close. A gym that could not be saved keeps it open with the
  ///   reason, so the name typed is still there for another try.
  @discardableResult
  public func completeSetup() -> Bool {
    if !existingGyms.isEmpty {
      chosenGymID = selectedGymID
      setupError = nil
      return true
    }
    let name = gymName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else {
      chosenGymID = nil
      setupError = nil
      return true
    }
    do {
      chosenGymID = try gyms.createGym(name: name)
      setupError = nil
      return true
    } catch {
      setupError = "“\(name)” could not be saved. Try again."
      return false
    }
  }
}
