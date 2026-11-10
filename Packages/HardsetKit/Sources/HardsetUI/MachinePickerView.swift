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
///
/// A failed read or save appears as an error banner above every choice, as in the gym picker, so
/// an unreadable gym is never presented as a gym with no machines.
public struct MachinePickerView: View {
  private let recent: [MachineOption]
  private let others: [MachineOption]
  private let selected: MachineID?
  private let unit: WeightUnit
  private let errorMessage: String?
  private let onSelect: (MachineID?) -> Void
  private let onEditIncrement: ((MachineID) -> Void)?
  private let onAddMachine: (() -> Void)?
  private let onArchive: ((MachineID) -> Void)?
  private let onCancel: (() -> Void)?

  /// The machine waiting for the lifter to confirm it should leave this gym's list.
  @State private var archiveCandidate: MachineOption?

  /// - Parameters:
  ///   - errorMessage: A failed read or save, in the lifter's words, shown as an error banner.
  ///     "Not recorded" stays selectable under it, so a failure never blocks logging.
  ///   - onArchive: Takes a machine off this gym's list after the lifter confirms. Offered from
  ///     a long press and as a VoiceOver action, never for the machine currently selected.
  ///   - onCancel: Closes the picker without choosing. When set, the picker draws "Cancel" in the
  ///     toolbar's cancellation position, so the caller should not draw its own.
  public init(
    recent: [MachineOption],
    others: [MachineOption] = [],
    selected: MachineID?,
    unit: WeightUnit = .kilograms,
    errorMessage: String? = nil,
    onSelect: @escaping (MachineID?) -> Void,
    onAddMachine: (() -> Void)? = nil,
    onEditIncrement: ((MachineID) -> Void)? = nil,
    onArchive: ((MachineID) -> Void)? = nil,
    onCancel: (() -> Void)? = nil
  ) {
    self.recent = recent
    self.others = others
    self.selected = selected
    self.unit = unit
    self.errorMessage = errorMessage
    self.onSelect = onSelect
    self.onEditIncrement = onEditIncrement
    self.onAddMachine = onAddMachine
    self.onArchive = onArchive
    self.onCancel = onCancel
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Tokens.Spacing.section) {
        VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
          if let visibleErrorMessage {
            HardsetBanner(.error, message: visibleErrorMessage)
          }

          Text("Loads are tracked per machine, so weight on different equipment stays separate.")
            .font(Tokens.Text.label)
            .foregroundStyle(Tokens.Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        if let hero = recent.first {
          VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
            SectionLabel("Used last time")
            heroCard(hero)
          }
        } else if others.isEmpty, visibleErrorMessage == nil {
          // True whether the gym has no machines yet or its list could not be read, which is why
          // it does not claim either. Left out under an error banner, which already says which.
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

        // Only for a machine on the list: the caller edits the step of a listed option, so for a
        // machine the list does not hold (after a failed read) the button would do nothing.
        if let selected, let onEditIncrement, isListed(selected) {
          Button("Set this machine’s load step") { onEditIncrement(selected) }
            .buttonStyle(HardsetButtonStyle(.secondary, size: .logger))
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
    .pickerCancelAction(onCancel)
    // Asked once, because nothing in the app brings an archived machine back to the list.
    .confirmationDialog(
      archiveTitle,
      isPresented: isConfirmingArchive,
      titleVisibility: .visible,
      presenting: archiveCandidate
    ) { option in
      Button("Archive", role: .destructive) { onArchive?(option.id) }
      Button("Cancel", role: .cancel) {}
    } message: { _ in
      Text("It leaves this gym’s list. Sets already logged on it stay in your history.")
    }
  }

  private var visibleErrorMessage: String? {
    guard let errorMessage else { return nil }
    let trimmed = errorMessage.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private func isListed(_ id: MachineID) -> Bool {
    recent.contains { $0.id == id } || others.contains { $0.id == id }
  }

  // MARK: - Archive

  private var isConfirmingArchive: Binding<Bool> {
    Binding(get: { archiveCandidate != nil }, set: { if !$0 { archiveCandidate = nil } })
  }

  private var archiveTitle: String {
    guard let archiveCandidate else { return "Archive this machine?" }
    return "Archive \(archiveCandidate.displayName)?"
  }

  /// Not for the selected machine: the movement is being logged on it right now, and taking it
  /// off the list would leave a selection the picker could no longer show.
  private func canArchive(_ option: MachineOption) -> Bool {
    onArchive != nil && selected != option.id
  }

  /// A long press, and the same action for VoiceOver, so archiving is reachable without putting a
  /// destructive control on every row of a screen used one-handed between sets.
  private func offeringArchive(_ row: some View, for option: MachineOption) -> some View {
    row
      .contextMenu {
        if canArchive(option) {
          Button("Archive machine", systemImage: "archivebox", role: .destructive) {
            archiveCandidate = option
          }
        }
      }
      .accessibilityActions {
        if canArchive(option) {
          Button("Archive machine") { archiveCandidate = option }
        }
      }
  }

  // MARK: - Hero card

  /// The machine used last time, as the largest target on the screen.
  ///
  /// Name in the title role and the stack step in the lifter's unit beneath it. Selected uses the
  /// same accent ring, tint and check as every other choice, only bigger.
  private func heroCard(_ hero: MachineOption) -> some View {
    offeringArchive(heroButton(hero), for: hero)
  }

  private func heroButton(_ hero: MachineOption) -> some View {
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
        offeringArchive(
          SelectionRow(
            title: option.displayName,
            subtitle: option.stackIncrementKg.map { Self.formatStep($0, unit: unit) },
            isSelected: selected == option.id,
            action: { onSelect(option.id) }
          ),
          for: option
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
    let errorMessage: String?
    @State private var selected: MachineID? = nil
    private let hammer = MachineID()
    private let cybex = MachineID()
    private let panatta = MachineID()

    init(unit: WeightUnit = .kilograms, isEmpty: Bool = false, errorMessage: String? = nil) {
      self.unit = unit
      self.isEmpty = isEmpty
      self.errorMessage = errorMessage
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
          errorMessage: errorMessage,
          onSelect: { selected = $0 },
          onAddMachine: {},
          onArchive: { _ in },
          onCancel: {}
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

  #Preview("Machine picker, read failed") {
    // The banner says the list could not be read; "Not recorded" stays selectable beneath it.
    MachinePickerHarness(
      isEmpty: true,
      errorMessage: "This gym’s machines could not be read. You can still log without one."
    )
  }
#endif
