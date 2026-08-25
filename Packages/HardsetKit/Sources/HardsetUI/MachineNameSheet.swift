import HardsetCore
import SwiftUI

/// Naming a machine, with the names you have already used offered back.
///
/// # Why suggestions
///
/// The same machine at a second gym was retyped from scratch every time, and "Hammer Strength
/// Iso-Lateral Row" is not a name anyone retypes identically. A near miss does not fail loudly — it
/// silently creates a third machine with a third empty history, and because invariant #10 forbids
/// merging two machines there is no way back from it.
///
/// # Why it must say what it is doing
///
/// This feature is one word away from reading as "merge my machines", which is the one thing the
/// app must never do. So picking a name used at *another* gym states plainly that a new machine is
/// being created and that its loads start empty. Picking a name that is already at *this* gym
/// resolves to that machine instead — the caller's job, and the reason `existingHere` travels with
/// each suggestion rather than just the string.
public struct MachineNameSheet: View {
  private let title: String
  private let suggestions: [MachineNameSuggestionRow]
  private let onConfirm: (String) -> Void
  private let onCancel: () -> Void

  @State private var name: String = ""
  @FocusState private var isNameFocused: Bool

  /// A name already used, and where. Mirrors the store's suggestion type so this view stays free
  /// of storage, the same way `MachineOption` does for the picker.
  public struct MachineNameSuggestionRow: Hashable, Sendable, Identifiable {
    public let name: String
    /// True when a machine of this name is already at the gym being added to.
    public let isAlreadyHere: Bool
    public let otherGymNames: [String]

    public var id: String { name }

    public init(name: String, isAlreadyHere: Bool, otherGymNames: [String]) {
      self.name = name
      self.isAlreadyHere = isAlreadyHere
      self.otherGymNames = otherGymNames
    }
  }

  public init(
    title: String = "Add a machine",
    suggestions: [MachineNameSuggestionRow] = [],
    onConfirm: @escaping (String) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.title = title
    self.suggestions = suggestions
    self.onConfirm = onConfirm
    self.onCancel = onCancel
  }

  private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

  /// Suggestions matching what has been typed so far. Everything, while the field is empty.
  private var matching: [MachineNameSuggestionRow] {
    guard !trimmed.isEmpty else { return suggestions }
    return suggestions.filter {
      $0.name.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
  }

  /// The suggestion the typed text names exactly, if any. Drives the disclosure.
  private var exactMatch: MachineNameSuggestionRow? {
    suggestions.first { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
  }

  public var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Name or brand", text: $name)
            .focused($isNameFocused)
            .submitLabel(.done)
            // Autocorrect off for the same reason the movement sheet turns it off: these are
            // proper nouns -- Panatta, Hammer Strength, Cybex, Nautilus -- and autocorrect
            // rewrote "Panatta chest press" to "Panama chest press".
            .autocorrectionDisabled()
            #if os(iOS)
              .textInputAutocapitalization(.words)
            #endif
        } header: {
          Text("Machine")
        } footer: {
          Text(disclosure)
        }

        if !matching.isEmpty {
          Section {
            ForEach(matching) { suggestion in
              Button {
                name = suggestion.name
              } label: {
                VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
                  Text(suggestion.name)
                    .foregroundStyle(Tokens.Color.textPrimary)
                  Text(Self.provenance(suggestion))
                    .font(Tokens.Text.caption)
                    .foregroundStyle(Tokens.Color.textSecondary)
                }
                .frame(minHeight: Tokens.minimumTapTarget)
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .accessibilityElement(children: .combine)
              .accessibilityLabel("\(suggestion.name), \(Self.provenance(suggestion))")
            }
          } header: {
            Text("Names you have used")
          }
        }
      }
      .navigationTitle(title)
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: onCancel)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Add") { onConfirm(trimmed) }
            .disabled(trimmed.isEmpty)
        }
      }
      .onAppear { isNameFocused = true }
    }
  }

  /// What is about to happen, in the lifter's terms.
  ///
  /// Three distinct outcomes and each is stated, because the difference between them is a history
  /// that continues and a history that starts empty.
  private var disclosure: String {
    guard let match = exactMatch else {
      return "Whatever you would recognise it by \u{2014} the brand, or \u{201C}the one by the window\u{201D}."
    }
    if match.isAlreadyHere {
      return "You already have this one here. Its loads carry on where you left off."
    }
    let others = Self.list(match.otherGymNames)
    return
      "A new machine at this gym. Its loads start empty \u{2014} they are not shared with the one at "
      + "\(others), because two machines are never the same machine."
  }

  static func provenance(_ suggestion: MachineNameSuggestionRow) -> String {
    if suggestion.isAlreadyHere { return "Already at this gym" }
    guard !suggestion.otherGymNames.isEmpty else { return "Used before" }
    return "At \(list(suggestion.otherGymNames))"
  }

  /// "A", "A and B", "A, B and C".
  static func list(_ names: [String]) -> String {
    switch names.count {
    case 0: "another gym"
    case 1: names[0]
    case 2: "\(names[0]) and \(names[1])"
    default: names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
    }
  }
}

#if DEBUG
  #Preview("Machine name") {
    MachineNameSheet(
      suggestions: [
        .init(name: "Hammer Strength Iso-Lateral Row", isAlreadyHere: true, otherGymNames: []),
        .init(name: "Cybex Leg Press", isAlreadyHere: false, otherGymNames: ["PureGym Holloway"]),
      ],
      onConfirm: { _ in },
      onCancel: {}
    )
  }
#endif
