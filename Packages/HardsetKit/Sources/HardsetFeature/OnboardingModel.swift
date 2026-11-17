import Foundation
import HardsetCore
import HardsetStore
import Observation

/// The first-launch sequence as plain state, so every rule can be tested without a pager.
///
/// Welcome, three pitch pages, the tour, then Setup. The model knows where the lifter is, what
/// "Next" and "Skip" do from there, whether the tour's current step may be left, and what Setup has
/// to offer and save. It draws nothing and owns no unit: the unit is the app's one stored
/// preference, and Setup edits it where it lives.
///
/// A replay from Settings runs the same pages without Setup, which the lifter has already done, and
/// ends where the tour ends.
@MainActor
@Observable
public final class OnboardingModel {
  /// Whether this is the first launch or a replay from Settings.
  public enum Mode: Sendable {
    case firstLaunch
    case replay
  }

  /// A page of the pager, in order.
  public enum Page: Int, CaseIterable, Hashable, Sendable {
    case welcome
    case pitchSetRow
    case pitchEstimate
    case pitchRest
    case tour
    case setup
  }

  /// A step of the tour, in order. Each is a place the staged phone shows.
  public enum TourStep: Int, CaseIterable, Hashable, Sendable {
    case train
    case logSet
    case keypad
    case rest
    case machines
    case volume
    case history
    case settings

    /// One-based, as the lifter counts: "3 of 8".
    public var number: Int { rawValue + 1 }
  }

  public static let tourStepCount = TourStep.allCases.count

  public let mode: Mode

  /// The page on screen. Bound to the pager, so a swipe sets it directly.
  public var page: Page

  /// The tour's current step.
  public private(set) var tourStep: TourStep = .train

  /// Whether the lifter has tapped the staged set's check. Step two's "Next" waits for it.
  public private(set) var hasLoggedTourSet = false

  /// Set when a replay reaches its end or is skipped. The first launch ends in Setup instead.
  public private(set) var isReplayFinished = false

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

  /// - Parameters:
  ///   - startingPage: The page shown first. Only a capture or a test starts anywhere but Welcome.
  ///   - startingTourStep: The tour step shown first, on the same terms.
  public init(
    gyms: GymStore, mode: Mode = .firstLaunch, startingPage: Page = .welcome,
    startingTourStep: TourStep = .train
  ) {
    self.gyms = gyms
    self.mode = mode
    self.page = startingPage
    self.tourStep = startingTourStep
  }

  // MARK: - Pages

  /// The pages the pager holds. A replay has no Setup page.
  public var pages: [Page] {
    switch mode {
    case .firstLaunch: Page.allCases
    case .replay: Page.allCases.filter { $0 != .setup }
    }
  }

  /// "Skip" is offered from the second page on, and not on Setup, which is where it leads.
  public var canSkip: Bool {
    page != .welcome && page != .setup
  }

  /// Leaves the pager's current page for the next one. On the tour it moves to the next step, or
  /// out of the tour after the last, and does nothing while the step still waits on the lifter.
  public func next() {
    switch page {
    case .welcome, .pitchSetRow, .pitchEstimate, .pitchRest:
      if let following = Page(rawValue: page.rawValue + 1) { page = following }
    case .tour:
      advanceTour()
    case .setup:
      break
    }
  }

  /// Jumps to where the sequence ends: Setup on a first launch, the end of a replay. Never from the
  /// welcome page, which has no skip.
  public func skip() {
    guard canSkip else { return }
    leaveTour()
  }

  // MARK: - Tour

  /// Whether the tour's "Next" is available. Step two is the one interactive step, so it waits for
  /// the lifter to tap the check; every other step may be left at once.
  public var canAdvanceTour: Bool {
    tourStep != .logSet || hasLoggedTourSet
  }

  /// Records that the staged set was logged by the lifter's own tap.
  public func didLogTourSet() {
    hasLoggedTourSet = true
  }

  private func advanceTour() {
    guard canAdvanceTour else { return }
    if let following = TourStep(rawValue: tourStep.rawValue + 1) {
      tourStep = following
    } else {
      leaveTour()
    }
  }

  private func leaveTour() {
    switch mode {
    case .firstLaunch: page = .setup
    case .replay: isReplayFinished = true
    }
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
