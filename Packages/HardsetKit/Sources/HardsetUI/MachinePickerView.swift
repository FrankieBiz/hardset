import Foundation
import HardsetCore
import SwiftUI

/// A machine, as the picker sees it. No storage dependency.
public struct MachineOption: Hashable, Sendable, Identifiable {
  public let id: MachineID
  public let displayName: String
  /// Present when this machine's stack step is known, so a suggestion can be honest about it.
  public let stackIncrementKg: Double?

  public init(id: MachineID, displayName: String, stackIncrementKg: Double? = nil) {
    self.id = id
    self.displayName = displayName
    self.stackIncrementKg = stackIncrementKg
  }
}

/// Picks which physical machine a movement is being performed on.
///
/// Recency-first: the machine the lifter used last time is rendered as a prominent hero card
/// at the top, reachable in a single tap on the gym floor. Other gym machines, unrecorded sets,
/// and adding a new machine are neatly structured below in dark-slate cards.
public struct MachinePickerView: View {
  private let recent: [MachineOption]
  private let others: [MachineOption]
  private let selected: MachineID?
  private let unit: WeightUnit
  private let onSelect: (MachineID?) -> Void
  private let onAddMachine: (() -> Void)?

  public init(
    recent: [MachineOption],
    others: [MachineOption] = [],
    selected: MachineID?,
    unit: WeightUnit = .kilograms,
    onSelect: @escaping (MachineID?) -> Void,
    onAddMachine: (() -> Void)? = nil
  ) {
    self.recent = recent
    self.others = others
    self.selected = selected
    self.unit = unit
    self.onSelect = onSelect
    self.onAddMachine = onAddMachine
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Tokens.Spacing.loose) {
        // Guidance header
        VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
          Text("Select Machine")
            .font(Tokens.Text.labelEmphasis)
            .foregroundStyle(Tokens.Color.textPrimary)

          Text("Loads are tracked per machine, so weight on different equipment stays separate.")
            .font(Tokens.Text.caption)
            .foregroundStyle(Tokens.Color.textSecondary)
        }
        .padding(.horizontal, Tokens.Spacing.loose)
        .padding(.top, Tokens.Spacing.regular)

