import HardsetCore
import SwiftUI

/// A gym location option for the gym picker, keeping HardsetUI free of storage types.
///
/// Identified by `GymID` rather than a bare `UUID`, so a machine or session identifier cannot be
/// handed in by mistake. `GymID` lives in HardsetCore, which this target already depends on.
public struct GymOption: Hashable, Sendable, Identifiable {
  public let id: GymID
  public let name: String

  public init(id: GymID, name: String) {
    self.id = id
    self.name = name
  }
}

/// Picks the physical training facility for the current workout.
///
/// Sets where the workout happens, enabling per-machine tracking. Saved gyms are 56 pt selection
/// rows under a sentence-case label; "Not recorded" stays a real choice beneath them, because
/// training somewhere unsaved is a true answer; and adding a gym is a plainly styled action rather
/// than a row pretending to be one. An error, such as a saved gym whose list could not be read
/// back, appears as a banner at the top, pinned above the list, where it cannot be scrolled past.
/// At accessibility text sizes the same banner is instead the first thing in the scrolling content,
/// so a tall banner cannot push every gym off screen; it is never height-capped.
/// A failed save is stated in the name sheet instead, where the typed name waits for the retry.
public struct GymPickerView: View {
  private let gyms: [GymOption]
  private let selected: GymID?
  private let onSelect: (GymID?) -> Void
  private let onAddGym: () -> Void
  private let errorMessage: String?
  private let isLoading: Bool
  private let onCancel: (() -> Void)?

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  /// - Parameters:
  ///   - isLoading: The saved gyms are still being read. The list says so in place of "No saved
  ///     gyms yet", which would claim an empty list the read has not confirmed. "Not recorded"
  ///     stays selectable meanwhile.
  ///   - onCancel: Closes the picker without choosing. When set, the picker draws "Cancel" in the
  ///     toolbar's cancellation position, so the caller should not draw its own.
  public init(
    gyms: [GymOption],
    selected: GymID?,
    errorMessage: String? = nil,
    isLoading: Bool = false,
    onSelect: @escaping (GymID?) -> Void,
    onAddGym: @escaping () -> Void,
    onCancel: (() -> Void)? = nil
  ) {
    self.gyms = gyms
    self.selected = selected
    self.errorMessage = errorMessage
    self.isLoading = isLoading
    self.onSelect = onSelect
    self.onAddGym = onAddGym
    self.onCancel = onCancel
  }

  /// The message with surrounding whitespace removed, or `nil` when nothing readable is left, so a
  /// blank error never draws an empty banner.
  private var visibleErrorMessage: String? {
    guard let errorMessage else { return nil }
    let trimmed = errorMessage.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  /// True while the saved gyms are unread, so the empty-list wording is not claimed yet.
  private var isReadingGyms: Bool {
    isLoading && gyms.isEmpty
  }

  /// True at accessibility text sizes, where the error banner is the first thing in the scrolling
  /// content rather than pinned above it: pinned, a banner at those sizes and the intro line could
  /// fill a phone screen and leave no gym in view. The banner is never height-capped.
  private var scrollsErrorBanner: Bool { dynamicTypeSize.isAccessibilitySize }

  /// The error banner, drawn pinned or scrolled by this one helper, so the two placements cannot
  /// drift apart.
  private func errorBanner(_ message: String) -> some View {
    HardsetBanner(.error, message: message)
      .hardsetArrival()
  }

  public var body: some View {
    VStack(spacing: 0) {
      // Pinned above the list rather than scrolled with it, so a failure cannot be scrolled out
      // of sight however many gyms are saved. At accessibility sizes it scrolls with the list
      // instead (`scrollsErrorBanner`).
      if !scrollsErrorBanner, let visibleErrorMessage {
        errorBanner(visibleErrorMessage)
          .padding(.horizontal, Tokens.Spacing.loose)
          .padding(.top, Tokens.Spacing.regular)
      }

      ScrollView {
        VStack(alignment: .leading, spacing: Tokens.Spacing.section) {
          if scrollsErrorBanner, let visibleErrorMessage {
            errorBanner(visibleErrorMessage)
          }

          Text("Loads are tracked per machine, and machines belong to a gym.")
            .font(Tokens.Text.label)
            .foregroundStyle(Tokens.Color.chalkDim)
            .fixedSize(horizontal: false, vertical: true)

          if isReadingGyms {
            // One quiet line, as `HardsetLoadingState` is, kept inside the list so the choices
            // below it stay in reach.
            Text("Reading your gyms…")
              .font(Tokens.Text.label)
              .foregroundStyle(Tokens.Color.chalkDim)
              .fixedSize(horizontal: false, vertical: true)
          } else if !gyms.isEmpty {
            VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
              SectionLabel("Saved gyms", count: gyms.count)

              ForEach(gyms) { gym in
                SelectionRow(
                  title: gym.name,
                  leadingIcon: "mappin.and.ellipse",
                  isSelected: selected == gym.id,
                  action: { onSelect(gym.id) }
                )
              }
            }
          }

          VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
            SectionLabel(gyms.isEmpty && !isLoading ? "No saved gyms yet" : "Somewhere else")

            SelectionRow(
              title: "Not recorded",
              subtitle: "Sets are logged without a machine",
              leadingIcon: "slash.circle",
              isSelected: selected == nil,
              action: { onSelect(nil) }
            )

            Button(action: onAddGym) {
              Label {
                Text("Add a gym")
              } icon: {
                Image(systemName: "plus")
                  .foregroundStyle(Tokens.Color.plateBlue)
              }
            }
            .buttonStyle(HardsetButtonStyle(.secondary, size: .logger))
            .padding(.top, Tokens.Spacing.tight)
          }
        }
        .padding(.horizontal, Tokens.Spacing.loose)
        .padding(.top, Tokens.Spacing.regular)
        .padding(.bottom, Tokens.Spacing.section)
      }
    }
    .background(Tokens.Color.canvas)
    .pickerCancelAction(onCancel)
  }
}

