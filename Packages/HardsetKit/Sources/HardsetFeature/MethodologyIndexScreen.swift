import HardsetCore
import HardsetUI
import SwiftUI

/// Renders `MethodologyIndex`, and knows nothing else.
///
/// The list used to live here as a `static let`, under a comment claiming that
/// "`MethodologyIndexTests` fails if the count drifts". **No such test existed, and none could** —
/// this module has no test target, so the enforcement was a comment. The data moved to
/// `HardsetCore.MethodologyIndex`, where `MethodologyIndexTests` sweeps the source tree for
/// `EvidenceSource` declarations and fails when one is missing from the list.
///
/// This file is now a view, which is all it should ever have been.
@MainActor
public struct MethodologyIndexScreen: View {
  @State private var showing: EvidenceSource?

  public init() {}

  public var body: some View {
    List {
      Section {
        Text(MethodologyIndex.preamble)
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.textSecondary)
      }

      ForEach(MethodologyIndex.sections) { section in
        Section(section.title) {
          ForEach(section.sources) { source in
            Button {
              showing = source
            } label: {
              VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
                Text(source.title)
                  .font(Tokens.Text.label)
                  .foregroundStyle(Tokens.Color.textPrimary)
                if source.citation != nil {
                  Text("Cited")
                    .font(Tokens.Text.caption)
                    .foregroundStyle(Tokens.Color.textSecondary)
                }
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
    .navigationTitle("How the numbers work")
    .sheet(item: $showing) { source in
      MethodologySheet(source: source)
    }
  }
}

#if DEBUG
  #Preview("Methodology index") {
    NavigationStack { MethodologyIndexScreen() }
      .preferredColorScheme(.dark)
  }
#endif