        // Hero card: Most recent machine
        if let hero = recent.first {
          VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
            Text("YOU USED THIS LAST")
              .font(Tokens.Text.sectionHeader)
              .foregroundStyle(Tokens.Color.textSecondary)
              .padding(.horizontal, Tokens.Spacing.loose)

            Button {
              onSelect(hero.id)
            } label: {
              VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
                HStack {
                  Text("Recent machine")
                    .font(Tokens.Text.caption.weight(.semibold))
                    .foregroundStyle(Tokens.Color.accent)
                  Spacer()
                  if selected == hero.id {
                    Image(systemName: "checkmark.circle.fill")
                      .font(.system(size: 16, weight: .semibold))
                      .foregroundStyle(Tokens.Color.accent)
                  }
                }

                Text(hero.displayName)
                  .font(Tokens.Text.rowTitle.weight(.semibold))
                  .foregroundStyle(Tokens.Color.textPrimary)

                if let increment = hero.stackIncrementKg {
                  Text(Self.formatStep(increment, unit: unit))
                    .font(Tokens.Text.caption)
                    .foregroundStyle(Tokens.Color.textSecondary)
                }
              }
              .padding(Tokens.Spacing.regular)
              .frame(maxWidth: .infinity, alignment: .leading)
              .hardsetCard(selected: selected == hero.id, cornerRadius: Tokens.Radius.control)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Tokens.Spacing.loose)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel(for: hero, prefix: "Last used"))
            .accessibilityAddTraits(selected == hero.id ? [.isButton, .isSelected] : [.isButton])
          }
        }

        // Other recents (if more than 1)
        if recent.count > 1 {
          VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
            Text("OTHER RECENT EQUIPMENT")
              .font(Tokens.Text.sectionHeader)
              .foregroundStyle(Tokens.Color.textSecondary)
              .padding(.horizontal, Tokens.Spacing.loose)

            VStack(spacing: Tokens.Spacing.snug) {
              ForEach(Array(recent.dropFirst())) { option in
                SelectionRow(
                  title: option.displayName,
                  subtitle: option.stackIncrementKg.map { Self.formatStep($0, unit: unit) },
                  badge: "Recent",
                  isSelected: selected == option.id,
                  action: { onSelect(option.id) }
                )
              }
            }
            .padding(.horizontal, Tokens.Spacing.loose)
          }
        }

        // Also at this gym
        if !others.isEmpty {
          VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
            Text("ALSO AT THIS GYM")
              .font(Tokens.Text.sectionHeader)
              .foregroundStyle(Tokens.Color.textSecondary)
              .padding(.horizontal, Tokens.Spacing.loose)

            VStack(spacing: Tokens.Spacing.snug) {
              ForEach(others) { option in
                SelectionRow(
                  title: option.displayName,
                  subtitle: option.stackIncrementKg.map { Self.formatStep($0, unit: unit) },
                  isSelected: selected == option.id,
                  action: { onSelect(option.id) }
                )
              }
            }
            .padding(.horizontal, Tokens.Spacing.loose)
          }
        }

        // Unrecorded and Add Machine
        VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
          Text("OPTIONS")
            .font(Tokens.Text.sectionHeader)
            .foregroundStyle(Tokens.Color.textSecondary)
            .padding(.horizontal, Tokens.Spacing.loose)

          VStack(spacing: Tokens.Spacing.snug) {
            SelectionRow(
              title: "Not recorded",
              subtitle: "Log set without machine calibration",
              leadingIcon: "slash.circle",
              isSelected: selected == nil,
              action: { onSelect(nil) }
            )

            if let onAddMachine {
              Button(action: onAddMachine) {
                HStack(spacing: Tokens.Spacing.regular) {
                  Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Tokens.Color.accent)

                  Text("Add a machine")
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
          }
          .padding(.horizontal, Tokens.Spacing.loose)
        }
      }
      .padding(.bottom, Tokens.Spacing.section)
    }
    .background(Tokens.Color.background)
  }

  private func accessibilityLabel(for option: MachineOption, prefix: String? = nil) -> String {
    var parts: [String] = []
    if let prefix { parts.append(prefix) }
    parts.append(option.displayName)
    if let increment = option.stackIncrementKg {
      parts.append(Self.formatStep(increment, unit: unit))
    }
    if selected == option.id {
      parts.append("selected")
    }
    return parts.joined(separator: ", ")
  }

  static func formatStep(_ incrementKg: Double, unit: WeightUnit) -> String {
    let displayValue = unit.fromKilograms(incrementKg)
    let rounded = (displayValue * 10).rounded() / 10
    let isWhole = rounded == rounded.rounded()
    let stepString = isWhole ? "\(Int(rounded))" : String(format: "%.1f", rounded)
    return "moves in \(stepString) \(unit.abbreviation) steps"
  }
}

#if DEBUG
  private struct MachinePickerHarness: View {
    @State private var selected: MachineID?
    private let hammer = MachineID()
    private let cybex = MachineID()
    private let panatta = MachineID()

    var body: some View {
      MachinePickerView(
        recent: [
          MachineOption(id: hammer, displayName: "Hammer Strength Leg Press", stackIncrementKg: 10),
          MachineOption(id: cybex, displayName: "Cybex Leg Press"),
        ],
        others: [MachineOption(id: panatta, displayName: "Panatta Leg Press")],
        selected: selected,
        unit: .kilograms,
        onSelect: { selected = $0 },
        onAddMachine: {}
      )
    }
  }

  #Preview("Machine picker") {
    NavigationStack {
      MachinePickerHarness().navigationTitle("Machine")
    }
  }
#endif
