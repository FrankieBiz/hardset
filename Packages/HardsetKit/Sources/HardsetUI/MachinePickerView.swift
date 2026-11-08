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
/// at the top, reachable in a single tap on the gym floor, because it is almost always the one
/// they are standing at. Other recent machines and the rest of the gym follow as 56 pt selection
/// rows under sentence-case labels. "Not recorded" stays a real choice, and adding a machine is a
/// plainly styled action rather than a row pretending to be one.
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
      VStack(alignment: .leading, spacing: Tokens.Spacing.section) {
        Text("Loads are tracked per machine, so weight on different equipment stays separate.")
          .font(Tokens.Text.label)
          .foregroundStyle(Tokens.Color.textSecondary)
          .fixedSize(horizontal: false, vertical: true)

        if let hero = recent.first {
          VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
            SectionLabel("Used last time")
            heroCard(hero)
          }
        } else if others.isEmpty {
          // True whether the gym has no machines yet or its list could not be read, which is why
          // it does not claim either.
          Text("No machines to show for this gym.")
            .font(Tokens.Text.label)
            .foregroundStyle(Tokens.Color.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
        }

        if recent.count > 1 {
          machineSection("Other recent machines", options: Array(recent.dropFirst()))
        }

        if !others.isEmpty {
          machineSection("Also at this gym", options: others)
        }

        VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
          SectionLabel("Not on the list")

          SelectionRow(
            title: "Not recorded",
            subtitle: "History is kept for the movement, not a machine",
            leadingIcon: "slash.circle",
            isSelected: selected == nil,
            action: { onSelect(nil) }
          )

          if let onAddMachine {
            Button(action: onAddMachine) {
              Label {
                Text("Add a machine")
              } icon: {
                Image(systemName: "plus")
                  .foregroundStyle(Tokens.Color.accent)
              }
            }
            .buttonStyle(HardsetButtonStyle(.secondary, size: .logger))
            .padding(.top, Tokens.Spacing.tight)
          }
        }
      }
      .padding(.horizontal, Tokens.Spacing.loose)
      .padding(.top, Tokens.Spacing.regular)
      .padding(.bottom, Tokens.Spacing.section)
    }
    .background(Tokens.Color.background)
  }

  // MARK: - Hero card

  /// The machine used last time, as the largest target on the screen.
  ///
  /// Name in the title role and the stack step in the lifter's unit beneath it. Selected uses the
  /// same accent ring, tint and check as every other choice, only bigger.
  private func heroCard(_ hero: MachineOption) -> some View {
    let isSelected = selected == hero.id
    return Button {
      onSelect(hero.id)
    } label: {
      HStack(alignment: .center, spacing: Tokens.Spacing.regular) {
        VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
          Text(hero.displayName)
            .font(Tokens.Text.title)
            .foregroundStyle(Tokens.Color.textPrimary)

          if let increment = hero.stackIncrementKg {
            Text(Self.formatStep(increment, unit: unit))
              .font(Tokens.Text.provenance.monospacedDigit())
              .foregroundStyle(Tokens.Color.textSecondary)
          }
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)

        SelectionIndicator(isSelected: isSelected)
      }
      .padding(Tokens.Spacing.loose)
      // Inside the label, so the frame and the tappable shape are the same rectangle.
      .frame(
        maxWidth: .infinity,
        minHeight: Tokens.loggerTapTarget + Tokens.Spacing.section,
        alignment: .leading
      )
      .contentShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
    }
    .buttonStyle(SelectionCardButtonStyle(isSelected: isSelected, cornerRadius: Tokens.Radius.card))
    .accessibilityElement(children: .combine)
    .accessibilityLabel(spokenLabel(for: hero, prefix: "Used last time"))
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
  }

  // MARK: - Lists

  private func machineSection(_ title: String, options: [MachineOption]) -> some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      SectionLabel(title, count: options.count)

      ForEach(options) { option in
        SelectionRow(
          title: option.displayName,
          subtitle: option.stackIncrementKg.map { Self.formatStep($0, unit: unit) },
          isSelected: selected == option.id,
          action: { onSelect(option.id) }
        )
      }
    }
  }

  /// The selected state is spoken by the `.isSelected` trait, so it is not repeated here.
  private func spokenLabel(for option: MachineOption, prefix: String? = nil) -> String {
    var parts: [String] = []
    if let prefix { parts.append(prefix) }
    parts.append(option.displayName)
    if let increment = option.stackIncrementKg {
      parts.append(Self.formatStep(increment, unit: unit))
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
    let unit: WeightUnit
    let isEmpty: Bool
    @State private var selected: MachineID? = nil
    private let hammer = MachineID()
    private let cybex = MachineID()
    private let panatta = MachineID()

    init(unit: WeightUnit = .kilograms, isEmpty: Bool = false) {
      self.unit = unit
      self.isEmpty = isEmpty
    }

    var body: some View {
      NavigationStack {
        MachinePickerView(
          recent: isEmpty
            ? []
            : [
              MachineOption(id: hammer, displayName: "Hammer Strength Leg Press", stackIncrementKg: 10),
              MachineOption(id: cybex, displayName: "Cybex Leg Press", stackIncrementKg: 4.5),
            ],
          others: isEmpty ? [] : [MachineOption(id: panatta, displayName: "Panatta Leg Press")],
          selected: selected,
          unit: unit,
          onSelect: { selected = $0 },
          onAddMachine: {}
        )
        .hardsetNavigationTitle("Machine")
      }
    }
  }

  #Preview("Machine picker") {
    MachinePickerHarness()
  }

  #Preview("Machine picker, pounds") {
    MachinePickerHarness(unit: .pounds)
  }

  #Preview("Machine picker, no machines") {
    MachinePickerHarness(isEmpty: true)
  }
#endif
