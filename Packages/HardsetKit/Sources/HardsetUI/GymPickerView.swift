import Foundation
import SwiftUI

/// A gym location option for the gym picker, keeping HardsetUI free of storage types.
public struct GymOption: Hashable, Sendable, Identifiable {
  public let id: UUID
  public let name: String

  public init(id: UUID, name: String) {
    self.id = id
    self.name = name
  }
}

/// Picks the physical training facility for the current workout.
///
/// Sets where the workout happens, enabling per-machine tracking. Built with the dark-slate
/// card aesthetic, 56 pt selection rows, clear guidance, and direct gym creation.
public struct GymPickerView: View {
  private let gyms: [GymOption]
  private let selected: UUID?
  private let onSelect: (UUID?) -> Void
  private let onAddGym: () -> Void
  private let errorMessage: String?

  public init(
    gyms: [GymOption],
    selected: UUID?,
    errorMessage: String? = nil,
    onSelect: @escaping (UUID?) -> Void,
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
      VStack(alignment: .leading, spacing: Tokens.Spacing.loose) {
        // Explanatory banner
        VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
          Text("Where are you training?")
            .font(Tokens.Text.labelEmphasis)
            .foregroundStyle(Tokens.Color.textPrimary)

          if let errorMessage {
            Text(errorMessage)
              .font(Tokens.Text.caption)
              .foregroundStyle(Tokens.Color.certainty(.low))
          } else {
            Text("Loads are tracked per machine, and machines belong to a gym.")
              .font(Tokens.Text.caption)
              .foregroundStyle(Tokens.Color.textSecondary)
          }
        }
        .padding(.horizontal, Tokens.Spacing.loose)
        .padding(.top, Tokens.Spacing.regular)

        // Gym list
        if !gyms.isEmpty {
          VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
            Text("SAVED GYMS")
              .font(Tokens.Text.sectionHeader)
              .foregroundStyle(Tokens.Color.textSecondary)
              .padding(.horizontal, Tokens.Spacing.loose)

            VStack(spacing: Tokens.Spacing.snug) {
              ForEach(gyms) { gym in
                SelectionRow(
                  title: gym.name,
                  leadingIcon: "mappin.and.ellipse",
                  isSelected: selected == gym.id,
                  action: { onSelect(gym.id) }
                )
              }
            }
            .padding(.horizontal, Tokens.Spacing.loose)
          }
        }

        // Secondary & Actions section
        VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
          Text("OPTIONS")
            .font(Tokens.Text.sectionHeader)
            .foregroundStyle(Tokens.Color.textSecondary)
            .padding(.horizontal, Tokens.Spacing.loose)

          VStack(spacing: Tokens.Spacing.snug) {
            SelectionRow(
              title: "Not recorded",
              subtitle: "Train without equipment tagging",
              leadingIcon: "slash.circle",
              isSelected: selected == nil,
              action: { onSelect(nil) }
            )

            Button(action: onAddGym) {
              HStack(spacing: Tokens.Spacing.regular) {
                Image(systemName: "plus.circle.fill")
                  .font(.system(size: 18, weight: .semibold))
                  .foregroundStyle(Tokens.Color.accent)

                Text("Add a gym")
                  .font(Tokens.Text.rowTitle.weight(.medium))
                  .foregroundStyle(Tokens.Color.accent)

                Spacer()
              }
              .padding(.horizontal, Tokens.Spacing.regular)
              .frame(minHeight: Tokens.loggerTapTarget)
              .contentShape(Rectangle())
              .hardsetCard(cornerRadius: Tokens.Radius.control)
            }
            .buttonStyle(.plain)
          }
          .padding(.horizontal, Tokens.Spacing.loose)
        }
      }
      .padding(.bottom, Tokens.Spacing.section)
    }
    .background(Tokens.Color.background)
  }
}

#if DEBUG
  #Preview("Gym Picker") {
    GymPickerView(
      gyms: [
        GymOption(id: UUID(), name: "Metroflex Gym"),
        GymOption(id: UUID(), name: "Equinox Hudson Yards"),
      ],
      selected: nil,
      onSelect: { _ in },
      onAddGym: {}
    )
  }
#endif
