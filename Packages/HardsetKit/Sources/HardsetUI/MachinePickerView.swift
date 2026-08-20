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
/// The differentiator's entry point, and the place it most easily dies. Per-machine progression is
/// worthless if recording the machine costs the lifter thought mid-workout, so the design is
/// recency-first: the machines this movement was actually performed on, most recent at the top,
/// because that is overwhelmingly the one they are standing at. The common case is one tap on the
/// first row, or no tap at all if it is already selected.
///
/// Everything else is deliberately below that: the rest of the gym's machines, then adding one.
/// "Not recorded" stays available and unpenalised — a lifter who does not care must not be nagged,
/// and a set with no machine is still a real set.
public struct MachinePickerView: View {
  private let recent: [MachineOption]
  private let others: [MachineOption]
  private let selected: MachineID?
  private let onSelect: (MachineID?) -> Void
  private let onAddMachine: (() -> Void)?

  public init(
    recent: [MachineOption],
    others: [MachineOption] = [],
    selected: MachineID?,
    onSelect: @escaping (MachineID?) -> Void,
    onAddMachine: (() -> Void)? = nil
  ) {
    self.recent = recent
    self.others = others
    self.selected = selected
    self.onSelect = onSelect
    self.onAddMachine = onAddMachine
  }

  public var body: some View {
    List {
      if !recent.isEmpty {
        Section {
          ForEach(recent) { row(for: $0) }
        } header: {
          Text("You've used these")
        } footer: {
          Text("Most recent first. Loads are tracked per machine, so the same weight on different equipment stays separate.")
        }
      }

      if !others.isEmpty {
        Section("Also at this gym") {
          ForEach(others) { row(for: $0) }
        }
      }

      Section {
        // Never a penalty state. A set with no machine is still a real set; it just cannot
        // contribute to a per-machine trend.
        Button {
          onSelect(nil)
        } label: {
          HStack {
            Text("Not recorded")
              .foregroundStyle(Tokens.Color.textSecondary)
            Spacer()
            if selected == nil {
              Image(systemName: "checkmark")
                .foregroundStyle(Tokens.Color.accent)
            }
          }
          .frame(minHeight: Tokens.minimumTapTarget)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        if let onAddMachine {
          Button(action: onAddMachine) {
            Label("Add a machine", systemImage: "plus")
              .frame(minHeight: Tokens.minimumTapTarget)
          }
          .buttonStyle(.plain)
          .foregroundStyle(Tokens.Color.accent)
        }
      }
    }
  }

  private func row(for option: MachineOption) -> some View {
    Button {
      onSelect(option.id)
    } label: {
      HStack(spacing: Tokens.Spacing.snug) {
        VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
          Text(option.displayName)
            .foregroundStyle(Tokens.Color.textPrimary)
          if let increment = option.stackIncrementKg {
            // Stated because it constrains what a progression suggestion may propose.
            Text("moves in \(Self.format(increment)) kg steps")
              .font(Tokens.Text.caption)
              .foregroundStyle(Tokens.Color.textSecondary)
          }
        }
        Spacer(minLength: 0)
        if selected == option.id {
          Image(systemName: "checkmark")
            .foregroundStyle(Tokens.Color.accent)
        }
      }
      // Larger than the app-wide minimum: this is inside the logging path.
      .frame(minHeight: Tokens.loggerTapTarget)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(
      selected == option.id ? "\(option.displayName), selected" : option.displayName
    )
  }

  static func format(_ value: Double) -> String {
    value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
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
