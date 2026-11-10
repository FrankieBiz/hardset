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
/// back, appears as a banner at the top, where it cannot be scrolled past. A failed save is stated
/// in the name sheet instead, where the typed name waits for the retry.
public struct GymPickerView: View {
  private let gyms: [GymOption]
  private let selected: GymID?
  private let onSelect: (GymID?) -> Void
  private let onAddGym: () -> Void
  private let errorMessage: String?

  public init(
    gyms: [GymOption],
    selected: GymID?,
    errorMessage: String? = nil,
    onSelect: @escaping (GymID?) -> Void,
    onAddGym: @escaping () -> Void
  ) {
    self.gyms = gyms
    self.selected = selected
    self.errorMessage = errorMessage
    self.onSelect = onSelect
    self.onAddGym = onAddGym
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Tokens.Spacing.section) {
        VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
          if let errorMessage, !errorMessage.isEmpty {
            HardsetBanner(.error, message: errorMessage)
          }

          Text("Loads are tracked per machine, and machines belong to a gym.")
            .font(Tokens.Text.label)
            .foregroundStyle(Tokens.Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        if !gyms.isEmpty {
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
          SectionLabel(gyms.isEmpty ? "No saved gyms yet" : "Somewhere else")

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
                .foregroundStyle(Tokens.Color.accent)
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
    .background(Tokens.Color.background)
  }
}

#if DEBUG
  private struct GymPickerHarness: View {
    let gyms: [GymOption]
    let errorMessage: String?
    @State private var selected: GymID?

    init(gyms: [GymOption], errorMessage: String? = nil) {
      self.gyms = gyms
      self.errorMessage = errorMessage
      self._selected = State(initialValue: gyms.first?.id)
    }

    var body: some View {
      NavigationStack {
        GymPickerView(
          gyms: gyms,
          selected: selected,
          errorMessage: errorMessage,
          onSelect: { selected = $0 },
          onAddGym: {}
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
#endif
