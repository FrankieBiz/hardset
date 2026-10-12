import HardsetCore
import HardsetStore
import HardsetUI
import SwiftUI

/// The sheet that chooses where the next workout is. Selection is a binding; adding a gym and
/// dismissing are the root's, passed in, so the store calls stay in one place.
struct GymPickerSheet: View {
  let gyms: [GymRecord]
  @Binding var selected: GymID?
  /// Why the last gym write failed, in the user's words.
  let error: String?
  let onAddGym: (String) -> Void
  let onDone: () -> Void
  @State private var isAddingGym = false

  var body: some View {
    NavigationStack {
      List {
        Section {
          ForEach(gyms) { gym in
            Button {
              selected = gym.id
              onDone()
            } label: {
              HStack {
                Text(gym.name).foregroundStyle(Tokens.Color.textPrimary)
                Spacer()
                if selected == gym.id {
                  Image(systemName: "checkmark").foregroundStyle(Tokens.Color.accent)
                }
              }
              .frame(minHeight: Tokens.minimumTapTarget)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
        } footer: {
          if let error {
            Text(error).foregroundStyle(Tokens.Color.critical)
          } else {
            Text("Loads are tracked per machine, and machines belong to a gym.")
          }
        }

        Section {
          Button {
            // Not recorded stays available: someone training at home or travelling should not be
            // made to invent a gym to log a set.
            selected = nil
            onDone()
          } label: {
            HStack {
              Text("Not recorded").foregroundStyle(Tokens.Color.textSecondary)
              Spacer()
              if selected == nil {
                Image(systemName: "checkmark").foregroundStyle(Tokens.Color.accent)
              }
            }
            .frame(minHeight: Tokens.minimumTapTarget)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)

          Button { isAddingGym = true } label: {
            Label("Add a gym", systemImage: "plus")
              .frame(minHeight: Tokens.minimumTapTarget)
          }
          .buttonStyle(.plain)
          .foregroundStyle(Tokens.Color.accent)
        }
      }
      .navigationTitle("Where are you training?")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { onDone() }
        }
      }
      // Attached INSIDE the gym sheet on purpose. Two `.sheet` modifiers on the same anchor means
      // the second one silently never presents: "Add a gym" was a button that did nothing.
      .sheet(isPresented: $isAddingGym) {
        NameEntrySheet(
          title: "Add a gym",
          prompt: "Name",
          footnote: "Machines are recorded per gym, so this is what groups them.",
          onConfirm: { name in
            isAddingGym = false
            onAddGym(name)
          },
          onCancel: { isAddingGym = false }
        )
      }
    }
  }
}
