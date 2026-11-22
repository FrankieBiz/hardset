import HardsetCore
import HardsetStore
import HardsetUI
import SwiftUI

/// The movement library, wired.
///
/// Reads every movement the Library lists, groups it by body part through `LibraryIndex`, and opens
/// the movement editor to tag the lifter's own movements, including the ones a workout import
/// created, or add a new one. Until the first read lands
/// it says it is reading rather than claiming the library is empty, and a failed read says so
/// instead of drawing an empty library: neither is a statement about the lifter's movements the app
/// could check. A failed save keeps the editor up with everything typed and says why in an alert.
@MainActor
public struct LibraryScreen: View {
  @State private var snapshot = SnapshotLoader<[CatalogEntry]>()
  @State private var editor: LibraryEditorTarget?
  @State private var saveError: String?
  /// Bumped to re-read after a save.
  @State private var reloadToken = 0

  private let catalog: CatalogSeeder
  private let onChanged: () -> Void

  /// - Parameter onChanged: Called after a movement is saved. A body part or equipment given here
  ///   changes what Progress and Volume read, which neither can see from this screen.
  public init(catalog: CatalogSeeder, onChanged: @escaping () -> Void = {}) {
    self.catalog = catalog
    self.onChanged = onChanged
  }

  public var body: some View {
    Group {
      if snapshot.loadFailed {
        // Scrollable so the pull-to-refresh the message promises actually works.
        ScrollView {
          HardsetEmptyState(
            title: "Could not read your movements",
            detail: "Your logged sets are safe. Pull down to try again.",
            systemImage: "exclamationmark.triangle"
          )
          .padding(.top, Tokens.Spacing.section)
        }
      } else if let entries = snapshot.value {
        LibraryView(
          sections: LibraryIndex.sections(entries),
          counts: LibraryIndex.counts(entries),
          onSelect: { editor = .editing($0) }
        )
      } else {
        HardsetLoadingState("Reading your movements…")
      }
    }
    .background(Tokens.Color.canvas)
    .hardsetNavigationTitle("Library")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          editor = .creating
        } label: {
          Image(systemName: "plus")
        }
        .accessibilityLabel("New movement")
        .disabled(snapshot.value == nil)
      }
    }
    .task(id: reloadToken) { await load() }
    .refreshable { await load() }
    .sheet(item: $editor, onDismiss: { saveError = nil }) { target in
      MovementEditorSheet(
        title: target.title,
        errorMessage: $saveError,
        draft: target.draft,
        onSave: { name, attribution in save(target, name: name, attribution: attribution) },
        onCancel: { editor = nil }
      )
      .hardsetSheet()
    }
  }

  private func load() async {
    let catalog = catalog
    await snapshot.load { try catalog.libraryExercises() }
  }

  private func save(_ target: LibraryEditorTarget, name: String, attribution: CustomAttribution) {
    do {
      switch target {
      case .creating:
        // Refused by the store, not returned: an existing movement of the same name handed back
        // would close the editor as if the lifter's choice had been saved.
        _ = try catalog.createNewCustomExercise(named: name, attribution: attribution)
      case .editing(let entry):
        _ = try catalog.updateCustomExercise(entry.id, name: name, attribution: attribution)
      }
      saveError = nil
      editor = nil
      reloadToken &+= 1
      onChanged()
    } catch CatalogSeederError.duplicateName {
      saveError = MovementEditorDraft.nameTakenMessage(name)
    } catch CatalogSeederError.curatedNotEditable {
      saveError = "This movement comes with the app, so its muscles cannot be changed."
    } catch CatalogSeederError.importedNotRenamable {
      saveError = "An imported movement keeps the name it was imported under. Its body part and equipment can still be set."
    } catch CatalogSeederError.blankName {
      saveError = "Type the movement's name first."
    } catch {
      saveError = "“\(name)” could not be saved. Try again."
    }
  }
}

/// What the library's editor is open on: a new movement, or one the lifter is retagging.
///
/// `nonisolated` so its computed `id` satisfies `Identifiable` without isolated-conformance
/// inference, as `ReceiptSelection` does.
private nonisolated enum LibraryEditorTarget: Identifiable {
  case creating
  case editing(CatalogEntry)

  var id: String {
    switch self {
    case .creating: "new"
    case .editing(let entry): entry.id.rawValue.uuidString
    }
  }

  var title: String {
    switch self {
    case .creating: "New movement"
    case .editing(let entry): entry.isImported ? "Imported movement" : "Movement"
    }
  }

  var draft: MovementEditorDraft {
    switch self {
    case .creating: MovementEditorDraft()
    case .editing(let entry): MovementEditorDraft(entry: entry)
    }
  }
}