#if DEBUG
  private enum GymPreviewSelection {
    case first
    case notRecorded
    /// A gym the list does not hold, as after a failed read of a saved selection.
    case unlisted
  }

  private let previewGyms = [
    GymOption(id: GymID(), name: "Metroflex Gym"),
    GymOption(id: GymID(), name: "Equinox Hudson Yards"),
  ]

  private let manyPreviewGyms = [
    "Metroflex Gym", "Equinox Hudson Yards", "Iron Temple Strength and Conditioning",
    "Planet Fitness Midtown", "Gold's Gym Venice", "Lifetime Athletic Brooklyn",
    "Crunch Fitness Union Square", "Chelsea Piers Fitness",
  ].map { GymOption(id: GymID(), name: $0) }

  private struct GymPickerHarness: View {
    let gyms: [GymOption]
    let errorMessage: String?
    let isLoading: Bool
    @State private var selected: GymID?

    init(
      gyms: [GymOption], errorMessage: String? = nil, isLoading: Bool = false,
      selection: GymPreviewSelection = .first
    ) {
      self.gyms = gyms
      self.errorMessage = errorMessage
      self.isLoading = isLoading
      switch selection {
      case .first: self._selected = State(initialValue: gyms.first?.id)
      case .notRecorded: self._selected = State(initialValue: nil)
      case .unlisted: self._selected = State(initialValue: GymID())
      }
    }

    var body: some View {
      NavigationStack {
        GymPickerView(
          gyms: gyms,
          selected: selected,
          errorMessage: errorMessage,
          isLoading: isLoading,
          onSelect: { selected = $0 },
          onAddGym: {},
          onCancel: {}
        )
        .hardsetNavigationTitle("Choose a gym")
      }
    }
  }

  #Preview("Gym picker") {
    GymPickerHarness(gyms: [
      GymOption(id: GymID(), name: "Metroflex Gym"),
      GymOption(id: GymID(), name: "Equinox Hudson Yards"),
    ])
  }

  #Preview("Gym picker, list unreadable") {
    GymPickerHarness(
      gyms: [],
      errorMessage: "The gym was saved, but its list could not be read."
    )
  }

  #Preview("Gym picker, no gyms") {
    GymPickerHarness(gyms: [], selection: .notRecorded)
  }

  #Preview("Gym picker, one selected") {
    GymPickerHarness(gyms: previewGyms)
  }

  #Preview("Gym picker, not recorded") {
    GymPickerHarness(gyms: previewGyms, selection: .notRecorded)
  }

  #Preview("Gym picker, unlisted selection") {
    GymPickerHarness(gyms: previewGyms, selection: .unlisted)
  }

  #Preview("Gym picker, many gyms") {
    GymPickerHarness(gyms: manyPreviewGyms)
  }

  #Preview("Gym picker, loading") {
    GymPickerHarness(gyms: [], isLoading: true, selection: .notRecorded)
  }

  #Preview("Gym picker, accessibility size") {
    GymPickerHarness(
      gyms: manyPreviewGyms,
      errorMessage: "The gym was saved, but its list could not be read."
    )
    .dynamicTypeSize(.accessibility3)
  }
#endif
